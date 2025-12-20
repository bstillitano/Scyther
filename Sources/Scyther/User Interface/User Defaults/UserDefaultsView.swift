//
//  UserDefaultsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct UserDefaultsView: View {
    @StateObject private var viewModel = UserDefaultsSwiftUIViewModel()
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section("Key/Values") {
                ForEach(viewModel.keyValues) { item in
                    LabeledContent(item.key, value: item.value)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(item.key): \(item.value)"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteKey(item.key)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }

            Section {
                Button("Reset UserDefaults.standard", role: .destructive) {
                    showingResetConfirmation = true
                }
            } footer: {
                Text("This will delete all values stored inside `UserDefaults.standard`, created by your app. This will not clear any values created internally by Scyther that are used for debug/feature purposes.")
            }
        }
        .navigationTitle("User Defaults")
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
}

struct UserDefaultItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class UserDefaultsSwiftUIViewModel: ViewModel {
    @Published var keyValues: [UserDefaultItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDefaults()
    }

    @MainActor
    private func loadDefaults() async {
        let defaults = UserDefaults.standard.stringStringDictionaryRepresentation
            .sorted { $0.key.lowercased() < $1.key.lowercased() }

        keyValues = defaults.map { UserDefaultItem(key: $0.key, value: $0.value) }
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
