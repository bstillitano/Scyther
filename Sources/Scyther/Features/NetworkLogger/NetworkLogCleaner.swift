//
//  NetworkLogCleaner.swift
//
//
//  Created by Brandon Stillitano on 01/01/26.
//

import Foundation

/// Manages cleanup of network log files stored on disk.
///
/// `NetworkLogCleaner` provides mechanisms to remove old or all network log files
/// from the app's Documents directory. It handles both time-based retention policies
/// and manual cleanup operations.
///
/// ## Features
/// - Automatic cleanup of files older than the retention period
/// - Manual deletion of all log files
/// - Thread-safe operations via `@MainActor`
///
/// ## File Types Managed
/// - `SessionLog.log` - Main session log file
/// - `logger_request_body_*` - Individual request body files
/// - `logger_response_body_*` - Individual response body files
///
/// ## Usage
/// ```swift
/// // Clean up old logs (called automatically on Scyther.start())
/// NetworkLogCleaner.shared.cleanupOldLogs()
///
/// // Delete all log files
/// NetworkLogCleaner.shared.deleteAllLogFiles()
/// ```
@MainActor
final class NetworkLogCleaner {
    /// Shared instance of the network log cleaner.
    static let shared = NetworkLogCleaner()

    /// The number of days to retain log files before deletion.
    ///
    /// Files older than this threshold will be automatically deleted
    /// when `cleanupOldLogs()` is called.
    static let retentionDays: Int = 7

    /// Private initializer to enforce singleton pattern.
    private init() {}

    /// Deletes network log files older than the retention period.
    ///
    /// This method scans the Documents directory for network log files
    /// (request bodies, response bodies, and session log) and deletes
    /// any that were created more than `retentionDays` ago.
    ///
    /// The cleanup is performed synchronously but is designed to be
    /// lightweight and fast, making it suitable for app startup.
    func cleanupOldLogs() {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? Date()

        do {
            let files = try fileManager.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            for fileURL in files {
                let fileName = fileURL.lastPathComponent

                // Check if this is a network log file
                guard isNetworkLogFile(fileName) else {
                    continue
                }

                // Get file creation date
                guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let creationDate = attributes[.creationDate] as? Date else {
                    continue
                }

                // Delete if older than retention period
                if creationDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Silently handle errors - cleanup is best-effort
        }
    }

    /// Deletes all network log files from disk.
    ///
    /// This method removes all network log files regardless of age,
    /// including:
    /// - All request body files (`logger_request_body_*`)
    /// - All response body files (`logger_response_body_*`)
    /// - The session log file (`SessionLog.log`)
    ///
    /// This is called when the user manually clears the network logs.
    func deleteAllLogFiles() {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            for fileURL in files {
                let fileName = fileURL.lastPathComponent

                if isNetworkLogFile(fileName) {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Silently handle errors - cleanup is best-effort
        }
    }

    /// Determines whether a file is a network log file based on its name.
    ///
    /// - Parameter fileName: The name of the file to check.
    /// - Returns: `true` if the file is a network log file, `false` otherwise.
    private func isNetworkLogFile(_ fileName: String) -> Bool {
        return fileName.hasPrefix("logger_request_body_") ||
               fileName.hasPrefix("logger_response_body_") ||
               fileName == "SessionLog.log"
    }
}
