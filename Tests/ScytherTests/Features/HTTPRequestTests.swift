//
//  HTTPRequestTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class HTTPRequestTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        let request = HTTPRequest()

        XCTAssertNil(request.requestURL)
        XCTAssertNil(request.requestMethod)
        XCTAssertNil(request.requestDate)
        XCTAssertNil(request.responseCode)
        XCTAssertTrue(request.noResponse)
    }

    // MARK: - getRandomHash Tests

    func testGetRandomHashReturnsValue() {
        let request = HTTPRequest()
        let hash = request.getRandomHash()
        XCTAssertFalse(hash.length == 0)
    }

    func testGetRandomHashReturnsSameValue() {
        let request = HTTPRequest()
        let hash1 = request.getRandomHash()
        let hash2 = request.getRandomHash()
        XCTAssertEqual(hash1, hash2)
    }

    func testDifferentRequestsHaveDifferentHashes() {
        let request1 = HTTPRequest()
        let request2 = HTTPRequest()
        let hash1 = request1.getRandomHash()
        let hash2 = request2.getRandomHash()
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - File Path Tests

    func testGetDocumentsPath() {
        let request = HTTPRequest()
        let path = request.getDocumentsPath()
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.contains("Documents"))
    }

    func testGetRequestBodyFilepath() {
        let request = HTTPRequest()
        let filepath = request.getRequestBodyFilepath()
        XCTAssertFalse(filepath.isEmpty)
        XCTAssertTrue(filepath.contains("logger_request_body"))
    }

    func testGetResponseBodyFilepath() {
        let request = HTTPRequest()
        let filepath = request.getResponseBodyFilepath()
        XCTAssertFalse(filepath.isEmpty)
        XCTAssertTrue(filepath.contains("logger_response_body"))
    }

    func testGetRequestBodyFilename() {
        let request = HTTPRequest()
        let filename = request.getRequestBodyFilename()
        XCTAssertTrue(filename.hasPrefix("logger_request_body"))
    }

    func testGetResponseBodyFilename() {
        let request = HTTPRequest()
        let filename = request.getResponseBodyFilename()
        XCTAssertTrue(filename.hasPrefix("logger_response_body"))
    }

    // MARK: - getShortTypeFrom Tests

    func testGetShortTypeFromJSON() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("application/json"), .JSON)
    }

    func testGetShortTypeFromVendorJSON() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("application/vnd.api+json"), .JSON)
    }

    func testGetShortTypeFromXML() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("application/xml"), .XML)
        XCTAssertEqual(request.getShortTypeFrom("text/xml"), .XML)
    }

    func testGetShortTypeFromHTML() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("text/html"), .HTML)
    }

    func testGetShortTypeFromImage() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("image/png"), .IMAGE)
        XCTAssertEqual(request.getShortTypeFrom("image/jpeg"), .IMAGE)
        XCTAssertEqual(request.getShortTypeFrom("image/gif"), .IMAGE)
    }

    func testGetShortTypeFromOther() {
        let request = HTTPRequest()

        XCTAssertEqual(request.getShortTypeFrom("text/plain"), .OTHER)
        XCTAssertEqual(request.getShortTypeFrom("application/octet-stream"), .OTHER)
    }

    // MARK: - getTimeFromDate Tests

    func testGetTimeFromDateValid() {
        let request = HTTPRequest()
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 21
        components.hour = 14
        components.minute = 30
        components.second = 45

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let timeString = request.getTimeFromDate(date)
        XCTAssertNotNil(timeString)
        XCTAssertTrue(timeString?.contains(":") ?? false)
    }

    func testGetTimeFromDateNil() {
        let request = HTTPRequest()
        let timeString = request.getTimeFromDate(nil)
        XCTAssertNil(timeString)
    }

    // MARK: - prettyPrint Tests

    func testPrettyPrintJSON() {
        let request = HTTPRequest()
        let jsonData = """
        {"name":"John","age":30}
        """.data(using: .utf8)!

        let result = request.prettyPrint(jsonData, type: .JSON)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("name") ?? false)
        XCTAssertTrue(result?.contains("John") ?? false)
    }

    func testPrettyPrintInvalidJSON() {
        let request = HTTPRequest()
        let invalidData = "not json".data(using: .utf8)!

        let result = request.prettyPrint(invalidData, type: .JSON)
        XCTAssertNil(result)
    }

    func testPrettyPrintOtherType() {
        let request = HTTPRequest()
        let data = "plain text".data(using: .utf8)!

        let result = request.prettyPrint(data, type: .OTHER)
        XCTAssertNil(result)
    }

    // MARK: - formattedRequestLogEntry Tests

    func testFormattedRequestLogEntry() {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com/test"
        request.requestMethod = "GET"
        request.requestDate = Date()

        let logEntry = request.formattedRequestLogEntry()
        XCTAssertTrue(logEntry.contains("START REQUEST"))
        XCTAssertTrue(logEntry.contains("api.example.com"))
        XCTAssertTrue(logEntry.contains("GET"))
        XCTAssertTrue(logEntry.contains("END REQUEST"))
    }

    func testFormattedRequestLogEntryWithAllFields() {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com/users"
        request.requestMethod = "POST"
        request.requestDate = Date()
        request.requestTime = "14:30:00"
        request.requestType = "application/json"
        request.requestTimeout = "30"
        request.requestHeaders = ["Content-Type": "application/json"]

        let logEntry = request.formattedRequestLogEntry()
        XCTAssertTrue(logEntry.contains("POST"))
        XCTAssertTrue(logEntry.contains("application/json"))
        XCTAssertTrue(logEntry.contains("14:30:00"))
    }

    // MARK: - formattedResponseLogEntry Tests

    func testFormattedResponseLogEntry() {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com/test"
        request.responseCode = 200
        request.responseDate = Date()
        request.responseType = "application/json"

        let logEntry = request.formattedResponseLogEntry()
        XCTAssertTrue(logEntry.contains("START RESPONSE"))
        XCTAssertTrue(logEntry.contains("200"))
        XCTAssertTrue(logEntry.contains("application/json"))
        XCTAssertTrue(logEntry.contains("END RESPONSE"))
    }

    // MARK: - saveErrorResponse Tests

    func testSaveErrorResponse() {
        let request = HTTPRequest()
        XCTAssertNil(request.responseDate)

        request.saveErrorResponse()
        XCTAssertNotNil(request.responseDate)
    }

    // MARK: - getResponseBodyDictionary Tests

    func testGetResponseBodyDictionaryEmpty() {
        let request = HTTPRequest()
        let result = request.getResponseBodyDictionary()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformance() async {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com"

        await Task {
            XCTAssertEqual(request.requestURL, "https://api.example.com")
        }.value
    }

    // MARK: - Identifiable Conformance Tests

    func testIdentifiableConformance() {
        let request = HTTPRequest()
        // HTTPRequest conforms to Identifiable, should have an id
        let hash = request.getRandomHash()
        XCTAssertFalse(hash.length == 0)
    }
}
