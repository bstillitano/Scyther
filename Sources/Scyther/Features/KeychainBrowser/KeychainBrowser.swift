//
//  KeychainBrowser.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

/// Utility for accessing and managing keychain items stored by the application.
///
/// `KeychainBrowser` provides read-only access to view all keychain entries
/// accessible by the app, organized by security class. It also provides a
/// method to clear all keychain data for debugging purposes.
///
/// ## Topics
/// ### Accessing Keychain Items
/// - ``keychainItems``
///
/// ### Managing Keychain
/// - ``clearKeychain()``
internal struct KeychainBrowser {
    /// Retrieves all keychain items accessible by the application.
    ///
    /// Returns a dictionary organized by keychain security class:
    /// - Generic Passwords (`kSecClassGenericPassword`)
    /// - Internet Passwords (`kSecClassInternetPassword`)
    /// - Identities (`kSecClassIdentity`)
    ///
    /// Each security class maps to a dictionary of key-value pairs representing
    /// the stored keychain items.
    ///
    /// - Returns: A dictionary where keys are security class names and values are
    ///   dictionaries of keychain items for that class.
    static var keychainItems: [String: [String: Any]] {
        var values: [String: [String: Any]] = [:]
        values["Generic Passwords"] = keychainItems(forClass: kSecClassGenericPassword)
        values["Internet Passwords"] = keychainItems(forClass: kSecClassInternetPassword)
        values["Identities"] = keychainItems(forClass: kSecClassIdentity)
        return values
    }

    static private func keychainItems(forClass secClass: CFString) -> [String: AnyObject] {
        // Construct Keychain query
        let query: [String: Any] = [
            kSecClass as String: secClass,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        // Prepare data
        var result: AnyObject?
        let lastResultCode = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
        }

        // Check result code and pass back array of values as a dictionary
        var values: [String: AnyObject] = [:]
        if lastResultCode == noErr, let array = result as? [[String: Any]] {
            array.forEach {
                if let key = $0[kSecAttrAccount as String] as? String, let value = $0[kSecValueData as String] as? Data {
                    values[key] = String(data: value, encoding: .utf8) as AnyObject?
                } else if let key = $0[kSecAttrLabel as String] as? String, let value = $0[kSecValueRef as String] {
                    values[key] = value as AnyObject
                }
            }
        }

        return values
    }
    
    /// Deletes all keychain items stored by the application.
    ///
    /// - Warning: This operation cannot be undone. All stored passwords, certificates,
    ///   keys, and identities will be permanently deleted.
    ///
    /// This method removes items from all keychain security classes:
    /// - Generic passwords
    /// - Internet passwords
    /// - Certificates
    /// - Cryptographic keys
    /// - Identities
    static internal func clearKeychain() {
        let secItemClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]

        for secItemClass in secItemClasses {
            let dictionary = [kSecClass as String: secItemClass]
            SecItemDelete(dictionary as CFDictionary)
        }
    }
}
