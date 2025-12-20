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

/// A view model item representing a single feature toggle in the list.
struct FeatureToggleItem: Identifiable {
    /// Unique identifier for this toggle item.
    let id = UUID()

    /// The name of the feature toggle.
    let name: String

    /// The local override value.
    var localValue: Bool

    /// The remote value from the server.
    let remoteValue: Bool

    /// Whether this toggle is pinned to the top of the list.
    var isPinned: Bool
}

/// View model for the feature flags view.
///
/// Manages the state and business logic for displaying and modifying feature toggles,
/// including pinning, searching, and restoring defaults.
class FeatureFlagsViewModel: ViewModel {
    /// UserDefaults key for storing pinned toggle names.
    private static let pinnedTogglesKey = "Scyther.FeatureFlags.PinnedToggles"

    /// Whether local overrides are globally enabled.
    @Published var overridesEnabled: Bool = false {
        didSet {
            Scyther.featureFlags.localOverridesEnabled = overridesEnabled
        }
    }

    /// All feature toggles currently displayed.
    @Published var toggles: [FeatureToggleItem] = []

    /// Toggles that have been pinned to the top of the list.
    var pinnedToggles: [FeatureToggleItem] {
        toggles.filter { $0.isPinned }
    }

    /// Toggles that are not pinned.
    var unpinnedToggles: [FeatureToggleItem] {
        toggles.filter { !$0.isPinned }
    }

    /// The set of toggle names that have been pinned, persisted in UserDefaults.
    private var pinnedToggleNames: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: Self.pinnedTogglesKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.pinnedTogglesKey)
        }
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadToggles()
    }

    /// Loads all feature toggles from Scyther and updates the view state.
    @MainActor
    private func loadToggles() async {
        overridesEnabled = Scyther.featureFlags.localOverridesEnabled
        let pinned = pinnedToggleNames

        toggles = Scyther.featureFlags.all
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { toggle in
                FeatureToggleItem(
                    name: toggle.name,
                    localValue: Scyther.featureFlags.localValue(for: toggle.name) ?? toggle.remoteValue,
                    remoteValue: toggle.remoteValue,
                    isPinned: pinned.contains(toggle.name)
                )
            }
    }

    /// Sets the local override value for a specific toggle.
    ///
    /// - Parameters:
    ///   - value: The new local value.
    ///   - name: The name of the toggle to update.
    @MainActor
    func setLocalValue(_ value: Bool, forToggle name: String) {
        Scyther.featureFlags.setLocalValue(value, for: name)
        if let index = toggles.firstIndex(where: { $0.name == name }) {
            toggles[index].localValue = value
        }
    }

    /// Creates a binding for a toggle's local value.
    ///
    /// - Parameter name: The name of the toggle.
    /// - Returns: A binding that reads and writes the toggle's local value.
    func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: {
                self.toggles.first { $0.name == name }?.localValue ?? false
            },
            set: { newValue in
                self.setLocalValue(newValue, forToggle: name)
            }
        )
    }

    /// Toggles the pinned state of a feature toggle.
    ///
    /// - Parameter name: The name of the toggle to pin or unpin.
    @MainActor
    func togglePin(for name: String) {
        guard let index = toggles.firstIndex(where: { $0.name == name }) else { return }

        var pinned = pinnedToggleNames
        if toggles[index].isPinned {
            pinned.remove(name)
        } else {
            pinned.insert(name)
        }
        pinnedToggleNames = pinned

        toggles[index].isPinned.toggle()
    }

    /// Restores all toggles to their remote values.
    ///
    /// This resets all local overrides, setting each toggle's local value to match
    /// its remote value from the server.
    @MainActor
    func restoreDefaults() {
        for toggle in Scyther.featureFlags.all {
            Scyther.featureFlags.setLocalValue(toggle.remoteValue, for: toggle.name)
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
