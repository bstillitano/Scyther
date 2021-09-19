//
//  File.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

/// Utility `struct` used to iterate the Keychain and return all values accessible by the consuming app.
internal struct KeychainBrowser {
    /// Creates a dictionary of keychain values of differing types
    /// - Returns: A dictionary containing kSecClassGenericPassword, kSecClassInternetPassword & kSecClassIdentity values
    static var keychainItems: [String: [String: AnyObject]] {
        var values: [String: [String: AnyObject]] = [:]
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
}
