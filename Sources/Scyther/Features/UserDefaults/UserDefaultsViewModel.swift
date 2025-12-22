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
    /// Published array of UserDefaults entries, sorted alphabetically by key.
    @Published var keyValues: [UserDefaultItem] = []

    /// Called when the view first appears.
    ///
    /// Loads all UserDefaults entries and sorts them alphabetically.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDefaults()
    }

    /// Loads all UserDefaults entries from `UserDefaults.standard`.
    ///
    /// This method:
    /// - Retrieves all key-value pairs from the dictionary representation
    /// - Sorts entries alphabetically by key (case-insensitive)
    /// - Detects value types and creates display-friendly representations
    /// - Updates the ``keyValues`` published property
    func loadDefaults() async {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
            .sorted { $0.key.lowercased() < $1.key.lowercased() }

        keyValues = defaults.map { key, value in
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
            return "\(data.count) bytes"
        }
        if let array = value as? [Any] {
            return "\(array.count) elements"
        }
        if let dict = value as? [String: Any] {
            return "\(dict.count) entries"
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
            get: {
                UserDefaults.standard.bool(forKey: key)
            },
            set: { [weak self] newValue in
                UserDefaults.standard.set(newValue, forKey: key)
                Task { @MainActor in
                    await self?.loadDefaults()
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
        UserDefaults.standard.set(value, forKey: key)
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
        UserDefaults.standard.removeObject(forKey: key)
        keyValues.removeAll { $0.key == key }
    }

    /// Resets all UserDefaults values except Scyther-specific keys.
    ///
    /// This method:
    /// - Iterates through all UserDefaults keys
    /// - Filters out any keys starting with "scyther" (case-insensitive)
    /// - Removes all non-Scyther keys
    /// - Synchronizes UserDefaults to disk
    /// - Reloads the defaults list
    ///
    /// > Warning: This action cannot be undone. All app-specific UserDefaults
    /// > values will be permanently deleted.
    func resetAllDefaults() {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { !$0.lowercased().hasPrefix("scyther") }
            .forEach(UserDefaults.standard.removeObject(forKey:))
        UserDefaults.standard.synchronize()

        Task {
            await loadDefaults()
        }
    }
}
