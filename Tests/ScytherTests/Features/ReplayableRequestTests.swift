//
//  ReplayableRequestTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ReplayableRequestTests: XCTestCase {

    /// Builds a captured model the way the interceptor does, including a body on disk.
    private func capture(
        url: String = "https://api.example.com/v1/users?page=2",
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json", "Authorization": "Bearer abc"],
        body: String? = "{\"name\":\"Ada\"}"
    ) -> HTTPRequest {
        capture(url: url, method: method, headers: headers, bodyData: body.map { Data($0.utf8) })
    }

    /// Builds a captured model from raw bytes, so a body that is not text can be captured too.
    private func capture(
        url: String = "https://api.example.com/v1/users?page=2",
        method: String = "POST",
        headers: [String: String] = [:],
        bodyData: Data?
    ) -> HTTPRequest {
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        headers.forEach { mutable.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let bodyData {
            // The same mechanism the interceptor uses to hand a body to the logger.
            URLProtocol.setProperty(bodyData, forKey: "ScytherBodyData", in: mutable)
        }
        let request = mutable as URLRequest
        let model = HTTPRequest()
        model.saveRequest(request)
        model.saveRequestBody(request)
        return model
    }

    func testADraftCapturesMethodURLHeadersAndBody() {
        let draft = ReplayableRequest(capturing: capture())
        XCTAssertEqual(draft.method, "POST")
        XCTAssertEqual(draft.url, "https://api.example.com/v1/users?page=2")
        XCTAssertEqual(draft.headers.first { $0.name == "Authorization" }?.value, "Bearer abc")
        XCTAssertEqual(draft.body, Data("{\"name\":\"Ada\"}".utf8))
    }

    func testAnEmptyCaptureYieldsAUsableDraft() {
        let draft = ReplayableRequest(capturing: HTTPRequest())
        XCTAssertEqual(draft.method, "GET")
        XCTAssertEqual(draft.url, "")
        XCTAssertTrue(draft.headers.isEmpty)
        XCTAssertNil(draft.body)
        XCTAssertNil(draft.makeURLRequest(replayOf: "abc"), "an empty URL cannot be sent")
    }

    func testHeadersAreOrderedAlphabeticallyAtCapture() {
        let draft = ReplayableRequest(capturing: capture(headers: [
            "Zeta": "1", "Accept": "2", "Middle": "3"
        ], body: nil))
        XCTAssertEqual(draft.headers.map(\.name), ["Accept", "Middle", "Zeta"])
    }

    func testHeadersKeepTheirOrderAndDuplicates() {
        var draft = ReplayableRequest(capturing: capture(headers: [:], body: nil))
        draft.headers = [
            .init(name: "Accept", value: "application/json"),
            .init(name: "Accept", value: "text/plain"),
        ]
        let request = draft.makeURLRequest(replayOf: "abc")
        XCTAssertEqual(draft.headers.map(\.value), ["application/json", "text/plain"])
        XCTAssertNotNil(request, "a duplicated header must not prevent the request being built")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"),
                       "application/json,text/plain",
                       "a duplicated header is joined onto the wire, never dropped")
    }

    func testMakeURLRequestStampsProvenance() throws {
        let draft = ReplayableRequest(capturing: capture())
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "original-hash"))
        XCTAssertEqual(URLProtocol.property(forKey: replayOfRequestKey, in: request) as? String, "original-hash")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{\"name\":\"Ada\"}".utf8))
    }

    func testMakeURLRequestReturnsNilForAnInvalidURL() {
        var draft = ReplayableRequest(capturing: capture())
        draft.url = "not a url"
        XCTAssertNil(draft.makeURLRequest(replayOf: "abc"))
    }

    func testMakeURLRequestRejectsAURLWithNoSchemeOrHost() {
        var draft = ReplayableRequest(capturing: capture())
        draft.url = "/v1/users"
        XCTAssertNil(draft.makeURLRequest(replayOf: "abc"), "a path alone is not somewhere to send a request")
        draft.url = "https://"
        XCTAssertNil(draft.makeURLRequest(replayOf: "abc"), "a scheme alone is not somewhere to send a request")
    }

    func testMakeURLRequestTrimsSurroundingWhitespaceFromTheURL() throws {
        var draft = ReplayableRequest(capturing: capture())
        draft.url = "  https://api.example.com/v1/users  "
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "abc"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/users")
    }

    func testMakeURLRequestUppercasesAndTrimsTheMethod() throws {
        var draft = ReplayableRequest(capturing: capture())
        draft.method = " patch "
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "abc"))
        XCTAssertEqual(request.httpMethod, "PATCH")
    }

    func testMakeURLRequestDropsManagedHeaders() throws {
        var draft = ReplayableRequest(capturing: capture(headers: [:], body: nil))
        draft.headers = [
            .init(name: "Content-Length", value: "9999"),
            .init(name: "HOST", value: "elsewhere.example.com"),
            .init(name: "X-Debug", value: "1"),
        ]
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "abc"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Length"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Host"), "managed headers are matched case-insensitively")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Debug"), "1")
    }

    func testMakeURLRequestDropsUnnamedHeaderRows() throws {
        var draft = ReplayableRequest(capturing: capture(headers: [:], body: nil))
        draft.headers = [.init(name: "  ", value: "orphan"), .init(name: "X-Debug", value: "1")]
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "abc"))
        XCTAssertEqual(request.allHTTPHeaderFields ?? [:], ["X-Debug": "1"])
    }

    func testIsModifiedDetectsEachEditedFacet() {
        let original = ReplayableRequest(capturing: capture())
        XCTAssertFalse(original.isModified(from: original))

        var method = original; method.method = "PUT"
        XCTAssertTrue(method.isModified(from: original))

        var url = original; url.url = "https://api.example.com/v1/users/1"
        XCTAssertTrue(url.isModified(from: original))

        var header = original; header.headers.append(.init(name: "X-Debug", value: "1"))
        XCTAssertTrue(header.isModified(from: original))

        var body = original; body.setBodyText("{}")
        XCTAssertTrue(body.isModified(from: original))
    }

    func testIsModifiedIgnoresRowIdentity() {
        let original = ReplayableRequest(capturing: capture())
        var rebuilt = original
        rebuilt.headers = original.headers.map { .init(name: $0.name, value: $0.value) }
        XCTAssertFalse(rebuilt.isModified(from: original), "a fresh row identity is not an edit")
    }

    func testManagedHeadersAreNamed() {
        XCTAssertTrue(ReplayableRequest.managedHeaderNames.contains("content-length"))
        XCTAssertTrue(ReplayableRequest.managedHeaderNames.contains("host"))
        XCTAssertTrue(ReplayableRequest.isManaged("Content-Length"))
        XCTAssertTrue(ReplayableRequest.isManaged(" HOST "))
        XCTAssertFalse(ReplayableRequest.isManaged("Authorization"))
    }

    func testBodyTextRoundTripsUTF8() {
        var draft = ReplayableRequest(capturing: capture())
        XCTAssertEqual(draft.bodyText, "{\"name\":\"Ada\"}")
        XCTAssertFalse(draft.hasUncapturedBody)

        draft.setBodyText("")
        XCTAssertEqual(draft.bodyText, "", "an absent body edits as empty text")
    }

    /// The defect W22 named. The old test drove this state by assigning bytes to the draft
    /// directly, which nothing in the app does, and so certified a branch no capture could reach
    /// while the branch that a capture *does* reach — an empty body, silently — went unnoticed.
    /// This one starts where the app starts: a request the logger measured but could not store.
    func testABinaryCaptureReportsABodyItCannotReplay() {
        let binary = capture(bodyData: Data([0xFF, 0xFE, 0x00, 0x01]))
        XCTAssertEqual(binary.requestBodyLength, 4, "the logger measured it")

        let draft = ReplayableRequest(capturing: binary)

        XCTAssertNil(draft.body, "and could not keep it")
        XCTAssertTrue(draft.hasUncapturedBody, "so the draft knows a body is missing rather than assuming none")
        XCTAssertEqual(draft.uncapturedBodyByteCount, 4)
    }

    func testACaptureWithNoBodyAtAllReportsNothingMissing() {
        let draft = ReplayableRequest(capturing: capture(body: nil))
        XCTAssertNil(draft.body)
        XCTAssertFalse(draft.hasUncapturedBody, "no body is not the same as a body that was lost")
    }

    func testTypingABodyClearsTheMissingBodyWarning() {
        var draft = ReplayableRequest(capturing: capture(bodyData: Data([0xFF, 0xFE])))
        XCTAssertTrue(draft.hasUncapturedBody)

        draft.setBodyText("{}")

        XCTAssertFalse(draft.hasUncapturedBody, "the developer supplied the bytes the log could not")
        XCTAssertEqual(draft.body, Data("{}".utf8))
    }

    func testSettingBodyTextToEmptyClearsTheBody() {
        var draft = ReplayableRequest(capturing: capture())
        draft.setBodyText("")
        XCTAssertNil(draft.body, "an emptied body is sent as no body at all")
        draft.setBodyText("{}")
        XCTAssertEqual(draft.body, Data("{}".utf8))
    }

    func testByteCountReportsTheBodyLength() {
        var draft = ReplayableRequest(capturing: capture())
        XCTAssertEqual(draft.bodyByteCount, 14)
        draft.setBodyText("")
        XCTAssertEqual(draft.bodyByteCount, 0)
    }
    /// A replay is a request Scyther composed and sent, so it carries the mark that keeps
    /// breakpoints and header rewrites off it. Nothing else in the suite drives a replay-built
    /// request through the interceptor, so without this the whole replay half of the exemption
    /// could be deleted and every test would still pass.
    func testAReplayIsMarkedAsScythersOwn() throws {
        let draft = ReplayableRequest(capturing: capture())
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "original-hash"))

        XCTAssertTrue(ScytherOriginatedRequest.identifies(request))
        XCTAssertFalse(ScytherOriginatedRequest.appliesOverrides(request),
                       "and by default asks for no override to touch it")
    }

    /// The **Apply Request Overrides** toggle, on the request it produces.
    func testAReplaySentWithOverridesOnCarriesTheOptIn() throws {
        let draft = ReplayableRequest(capturing: capture())
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "original-hash", applyingOverrides: true))

        XCTAssertTrue(ScytherOriginatedRequest.identifies(request),
                      "opting into overrides does not stop it being Scyther's own request")
        XCTAssertTrue(ScytherOriginatedRequest.appliesOverrides(request))
    }
}

/// The capture side of a replay: the provenance property survives into the logged model, and is
/// stripped from a redirect so the entry a redirect produces is not claimed as a second replay.
final class ReplayInterceptorTests: XCTestCase {

    private let url = URL(string: "https://api.example.com/v1/users")!

    /// Records the request the interceptor forwarded to the client on a redirect.
    ///
    /// `URLProtocolClient` is `Sendable`, so the recorded request is held behind a lock rather
    /// than in a bare mutable property — the same shape every other recording double in this
    /// target uses.
    private final class RedirectRecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: URLRequest?

        var redirectedTo: URLRequest? { lock.withLock { storage } }

        func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
            lock.withLock { storage = request }
        }

        func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) { }
        func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) { }
        func urlProtocolDidFinishLoading(_ protocol: URLProtocol) { }
        func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) { }
        func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { }
        func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { }
        func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { }
    }

    func testACapturedReplayRecordsWhatItReplays() throws {
        let mutable = NSMutableURLRequest(url: url)
        mutable.httpMethod = "GET"
        URLProtocol.setProperty("original-hash", forKey: replayOfRequestKey, in: mutable)

        let model = HTTPRequest()
        model.saveRequest(mutable as URLRequest)
        XCTAssertEqual(model.replayOfID, "original-hash")
    }

    func testAnOrdinaryRequestRecordsNoProvenance() {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(request)
        XCTAssertNil(model.replayOfID)
    }

    func testProvenanceSurvivesARewrittenRequestBeingSavedAgain() {
        let mutable = NSMutableURLRequest(url: url)
        URLProtocol.setProperty("original-hash", forKey: replayOfRequestKey, in: mutable)

        let model = HTTPRequest()
        model.saveRequest(mutable as URLRequest)

        // A header rewrite re-saves the request from a copy. Whether or not the copy carries the
        // property, the provenance already recorded must not be lost.
        var rewritten = URLRequest(url: url)
        rewritten.setValue("1", forHTTPHeaderField: "X-Debug")
        model.saveRequest(rewritten)

        XCTAssertEqual(model.replayOfID, "original-hash")
    }

    func testARedirectCarriesNeitherTheInternalMarkerNorTheProvenance() throws {
        let client = RedirectRecordingClient()
        let interceptor = HTTPInterceptorURLProtocol(request: URLRequest(url: url), cachedResponse: nil, client: client)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URLRequest(url: url))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))

        let redirected = NSMutableURLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v2/users")))
        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: redirected)
        URLProtocol.setProperty("original-hash", forKey: replayOfRequestKey, in: redirected)

        var handed: URLRequest?
        interceptor.urlSession(session,
                               task: task,
                               willPerformHTTPRedirection: response,
                               newRequest: redirected as URLRequest) { handed = $0 }
        session.invalidateAndCancel()

        let forwarded = try XCTUnwrap(handed)
        XCTAssertNil(URLProtocol.property(forKey: internalNetworkRequestKey, in: forwarded))
        XCTAssertNil(URLProtocol.property(forKey: replayOfRequestKey, in: forwarded),
                     "a redirect is a request of its own, not a second replay of the original")
        XCTAssertEqual(client.redirectedTo?.url, forwarded.url)
        XCTAssertNil(client.redirectedTo.flatMap { URLProtocol.property(forKey: replayOfRequestKey, in: $0) })
    }

    func testARedirectOfOrdinaryTrafficIsForwardedUnchanged() throws {
        let client = RedirectRecordingClient()
        let interceptor = HTTPInterceptorURLProtocol(request: URLRequest(url: url), cachedResponse: nil, client: client)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URLRequest(url: url))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let redirected = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v2/users")))

        var handed: URLRequest?
        interceptor.urlSession(session,
                               task: task,
                               willPerformHTTPRedirection: response,
                               newRequest: redirected) { handed = $0 }
        session.invalidateAndCancel()

        XCTAssertEqual(handed?.url?.absoluteString, "https://api.example.com/v2/users")
    }
}
