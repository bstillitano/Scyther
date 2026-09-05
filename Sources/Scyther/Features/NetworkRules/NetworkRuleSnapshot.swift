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
/// ## Topics
///
/// ### Reading
/// - ``current``
///
/// ### Writing
/// - ``update(isEnabled:rules:)``
enum NetworkRuleSnapshot {
    /// Guards ``storage`` so that reads from the URL loading system's threads never observe a
    /// half-written value.
    private static let lock = NSLock()

    /// The published copy of the store's state.
    ///
    /// - Note: Declared `nonisolated(unsafe)` because every access goes through ``lock``, which
    ///   provides the synchronisation the compiler cannot prove.
    nonisolated(unsafe) private static var storage: (isEnabled: Bool, rules: [NetworkRule]) = (true, [])

    /// The current snapshot. Safe to call from any thread.
    static var current: (isEnabled: Bool, rules: [NetworkRule]) {
        lock.withLock { storage }
    }

    /// Replaces the snapshot. Called by ``NetworkRuleStore`` after every mutation.
    ///
    /// - Parameters:
    ///   - isEnabled: The master switch.
    ///   - rules: Persisted rules followed by transient ones — also their precedence order.
    static func update(isEnabled: Bool, rules: [NetworkRule]) {
        lock.withLock { storage = (isEnabled, rules) }
    }
}
