//
//  DataRow.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

/// Internal enum representing different types of data for presentation in the data browser.
///
/// `DataRow` intelligently parses various data types (strings, JSON, arrays, dictionaries, etc.)
/// and converts them into a consistent format for display. It handles type detection,
/// JSON parsing, and special cases like certificates and boolean values.
///
/// ## Topics
/// ### Cases
/// - ``string(title:data:)``
/// - ``json(title:data:)``
/// - ``array(title:data:)``
/// - ``dictionary(title:data:)``
///
/// ### Creating a Data Row
/// - ``init(title:from:)``
internal enum DataRow {
    /// A simple string value.
    ///
    /// - Parameters:
    ///   - title: The display title for this data row.
    ///   - data: The string content.
    case string(title: String?, data: String?)

    /// A JSON-encoded value (array or object).
    ///
    /// - Parameters:
    ///   - title: The display title for this data row.
    ///   - data: The parsed JSON data.
    case json(title: String?, data: Any)

    /// An array of strings.
    ///
    /// - Parameters:
    ///   - title: The display title for this data row.
    ///   - data: The array of string values.
    case array(title: String?, data: [String])

    /// A dictionary of key-value pairs.
    ///
    /// - Parameters:
    ///   - title: The display title for this data row.
    ///   - data: The dictionary data.
    case dictionary(title: String?, data: [String: Any])

    /// Creates a data row by intelligently parsing the input value.
    ///
    /// This initializer automatically detects the type of the input and converts it
    /// to the most appropriate `DataRow` case. It handles:
    /// - Data objects (attempts JSON parsing, falls back to string or byte count)
    /// - Strings (attempts JSON parsing, falls back to plain string)
    /// - NSNumber (distinguishes between booleans and numbers)
    /// - Dates, URLs, and null values
    /// - Arrays and dictionaries (both Swift and Foundation types)
    /// - Certificate data arrays
    ///
    /// - Parameters:
    ///   - title: The display title for this data row.
    ///   - input: The raw data to parse and format.
    init(title: String?, from input: Any) {
        // Handle Data - try to parse as JSON
        if let inputData = input as? Data {
            if let json = try? JSONSerialization.jsonObject(with: inputData, options: []) {
                self = .json(title: title, data: json)
            } else if let string = String(data: inputData, encoding: .utf8) {
                self = .string(title: title, data: string)
            } else {
                self = .string(title: title, data: "<\(inputData.count) bytes>")
            }
        }
        // Handle String - try to parse as JSON, fallback to plain string
        else if let inputData = input as? String {
            if let data = inputData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                self = .json(title: title, data: json)
            } else {
                self = .string(title: title, data: inputData)
            }
        }
        // Handle NSNumber - distinguish between Bool and numeric types
        else if let inputData = input as? NSNumber {
            if CFGetTypeID(inputData) == CFBooleanGetTypeID() {
                self = .string(title: title, data: inputData.boolValue ? "true" : "false")
            } else {
                self = .string(title: title, data: "\(inputData)")
            }
        }
        // Handle null
        else if input is NSNull {
            self = .string(title: title, data: "null")
        }
        // Handle Date
        else if let inputData = input as? Date {
            self = .string(title: title, data: inputData.formatted())
        }
        // Handle URL
        else if let inputData = input as? URL {
            self = .string(title: title, data: inputData.absoluteString)
        }
        // Handle dictionaries (both Swift and Foundation types)
        else if let inputData = input as? [String: Any] {
            self = .dictionary(title: title, data: inputData)
        }
        else if let inputData = input as? NSDictionary {
            var dict: [String: Any] = [:]
            for (key, value) in inputData {
                if let stringKey = key as? String {
                    dict[stringKey] = value
                }
            }
            self = .dictionary(title: title, data: dict)
        }
        // Handle arrays (both Swift and Foundation types)
        else if let inputData = input as? [Any] {
            self = .json(title: title, data: inputData)
        }
        else if let inputData = input as? NSArray {
            self = .json(title: title, data: Array(inputData))
        }
        // Handle certificate data arrays
        else if let inputData = input as? [Data] {
            let certificates: [SecCertificate] = inputData.compactMap {
                SecCertificateCreateWithData(kCFAllocatorDefault, $0 as CFData)
            }
            if !certificates.isEmpty {
                let certificateNames: [String] = certificates.compactMap {
                    var name: CFString?
                    _ = SecCertificateCopyCommonName($0, &name)
                    return name as String?
                }
                self = .array(title: title, data: certificateNames)
            } else {
                self = .array(title: title, data: inputData.compactMap { String(data: $0, encoding: .utf8) })
            }
        }
        // Handle string arrays
        else if let inputData = input as? [String] {
            self = .array(title: title, data: inputData)
        }
        // Fallback for unsupported types
        else {
            self = .string(title: title, data: "Unsupported (\(type(of: input)))")
        }
    }
}
