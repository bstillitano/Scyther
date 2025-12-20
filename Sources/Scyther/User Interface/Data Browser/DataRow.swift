//
//  DataRow.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

/// Internal enum used to represent different types of presentable data
internal enum DataRow {
    case string(title: String?, data: String?)
    case json(title: String?, data: Any)
    case array(title: String?, data: [String])
    case dictionary(title: String?, data: [String: Any])

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
