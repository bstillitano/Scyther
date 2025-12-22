//
//  FeatureFlagsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

/// A SwiftUI view for browsing and managing feature flags.
///
/// This view provides a searchable list of all registered feature toggles with the ability to:
/// - Enable/disable local overrides globally
/// - Toggle individual feature flags on/off
/// - Pin frequently used toggles to the top
/// - Search toggles by name
/// - Restore all toggles to their remote values
///
/// The view displays both remote and local values for each toggle, making it easy to see
/// which features have been overridden during development.
struct FeatureFlagsView: View {
    @StateObject private var viewModel = FeatureFlagsViewModel()
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    private var filteredPinnedToggles: [FeatureToggleItem] {
        guard !debouncedSearchText.isEmpty else { return viewModel.pinnedToggles }
        let search = debouncedSearchText.lowercased()
        return viewModel.pinnedToggles.filter { $0.name.lowercased().contains(search) }
    }

    private var filteredUnpinnedToggles: [FeatureToggleItem] {
        guard !debouncedSearchText.isEmpty else { return viewModel.unpinnedToggles }
        let search = debouncedSearchText.lowercased()
        return viewModel.unpinnedToggles.filter { $0.name.lowercased().contains(search) }
    }

    var body: some View {
        List {
            Section("Global Settings") {
                Toggle("Enable overrides", isOn: $viewModel.overridesEnabled)

                Button("Restore remote values") {
                    viewModel.restoreDefaults()
                }
            }

            if !filteredPinnedToggles.isEmpty {
                Section("Pinned") {
                    ForEach(filteredPinnedToggles) { toggle in
                        toggleRow(for: toggle)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.togglePin(for: toggle.name)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }

            Section("Toggles") {
                if viewModel.toggles.isEmpty {
                    Text("No toggles configured")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredUnpinnedToggles.isEmpty && debouncedSearchText.isEmpty {
                    Text("All toggles are pinned")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredUnpinnedToggles.isEmpty {
                    Text("No matching toggles")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(filteredUnpinnedToggles) { toggle in
                        toggleRow(for: toggle)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.togglePin(for: toggle.name)
                                } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .navigationTitle("Feature Flags")
        .searchable(text: $searchText, prompt: "Search toggles")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    @ViewBuilder
    private func toggleRow(for toggle: FeatureToggleItem) -> some View {
        Toggle(isOn: viewModel.binding(for: toggle.name)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toggle.name)
                Text("Remote: \(toggle.remoteValue ? "true" : "false")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeatureFlagsView()
    }
}
