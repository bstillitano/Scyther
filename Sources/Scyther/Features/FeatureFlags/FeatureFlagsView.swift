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
/// - Set each feature flag to True, False, or Remote via a dropdown menu
/// - Pin frequently used toggles to an additional section at the top; pinned toggles remain
///   in the main list as well
/// - Search toggles by name
/// - Reset all toggles back to their remote values
///
/// The view displays both remote and local values for each toggle, making it easy to see
/// which features have been overridden during development.
///
/// While **Enable overrides** is off, the Pinned and Toggles sections and the reset button
/// are hidden — local overrides have no effect in that state, so presenting an interactive
/// list would be misleading. The search field remains visible throughout.
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

    private var filteredToggles: [FeatureToggleItem] {
        guard !debouncedSearchText.isEmpty else { return viewModel.toggles }
        let search = debouncedSearchText.lowercased()
        return viewModel.toggles.filter { $0.name.lowercased().contains(search) }
    }

    var body: some View {
        list
            .searchable(text: $searchText, prompt: "Search toggles")
            .navigationTitle("Feature Flags")
            .onChange(of: searchText) { newValue in
                searchSubject.send(newValue)
            }
            .onChange(of: viewModel.overridesEnabled) { enabled in
                guard !enabled else { return }
                searchText = ""
                debouncedSearchText = ""
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

    private var list: some View {
        List {
            Section {
                Toggle("Enable overrides", isOn: $viewModel.overridesEnabled)

                if viewModel.overridesEnabled {
                    Button("Reset all to Remote") {
                        viewModel.resetAllToRemote()
                    }
                }
            } header: {
                Text("Global Settings")
            } footer: {
                if !viewModel.overridesEnabled {
                    Text("Enable overrides to view and modify feature flags.")
                }
            }

            if viewModel.overridesEnabled {
                if !filteredPinnedToggles.isEmpty {
                    Section("Pinned") {
                        ForEach(filteredPinnedToggles, id: \.pinnedRowID) { toggle in
                            toggleRow(for: toggle)
                                .swipeActions(edge: .trailing) {
                                    pinButton(for: toggle)
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
                    } else if filteredToggles.isEmpty {
                        Text("No matching toggles")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredToggles) { toggle in
                            toggleRow(for: toggle)
                                .swipeActions(edge: .trailing) {
                                    pinButton(for: toggle)
                                }
                        }
                    }
                }
            }
        }
    }

    /// The pin/unpin swipe action for a toggle.
    ///
    /// The label reflects the toggle's pin state rather than which section it is rendered
    /// in, because pinned toggles remain in the main list.
    @ViewBuilder
    private func pinButton(for toggle: FeatureToggleItem) -> some View {
        Button {
            viewModel.togglePin(for: toggle.name)
        } label: {
            Label(
                toggle.isPinned ? "Unpin" : "Pin",
                systemImage: toggle.isPinned ? "pin.slash" : "pin"
            )
        }
        .tint(.blue)
    }

    @ViewBuilder
    private func toggleRow(for toggle: FeatureToggleItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toggle.name)
                Text("Remote: \(toggle.remoteValue ? "true" : "false")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(selection: viewModel.binding(for: toggle.name)) {
                ForEach(FeatureToggleState.allCases) { state in
                    Text(state.displayName).tag(state)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

#Preview {
    NavigationStack {
        FeatureFlagsView()
    }
}
