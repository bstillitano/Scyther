//
//  ServerConfigurationView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import SwiftUI

struct ServerConfigurationView: View {
    @State private var searchText: String = ""
    @StateObject private var viewModel: ServerConfigurationViewModel = ServerConfigurationViewModel()

    var body: some View {
        List {
            Section {
                ForEach(viewModel.configurations) { configuration in
                    row(for: configuration)
                }
            } header: {
                Text("Configuration")
            }
            
            Section {
                ForEach(viewModel.variables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    row(withLabel: key, description: value)
                }
            } header: {
                Text("Variables")
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
    
    func row(for configuration: ServerConfigurationListItem) -> some View {
        Button {
            Task { await viewModel.didSelectConfiguration(configuration) }
        } label: {
            HStack {
                Text(configuration.id)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if configuration.isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
    
    func row(withLabel label: String, description: String? = nil, icon: String? = nil, andLoadingState loading: Bool = false) -> some View {
        HStack {
            if let icon {
                Label(label, systemImage: icon)
            } else {
                VStack {
                    Text(label)
                    if let description {
                        Text(description)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if loading {
                ProgressView()
            }
        }
    }
}
