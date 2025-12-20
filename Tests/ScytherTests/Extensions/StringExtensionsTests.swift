//
//  StringExtensionsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class StringExtensionsTests: XCTestCase {

    // MARK: - replacingOccurences Tests

    func testReplacingOccurencesWithSingleString() {
        let input = "Hello World"
        let result = input.replacingOccurences(of: ["World"], with: "Swift")
        XCTAssertEqual(result, "Hello Swift")
    }

    func testReplacingOccurencesWithMultipleStrings() {
        let input = "iPhone12,3"
        let result = input.replacingOccurences(of: ["iPhone", "iPad", "iPod"], with: "")
        XCTAssertEqual(result, "12,3")
    }

    func testReplacingOccurencesWithEmptyArray() {
        let input = "Hello World"
        let result = input.replacingOccurences(of: [], with: "")
        XCTAssertEqual(result, "Hello World")
    }

    func testReplacingOccurencesNoMatch() {
        let input = "Hello World"
        let result = input.replacingOccurences(of: ["Foo", "Bar"], with: "Baz")
        XCTAssertEqual(result, "Hello World")
    }

    func testReplacingOccurencesMultipleMatches() {
        let input = "aaa bbb aaa"
        let result = input.replacingOccurences(of: ["aaa"], with: "xxx")
        XCTAssertEqual(result, "xxx bbb xxx")
    }

    // MARK: - dictionaryRepresentation Tests

    func testDictionaryRepresentationValidJSON() {
        let jsonString = """
        {"name": "John", "age": 30}
        """
        let result = jsonString.dictionaryRepresentation
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["name"] as? String, "John")
        XCTAssertEqual(result?["age"] as? Int, 30)
    }

    func testDictionaryRepresentationInvalidJSON() {
        let invalidJson = "not valid json"
        let result = invalidJson.dictionaryRepresentation
        XCTAssertNil(result)
    }

    func testDictionaryRepresentationEmptyObject() {
        let jsonString = "{}"
        let result = jsonString.dictionaryRepresentation
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty ?? false)
    }

    func testDictionaryRepresentationNestedJSON() {
        let jsonString = """
        {"user": {"name": "John", "active": true}, "count": 5}
        """
        let result = jsonString.dictionaryRepresentation
        XCTAssertNotNil(result)
        let user = result?["user"] as? [String: Any]
        XCTAssertNotNil(user)
        XCTAssertEqual(user?["name"] as? String, "John")
        XCTAssertEqual(user?["active"] as? Bool, true)
    }

    // MARK: - jsonRepresentation Tests

    func testJsonRepresentationWithDictionary() {
        let jsonString = """
        {"status": "success", "count": 5}
        """
        let result = jsonString.jsonRepresentation
        XCTAssertNotNil(result)
        let dict = result as? [String: Any]
        XCTAssertEqual(dict?["status"] as? String, "success")
        XCTAssertEqual(dict?["count"] as? Int, 5)
    }

    func testJsonRepresentationWithArray() {
        let jsonString = """
        [{"id": 1}, {"id": 2}]
        """
        let result = jsonString.jsonRepresentation
        XCTAssertNotNil(result)
        let array = result as? [[String: Any]]
        XCTAssertEqual(array?.count, 2)
        XCTAssertEqual(array?[0]["id"] as? Int, 1)
        XCTAssertEqual(array?[1]["id"] as? Int, 2)
    }

    func testJsonRepresentationInvalidJSON() {
        let invalidJson = "not json at all"
        let result = invalidJson.jsonRepresentation
        XCTAssertNil(result)
    }

    func testJsonRepresentationEmptyString() {
        let emptyString = ""
        let result = emptyString.jsonRepresentation
        XCTAssertNil(result)
    }

    // MARK: - ranges Tests

    func testRangesFindsMultipleOccurrences() {
        let text = "Hello world, hello Swift"
        let ranges = text.ranges(of: "hello", options: .caseInsensitive)
        XCTAssertEqual(ranges.count, 2)
    }

    func testRangesNoMatch() {
        let text = "Hello world"
        let ranges = text.ranges(of: "foo")
        XCTAssertTrue(ranges.isEmpty)
    }

    func testRangesCaseSensitive() {
        let text = "Hello hello HELLO"
        let ranges = text.ranges(of: "hello")
        XCTAssertEqual(ranges.count, 1)
    }

    func testRangesEmptySubstring() {
        let text = "Hello world"
        let ranges = text.ranges(of: "")
        // Empty string search behavior: Swift's range(of:) returns nil for empty string
        // so we get an empty array
        XCTAssertTrue(ranges.isEmpty)
    }
}
