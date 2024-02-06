//
//  File.swift
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
    case dictionary(title: String?, data: [String: AnyObject])

    init(title: String?, from input: Any) {
        if let inputData = input as? Data, JSONSerialization.isValidJSONObject(inputData) {
            self = .json(title: title, data: inputData)
        } else if let inputData = input as? String {
            if let data = inputData.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                self = .json(title: title, data: json)
            } else {
                self = .string(title: title, data: inputData)
            }
        } else if let inputData = input as? Bool {
            self = .string(title: title, data: inputData.stringValue)
        } else if let inputData = input as? NSNumber {
            self = .string(title: title, data: "\(inputData)")
        } else if let inputData = input as? Date {
            self = .string(title: title, data: inputData.formatted())
        } else if let inputData = input as? [String] {
            self = .array(title: title, data: inputData)
        } else if let inputData = input as? [Data] {
            let certificates: [SecCertificate] = inputData.compactMap { SecCertificateCreateWithData(kCFAllocatorDefault, $0 as CFData) }
            if certificates.count > 1 {
                let certificateNames: [CFString] = certificates.compactMap { var name: CFString?; _ = SecCertificateCopyCommonName($0, &name); return name }
                self = .array(title: title, data: certificateNames.compactMap { String($0) })
            } else {
                self = .array(title: title, data: inputData.compactMap { String(data: $0, encoding: .utf8) })
            }
        } else if let inputData = input as? [String: AnyObject] {
            self = .dictionary(title: title, data: inputData)
        } else if input is NSNull {
            self = .string(title: title, data: "null")
        } else if input is NSArray {
            self = .string(title: nil, data: nil)
            if let jsonString = json(from: input as Any), let data = jsonString.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                self = .json(title: title, data: json)
            } else {
                self = .string(title: title, data: "Unsupported (\(type(of: input)))")
            }
        } else {
            self = .string(title: title, data: "Unsupported (\(type(of: input)))")
        }
    }

    private func json(from object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: String.Encoding.utf8)
    }

}
