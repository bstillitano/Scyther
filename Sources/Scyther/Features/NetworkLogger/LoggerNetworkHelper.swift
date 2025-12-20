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

/// Categorizes HTTP responses by their content type.
///
/// This enum provides a simplified classification of HTTP response types
/// based on the `Content-Type` header. It's used for filtering and displaying
/// network logs in the Scyther debug interface.
///
/// ## Example
/// ```swift
/// let type = HTTPModelShortType.JSON
/// print(type.rawValue) // "JSON"
/// ```
public enum HTTPModelShortType: String, CaseIterable {
    /// JSON response (application/json or variants like application/vnd.api+json).
    case JSON = "JSON"

    /// XML response (application/xml or text/xml).
    case XML = "XML"

    /// HTML response (text/html).
    case HTML = "HTML"

    /// Image response (any image/* content type).
    case IMAGE = "Image"

    /// Any other response type not covered by the above categories.
    case OTHER = "Other"
}

/// Extension providing helper properties for `URLRequest` used by the network logger.
///
/// These properties extract and format various aspects of a URL request for logging purposes,
/// including URL components, headers, body data, and cURL command generation.
extension URLRequest {
    /// Returns the absolute URL string, or "-" if unavailable.
    var urlString: String {
        return url?.absoluteString ?? "-"
    }

    /// Returns the URL components for parsing query parameters and other URL parts.
    ///
    /// - Returns: `URLComponents` if the URL can be parsed, otherwise `nil`.
    var urlComponents: URLComponents? {
        guard let url = self.url else {
            return nil
        }
        return URLComponents(string: url.absoluteString)
    }

    /// Returns the HTTP method as a string, or "-" if unavailable.
    var method: String {
        return httpMethod ?? "-"
    }

    /// Returns a human-readable string representation of the cache policy.
    ///
    /// - Returns: A string describing the cache policy (e.g., "UseProtocolCachePolicy").
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

    /// Returns the timeout interval as a string.
    var timeout: String {
        return String(Double(timeoutInterval))
    }

    /// Returns all HTTP headers as a dictionary.
    ///
    /// - Returns: Dictionary of header fields, or an empty dictionary if none exist.
    var headers: [AnyHashable: Any] {
        return allHTTPHeaderFields ?? [:]
    }

    /// Returns the HTTP body data.
    ///
    /// This property attempts to retrieve body data from either the body stream or
    /// from a property previously set by the network logger protocol.
    ///
    /// - Returns: The body data if available, otherwise `nil`.
    var body: Data? {
        return httpBodyStream?.readfully() ?? URLProtocol.property(forKey: "ScytherBodyData", in: self) as? Data
    }

    /// Returns a cURL command string that can be used to reproduce this request.
    ///
    /// This property generates a complete cURL command including the URL, HTTP method,
    /// headers, and body data. Useful for debugging and sharing network requests.
    ///
    /// ## Example
    /// ```swift
    /// let request = URLRequest(url: URL(string: "https://api.example.com")!)
    /// print(request.curlString)
    /// // Output: curl 'https://api.example.com' -X GET -H 'Accept: application/json'
    /// ```
    ///
    /// - Returns: A formatted cURL command string, or an empty string if the URL is unavailable.
    var curlString: String {
        /// Check for `url` value, otherwise return empty string
        guard let url = url else {
            return ""
        }

        /// Construct curl command
        let baseCommand = "curl \u{27}\(url.absoluteString)\u{27}"
        var commands = [baseCommand]

        /// Check method and append onto commands array
        if let method = httpMethod {
            commands.append("-X \(method)")
        }

        /// Append all headers
        for (key, value) in headers {
            commands.append("-H \u{27}\(key): \(value)\u{27}")
        }

        /// Append Conditional Body
        guard let requestBody: Data = body,
            let body = String(data: requestBody, encoding: .utf8) else {
            return commands.joined(separator: " ")
        }
        commands.append("-d \u{27}\(body)\u{27}")

        return commands.joined(separator: " ")
    }
}

/// Extension providing helper properties for `URLResponse` used by the network logger.
///
/// These properties extract commonly needed information from HTTP responses for logging.
extension URLResponse {
    /// Returns the HTTP status code, or 999 if not an HTTP response.
    ///
    /// - Returns: The status code from the HTTP response, or 999 as a fallback.
    var statusCodeInt: Int {
        return (self as? HTTPURLResponse)?.statusCode ?? 999
    }

    /// Returns all HTTP response headers as a dictionary.
    ///
    /// - Returns: Dictionary of response header fields, or an empty dictionary if not an HTTP response.
    var headers: [AnyHashable: Any] {
        return (self as? HTTPURLResponse)?.allHeaderFields ?? [:]
    }
}

/// Extension for reading all data from an `InputStream`.
///
/// This extension is used by the network logger to capture request body data from streams.
extension InputStream {
    /// Reads all available data from the stream.
    ///
    /// This method opens the stream, reads all available data in 4KB chunks,
    /// and then closes the stream.
    ///
    /// - Returns: All data read from the stream.
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

/// Extension for appending strings to files.
///
/// Used by the network logger to write log entries to the session log file.
extension String {
    /// Appends this string to a file at the specified path.
    ///
    /// If the file already exists, the string is appended to the end.
    /// If the file doesn't exist, it's created with this string as the content.
    ///
    /// - Parameter filePath: The path to the file where the string should be appended.
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
                logMessage("Error creating \(filePath)")
            }
        }
    }
}

public extension NSNotification.Name {
    /// Notification posted to deactivate search in the network logger UI.
    static let LoggerDeactivateSearch = Notification.Name("LoggerDeactivateSearch")

    /// Notification posted when the network logger data should be reloaded.
    static let LoggerReloadData = Notification.Name("LoggerReloadData")

    /// Notification posted when a new network log model is added.
    static let LoggerAddedModel = Notification.Name("LoggerAddedModel")

    /// Notification posted when all network log models are cleared.
    static let LoggerClearedModels = Notification.Name("LoggerClearedModels")
}
