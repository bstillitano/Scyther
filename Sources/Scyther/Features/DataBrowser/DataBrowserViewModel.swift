//
//  DataBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the data browser's state and data processing.
///
/// `DataBrowserViewModel` handles parsing raw hierarchical data structures into displayable
/// sections and items. It provides intelligent data processing with support for nested structures,
/// automatic type detection, and smart sorting of array indices.
///
/// ## Features
///
/// - **Hierarchical Data Processing**: Converts nested dictionaries and arrays into navigable sections
/// - **Type Detection**: Automatically identifies arrays, dictionaries, JSON objects, and primitive values
/// - **Intelligent Sorting**: Numerically sorts array indices (e.g., [0], [1], ..., [10]) while alphabetically sorting other keys
/// - **Nested Navigation**: Enables drill-down exploration of complex data structures
/// - **Lazy Loading**: Processes data on first appearance for optimal performance
///
/// ## Usage
///
/// ```swift
/// let data: [String: [String: Any]] = [
///     "User Info": [
///         "name": "John Doe",
///         "age": 30,
///         "preferences": ["darkMode": true, "notifications": false]
///     ]
/// ]
///
/// let viewModel = DataBrowserViewModel(data: data)
/// await viewModel.onFirstAppear()
/// // Access viewModel.sections for processed data
/// ```
///
/// ## Topics
///
/// ### Creating a View Model
/// - ``init(data:)``
///
/// ### Managing State
/// - ``sections``
///
/// ### Lifecycle
/// - ``onFirstAppear()``
class DataBrowserViewModel: ViewModel {
    /// The raw data structure to be processed and displayed.
    private let data: [String: [String: Any]]

    /// The processed sections ready for display in the browser.
    ///
    /// Each section represents a top-level key from the input data, with its items
    /// sorted intelligently (numeric indices sorted numerically, other keys alphabetically).
    @Published var sections: [DataBrowserSection] = []

    /// Creates a new data browser view model.
    ///
    /// - Parameter data: The hierarchical data structure to browse, organized as
    ///   sections (top-level keys) containing key-value pairs.
    init(data: [String: [String: Any]]) {
        self.data = data
        super.init()
    }

    /// Prepares the view model when the view first appears.
    ///
    /// This method triggers data processing to convert the raw input data into
    /// displayable sections and items.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await prepareObjects()
    }

    /// Processes the raw data into displayable sections and items.
    ///
    /// This method:
    /// 1. Converts each top-level key into a section
    /// 2. Parses each value into typed items (arrays, dictionaries, or primitives)
    /// 3. Sorts items intelligently (numeric array indices numerically, others alphabetically)
    /// 4. Sorts sections alphabetically by title
    @MainActor
    private func prepareObjects() async {
        sections = data.map { key, value in
            let items = value.map { objectKey, objectValue in
                parseItem(key: objectKey, value: objectValue)
            }.sorted { lhs, rhs in
                // Sort array indices numerically, e.g. [0], [1], [2], ..., [10], [11]
                if let lhsIndex = extractArrayIndex(from: lhs.key),
                   let rhsIndex = extractArrayIndex(from: rhs.key) {
                    return lhsIndex < rhsIndex
                }
                // Fall back to alphabetical for non-array keys
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }

            return DataBrowserSection(title: key, items: items)
        }.sorted { $0.title < $1.title }
    }

    /// Extracts a numeric index from an array-style key.
    ///
    /// - Parameter key: The key string to parse (e.g., "[0]", "[123]")
    /// - Returns: The numeric index if the key matches the pattern, `nil` otherwise
    private func extractArrayIndex(from key: String) -> Int? {
        // Match keys like "[0]", "[123]", etc.
        guard key.hasPrefix("["), key.hasSuffix("]") else { return nil }
        let indexString = String(key.dropFirst().dropLast())
        return Int(indexString)
    }

    /// Parses a raw key-value pair into a typed data browser item.
    ///
    /// This method detects the value type and creates an appropriate `DataBrowserItem`:
    /// - Arrays become navigable items with indexed sub-items
    /// - Dictionaries become navigable items with their key-value pairs
    /// - JSON objects are parsed and handled as arrays or dictionaries
    /// - Primitives (strings, numbers, booleans) become plain display items
    ///
    /// - Parameters:
    ///   - key: The key/label for this item
    ///   - value: The raw value to parse
    /// - Returns: A typed `DataBrowserItem` ready for display
    private func parseItem(key: String, value: Any) -> DataBrowserItem {
        let dataRow = DataRow(title: key, from: value)

        switch dataRow {
        case .array(let title, let arrayData):
            var subData: [String: Any] = [:]
            arrayData.enumerated().forEach { index, element in
                subData["\(index)"] = element
            }
            let nestedData: [String: [String: Any]] = ["Array Data": subData]
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: "Array",
                itemType: .navigable(data: nestedData)
            )

        case .dictionary(let title, let dictionaryData):
            let nestedData: [String: [String: Any]] = ["Dictionary Data": dictionaryData as [String: Any]]
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: "Dictionary",
                itemType: .navigable(data: nestedData)
            )

        case .json(let title, let jsonData):
            if let arrayData = jsonData as? NSArray {
                var subData: [String: Any] = [:]
                arrayData.enumerated().forEach { index, element in
                    subData["\(index)"] = element
                }
                let nestedData: [String: [String: Any]] = ["Array Data": subData]
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: "Array",
                    itemType: .navigable(data: nestedData)
                )
            } else if let dictionaryData = jsonData as? NSDictionary {
                let nestedData: [String: [String: Any]] = ["Dictionary Data": dictionaryData.swiftDictionary]
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: "Dictionary",
                    itemType: .navigable(data: nestedData)
                )
            } else {
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: String(describing: jsonData),
                    itemType: .plain
                )
            }

        case .string(let title, let stringData):
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: stringData,
                itemType: .plain
            )
        }
    }
}
