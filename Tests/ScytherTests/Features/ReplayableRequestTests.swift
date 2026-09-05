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
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        headers.forEach { mutable.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            // The same mechanism the interceptor uses to hand a body to the logger.
            URLProtocol.setProperty(Data(body.utf8), forKey: "ScytherBodyData", in: mutable)
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

        var body = original; body.body = Data("{}".utf8)
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

    func testBodyTextRoundTripsUTF8AndRefusesBinary() {
        var draft = ReplayableRequest(capturing: capture())
        XCTAssertEqual(draft.bodyText, "{\"name\":\"Ada\"}")
        XCTAssertTrue(draft.isBodyEditable)

        draft.body = Data([0xFF, 0xFE, 0x00])
        XCTAssertNil(draft.bodyText)
        XCTAssertFalse(draft.isBodyEditable, "a body that is not valid UTF-8 cannot be edited as text")

        draft.body = nil
        XCTAssertEqual(draft.bodyText, "", "an absent body edits as empty text")
        XCTAssertTrue(draft.isBodyEditable)
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
        draft.body = nil
        XCTAssertEqual(draft.bodyByteCount, 0)
    }
}
