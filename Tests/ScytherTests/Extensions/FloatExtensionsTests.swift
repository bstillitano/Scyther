//
//  FloatExtensionsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class FloatExtensionsTests: XCTestCase {

    // MARK: - clean Tests

    func testCleanWithWholeNumber() {
        let value: Float = 5.0
        XCTAssertEqual(value.clean, "5")
    }

    func testCleanWithDecimal() {
        let value: Float = 5.7
        XCTAssertEqual(value.clean, "5.7")
    }

    func testCleanWithMultipleDecimals() {
        let value: Float = 3.14159
        let result = value.clean
        XCTAssertTrue(result.hasPrefix("3.14"))
    }

    func testCleanWithZero() {
        let value: Float = 0.0
        XCTAssertEqual(value.clean, "0")
    }

    func testCleanWithNegativeWholeNumber() {
        let value: Float = -5.0
        XCTAssertEqual(value.clean, "-5")
    }

    func testCleanWithNegativeDecimal() {
        let value: Float = -3.5
        XCTAssertEqual(value.clean, "-3.5")
    }

    func testCleanWithVerySmallDecimal() {
        let value: Float = 0.001
        let result = value.clean
        XCTAssertTrue(result.hasPrefix("0.00"))
    }

    // MARK: - withoutDecimals Tests

    func testWithoutDecimalsWholeNumber() {
        let value: Float = 42.0
        XCTAssertEqual(value.withoutDecimals, "42")
    }

    func testWithoutDecimalsTruncates() {
        let value: Float = 5.9
        XCTAssertEqual(value.withoutDecimals, "5")
    }

    func testWithoutDecimalsNegative() {
        let value: Float = -3.7
        XCTAssertEqual(value.withoutDecimals, "-3")
    }

    func testWithoutDecimalsZero() {
        let value: Float = 0.0
        XCTAssertEqual(value.withoutDecimals, "0")
    }

    func testWithoutDecimalsLargeNumber() {
        let value: Float = 1234567.89
        let result = value.withoutDecimals
        XCTAssertTrue(result.count >= 7)
    }

    func testWithoutDecimalsSmallFraction() {
        let value: Float = 0.99
        XCTAssertEqual(value.withoutDecimals, "0")
    }
}
