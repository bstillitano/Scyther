//
//  Bundle+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

import Foundation

extension Bundle {
    public var versionNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    public var buildNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    public var buildDate: Date {
        guard let infoPath = self.path(forResource: "Info", ofType: "plist") else {
            return Date()
        }
        guard let infoAttributes = try? FileManager.default.attributesOfItem(atPath: infoPath) else {
            return Date()
        }
        return infoAttributes[.modificationDate] as? Date ?? Date()
    }

    
    /// Returns the "App Identifier Prefix" for the application. This is also commonly referred to as the "Seed ID" or the "Team ID".
    /// https://stackoverflow.com/questions/11726672/access-app-identifier-prefix-programmatically
    public var seedId: String? {
        let queryLoad: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "bundleSeedID" as AnyObject,
            kSecAttrService as String: "" as AnyObject,
            kSecReturnAttributes as String: kCFBooleanTrue
        ]

        var result: AnyObject?
        var status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(queryLoad as CFDictionary, UnsafeMutablePointer($0))
        }

        if status == errSecItemNotFound {
            status = withUnsafeMutablePointer(to: &result) {
                SecItemAdd(queryLoad as CFDictionary, UnsafeMutablePointer($0))
            }
        }

        if status == noErr {
            if let resultDict = result as? [String: Any], let accessGroup = resultDict[kSecAttrAccessGroup as String] as? String {
                let components = accessGroup.components(separatedBy: ".")
                return components.first
            } else {
                return nil
            }
        } else {
            print("Error getting bundleSeedID to Keychain")
            return nil
        }
    }
}

/// Cocoapods Specific Extensions
#if !SWIFT_PACKAGE
    extension Bundle {
        static var module: Bundle {
            Bundle(identifier: "org.cocoapods.Scyther")!
        }
    }
#endif
