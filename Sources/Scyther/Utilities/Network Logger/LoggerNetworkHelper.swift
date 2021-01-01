//
//  ScytherNetworkHelper.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// Enum representing different HTTP request/response models
public enum HTTPModelShortType: String, CaseIterable {
    case JSON = "JSON"
    case XML = "XML"
    case HTML = "HTML"
    case IMAGE = "Image"
    case OTHER = "Other"
}

extension URLRequest {
    var urlString: String {
        return url?.absoluteString ?? "-"
    }

    var urlComponents: URLComponents? {
        guard let url = self.url else {
            return nil
        }
        return URLComponents(string: url.absoluteString)
    }

    var method: String {
        return httpMethod ?? "-"
    }

    var cachePolicyString: String {
        switch cachePolicy {
        case .useProtocolCachePolicy:
            return "UseProtocolCachePolicy"
        case .reloadIgnoringLocalCacheData:
            return "ReloadIgnoringLocalCacheData"
        case .reloadIgnoringLocalAndRemoteCacheData:
            return "ReloadIgnoringLocalAndRemoteCacheData"
        case .returnCacheDataElseLoad:
            return "ReturnCacheDataElseLoad"
        case .returnCacheDataDontLoad:
            return "ReturnCacheDataDontLoad"
        case .reloadRevalidatingCacheData:
            return "ReloadRevalidatingCacheData"
        @unknown default:
            return "Unknown \(cachePolicy)"
        }
    }

    var timeout: String {
        return String(Double(timeoutInterval))
    }

    var headers: [AnyHashable: Any] {
        return allHTTPHeaderFields ?? [:]
    }

    var body: Data? {
        return httpBodyStream?.readfully() ?? URLProtocol.property(forKey: "ScytherBodyData", in: self) as? Data
    }

    var curlString: String {
        /// Check for `url` value, otherwise return empty string
        guard let url = url else {
            return ""
        }

        /// Construct curl command
        let baseCommand = "curl \u{22}\(url.absoluteString)\u{22}"
        var commands = [baseCommand]

        /// Check method and append onto commands array
        if let method = httpMethod {
            commands.append("-X \(method)")
        }

        /// Append all headers
        for (key, value) in headers {
            commands.append("-H \u{22}\(key): \(value)\u{22}")
        }

        /// Append Conditional Body
        guard let requestBody: Data = body,
            let body = String(data: requestBody, encoding: .utf8) else {
            return commands.joined(separator: " ")
        }
        commands.append("-d \u{22}\(body)\u{22}")

        return commands.joined(separator: " ")
    }
}

extension URLResponse {
    var statusCodeInt: Int {
        return (self as? HTTPURLResponse)?.statusCode ?? 999
    }

    var headers: [AnyHashable: Any] {
        return (self as? HTTPURLResponse)?.allHeaderFields ?? [:]
    }
}

extension InputStream {
    func readfully() -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        open()

        var amount = 0
        repeat {
            amount = read(&buffer, maxLength: buffer.count)
            if amount > 0 {
                result.append(buffer, count: amount)
            }
        } while amount > 0

        close()

        return result
    }
}

extension String {
    func appendToFile(filePath: String) {
        let contentToAppend = self

        /// Create file or append to file
        if let fileHandle = FileHandle(forWritingAtPath: filePath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(contentToAppend.data(using: String.Encoding.utf8) ?? Data())
        } else {
            do {
                try contentToAppend.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error creating \(filePath)")
            }
        }
    }
}

public extension NSNotification.Name {
    static let LoggerDeactivateSearch = Notification.Name("LoggerDeactivateSearch")
    static let LoggerReloadData = Notification.Name("LoggerReloadData")
    static let LoggerAddedModel = Notification.Name("LoggerAddedModel")
    static let LoggerClearedModels = Notification.Name("LoggerClearedModels")
}
