//
//  FeatureFlagsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

struct FeatureFlagsView: View {
    @StateObject private var viewModel = FeatureFlagsSwiftUIViewModel()
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

struct FeatureToggleItem: Identifiable {
    let id = UUID()
    let name: String
    var localValue: Bool
    let remoteValue: Bool
    var isPinned: Bool
}

class FeatureFlagsSwiftUIViewModel: ViewModel {
    private static let pinnedTogglesKey = "Scyther.FeatureFlags.PinnedToggles"

    @Published var overridesEnabled: Bool = false {
        didSet {
            Toggler.instance.localOverridesEnabled = overridesEnabled
        }
    }
    @Published var toggles: [FeatureToggleItem] = []

    var pinnedToggles: [FeatureToggleItem] {
        toggles.filter { $0.isPinned }
    }

    var unpinnedToggles: [FeatureToggleItem] {
        toggles.filter { !$0.isPinned }
    }

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

    @MainActor
    private func loadToggles() async {
        overridesEnabled = Toggler.instance.localOverridesEnabled
        let pinned = pinnedToggleNames

        toggles = Toggler.instance.toggles
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { toggle in
                FeatureToggleItem(
                    name: toggle.name,
                    localValue: Toggler.instance.localValue(forToggle: toggle.name) ?? toggle.remoteValue,
                    remoteValue: toggle.remoteValue,
                    isPinned: pinned.contains(toggle.name)
                )
            }
    }

    @MainActor
    func setLocalValue(_ value: Bool, forToggle name: String) {
        Toggler.instance.setLocalValue(value: value, forToggleWithName: name)
        if let index = toggles.firstIndex(where: { $0.name == name }) {
            toggles[index].localValue = value
        }
    }

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
