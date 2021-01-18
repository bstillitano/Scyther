//
//  ConsoleLogger.swift
//
//
//  Created by Brandon Stillitano on 18/1/21.
//

import Foundation

public class ConsoleLogger {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `ConfigurationSwitcher` class.
    static let instance = ConsoleLogger()

    /// Essentialy "starts" the logger by telling the system to start writing console output to a local file.
    internal func start() {
        // Check for log file availability
        guard let logURL: URL = URL.consoleLogURL else {
            return
        }

        // Try deleting existing file in an effort to try and keep the library/documents folder clean.
        try? FileManager.default.removeItem(at: logURL)

        // Start capturing output
        freopen(logURL.absoluteString, "a+", stdout)
    }

    /// String representation of the log file
    internal var logContents: String? {
        // Check for log file availability
        guard let logURL: URL = URL.consoleLogURL else {
            return nil
        }
        return try? String(contentsOf: logURL, encoding: .utf8)
    }
}
