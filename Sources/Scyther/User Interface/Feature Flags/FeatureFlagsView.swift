//
//  FeatureFlagsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct FeatureFlagsView: View {
    @StateObject private var viewModel = FeatureFlagsSwiftUIViewModel()

    var body: some View {
        List {
            Section("Global Settings") {
                Toggle("Enable overrides", isOn: $viewModel.overridesEnabled)

                Button("Restore remote values") {
                    viewModel.restoreDefaults()
                }
            }

            Section("Toggles") {
                if viewModel.toggles.isEmpty {
                    Text("No toggles configured")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach($viewModel.toggles) { $toggle in
                        Toggle(isOn: $toggle.localValue) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(toggle.name)
                                Text("Remote value: \(toggle.remoteValue ? "true" : "false")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: toggle.localValue) { newValue in
                            viewModel.setLocalValue(newValue, forToggle: toggle.name)
                        }
                    }
                }
            }
        }
        .navigationTitle("Feature Flags")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

struct FeatureToggleItem: Identifiable {
    let id = UUID()
    let name: String
    var localValue: Bool
    let remoteValue: Bool
}

class FeatureFlagsSwiftUIViewModel: ViewModel {
    @Published var overridesEnabled: Bool = false {
        didSet {
            Toggler.instance.localOverridesEnabled = overridesEnabled
        }
    }
    @Published var toggles: [FeatureToggleItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadToggles()
    }

    @MainActor
    private func loadToggles() async {
        overridesEnabled = Toggler.instance.localOverridesEnabled

        toggles = Toggler.instance.toggles
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { toggle in
                FeatureToggleItem(
                    name: toggle.name,
                    localValue: Toggler.instance.localValue(forToggle: toggle.name) ?? toggle.remoteValue,
                    remoteValue: toggle.remoteValue
                )
            }
    }

    @MainActor
    func setLocalValue(_ value: Bool, forToggle name: String) {
        Toggler.instance.setLocalValue(value: value, forToggleWithName: name)
    }

    @MainActor
    func restoreDefaults() {
        for toggle in Toggler.instance.toggles {
            Toggler.instance.setLocalValue(value: toggle.remoteValue, forToggleWithName: toggle.name)
        }
        Task {
            await loadToggles()
        }
    }
}

#Preview {
    NavigationStack {
        FeatureFlagsView()
    }
}
