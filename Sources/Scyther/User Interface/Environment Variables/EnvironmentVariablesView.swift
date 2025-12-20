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

class EnvironmentVariablesSwiftUIViewModel: ViewModel {
    @Published var variables: [(key: String, value: String)] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadVariables()
    }

    @MainActor
    private func loadVariables() async {
        variables = Scyther.instance.customEnvironmentVariables
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }
}

#Preview {
    NavigationStack {
        EnvironmentVariablesView()
    }
}
