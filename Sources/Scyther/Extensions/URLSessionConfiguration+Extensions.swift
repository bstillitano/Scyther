//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 1/1/21.
//

import Foundation

// MARK: - Non-Swizzling Constants
public extension String {
    /// Constant string value used to tell Scyther that a given URLSessionConfiguration should not be swizzled. Useful for webhooks as injecting a class protocol will mean a webhook can't connect. Any URLSessionConfiguration that has an identifier that contains this string, will not be swizzled. E.g. "do_not_swizzle_ABC123"  & "ABC123_do_not_swizzle" will not be swizzled.
    static var noSwizzle: String {
        return "do_not_swizzle"
    }
}

// MARK: - Custom Init
public extension URLSessionConfiguration {
    @objc class func `default`(withIdentifier identifier: String) -> URLSessionConfiguration {
        var configuration: URLSessionConfiguration = .default
        configuration.sharedContainerIdentifier = identifier
        return configuration
    }
}

internal extension URLSessionConfiguration {

    class func swizzleDefaultSessionConfiguration() {
        guard self == URLSessionConfiguration.self else { return }

        let defaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default))
        let swizzledDefaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledDefaultSessionConfiguration))
        method_exchangeImplementations(defaultSessionConfiguration!, swizzledDefaultSessionConfiguration!)
        
        let defaultWithIdentifierSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.default(withIdentifier:)))
        let swizzledDefaultWithIdentifierSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledDefault(withIdentifier:)))
        method_exchangeImplementations(defaultWithIdentifierSessionConfiguration!, swizzledDefaultWithIdentifierSessionConfiguration!)

        let ephemeralSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral))
        let swizzledEphemeralSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledEphemeralSessionConfiguration))
        method_exchangeImplementations(ephemeralSessionConfiguration!, swizzledEphemeralSessionConfiguration!)

        let backgroundSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.background(withIdentifier:)))
        let swizzledBackgroundSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledBackground(withIdentifier:)))
        method_exchangeImplementations(backgroundSessionConfiguration!, swizzledBackgroundSessionConfiguration!)

        let initSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.init))
        let swizzledInitSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledInit))
        method_exchangeImplementations(initSessionConfiguration!, swizzledInitSessionConfiguration!)
    }

    @objc
    class func swizzledDefaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = swizzledDefaultSessionConfiguration()
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }
    
    @objc
    class func swizzledDefault(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration = swizzledDefault(withIdentifier: identifier)
        Logger.enable(!(configuration.sharedContainerIdentifier?.contains(identifier) ?? false), sessionConfiguration: configuration)
        return configuration
    }

    @objc
    class func swizzledEphemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = swizzledEphemeralSessionConfiguration()
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }

    @objc
    class func swizzledBackground(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration = swizzledBackground(withIdentifier: identifier)
        Logger.enable(!(configuration.sharedContainerIdentifier?.contains(identifier) ?? false), sessionConfiguration: configuration)
        return configuration
    }

    @objc
    class func swizzledInit() -> URLSessionConfiguration {
        let configuration = swizzledInit()
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }
}
