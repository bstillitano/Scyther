//
//  BreakpointStore.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// Owns the breakpoints: their order, their persistence and the master switch.
///
/// The store is the single writer of breakpoint state. Every mutation persists to
/// `UserDefaults.scyther` and republishes ``BreakpointSnapshot``, so the interceptor — which runs
/// off the main actor and cannot read this class — always sees the current set. It mirrors
/// ``NetworkRuleStore`` without the parts breakpoints have no use for: there are no bodies on
/// disk to reclaim and no transient registrations, because a breakpoint is something a person
/// sets while they are watching, not something an app installs for itself.
///
/// The master switch **defaults to off**, unlike the overrides one. An override left on changes a
/// response; a breakpoint left on holds the app up, so it is opted into rather than out of.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Creating a Store
/// - ``init(defaults:)``
///
/// ### Reading
/// - ``breakpoints``
/// - ``isEnabled``
/// - ``enabledCount``
///
/// ### Mutating
/// - ``activate()``
/// - ``add(_:)``
/// - ``update(_:)``
/// - ``setEnabled(_:to:)``
/// - ``remove(id:)``
/// - ``remove(atOffsets:)``
/// - ``removeAll()``
@MainActor
internal final class BreakpointStore: ObservableObject {
    /// The `UserDefaults` keys the store writes.
    private enum Key {
        /// The JSON-encoded array of breakpoints.
        static let breakpoints = "Scyther.NetworkBreakpoints.Breakpoints"
        /// The master switch. Absent means off.
        static let isEnabled = "Scyther.NetworkBreakpoints.Enabled"
    }

    /// The store the menu and the interceptor both read.
    static let shared = BreakpointStore()

    /// The preferences store breakpoints are persisted to.
    private let defaults: UserDefaults

    /// The configured breakpoints, in the order they were added — also their precedence order.
    @Published private(set) var breakpoints: [NetworkBreakpoint] = []

    /// The master switch. Turning it off leaves every breakpoint intact but holds nothing.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            publish()
        }
    }

    /// How many breakpoints are being applied right now.
    ///
    /// Zero while the master switch is off, however many are enabled behind it: the menu badge
    /// says what is being applied, not what is configured.
    var enabledCount: Int {
        isEnabled ? breakpoints.filter(\.isEnabled).count : 0
    }

    /// Creates a store backed by a preferences store.
    ///
    /// Decoding is tolerant of a blob this version cannot read: the store starts empty rather
    /// than trapping, because a breakpoint that fails to load costs a pause the developer can set
    /// again, and there is nothing on disk pointing at it to orphan.
    ///
    /// - Parameter defaults: Where breakpoints and the master switch are persisted. Defaults to
    ///   Scyther's own suite; tests pass a throwaway suite.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
        if let stored = defaults.data(forKey: Key.breakpoints),
           let decoded = try? JSONDecoder().decode([NetworkBreakpoint].self, from: stored) {
            breakpoints = decoded
        }
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        publish()
    }

    // MARK: - Activation

    /// Publishes the current breakpoints so they apply from the launch's first request.
    ///
    /// Idempotent: it republishes state the store already holds, so calling it more than once
    /// costs a snapshot and changes nothing.
    func activate() {
        publish()
    }

    // MARK: - Mutation

    /// Adds a breakpoint, or replaces the one already registered under its identifier.
    ///
    /// - Parameter breakpoint: The breakpoint to add. Its timeout is clamped to
    ///   ``NetworkBreakpoint/timeoutRange``.
    func add(_ breakpoint: NetworkBreakpoint) {
        var updated = breakpoints
        let clamped = clamping(breakpoint)
        if let index = updated.firstIndex(where: { $0.id == clamped.id }) {
            updated[index] = clamped
        } else {
            updated.append(clamped)
        }
        breakpoints = updated
        persist()
    }

    /// Replaces the breakpoint carrying the same identifier, leaving its position alone.
    ///
    /// Does nothing when no breakpoint has that identifier, so an edit of one deleted in the
    /// meantime cannot resurrect it.
    ///
    /// - Parameter breakpoint: The edited breakpoint.
    func update(_ breakpoint: NetworkBreakpoint) {
        guard let index = breakpoints.firstIndex(where: { $0.id == breakpoint.id }) else { return }
        breakpoints[index] = clamping(breakpoint)
        persist()
    }

    /// Switches one breakpoint on or off without opening the editor.
    ///
    /// - Parameters:
    ///   - breakpoint: The breakpoint to change.
    ///   - enabled: Whether it should be evaluated.
    func setEnabled(_ breakpoint: NetworkBreakpoint, to enabled: Bool) {
        guard let index = breakpoints.firstIndex(where: { $0.id == breakpoint.id }) else { return }
        breakpoints[index].isEnabled = enabled
        persist()
    }

    /// Deletes the breakpoint with this identifier, if there is one.
    ///
    /// - Parameter id: The breakpoint's identifier.
    func remove(id: UUID) {
        let remaining = breakpoints.filter { $0.id != id }
        guard remaining.count != breakpoints.count else { return }
        breakpoints = remaining
        persist()
    }

    /// Deletes the breakpoints at these offsets, as a `ForEach` reports them.
    ///
    /// - Parameter offsets: The rows to delete.
    func remove(atOffsets offsets: IndexSet) {
        var updated = breakpoints
        updated.remove(atOffsets: offsets)
        breakpoints = updated
        persist()
    }

    /// Deletes every breakpoint.
    func removeAll() {
        guard !breakpoints.isEmpty else { return }
        breakpoints = []
        persist()
    }

    // MARK: - Private

    /// The breakpoint with its timeout brought inside the allowed range.
    ///
    /// - Parameter breakpoint: The breakpoint to clamp.
    /// - Returns: The clamped copy.
    private func clamping(_ breakpoint: NetworkBreakpoint) -> NetworkBreakpoint {
        var copy = breakpoint
        copy.timeout = NetworkBreakpoint.clampedTimeout(copy.timeout)
        return copy
    }

    /// Writes the breakpoints to `UserDefaults` and republishes the snapshot.
    private func persist() {
        if let encoded = try? JSONEncoder().encode(breakpoints) {
            defaults.set(encoded, forKey: Key.breakpoints)
        }
        publish()
    }

    /// Publishes the current state to ``BreakpointSnapshot``.
    private func publish() {
        BreakpointSnapshot.update(isEnabled: isEnabled, breakpoints: breakpoints)
    }
}
