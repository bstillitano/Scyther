//
//  NetworkConditioningViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
import Foundation

/// Backs ``NetworkConditioningView``, the screen that degrades the whole app's traffic at once.
///
/// A thin front for ``NetworkConditioningStore``: the store stays the single writer, and this
/// republishes it so the screen redraws when the conditioning is changed from anywhere else.
///
/// ## Presets
///
/// ``preset`` reads as whichever named link the three fields currently describe, and writing it
/// fills those fields in. Editing any of them by hand makes it read as
/// ``NetworkConditioningPreset/custom`` again, because that is what it now is — the picker follows
/// the fields rather than the fields being locked to the picker.
///
/// ## Topics
///
/// ### Creating the Screen
/// - ``init(store:)``
///
/// ### State
/// - ``isEnabled``
/// - ``preset``
/// - ``offeredPresets``
/// - ``latency``
/// - ``bandwidthKBps``
/// - ``failureRate``
@MainActor
final class NetworkConditioningViewModel: ViewModel {
    /// The store this screen reads and writes.
    private let store: NetworkConditioningStore

    /// Keeps the store's publishers alive for the lifetime of the screen.
    private var cancellables: Set<AnyCancellable> = []

    /// Creates the screen's view model.
    ///
    /// - Parameter store: The store to mirror. Defaults to the shared store; tests pass their own.
    init(store: NetworkConditioningStore = .shared) {
        self.store = store
        super.init()
    }

    override func setup() {
        super.setup()
        // No `receive(on:)`: the store is main-actor isolated and so is this view model, so the
        // values already arrive on the main thread. Hopping would leave the screen showing stale
        // values for a frame after every change.
        store.$isEnabled
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.$condition
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Whether conditioning is applied to every intercepted request.
    ///
    /// Reads through to the store rather than mirroring it, so the screen and the menu row can
    /// never disagree about which is authoritative.
    var isEnabled: Bool {
        get { store.isEnabled }
        set { store.isEnabled = newValue }
    }

    /// The presets the picker offers.
    ///
    /// ``NetworkConditioningPreset/custom`` is not a choice a developer makes — it is what the
    /// three fields read as when they match no named link — so it is listed only while it is the
    /// current value, which is what lets the picker render that selection at all. Offering it as
    /// a choice made picking it a no-op that the picker then silently undid on the next redraw:
    /// the row snapped back to whatever it said before, with no explanation.
    var offeredPresets: [NetworkConditioningPreset] {
        let named = NetworkConditioningPreset.allCases.filter { $0 != .custom }
        return preset == .custom ? [.custom] + named : named
    }

    /// The named link the three fields currently describe.
    ///
    /// Setting it fills the fields in. Setting ``NetworkConditioningPreset/custom`` deliberately
    /// leaves them alone: "custom" is the *absence* of a preset, and having it clear the fields
    /// would make picking it a destructive act. ``offeredPresets`` is why that is not a silent
    /// no-op on screen — the picker never offers Custom as something to move *to*.
    ///
    /// The configured failure code is carried across, because no preset sets one and
    /// ``NetworkConditioningPreset/matching(_:)`` deliberately ignores it when deciding which
    /// preset a condition reads as. Without this the round trip was lossy in the one direction
    /// nothing would warn about: a condition carrying a custom code read as 3G, and picking 3G —
    /// the preset it already was — silently reset the code to `.notConnectedToInternet`.
    var preset: NetworkConditioningPreset {
        get { NetworkConditioningPreset.matching(store.condition) }
        set {
            guard var condition = newValue.condition else { return }
            condition.failureCode = store.condition.failureCode
            store.condition = condition
        }
    }

    /// Seconds added before every intercepted request is sent, or before a stub answers.
    var latency: TimeInterval {
        get { store.condition.latency }
        set { store.condition.latency = newValue }
    }

    /// The bandwidth ceiling in kilobytes per second. `0` means unthrottled.
    var bandwidthKBps: Int {
        get { store.condition.bandwidthKBps ?? 0 }
        set { store.condition.bandwidthKBps = newValue > 0 ? newValue : nil }
    }

    /// The fraction of requests, from `0` to `1`, that fail instead of being sent.
    var failureRate: Double {
        get { store.condition.failureRate }
        set { store.condition.failureRate = newValue }
    }
}
