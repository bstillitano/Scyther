//
//  UIApplication+Extensions.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

/// Provides convenient extensions for accessing application metadata and managing the launch screen.
///
/// This extension adds utility properties and methods to retrieve common application information
/// and manage launch screen caching behavior.
public extension UIApplication {
    /// The file path to the launch screen cache directory.
    ///
    /// This private property returns the path to the SplashBoard directory where iOS caches
    /// the launch screen snapshot.
    private static var launchScreenPath: String {
        return "\(NSHomeDirectory())/Library/SplashBoard"
    }

    /// Clears the cached launch screen snapshot.
    ///
    /// This method removes the cached launch screen files, forcing iOS to regenerate them
    /// the next time the app launches. This is useful when the launch screen has been
    /// modified and you want to see the changes immediately.
    ///
    /// ## Example
    /// ```swift
    /// // Clear launch screen cache after updating launch screen
    /// UIApplication.shared.clearLaunchScreenCache()
    /// ```
    ///
    /// - Note: The app must be restarted for the new launch screen to appear.
    ///         Changes will not be visible until the next app launch.
    ///
    /// - Important: This method silently fails if the directory doesn't exist or
    ///              cannot be deleted due to permissions.
    func clearLaunchScreenCache() {
        try? FileManager.default.removeItem(atPath: Self.launchScreenPath)
    }

    /// The display name of the running application.
    ///
    /// Returns the value of the `CFBundleName` key from the app's Info.plist file.
    /// This is typically the name shown under the app icon on the home screen.
    ///
    /// ## Example
    /// ```swift
    /// let name = UIApplication.shared.appName
    /// print("Welcome to \(name)")
    /// ```
    ///
    /// - Returns: The application's display name, or an empty string if not found.
    var appName: String {
        return Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? ""
    }

    /// The current app version for the running application.
    ///
    /// Returns the value of the `CFBundleShortVersionString` key from the app's Info.plist file.
    /// This is the user-facing version number (e.g., "1.0.0").
    ///
    /// ## Example
    /// ```swift
    /// if let version = UIApplication.shared.appVersion {
    ///     print("Version: \(version)")
    /// }
    /// ```
    ///
    /// - Returns: The version string, or `nil` if not found in the Info.plist
    var appVersion: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The current build number for the running application.
    ///
    /// Returns the value of the `CFBundleVersion` key from the app's Info.plist file.
    /// This is typically an incrementing number used to distinguish different builds.
    ///
    /// ## Example
    /// ```swift
    /// if let build = UIApplication.shared.buildNumber {
    ///     print("Build: \(build)")
    /// }
    /// ```
    ///
    /// - Returns: The build number string, or `nil` if not found in the Info.plist
    var buildNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
