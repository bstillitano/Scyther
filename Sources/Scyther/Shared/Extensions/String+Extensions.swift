//
//  String+Extensions.swift
//  MYTUtilityKit
//
//  Created by Brandon Stillitano on 4/12/20.
//

import Foundation

/// Provides convenient extensions for String manipulation and conversion.
///
/// This extension adds utility methods for string manipulation, JSON parsing, and
/// pattern searching within string values.
public extension String {
    /// Replaces all occurrences of an array of strings with the provided replacement string.
    ///
    /// This method iterates through each string in the provided array and replaces all
    /// occurrences of it with the specified replacement string.
    ///
    /// - Parameters:
    ///   - characters: The array of string values to be replaced
    ///   - replacement: The string to use as the replacement for each occurrence
    ///
    /// - Returns: A new string with all occurrences of the specified strings replaced
    ///
    /// - Complexity: O(*n*) where *n* is the number of strings in the `characters` array.
    ///
    /// ## Example
    /// ```swift
    /// let deviceModel = "iPhone12,3"
    /// let cleaned = deviceModel.replacingOccurences(
    ///     of: ["iPhone", "iPad", "iPod"],
    ///     with: ""
    /// )
    /// print(cleaned) // Prints "12,3"
    /// ```
    func replacingOccurences(of characters: [String], with replacement: String) -> String {
        //Setup Data
        var newValue: String = self

        //Iterate Characters
        characters.forEach { string in
            newValue = newValue.replacingOccurrences(of: string, with: replacement)
        }

        return newValue
    }

    /// Parses this string as a JSON object and returns it as a dictionary.
    ///
    /// Attempts to deserialize the string as JSON and convert it to a dictionary with
    /// String keys and Any values. Returns `nil` if the string is not valid JSON or
    /// cannot be represented as a dictionary.
    ///
    /// - Returns: A dictionary representation of the JSON string, or `nil` if parsing fails
    ///
    /// ## Example
    /// ```swift
    /// let jsonString = """
    /// {"name": "John", "age": 30, "active": true}
    /// """
    ///
    /// if let dict = jsonString.dictionaryRepresentation {
    ///     print(dict["name"]) // Prints Optional("John")
    ///     print(dict["age"])  // Prints Optional(30)
    /// }
    /// ```
    ///
    /// - Note: This property uses `.mutableContainers` option for JSON deserialization.
    var dictionaryRepresentation: [String: Any]? {
        if let data = self.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any]
                return json
            } catch {
                logMessage("Something went wrong")
            }
        }
        return nil
    }

    /// Parses this string as JSON and returns the result as either an array or dictionary.
    ///
    /// Attempts to deserialize the string as JSON without assuming a specific structure.
    /// The result can be a dictionary, array, or any other JSON-compatible type.
    ///
    /// - Returns: The parsed JSON object (Array, Dictionary, String, Number, etc.), or `nil` if parsing fails
    ///
    /// ## Example
    /// ```swift
    /// // Parsing a JSON array
    /// let arrayString = """
    /// [{"id": 1}, {"id": 2}]
    /// """
    /// if let array = arrayString.jsonRepresentation as? [[String: Any]] {
    ///     print(array.count) // Prints 2
    /// }
    ///
    /// // Parsing a JSON object
    /// let objectString = """
    /// {"status": "success", "count": 5}
    /// """
    /// if let object = objectString.jsonRepresentation as? [String: Any] {
    ///     print(object["status"]) // Prints Optional("success")
    /// }
    /// ```
    ///
    /// - Note: This property uses `.mutableContainers` option for JSON deserialization.
    var jsonRepresentation: Any? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .mutableContainers)
    }

    /// Finds all ranges of a substring within this string.
    ///
    /// This internal method searches for all occurrences of a substring and returns
    /// an array of their ranges within the string.
    ///
    /// - Parameters:
    ///   - substring: The substring to search for
    ///   - options: String comparison options (case sensitivity, etc.)
    ///   - locale: The locale to use for comparisons
    ///
    /// - Returns: An array of ranges where the substring was found
    ///
    /// ## Example
    /// ```swift
    /// let text = "Hello world, hello Swift"
    /// let ranges = text.ranges(of: "hello", options: .caseInsensitive)
    /// print(ranges.count) // Prints 2
    /// ```
    internal func ranges(of substring: String, options: CompareOptions = [], locale: Locale? = nil) -> [Range<Index>] {
        var ranges: [Range<Index>] = []
        while let range = range(of: substring, options: options, range: (ranges.last?.upperBound ?? self.startIndex)..<self.endIndex, locale: locale) {
            ranges.append(range)
        }
        return ranges
    }
}
