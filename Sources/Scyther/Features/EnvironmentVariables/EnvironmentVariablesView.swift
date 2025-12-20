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
/// feature flags. Values can be copied to the clipboard via context menu.
struct EnvironmentVariablesView: View {
    @StateObject private var viewModel = EnvironmentVariablesViewModel()

    var body: some View {
        List {
            Section("Custom Key/Values") {
                if viewModel.variables.isEmpty {
                    Text("No variables configured")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.variables, id: \.key) { key, value in
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
        .navigationTitle("Environment Variables")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

/// View model managing the environment variables display.
///
/// Loads and sorts environment variables from `Scyther.environmentVariables`.
class EnvironmentVariablesViewModel: ViewModel {
    @Published var variables: [(key: String, value: String)] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadVariables()
    }

    @MainActor
    private func loadVariables() async {
        variables = Scyther.environmentVariables
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }
}

#Preview {
    NavigationStack {
        EnvironmentVariablesView()
    }
}
