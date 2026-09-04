//
//  UserDefaultsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// A view model for managing UserDefaults browser and editor functionality.
///
/// This view model provides comprehensive CRUD operations for UserDefaults entries,
/// including type detection, value formatting, and nested structure handling.
///
/// ## Features
///
/// - **Data Loading**: Asynchronously loads and sorts all UserDefaults entries
/// - **Type Detection**: Intelligently detects and categorizes values (strings, numbers, booleans, dates, data, arrays, dictionaries)
/// - **Value Formatting**: Provides human-readable display strings for all value types
/// - **Live Editing**: Supports inline boolean toggling and dedicated editors for strings and numbers
/// - **CRUD Operations**: Create, read, update, and delete individual entries
/// - **Bulk Operations**: Reset all non-Scyther UserDefaults values
/// - **Nested Navigation**: Handles arrays and dictionaries with proper type preservation
///
/// ## Usage
///
/// ```swift
/// struct MyView: View {
///     @StateObject private var viewModel = UserDefaultsViewModel()
///
///     var body: some View {
///         List(viewModel.keyValues) { item in
///             Text(item.key)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Initialization
/// - ``UserDefaultsViewModel``
///
/// ### Store Selection
/// - ``store``
///
/// ### Data Management
/// - ``loadDefaults()``
/// - ``keyValues``
///
/// ### Value Operations
/// - ``updateValue(_:forKey:)``
/// - ``deleteKey(_:)``
/// - ``resetAllDefaults()``
/// - ``boolBinding(for:currentValue:)``
///
/// ### Type Detection
/// - ``detectValueType(_:)``
/// - ``displayString(for:)``
@MainActor
class UserDefaultsViewModel: ViewModel {
    /// The store currently being browsed.
    ///
    /// Changing this reloads ``keyValues`` from the newly selected store.
    @Published var store: DefaultsStore {
        didSet {
            guard oldValue != store else { return }
            Task { await loadDefaults() }
        }
    }

    /// Published array of UserDefaults entries, sorted alphabetically by key.
    @Published var keyValues: [UserDefaultItem] = []

    /// Creates a view model browsing the given store.
    ///
    /// - Parameter store: The store to browse. Defaults to the host app's own defaults.
    init(store: DefaultsStore = .app) {
        self.store = store
        super.init()
    }

    /// Called when the view first appears.
    ///
    /// Loads all UserDefaults entries and sorts them alphabetically.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDefaults()
    }

    /// Loads all entries from the currently selected store.
    ///
    /// The application store is read via `dictionaryRepresentation()`, matching what the app
    /// itself sees. Scyther's suite is read via `persistentDomain(forName:)` so only keys
    /// actually written to the suite appear, without inherited global-domain noise.
    func loadDefaults() async {
        let entries: [String: Any]
        switch store {
        case .app:
            entries = UserDefaults.standard.dictionaryRepresentation()
        case .scyther:
            entries = UserDefaults.standard.persistentDomain(forName: ScytherDefaults.suiteName) ?? [:]
        }

        keyValues = entries
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { key, value in
                let valueType = Self.detectValueType(value)
                let displayValue = Self.displayString(for: value)
                return UserDefaultItem(key: key, rawValue: value, valueType: valueType, displayValue: displayValue)
            }
    }

    /// Detects the type of a UserDefaults value.
    ///
    /// This method intelligently categorizes values into specific types,
    /// including proper distinction between booleans and numbers (both are NSNumber).
    ///
    /// - Parameter value: The value to analyze
    /// - Returns: A ``UserDefaultValueType`` enum case representing the detected type
    static func detectValueType(_ value: Any) -> UserDefaultValueType {
        // Check for NSNumber (includes bools and numbers)
        if let number = value as? NSNumber {
            // Use CFBooleanGetTypeID to distinguish bools from numbers
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            } else {
                return .number(number)
            }
        }

        // Check other types
        if let string = value as? String {
            return .string(string)
        }
        if let date = value as? Date {
            return .date(date)
        }
        if let data = value as? Data {
            return .data(data)
        }
        if let array = value as? [Any] {
            return .array(array)
        }
        if let dict = value as? [String: Any] {
            return .dictionary(dict)
        }

        return .unknown
    }

    /// Creates a human-readable display string for a UserDefaults value.
    ///
    /// - Parameter value: The value to format
    /// - Returns: A display-friendly string representation
    static func displayString(for value: Any) -> String {
        // Check for NSNumber first (includes bools and numbers)
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            } else {
                return "\(number)"
            }
        }

        if let string = value as? String {
            return string
        }
        if let date = value as? Date {
            return date.formatted()
        }
        if let data = value as? Data {
            return localized("\(data.count) bytes")
        }
        if let array = value as? [Any] {
            return localized("\(array.count) elements")
        }
        if let dict = value as? [String: Any] {
            return localized("\(dict.count) entries")
        }

        return String(describing: value)
    }

    /// Creates a SwiftUI binding for a boolean UserDefaults value.
    ///
    /// The binding automatically persists changes to UserDefaults and reloads
    /// the entire defaults list to reflect the update.
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key
    ///   - currentValue: The current boolean value (used for initial state)
    /// - Returns: A two-way binding to the boolean value
    func boolBinding(for key: String, currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                // Read through `self` rather than capturing `store` by value, so the binding
                // always reflects the currently selected store.
                self?.store.defaults.bool(forKey: key) ?? currentValue
            },
            set: { [weak self] newValue in
                guard let self else { return }
                self.store.defaults.set(newValue, forKey: key)
                Task { @MainActor in
                    await self.loadDefaults()
                }
            }
        )
    }

    /// Updates a UserDefaults value for a given key.
    ///
    /// After updating, the defaults list is automatically reloaded.
    ///
    /// - Parameters:
    ///   - value: The new value to store
    ///   - key: The UserDefaults key
    func updateValue(_ value: Any, forKey key: String) {
        store.defaults.set(value, forKey: key)
        Task {
            await loadDefaults()
        }
    }

    /// Deletes a UserDefaults entry by key.
    ///
    /// The entry is removed from both UserDefaults and the UI list.
    ///
    /// - Parameter key: The UserDefaults key to delete
    func deleteKey(_ key: String) {
        store.defaults.removeObject(forKey: key)
        keyValues.removeAll { $0.key == key }
    }

    /// Clears the currently selected store.
    ///
    /// For ``DefaultsStore/app`` this removes every key the host app created, keeping the
    /// `scyther` prefix filter as a safety net for any value an older Scyther left behind
    /// before migration. For ``DefaultsStore/scyther`` the entire suite is removed, which
    /// resets every Scyther setting including pinned items and feature flag overrides.
    ///
    /// > Warning: This action cannot be undone.
    func resetAllDefaults() {
        switch store {
        case .app:
            UserDefaults.standard.dictionaryRepresentation().keys
                .filter { !$0.lowercased().hasPrefix(ScytherDefaults.keyPrefix) }
                .forEach(UserDefaults.standard.removeObject(forKey:))
            UserDefaults.standard.synchronize()

        case .scyther:
            UserDefaults.standard.removePersistentDomain(forName: ScytherDefaults.suiteName)
        }

        Task {
            await loadDefaults()
        }
    }
}
