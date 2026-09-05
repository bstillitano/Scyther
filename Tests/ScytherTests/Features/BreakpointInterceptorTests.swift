//
//  BreakpointInterceptorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Drives `HTTPInterceptorURLProtocol` through a breakpoint, on its own coordinator.
///
/// The interceptor is driven directly rather than through a live `URLSession`, for the same
/// reason the override suite drives it directly: it is the only way to observe what
/// `startLoading()` hands the client, and when.
///
/// Every test opts this process into ``BreakpointSnapshot`` — which reports disabled inside a test
/// run — and opts back out in `tearDown`, so a breakpoint can never leak into the rest of the
/// suite.
final class BreakpointInterceptorTests: XCTestCase {

    /// Records what the interceptor forwarded, in order.
    private final class RecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var bytes = Data()
        private var status: Int?
        private var failure: URLError.Code?

        /// The callbacks received, in order.
        var received: [String] { lock.withLock { events } }

        /// Every byte forwarded to the client.
        var body: Data { lock.withLock { bytes } }

        /// The status code of the response the client was handed, if any.
        var statusCode: Int? { lock.withLock { status } }

        /// The error the load failed with, if it failed.
        var failureCode: URLError.Code? { lock.withLock { failure } }

        func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
            lock.withLock {
                events.append("data")
                bytes.append(data)
            }
        }

        func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
            lock.withLock {
                events.append("response")
                status = (response as? HTTPURLResponse)?.statusCode
            }
        }

        func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
            lock.withLock { events.append("finished") }
        }

        func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
            lock.withLock {
                events.append("failed")
                failure = (error as? URLError)?.code
            }
        }

        func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { }
        func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { }
    }

    /// The host never resolves, so a request that really starts fails instead of hanging — which
    /// is what makes "the request went out" observable without a server to talk to.
    private let url = URL(string: "https://unreachable.invalid/v1/users")!

    private var coordinator: BreakpointCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = BreakpointCoordinator()
        BreakpointSnapshot.setEnabledDuringTests(true)
    }

    override func tearDown() {
        BreakpointSnapshot.setEnabledDuringTests(false)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: [])
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        coordinator = nil
        super.tearDown()
    }

    /// Publishes one breakpoint and returns an interceptor wired to `client` and this test's
    /// coordinator.
    private func interceptor(stage: NetworkBreakpoint.Stage,
                             host: String = "unreachable.invalid",
                             timeout: TimeInterval = 60,
                             client: RecordingClient) -> HTTPInterceptorURLProtocol {
        BreakpointSnapshot.update(isEnabled: true, breakpoints: [
            NetworkBreakpoint(id: UUID(),
                              name: "cart",
                              isEnabled: true,
                              match: .host(host),
                              stage: stage,
                              timeout: 60)
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer original", forHTTPHeaderField: "Authorization")
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.breakpoints = coordinator
        interceptor.breakpointTimeoutOverride = timeout
        return interceptor
    }

    /// Spins the run loop until `condition` holds, rather than sleeping a fixed amount and hoping.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// The pause the coordinator is holding, once it has published one.
    @MainActor
    private func heldPause() -> PendingBreakpoint? {
        waitUntil { !coordinator.pending.isEmpty }
        return coordinator.pending.first
    }

    // MARK: - The request stage

    /// The property the whole design rests on: `startLoading()` runs on a thread the URL loading
    /// system owns, and a held request must not occupy it.
    @MainActor
    func testStartLoadingReturnsPromptlyWhileARequestIsHeld() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)

        let start = Date()
        interceptor.startLoading()
        let returned = Date().timeIntervalSince(start)

        XCTAssertLessThan(returned, 0.2, "a held request must not hold the loading system's thread")
        XCTAssertTrue(client.received.isEmpty, "and must not have answered the client either")
        XCTAssertNotNil(heldPause(), "the pause is live, waiting for a decision")
        XCTAssertFalse(interceptor.hasStartedTask, "nothing has gone out yet")

        interceptor.stopLoading()
    }

    @MainActor
    func testTheHeldDraftDescribesTheRequestAboutToBeSent() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)
        interceptor.startLoading()
        defer { interceptor.stopLoading() }

        let pause = try XCTUnwrap(heldPause())
        XCTAssertEqual(pause.breakpointName, "cart")
        XCTAssertEqual(pause.stage, .request)
        XCTAssertEqual(pause.draft.url, url.absoluteString)
        XCTAssertEqual(pause.draft.headers.first { $0.name == "Authorization" }?.value, "Bearer original")
    }

    @MainActor
    func testContinuingSendsTheEditedRequest() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)
        interceptor.startLoading()

        let pause = try XCTUnwrap(heldPause())
        var edited = pause.draft
        edited.headers.append(BreakpointDraft.Header(name: "X-Held", value: "1"))
        coordinator.resolve(id: pause.id, with: .continue(edited))

        XCTAssertTrue(waitUntil { interceptor.hasStartedTask }, "the edited request goes out")
        interceptor.stopLoading()
    }

    @MainActor
    func testAbortingFailsTheRequestWithTheChosenError() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)
        interceptor.startLoading()

        let pause = try XCTUnwrap(heldPause())
        coordinator.resolve(id: pause.id, with: .abort(.badServerResponse))

        XCTAssertTrue(waitUntil { client.received.contains("failed") })
        XCTAssertEqual(client.failureCode, .badServerResponse)
        XCTAssertFalse(interceptor.hasStartedTask, "an aborted request never reaches the network")
    }

    /// The rail: nobody decided, so the request proceeds exactly as the app wrote it.
    @MainActor
    func testTimingOutSendsTheRequestUnmodified() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, timeout: 0.3, client: client)

        interceptor.startLoading()
        XCTAssertFalse(interceptor.hasStartedTask)

        XCTAssertTrue(waitUntil { interceptor.hasStartedTask },
                      "the timeout continues the request rather than leaving the app hanging")
        XCTAssertTrue(waitUntil { self.coordinator.pending.isEmpty })
        interceptor.stopLoading()
    }

    /// A blocked pause could not be cancelled, which is half the reason nothing blocks.
    @MainActor
    func testCancellingAHeldRequestDeliversNothing() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, timeout: 0.3, client: client)
        interceptor.startLoading()
        _ = heldPause()

        interceptor.stopLoading()

        XCTAssertTrue(waitUntil { self.coordinator.pending.isEmpty },
                      "the editor stops showing a request nobody wants")
        XCTAssertFalse(waitUntil(1) { !client.received.isEmpty },
                       "a cancelled request delivers nothing, not even when its timeout fires")
        XCTAssertFalse(interceptor.hasStartedTask, "and never reaches the network")
    }

    @MainActor
    func testARequestNoBreakpointMatchesIsUntouched() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, host: "other.invalid", client: client)

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask, "it goes out inline, exactly as it did before")
        XCTAssertTrue(coordinator.pending.isEmpty)
        interceptor.stopLoading()
    }

    @MainActor
    func testNothingIsHeldWhileTheMasterSwitchIsOff() throws {
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: BreakpointSnapshot.current.breakpoints)

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask)
        XCTAssertTrue(coordinator.pending.isEmpty)
        interceptor.stopLoading()
    }

    /// The gate that keeps a stray breakpoint out of CI. Every other test in this class has
    /// deliberately opted out of it.
    @MainActor
    func testBreakpointsAreInertInATestRunByDefault() throws {
        BreakpointSnapshot.setEnabledDuringTests(false)
        let client = RecordingClient()
        let interceptor = interceptor(stage: .request, client: client)

        interceptor.startLoading()

        XCTAssertTrue(interceptor.hasStartedTask, "a test run holds nothing")
        XCTAssertTrue(coordinator.pending.isEmpty)
        interceptor.stopLoading()
    }

    // MARK: - The response stage

    /// Everything needed to drive a response through the delegate callbacks by hand.
    private struct ResponseHarness {
        let interceptor: HTTPInterceptorURLProtocol
        let client: RecordingClient
        let session: URLSession
        let task: URLSessionDataTask
        let response: HTTPURLResponse
    }

    private func responseHarness(timeout: TimeInterval = 60, status: Int = 500) throws -> ResponseHarness {
        let client = RecordingClient()
        let request = URLRequest(url: url)
        let interceptor = HTTPInterceptorURLProtocol(request: request, cachedResponse: nil, client: client)
        interceptor.breakpoints = coordinator
        interceptor.heldBreakpoint = NetworkBreakpoint(id: UUID(),
                                                       name: "cart",
                                                       isEnabled: true,
                                                       match: .host("unreachable.invalid"),
                                                       stage: .response,
                                                       timeout: 60)
        interceptor.breakpointTimeoutOverride = timeout
        let session = URLSession(configuration: .ephemeral)
        return ResponseHarness(
            interceptor: interceptor,
            client: client,
            session: session,
            task: session.dataTask(with: request),
            response: try XCTUnwrap(HTTPURLResponse(url: url,
                                                    statusCode: status,
                                                    httpVersion: nil,
                                                    headerFields: ["Content-Type": "application/json"]))
        )
    }

    /// Delivers a whole response through the delegate callbacks, as `URLSession` would.
    private func deliver(_ harness: ResponseHarness, body: Data, error: Error? = nil) {
        harness.interceptor.urlSession(harness.session,
                                       dataTask: harness.task,
                                       didReceive: harness.response) { _ in }
        harness.interceptor.urlSession(harness.session, dataTask: harness.task, didReceive: body)
        harness.interceptor.urlSession(harness.session, task: harness.task, didCompleteWithError: error)
    }

    /// A chunk already forwarded cannot be taken back, so a held response has to withhold every
    /// byte until the developer has decided.
    @MainActor
    func testAHeldResponseWithholdsEveryByteUntilItIsResolved() throws {
        let harness = try responseHarness()

        deliver(harness, body: Data("{\"error\":true}".utf8))

        XCTAssertTrue(harness.client.received.isEmpty, "not one byte, and not the headers either")
        let pause = try XCTUnwrap(heldPause())
        XCTAssertEqual(pause.stage, .response)
        XCTAssertEqual(pause.draft.statusCode, 500)
        XCTAssertEqual(pause.draft.body, Data("{\"error\":true}".utf8))

        var edited = pause.draft
        edited.statusCode = 200
        edited.setBodyText("[]")
        coordinator.resolve(id: pause.id, with: .continue(edited))

        XCTAssertTrue(waitUntil { harness.client.received == ["response", "data", "finished"] })
        XCTAssertEqual(harness.client.statusCode, 200)
        XCTAssertEqual(harness.client.body, Data("[]".utf8))
    }

    @MainActor
    func testAHeldResponseTimesOutUnmodified() throws {
        let harness = try responseHarness(timeout: 0.3)

        deliver(harness, body: Data("{\"error\":true}".utf8))
        XCTAssertTrue(harness.client.received.isEmpty)

        XCTAssertTrue(waitUntil { harness.client.received == ["response", "data", "finished"] })
        XCTAssertEqual(harness.client.statusCode, 500, "unmodified means unmodified")
        XCTAssertEqual(harness.client.body, Data("{\"error\":true}".utf8))
    }

    @MainActor
    func testAbortingAHeldResponseFailsTheLoad() throws {
        let harness = try responseHarness()
        deliver(harness, body: Data("{}".utf8))

        let pause = try XCTUnwrap(heldPause())
        coordinator.resolve(id: pause.id, with: .abort(.cannotParseResponse))

        XCTAssertTrue(waitUntil { harness.client.received == ["failed"] })
        XCTAssertEqual(harness.client.failureCode, .cannotParseResponse)
        XCTAssertTrue(harness.client.body.isEmpty, "an aborted response hands the app no bytes")
    }

    @MainActor
    func testCancellingAHeldResponseDeliversNothing() throws {
        let harness = try responseHarness(timeout: 0.3)
        deliver(harness, body: Data("{}".utf8))
        _ = heldPause()

        harness.interceptor.stopLoading()

        XCTAssertTrue(waitUntil { self.coordinator.pending.isEmpty })
        XCTAssertFalse(waitUntil(1) { !harness.client.received.isEmpty })
    }

    /// A failed load has no response to edit, so it is not held at all — and the bytes that were
    /// withheld on the way through still have to reach the app.
    @MainActor
    func testAFailedLoadIsNotHeldAndStillReportsItsFailure() throws {
        let harness = try responseHarness()

        deliver(harness, body: Data(), error: URLError(.timedOut))

        // The response arrived and was withheld; then the load failed. The app is handed both, in
        // the order it would have seen them had nothing been held.
        XCTAssertTrue(waitUntil { harness.client.received == ["response", "failed"] })
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    /// Buffering a large download in order to show it is not worth stalling the app for, so the
    /// pause is skipped and the response is forwarded as it stands.
    @MainActor
    func testAResponseOverTheBufferCapIsNotHeld() throws {
        let harness = try responseHarness(status: 200)
        harness.interceptor.maximumHeldResponseBytes = 64

        deliver(harness, body: Data(repeating: UInt8(ascii: "x"), count: 128))

        XCTAssertTrue(waitUntil { harness.client.received == ["response", "data", "finished"] })
        XCTAssertEqual(harness.client.body.count, 128, "every byte still arrives")
        XCTAssertTrue(coordinator.pending.isEmpty, "nothing was held")
    }

    // MARK: - Provenance

    /// The rebuilt request has to keep the marker that stops the interceptor picking it up a
    /// second time, whatever the developer changed about it.
    func testARebuiltRequestStillCarriesTheInterceptorsMarker() throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var draft = BreakpointDraft(request: request)
        draft.url = "https://elsewhere.invalid/v2/users"

        let rebuilt = HTTPInterceptorURLProtocol.marked(draft.makeURLRequest(basedOn: request))
        XCTAssertNotNil(URLProtocol.property(forKey: internalNetworkRequestKey, in: rebuilt))
        XCTAssertEqual(rebuilt.url?.absoluteString, "https://elsewhere.invalid/v2/users")
    }
}
