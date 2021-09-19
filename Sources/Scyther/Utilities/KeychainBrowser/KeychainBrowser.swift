//
//  File.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

import Foundation

struct KeychainBrowswer {
    static var keychainItems: [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, // change the kSecClass for your needs
            kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnRef as String: true]
        var items_ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items_ref)
        guard status != errSecItemNotFound else { return [] }
        guard status == errSecSuccess else { return [] }
        let items = items_ref as! Array<Dictionary<String, Any>>

        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }
}
