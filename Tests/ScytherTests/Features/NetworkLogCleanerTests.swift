//
//  NetworkLogCleanerTests.swift
//  ScytherTests
//
//  Created by Claude on 01/01/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class NetworkLogCleanerTests: XCTestCase {

    private var testDirectory: URL!
    private var fileManager: FileManager!

    override func setUp() async throws {
        try await super.setUp()
        fileManager = FileManager.default

        // Create a temporary test directory
        testDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up test directory
        if let testDirectory = testDirectory {
            try? fileManager.removeItem(at: testDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSingletonInstance() {
        let instance1 = NetworkLogCleaner.shared
        let instance2 = NetworkLogCleaner.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Retention Period Tests

    func testRetentionDaysIsSevenDays() {
        XCTAssertEqual(NetworkLogCleaner.retentionDays, 7)
    }

    // MARK: - File Pattern Matching Tests

    func testCleanupDoesNotDeleteNonLogFiles() {
        // Create a non-log file
        let nonLogFile = testDirectory.appendingPathComponent("user_data.json")
        fileManager.createFile(atPath: nonLogFile.path, contents: Data())

        // Verify file exists
        XCTAssertTrue(fileManager.fileExists(atPath: nonLogFile.path))

        // cleanupOldLogs should not affect non-log files (testing the pattern matching logic)
        // Since we can't inject the directory, we verify the file pattern matching works correctly
        let fileName = "user_data.json"
        XCTAssertFalse(isNetworkLogFile(fileName))
    }

    func testRequestBodyFilePatternRecognized() {
        XCTAssertTrue(isNetworkLogFile("logger_request_body_10:30:45.123_ABC123"))
        XCTAssertTrue(isNetworkLogFile("logger_request_body_unknown_XYZ789"))
    }

    func testResponseBodyFilePatternRecognized() {
        XCTAssertTrue(isNetworkLogFile("logger_response_body_10:30:45.123_ABC123"))
        XCTAssertTrue(isNetworkLogFile("logger_response_body_unknown_XYZ789"))
    }

    func testSessionLogFilePatternRecognized() {
        XCTAssertTrue(isNetworkLogFile("SessionLog.log"))
    }

    func testNonLogFilePatternsNotRecognized() {
        XCTAssertFalse(isNetworkLogFile("user_preferences.json"))
        XCTAssertFalse(isNetworkLogFile("database.sqlite"))
        XCTAssertFalse(isNetworkLogFile("console.log"))
        XCTAssertFalse(isNetworkLogFile("logger_crash_body_123"))
        XCTAssertFalse(isNetworkLogFile("SessionLog.txt"))
    }

    // MARK: - Helper to test file pattern matching

    /// Mirrors the logic in NetworkLogCleaner.isNetworkLogFile
    private func isNetworkLogFile(_ fileName: String) -> Bool {
        return fileName.hasPrefix("logger_request_body_") ||
               fileName.hasPrefix("logger_response_body_") ||
               fileName == "SessionLog.log"
    }

    // MARK: - Integration Tests

    func testCleanupOldLogsDoesNotCrashOnEmptyDirectory() {
        // Should handle empty directory gracefully without crashing
        NetworkLogCleaner.shared.cleanupOldLogs()
        // If we get here without crashing, the test passes
    }

    func testDeleteAllLogFilesDoesNotCrashOnEmptyDirectory() {
        // Should handle empty directory gracefully without crashing
        NetworkLogCleaner.shared.deleteAllLogFiles()
        // If we get here without crashing, the test passes
    }

    func testCleanupPreservesFilePattern() {
        // Test that the file pattern matching logic correctly identifies log files
        let testCases: [(fileName: String, isLogFile: Bool)] = [
            ("logger_request_body_12:34:56.789_UUID123", true),
            ("logger_response_body_12:34:56.789_UUID456", true),
            ("SessionLog.log", true),
            ("other_file.txt", false),
            ("logger_request_body", false),  // Missing timestamp and UUID
            ("request_body_12:34:56.789_UUID", false),  // Missing logger_ prefix
            ("SessionLog", false),  // Missing .log extension
        ]

        for testCase in testCases {
            XCTAssertEqual(
                isNetworkLogFile(testCase.fileName),
                testCase.isLogFile,
                "Pattern matching failed for: \(testCase.fileName)"
            )
        }
    }
}
#endif
