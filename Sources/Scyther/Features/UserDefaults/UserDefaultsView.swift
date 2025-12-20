//
//  UserDefaultsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

/// A comprehensive browser and editor for UserDefaults values.
///
/// This view provides full CRUD (Create, Read, Update, Delete) capabilities
/// for UserDefaults entries, with support for:
/// - Viewing and editing strings, numbers, booleans, dates, and data
/// - Navigating nested arrays and dictionaries
/// - Searching across keys and values
/// - Deleting individual entries or resetting all non-Scyther values
/// - Inline boolean toggle editing
/// - Dedicated editors for strings and numbers
///
/// The view intelligently handles type detection and provides appropriate
/// UI controls for each data type.
struct UserDefaultsView: View {
    @StateObject private var viewModel = UserDefaultsViewModel()
    @State private var showingResetConfirmation = false
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    private var filteredItems: [UserDefaultItem] {
        guard !debouncedSearchText.isEmpty else { return viewModel.keyValues }
        let search = debouncedSearchText.lowercased()
        return viewModel.keyValues.filter {
            $0.key.lowercased().contains(search) ||
            $0.displayValue.lowercased().contains(search)
        }
    }

    var body: some View {
        List {
            Section("Key/Values") {
                if viewModel.keyValues.isEmpty {
                    Text("No user defaults")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredItems.isEmpty {
                    Text("No matching items")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(filteredItems) { item in
                        rowView(for: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteKey(item.key)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if debouncedSearchText.isEmpty {
                Section {
                    Button("Reset UserDefaults.standard", role: .destructive) {
                        showingResetConfirmation = true
                    }
                } footer: {
                    Text("This will delete all values stored inside `UserDefaults.standard`, created by your app. This will not clear any values created internally by Scyther that are used for debug/feature purposes.")
                }
            }
        }
        .navigationTitle("User Defaults")
        .searchable(text: $searchText, prompt: "Search keys and values")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .confirmationDialog(
            "Reset UserDefaults?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                viewModel.resetAllDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    @ViewBuilder
    private func rowView(for item: UserDefaultItem) -> some View {
        switch item.valueType {
        case .array(let data):
            NavigationLink {
                UserDefaultsArrayView(key: item.key, items: data, rootKey: item.key, keyPath: []) {
                    Task { await viewModel.loadDefaults() }
                }
            } label: {
                LabeledContent(item.key, value: item.displayValue)
            }

        case .dictionary(let data):
            NavigationLink {
                UserDefaultsDictionaryView(key: item.key, dictionary: data, rootKey: item.key, keyPath: []) {
                    Task { await viewModel.loadDefaults() }
                }
            } label: {
                LabeledContent(item.key, value: item.displayValue)
            }

        case .bool(let value):
            Toggle(item.key, isOn: viewModel.boolBinding(for: item.key, currentValue: value))

        case .string(let value):
            NavigationLink {
                UserDefaultsStringEditorView(key: item.key, initialValue: value) { newValue in
                    viewModel.updateValue(newValue, forKey: item.key)
                }
            } label: {
                LabeledContent(item.key, value: value)
            }

        case .number(let value):
            NavigationLink {
                UserDefaultsNumberEditorView(key: item.key, initialValue: value) { newValue in
                    viewModel.updateValue(newValue, forKey: item.key)
                }
            } label: {
                LabeledContent(item.key, value: item.displayValue)
            }

        case .date(let value):
            LabeledContent(item.key, value: value.formatted())
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(item.key): \(value.formatted())"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

        case .data(let value):
            LabeledContent(item.key, value: "\(value.count) bytes")
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(item.key): \(value.count) bytes"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

        case .unknown:
            LabeledContent(item.key, value: item.displayValue)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(item.key): \(item.displayValue)"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }
}

// MARK: - Array View

struct UserDefaultsArrayView: View {
    let key: String
    let items: [Any]
    let rootKey: String
    let keyPath: [Any] // Can be String (dict key) or Int (array index)
    let onUpdate: () -> Void

    init(key: String, items: [Any], rootKey: String? = nil, keyPath: [Any] = [], onUpdate: @escaping () -> Void = {}) {
        self.key = key
        self.items = items
        self.rootKey = rootKey ?? key
        self.keyPath = keyPath
        self.onUpdate = onUpdate
    }

    var body: some View {
        List {
            Section("Array Elements") {
                if items.isEmpty {
                    Text("Empty array")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, element in
                        arrayRow(index: index, element: element)
                    }
                }
            }
        }
        .navigationTitle(key)
    }

    @ViewBuilder
    private func arrayRow(index: Int, element: Any) -> some View {
        let displayValue = UserDefaultsViewModel.displayString(for: element)
        let valueType = UserDefaultsViewModel.detectValueType(element)
        let childPath = keyPath + [index]

        switch valueType {
        case .array(let nestedArray):
            NavigationLink {
                UserDefaultsArrayView(key: "[\(index)]", items: nestedArray, rootKey: rootKey, keyPath: childPath, onUpdate: onUpdate)
            } label: {
                LabeledContent("[\(index)]", value: displayValue)
            }

        case .dictionary(let nestedDict):
            NavigationLink {
                UserDefaultsDictionaryView(key: "[\(index)]", dictionary: nestedDict, rootKey: rootKey, keyPath: childPath, onUpdate: onUpdate)
            } label: {
                LabeledContent("[\(index)]", value: displayValue)
            }

        case .bool(let value):
            Toggle("[\(index)]", isOn: Binding(
                get: { value },
                set: { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            ))

        case .string(let value):
            NavigationLink {
                UserDefaultsStringEditorView(key: "[\(index)]", initialValue: value) { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            } label: {
                LabeledContent("[\(index)]", value: displayValue)
            }

        case .number(let value):
            NavigationLink {
                UserDefaultsNumberEditorView(key: "[\(index)]", initialValue: value) { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            } label: {
                LabeledContent("[\(index)]", value: displayValue)
            }

        default:
            LabeledContent("[\(index)]", value: displayValue)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "[\(index)]: \(displayValue)"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }

    private func updateNestedValue(_ newValue: Any, at path: [Any]) {
        guard var rootValue = UserDefaults.standard.object(forKey: rootKey) else { return }
        rootValue = setNestedValue(in: rootValue, at: path, to: newValue)
        UserDefaults.standard.set(rootValue, forKey: rootKey)
        onUpdate()
    }

    private func setNestedValue(in object: Any, at path: [Any], to newValue: Any) -> Any {
        guard !path.isEmpty else { return newValue }

        var path = path
        let currentKey = path.removeFirst()

        if let index = currentKey as? Int, var array = object as? [Any] {
            if path.isEmpty {
                array[index] = newValue
            } else {
                array[index] = setNestedValue(in: array[index], at: path, to: newValue)
            }
            return array
        } else if let key = currentKey as? String, var dict = object as? [String: Any] {
            if path.isEmpty {
                dict[key] = newValue
            } else if let existingValue = dict[key] {
                dict[key] = setNestedValue(in: existingValue, at: path, to: newValue)
            }
            return dict
        }

        return object
    }
}

// MARK: - Dictionary View

struct UserDefaultsDictionaryView: View {
    let key: String
    let dictionary: [String: Any]
    let rootKey: String
    let keyPath: [Any]
    let onUpdate: () -> Void

    init(key: String, dictionary: [String: Any], rootKey: String? = nil, keyPath: [Any] = [], onUpdate: @escaping () -> Void = {}) {
        self.key = key
        self.dictionary = dictionary
        self.rootKey = rootKey ?? key
        self.keyPath = keyPath
        self.onUpdate = onUpdate
    }

    private var sortedKeys: [String] {
        dictionary.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            Section("Dictionary Entries") {
                if dictionary.isEmpty {
                    Text("Empty dictionary")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(sortedKeys, id: \.self) { dictKey in
                        if let value = dictionary[dictKey] {
                            dictionaryRow(key: dictKey, value: value)
                        }
                    }
                }
            }
        }
        .navigationTitle(key)
    }

    @ViewBuilder
    private func dictionaryRow(key rowKey: String, value: Any) -> some View {
        let displayValue = UserDefaultsViewModel.displayString(for: value)
        let valueType = UserDefaultsViewModel.detectValueType(value)
        let childPath = keyPath + [rowKey]

        switch valueType {
        case .array(let nestedArray):
            NavigationLink {
                UserDefaultsArrayView(key: rowKey, items: nestedArray, rootKey: rootKey, keyPath: childPath, onUpdate: onUpdate)
            } label: {
                LabeledContent(rowKey, value: displayValue)
            }

        case .dictionary(let nestedDict):
            NavigationLink {
                UserDefaultsDictionaryView(key: rowKey, dictionary: nestedDict, rootKey: rootKey, keyPath: childPath, onUpdate: onUpdate)
            } label: {
                LabeledContent(rowKey, value: displayValue)
            }

        case .bool(let boolValue):
            Toggle(rowKey, isOn: Binding(
                get: { boolValue },
                set: { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            ))

        case .string(let stringValue):
            NavigationLink {
                UserDefaultsStringEditorView(key: rowKey, initialValue: stringValue) { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            } label: {
                LabeledContent(rowKey, value: displayValue)
            }

        case .number(let numberValue):
            NavigationLink {
                UserDefaultsNumberEditorView(key: rowKey, initialValue: numberValue) { newValue in
                    updateNestedValue(newValue, at: childPath)
                }
            } label: {
                LabeledContent(rowKey, value: displayValue)
            }

        default:
            LabeledContent(rowKey, value: displayValue)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(rowKey): \(displayValue)"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }

    private func updateNestedValue(_ newValue: Any, at path: [Any]) {
        guard var rootValue = UserDefaults.standard.object(forKey: rootKey) else { return }
        rootValue = setNestedValue(in: rootValue, at: path, to: newValue)
        UserDefaults.standard.set(rootValue, forKey: rootKey)
        onUpdate()
    }

    private func setNestedValue(in object: Any, at path: [Any], to newValue: Any) -> Any {
        guard !path.isEmpty else { return newValue }

        var path = path
        let currentKey = path.removeFirst()

        if let index = currentKey as? Int, var array = object as? [Any] {
            if path.isEmpty {
                array[index] = newValue
            } else {
                array[index] = setNestedValue(in: array[index], at: path, to: newValue)
            }
            return array
        } else if let key = currentKey as? String, var dict = object as? [String: Any] {
            if path.isEmpty {
                dict[key] = newValue
            } else if let existingValue = dict[key] {
                dict[key] = setNestedValue(in: existingValue, at: path, to: newValue)
            }
            return dict
        }

        return object
    }
}

// MARK: - String Editor View

struct UserDefaultsStringEditorView: View {
    let key: String
    let initialValue: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        Form {
            Section("Value") {
                TextField("Value", text: $text, axis: .vertical)
                    .lineLimit(5...10)
            }
        }
        .navigationTitle(key)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
            }
        }
        .onAppear {
            text = initialValue
        }
    }
}

// MARK: - Number Editor View

struct UserDefaultsNumberEditorView: View {
    let key: String
    let initialValue: NSNumber
    let onSave: (NSNumber) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var showingError = false

    private var isInteger: Bool {
        let doubleValue = initialValue.doubleValue
        return floor(doubleValue) == doubleValue
    }

    var body: some View {
        Form {
            Section("Value (\(isInteger ? "Integer" : "Decimal"))") {
                TextField("Value", text: $text)
                    .keyboardType(isInteger ? .numberPad : .decimalPad)
            }
        }
        .navigationTitle(key)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveValue()
                }
            }
        }
        .alert("Invalid Number", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid number.")
        }
        .onAppear {
            text = "\(initialValue)"
        }
    }

    private func saveValue() {
        if isInteger {
            if let intValue = Int(text) {
                onSave(NSNumber(value: intValue))
                dismiss()
            } else {
                showingError = true
            }
        } else {
            if let doubleValue = Double(text) {
                onSave(NSNumber(value: doubleValue))
                dismiss()
            } else {
                showingError = true
            }
        }
    }
}

// MARK: - Data Types

enum UserDefaultValueType {
    case string(String)
    case bool(Bool)
    case number(NSNumber)
    case date(Date)
    case data(Data)
    case array([Any])
    case dictionary([String: Any])
    case unknown
}

struct UserDefaultItem: Identifiable {
    let id = UUID()
    let key: String
    let rawValue: Any
    let valueType: UserDefaultValueType
    let displayValue: String
}

// MARK: - ViewModel

class UserDefaultsViewModel: ViewModel {
    @Published var keyValues: [UserDefaultItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDefaults()
    }

    @MainActor
    func loadDefaults() async {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
            .sorted { $0.key.lowercased() < $1.key.lowercased() }

        keyValues = defaults.map { key, value in
            let valueType = Self.detectValueType(value)
            let displayValue = Self.displayString(for: value)
            return UserDefaultItem(key: key, rawValue: value, valueType: valueType, displayValue: displayValue)
        }
    }

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

    @MainActor
    func updateValue(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        Task {
            await loadDefaults()
        }
    }

    @MainActor
    func deleteKey(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        keyValues.removeAll { $0.key == key }
    }

    @MainActor
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

#Preview {
    NavigationStack {
        UserDefaultsView()
    }
}
