//
//  NetworkRuleInterceptorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkRuleStubResponderTests: XCTestCase {

    private let url = URL(string: "https://api.example.com/v1/users")!

    func testMockProducesTheConfiguredStatusHeadersAndBody() throws {
        let bodyID = UUID()
        let mock = MockResponse(
            statusCode: 201,
            headers: ["Content-Type": "application/json"],
            bodyID: bodyID,
            delay: 0
        )
        let result = try XCTUnwrap(
            NetworkRuleStubResponder.response(for: .mock(mock), url: url) { id in
                id == bodyID ? Data("{\"id\":1}".utf8) : nil
            }
        )
        XCTAssertEqual(result.0.statusCode, 201)
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(result.1, Data("{\"id\":1}".utf8))
    }

    func testMockWithoutABodyProducesEmptyData() throws {
        let mock = MockResponse(statusCode: 204, headers: [:], bodyID: nil, delay: 0)
        let result = try XCTUnwrap(NetworkRuleStubResponder.response(for: .mock(mock), url: url) { _ in nil })
        XCTAssertEqual(result.0.statusCode, 204)
        XCTAssertTrue(result.1.isEmpty)
    }

    func testMapLocalReadsTheFileAndSetsContentType() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: file)

        let map = MapLocalFile(
            relativePath: file.path,
            statusCode: 200,
            contentType: "application/json",
            delay: 0
        )
        let result = try XCTUnwrap(NetworkRuleStubResponder.response(for: .mapLocal(map), url: url) { _ in nil })
        XCTAssertEqual(result.0.statusCode, 200)
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(result.1, Data("[]".utf8))
    }

    func testMapLocalReturnsNilWhenTheFileIsMissing() {
        let map = MapLocalFile(relativePath: "/nope/missing.json", statusCode: 200, contentType: nil, delay: 0)
        XCTAssertNil(NetworkRuleStubResponder.response(for: .mapLocal(map), url: url) { _ in nil })
    }
}

@MainActor
final class NetworkRuleInterceptorTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var bodyDirectory: URL!

    override func setUpWithError() throws {
        suiteName = "NetworkRuleInterceptorTests.\(UUID().uuidString)"
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// A store over this test's throwaway suite and body directory, already publishing to
    /// ``NetworkRuleSnapshot`` — which is what the interceptor actually reads.
    private func makeStore() throws -> NetworkRuleStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
        Scyther.start()
        return store
    }

    /// Restores the snapshot so a rule cannot leak into a later test in the suite.
    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    private func perform(_ url: String) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPInterceptorURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: URL(string: url)!)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testAMatchedMockIsServedWithoutTheNetwork() async throws {
        let store = try makeStore()
        let bodyID = store.storeBody(Data("{\"mocked\":true}".utf8))
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 418, headers: ["X-Mock": "yes"], bodyID: bodyID, delay: 0))
        ))

        // The host does not resolve; only a stub can answer it.
        let (data, response) = try await perform("https://unreachable.invalid/cart")
        XCTAssertEqual(response.statusCode, 418)
        XCTAssertEqual(response.value(forHTTPHeaderField: "X-Mock"), "yes")
        XCTAssertEqual(data, Data("{\"mocked\":true}".utf8))
    }

    func testAFailureConditionSurfacesTheConfiguredError() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "offline",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .condition(NetworkCondition(
                latency: 0,
                bandwidthKBps: nil,
                failureRate: 1,
                failureCode: URLError.Code.notConnectedToInternet.rawValue
            ))
        ))

        do {
            _ = try await perform("https://unreachable.invalid/x")
            XCTFail("expected the rule to fail the request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testLatencyDelaysTheStub() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "slow",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0.4))
        ))
        let start = Date()
        _ = try await perform("https://unreachable.invalid/slow")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)
    }

    func testTheMasterSwitchDisablesEverything() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        ))
        store.isEnabled = false

        do {
            _ = try await perform("https://unreachable.invalid/cart")
            XCTFail("with rules off the request should reach the network and fail to resolve")
        } catch {
            XCTAssertNotNil(error as? URLError)
        }
    }
}
