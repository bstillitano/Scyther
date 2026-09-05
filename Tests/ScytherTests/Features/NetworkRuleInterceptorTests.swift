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

final class NetworkHeaderRewriteTests: XCTestCase {

    private func rewritten(_ rewrite: NetworkHeaderRewrite,
                           startingFrom existing: [String: String] = [:]) -> NSMutableURLRequest {
        let request = NSMutableURLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        existing.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        rewrite.apply(to: request)
        return request
    }

    func testAKeyOnlyInSetIsPresentWithItsValue() {
        let request = rewritten(NetworkHeaderRewrite(set: ["Authorization": "Bearer test"], remove: []))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
    }

    func testASetKeyReplacesAnExistingValue() {
        let request = rewritten(NetworkHeaderRewrite(set: ["Authorization": "Bearer new"], remove: []),
                                startingFrom: ["Authorization": "Bearer old"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testAKeyOnlyInRemoveIsGone() {
        let request = rewritten(NetworkHeaderRewrite(set: [:], remove: ["Authorization"]),
                                startingFrom: ["Authorization": "Bearer old"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    /// The contract on `RuleOutcome.headerRewrite`: sets apply first, removals second, so a key in
    /// both ends up removed rather than quietly kept.
    func testAKeyInBothSetAndRemoveIsRemoved() {
        let request = rewritten(NetworkHeaderRewrite(set: ["Authorization": "Bearer test"],
                                                     remove: ["Authorization"]))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    /// Guards the assumption removal rests on: passing `nil` really does delete the header rather
    /// than storing an empty value.
    func testSettingNilRemovesAHeaderFromAMutableRequest() {
        let request = NSMutableURLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        request.setValue("Bearer old", forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.allHTTPHeaderFields?["Authorization"])
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

    /// The model the interceptor logged for a request, once the logger's `Task` has landed it.
    ///
    /// The interceptor adds to ``NetworkLogger`` from a detached main-actor task, so the entry is
    /// not there the instant `perform(_:)` returns. Polls rather than sleeping a fixed amount, and
    /// matches on the request URL because the logger is shared across the whole test run.
    private func loggedRequest(matching url: String) async -> HTTPRequest? {
        for _ in 0..<200 {
            let match = await NetworkLogger.instance.items.first { $0.requestURL == url }
            if let match { return match }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
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
        let url = "https://unreachable.invalid/cart"
        let (data, response) = try await perform(url)
        XCTAssertEqual(response.statusCode, 418)
        XCTAssertEqual(response.value(forHTTPHeaderField: "X-Mock"), "yes")
        XCTAssertEqual(data, Data("{\"mocked\":true}".utf8))

        // A stubbed response is logged exactly as a real one is, and says where it came from.
        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        XCTAssertTrue(logged.wasStubbed)
        XCTAssertEqual(logged.appliedRuleNames, ["cart"])
        XCTAssertEqual(logged.responseCode, 418)
        XCTAssertFalse(logged.noResponse)
    }

    func testARewrittenHeaderIsWhatGetsLogged() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "staging auth",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .rewriteHeaders(NetworkHeaderRewrite(set: ["Authorization": "Bearer rewritten"],
                                                         remove: ["X-Original"]))
        ))

        // A rewrite does not stub, so this reaches the network and fails to resolve — but it is
        // still logged, which is the point: the log must describe the request as actually sent.
        let url = "https://unreachable.invalid/rewrite"
        var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        request.setValue("Bearer original", forHTTPHeaderField: "Authorization")
        request.setValue("please remove me", forHTTPHeaderField: "X-Original")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPInterceptorURLProtocol.self]
        _ = try? await URLSession(configuration: configuration).data(for: request)

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        let headers = try XCTUnwrap(logged.requestHeaders)
        XCTAssertEqual(headers["Authorization"] as? String, "Bearer rewritten")
        XCTAssertNil(headers["X-Original"])
        XCTAssertEqual(logged.appliedRuleNames, ["staging auth"])
        XCTAssertTrue(try XCTUnwrap(logged.requestCurl).contains("Bearer rewritten"))
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
