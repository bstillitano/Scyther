//
//  BoolExtensionsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class BoolExtensionsTests: XCTestCase {

    // MARK: - stringValue Tests

    func testStringValueTrue() {
        let value = true
        XCTAssertEqual(value.stringValue, "true")
    }

    func testStringValueFalse() {
        let value = false
        XCTAssertEqual(value.stringValue, "false")
    }

    // MARK: - OR Compound Assignment (|=) Tests

    func testOrAssignmentFalseOrTrue() {
        var value = false
        value |= true
        XCTAssertTrue(value)
    }

    func testOrAssignmentFalseOrFalse() {
        var value = false
        value |= false
        XCTAssertFalse(value)
    }

    func testOrAssignmentTrueOrFalse() {
        var value = true
        value |= false
        XCTAssertTrue(value)
    }

    func testOrAssignmentTrueOrTrue() {
        var value = true
        value |= true
        XCTAssertTrue(value)
    }

    // MARK: - AND Compound Assignment (&=) Tests

    func testAndAssignmentTrueAndTrue() {
        var value = true
        value &= true
        XCTAssertTrue(value)
    }

    func testAndAssignmentTrueAndFalse() {
        var value = true
        value &= false
        XCTAssertFalse(value)
    }

    func testAndAssignmentFalseAndTrue() {
        var value = false
        value &= true
        XCTAssertFalse(value)
    }

    func testAndAssignmentFalseAndFalse() {
        var value = false
        value &= false
        XCTAssertFalse(value)
    }

    // MARK: - XOR Compound Assignment (^=) Tests

    func testXorAssignmentFalseXorTrue() {
        var value = false
        value ^= true
        XCTAssertTrue(value)
    }

    func testXorAssignmentTrueXorTrue() {
        var value = true
        value ^= true
        XCTAssertFalse(value)
    }

    func testXorAssignmentFalseXorFalse() {
        var value = false
        value ^= false
        XCTAssertFalse(value)
    }

    func testXorAssignmentTrueXorFalse() {
        var value = true
        value ^= false
        XCTAssertTrue(value)
    }

    func testXorToggleBehavior() {
        var toggle = false
        toggle ^= true  // Should become true
        XCTAssertTrue(toggle)
        toggle ^= true  // Should become false (toggle back)
        XCTAssertFalse(toggle)
    }
}
