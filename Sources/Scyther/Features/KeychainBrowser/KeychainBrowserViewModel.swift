//
//  KeychainBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI
import Security

/// A view model that manages keychain browsing and manipulation operations.
///
/// `KeychainBrowserViewModel` provides the business logic for loading, filtering,
/// and managing keychain items across different security classes. It serves as the
/// data source and command handler for the Keychain Browser feature.
///
/// ## Features
///
/// - **Multi-class Support**: Fetches items from Generic Passwords, Internet Passwords, and Identities
/// - **Organized Sections**: Groups keychain items by security class for easy navigation
/// - **CRUD Operations**: Supports reading, deleting individual items, and bulk keychain clearing
/// - **Async Loading**: Performs keychain queries asynchronously to avoid blocking the UI
/// - **Attribute Parsing**: Extracts and formats keychain attributes with human-readable names
///
/// ## Usage
///
/// ```swift
/// @StateObject private var viewModel = KeychainBrowserViewModel()
///
/// var body: some View {
///     List {
///         ForEach(viewModel.sections) { section in
///             Section(section.title) {
///                 ForEach(section.items) { item in
///                     // Display keychain item
///                 }
///             }
///         }
///     }
///     .onFirstAppear {
///         await viewModel.onFirstAppear()
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Initialization
/// - ``KeychainBrowserViewModel``
///
/// ### Published Properties
/// - ``sections``
///
/// ### Loading Data
/// - ``loadItems()``
/// - ``fetchKeychainItems(forClass:)``
///
/// ### Deleting Items
/// - ``deleteItem(_:)``
/// - ``deleteKeychainItem(_:)``
/// - ``clearKeychain()``
///
/// ### Attribute Formatting
/// - ``keychainAttributeDisplayName(_:)``
/// - ``stringDescription(for:)``
class KeychainBrowserViewModel: ViewModel {
    /// The keychain sections organized by security class.
    ///
    /// Each section contains a title, security class type, and array of items
    /// belonging to that class. Sections are automatically populated when
    /// ``loadItems()`` is called.
    @Published var sections: [KeychainSection] = []

    /// Called when the view first appears.
    ///
    /// Triggers the initial load of keychain items across all security classes.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadItems()
    }

    /// Loads all keychain items organized by security class.
    ///
    /// Fetches items from Generic Passwords, Internet Passwords, and Identities,
    /// then updates the ``sections`` property with the results.
    ///
    /// - Note: This method runs on the main actor to safely update the UI.
    @MainActor
    func loadItems() async {
        var newSections: [KeychainSection] = []

        for secClass in [KeychainSecurityClass.genericPassword, .internetPassword, .identity] {
            let items = Self.fetchKeychainItems(forClass: secClass)
            newSections.append(KeychainSection(
                title: secClass.sectionTitle,
                securityClass: secClass,
                items: items
            ))
        }

        sections = newSections
    }

    /// Fetches keychain items for a specific security class.
    ///
    /// Queries the keychain using `SecItemCopyMatching` and transforms the raw
    /// results into structured ``KeychainItem`` instances with formatted attributes.
    ///
    /// - Parameter secClass: The security class to query (e.g., `.genericPassword`)
    /// - Returns: An array of keychain items sorted alphabetically by account name
    static func fetchKeychainItems(forClass secClass: KeychainSecurityClass) -> [KeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: secClass.secClass,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict -> KeychainItem? in
            let account = dict[kSecAttrAccount as String] as? String ?? dict[kSecAttrLabel as String] as? String ?? "Unknown"
            let service = dict[kSecAttrService as String] as? String
            let label = dict[kSecAttrLabel as String] as? String

            var stringValue: String?
            var dataValue: Data?

            if let data = dict[kSecValueData as String] as? Data {
                dataValue = data
                stringValue = String(data: data, encoding: .utf8)
            }

            // Build attributes dictionary
            var attributes: [String: String] = [:]
            let skipKeys: Set<String> = [
                kSecValueData as String,
                kSecValueRef as String,
                kSecAttrAccount as String,
                kSecAttrService as String,
                kSecAttrLabel as String,
                kSecClass as String
            ]

            for (key, value) in dict {
                guard !skipKeys.contains(key) else { continue }
                let displayKey = keychainAttributeDisplayName(key)
                attributes[displayKey] = stringDescription(for: value)
            }

            return KeychainItem(
                account: account,
                service: service,
                label: label,
                securityClass: secClass,
                stringValue: stringValue,
                dataValue: dataValue,
                attributes: attributes,
                rawAttributes: dict
            )
        }.sorted { $0.account.lowercased() < $1.account.lowercased() }
    }

    /// Converts keychain attribute keys to human-readable display names.
    ///
    /// - Parameter key: The raw keychain attribute key (e.g., `kSecAttrAccessible`)
    /// - Returns: A user-friendly display name (e.g., "Accessible")
    private static func keychainAttributeDisplayName(_ key: String) -> String {
        let mapping: [String: String] = [
            kSecAttrAccessible as String: "Accessible",
            kSecAttrCreationDate as String: "Created",
            kSecAttrModificationDate as String: "Modified",
            kSecAttrDescription as String: "Description",
            kSecAttrComment as String: "Comment",
            kSecAttrCreator as String: "Creator",
            kSecAttrType as String: "Type",
            kSecAttrIsInvisible as String: "Invisible",
            kSecAttrIsNegative as String: "Negative",
            kSecAttrSynchronizable as String: "Synchronizable",
            kSecAttrAccessGroup as String: "Access Group",
            kSecAttrSecurityDomain as String: "Security Domain",
            kSecAttrServer as String: "Server",
            kSecAttrProtocol as String: "Protocol",
            kSecAttrAuthenticationType as String: "Auth Type",
            kSecAttrPort as String: "Port",
            kSecAttrPath as String: "Path"
        ]
        return mapping[key] ?? key
    }

    /// Converts keychain attribute values to formatted string descriptions.
    ///
    /// Handles special formatting for dates, booleans, data, and other types.
    ///
    /// - Parameter value: The attribute value to format
    /// - Returns: A human-readable string representation
    private static func stringDescription(for value: Any) -> String {
        if let date = value as? Date {
            return date.formatted()
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "Yes" : "No"
            }
            return "\(number)"
        } else if let data = value as? Data {
            return "\(data.count) bytes"
        } else if let string = value as? String {
            return string
        }
        return String(describing: value)
    }

    /// Deletes a specific keychain item and updates the local state.
    ///
    /// Removes the item from the system keychain and updates the ``sections``
    /// array to reflect the deletion in the UI.
    ///
    /// - Parameter item: The keychain item to delete
    @MainActor
    func deleteItem(_ item: KeychainItem) {
        Self.deleteKeychainItem(item)

        // Remove from local state
        for i in sections.indices {
            sections[i].items.removeAll { $0.id == item.id }
        }
    }

    /// Deletes a keychain item from the system keychain.
    ///
    /// Uses the item's raw attributes to construct a precise deletion query.
    /// Falls back to label-based deletion if account/service aren't available.
    ///
    /// - Parameter item: The keychain item to delete
    static func deleteKeychainItem(_ item: KeychainItem) {
        var query: [String: Any] = [
            kSecClass as String: item.securityClass.secClass
        ]

        // Use account or label for identification
        if let account = item.rawAttributes[kSecAttrAccount as String] {
            query[kSecAttrAccount as String] = account
        }
        if let service = item.rawAttributes[kSecAttrService as String] {
            query[kSecAttrService as String] = service
        }
        if query.count == 1, let label = item.rawAttributes[kSecAttrLabel as String] {
            query[kSecAttrLabel as String] = label
        }

        SecItemDelete(query as CFDictionary)
    }

    /// Clears all keychain items and reloads the sections.
    ///
    /// Delegates to ``KeychainBrowser/clearKeychain()`` to perform the bulk
    /// deletion, then refreshes the UI by reloading items.
    @MainActor
    func clearKeychain() {
        KeychainBrowser.clearKeychain()
        Task {
            await loadItems()
        }
    }
}
