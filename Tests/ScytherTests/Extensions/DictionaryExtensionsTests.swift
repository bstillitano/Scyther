//
//  DictionaryExtensionsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class DictionaryExtensionsTests: XCTestCase {

    // MARK: - jsonString Tests

    func testJsonStringWithSimpleDictionary() {
        let dict: [String: Any] = ["name": "John"]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("\"name\"") ?? false)
        XCTAssertTrue(result?.contains("\"John\"") ?? false)
    }

    func testJsonStringWithMultipleValues() {
        let dict: [String: Any] = ["name": "John", "age": 30, "active": true]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("name") ?? false)
        XCTAssertTrue(result?.contains("age") ?? false)
        XCTAssertTrue(result?.contains("active") ?? false)
    }

    func testJsonStringWithEmptyDictionary() {
        let dict: [String: Any] = [:]
        let result = dict.jsonString
        XCTAssertEqual(result, "{}")
    }

    func testJsonStringWithNestedDictionary() {
        let dict: [String: Any] = [
            "user": ["name": "John", "email": "john@example.com"]
        ]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("user") ?? false)
        XCTAssertTrue(result?.contains("name") ?? false)
    }

    func testJsonStringWithArray() {
        let dict: [String: Any] = ["items": [1, 2, 3]]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("items") ?? false)
    }

    func testJsonStringWithNumericValues() {
        let dict: [String: Any] = ["integer": 42, "double": 3.14]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("42") ?? false)
    }

    func testJsonStringWithBooleanValues() {
        let dict: [String: Any] = ["isEnabled": true, "isDisabled": false]
        let result = dict.jsonString
        XCTAssertNotNil(result)
        // JSON serialization uses 1/0 or true/false depending on platform
    }
}
