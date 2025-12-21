//
//  CrashLoggerTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class CrashLoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any existing crash logs before each test
        CrashLogger.instance.clear()
    }

    override func tearDown() {
        // Clean up after each test
        CrashLogger.instance.clear()
        super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSingletonInstance() {
        let instance1 = CrashLogger.instance
        let instance2 = CrashLogger.instance
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        XCTAssertTrue(CrashLogger.instance.allCrashes.isEmpty)
        XCTAssertEqual(CrashLogger.instance.crashCount, 0)
    }

    // MARK: - Clear Tests

    func testClearEmptiesCrashes() {
        CrashLogger.instance.clear()
        XCTAssertTrue(CrashLogger.instance.allCrashes.isEmpty)
        XCTAssertEqual(CrashLogger.instance.crashCount, 0)
    }

    func testClearPostsNotification() {
        let expectation = XCTestExpectation(description: "Notification posted")

        let observer = NotificationCenter.default.addObserver(
            forName: CrashLogger.didRecordCrashNotification,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        CrashLogger.instance.clear()

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Crash Count Tests

    func testCrashCountMatchesAllCrashesCount() {
        let crashes = CrashLogger.instance.allCrashes
        let count = CrashLogger.instance.crashCount
        XCTAssertEqual(crashes.count, count)
    }
}

// MARK: - CrashLogEntry Tests

final class CrashLogEntryTests: XCTestCase {

    // MARK: - Initialization Tests

    func testEntryInitialization() {
        let entry = CrashLogEntry(
            name: "NSInvalidArgumentException",
            reason: "Test reason",
            stackTrace: ["Frame 0", "Frame 1"],
            appVersion: "1.0.0",
            buildNumber: "42",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertEqual(entry.name, "NSInvalidArgumentException")
        XCTAssertEqual(entry.reason, "Test reason")
        XCTAssertEqual(entry.stackTrace, ["Frame 0", "Frame 1"])
        XCTAssertEqual(entry.appVersion, "1.0.0")
        XCTAssertEqual(entry.buildNumber, "42")
        XCTAssertEqual(entry.osVersion, "17.0")
        XCTAssertEqual(entry.deviceModel, "iPhone")
        XCTAssertNotNil(entry.id)
        XCTAssertNotNil(entry.timestamp)
    }

    func testEntryWithNilReason() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: nil,
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertNil(entry.reason)
    }

    func testEntryWithEmptyStackTrace() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertTrue(entry.stackTrace.isEmpty)
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertNotNil(entry.id)
    }

    func testDifferentEntriesHaveUniqueIds() {
        let entry1 = CrashLogEntry(
            name: "Exception1",
            reason: "Reason 1",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let entry2 = CrashLogEntry(
            name: "Exception2",
            reason: "Reason 2",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertNotEqual(entry1.id, entry2.id)
    }

    // MARK: - Equatable Tests

    func testEquatableSameEntry() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: "Test",
            stackTrace: ["Frame 0"],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertEqual(entry, entry)
    }

    func testEquatableDifferentEntries() {
        let entry1 = CrashLogEntry(
            name: "Exception1",
            reason: "Reason 1",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let entry2 = CrashLogEntry(
            name: "Exception2",
            reason: "Reason 2",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertNotEqual(entry1, entry2)
    }

    // MARK: - Codable Tests

    func testEncodingDecoding() throws {
        let originalEntry = CrashLogEntry(
            name: "NSRangeException",
            reason: "Array index out of bounds",
            stackTrace: ["Frame 0", "Frame 1", "Frame 2"],
            appVersion: "2.0.0",
            buildNumber: "100",
            osVersion: "18.0",
            deviceModel: "iPad"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalEntry)

        let decoder = JSONDecoder()
        let decodedEntry = try decoder.decode(CrashLogEntry.self, from: data)

        XCTAssertEqual(originalEntry.id, decodedEntry.id)
        XCTAssertEqual(originalEntry.name, decodedEntry.name)
        XCTAssertEqual(originalEntry.reason, decodedEntry.reason)
        XCTAssertEqual(originalEntry.stackTrace, decodedEntry.stackTrace)
        XCTAssertEqual(originalEntry.appVersion, decodedEntry.appVersion)
        XCTAssertEqual(originalEntry.buildNumber, decodedEntry.buildNumber)
        XCTAssertEqual(originalEntry.osVersion, decodedEntry.osVersion)
        XCTAssertEqual(originalEntry.deviceModel, decodedEntry.deviceModel)
    }

    func testEncodingDecodingWithNilReason() throws {
        let originalEntry = CrashLogEntry(
            name: "TestException",
            reason: nil,
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalEntry)

        let decoder = JSONDecoder()
        let decodedEntry = try decoder.decode(CrashLogEntry.self, from: data)

        XCTAssertNil(decodedEntry.reason)
    }

    // MARK: - FormattedTimestamp Tests

    func testFormattedTimestamp() {
        var components = DateComponents()
        components.year = 2024
        components.month = 12
        components.day = 22
        components.hour = 14
        components.minute = 30
        components.second = 45

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let entry = CrashLogEntry(
            id: UUID(),
            timestamp: date,
            name: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let formatted = entry.formattedTimestamp
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("2024"))
    }

    // MARK: - Summary Tests

    func testSummaryWithReason() {
        let entry = CrashLogEntry(
            name: "NSException",
            reason: "This is the reason",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertEqual(entry.summary, "This is the reason")
    }

    func testSummaryWithoutReason() {
        let entry = CrashLogEntry(
            name: "NSException",
            reason: nil,
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        XCTAssertEqual(entry.summary, "NSException")
    }

    // MARK: - Full Report Tests

    func testFullReportContainsAllFields() {
        let entry = CrashLogEntry(
            name: "NSInvalidArgumentException",
            reason: "Test reason for crash",
            stackTrace: ["Frame 0: TestApp", "Frame 1: UIKit"],
            appVersion: "1.2.3",
            buildNumber: "456",
            osVersion: "17.2",
            deviceModel: "iPhone 15 Pro"
        )

        let report = entry.fullReport

        XCTAssertTrue(report.contains("Crash Report"))
        XCTAssertTrue(report.contains("NSInvalidArgumentException"))
        XCTAssertTrue(report.contains("Test reason for crash"))
        XCTAssertTrue(report.contains("Frame 0: TestApp"))
        XCTAssertTrue(report.contains("Frame 1: UIKit"))
        XCTAssertTrue(report.contains("1.2.3"))
        XCTAssertTrue(report.contains("456"))
        XCTAssertTrue(report.contains("17.2"))
        XCTAssertTrue(report.contains("iPhone 15 Pro"))
        XCTAssertTrue(report.contains("Stack Trace:"))
    }

    func testFullReportWithNilReason() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: nil,
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let report = entry.fullReport
        XCTAssertTrue(report.contains("Unknown"))
    }

    func testFullReportWithEmptyStackTrace() {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        let report = entry.fullReport
        XCTAssertTrue(report.contains("Stack Trace:"))
        // Stack trace section exists but has no frames
    }

    // MARK: - Sendable Tests

    func testSendableConformance() async {
        let entry = CrashLogEntry(
            name: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "17.0",
            deviceModel: "iPhone"
        )

        // Verify we can pass the entry across actor boundaries
        let result = await Task.detached {
            return entry.name
        }.value

        XCTAssertEqual(result, "TestException")
    }
}
#endif
