//
//  ScytherOriginatedRequestTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// The marker itself: what it recognises, and what it refuses to recognise.
///
/// The refusal is the point. If the mark were a header, or a `Bool` under a known key, the host
/// app could opt its own traffic out of the developer's own breakpoints by setting it — silently,
/// and with no way of telling from the log that it had happened.
final class ScytherOriginatedRequestMarkerTests: XCTestCase {

    private let url = URL(string: "https://api.ipify.org/?format=json")!

    func testAMarkedRequestIsRecognised() {
        XCTAssertTrue(ScytherOriginatedRequest.identifies(ScytherOriginatedRequest.marked(URLRequest(url: url))))
    }

    func testAnOrdinaryRequestIsNot() {
        XCTAssertFalse(ScytherOriginatedRequest.identifies(URLRequest(url: url)))
    }

    /// The interceptor copies a request at least three times on its way out — the rewrite copy,
    /// the breakpoint rebuild, the redirect copy — so a marker that did not survive `mutableCopy()`
    /// would protect nothing past the first of them.
    func testTheMarkSurvivesCopyingTheRequest() throws {
        let marked = ScytherOriginatedRequest.marked(URLRequest(url: url))
        let copy = try XCTUnwrap((marked as NSURLRequest).mutableCopy() as? NSMutableURLRequest)
        XCTAssertTrue(ScytherOriginatedRequest.identifies(copy as URLRequest))
    }

    /// An app that guessed the property key still cannot forge the mark, because the value is a
    /// token minted for this process and never published.
    func testAForgedValueUnderTheSameKeyIsNotHonoured() throws {
        let forged = try XCTUnwrap((URLRequest(url: url) as NSURLRequest).mutableCopy() as? NSMutableURLRequest)
        URLProtocol.setProperty(true, forKey: scytherOriginatedRequestKey, in: forged)
        XCTAssertFalse(ScytherOriginatedRequest.identifies(forged as URLRequest))

        URLProtocol.setProperty("Scyther_Originated_Request", forKey: scytherOriginatedRequestKey, in: forged)
        XCTAssertFalse(ScytherOriginatedRequest.identifies(forged as URLRequest))
    }
}

/// Scyther's own traffic reaches the log but reaches none of the interception features.
///
/// The bug this suite pins down: the menu's IP lookup was held by a breakpoint on
/// `api.ipify.org`, the held-request editor was presented over the menu, the presentation
/// re-created the menu, and the menu asked for the IP address again — one modal per second,
/// stacking without limit, over the one screen that could have switched the breakpoint off.
///
/// Held, stubbed, conditioned and rewritten are tested separately rather than as one "is exempt"
/// assertion, because they are four independent paths through `startLoading()` and a fix that
/// covered three of them would look like a fix.
///
/// `@MainActor` because ``NetworkRuleStore`` is, exactly as the override suite is.
@MainActor
final class ScytherOriginatedInterceptionTests: XCTestCase {

    /// Records what the interceptor forwarded, so a test can tell "went to the network" from
    /// "was answered without it".
    private final class RecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        /// The callbacks received, in order.
        var received: [String] { lock.withLock { events } }

        func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
            lock.withLock { events.append("data") }
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

    /// The host never resolves, so a request that really goes out fails rather than hanging —
    /// which is what makes "it reached the network" observable without a server to talk to.
    private let host = "unreachable.invalid"

    /// How the URL loading system reports a real attempt at a host that does not resolve.
    ///
    /// Which of them arrives depends on the machine's resolver and whether it has a network at
    /// all, so the conditioning tests accept any of the three. What they will not accept is the
    /// condition's own `.badServerResponse`, or no error at all.
    private static let networkFailureCodes: Set<URLError.Code> = [
        .cannotFindHost,
        .notConnectedToInternet,
        .cannotConnectToHost
    ]

    nonisolated(unsafe) private var coordinator: BreakpointCoordinator!
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var bodyDirectory: URL!
    nonisolated(unsafe) private var wasStarted = false

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    override func setUpWithError() throws {
        coordinator = BreakpointCoordinator()
        suiteName = "ScytherOriginatedInterceptionTests.\(UUID().uuidString)"
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        wasStarted = Scyther.isStarted
        Scyther._started = true
        BreakpointSnapshot.setEnabledDuringTests(true)
    }

    override func tearDownWithError() throws {
        BreakpointSnapshot.setEnabledDuringTests(false)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: [])
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        NetworkRuleSnapshot.update(globalCondition: nil)
        Scyther._started = wasStarted
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
        coordinator = nil
    }

    /// A store over this test's throwaway suite, already publishing to ``NetworkRuleSnapshot``.
    private func makeStore() throws -> NetworkRuleStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
    }

    /// Spins the run loop until `condition` holds, rather than sleeping and hoping.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// The model the interceptor logged for a request, once the logger's `Task` has landed it.
    private func loggedRequest(matching url: String) async -> HTTPRequest? {
        for _ in 0..<300 {
            let match = await NetworkLogger.instance.items.first { $0.requestURL == url }
            if let match { return match }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    /// Sends `request` through the interceptor on a session of its own, and reports how it ended.
    private func perform(_ request: URLRequest) async -> Error? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPInterceptorURLProtocol.self]
        do {
            _ = try await URLSession(configuration: configuration).data(for: request)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Breakpoints

    /// The defect, at its narrowest: a breakpoint matching Scyther's own lookup held it.
    @MainActor
    func testAMarkedRequestIsNotHeldByAMatchingBreakpoint() throws {
        BreakpointSnapshot.update(isEnabled: true, breakpoints: [
            NetworkBreakpoint(id: UUID(),
                              name: "ip",
                              isEnabled: true,
                              match: .host(host),
                              stage: .both,
                              timeout: 60)
        ])

        let client = RecordingClient()
        let request = ScytherOriginatedRequest.marked(URLRequest(url: URL(string: "https://\(host)/?format=json")!))
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.breakpoints = coordinator
        interceptor.breakpointTimeoutOverride = 60

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask,
                      "Scyther's own request goes straight out; nothing may hold the menu's own lookup")
        XCTAssertTrue(coordinator.pending.isEmpty,
                      "and no editor is presented for it, which is what stacked one modal per second")

        interceptor.stopLoading()
    }

    /// The control: the same breakpoint, the same URL, an unmarked request. Without this the test
    /// above would pass just as well if breakpoints had stopped working altogether.
    @MainActor
    func testAnUnmarkedRequestIsStillHeldByTheSameBreakpoint() throws {
        BreakpointSnapshot.update(isEnabled: true, breakpoints: [
            NetworkBreakpoint(id: UUID(),
                              name: "ip",
                              isEnabled: true,
                              match: .host(host),
                              stage: .both,
                              timeout: 60)
        ])

        let client = RecordingClient()
        let request = URLRequest(url: URL(string: "https://\(host)/?format=json")!)
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.breakpoints = coordinator
        interceptor.breakpointTimeoutOverride = 60

        interceptor.startLoading()

        XCTAssertTrue(waitUntil { !self.coordinator.pending.isEmpty }, "app traffic is still held")
        XCTAssertFalse(interceptor.hasStartedTask)

        interceptor.stopLoading()
    }

    // MARK: - Overrides

    /// A mock answering Scyther's own request would have made the menu show a number the
    /// developer typed into an override, presented as the device's IP address.
    func testAMarkedRequestIsNotStubbedButIsStillLogged() async throws {
        let store = try makeStore()
        let bodyID = try store.storeBody(Data("{\"ip\":\"1.2.3.4\"}".utf8))
        store.add(NetworkRule(
            id: UUID(),
            name: "fake ip",
            isEnabled: true,
            match: .host(host),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200,
                                                                 headers: [:],
                                                                 bodyID: bodyID,
                                                                 delay: 0)))
        ))

        let url = "https://\(host)/not-stubbed"
        let error = await perform(ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url)))))

        XCTAssertNotNil(error, "nothing answered it, because the host does not resolve — the mock did not")

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found, "Scyther's own traffic is still logged")
        XCTAssertFalse(logged.wasStubbed)
        XCTAssertTrue(logged.appliedRuleNames.isEmpty, "and is credited to no override, because none applied")
    }

    /// A rewrite would have put a header on a request the developer never wrote.
    func testAMarkedRequestIsNotRewritten() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "staging auth",
            isEnabled: true,
            match: .host(host),
            actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["X-Rewritten": "yes"],
                                                                            remove: []))
        ))

        let url = "https://\(host)/not-rewritten"
        _ = await perform(ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url)))))

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        let headers = try XCTUnwrap(logged.requestHeaders)
        XCTAssertNil(headers["X-Rewritten"])
        XCTAssertTrue(logged.appliedRuleNames.isEmpty)
    }

    // MARK: - Conditioning

    /// `.badServerResponse` can only have come from the condition: nothing answered, so nothing
    /// could have answered badly. A real attempt at an unresolvable host reports something else.
    func testAMarkedRequestIsNotFailedByAMatchingCondition() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "offline",
            isEnabled: true,
            match: .host(host),
            actions: NetworkRuleActions(condition: NetworkCondition(
                latency: 0,
                bandwidthKBps: nil,
                failureRate: 1,
                failureCode: URLError.Code.badServerResponse.rawValue
            ))
        ))

        let url = "https://\(host)/not-conditioned"
        let error = await perform(ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url)))))

        /// Asserted positively. `XCTAssertNotEqual` on the code alone is satisfied by a `nil`
        /// error too, so on a machine whose resolver hijacks unknown hosts the test would hold
        /// while proving nothing. The request has to have really tried and really failed to
        /// resolve.
        let code = try XCTUnwrap((error as? URLError)?.code, "the request went to the network and failed there")
        XCTAssertTrue(Self.networkFailureCodes.contains(code),
                      "the override's failure must not take out Scyther's own request, but \(code) is not a real network failure either")
    }

    /// Global conditioning is a floor under every intercepted request. Scyther's own requests are
    /// the one thing it does not stand under: a developer who set the whole app to a lossy link
    /// did not ask for the menu itself to stop working.
    func testAMarkedRequestIgnoresGlobalConditioning() async throws {
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0,
            bandwidthKBps: nil,
            failureRate: 1,
            failureCode: URLError.Code.badServerResponse.rawValue
        ))

        let url = "https://\(host)/no-global-condition"
        let error = await perform(ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url)))))

        let code = try XCTUnwrap((error as? URLError)?.code, "the request went to the network and failed there")
        XCTAssertTrue(Self.networkFailureCodes.contains(code),
                      "the global floor must not take out Scyther's own request, but \(code) is not a real network failure either")
    }

    /// The control for both conditioning tests.
    func testAnUnmarkedRequestIsStillFailedByGlobalConditioning() async throws {
        NetworkRuleSnapshot.update(globalCondition: NetworkCondition(
            latency: 0,
            bandwidthKBps: nil,
            failureRate: 1,
            failureCode: URLError.Code.badServerResponse.rawValue
        ))

        let url = "https://\(host)/global-condition"
        let error = await perform(URLRequest(url: try XCTUnwrap(URL(string: url))))

        XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
    }

    // MARK: - Redirects

    /// The one place the mark does not survive on its own.
    ///
    /// Every other hop is a `mutableCopy()`, which carries protocol properties across; the
    /// redirect request is built by the URL loading system, and the internal marker is
    /// deliberately stripped there so the redirect is re-examined from scratch. Without the
    /// re-stamp a `301` on Scyther's own endpoint would land the follow-up in front of every
    /// breakpoint and override the original was exempt from.
    func testARedirectOfAScytherRequestStaysMarked() throws {
        let client = RedirectRecordingClient()
        let original = ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v1/ip"))))
        let interceptor = HTTPInterceptorURLProtocol(request: original, cachedResponse: nil, client: client)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(original.url), statusCode: 301, httpVersion: nil, headerFields: nil))

        let redirected = try XCTUnwrap((URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v2/ip"))) as NSURLRequest).mutableCopy() as? NSMutableURLRequest)
        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: redirected)

        var handed: URLRequest?
        interceptor.urlSession(session,
                               task: task,
                               willPerformHTTPRedirection: response,
                               newRequest: redirected as URLRequest) { handed = $0 }
        session.invalidateAndCancel()

        let forwarded = try XCTUnwrap(handed)
        XCTAssertTrue(ScytherOriginatedRequest.identifies(forwarded),
                      "the redirect of a request Scyther made is still a request Scyther made")
        XCTAssertNil(URLProtocol.property(forKey: internalNetworkRequestKey, in: forwarded),
                     "and is still re-examined from scratch, exactly as any other redirect is")
    }

    /// The mirror: an ordinary redirect must not pick the mark up.
    func testARedirectOfOrdinaryTrafficIsNotMarked() throws {
        let client = RedirectRecordingClient()
        let original = URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v1/users")))
        let interceptor = HTTPInterceptorURLProtocol(request: original, cachedResponse: nil, client: client)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(original.url), statusCode: 301, httpVersion: nil, headerFields: nil))
        let redirected = URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v2/users")))

        var handed: URLRequest?
        interceptor.urlSession(session,
                               task: task,
                               willPerformHTTPRedirection: response,
                               newRequest: redirected) { handed = $0 }
        session.invalidateAndCancel()

        XCTAssertFalse(ScytherOriginatedRequest.identifies(try XCTUnwrap(handed)))
    }

    /// The opt-in travels with the redirect too, so a replay sent with **Apply Request Overrides**
    /// on does not silently lose it at the first `302`.
    func testARedirectCarriesTheOverridesOptInWithIt() throws {
        let client = RedirectRecordingClient()
        let original = ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v1/cart"))),
                                                      applyingOverrides: true)
        let interceptor = HTTPInterceptorURLProtocol(request: original, cachedResponse: nil, client: client)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(original.url), statusCode: 302, httpVersion: nil, headerFields: nil))
        let redirected = URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v2/cart")))

        var handed: URLRequest?
        interceptor.urlSession(session,
                               task: task,
                               willPerformHTTPRedirection: response,
                               newRequest: redirected) { handed = $0 }
        session.invalidateAndCancel()

        XCTAssertTrue(ScytherOriginatedRequest.appliesOverrides(try XCTUnwrap(handed)))
    }

    // MARK: - The overrides opt-in

    /// The toggle's whole point: a replay sent with it on is answered by the mock, exactly as app
    /// traffic would be, and the log says so with the badge it already has.
    func testAnOptedInRequestIsStubbedAndCredited() async throws {
        let store = try makeStore()
        let bodyID = try store.storeBody(Data("{\"mocked\":true}".utf8))
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host(host),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 418,
                                                                 headers: [:],
                                                                 bodyID: bodyID,
                                                                 delay: 0)))
        ))

        let url = "https://\(host)/opted-in"
        let request = ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url))),
                                                      applyingOverrides: true)
        let error = await perform(request)
        XCTAssertNil(error, "the mock answered it, so nothing reached the unresolvable host")

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        XCTAssertTrue(logged.wasStubbed)
        XCTAssertEqual(logged.appliedRuleNames, ["cart"], "and the log credits the override, as it always has")
    }

    /// The half of the exemption the opt-in does **not** relax: a held replay would stall the
    /// editor that sent it.
    @MainActor
    func testAnOptedInRequestIsStillNotHeldByABreakpoint() throws {
        BreakpointSnapshot.update(isEnabled: true, breakpoints: [
            NetworkBreakpoint(id: UUID(),
                              name: "cart",
                              isEnabled: true,
                              match: .host(host),
                              stage: .both,
                              timeout: 60)
        ])

        let client = RecordingClient()
        let request = ScytherOriginatedRequest.marked(URLRequest(url: URL(string: "https://\(host)/opted-in-not-held")!),
                                                      applyingOverrides: true)
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.breakpoints = coordinator
        interceptor.breakpointTimeoutOverride = 60

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask)
        XCTAssertTrue(coordinator.pending.isEmpty)

        interceptor.stopLoading()
    }

    /// The other half the opt-in does not relax, and the reason it does not: the editor's promise
    /// is *this request, exactly as edited*. An override that only rewrites headers is not even
    /// credited, because it shaped nothing.
    func testAnOptedInRequestIsStillNotRewritten() async throws {
        let store = try makeStore()
        store.add(NetworkRule(
            id: UUID(),
            name: "staging auth",
            isEnabled: true,
            match: .host(host),
            actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["X-Rewritten": "yes"],
                                                                            remove: []))
        ))

        let url = "https://\(host)/opted-in-not-rewritten"
        let request = ScytherOriginatedRequest.marked(URLRequest(url: try XCTUnwrap(URL(string: url))),
                                                      applyingOverrides: true)
        _ = await perform(request)

        let found = await loggedRequest(matching: url)
        let logged = try XCTUnwrap(found)
        let headers = try XCTUnwrap(logged.requestHeaders)
        XCTAssertNil(headers["X-Rewritten"])
        XCTAssertTrue(logged.appliedRuleNames.isEmpty,
                      "a rewrite that was never applied must not be credited as though it had been")
    }
}

/// Records the redirect the interceptor forwarded to its client.
private final class RedirectRecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
    /// The request the client was told the load had been redirected to.
    private(set) var redirectedTo: URLRequest?

    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
        redirectedTo = request
    }

    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) { }
    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) { }
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) { }
    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) { }
    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { }
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { }
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { }
}
