//
//  NetworkConditioningStore.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
import Foundation

/// Owns the conditioning applied to **every** intercepted request.
///
/// Latency, a bandwidth ceiling and a failure rate are things a developer wants to apply to the
/// whole app at once — which is what Network Link Conditioner does — so they are a tool of their
/// own rather than only a per-override action. A request override's own condition still exists and
/// still wins, for the times only one endpoint should be degraded.
///
/// ## Publishing
///
/// The store writes its half of ``NetworkRuleSnapshot``, the same lock-guarded channel the
/// overrides publish through, because `HTTPInterceptorURLProtocol` reads both from a thread the
/// URL loading system owns and cannot hop to the main actor to ask. A global of its own would mean
/// a second lock and a second chance for the two halves to disagree.
///
/// ## Precedence
///
/// The global condition is a **floor**, not an addition: a matching override's condition replaces
/// it outright. Adding the two would make a deliberately fast endpoint impossible to express while
/// the rest of the app is being slowed down.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Creating a Store
/// - ``init(defaults:)``
///
/// ### State
/// - ``isEnabled``
/// - ``condition``
/// - ``activate()``
@MainActor
internal final class NetworkConditioningStore: ObservableObject {
    /// The `UserDefaults` keys the store writes.
    private enum Key {
        /// The master switch. Absent means off.
        static let isEnabled = "Scyther.NetworkConditioning.Enabled"
        /// The JSON-encoded ``NetworkCondition``.
        static let condition = "Scyther.NetworkConditioning.Condition"
    }

    /// The store the menu and the interceptor both see.
    static let shared = NetworkConditioningStore()

    /// The preferences store conditioning is persisted to.
    private let defaults: UserDefaults

    /// Whether the conditioning below is applied to every intercepted request.
    ///
    /// Off by default. Conditioning the whole app is a large hammer, and a developer who does not
    /// know it is on will spend an afternoon blaming their backend.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            publish()
        }
    }

    /// The latency, bandwidth ceiling and failure rate applied while ``isEnabled``.
    @Published var condition: NetworkCondition {
        didSet {
            persistCondition()
            publish()
        }
    }

    /// Creates a store backed by a preferences store.
    ///
    /// - Parameter defaults: Where the switch and the condition are persisted. Defaults to
    ///   Scyther's own suite; tests pass a throwaway suite.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Key.isEnabled)
        self.condition = Self.decodeCondition(from: defaults.data(forKey: Key.condition))
        publish()
    }

    /// Publishes the persisted conditioning so it applies from the launch's first request.
    ///
    /// Called from ``Scyther/start()`` for the same reason the overrides are activated there:
    /// without it, conditioning a developer switched on yesterday would sit dormant after a
    /// relaunch and then take effect the moment its screen happened to be opened.
    ///
    /// Idempotent — it republishes state the store already holds.
    func activate() {
        publish()
    }

    /// Writes the store's half of the interceptor's snapshot.
    ///
    /// Publishes `nil` while the switch is off, so the interceptor has one thing to read rather
    /// than a condition and a flag it has to remember to check together.
    private func publish() {
        NetworkRuleSnapshot.update(globalCondition: isEnabled ? condition : nil)
    }

    /// Writes ``condition`` to `UserDefaults`.
    ///
    /// A failure to encode leaves the previous value in place rather than clearing it: a condition
    /// that cannot be written is a bug, and forgetting the developer's settings on top of it would
    /// not help anyone.
    private func persistCondition() {
        guard let data = try? JSONEncoder().encode(condition) else { return }
        defaults.set(data, forKey: Key.condition)
    }

    /// Decodes the persisted condition, falling back to an unconditioned one.
    ///
    /// - Parameter data: The JSON written by ``persistCondition()``, or `nil` on a first launch.
    /// - Returns: The stored condition, or a condition that changes nothing.
    private static func decodeCondition(from data: Data?) -> NetworkCondition {
        guard let data, let decoded = try? JSONDecoder().decode(NetworkCondition.self, from: data) else {
            return NetworkCondition()
        }
        return decoded
    }
}
