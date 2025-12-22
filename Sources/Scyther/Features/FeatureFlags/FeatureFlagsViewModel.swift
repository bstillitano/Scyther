//
//  FeatureFlagsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI
import Combine

/// A view model item representing a single feature toggle in the list.
///
/// This model encapsulates all the state needed to display and manage a feature toggle,
/// including its local override value, remote value, and pinned status.
///
/// ## Features
///
/// - Unique identification for list management
/// - Local and remote value tracking
/// - Pin state management for organizing frequently used toggles
///
/// ## Usage
///
/// ```swift
/// let toggle = FeatureToggleItem(
///     name: "darkMode",
///     localValue: true,
///     remoteValue: false,
///     isPinned: true
/// )
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``id``
/// - ``name``
/// - ``localValue``
/// - ``remoteValue``
/// - ``isPinned``
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
/// including pinning, searching, and restoring defaults. This view model serves as the
/// single source of truth for feature flag state within the UI, syncing with the underlying
/// ``Scyther/featureFlags`` subsystem.
///
/// ## Features
///
/// - Global override control via ``overridesEnabled``
/// - Local value management for individual toggles
/// - Toggle pinning to organize frequently used flags
/// - Persistent pin state across app launches
/// - Batch restore of all toggles to remote values
/// - Automatic sorting and organization of toggle lists
///
/// ## Usage
///
/// The view model is typically used within ``FeatureFlagsView`` and manages all state
/// and business logic for the feature flags UI:
///
/// ```swift
/// struct FeatureFlagsView: View {
///     @StateObject private var viewModel = FeatureFlagsViewModel()
///
///     var body: some View {
///         List {
///             Toggle("Enable overrides", isOn: $viewModel.overridesEnabled)
///             ForEach(viewModel.pinnedToggles) { toggle in
///                 Toggle(toggle.name, isOn: viewModel.binding(for: toggle.name))
///             }
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Implementation Details
///
/// The view model maintains a published array of ``FeatureToggleItem`` instances that
/// represent the current state of all feature toggles. It provides computed properties
/// to separate pinned and unpinned toggles for easy UI organization.
///
/// Pin state is persisted to `UserDefaults` using the key `Scyther.FeatureFlags.PinnedToggles`
/// and is automatically restored when the view model loads.
///
/// ## Topics
///
/// ### State Management
/// - ``overridesEnabled``
/// - ``toggles``
/// - ``pinnedToggles``
/// - ``unpinnedToggles``
///
/// ### Toggle Operations
/// - ``setLocalValue(_:forToggle:)``
/// - ``binding(for:)``
/// - ``togglePin(for:)``
/// - ``restoreDefaults()``
///
/// ### Lifecycle
/// - ``onFirstAppear()``
class FeatureFlagsViewModel: ViewModel {
    /// UserDefaults key for storing pinned toggle names.
    private static let pinnedTogglesKey = "Scyther.FeatureFlags.PinnedToggles"

    /// Whether local overrides are globally enabled.
    ///
    /// When set, this property updates the underlying ``Scyther/featureFlags``
    /// subsystem's ``FeatureFlags/localOverridesEnabled`` property to ensure
    /// the global override state remains in sync.
    @Published var overridesEnabled: Bool = false {
        didSet {
            Scyther.featureFlags.localOverridesEnabled = overridesEnabled
        }
    }

    /// All feature toggles currently displayed.
    ///
    /// This array is sorted alphabetically by toggle name and includes both
    /// pinned and unpinned toggles. Use ``pinnedToggles`` and ``unpinnedToggles``
    /// to access filtered subsets.
    @Published var toggles: [FeatureToggleItem] = []

    /// Toggles that have been pinned to the top of the list.
    ///
    /// This computed property filters ``toggles`` to return only items where
    /// ``FeatureToggleItem/isPinned`` is `true`, maintaining the same sort order.
    var pinnedToggles: [FeatureToggleItem] {
        toggles.filter { $0.isPinned }
    }

    /// Toggles that are not pinned.
    ///
    /// This computed property filters ``toggles`` to return only items where
    /// ``FeatureToggleItem/isPinned`` is `false`, maintaining the same sort order.
    var unpinnedToggles: [FeatureToggleItem] {
        toggles.filter { !$0.isPinned }
    }

    /// The set of toggle names that have been pinned, persisted in UserDefaults.
    ///
    /// This property reads from and writes to `UserDefaults` using the key
    /// ``pinnedTogglesKey`` to maintain pin state across app launches.
    private var pinnedToggleNames: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: Self.pinnedTogglesKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.pinnedTogglesKey)
        }
    }

    /// Called when the view first appears.
    ///
    /// This method loads all feature toggles from the ``Scyther/featureFlags``
    /// subsystem and initializes the view model's state.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadToggles()
    }

    /// Loads all feature toggles from Scyther and updates the view state.
    ///
    /// This method:
    /// 1. Syncs ``overridesEnabled`` with the global override state
    /// 2. Retrieves all registered toggles from ``Scyther/featureFlags``
    /// 3. Sorts toggles alphabetically by name
    /// 4. Restores pin state from persistent storage
    /// 5. Updates the ``toggles`` array with fresh state
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
    /// This method updates both the underlying ``Scyther/featureFlags`` subsystem
    /// and the view model's ``toggles`` array to keep the UI in sync.
    ///
    /// - Parameters:
    ///   - value: The new local value.
    ///   - name: The name of the toggle to update.
    ///
    /// - Note: This method is marked `@MainActor` to ensure UI updates happen
    ///   on the main thread.
    @MainActor
    func setLocalValue(_ value: Bool, forToggle name: String) {
        Scyther.featureFlags.setLocalValue(value, for: name)
        if let index = toggles.firstIndex(where: { $0.name == name }) {
            toggles[index].localValue = value
        }
    }

    /// Creates a binding for a toggle's local value.
    ///
    /// This method returns a two-way binding that can be used with SwiftUI's
    /// `Toggle` view. The binding reads from ``toggles`` and writes via
    /// ``setLocalValue(_:forToggle:)``.
    ///
    /// - Parameter name: The name of the toggle.
    /// - Returns: A binding that reads and writes the toggle's local value.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// Toggle(toggle.name, isOn: viewModel.binding(for: toggle.name))
    /// ```
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
    /// This method updates both the in-memory ``toggles`` array and persists
    /// the change to `UserDefaults` via ``pinnedToggleNames``.
    ///
    /// - Parameter name: The name of the toggle to pin or unpin.
    ///
    /// - Note: If the toggle is currently pinned, it will be unpinned, and vice versa.
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
    /// This method resets all local overrides, setting each toggle's local value
    /// to match its remote value from the server. After restoration, it reloads
    /// the toggles to refresh the UI state.
    ///
    /// - Note: This operation affects all toggles regardless of their current
    ///   local override values.
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
