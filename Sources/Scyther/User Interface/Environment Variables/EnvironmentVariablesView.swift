//
//  EnvironmentVariablesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct EnvironmentVariablesView: View {
    @StateObject private var viewModel = EnvironmentVariablesSwiftUIViewModel()

    var body: some View {
        List {
            Section("Configuration Variables") {
                if viewModel.staticVariables.isEmpty {
                    Text("No variables configured")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.staticVariables) { variable in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variable.key)
                            Text(variable.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(variable.key): \(variable.value)"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }

            Section("Custom Key/Values") {
                if viewModel.customVariables.isEmpty {
                    Text("No variables configured")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.customVariables) { variable in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variable.key)
                            Text(variable.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(variable.key): \(variable.value)"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Environment Variables")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

struct EnvironmentVariable: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class EnvironmentVariablesSwiftUIViewModel: ViewModel {
    @Published var staticVariables: [EnvironmentVariable] = []
    @Published var customVariables: [EnvironmentVariable] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadVariables()
    }

    @MainActor
    private func loadVariables() async {
        customVariables = Scyther.instance.customEnvironmentVariables
            .map { EnvironmentVariable(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }
}

#Preview {
    NavigationStack {
        EnvironmentVariablesView()
    }
}
