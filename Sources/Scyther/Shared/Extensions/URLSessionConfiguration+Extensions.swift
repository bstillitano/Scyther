//
//  URLSessionConfiguration+Extensions.swift
//
//
//  Created by Brandon Stillitano on 1/1/21.
//

import Foundation

// MARK: - Non-Swizzling Constants

/// String extension providing constants for URLSessionConfiguration swizzling control.
public extension String {
    /// Constant string value used to exclude URLSessionConfiguration from network interception.
    ///
    /// When a URLSessionConfiguration's identifier contains this string, Scyther will skip
    /// swizzling that configuration's network requests. This is useful for scenarios where
    /// network interception would interfere with functionality, such as webhooks or third-party
    /// SDKs that require unmodified network behavior.
    ///
    /// ## Usage
    /// Include this string anywhere in the configuration identifier to prevent swizzling:
    /// - `"do_not_swizzle_ABC123"` - Will NOT be swizzled
    /// - `"ABC123_do_not_swizzle"` - Will NOT be swizzled
    /// - `"webhook_do_not_swizzle"` - Will NOT be swizzled
    ///
    /// ## Example
    /// ```swift
    /// // Create a configuration that won't be intercepted
    /// let config = URLSessionConfiguration.default(
    ///     withIdentifier: "webhook_\(String.noSwizzle)"
    /// )
    ///
    /// // Use for third-party SDKs that need unmodified networking
    /// let analyticsConfig = URLSessionConfiguration.default(
    ///     withIdentifier: "analytics_\(String.noSwizzle)_session"
    /// )
    /// ```
    ///
    /// - Important: This only affects URLSessionConfiguration objects with custom identifiers.
    ///              Use the `default(withIdentifier:)` initializer to set an identifier.
    ///
    /// - Note: This is particularly useful for:
    ///   - Webhook endpoints that validate request signatures
    ///   - Third-party analytics SDKs
    ///   - Payment processing SDKs
    ///   - Any networking that requires unmodified headers/behavior
    static var noSwizzle: String {
        return "do_not_swizzle"
    }
}

// MARK: - Custom Init

/// Public extensions for URLSessionConfiguration providing custom initializers.
public extension URLSessionConfiguration {
    /// Creates a default URLSessionConfiguration with a custom identifier.
    ///
    /// This convenience method creates a standard default configuration and assigns
    /// a custom identifier to it. The identifier can be used to control network interception
    /// behavior (e.g., by including `String.noSwizzle` to prevent swizzling).
    ///
    /// - Parameter identifier: A string identifier for the configuration
    ///
    /// - Returns: A default URLSessionConfiguration with the specified identifier
    ///
    /// ## Example
    /// ```swift
    /// // Create a configuration with custom identifier
    /// let config = URLSessionConfiguration.default(withIdentifier: "api_client")
    ///
    /// // Create a configuration that won't be intercepted
    /// let webhookConfig = URLSessionConfiguration.default(
    ///     withIdentifier: "webhook_\(String.noSwizzle)"
    /// )
    /// ```
    @objc class func `default`(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration: URLSessionConfiguration = .default
        configuration.sharedContainerIdentifier = identifier
        return configuration
    }
}

// MARK: - Internal Swizzling Methods

/// Internal extensions for URLSessionConfiguration handling network interception.
///
/// These methods implement the swizzling mechanism that allows Scyther to intercept
/// and log network requests. The swizzled methods wrap the original URLSessionConfiguration
/// initializers and enable network monitoring through the NetworkHelper.
internal extension URLSessionConfiguration {

    /// Sets up method swizzling for all URLSessionConfiguration initializers.
    ///
    /// This method swizzles the following configuration creation methods:
    /// - `default` property
    /// - `default(withIdentifier:)` method
    /// - `ephemeral` property
    /// - `background(withIdentifier:)` method
    /// - `init()` initializer
    ///
    /// Called once during Scyther initialization to enable network monitoring.
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

    /// Swizzled version of the default configuration getter.
    ///
    /// Creates a default configuration and enables network monitoring on it.
    @objc
    class func swizzledDefaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = swizzledDefaultSessionConfiguration()
        NetworkHelper.instance.enable(true, sessionConfiguration: configuration)
        return configuration
    }

    /// Swizzled version of the default configuration with identifier method.
    ///
    /// Creates a default configuration with the specified identifier and enables
    /// network monitoring unless the identifier contains the noSwizzle string.
    @objc
    class func swizzledDefault(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration = swizzledDefault(withIdentifier: identifier)
        NetworkHelper.instance.enable(!(configuration.sharedContainerIdentifier?.contains(String.noSwizzle) ?? false), sessionConfiguration: configuration)
        return configuration
    }

    /// Swizzled version of the ephemeral configuration getter.
    ///
    /// Creates an ephemeral configuration and enables network monitoring on it.
    @objc
    class func swizzledEphemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = swizzledEphemeralSessionConfiguration()
        NetworkHelper.instance.enable(true, sessionConfiguration: configuration)
        return configuration
    }

    /// Swizzled version of the background configuration method.
    ///
    /// Creates a background configuration with the specified identifier and enables
    /// network monitoring unless the identifier contains the noSwizzle string.
    @objc
    class func swizzledBackground(withIdentifier identifier: String) -> URLSessionConfiguration {
        let configuration = swizzledBackground(withIdentifier: identifier)
        NetworkHelper.instance.enable(!(configuration.identifier?.contains(String.noSwizzle) ?? false), sessionConfiguration: configuration)
        return configuration
    }

    /// Swizzled version of the default initializer.
    ///
    /// Creates a configuration and enables network monitoring on it.
    @objc
    class func swizzledInit() -> URLSessionConfiguration {
        let configuration = swizzledInit()
        NetworkHelper.instance.enable(true, sessionConfiguration: configuration)
        return configuration
    }
}
