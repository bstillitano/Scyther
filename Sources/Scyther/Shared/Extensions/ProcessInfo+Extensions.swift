//
//  ProcessInfo+Extensions.swift
//
//
//  Created by Brandon Stillitano on 10/2/22.
//

import Foundation

/// Provides convenient extensions for detecting test environments.
///
/// This extension adds utility properties to determine if the current process is running
/// within a testing context, useful for conditionally enabling or disabling features during tests.
public extension ProcessInfo {
    /// Returns a Boolean value indicating whether the process is running as part of a test.
    ///
    /// This property checks for the presence of the `XCTestConfigurationFilePath` environment
    /// variable, which is set by Xcode when running XCTest or XCUITest-based tests.
    ///
    /// - Returns: `true` if running within an XCTestCase or XCUITestCase, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if ProcessInfo.processInfo.isRunningInTestEnvironment {
    ///     print("Running in test mode - using mock data")
    ///     // Use test fixtures or mock objects
    /// } else {
    ///     print("Running in production mode")
    ///     // Use real network calls and data
    /// }
    /// ```
    ///
    /// ## Use Cases
    /// - Conditionally enabling debug features only during testing
    /// - Switching between real and mock implementations
    /// - Bypassing authentication in test environments
    /// - Adjusting timing or animations for faster test execution
    ///
    /// - Note: This property only detects XCTest-based tests. Other testing frameworks
    ///         may not set this environment variable.
    var isRunningInTestEnvironment: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
