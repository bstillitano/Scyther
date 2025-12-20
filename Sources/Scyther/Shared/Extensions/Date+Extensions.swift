//
//  Date+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

import Foundation

/// Provides convenient extensions for formatting Date objects.
///
/// This extension adds utility methods to convert Date instances into formatted string
/// representations using custom date format patterns.
extension Date {
    /// Returns a formatted string representation of the date.
    ///
    /// Converts the date into a string using the specified format pattern. If no format
    /// is provided, defaults to "dd/MM/yyyy hh:mm:ss".
    ///
    /// - Parameter format: A date format string following the Unicode Technical Standard #35.
    ///                     Defaults to `"dd/MM/yyyy hh:mm:ss"`.
    ///
    /// - Returns: A string representation of the date formatted according to the specified pattern.
    ///
    /// ## Example
    /// ```swift
    /// let date = Date()
    ///
    /// // Using default format
    /// let defaultFormatted = date.formatted()
    /// // Returns: "20/12/2025 02:30:45"
    ///
    /// // Using custom format
    /// let customFormatted = date.formatted(format: "yyyy-MM-dd")
    /// // Returns: "2025-12-20"
    ///
    /// // Another custom format
    /// let timeOnly = date.formatted(format: "HH:mm:ss")
    /// // Returns: "14:30:45"
    /// ```
    ///
    /// ## Common Format Patterns
    /// - `yyyy`: 4-digit year (e.g., 2025)
    /// - `MM`: 2-digit month (01-12)
    /// - `dd`: 2-digit day (01-31)
    /// - `HH`: 2-digit hour in 24-hour format (00-23)
    /// - `hh`: 2-digit hour in 12-hour format (01-12)
    /// - `mm`: 2-digit minute (00-59)
    /// - `ss`: 2-digit second (00-59)
    ///
    /// - Note: This method creates a new `DateFormatter` instance on each call.
    ///         For performance-critical code with many dates to format, consider
    ///         reusing a single `DateFormatter` instance.
    public func formatted(format: String = "dd/MM/yyyy hh:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
