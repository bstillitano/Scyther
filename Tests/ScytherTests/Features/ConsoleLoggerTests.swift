//
//  ConsoleLoggerTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class ConsoleLoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Stop any ongoing capture and clear logs before each test
        ConsoleLogger.instance.stop()
        ConsoleLogger.instance.clear()
    }

    override func tearDown() {
        // Ensure we stop capturing after each test
        ConsoleLogger.instance.stop()
        ConsoleLogger.instance.clear()
        super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSingletonInstance() {
        let instance1 = ConsoleLogger.instance
        let instance2 = ConsoleLogger.instance
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertFalse(ConsoleLogger.instance.isCapturing)
        XCTAssertTrue(ConsoleLogger.instance.allLogs.isEmpty)
    }

    // MARK: - Start/Stop Tests

    func testStartSetsIsCapturing() {
        ConsoleLogger.instance.start()
        XCTAssertTrue(ConsoleLogger.instance.isCapturing)
        ConsoleLogger.instance.stop()
    }

    func testStopClearsIsCapturing() {
        ConsoleLogger.instance.start()
        ConsoleLogger.instance.stop()
        XCTAssertFalse(ConsoleLogger.instance.isCapturing)
    }

    func testStartMultipleTimesNoEffect() {
        ConsoleLogger.instance.start()
        ConsoleLogger.instance.start()
        ConsoleLogger.instance.start()
        XCTAssertTrue(ConsoleLogger.instance.isCapturing)
        ConsoleLogger.instance.stop()
    }

    func testStopWhenNotCapturingNoEffect() {
        XCTAssertFalse(ConsoleLogger.instance.isCapturing)
        ConsoleLogger.instance.stop()
        XCTAssertFalse(ConsoleLogger.instance.isCapturing)
    }

    // MARK: - Clear Tests

    func testClearEmptiesLogs() {
        ConsoleLogger.instance.clear()
        XCTAssertTrue(ConsoleLogger.instance.allLogs.isEmpty)
    }

    // MARK: - Notification Tests

    func testClearPostsNotification() {
        let expectation = XCTestExpectation(description: "Notification posted")

        let observer = NotificationCenter.default.addObserver(
            forName: .ConsoleLoggerDidLog,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        ConsoleLogger.instance.clear()

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - ConsoleLogEntry Tests

final class ConsoleLogEntryTests: XCTestCase {

    func testEntryInitialization() {
        let entry = ConsoleLogEntry(
            timestamp: Date(),
            message: "Test message",
            source: .stdout
        )

        XCTAssertEqual(entry.message, "Test message")
        XCTAssertEqual(entry.source, .stdout)
        XCTAssertNotNil(entry.id)
    }

    func testEntryWithStderr() {
        let entry = ConsoleLogEntry(
            timestamp: Date(),
            message: "Error message",
            source: .stderr
        )

        XCTAssertEqual(entry.source, .stderr)
        XCTAssertEqual(entry.source.rawValue, "stderr")
    }

    func testLogSourceRawValues() {
        XCTAssertEqual(ConsoleLogEntry.LogSource.stdout.rawValue, "stdout")
        XCTAssertEqual(ConsoleLogEntry.LogSource.stderr.rawValue, "stderr")
    }

    func testFormattedTimestamp() {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 21
        components.hour = 10
        components.minute = 30
        components.second = 45

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let entry = ConsoleLogEntry(
            timestamp: date,
            message: "Test",
            source: .stdout
        )

        let formatted = entry.formattedTimestamp
        XCTAssertFalse(formatted.isEmpty)
    }

    func testEquatable() {
        let date = Date()
        let entry1 = ConsoleLogEntry(timestamp: date, message: "Test", source: .stdout)
        let entry2 = ConsoleLogEntry(timestamp: date, message: "Test", source: .stdout)

        // Different IDs mean they're not equal
        XCTAssertNotEqual(entry1, entry2)

        // Same entry should equal itself
        XCTAssertEqual(entry1, entry1)
    }

    func testIdentifiable() {
        let entry = ConsoleLogEntry(
            timestamp: Date(),
            message: "Test",
            source: .stdout
        )

        // Verify UUID is created
        XCTAssertNotNil(entry.id)
    }

    func testDifferentEntriesHaveUniqueIds() {
        let entry1 = ConsoleLogEntry(timestamp: Date(), message: "Message 1", source: .stdout)
        let entry2 = ConsoleLogEntry(timestamp: Date(), message: "Message 2", source: .stdout)

        XCTAssertNotEqual(entry1.id, entry2.id)
    }
}
#endif
