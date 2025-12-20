//
//  Dictionary+Extensions.swift
//
//
//  Created by Brandon Stillitano on 31/8/21.
//

import Foundation

/// Provides convenient extensions for converting Dictionary objects to JSON strings.
///
/// This extension adds utility methods to serialize Dictionary instances into JSON-formatted
/// string representations.
extension Dictionary {
    /// Converts the dictionary to a JSON-formatted string.
    ///
    /// Serializes the dictionary into a JSON string using `JSONSerialization`. The resulting
    /// string uses ASCII encoding.
    ///
    /// - Returns: A JSON string representation of the dictionary, or `nil` if serialization fails.
    ///
    /// ## Example
    /// ```swift
    /// let userInfo: [String: Any] = [
    ///     "name": "John Doe",
    ///     "age": 30,
    ///     "active": true
    /// ]
    ///
    /// if let jsonString = userInfo.jsonString {
    ///     print(jsonString)
    ///     // Prints: {"name":"John Doe","age":30,"active":true}
    /// }
    /// ```
    ///
    /// - Note: This property will return `nil` if:
    ///   - The dictionary contains values that cannot be serialized to JSON
    ///   - The serialization process fails for any other reason
    ///   - The data cannot be encoded as ASCII
    ///
    /// - Important: Only dictionaries containing JSON-compatible types
    ///              (String, Number, Array, Dictionary, Bool, or nil) can be serialized.
    public var jsonString: String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: jsonData, encoding: String.Encoding.ascii)

    }
}

