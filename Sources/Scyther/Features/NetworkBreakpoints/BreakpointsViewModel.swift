//
//  BreakpointsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Combine
import Foundation

/// Backs ``BreakpointsView``, the list of configured breakpoints.
///
/// A thin front for ``BreakpointStore``: the store stays the single writer, and this republishes
/// its breakpoints so the list redraws when one is added, edited or switched off.
///
/// ## Deletion
///
/// A swipe records the breakpoints in ``pendingDeletions`` rather than deleting them, so the view
/// can put an alert in front of them — the same shape the overrides list uses.
///
/// ## Topics
///
/// ### Creating the List
/// - ``init(store:)``
///
/// ### Reading
/// - ``breakpoints``
/// - ``isEnabled``
/// - ``isEmpty``
/// - ``subtitle(for:)``
///
/// ### Mutating
/// - ``setEnabled(_:to:)``
///
/// ### Confirming a Deletion
/// - ``pendingDeletions``
/// - ``requestDeletion(at:)``
/// - ``requestDeletion(of:)``
/// - ``confirmDeletion()``
/// - ``cancelDeletion()``
final class BreakpointsViewModel: ViewModel {
    /// The configured breakpoints, mirrored from the store.
    @Published private(set) var breakpoints: [NetworkBreakpoint] = []

    /// The breakpoints a swipe has proposed deleting, awaiting confirmation. Empty hides the
    /// alert.
    ///
    /// A list rather than one breakpoint because `onDelete` reports an `IndexSet`: in edit mode
    /// several rows can be deleted in one gesture, and taking only the first offset would
    /// silently keep the rest.
    @Published var pendingDeletions: [NetworkBreakpoint] = []

    /// The store this list reads and writes.
    private let store: BreakpointStore

    /// Keeps the store's publishers alive for the lifetime of the list.
    private var cancellables: Set<AnyCancellable> = []

    /// Creates the list.
    ///
    /// - Parameter store: The store to mirror. Defaults to the shared store; tests pass their own.
    init(store: BreakpointStore = .shared) {
        self.store = store
        super.init()
    }

    override func setup() {
        super.setup()
        // No `receive(on:)`: the store is main-actor isolated and so is this view model, so the
        // values already arrive on the main thread.
        store.$breakpoints
            .sink { [weak self] breakpoints in self?.breakpoints = breakpoints }
            .store(in: &cancellables)
        store.$isEnabled
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// The master switch. Turning it off leaves every breakpoint intact but holds nothing.
    ///
    /// Reads through to the store rather than mirroring it, so the two can never disagree about
    /// which is authoritative.
    var isEnabled: Bool {
        get { store.isEnabled }
        set { store.isEnabled = newValue }
    }

    /// Whether the list has nothing to show.
    var isEmpty: Bool { breakpoints.isEmpty }

    /// The subtitle for one breakpoint's row: which side it holds, and for how long.
    ///
    /// It does not say whether the breakpoint is enabled — the row shows that by reading as
    /// disabled, which is something a developer takes in without reading at all.
    ///
    /// - Parameter breakpoint: The breakpoint the row shows.
    /// - Returns: For example `Request · 60 seconds`.
    func subtitle(for breakpoint: NetworkBreakpoint) -> String {
        "\(breakpoint.stage.title) · \(NetworkBreakpoint.secondsText(breakpoint.timeout))"
    }

    /// Enables or disables a single breakpoint.
    ///
    /// - Parameters:
    ///   - breakpoint: The breakpoint to change.
    ///   - isEnabled: Whether the interceptor should evaluate it.
    func setEnabled(_ breakpoint: NetworkBreakpoint, to isEnabled: Bool) {
        store.setEnabled(breakpoint, to: isEnabled)
    }

    /// Records the swiped breakpoints so the view can confirm before anything is deleted.
    ///
    /// - Parameter offsets: The offsets SwiftUI's `onDelete` reported.
    func requestDeletion(at offsets: IndexSet) {
        pendingDeletions = offsets.sorted().compactMap {
            breakpoints.indices.contains($0) ? breakpoints[$0] : nil
        }
    }

    /// Records a breakpoint the row's own delete button named, so the view can confirm first.
    ///
    /// - Parameter breakpoint: The breakpoint to delete.
    func requestDeletion(of breakpoint: NetworkBreakpoint) {
        pendingDeletions = [breakpoint]
    }

    /// Deletes everything ``pendingDeletions`` names.
    func confirmDeletion() {
        pendingDeletions.forEach { store.remove(id: $0.id) }
        pendingDeletions = []
    }

    /// Abandons a proposed deletion, leaving every breakpoint in place.
    func cancelDeletion() {
        pendingDeletions = []
    }
}

internal extension NetworkBreakpoint {
    /// A number of seconds, spelled out in the reader's locale.
    ///
    /// Formatted by the system rather than through a catalogue key, because a duration is a
    /// measurement: `Duration`'s own style already knows how every supported language pluralises
    /// and abbreviates one, and a hand-written key would have to carry six plural categories in
    /// Arabic alone to say the same thing worse.
    ///
    /// - Parameter seconds: The interval to describe.
    /// - Returns: For example `60 seconds`.
    static func secondsText(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds).rounded()))
            .formatted(.units(allowed: [.seconds], width: .wide))
    }
}

internal extension NetworkBreakpoint.Stage {
    /// The localised label shown in the stage picker and in a breakpoint's subtitle.
    var title: String {
        switch self {
        case .request: return localized("Request")
        case .response: return localized("Response")
        case .both: return localized("Both")
        }
    }
}
