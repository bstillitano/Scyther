//
//  BreakpointDraftTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class BreakpointDraftTests: XCTestCase {

    func testARequestDraftCapturesMethodURLHeadersAndBody() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users?page=2")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"name\":\"Ada\"}".utf8)

        let draft = BreakpointDraft(request: request)
        XCTAssertEqual(draft.method, "POST")
        XCTAssertEqual(draft.url, "https://api.example.com/v1/users?page=2")
        XCTAssertEqual(draft.headers.first { $0.name == "Content-Type" }?.value, "application/json")
        XCTAssertEqual(draft.body, Data("{\"name\":\"Ada\"}".utf8))
        XCTAssertNil(draft.statusCode, "a request draft has no status")
    }

    func testAnEditedRequestDraftRebuildsTheRequest() throws {
        var original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        original.httpMethod = "GET"

        var draft = BreakpointDraft(request: original)
        draft.method = "PUT"
        draft.url = "https://api.example.com/v1/users/1"
        draft.headers.append(BreakpointDraft.Header(name: "X-Debug", value: "1"))
        draft.body = Data("{}".utf8)

        let rebuilt = draft.makeURLRequest(basedOn: original)
        XCTAssertEqual(rebuilt.httpMethod, "PUT")
        XCTAssertEqual(rebuilt.url?.absoluteString, "https://api.example.com/v1/users/1")
        XCTAssertEqual(rebuilt.value(forHTTPHeaderField: "X-Debug"), "1")
        XCTAssertEqual(rebuilt.httpBody, Data("{}".utf8))
    }

    func testAnInvalidURLKeepsTheOriginalRequestURL() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        var draft = BreakpointDraft(request: original)
        draft.url = "not a url at all"
        XCTAssertEqual(draft.makeURLRequest(basedOn: original).url, original.url)
    }

    /// A header the developer deleted has to leave the request, which setting the remaining rows
    /// one by one would never achieve.
    func testADeletedHeaderIsGoneFromTheRebuiltRequest() {
        var original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        original.setValue("Bearer test", forHTTPHeaderField: "Authorization")

        var draft = BreakpointDraft(request: original)
        draft.headers.removeAll { $0.name == "Authorization" }

        XCTAssertNil(draft.makeURLRequest(basedOn: original).value(forHTTPHeaderField: "Authorization"))
    }

    /// The interceptor stamps its own marker on the request it sends. Losing it on the way through
    /// a breakpoint would have the rebuilt request intercepted a second time, which is a loop.
    func testRebuildingKeepsTheProtocolPropertiesOfTheOriginal() throws {
        let mutable = NSMutableURLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutable)
        let original = mutable as URLRequest

        var draft = BreakpointDraft(request: original)
        draft.url = "https://api.example.com/v1/other"

        let rebuilt = draft.makeURLRequest(basedOn: original)
        XCTAssertNotNil(URLProtocol.property(forKey: internalNetworkRequestKey, in: rebuilt))
    }

    /// `URLSession` sets these itself, and sending a stale `Content-Length` alongside an edited
    /// body is a request the server rejects for a reason the developer cannot see.
    func testHeadersTheSystemOwnsAreNotSentBack() {
        var original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        original.setValue("12", forHTTPHeaderField: "Content-Length")

        let draft = BreakpointDraft(request: original)
        XCTAssertNil(draft.makeURLRequest(basedOn: original).value(forHTTPHeaderField: "Content-Length"))
    }

    func testAResponseDraftCapturesStatusHeadersAndBody() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/users")!,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        let draft = BreakpointDraft(response: response, body: Data("{\"error\":true}".utf8))
        XCTAssertEqual(draft.statusCode, 500)
        XCTAssertEqual(draft.headers.first { $0.name == "Content-Type" }?.value, "application/json")
        XCTAssertEqual(draft.body, Data("{\"error\":true}".utf8))
        XCTAssertNil(draft.method, "a response draft has no method")
    }

    func testAnEditedResponseDraftRebuildsTheResponse() throws {
        let url = URL(string: "https://api.example.com/v1/users")!
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: [:]))
        var draft = BreakpointDraft(response: response, body: Data())
        draft.statusCode = 200
        draft.body = Data("[]".utf8)

        let rebuilt = try XCTUnwrap(draft.makeResponse(url: url))
        XCTAssertEqual(rebuilt.0.statusCode, 200)
        XCTAssertEqual(rebuilt.1, Data("[]".utf8))
    }

    func testARequestDraftCannotBeRebuiltAsAResponse() {
        let draft = BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
        XCTAssertNil(draft.makeResponse(url: URL(string: "https://api.example.com/v1/users")!),
                     "a draft with no status is not a response")
    }

    /// Identity is excluded from equality so that rebuilding the same values does not read as an
    /// edit — which is what decides whether the log marks the request as edited.
    func testTwoDraftsCarryingTheSameValuesAreEqual() {
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        XCTAssertEqual(BreakpointDraft(request: request), BreakpointDraft(request: request))
    }

    func testAnEditedDraftIsNotEqualToTheOneItCameFrom() {
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        let draft = BreakpointDraft(request: request)
        var edited = draft
        edited.method = "DELETE"
        XCTAssertNotEqual(edited, draft)
    }

    func testTheBodyReadsAndWritesAsText() {
        var draft = BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
        draft.setBodyText("{\"a\":1}")
        XCTAssertEqual(draft.body, Data("{\"a\":1}".utf8))
        XCTAssertEqual(draft.bodyText, "{\"a\":1}")
        draft.setBodyText("")
        XCTAssertNil(draft.body, "an emptied field sends nothing rather than a zero-length body")
    }

    func testABinaryBodyIsNotEditableAsText() {
        var draft = BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
        draft.body = Data([0xFF, 0xFE, 0xFD])
        XCTAssertFalse(draft.isBodyEditable)
        XCTAssertNil(draft.bodyText)
    }
}
