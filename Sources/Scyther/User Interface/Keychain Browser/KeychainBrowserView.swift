//
//  KeychainBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine
import Security

struct KeychainBrowserView: View {
    @StateObject private var viewModel = KeychainBrowserViewModel()
    @State private var showingClearConfirmation = false
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    private func filteredItems(for section: KeychainSection) -> [KeychainItem] {
        guard !debouncedSearchText.isEmpty else { return section.items }
        let search = debouncedSearchText.lowercased()
        return section.items.filter {
            $0.account.lowercased().contains(search) ||
            $0.displayValue.lowercased().contains(search) ||
            ($0.service?.lowercased().contains(search) ?? false)
        }
    }

    var body: some View {
        List {
            ForEach(viewModel.sections) { section in
                let filtered = filteredItems(for: section)

                Section(section.title) {
                    if section.items.isEmpty {
                        Text("No items")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if filtered.isEmpty {
                        Text("No matching items")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filtered) { item in
                            NavigationLink {
                                KeychainItemDetailView(item: item) {
                                    Task { await viewModel.loadItems() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.account)
                                    if let service = item.service {
                                        Text(service)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteItem(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if debouncedSearchText.isEmpty {
                Section {
                    Button("Clear Keychain", role: .destructive) {
                        showingClearConfirmation = true
                    }
                } footer: {
                    Text("This will delete all keychain items stored by this app. This action cannot be undone.")
                }
            }
        }
        .navigationTitle("Keychain Browser")
        .searchable(text: $searchText, prompt: "Search accounts and services")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .confirmationDialog(
            "Clear Keychain?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearKeychain()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all keychain items. This action cannot be undone.")
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

// MARK: - Detail View

struct KeychainItemDetailView: View {
    let item: KeychainItem
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var isValueRevealed = false

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Account", value: item.account)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.account
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }

                if let service = item.service {
                    LabeledContent("Service", value: service)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = service
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }

                if let label = item.label {
                    LabeledContent("Label", value: label)
                }

                LabeledContent("Type", value: item.securityClass.displayName)
            }

            Section("Value") {
                if let stringValue = item.stringValue {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isValueRevealed ? stringValue : String(repeating: "•", count: min(stringValue.count, 20)))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                isValueRevealed.toggle()
                            } label: {
                                Image(systemName: isValueRevealed ? "eye.slash" : "eye")
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = stringValue
                        } label: {
                            Label("Copy Value", systemImage: "doc.on.doc")
                        }
                    }
                } else if let dataValue = item.dataValue {
                    LabeledContent("Data", value: "\(dataValue.count) bytes")
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = dataValue.base64EncodedString()
                            } label: {
                                Label("Copy Base64", systemImage: "doc.on.doc")
                            }
                        }
                } else {
                    Text("Unable to read value")
                        .foregroundStyle(.secondary)
                }
            }

            if !item.attributes.isEmpty {
                Section("Attributes") {
                    ForEach(item.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = "\(key): \(value)"
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }

            Section {
                Button("Delete Item", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Keychain Item")
        .confirmationDialog(
            "Delete this keychain item?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                KeychainBrowserViewModel.deleteKeychainItem(item)
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Models

enum KeychainSecurityClass: String, CaseIterable {
    case genericPassword
    case internetPassword
    case identity
    case certificate
    case key

    var secClass: CFString {
        switch self {
        case .genericPassword: return kSecClassGenericPassword
        case .internetPassword: return kSecClassInternetPassword
        case .identity: return kSecClassIdentity
        case .certificate: return kSecClassCertificate
        case .key: return kSecClassKey
        }
    }

    var displayName: String {
        switch self {
        case .genericPassword: return "Generic Password"
        case .internetPassword: return "Internet Password"
        case .identity: return "Identity"
        case .certificate: return "Certificate"
        case .key: return "Key"
        }
    }

    var sectionTitle: String {
        switch self {
        case .genericPassword: return "Generic Passwords"
        case .internetPassword: return "Internet Passwords"
        case .identity: return "Identities"
        case .certificate: return "Certificates"
        case .key: return "Keys"
        }
    }
}

struct KeychainSection: Identifiable {
    let id = UUID()
    let title: String
    let securityClass: KeychainSecurityClass
    var items: [KeychainItem]
}

struct KeychainItem: Identifiable {
    let id = UUID()
    let account: String
    let service: String?
    let label: String?
    let securityClass: KeychainSecurityClass
    let stringValue: String?
    let dataValue: Data?
    let attributes: [String: String]
    let rawAttributes: [String: Any]

    var displayValue: String {
        if let stringValue = stringValue {
            return stringValue
        } else if let dataValue = dataValue {
            return "\(dataValue.count) bytes"
        }
        return "N/A"
    }
}

// MARK: - ViewModel

class KeychainBrowserViewModel: ViewModel {
    @Published var sections: [KeychainSection] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadItems()
    }

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

    @MainActor
    func deleteItem(_ item: KeychainItem) {
        Self.deleteKeychainItem(item)

        // Remove from local state
        for i in sections.indices {
            sections[i].items.removeAll { $0.id == item.id }
        }
    }

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

    @MainActor
    func clearKeychain() {
        KeychainBrowser.clearKeychain()
        Task {
            await loadItems()
        }
    }
}

#Preview {
    NavigationStack {
        KeychainBrowserView()
    }
}
