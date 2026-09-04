//
//  EnvironmentVariablesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A view displaying custom environment variables configured in the application.
///
/// Shows key-value pairs of environment variables registered with Scyther,
/// typically used for displaying configuration values, API endpoints, or
/// feature flags. Values can be copied to the clipboard via context menu,
/// and the list is searchable by key and value.
struct EnvironmentVariablesView: View {
    @StateObject private var viewModel = EnvironmentVariablesViewModel()

    var body: some View {
        List {
            Section(localized("Custom Key/Values")) {
                if viewModel.variables.isEmpty {
                    Text(localized("No variables configured"))
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if viewModel.filteredVariables.isEmpty {
                    noSearchResults
                } else {
                    ForEach(viewModel.filteredVariables, id: \.key) { key, value in
                        LabeledContent(key, value: value)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = value
                                } label: {
                                    Label(localized("Copy Value"), systemImage: "doc.on.doc")
                                }
                                Button {
                                    UIPasteboard.general.string = "\(key): \(value)"
                                } label: {
                                    Label(localized("Copy Key & Value"), systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: localized("Search keys and values"))
        .navigationTitle(localized("Environment Variables"))
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    /// Shown when a search query matches no variables.
    @ViewBuilder
    private var noSearchResults: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text(localized("No results for \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\""))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview {
    NavigationStack {
        EnvironmentVariablesView()
    }
}
