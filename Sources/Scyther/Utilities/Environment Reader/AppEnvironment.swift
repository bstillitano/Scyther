//
//  EnvironmentReader.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

#if !os(macOS)
import UIKit

public class AppEnvironment {
    /**
     Indicates whether the `appStoreReceiptURL` at `Bundle.main.appStoreReceiptURL` is a sandbox receipt.
     */
    public static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && !AppEnvironment.isDebug

    /**
     Returns a `Bool` value indicating whether or not `#if DEBUG` is true for the current build.
     */
    public static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
    
    /**
     Returns a `Bool` value indicating whether or not the current build is being run via the iOS Simulator.
    */
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }

    /**
     Returns a `Bool` value indicating whether or not the current build is being run via XCode or TestFlight.
    */
    public static var isDevelopment: Bool {
        return isTestFlight || isSimulator
    }

    /**
     Returns a `Bool` value indicating whether or not the current build is being run via an App Store installation.
    */
    public static var isAppStore: Bool {
        return !isDevelopment
    }

    /**
     Returns a `BuildType` value representing the current build environment.
     */
    public static func configuration(testValue: BuildType? = nil) -> BuildType {
        if isTestFlight || testValue == .testFlight {
            return .testFlight
        } else if isAppStore || testValue == .appStore {
            return .appStore
        } else {
            return .debug
        }
    }
    
    /**
     Returns a `Bool` value indicating whether or not the current device is jailbroken by determining whether
     or not `Cydia` or `Sileo` is installed. It also checks for multiple other red flags that would indicate
     root/ssh access on the device. These checks will not apply if the device is a simulator.
    */
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

/**
Enum class used for strongly tpying the current build environment. Conditions must be listed here to be used as conditions on the AppConfig object.
*/
public enum BuildType: String {
    /**
    Indicates that the current build is being run in debug mode. This means that the build was installed via Xcode and is connected to a debugger.
    */
    case debug = "Debug"

    /**
    Indicates that the current build was installed via TestFlight and contains a sandbox receipt.
    */
    case testFlight = "TestFlight"

    /**
    Indicates that the current build was installed via the AppStore and contains a production receipt.
    */
    case appStore = "App Store"
}
#endif
