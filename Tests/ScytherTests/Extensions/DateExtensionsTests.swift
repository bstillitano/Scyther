//
//  DateExtensionsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class DateExtensionsTests: XCTestCase {

    // MARK: - formatted Tests

    func testFormattedWithDefaultFormat() {
        // Create a specific date for testing
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 25
        components.hour = 14
        components.minute = 30
        components.second = 45

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        // Use the extension's formatted method with explicit default format
        let result = date.formatted(format: "dd/MM/yyyy hh:mm:ss")
        XCTAssertEqual(result, "25/12/2025 02:30:45")
    }

    func testFormattedWithCustomFormat() {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 20

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let result = date.formatted(format: "yyyy-MM-dd")
        XCTAssertEqual(result, "2025-12-20")
    }

    func testFormattedTimeOnly() {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        components.hour = 9
        components.minute = 5
        components.second = 3

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let result = date.formatted(format: "HH:mm:ss")
        XCTAssertEqual(result, "09:05:03")
    }

    func testFormattedDateOnly() {
        var components = DateComponents()
        components.year = 2020
        components.month = 6
        components.day = 15

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let result = date.formatted(format: "dd/MM/yyyy")
        XCTAssertEqual(result, "15/06/2020")
    }

    func testFormattedYearMonth() {
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 1

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let result = date.formatted(format: "MMMM yyyy")
        XCTAssertEqual(result, "March 2025")
    }
}
