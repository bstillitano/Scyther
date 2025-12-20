//
//  Float+Extensions.swift
//
//
//  Created by Brandon Stillitano on 7/4/2024.
//

import Foundation

/// Provides convenient extensions for converting Float values to strings.
///
/// This extension adds utility properties to convert Float values to string representations
/// with various formatting options, particularly useful for UI display.
extension Float {
    /// Returns a string representation of this value with smart decimal handling.
    ///
    /// If the float has no fractional part (e.g., 5.0), returns the value without decimals.
    /// If the float has a fractional part (e.g., 5.7), returns the full value as a string.
    ///
    /// - Returns: A string representation of the float, formatted based on whether it has decimals.
    ///
    /// ## Example
    /// ```swift
    /// let wholeNumber: Float = 5.0
    /// print(wholeNumber.clean) // Prints "5"
    ///
    /// let decimal: Float = 5.7
    /// print(decimal.clean) // Prints "5.7"
    ///
    /// let anotherDecimal: Float = 3.14159
    /// print(anotherDecimal.clean) // Prints "3.14159"
    /// ```
    var clean: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }

    /// Returns only the integer part of the float as a string, truncating any decimal places.
    ///
    /// This property converts the float to an integer by truncating (not rounding) the decimal
    /// portion, then returns the result as a string.
    ///
    /// - Returns: A string containing only the integer portion of the float.
    ///
    /// ## Example
    /// ```swift
    /// let value: Float = 5.9
    /// print(value.withoutDecimals) // Prints "5"
    ///
    /// let negative: Float = -3.7
    /// print(negative.withoutDecimals) // Prints "-3"
    ///
    /// let wholeNumber: Float = 42.0
    /// print(wholeNumber.withoutDecimals) // Prints "42"
    /// ```
    ///
    /// - Note: This property truncates rather than rounds. For example, 5.9 becomes "5", not "6".
    var withoutDecimals: String {
        return String(Int(self))
    }
}
