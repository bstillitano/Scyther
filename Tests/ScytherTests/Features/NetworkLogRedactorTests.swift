//
//  NetworkLogRedactorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkLogRedactorTests: XCTestCase {

    // MARK: Names

    func testSensitiveNamesAreDetectedCaseInsensitively() {
        for name in ["Authorization", "authorization", "Cookie", "Set-Cookie", "X-API-Key", "x-auth-token",
                     "access_token", "refreshToken", "password", "client_secret", "sessionId", "apikey"] {
            XCTAssertTrue(NetworkLogRedactor.isSensitiveName(name), name)
        }
        for name in ["Content-Type", "Accept", "page", "sort", "user_id", "name"] {
            XCTAssertFalse(NetworkLogRedactor.isSensitiveName(name), name)
        }
    }

    // MARK: Headers and query

    func testHeadersWithSensitiveNamesAreRedacted() {
        let headers = [
            HARNameValue(name: "Authorization", value: "Bearer abc"),
            HARNameValue(name: "Content-Type", value: "application/json"),
        ]
        let redacted = NetworkLogRedactor.redact(headers)
        XCTAssertEqual(redacted.map(\.value), ["REDACTED", "application/json"])
    }

    func testURLQueryValuesWithSensitiveNamesAreRedacted() {
        let url = "https://api.example.com/users?page=2&access_token=abc123&sort=name"
        XCTAssertEqual(
            NetworkLogRedactor.redactURL(url),
            "https://api.example.com/users?page=2&access_token=REDACTED&sort=name"
        )
        XCTAssertEqual(NetworkLogRedactor.redactURL("https://api.example.com/users"), "https://api.example.com/users")
    }

    // MARK: Body text

    func testJSONKeysWithSensitiveNamesAreRedacted() {
        let body = #"{"user":"ada","password":"hunter2","token": "t-1","nested":{"apiKey":"k","id":7}}"#
        let redacted = NetworkLogRedactor.redactText(body)
        XCTAssertEqual(
            redacted,
            #"{"user":"ada","password":"REDACTED","token": "REDACTED","nested":{"apiKey":"REDACTED","id":7}}"#
        )
    }

    func testBearerAndJWTValuesAreRedactedAnywhereInText() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let text = "Authorization: Bearer \(jwt)\nplain \(jwt) end\nBearer short"
        let redacted = NetworkLogRedactor.redactText(text)
        XCTAssertFalse(redacted.contains(jwt))
        XCTAssertEqual(redacted, "Authorization: Bearer REDACTED\nplain REDACTED end\nBearer REDACTED")
    }

    func testNonSensitiveTextIsUntouched() {
        let text = #"{"items":[{"id":1,"name":"Ada"}],"page":2}"#
        XCTAssertEqual(NetworkLogRedactor.redactText(text), text)
    }

    // MARK: cURL

    func testCurlHeadersWithSensitiveNamesAreRedacted() {
        let curl = "curl 'https://api.example.com/a?api_key=k1' -X GET -H 'Authorization: Bearer abc' -H 'Accept: */*' -H \"Cookie: session=1\""
        XCTAssertEqual(
            NetworkLogRedactor.redactCurl(curl),
            "curl 'https://api.example.com/a?api_key=REDACTED' -X GET -H 'Authorization: REDACTED' -H 'Accept: */*' -H \"Cookie: REDACTED\""
        )
    }

    // MARK: HAR

    func testHARRedactionTouchesEveryFieldAndAddsComment() {
        let entry = HAREntry(
            startedDateTime: "2026-09-04T00:00:00.000Z",
            time: 1,
            request: HARRequest(
                method: "POST",
                url: "https://api.example.com/login?token=abc",
                httpVersion: "HTTP/1.1",
                cookies: [],
                headers: [HARNameValue(name: "Cookie", value: "s=1")],
                queryString: [HARNameValue(name: "token", value: "abc")],
                postData: HARPostData(mimeType: "application/json", text: #"{"password":"x"}"#),
                headersSize: -1,
                bodySize: 14
            ),
            response: HARResponse(
                status: 200,
                statusText: "no error",
                httpVersion: "HTTP/1.1",
                cookies: [],
                headers: [HARNameValue(name: "Set-Cookie", value: "s=2")],
                content: HARContent(size: 10, mimeType: "application/json", text: #"{"refresh_token":"r"}"#, encoding: nil),
                redirectURL: "",
                headersSize: -1,
                bodySize: 10
            ),
            cache: HARCache(),
            timings: HARTimings(send: 0, wait: 1, receive: 0)
        )
        let log = HARLog(log: HARLogBody(version: "1.2", creator: HARCreator(name: "Scyther", version: "1"), comment: nil, entries: [entry]))

        let redacted = NetworkLogRedactor.redact(log)
        let out = redacted.log.entries[0]
        XCTAssertEqual(out.request.url, "https://api.example.com/login?token=REDACTED")
        XCTAssertEqual(out.request.headers[0].value, "REDACTED")
        XCTAssertEqual(out.request.queryString[0].value, "REDACTED")
        XCTAssertEqual(out.request.postData?.text, #"{"password":"REDACTED"}"#)
        XCTAssertEqual(out.response.headers[0].value, "REDACTED")
        XCTAssertEqual(out.response.content.text, #"{"refresh_token":"REDACTED"}"#)
        XCTAssertEqual(redacted.log.comment, NetworkLogRedactor.harComment)
    }

    func testBase64ContentIsLeftAlone() {
        let content = HARContent(size: 4, mimeType: "image/png", text: "iVBORw0KGgo=", encoding: "base64")
        XCTAssertEqual(NetworkLogRedactor.redact(content).text, "iVBORw0KGgo=")
    }
}
