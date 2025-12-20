//
//  EnvironmentReader.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

#if !os(macOS)
import UIKit

/// A utility for detecting the current build and runtime environment.
///
/// `AppEnvironment` provides static properties to determine how your app was installed
/// and what environment it's running in. This is useful for:
/// - Conditionally enabling debug features
/// - Adjusting behavior based on TestFlight vs App Store
/// - Detecting simulator builds
/// - Checking for jailbroken devices
///
/// ## Example Usage
///
/// ```swift
/// if AppEnvironment.isDevelopment {
///     enableDebugMenu()
/// }
///
/// if AppEnvironment.isJailbroken {
///     showSecurityWarning()
/// }
///
/// switch AppEnvironment.configuration() {
/// case .debug:
///     print("Running in Xcode")
/// case .testFlight:
///     print("Running via TestFlight")
/// case .appStore:
///     print("Running from App Store")
/// }
/// ```
///
/// ## Topics
///
/// ### Build Detection
/// - ``isDebug``
/// - ``isSimulator``
/// - ``isTestFlight``
/// - ``isTestCase``
///
/// ### Environment Classification
/// - ``isDevelopment``
/// - ``isAppStore``
/// - ``configuration(testValue:)``
///
/// ### Security
/// - ``isJailbroken``
public struct AppEnvironment {
    /// Indicates whether the `appStoreReceiptURL` at `Bundle.main.appStoreReceiptURL` is a sandbox receipt.
    public static var isTestFlight: Bool{
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && !AppEnvironment.isDebug
    }

    /// Returns a `Bool` value indicating whether or not the current process is being run as part of a test case
    public static var isTestCase: Bool {
        return ProcessInfo.processInfo.isRunningInTestEnvironment
    }
    /// Returns a `Bool` value indicating whether or not `#if DEBUG` is true for the current build.
    public static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
    
    /// Returns a `Bool` value indicating whether or not the current build is being run via the iOS Simulator.
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }

    /// Returns a `Bool` value indicating whether or not the current build is being run via XCode or TestFlight.
    public static var isDevelopment: Bool {
        return isTestFlight || isSimulator || isDebug
    }

    /// Returns a `Bool` value indicating whether or not the current build is being run via an App Store installation.
    public static var isAppStore: Bool {
        return !isDevelopment
    }

    /// Returns a `BuildType` value representing the current build environment.
    public static func configuration(testValue: BuildType? = nil) -> BuildType {
        if isTestFlight || testValue == .testFlight {
            return .testFlight
        } else if isAppStore || testValue == .appStore {
            return .appStore
        } else {
            return .debug
        }
    }
    
    /// Returns a `Bool` value indicating whether or not the current device is jailbroken by determining whether or not `Cydia` or `Sileo` is installed. It also checks for multiple other red flags that would indicate  root/ssh access on the device. These checks will not apply if the device is a simulator.
    public static var isJailbroken: Bool {
        // Check if the device is not a simulator
        guard !AppEnvironment.isSimulator else {
            return false
        }
        
        //Check for Cydia URL Scheme
        guard let cydiaUrlScheme = URL(string: "cydia://package/com.example.package") else {
            return false
        }
        if UIApplication.shared.canOpenURL(cydiaUrlScheme) {
            return true
        }
        
        //Check for Sileo URL Scheme
        guard let sileoUrlScheme = URL(string: "sileo://package/com.example.package") else {
            return false
        }
        if UIApplication.shared.canOpenURL(sileoUrlScheme) {
            return true
        }
        
        //Check for File Access to Cydia, Sileo & Substrate.
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: "/Applications/Cydia.app") ||
            fileManager.fileExists(atPath: "/Applications/Sileo.app") ||
            fileManager.fileExists(atPath: "/Library/MobileSubstrate/MobileSubstrate.dylib") ||
            fileManager.fileExists(atPath: "/bin/bash") ||
            fileManager.fileExists(atPath: "/usr/sbin/sshd") ||
            fileManager.fileExists(atPath: "/etc/apt") ||
            fileManager.fileExists(atPath: "/usr/bin/ssh") ||
            fileManager.fileExists(atPath: "/private/var/lib/apt") {
            return true
        }
        
        //Further Check for App Availalability
        if canOpen(path: "/Applications/Cydia.app") ||
            canOpen(path: "/Applications/Sileo.app") ||
            canOpen(path: "/Library/MobileSubstrate/MobileSubstrate.dylib") ||
            canOpen(path: "/bin/bash") ||
            canOpen(path: "/usr/sbin/sshd") ||
            canOpen(path: "/etc/apt") ||
            canOpen(path: "/usr/bin/ssh") {
            return true
        }
        
        //Check if root file system access is available
        let path = "/private/" + UUID().uuidString
        do {
            try "anyString".write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
}

extension AppEnvironment {
    /**
     Convenience method allowing us to determine whether or not our app can open a particular URL scheme or path.
     
     - Parameters:
        - path: The URL scheme or path that we wish to check against.
    
     - Returns: A `Bool` value representing whether or not the path/scheme is valid for the running device.
     
     - Complexity: O(*1*)
     */
    private static func canOpen(path: String) -> Bool {
        let file = fopen(path, "r")
        guard file != nil else { return false }
        fclose(file)
        return true
    }
}

/// Represents the type of build environment the app is running in.
///
/// Use ``AppEnvironment/configuration(testValue:)`` to get the current build type.
public enum BuildType: String {
    /// The app was installed via Xcode and is running in debug mode.
    ///
    /// This typically means a developer is actively working on the app
    /// with a debugger attached.
    case debug = "Debug"

    /// The app was installed via TestFlight.
    ///
    /// TestFlight builds contain a sandbox receipt and are used for
    /// beta testing before App Store release.
    case testFlight = "TestFlight"

    /// The app was installed from the App Store.
    ///
    /// This is a production build downloaded by end users.
    case appStore = "App Store"
}
#endif
