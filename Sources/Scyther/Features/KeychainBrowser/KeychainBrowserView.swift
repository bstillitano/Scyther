//
//  KeychainBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine
import Security

/// A SwiftUI view for browsing and managing keychain items.
///
/// Provides a comprehensive interface for viewing all keychain entries accessible
/// by the application, organized by security class (Generic Passwords, Internet
/// Passwords, Identities). Supports searching, individual item deletion, and
/// bulk keychain clearing.
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
                        Text(localized("No items"))
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if filtered.isEmpty {
                        Text(localized("No matching items"))
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
                                    Label(localized("Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if debouncedSearchText.isEmpty {
                Section {
                    Button(localized("Clear Keychain"), role: .destructive) {
                        showingClearConfirmation = true
                    }
                } footer: {
                    Text(localized("This will delete all keychain items stored by this app. This action cannot be undone."))
                }
            }
        }
        .navigationTitle(localized("Keychain Browser"))
        .searchable(text: $searchText, prompt: localized("Search accounts and services"))
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .confirmationDialog(
            localized("Clear the entire keychain?"),
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Clear All"), role: .destructive) {
                viewModel.clearKeychain()
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This will delete all keychain items. This action cannot be undone."))
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
            Section(localized("Account")) {
                LabeledContent(localized("Account"), value: item.account)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.account
                        } label: {
                            Label(localized("Copy"), systemImage: "doc.on.doc")
                        }
                    }

                if let service = item.service {
                    LabeledContent(localized("Service"), value: service)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = service
                            } label: {
                                Label(localized("Copy"), systemImage: "doc.on.doc")
                            }
                        }
                }

                if let label = item.label {
                    LabeledContent(localized("Label"), value: label)
                }

                LabeledContent(localized("Type"), value: item.securityClass.displayName)
            }

            Section(localized("Value")) {
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
                            Label(localized("Copy Value"), systemImage: "doc.on.doc")
                        }
                    }
                } else if let dataValue = item.dataValue {
                    LabeledContent(localized("Data"), value: localized("\(dataValue.count) bytes"))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = dataValue.base64EncodedString()
                            } label: {
                                Label(localized("Copy Base64"), systemImage: "doc.on.doc")
                            }
                        }
                } else {
                    Text(localized("Unable to read value"))
                        .foregroundStyle(.secondary)
                }
            }

            if !item.attributes.isEmpty {
                Section(localized("Attributes")) {
                    ForEach(item.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = "\(key): \(value)"
                                } label: {
                                    Label(localized("Copy"), systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }

            Section {
                Button(localized("Delete Item"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(localized("Keychain Item"))
        .confirmationDialog(
            localized("Delete this keychain item?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Delete"), role: .destructive) {
                KeychainBrowserViewModel.deleteKeychainItem(item)
                onDelete()
                dismiss()
            }
            Button(localized("Cancel"), role: .cancel) {}
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
        case .genericPassword: return localized("Generic Password")
        case .internetPassword: return localized("Internet Password")
        case .identity: return localized("Identity")
        case .certificate: return localized("Certificate")
        case .key: return localized("Key")
        }
    }

    var sectionTitle: String {
        switch self {
        case .genericPassword: return localized("Generic Passwords")
        case .internetPassword: return localized("Internet Passwords")
        case .identity: return localized("Identities")
        case .certificate: return localized("Certificates")
        case .key: return localized("Keys")
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
            return localized("\(dataValue.count) bytes")
        }
        return localized("N/A")
    }
}

#Preview {
    NavigationStack {
        KeychainBrowserView()
    }
}
