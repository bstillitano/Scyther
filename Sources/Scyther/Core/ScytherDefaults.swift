//
//  ScytherDefaults.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// Scyther's private preferences store.
///
/// Every setting, override and preference Scyther persists is written here rather than to
/// `UserDefaults.standard`, so that a host app clearing its own defaults does not destroy
/// Scyther's state.
///
/// ## Why a separate suite
///
/// Apps commonly wipe their preferences when a user signs out, using either of:
///
/// ```swift
/// UserDefaults.standard.dictionaryRepresentation().keys
///     .forEach(UserDefaults.standard.removeObject(forKey:))
///
/// UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
/// ```
///
/// Both operate on the **application domain** only. A named suite is a separate persistent
/// domain, so neither touches it. On iOS the suite is written to
/// `<container>/Library/Preferences/com.scyther.settings.plist`, inside the app's own
/// sandbox — a fixed suite name therefore carries no cross-app collision risk.
///
/// ## Migration
///
/// Earlier versions of Scyther wrote to `UserDefaults.standard`. The first time
/// ``UserDefaults/scyther`` is accessed, ``migrateIfNeeded(from:to:)`` moves every key
/// prefixed `scyther` (compared case-insensitively) into the suite and removes it from the
/// standard store, so existing overrides, pins and spoofed locations survive the upgrade.
///
/// ## Topics
///
/// ### Configuration
/// - ``suiteName``
/// - ``keyPrefix``
/// - ``migrationKey``
///
/// ### Migration
/// - ``migrate(from:to:)``
/// - ``migrateIfNeeded(from:to:)``
///
/// ### Construction
/// - ``makeStore()``
internal enum ScytherDefaults {
    /// The name of the `UserDefaults` suite backing ``UserDefaults/scyther``.
    static let suiteName = "com.scyther.settings"

    /// The prefix every Scyther-owned defaults key carries, compared case-insensitively.
    ///
    /// Scyther's keys are consistently namespaced (`Scyther_*`, `Scyther.*`, `scyther.*`),
    /// which makes this a safe predicate for deciding what belongs to Scyther during
    /// migration.
    static let keyPrefix = "scyther"

    /// The key recording that the one-time migration out of `UserDefaults.standard` has run.
    ///
    /// Stored in the destination suite so that clearing the standard store can never cause
    /// the migration to run a second time.
    static let migrationKey = "Scyther.Defaults.DidMigrateFromStandard"

    /// Builds the Scyther preferences store and runs the one-time migration.
    ///
    /// - Returns: The `com.scyther.settings` suite, or `UserDefaults.standard` if the suite
    ///   could not be created. Falling back keeps Scyther functional rather than trapping;
    ///   the only consequence is the loss of isolation.
    static func makeStore() -> UserDefaults {
        guard let store = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        migrateIfNeeded(from: .standard, to: store)
        return store
    }

    /// Runs ``migrate(from:to:)`` once, then records that it has happened.
    ///
    /// Subsequent calls return immediately. This guard lives here rather than inside
    /// ``migrate(from:to:)`` so the migration itself stays a pure, directly testable
    /// operation.
    ///
    /// - Parameters:
    ///   - source: The store to migrate legacy keys out of.
    ///   - destination: The store to migrate legacy keys into, and where the completion
    ///     flag is recorded.
    static func migrateIfNeeded(from source: UserDefaults, to destination: UserDefaults) {
        guard !destination.bool(forKey: migrationKey) else { return }
        migrate(from: source, to: destination)
        destination.set(true, forKey: migrationKey)
    }

    /// Moves every ``keyPrefix``-prefixed key from one store to another.
    ///
    /// A key already present in `destination` is left alone — newer state is never
    /// clobbered by a stale value — but is still removed from `source`, so the migration
    /// always leaves the source clean.
    ///
    /// - Parameters:
    ///   - source: The store to read from and remove keys from.
    ///   - destination: The store to write keys into.
    ///
    /// - Note: `dictionaryRepresentation()` also returns inherited global-domain keys. That
    ///   is harmless here because no `NSGlobalDomain` key carries the `scyther` prefix, so
    ///   the filter excludes them.
    static func migrate(from source: UserDefaults, to destination: UserDefaults) {
        let legacyKeys = source.dictionaryRepresentation().keys
            .filter { $0.lowercased().hasPrefix(keyPrefix) }

        for key in legacyKeys {
            if destination.object(forKey: key) == nil {
                destination.set(source.object(forKey: key), forKey: key)
            }
            source.removeObject(forKey: key)
        }
    }
}

public extension UserDefaults {
    /// Scyther's private preferences store, isolated from `UserDefaults.standard`.
    ///
    /// Backed by the `com.scyther.settings` suite. Host apps that clear their standard
    /// defaults — a common sign-out behaviour — leave this store untouched, so feature flag
    /// overrides, pinned items, spoofed locations and every other Scyther setting persist.
    ///
    /// On first access, any Scyther keys left behind in `UserDefaults.standard` by an
    /// earlier version are migrated across automatically.
    ///
    /// ```swift
    /// UserDefaults.scyther.set(true, forKey: "Scyther_grid_overlay_enabled")
    /// ```
    ///
    /// - Note: Declared `nonisolated(unsafe)` because the iOS SDK marks `UserDefaults` as
    ///   non-`Sendable`. `UserDefaults` is documented as thread-safe, and this property is
    ///   an immutable `let`, so unsynchronised access from any actor is safe. This mirrors
    ///   the `nonisolated` accessors already used across Scyther to avoid main-actor hops.
    nonisolated(unsafe) static let scyther: UserDefaults = ScytherDefaults.makeStore()
}
