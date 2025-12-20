//
//  LoggerFilePath.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// Provides file paths used by the network logger for storing log files.
///
/// This struct centralizes file path management for the network logging system,
/// providing consistent access to the documents directory and session log file location.
struct LoggerFilePath {
    /// Returns the path to the documents directory.
    ///
    /// This property safely accesses the documents directory path. If no directory
    /// is available, it returns an empty string rather than crashing.
    ///
    /// - Returns: The documents directory path as an `NSString`, or an empty string if unavailable.
    static var Documents: NSString {
        guard let documentPath = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory,
                                                                     FileManager.SearchPathDomainMask.allDomainsMask,
                                                                     true).first as NSString? else {
            return ""
        }
        return documentPath
    }

    /// The full file path for the network session log file.
    ///
    /// This file contains formatted text logs of all network requests and responses
    /// captured during the application's lifetime.
    static let SessionLog = LoggerFilePath.Documents.appendingPathComponent("SessionLog.log");
}
