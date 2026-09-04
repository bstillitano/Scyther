//
//  NetworkLogHARBuilderTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkLogHARBuilderTests: XCTestCase {

    private func makeRequest(
        url: String = "https://api.example.com/users?page=2&sort=name",
        method: String = "POST",
        requestBody: String? = "{\"name\":\"Ada\"}",
        responseBody: Data = Data("{\"ok\":true}".utf8),
        status: Int = 201,
        contentType: String = "application/json"
    ) -> HTTPRequest {
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        mutable.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutable.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        if let requestBody {
            // Same mechanism the interceptor uses to hand the body to the logger.
            URLProtocol.setProperty(Data(requestBody.utf8), forKey: "ScytherBodyData", in: mutable)
        }
        let urlRequest = mutable as URLRequest

        let request = HTTPRequest()
        request.saveRequest(urlRequest)
        request.saveRequestBody(urlRequest)

        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType, "X-Trace": "abc"]
        )!
        request.saveResponse(response, data: responseBody)
        return request
    }

    func testLogHeaderAndCreator() {
        let log = NetworkLogHARBuilder.build(from: [makeRequest()], creatorVersion: "9.9.9")
        XCTAssertEqual(log.log.version, "1.2")
        XCTAssertEqual(log.log.creator.name, "Scyther")
        XCTAssertEqual(log.log.creator.version, "9.9.9")
        XCTAssertEqual(log.log.entries.count, 1)
    }

    func testEntryMapsRequestFields() throws {
        let entry = try XCTUnwrap(NetworkLogHARBuilder.build(from: [makeRequest()]).log.entries.first)
        XCTAssertEqual(entry.request.method, "POST")
        XCTAssertEqual(entry.request.url, "https://api.example.com/users?page=2&sort=name")
        XCTAssertEqual(entry.request.httpVersion, "HTTP/1.1")
        XCTAssertEqual(entry.request.queryString.map(\.name), ["page", "sort"])
        XCTAssertEqual(entry.request.queryString.map(\.value), ["2", "name"])
        XCTAssertTrue(entry.request.headers.contains { $0.name == "Authorization" && $0.value == "Bearer secret" })
        XCTAssertEqual(entry.request.postData?.mimeType, "application/json")
        XCTAssertEqual(entry.request.postData?.text, "{\"name\":\"Ada\"}")
        XCTAssertEqual(entry.request.bodySize, "{\"name\":\"Ada\"}".utf8.count)
        XCTAssertEqual(entry.request.headersSize, -1)
    }

    func testEntryMapsResponseFieldsAndTimings() throws {
        let entry = try XCTUnwrap(NetworkLogHARBuilder.build(from: [makeRequest()]).log.entries.first)
        XCTAssertEqual(entry.response.status, 201)
        XCTAssertEqual(entry.response.statusText, "created")
        XCTAssertTrue(entry.response.headers.contains { $0.name == "X-Trace" && $0.value == "abc" })
        XCTAssertEqual(entry.response.content.mimeType, "application/json")
        XCTAssertEqual(entry.response.content.text, "{\"ok\":true}")
        XCTAssertNil(entry.response.content.encoding)
        XCTAssertEqual(entry.response.content.size, "{\"ok\":true}".utf8.count)
        XCTAssertEqual(entry.response.redirectURL, "")
        XCTAssertGreaterThanOrEqual(entry.time, 0)
        XCTAssertEqual(entry.timings.wait, entry.time)
        XCTAssertEqual(entry.timings.send, 0)
        XCTAssertEqual(entry.timings.receive, 0)
        XCTAssertTrue(entry.startedDateTime.hasSuffix("Z"), "expected ISO 8601 UTC, got \(entry.startedDateTime)")
    }

    func testImageResponseIsMarkedBase64() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        let request = makeRequest(responseBody: png, contentType: "image/png")
        let entry = try XCTUnwrap(NetworkLogHARBuilder.build(from: [request]).log.entries.first)
        XCTAssertEqual(entry.response.content.encoding, "base64")
        XCTAssertEqual(
            entry.response.content.text?.replacingOccurrences(of: "\n", with: ""),
            png.base64EncodedString()
        )
    }

    func testRequestWithoutBodyHasNoPostData() throws {
        let request = makeRequest(method: "GET", requestBody: nil)
        let entry = try XCTUnwrap(NetworkLogHARBuilder.build(from: [request]).log.entries.first)
        XCTAssertNil(entry.request.postData)
        XCTAssertEqual(entry.request.bodySize, 0)
    }

    func testPendingRequestHasZeroStatusAndNoContent() throws {
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/slow")!)
        urlRequest.httpMethod = "GET"
        let request = HTTPRequest()
        request.saveRequest(urlRequest)
        let entry = try XCTUnwrap(NetworkLogHARBuilder.build(from: [request]).log.entries.first)
        XCTAssertEqual(entry.response.status, 0)
        XCTAssertNil(entry.response.content.text)
        XCTAssertEqual(entry.time, 0)
    }

    func testEntriesAreOrderedOldestFirst() {
        let newer = makeRequest(url: "https://api.example.com/newer")
        let older = makeRequest(url: "https://api.example.com/older")
        older.requestDate = Date(timeIntervalSince1970: 1_000)
        newer.requestDate = Date(timeIntervalSince1970: 2_000)
        let log = NetworkLogHARBuilder.build(from: [newer, older])
        XCTAssertEqual(log.log.entries.map(\.request.url), ["https://api.example.com/older", "https://api.example.com/newer"])
    }

    func testEncodedOutputIsValidJSONWithLogRoot() throws {
        let data = try NetworkLogHARBuilder.encode(NetworkLogHARBuilder.build(from: [makeRequest()]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let log = try XCTUnwrap(object["log"] as? [String: Any])
        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertEqual((log["entries"] as? [Any])?.count, 1)
    }
}
