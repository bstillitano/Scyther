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

extension Date {
    func isGreaterThanDate(_ dateToCompare: Date) -> Bool {
        if self.compare(dateToCompare) == ComparisonResult.orderedDescending {
            return true
        } else {
            return false
        }
    }
}

extension String {
    func appendToFile(filePath: String) {
        let contentToAppend = self

        if let fileHandle = FileHandle(forWritingAtPath: filePath) {
            /* Append to file */
            fileHandle.seekToEndOfFile()
            fileHandle.write(contentToAppend.data(using: String.Encoding.utf8)!)
        } else {
            /* Create new file */
            do {
                try contentToAppend.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error creating \(filePath)")
            }
        }
    }
}

@objc private extension URLSessionConfiguration {
    private static var firstOccurrence = true

    static func implementLogger() {
        guard firstOccurrence else { return }
        firstOccurrence = false

        // First let's make sure setter: URLSessionConfiguration.protocolClasses is de-duped
        // This ensures ScytherProtocol won't be added twice
        swizzleProtocolSetter()

        // Now, let's make sure ScytherProtocol is always included in the default and ephemeral configuration(s)
        // Adding it twice won't be an issue anymore, because we've de-duped the setter
        swizzleDefault()
        swizzleEphemeral()
    }

    private static func swizzleProtocolSetter() {
        let instance = URLSessionConfiguration.default

        let aClass: AnyClass = object_getClass(instance)!

        let origSelector = #selector(setter: URLSessionConfiguration.protocolClasses)
        let newSelector = #selector(setter: URLSessionConfiguration.protocolClasses_Swizzled)

        let origMethod = class_getInstanceMethod(aClass, origSelector)!
        let newMethod = class_getInstanceMethod(aClass, newSelector)!

        method_exchangeImplementations(origMethod, newMethod)
    }

    @objc private var protocolClasses_Swizzled: [AnyClass]? {
        get {
            // Unused, but required for compiler
            return self.protocolClasses_Swizzled
        }
        set {
            guard let newTypes = newValue else { self.protocolClasses_Swizzled = nil; return }

            var types = [AnyClass]()

            // de-dup
            for newType in newTypes {
                if !types.contains(where: { (existingType) -> Bool in
                    existingType == newType
                }) {
                    types.append(newType)
                }
            }

            self.protocolClasses_Swizzled = types
        }
    }

    private static func swizzleDefault() {
        let aClass: AnyClass = object_getClass(self)!

        let origSelector = #selector(getter: URLSessionConfiguration.default)
        let newSelector = #selector(getter: URLSessionConfiguration.default_swizzled)

        let origMethod = class_getClassMethod(aClass, origSelector)!
        let newMethod = class_getClassMethod(aClass, newSelector)!

        method_exchangeImplementations(origMethod, newMethod)
    }

    private static func swizzleEphemeral() {
        let aClass: AnyClass = object_getClass(self)!

        let origSelector = #selector(getter: URLSessionConfiguration.ephemeral)
        let newSelector = #selector(getter: URLSessionConfiguration.ephemeral_swizzled)

        let origMethod = class_getClassMethod(aClass, origSelector)!
        let newMethod = class_getClassMethod(aClass, newSelector)!

        method_exchangeImplementations(origMethod, newMethod)
    }

    @objc private class var default_swizzled: URLSessionConfiguration {
        get {
            let config = URLSessionConfiguration.default_swizzled

            // Let's go ahead and add in ScytherProtocol, since it's safe to do so.
            config.protocolClasses?.insert(LoggerProtocol.self, at: 0)

            return config
        }
    }

    @objc private class var ephemeral_swizzled: URLSessionConfiguration {
        get {
            let config = URLSessionConfiguration.ephemeral_swizzled

            // Let's go ahead and add in ScytherProtocol, since it's safe to do so.
            config.protocolClasses?.insert(LoggerProtocol.self, at: 0)

            return config
        }
    }
}

public extension NSNotification.Name {
    static let LoggerDeactivateSearch = Notification.Name("LoggerDeactivateSearch")
    static let LoggerReloadData = Notification.Name("LoggerReloadData")
    static let LoggerAddedModel = Notification.Name("LoggerAddedModel")
    static let LoggerClearedModels = Notification.Name("LoggerClearedModels")
}
