//
//  DatabaseValueTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class DatabaseValueTests: XCTestCase {

    // MARK: - Integer Tests

    func testIntegerValue() {
        let value = DatabaseValue.integer(42)
        XCTAssertEqual(value.displayString, "42")
        XCTAssertFalse(value.isNull)
    }

    func testNegativeInteger() {
        let value = DatabaseValue.integer(-100)
        XCTAssertEqual(value.displayString, "-100")
    }

    // MARK: - Real Tests

    func testRealValue() {
        let value = DatabaseValue.real(3.14159)
        XCTAssertTrue(value.displayString.hasPrefix("3.14"))
        XCTAssertFalse(value.isNull)
    }

    func testRealWithWholeNumber() {
        let value = DatabaseValue.real(42.0)
        XCTAssertEqual(value.displayString, "42")
    }

    // MARK: - Text Tests

    func testTextValue() {
        let value = DatabaseValue.text("Hello, World!")
        XCTAssertEqual(value.displayString, "Hello, World!")
        XCTAssertFalse(value.isNull)
    }

    func testEmptyText() {
        let value = DatabaseValue.text("")
        XCTAssertEqual(value.displayString, "")
    }

    // MARK: - Blob Tests

    func testBlobValue() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let value = DatabaseValue.blob(data)
        XCTAssertTrue(value.displayString.contains("4 bytes"))
        XCTAssertFalse(value.isNull)
    }

    func testEmptyBlob() {
        let value = DatabaseValue.blob(Data())
        // Empty blob displays as "<Zero KB>" or similar based on ByteCountFormatter
        XCTAssertTrue(value.displayString.hasPrefix("<"))
        XCTAssertTrue(value.displayString.hasSuffix(">"))
    }

    // MARK: - Null Tests

    func testNullValue() {
        let value = DatabaseValue.null
        XCTAssertEqual(value.displayString, "NULL")
        XCTAssertTrue(value.isNull)
    }

    // MARK: - Equatable Tests

    func testEquatableIntegers() {
        XCTAssertEqual(DatabaseValue.integer(42), DatabaseValue.integer(42))
        XCTAssertNotEqual(DatabaseValue.integer(42), DatabaseValue.integer(100))
    }

    func testEquatableReals() {
        XCTAssertEqual(DatabaseValue.real(3.14), DatabaseValue.real(3.14))
        XCTAssertNotEqual(DatabaseValue.real(3.14), DatabaseValue.real(2.71))
    }

    func testEquatableText() {
        XCTAssertEqual(DatabaseValue.text("hello"), DatabaseValue.text("hello"))
        XCTAssertNotEqual(DatabaseValue.text("hello"), DatabaseValue.text("world"))
    }

    func testEquatableDifferentTypes() {
        XCTAssertNotEqual(DatabaseValue.integer(42), DatabaseValue.text("42"))
        XCTAssertNotEqual(DatabaseValue.real(3.14), DatabaseValue.integer(3))
    }
}
#endif
