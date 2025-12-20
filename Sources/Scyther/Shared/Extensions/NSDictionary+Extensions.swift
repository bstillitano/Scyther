//
//  NSDictionary+Extensions.swift
//
//
//  Created by Brandon Stillitano on 20/9/21.
//

import Foundation

/// Provides convenient extensions for converting NSDictionary to Swift Dictionary.
///
/// This extension adds utility properties to bridge between Objective-C NSDictionary
/// and Swift's native Dictionary type.
extension NSDictionary {
    /// Converts the NSDictionary to a Swift Dictionary with String keys.
    ///
    /// Iterates through all keys in the NSDictionary and converts them to a Swift Dictionary.
    /// Only keys that can be cast to String are included in the resulting dictionary.
    /// Non-string keys are silently skipped.
    ///
    /// - Returns: A Swift Dictionary with String keys and Any values.
    ///
    /// ## Example
    /// ```swift
    /// let objcDict = NSDictionary(dictionary: [
    ///     "name": "John Doe",
    ///     "age": 30,
    ///     "active": true
    /// ])
    ///
    /// let swiftDict = objcDict.swiftDictionary
    /// print(swiftDict["name"]) // Prints Optional("John Doe")
    /// ```
    ///
    /// - Note: This property only includes keys that can be cast to String.
    ///         Keys of other types are filtered out during the conversion.
    var swiftDictionary: Dictionary<String, Any> {
        var swiftDictionary = Dictionary<String, Any>()

        for key: Any in self.allKeys {
            guard let stringKey = key as? String else {
                continue
            }
            if let keyValue = self.value(forKey: stringKey) {
                swiftDictionary[stringKey] = keyValue
            }
        }

        return swiftDictionary
    }
}
