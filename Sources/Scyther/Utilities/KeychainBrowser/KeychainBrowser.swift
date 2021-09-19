//
//  File.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

internal struct KeychainItem {
    init() { }

    var name: String?
    var value: String?
}

struct KeychainBrowswer {
    /// Retrieves all keychain items for a given kSecClass
    /// - Parameter secClass: The class of item that should be retrieved
    /// - Returns: A dictionary of keychain items
    static func keychainItems(forClass secClass: CFString) -> [KeychainItem] {
        // Construct keychain query
        let query: [String: Any] = [kSecClass as String: secClass,
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnRef as String: true]

        // Check data can found and returned/accessed succesfully
        var items_ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items_ref)
        guard status != errSecItemNotFound else {
            return []
        }
        guard status == errSecSuccess else {
            return []
        }
        let items = items_ref as! Array<Dictionary<String, Any>>

        return items.compactMap { item in
            var keychainItem: KeychainItem = KeychainItem()
            keychainItem.name = item[kSecAttrAccount as String] as? String
            keychainItem.value = try? readPassword(service: item[kSecAttrService as String] as? String,
                                                   account: item[kSecAttrAccount as String] as? String)
            return keychainItem
        }
    }

    private static func readPassword(service: String?, account: String?) throws -> String {
        let query: [String: AnyObject] = [
            // kSecAttrService,  kSecAttrAccount, and kSecClass
            // uniquely identify the item to read in Keychain
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,

            // kSecMatchLimitOne indicates keychain should read
            // only the most recent item matching this query
            kSecMatchLimit as String: kSecMatchLimitOne,

            // kSecReturnData is set to kCFBooleanTrue in order
            // to retrieve the data for the item
            kSecReturnData as String: kCFBooleanTrue
        ]

        // SecItemCopyMatching will attempt to copy the item
        // identified by query to the reference itemCopy
        var itemCopy: AnyObject?
        let status = SecItemCopyMatching(
            query as CFDictionary,
                &itemCopy
        )

        // errSecItemNotFound is a special status indicating the
        // read item does not exist. Throw itemNotFound so the
        // client can determine whether or not to handle
        // this case
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        // Any status other than errSecSuccess indicates the
        // read operation failed.
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        // This implementation of KeychainInterface requires all
        // items to be saved and read as Data. Otherwise,
        // invalidItemFormat is thrown
        guard let password = itemCopy as? Data else {
            throw KeychainError.invalidItemFormat
        }

        return String(decoding: password, as: UTF8.self)
    }
}
