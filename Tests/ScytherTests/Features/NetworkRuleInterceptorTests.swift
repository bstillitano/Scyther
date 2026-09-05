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

    /// The contract on ``NetworkHeaderRewrite/apply(to:)``: sets apply first, removals second, so
    /// a key in both ends up removed rather than quietly kept. A rewrite the engine merged never
    /// names a key in both — it settles that per header, in rule order — so this is the rule for a
    /// rewrite built by hand, as one registered from code may be.
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
        let bodyID = try store.storeBody(Data("{\"mocked\":true}".utf8))
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 418, headers: ["X-Mock": "yes"], bodyID: bodyID, delay: 0)))
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
            actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["Authorization": "Bearer rewritten"],
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

    /// Deliberately **not** `.notConnectedToInternet`, which is what the default is and also what a
    /// real attempt to reach `unreachable.invalid` produces on a machine with no network — so the
    /// old assertion passed with the whole feature removed. `.badServerResponse` can only have
    /// come from the condition: nothing answered, so nothing could have answered badly.
    func testAFailureConditionSurfacesTheConfiguredError() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "offline",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(condition: NetworkCondition(
                latency: 0,
                bandwidthKBps: nil,
                failureRate: 1,
                failureCode: URLError.Code.badServerResponse.rawValue
            ))
        ))

        do {
            _ = try await perform("https://unreachable.invalid/x")
            XCTFail("expected the rule to fail the request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse,
                           "the configured code, not whatever the network would have said")
        }
    }

    func testLatencyDelaysTheStub() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "slow",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0.4)))
        ))
        let start = Date()
        _ = try await perform("https://unreachable.invalid/slow")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)
    }

    /// The log's Overrides row names what shaped the request, which is now a larger set than the
    /// override that served the response: a condition applies to a stub, and a rewrite still
    /// shapes the request the log describes even though nothing goes on the wire.
    func testEveryOverrideThatAppliedIsCredited() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "rewrite",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["X-Rewritten": "yes"], remove: []))
        ))
        store.add(NetworkRule(
            id: UUID(),
            name: "slow",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(condition: NetworkCondition(latency: 0.2, bandwidthKBps: nil, failureRate: 0))
        ))
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
        ))

        let url = "https://unreachable.invalid/credited"
        let (_, response) = try await perform(url)
        XCTAssertEqual(response.statusCode, 200, "the mock is what answered")

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        XCTAssertEqual(
            logged.appliedRuleNames,
            ["cart", "rewrite", "slow"],
            "the stub first, then everything else that still applied to it"
        )
        let headers = try XCTUnwrap(logged.requestHeaders)
        XCTAssertEqual(headers["X-Rewritten"] as? String, "yes",
                       "a rewrite has no wire effect on a stub, but the log still shows it")
    }

    /// One override carrying both a stub and a condition is credited once, not twice.
    func testAnOverrideThatBothStubsAndConditionsIsNamedOnce() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "slow cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)),
                condition: NetworkCondition(latency: 0.2, bandwidthKBps: nil, failureRate: 0)
            )
        ))

        let url = "https://unreachable.invalid/once"
        _ = try await perform(url)
        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        XCTAssertEqual(logged.appliedRuleNames, ["slow cart"])
    }

    /// "Mock this endpoint and make it slow" — the combination that used to be inert.
    func testAConditionDelaysAStubbedResponse() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "slow cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)),
                condition: NetworkCondition(latency: 0.5, bandwidthKBps: nil, failureRate: 0)
            )
        ))

        let start = Date()
        let (_, response) = try await perform("https://unreachable.invalid/slow-mock")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.5,
                                    "the condition's latency reaches the stub, not just the network")
    }

    /// A failure rate takes out a stubbed request too, so an endpoint can be mocked and flaky.
    func testAFailureConditionFailsAStubbedResponse() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "flaky cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)),
                condition: NetworkCondition(latency: 0,
                                            bandwidthKBps: nil,
                                            failureRate: 1,
                                            failureCode: URLError.Code.timedOut.rawValue)
            )
        ))

        do {
            _ = try await perform("https://unreachable.invalid/flaky-mock")
            XCTFail("expected the condition to fail the stubbed request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    /// A bandwidth ceiling paces a synthetic body, which means the response takes at least as long
    /// as the ceiling implies. One kilobyte at one kilobyte per second is a second.
    func testABandwidthCeilingPacesAStubbedBody() async throws {
        let store = try makeStore()
        let bodyID = try store.storeBody(Data(repeating: UInt8(ascii: "x"), count: 32 * 1024))
        store.add(NetworkRule(
            id: UUID(),
            name: "throttled cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)),
                condition: NetworkCondition(latency: 0, bandwidthKBps: 32, failureRate: 0)
            )
        ))

        let start = Date()
        let (data, response) = try await perform("https://unreachable.invalid/throttled-mock")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data.count, 32 * 1024, "every byte still arrives, just later")
        XCTAssertGreaterThanOrEqual(elapsed, 0.5,
                                    "32 KB at 32 KB/s cannot be delivered instantly")
    }

    /// The whole reason a picked file is copied: the override still serves it after the document
    /// it came from has gone away, and after the store has been rebuilt as it is on a relaunch.
    func testACopiedMapLocalFileIsStillServedAfterAReload() async throws {
        let store = try makeStore()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let picked = directory.appendingPathComponent("users.json")
        try Data("[1,2,3]".utf8).write(to: picked)

        let path = try XCTUnwrap(store.storeFile(at: picked))
        try FileManager.default.removeItem(at: picked)

        store.add(NetworkRule(
            id: UUID(),
            name: "users",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(stub: .mapLocal(MapLocalFile(
                relativePath: path,
                fileName: "users.json",
                statusCode: 200,
                contentType: "application/json"
            )))
        ))

        // A relaunch: a fresh store over the same preferences and directory, republishing what it
        // finds there.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reloaded = NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
        XCTAssertEqual(reloaded.rules.map(\.name), ["users"])

        let (data, response) = try await perform("https://unreachable.invalid/users")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(data, Data("[1,2,3]".utf8))
    }

    func testTheMasterSwitchDisablesEverything() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
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

/// Global conditioning, as the interceptor sees it.
///
/// Every assertion here is on which `URLError` comes back rather than on how long something took,
/// because a failure rate of one is deterministic and a stopwatch is not.
@MainActor
final class NetworkGlobalConditioningTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Scyther.start()
    }

    override func tearDown() {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        NetworkRuleSnapshot.update(globalCondition: nil)
        super.tearDown()
    }

    private func perform(_ url: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPInterceptorURLProtocol.self]
        _ = try await URLSession(configuration: configuration).data(from: URL(string: url)!)
    }

    /// Fails a request and reports the error's code, or `nil` when it somehow succeeded.
    private func failureCode(for url: String) async -> URLError.Code? {
        do {
            try await perform(url)
            return nil
        } catch {
            return (error as? URLError)?.code
        }
    }

    func testGlobalConditioningAppliesWithNoOverridePresent() async {
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0, bandwidthKBps: nil, failureRate: 1, failureCode: URLError.Code.timedOut.rawValue
        ))

        let code = await failureCode(for: "https://unreachable.invalid/global")
        XCTAssertEqual(code, .timedOut, "the whole app is conditioned, override or not")
    }

    /// The global condition is a floor a matching override replaces, not something it adds to.
    func testAMatchingOverridesConditionBeatsTheGlobalOne() async {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(name: "targeted",
                        match: .host("unreachable.invalid"),
                        actions: NetworkRuleActions(condition: NetworkCondition(
                            latency: 0,
                            bandwidthKBps: nil,
                            failureRate: 1,
                            failureCode: URLError.Code.networkConnectionLost.rawValue
                        )))
        ])
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0, bandwidthKBps: nil, failureRate: 1, failureCode: URLError.Code.timedOut.rawValue
        ))

        let code = await failureCode(for: "https://unreachable.invalid/targeted")
        XCTAssertEqual(code, .networkConnectionLost, "the override replaces the global condition")
    }

    /// An override that matches but carries no condition leaves the global one in place.
    func testAnOverrideWithoutAConditionDoesNotDisplaceTheGlobalOne() async {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(name: "rewrite",
                        match: .host("unreachable.invalid"),
                        actions: NetworkRuleActions(
                            rewriteHeaders: NetworkHeaderRewrite(set: ["X-Test": "yes"])
                        ))
        ])
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0, bandwidthKBps: nil, failureRate: 1, failureCode: URLError.Code.timedOut.rawValue
        ))

        let code = await failureCode(for: "https://unreachable.invalid/rewritten")
        XCTAssertEqual(code, .timedOut)
    }

    /// Global conditioning has its own switch, so the overrides' master switch does not reach it.
    func testTheOverridesMasterSwitchDoesNotSuspendGlobalConditioning() async {
        NetworkRuleSnapshot.update(isEnabled: false, rules: [])
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0, bandwidthKBps: nil, failureRate: 1, failureCode: URLError.Code.timedOut.rawValue
        ))

        let code = await failureCode(for: "https://unreachable.invalid/switched-off")
        XCTAssertEqual(code, .timedOut)
    }

    /// A stubbed request is conditioned by the global setting too — the stub is what a request
    /// with no network would otherwise have no way of being slowed down or failed.
    func testGlobalConditioningReachesAStubbedRequest() async {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(name: "cart",
                        match: .host("unreachable.invalid"),
                        actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200))))
        ])
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0, bandwidthKBps: nil, failureRate: 1, failureCode: URLError.Code.timedOut.rawValue
        ))

        let code = await failureCode(for: "https://unreachable.invalid/stubbed-global")
        XCTAssertEqual(code, .timedOut)
    }
}

/// Drives `HTTPInterceptorURLProtocol`'s data-delegate callbacks directly, which is the only way
/// to observe the bandwidth ceiling: a stubbed response never creates a data task, and a real one
/// needs a server.
final class NetworkRuleBandwidthTests: XCTestCase {

    /// Stands in for the URL loading system, recording what the interceptor forwards and when.
    private final class RecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Int = 0
        private var marks: [UInt8] = []
        private var events: [String] = []

        /// Bytes handed to the client so far.
        var forwardedByteCount: Int { lock.withLock { bytes } }

        /// The first byte of each chunk forwarded, in the order the client saw them.
        var chunkMarks: [UInt8] { lock.withLock { marks } }

        /// The callbacks received so far, in order.
        var received: [String] { lock.withLock { events } }

        func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
            lock.withLock {
                bytes += data.count
                events.append("data")
                if let first = data.first { marks.append(first) }
            }
        }

        func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
            lock.withLock { events.append("response") }
        }

        func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
            lock.withLock { events.append("finished") }
        }

        func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
            lock.withLock { events.append("failed") }
        }

        func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { }
        func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { }
    }

    private let url = URL(string: "https://api.example.com/v1/large")!

    /// Everything one driven response needs: the interceptor under test, the client recording what
    /// it forwarded, and the session and task the delegate callbacks are addressed from.
    private struct Harness {
        let interceptor: HTTPInterceptorURLProtocol
        let client: RecordingClient
        let session: URLSession
        let task: URLSessionDataTask
        let response: HTTPURLResponse
    }

    private func harness(condition: NetworkCondition?) -> Harness {
        let client = RecordingClient()
        let request = URLRequest(url: url)
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.condition = condition
        let session = URLSession(configuration: .ephemeral)
        return Harness(
            interceptor: interceptor,
            client: client,
            session: session,
            task: session.dataTask(with: request),
            response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    /// Spins the run loop until `condition` holds, rather than sleeping a fixed amount and hoping.
    ///
    /// - Returns: Whether it held before `timeout` elapsed.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// The bytes forwarded and the wall-clock time taken to forward all of them, delivering
    /// `chunks` chunks of `chunkSize` bytes through the data delegate under `condition`.
    ///
    /// A paced response is now delivered asynchronously, so this waits for the last byte to reach
    /// the client rather than assuming it has by the time the callbacks return.
    private func deliver(chunks: Int,
                         chunkSize: Int,
                         condition: NetworkCondition?) -> (bytes: Int, elapsed: TimeInterval) {
        let harness = harness(condition: condition)
        let expected = chunks * chunkSize

        let start = Date()
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        let chunk = Data(count: chunkSize)
        for _ in 0..<chunks {
            harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: chunk)
        }
        waitUntil { harness.client.forwardedByteCount >= expected }
        return (harness.client.forwardedByteCount, Date().timeIntervalSince(start))
    }

    /// The regression: CFNetwork delivers a body in chunks smaller than a second's worth of any
    /// realistic ceiling, so a per-delivery budget throttles nothing at all.
    func testAChunkedResponseIsPacedAcrossDeliveries() {
        // 512 KB at 512 KB/s should take about a second, in eight deliveries none of which is
        // anywhere near a second's worth on its own.
        let throttled = deliver(chunks: 8,
                                chunkSize: 64 * 1024,
                                condition: NetworkCondition(latency: 0, bandwidthKBps: 512, failureRate: 0))

        XCTAssertEqual(throttled.bytes, 8 * 64 * 1024, "every byte is still forwarded, just later")
        XCTAssertGreaterThan(throttled.elapsed, 0.7,
                             "eight 64 KB deliveries under a 512 KB/s ceiling must take about a second")
        XCTAssertLessThan(throttled.elapsed, 5, "and must not overshoot the ceiling either")
    }

    func testTheSameResponseIsNotDelayedWithoutACeiling() {
        let unthrottled = deliver(chunks: 8, chunkSize: 64 * 1024, condition: nil)
        XCTAssertEqual(unthrottled.bytes, 8 * 64 * 1024)
        XCTAssertLessThan(unthrottled.elapsed, 0.3, "an unconditioned response is forwarded as it arrives")
    }

    /// A condition with latency but no ceiling must not throttle the body either — the latency is
    /// applied once, in `startLoading()`.
    func testAConditionWithoutACeilingDoesNotPaceTheBody() {
        let result = deliver(chunks: 8,
                             chunkSize: 64 * 1024,
                             condition: NetworkCondition(latency: 2, bandwidthKBps: nil, failureRate: 0))
        XCTAssertEqual(result.bytes, 8 * 64 * 1024)
        XCTAssertLessThan(result.elapsed, 0.3)
    }

    /// The pacing used to be a `Thread.sleep` taken on the session's own delegate queue — the same
    /// queue the answer to `getTasksWithCompletionHandler` is delivered on, so a cancellation sat
    /// behind up to 30 seconds of it while the socket kept transferring. The callback returns at
    /// once now, and the wait is scheduled.
    func testAPacedDeliveryDoesNotHoldTheDeliveringThread() {
        // 64 KB at 1 KB/s is over a minute of pacing, clamped to the 30-second budget.
        let harness = harness(condition: NetworkCondition(latency: 0, bandwidthKBps: 1, failureRate: 0))

        let start = Date()
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: Data(count: 64 * 1024))
        let returned = Date().timeIntervalSince(start)

        harness.interceptor.stopLoading()

        XCTAssertLessThan(returned, 1, "the wait must not be taken on the thread the bytes arrived on")
        XCTAssertEqual(harness.client.forwardedByteCount, 0, "and the bytes must not be forwarded early either")
    }

    /// Scheduling instead of sleeping is only correct if the order survives it. Each chunk carries
    /// a distinct first byte, so a reordering or a duplicate would show.
    func testEveryPacedChunkIsForwardedOnceAndInOrder() {
        let harness = harness(condition: NetworkCondition(latency: 0, bandwidthKBps: 32, failureRate: 0))

        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        let marks: [UInt8] = Array(0..<8)
        for mark in marks {
            var chunk = Data(repeating: mark, count: 8 * 1024)
            chunk[0] = mark
            harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: chunk)
        }

        XCTAssertTrue(waitUntil { harness.client.chunkMarks.count == marks.count },
                      "every chunk is forwarded eventually")
        XCTAssertEqual(harness.client.chunkMarks, marks, "in the order the session delivered them, once each")
    }

    /// The task finishes as soon as the last bytes are off the socket, which is well before the
    /// ceiling has finished handing them to the client. Reporting the load finished at that point
    /// would have the client believe a body it had not yet received was complete.
    func testTheLoadFinishesOnlyAfterThePacedBytesAreForwarded() {
        let harness = harness(condition: NetworkCondition(latency: 0, bandwidthKBps: 32, failureRate: 0))

        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        for _ in 0..<4 {
            harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: Data(count: 8 * 1024))
        }
        harness.interceptor.urlSession(harness.session, task: harness.task, didCompleteWithError: nil)

        XCTAssertTrue(waitUntil { harness.client.received.last == "finished" })
        XCTAssertEqual(harness.client.received, ["response", "data", "data", "data", "data", "finished"])
    }

    /// The budget used to be rebuilt on every `didReceive response:`, so a
    /// `multipart/x-mixed-replace` response restarted it once per part and the per-request bound
    /// was no bound at all. The clock restarts with each part; the budget does not.
    func testThePacingBudgetIsSpentAcrossTheRequestNotResetPerPart() {
        let harness = harness(condition: NetworkCondition(latency: 0, bandwidthKBps: 1, failureRate: 0))
        harness.interceptor.maximumBandwidthSleep = 0.4

        // Part one: 64 KB at 1 KB/s wants far more pacing than the budget allows, so it spends it.
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: Data(count: 64 * 1024))
        XCTAssertTrue(waitUntil { harness.client.forwardedByteCount >= 64 * 1024 })

        // Part two, down the same request, wanting just as much.
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: harness.response) { _ in }
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: Data(count: 64 * 1024))
        XCTAssertTrue(waitUntil { harness.client.forwardedByteCount >= 128 * 1024 })

        XCTAssertEqual(harness.interceptor.pacingAsked, 0.4, accuracy: 0.001,
                       "one budget for the request, not one per part of the response")
    }
}

/// A rule's latency and a mock's delay used to be slept for on the thread `startLoading()` was
/// called on — a thread the URL loading system owns, and possibly shares with requests that match
/// no override at all. These drive `startLoading()` directly, because that thread is the subject.
final class NetworkRuleDelayTests: XCTestCase {

    /// Records what the interceptor delivered, and when it finished.
    private final class RecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        /// Called on whichever thread finished the load.
        var onFinish: (@Sendable () -> Void)?

        /// Called from inside `urlProtocol(_:didReceive:cacheStoragePolicy:)`, which is a place
        /// the URL loading system is entitled to cancel from.
        var onResponse: (@Sendable () -> Void)?

        /// The callbacks received so far, in order.
        var received: [String] { lock.withLock { events } }

        private func record(_ event: String) {
            lock.withLock { events.append(event) }
        }

        func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
            record("response")
            onResponse?()
        }
        func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
            record("data")
        }
        func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
            record("finished")
            onFinish?()
        }
        func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
            record("failed")
            onFinish?()
        }
        func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { }
        func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { }
    }

    private let url = URL(string: "https://delayed.invalid/profile")!

    override func tearDown() {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
    }

    /// Publishes one mock rule with the given delay and returns an interceptor wired to `client`.
    private func interceptor(mockDelay: TimeInterval, client: RecordingClient) -> HTTPInterceptorURLProtocol {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(
                id: UUID(),
                name: "delayed",
                isEnabled: true,
                match: .host("delayed.invalid"),
                actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: mockDelay)))
            )
        ])
        return HTTPInterceptorURLProtocol(request: URLRequest(url: url), cachedResponse: nil, client: client)
    }

    func testStartLoadingReturnsWithoutWaitingOutAMockDelay() {
        let client = RecordingClient()
        let delivered = expectation(description: "the stub is delivered")
        client.onFinish = { delivered.fulfill() }
        let interceptor = interceptor(mockDelay: 1, client: client)

        let start = Date()
        interceptor.startLoading()
        let returned = Date().timeIntervalSince(start)

        XCTAssertLessThan(returned, 0.2, "startLoading must not hold the thread the URL loading system gave it")
        XCTAssertTrue(client.received.isEmpty, "and must not have answered yet either")

        wait(for: [delivered], timeout: 10)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 1,
                                    "the delay is still honoured, just not by occupying a thread")
        XCTAssertEqual(client.received, ["response", "data", "finished"])
    }

    /// The same for a condition's latency, which delays a request that really does go out.
    func testStartLoadingReturnsWithoutWaitingOutAConditionLatency() {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(
                id: UUID(),
                name: "slow",
                isEnabled: true,
                match: .host("unreachable.invalid"),
                actions: NetworkRuleActions(condition: NetworkCondition(latency: 1, bandwidthKBps: nil, failureRate: 0))
            )
        ])
        let client = RecordingClient()
        let finished = expectation(description: "the request completes")
        client.onFinish = { finished.fulfill() }
        let request = URLRequest(url: URL(string: "https://unreachable.invalid/latency")!)
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)

        let start = Date()
        interceptor.startLoading()

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2,
                          "a second of latency must not be a second of somebody else's thread")

        // The host does not resolve, so the load fails — after the latency, which is the point.
        wait(for: [finished], timeout: 30)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 1)
    }

    /// The common path — nothing delayed — keeps the ordering it has always had.
    func testAnUndelayedMockIsStillServedInline() {
        let client = RecordingClient()
        let interceptor = interceptor(mockDelay: 0, client: client)

        interceptor.startLoading()

        XCTAssertEqual(client.received, ["response", "data", "finished"])
    }

    func testCancellingDuringTheDelayDeliversNothing() {
        let client = RecordingClient()
        let interceptor = interceptor(mockDelay: 0.4, client: client)

        interceptor.startLoading()
        interceptor.stopLoading()

        let waited = expectation(description: "the delay elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { waited.fulfill() }
        wait(for: [waited], timeout: 5)

        XCTAssertTrue(client.received.isEmpty, "a cancelled request must deliver nothing at all")
    }

    /// Publishes one condition rule with the given latency and failure rate, and returns an
    /// interceptor wired to `client`.
    ///
    /// The host does not resolve, so a request that really starts fails instead of hanging — which
    /// is what makes "a task was started" observable without a server to talk to.
    private func interceptor(latency: TimeInterval,
                             failureRate: Double = 0,
                             client: RecordingClient) -> HTTPInterceptorURLProtocol {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            NetworkRule(
                id: UUID(),
                name: "slow",
                isEnabled: true,
                match: .host("unreachable.invalid"),
                actions: NetworkRuleActions(condition: NetworkCondition(latency: latency,
                                                    bandwidthKBps: nil,
                                                    failureRate: failureRate))
            )
        ])
        let request = URLRequest(url: URL(string: "https://unreachable.invalid/latency")!)
        return HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
    }

    /// `URLSession` holds its delegate until it is invalidated, and this instance holds the
    /// session, so every intercepted request used to leak the protocol instance, the session, its
    /// operation queue, the logged model and an `NSMutableData` holding the whole response body.
    func testACompletedRequestReleasesTheInterceptor() {
        weak var leaked: HTTPInterceptorURLProtocol?
        let finished = expectation(description: "the request completes")

        autoreleasepool {
            let client = RecordingClient()
            client.onFinish = { finished.fulfill() }
            let interceptor = interceptor(latency: 0, client: client)
            leaked = interceptor
            interceptor.startLoading()
            wait(for: [finished], timeout: 30)
        }

        // The session releases its delegate once the invalidation has drained, which happens on
        // the session's own queue. Poll rather than sleep a fixed amount and hope.
        let deadline = Date().addingTimeInterval(10)
        while leaked != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertNil(leaked, "the session was never invalidated, so it still holds its delegate")
    }

    /// The same for a cancelled request, which never reaches `didCompleteWithError`'s invalidation.
    func testACancelledRequestReleasesTheInterceptor() {
        weak var leaked: HTTPInterceptorURLProtocol?

        autoreleasepool {
            let interceptor = interceptor(latency: 0, client: RecordingClient())
            leaked = interceptor
            interceptor.startLoading()
            interceptor.stopLoading()
        }

        let deadline = Date().addingTimeInterval(10)
        while leaked != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertNil(leaked, "cancelling must invalidate the session it started")
    }

    /// A client may cancel from inside the response callback. `serve()` checked cancellation once,
    /// on the way in, and then made two more client calls regardless — which the `URLProtocol`
    /// contract forbids.
    func testCancellingFromInsideTheResponseCallbackStopsTheStub() {
        let client = RecordingClient()
        let interceptor = interceptor(mockDelay: 0, client: client)
        client.onResponse = { [weak interceptor] in interceptor?.stopLoading() }

        interceptor.startLoading()

        XCTAssertEqual(client.received, ["response"],
                       "nothing is delivered to a client that has been told to stop")
    }

    /// The delay queue used to be serial, and the block it runs is not merely a wait: serving a
    /// stub hands three callbacks to the client and writes the bodies to the log. One slow mock
    /// therefore held up every other override's delay behind it.
    ///
    /// Written without a timing margin. The first mock's delay is shorter, so it is scheduled
    /// first for certain; it then occupies its block until told to let go. On a serial queue the
    /// second mock can never be delivered and the expectation times out.
    func testOneDelayedMockDoesNotHoldUpAnother() {
        /// Two rules, so the two interceptors can be given different delays from one snapshot.
        func mock(host: String, delay: TimeInterval) -> NetworkRule {
            NetworkRule(
                id: UUID(),
                name: host,
                isEnabled: true,
                match: .host(host),
                actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: delay)))
            )
        }
        NetworkRuleSnapshot.update(isEnabled: true, rules: [
            mock(host: "blocking.invalid", delay: 0.05),
            mock(host: "waiting.invalid", delay: 0.2)
        ])

        func interceptor(host: String, client: RecordingClient) -> HTTPInterceptorURLProtocol {
            let request = URLRequest(url: URL(string: "https://\(host)/thing")!)
            return HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        }

        let release = DispatchSemaphore(value: 0)
        let occupied = expectation(description: "the first mock is occupying the delay queue")
        let delivered = expectation(description: "the second mock is delivered anyway")

        let blockingClient = RecordingClient()
        blockingClient.onResponse = {
            occupied.fulfill()
            release.wait()
        }
        let blocking = interceptor(host: "blocking.invalid", client: blockingClient)

        let waitingClient = RecordingClient()
        waitingClient.onFinish = { delivered.fulfill() }
        let waiting = interceptor(host: "waiting.invalid", client: waitingClient)

        blocking.startLoading()
        waiting.startLoading()

        wait(for: [occupied], timeout: 5)
        defer { release.signal() }
        wait(for: [delivered], timeout: 5)

        XCTAssertEqual(waitingClient.received, ["response", "data", "finished"])
    }

    /// A draw of a fixed value that counts how many times it was asked for.
    private final class CountingRandomSource: @unchecked Sendable {
        private let lock = NSLock()
        private let value: Double
        private var draws: Int = 0

        init(_ value: Double) { self.value = value }

        /// How many draws the interceptor made.
        var drawCount: Int { lock.withLock { draws } }

        func next() -> Double {
            lock.withLock { draws += 1 }
            return value
        }
    }

    /// A degraded link is slow before it is flaky. The roll used to happen at `startLoading()`, so
    /// a condition of three seconds' latency and a 30% failure rate failed 30% of requests at
    /// t = 0 rather than after the wait.
    func testTheFailureIsRolledAfterTheLatencyRatherThanBeforeIt() {
        let client = RecordingClient()
        let failed = expectation(description: "the request fails")
        client.onFinish = { failed.fulfill() }
        let interceptor = interceptor(latency: 0.4, failureRate: 1, client: client)

        let start = Date()
        interceptor.startLoading()

        XCTAssertTrue(client.received.isEmpty, "the latency has not elapsed, so nothing has been rolled yet")

        wait(for: [failed], timeout: 5)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4,
                                    "the failure arrives after the wait, as a degraded link would deliver it")
        XCTAssertEqual(client.received, ["failed"])
        XCTAssertFalse(interceptor.hasStartedTask, "a failed request never reaches the network")
    }

    /// A rate of `1` means every request, with no draw to escape through. The comparison used to
    /// be `Double.random(in: 0...1) < 1`, which a draw of exactly `1` walks straight past.
    func testAFailureRateOfOneFailsWithoutDrawingAtAll() {
        let client = RecordingClient()
        let interceptor = interceptor(latency: 0, failureRate: 1, client: client)
        let source = CountingRandomSource(1)
        interceptor.randomSource = { source.next() }

        interceptor.startLoading()

        XCTAssertEqual(client.received, ["failed"])
        XCTAssertFalse(interceptor.hasStartedTask)
        XCTAssertEqual(source.drawCount, 0, "there is nothing to decide, so nothing is drawn")
    }

    /// A rate of `0` is likewise decided without a draw, and lets the request through.
    func testAFailureRateOfZeroProceedsWithoutDrawingAtAll() {
        let client = RecordingClient()
        let interceptor = interceptor(latency: 0, failureRate: 0, client: client)
        let source = CountingRandomSource(0)
        interceptor.randomSource = { source.next() }

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask)
        XCTAssertEqual(source.drawCount, 0)
    }

    /// One draw per request — not one per chunk, and not one per matching rule — compared strictly
    /// against the rate, so a draw equal to the rate proceeds.
    func testAFractionalRateDrawsOnceAndComparesStrictly() {
        let proceeding = RecordingClient()
        let onTheBoundary = interceptor(latency: 0, failureRate: 0.5, client: proceeding)
        let boundarySource = CountingRandomSource(0.5)
        onTheBoundary.randomSource = { boundarySource.next() }

        onTheBoundary.startLoading()

        XCTAssertTrue(onTheBoundary.hasStartedTask, "a draw equal to the rate is not below it")
        XCTAssertEqual(boundarySource.drawCount, 1, "exactly one draw decides the whole request")

        let failing = RecordingClient()
        let belowTheBoundary = interceptor(latency: 0, failureRate: 0.5, client: failing)
        let lowSource = CountingRandomSource(0.4999)
        belowTheBoundary.randomSource = { lowSource.next() }

        belowTheBoundary.startLoading()

        XCTAssertEqual(failing.received, ["failed"])
        XCTAssertFalse(belowTheBoundary.hasStartedTask)
        XCTAssertEqual(lowSource.drawCount, 1)
    }

    /// A mock's delay is answered from the interceptor; a condition's latency starts a real task.
    /// Cancelling while that latency is still counting down must leave no task started at all —
    /// otherwise the request the app abandoned goes out anyway, and by then nothing can cancel it.
    func testCancellingDuringALatencyDelayStartsNoTask() {
        let client = RecordingClient()
        let interceptor = interceptor(latency: 0.4, client: client)

        interceptor.startLoading()
        interceptor.stopLoading()

        let waited = expectation(description: "the latency elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { waited.fulfill() }
        wait(for: [waited], timeout: 5)

        XCTAssertFalse(interceptor.hasStartedTask, "a cancelled request must never reach the network")
        XCTAssertTrue(client.received.isEmpty, "and must deliver nothing to a client that has gone away")
    }

    /// The other half of the contract: a delayed request nobody cancelled still starts, and starts
    /// exactly one task. Two would mean two sessions — the failure an unsynchronised `lazy var`
    /// allows — and would show up here as a second terminal callback.
    func testADelayedRequestThatIsNotCancelledStartsExactlyOneTask() {
        let client = RecordingClient()
        let finished = expectation(description: "the request completes")
        client.onFinish = { finished.fulfill() }
        let interceptor = interceptor(latency: 0.5, client: client)

        interceptor.startLoading()
        XCTAssertFalse(interceptor.hasStartedTask, "the task waits out the latency rather than starting now")

        wait(for: [finished], timeout: 30)
        XCTAssertTrue(interceptor.hasStartedTask, "and starts once the latency has elapsed")
        XCTAssertEqual(client.received, ["failed"], "one task, so exactly one terminal callback")
    }

    /// The guard itself, with no timing in it. Cancellation and task creation are decided together
    /// inside the interceptor, so a request already cancelled starts nothing even on the inline
    /// path a zero delay takes.
    ///
    /// The URL loading system does not call `stopLoading()` before `startLoading()`. This is the
    /// interleaving the lock exists to make impossible, written as the one ordering a test can
    /// actually pin down: the real race between the delay queue and the cancelling thread cannot
    /// be forced deterministically, and a test that tried would pass on luck.
    func testAnAlreadyCancelledRequestStartsNothingOnTheInlinePath() {
        let client = RecordingClient()
        let interceptor = interceptor(latency: 0, client: client)

        interceptor.stopLoading()
        interceptor.startLoading()

        XCTAssertFalse(interceptor.hasStartedTask, "the cancellation is seen before anything is started")
        XCTAssertTrue(client.received.isEmpty)
    }
}
