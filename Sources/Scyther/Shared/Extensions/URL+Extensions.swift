//
//  URL+Extensions.swift
//
//
//  Created by Brandon Stillitano on 18/1/21.
//

import Foundation

/// Provides convenient extensions for URL path constants.
///
/// This extension adds utility properties for accessing common file system locations
/// used by Scyther, particularly for logging and debugging purposes.
extension URL {
    /// The URL for the console log file used by Scyther's ConsoleLogger.
    ///
    /// Returns the path to the console.log file in the app's documents directory.
    /// This file is used to capture and store console output for debugging purposes.
    ///
    /// - Returns: A URL pointing to the console log file, or `nil` if the documents
    ///            directory cannot be accessed.
    ///
    /// ## Example
    /// ```swift
    /// if let logURL = URL.consoleLogURL {
    ///     // Read console logs
    ///     let logs = try? String(contentsOf: logURL)
    ///     print(logs)
    ///
    ///     // Share logs via activity controller
    ///     let activityVC = UIActivityViewController(
    ///         activityItems: [logURL],
    ///         applicationActivities: nil
    ///     )
    /// }
    /// ```
    ///
    /// ## File Location
    /// The file is stored at:
    /// ```
    /// <Application_Home>/Documents/console.log
    /// ```
    ///
    /// - Note: This file is created and managed by the ConsoleLogger class.
    ///         It may not exist until logging is enabled.
    ///
    /// - Important: The file is stored in the Documents directory, which means it:
    ///   - Will be backed up by iTunes/iCloud (unless excluded)
    ///   - Can be accessed via Files app when file sharing is enabled
    ///   - Persists across app launches
    internal static var consoleLogURL: URL? {
        // Get local document directory
        guard let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return nil
        }
        let documentsDirectory = NSURL(fileURLWithPath: documentsPath)

        // Construct log path
        guard let logPath = documentsDirectory.appendingPathComponent("console.log") else {
            return nil
        }
        return logPath
    }
}
