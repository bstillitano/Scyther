//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 1/1/21.
//

import Foundation

internal extension URLSessionConfiguration {

    class func swizzleDefaultSessionConfiguration() {
        guard self == URLSessionConfiguration.self else { return }

        let defaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default))
        let swizzledDefaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.swizzledDefaultSessionConfiguration))
        method_exchangeImplementations(defaultSessionConfiguration!, swizzledDefaultSessionConfiguration!)

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
    class func swizzledEphemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = swizzledEphemeralSessionConfiguration()
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }

    @objc
    class func swizzledBackground(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration = swizzledBackground(withIdentifier: identifier)
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }

    @objc
    class func swizzledInit() -> URLSessionConfiguration {
        let configuration = swizzledInit()
        Logger.enable(true, sessionConfiguration: configuration)
        return configuration
    }
}
