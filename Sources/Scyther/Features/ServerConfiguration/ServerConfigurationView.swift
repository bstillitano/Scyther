//
//  ServerConfigurationView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import SwiftUI

/// A SwiftUI view for browsing and switching between server configurations.
///
/// This view provides:
/// - A list of all available server configurations with selection indicators
/// - The ability to switch between configurations by tapping
/// - Display of all variables for the currently selected configuration
/// - Search functionality to filter configurations by name or variable content
/// - Context menu to copy variable values to the clipboard
///
/// The view is useful during development for quickly switching between different
/// server environments (development, staging, production, etc.).
struct ServerConfigurationView: View {
    @State private var searchText: String = ""
    @StateObject private var viewModel: ServerConfigurationViewModel = ServerConfigurationViewModel()

    var body: some View {
        List {
            Section("Configuration") {
                ForEach(viewModel.configurations) { configuration in
                    Button {
                        Task { await viewModel.didSelectConfiguration(configuration) }
                    } label: {
                        HStack {
                            Text(configuration.id)
                                .foregroundStyle(.primary)
                            Spacer()
                            if configuration.isChecked {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            Section("Variables") {
                if viewModel.variables.isEmpty {
                    Text("No variables")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.variables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = value
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                }
                                Button {
                                    UIPasteboard.general.string = "\(key): \(value)"
                                } label: {
                                    Label("Copy Key & Value", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search via name or variable key/values"
        )
        .navigationTitle("Server Configuration")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onChange(of: searchText) {
            viewModel.setSearchTerm(to: $0)
        }
    }
}
