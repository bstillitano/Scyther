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
/// including its override state, remote value, and pinned status.
///
/// ## Features
///
/// - Unique identification for list management
/// - Three-state override tracking (True / False / Remote)
/// - Remote value tracking
/// - Pin state management for organizing frequently used toggles
///
/// ## Usage
///
/// ```swift
/// let toggle = FeatureToggleItem(
///     name: "darkMode",
///     state: .on,
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
/// - ``state``
/// - ``remoteValue``
/// - ``isPinned``
/// - ``pinnedRowID``
struct FeatureToggleItem: Identifiable {
    /// Unique identifier for this toggle item.
    let id = UUID()

    /// The name of the feature toggle.
    let name: String

    /// The selected override state (True / False / Remote).
    var state: FeatureToggleState

    /// The remote value from the server.
    let remoteValue: Bool

    /// Whether this toggle is pinned to the top of the list.
    var isPinned: Bool

    /// A namespaced identifier for rendering this toggle inside the "Pinned" section.
    ///
    /// Pinned toggles remain in the main list, so the same toggle appears twice in one
    /// `List`. Namespacing the pinned copy keeps SwiftUI's row identity unambiguous.
    var pinnedRowID: String { "pinned.\(name)" }
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
///                 Picker(toggle.name, selection: viewModel.binding(for: toggle.name)) {
///                     ForEach(FeatureToggleState.allCases) { state in
///                         Text(state.displayName).tag(state)
///                     }
///                 }
///                 .pickerStyle(.menu)
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
/// represent the current state of all feature toggles. Pin state is persisted to
/// ``UserDefaults/scyther`` using the key `Scyther.FeatureFlags.PinnedToggles` and is
/// automatically restored when the view model loads. Pinned toggles remain in the full
/// ``toggles`` list, so a pinned toggle is shown both in the "Pinned" section and in the
/// main list.
///
/// ## Topics
///
/// ### State Management
/// - ``overridesEnabled``
/// - ``toggles``
/// - ``pinnedToggles``
///
/// ### Toggle Operations
/// - ``setState(_:forToggle:)``
/// - ``binding(for:)``
/// - ``togglePin(for:)``
/// - ``resetAllToRemote()``
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
    /// This array is sorted alphabetically by toggle name and includes both pinned and
    /// unpinned toggles. Use ``pinnedToggles`` to access the pinned subset; pinned toggles
    /// remain in this array as well.
    @Published var toggles: [FeatureToggleItem] = []

    /// Toggles that have been pinned to the top of the list.
    ///
    /// This computed property filters ``toggles`` to return only items where
    /// ``FeatureToggleItem/isPinned`` is `true`, maintaining the same sort order.
    var pinnedToggles: [FeatureToggleItem] {
        toggles.filter { $0.isPinned }
    }

    /// The store pinned toggle names are read from and written to.
    private let defaults: UserDefaults

    /// Creates a feature flags view model.
    ///
    /// - Parameter defaults: The store backing pin state. Defaults to Scyther's private
    ///   preferences suite; tests inject a throwaway suite.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
        super.init()
    }

    /// The set of toggle names that have been pinned, persisted in ``UserDefaults/scyther``.
    ///
    /// This property reads from and writes to ``defaults`` using the key
    /// ``pinnedTogglesKey`` to maintain pin state across app launches.
    private var pinnedToggleNames: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Self.pinnedTogglesKey) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Self.pinnedTogglesKey)
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
                    state: Self.state(forLocalValue: Scyther.featureFlags.localValue(for: toggle.name)),
                    remoteValue: toggle.remoteValue,
                    isPinned: pinned.contains(toggle.name)
                )
            }
    }

    /// Maps a stored local override value to a ``FeatureToggleState``.
    ///
    /// A `nil` value means no override is present, which maps to ``FeatureToggleState/remote``.
    ///
    /// - Parameter localValue: The stored override, or `nil` when none exists.
    /// - Returns: The corresponding three-state value.
    private static func state(forLocalValue localValue: Bool?) -> FeatureToggleState {
        switch localValue {
        case .some(true): return .on
        case .some(false): return .off
        case .none: return .remote
        }
    }

    /// Sets the override state for a specific toggle.
    ///
    /// This method updates both the underlying ``Scyther/featureFlags`` subsystem
    /// and the view model's ``toggles`` array to keep the UI in sync. Selecting
    /// ``FeatureToggleState/remote`` clears the flag's local override; selecting
    /// ``FeatureToggleState/on`` or ``FeatureToggleState/off`` stores an override.
    ///
    /// - Parameters:
    ///   - state: The new override state.
    ///   - name: The name of the toggle to update.
    ///
    /// - Note: This method is marked `@MainActor` to ensure UI updates happen
    ///   on the main thread.
    @MainActor
    func setState(_ state: FeatureToggleState, forToggle name: String) {
        switch state {
        case .on:
            Scyther.featureFlags.setLocalValue(true, for: name)
        case .off:
            Scyther.featureFlags.setLocalValue(false, for: name)
        case .remote:
            Scyther.featureFlags.clearLocalValue(for: name)
        }
        if let index = toggles.firstIndex(where: { $0.name == name }) {
            toggles[index].state = state
        }
    }

    /// Creates a binding for a toggle's override state.
    ///
    /// This method returns a two-way binding that can be used with SwiftUI's
    /// `Picker` view. The binding reads from ``toggles`` and writes via
    /// ``setState(_:forToggle:)``.
    ///
    /// - Parameter name: The name of the toggle.
    /// - Returns: A binding that reads and writes the toggle's override state.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// Picker(toggle.name, selection: viewModel.binding(for: toggle.name)) {
    ///     ForEach(FeatureToggleState.allCases) { state in
    ///         Text(state.displayName).tag(state)
    ///     }
    /// }
    /// .pickerStyle(.menu)
    /// ```
    func binding(for name: String) -> Binding<FeatureToggleState> {
        Binding(
            get: {
                self.toggles.first { $0.name == name }?.state ?? .remote
            },
            set: { newState in
                self.setState(newState, forToggle: name)
            }
        )
    }

    /// Toggles the pinned state of a feature toggle.
    ///
    /// This method updates both the in-memory ``toggles`` array and persists
    /// the change to ``UserDefaults/scyther`` via ``pinnedToggleNames``.
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

    /// Resets every toggle to its remote value.
    ///
    /// This method clears all local overrides via ``FeatureFlags/clearAllLocalValues()``,
    /// setting every toggle's state to ``FeatureToggleState/remote``. After clearing, it
    /// reloads the toggles to refresh the UI state. It is the bulk equivalent of selecting
    /// "Remote" on every individual toggle.
    ///
    /// - Note: This operation affects all toggles regardless of their current
    ///   override state.
    @MainActor
    func resetAllToRemote() {
        Scyther.featureFlags.clearAllLocalValues()
        Task {
            await loadToggles()
        }
    }
}
