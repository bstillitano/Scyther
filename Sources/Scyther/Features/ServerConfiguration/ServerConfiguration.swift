//
//  ServerConfiguration.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import Foundation

/// A server configuration containing an identifier and associated environment variables.
///
/// `ServerConfiguration` represents a single server environment (e.g., development, staging,
/// production) with its associated configuration variables. These variables typically include
/// API endpoints, feature flags, and other environment-specific settings.
///
/// ## Usage
/// ```swift
/// let devConfig = ServerConfiguration(
///     id: "Development",
///     variables: [
///         "API_URL": "https://dev-api.example.com",
///         "ENABLE_LOGGING": "true"
///     ]
/// )
/// ```
public struct ServerConfiguration: Sendable, Identifiable {
    /// The unique identifier for this server configuration.
    ///
    /// Typically represents the environment name (e.g., "Development", "Production").
    public var id: String

    /// Key-value pairs of configuration variables for this environment.
    ///
    /// Common variables include API URLs, feature toggles, and environment-specific settings.
    public var variables: [String: String] = [:]
}
