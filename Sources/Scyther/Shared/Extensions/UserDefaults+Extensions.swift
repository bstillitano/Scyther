//
//  UserDefaults+Extensions.swift
//
//
//  Created by Brandon Stillitano on 18/12/20.
//

import Foundation

/// Provides convenient extensions for converting UserDefaults to string-based dictionaries.
///
/// This internal extension adds utility properties to convert UserDefaults key-value pairs
/// into a format suitable for display in debugging interfaces, where all values are
/// represented as strings.
internal extension UserDefaults {
    /// Returns a dictionary representation of UserDefaults with all values converted to strings.
    ///
    /// Converts the UserDefaults store into a `[String: String]` dictionary suitable for
    /// display in UI lists or debugging views. Different value types are handled as follows:
    /// - String values: Passed through unchanged
    /// - Bool values: Converted to "true" or "false"
    /// - Array values: Converted to "{count} elements"
    /// - Other types: Excluded from the result
    ///
    /// - Returns: A dictionary mapping UserDefaults keys to their string representations
    ///
    /// ## Example
    /// ```swift
    /// // Given UserDefaults with these values:
    /// // "username" = "John"
    /// // "isLoggedIn" = true
    /// // "recentSearches" = ["Swift", "iOS", "Xcode"]
    ///
    /// let dict = UserDefaults.standard.stringStringDictionaryRepresentation
    /// // Returns:
    /// // [
    /// //   "username": "John",
    /// //   "isLoggedIn": "true",
    /// //   "recentSearches": "3 elements"
    /// // ]
    /// ```
    ///
    /// - Note: This property is used internally by Scyther's UserDefaults browser to
    ///         display all stored preferences in a readable format.
    ///
    /// - Important: Complex types (dictionaries, custom objects, etc.) are not included
    ///              in the output as they cannot be meaningfully represented as simple strings.
    var stringStringDictionaryRepresentation: [String: String] {
        var dictionary: [String: String] = [:]
        for keyValuePair in dictionaryRepresentation() {
            /// Setup Data
            var value: String?

            /// Check Value Type
            switch keyValuePair.value {
            case is String:
                value = keyValuePair.value as? String

            case is Bool:
                value = (keyValuePair.value as? Bool)?.stringValue

            case is Array<Any>:
                value = "\((keyValuePair.value as? Array<Any>)?.count ?? 0) elements"
            default:
                break
            }

            /// Set K/V Data
            dictionary[keyValuePair.key] = value
        }
        return dictionary
    }
}
