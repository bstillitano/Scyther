//
//  NetworkRuleSnapshot.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The rule set as the interceptor sees it.
///
/// `HTTPInterceptorURLProtocol` callbacks run on an arbitrary thread owned by the URL loading
/// system. They cannot hop to the main actor to read ``NetworkRuleStore`` without risking a
/// deadlock, so the store publishes an immutable copy here after every mutation and the
/// interceptor reads it under a lock. This mirrors `NetworkHelper.instance.ignoredURLs`, which
/// is read from the same context.
///
/// ``NetworkConditioningStore`` publishes here too. Global conditioning is a second thing the
/// interceptor has to read off the main actor, and giving it a global of its own would mean two
/// locks and two chances for the two halves to disagree; it writes its own half of one snapshot
/// instead, which is why the two writers have a function each rather than sharing one.
///
/// ## Topics
///
/// ### Reading
/// - ``current``
///
/// ### Writing
/// - ``update(isEnabled:rules:bodyDirectory:)``
/// - ``update(globalCondition:)``
enum NetworkRuleSnapshot {
    /// Everything the interceptor reads before it decides what to do with a request.
    struct State: Sendable {
        /// The overrides' master switch.
        var isEnabled: Bool
        /// Persisted overrides followed by transient ones — also their precedence order.
        var rules: [NetworkRule]
        /// Where the publishing store writes mock response bodies and map-local copies.
        var bodyDirectory: URL
        /// Conditioning applied to every intercepted request, or `nil` when it is switched off.
        ///
        /// A floor rather than an addition: a matching override's own condition replaces this one
        /// outright, so targeted conditioning always beats the global setting.
        var globalCondition: NetworkCondition?
    }

    /// Guards ``storage`` so that reads from the URL loading system's threads never observe a
    /// half-written value.
    private static let lock = NSLock()

    /// The published copy of both stores' state.
    ///
    /// - Note: Declared `nonisolated(unsafe)` because every access goes through ``lock``, which
    ///   provides the synchronisation the compiler cannot prove.
    nonisolated(unsafe) private static var storage = State(isEnabled: true,
                                                           rules: [],
                                                           bodyDirectory: NetworkRuleStore.defaultBodyDirectory,
                                                           globalCondition: nil)

    /// The current snapshot. Safe to call from any thread.
    static var current: State {
        lock.withLock { storage }
    }

    /// Replaces the overrides half of the snapshot. Called by ``NetworkRuleStore`` after every
    /// mutation.
    ///
    /// The body directory travels with the rules rather than living in a separate global, so the
    /// directory the interceptor reads mock bodies from is always the one belonging to the store
    /// that published those rules, and resetting the snapshot resets it too.
    ///
    /// Leaves ``State/globalCondition`` alone: the two stores publish independently, and an
    /// override being edited must not switch the developer's global conditioning off.
    ///
    /// - Parameters:
    ///   - isEnabled: The master switch.
    ///   - rules: Persisted rules followed by transient ones — also their precedence order.
    ///   - bodyDirectory: Where the publishing store writes mock response bodies. Defaults to
    ///     ``NetworkRuleStore/defaultBodyDirectory``, which is what a reset restores.
    static func update(isEnabled: Bool,
                       rules: [NetworkRule],
                       bodyDirectory: URL = NetworkRuleStore.defaultBodyDirectory) {
        lock.withLock {
            storage.isEnabled = isEnabled
            storage.rules = rules
            storage.bodyDirectory = bodyDirectory
        }
    }

    /// Replaces the global conditioning half of the snapshot. Called by
    /// ``NetworkConditioningStore`` after every change.
    ///
    /// - Parameter globalCondition: The conditioning to apply to every intercepted request, or
    ///   `nil` when it is switched off.
    static func update(globalCondition: NetworkCondition?) {
        lock.withLock { storage.globalCondition = globalCondition }
    }
}
