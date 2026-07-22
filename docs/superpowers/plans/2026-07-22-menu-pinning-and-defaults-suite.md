# Pinnable Menu Items & Private Preferences Suite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all of Scyther's persisted settings into a private `UserDefaults` suite that survives a host app wiping the standard domain, and make every row of the main menu pinnable to a new "Pinned" section.

**Architecture:** A `ScytherDefaults` enum vends `UserDefaults.scyther` (suite `com.scyther.settings`) and runs a one-time prefix-based migration out of `UserDefaults.standard`. The hardcoded `MenuView` is refactored into a `MenuItem` / `MenuSection` data model so rows have stable identities that can be persisted as pins and rendered in two places. Feature Flags is aligned to the same "pinned rows stay in place" semantics and its list is gated behind the overrides toggle.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI, XCTest, iOS 16+, Swift Package Manager.

## Global Constraints

- **iOS only.** Never build or test for macOS. `swift build` does not work — this target requires UIKit.
- **No simulator is currently booted.** Use the fallback destination in every build/test command: `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. If one is booted by the time you run, prefer `-destination 'platform=iOS Simulator,id=<booted-udid>'`.
- **Swift 6 language mode** is enforced on both targets. `UserDefaults` is `@_nonSendable(_assumed)` in the iOS SDK — this is verified, not assumed. Any global/static of type `UserDefaults` **must** be declared `nonisolated(unsafe)` or it will not compile.
- **Minimum deployment target is iOS 16.** Use the two-parameter-free `onChange(of:) { newValue in }` form already used throughout the codebase, not the iOS 17 zero/two-parameter forms.
- **MVVM + Repository, Separation of Concerns.** View models live in their own files. New models get their own files.
- **DocC documentation is mandatory** on every new type, property and method, matching the density of the surrounding code (the codebase uses extensive `///` blocks with `## Features`, `## Usage`, `## Topics` sections).
- **README must be updated** to reflect user-visible changes.
- **Never use `.confirmationDialog`** — the project rule is alerts only. Existing `.confirmationDialog` usage in a file you are modifying should be converted to `.alert`.
- Suite name is exactly `com.scyther.settings`. Migration key is exactly `Scyther.Defaults.DidMigrateFromStandard`. Menu pin key is exactly `Scyther.Menu.PinnedItems`. Key prefix matched for migration is `scyther`, compared case-insensitively.
- All test files start with `#if !os(macOS)` and end with `#endif`, matching existing tests.

## Deviation from the spec (already agreed, recorded here)

The spec says migration enumerates `persistentDomain(forName: Bundle.main.bundleIdentifier)`. This plan uses `dictionaryRepresentation()` filtered by the `scyther` prefix instead. Reason: the prefix filter already excludes inherited global-domain keys (nothing in `NSGlobalDomain` begins with `scyther`), so the precision `persistentDomain` bought is redundant — and `persistentDomain` would force a domain-name parameter through the API purely to make it testable, plus `Bundle.main.bundleIdentifier` is optional and unreliable in a test host. The simpler signature is fully testable with throwaway suites.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Sources/Scyther/Core/ScytherDefaults.swift` | Suite construction, key prefix, one-time migration, `UserDefaults.scyther` |
| `Sources/Scyther/Features/UserDefaults/DefaultsStore.swift` | Enum identifying which store the browser is showing |
| `Sources/Scyther/Features/Menu/MenuItem.swift` | Stable identity, title and icon for every menu row |
| `Sources/Scyther/Features/Menu/MenuSection.swift` | Ordered section layout of `MenuItem`s |
| `Tests/ScytherTests/Core/ScytherDefaultsTests.swift` | Migration behaviour |
| `Tests/ScytherTests/Features/MenuItemTests.swift` | Identity round-tripping, titles |
| `Tests/ScytherTests/Features/MenuViewModelTests.swift` | Section coverage, pin state, persistence |
| `Tests/ScytherTests/Features/UserDefaultsViewModelTests.swift` | Store switching and routing |

**Modified:**

| Path | Change |
| --- | --- |
| 12 files listed in Task 2 | `UserDefaults.standard` → `UserDefaults.scyther` |
| `Sources/Scyther/Features/UserDefaults/UserDefaultsViewModel.swift` | Store selection, store-aware CRUD and reset |
| `Sources/Scyther/Features/UserDefaults/UserDefaultsView.swift` | Store picker, alert conversion, store-aware copy |
| `Sources/Scyther/Features/Menu/MenuViewModel.swift` | Sections, pin state, injectable defaults |
| `Sources/Scyther/Features/Menu/MenuView.swift` | Data-driven body, Pinned section, swipe actions |
| `Sources/Scyther/Features/FeatureFlags/FeatureFlagsViewModel.swift` | Drop `unpinnedToggles`, injectable defaults |
| `Sources/Scyther/Features/FeatureFlags/FeatureFlagsView.swift` | Gate on overrides, pinned rows stay in list |
| `Tests/ScytherTests/Features/FeatureFlagsTests.swift` | Clean the Scyther suite, not standard |
| `README.md` | "Preferences Storage" and "Pinning menu items" |

---

## Task 1: `ScytherDefaults` and the private suite

**Files:**
- Create: `Sources/Scyther/Core/ScytherDefaults.swift`
- Create: `Tests/ScytherTests/Core/ScytherDefaultsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `UserDefaults.scyther` → `UserDefaults` (public, `nonisolated(unsafe) static let`)
  - `ScytherDefaults.suiteName` → `String` = `"com.scyther.settings"` (internal)
  - `ScytherDefaults.keyPrefix` → `String` = `"scyther"` (internal)
  - `ScytherDefaults.migrationKey` → `String` = `"Scyther.Defaults.DidMigrateFromStandard"` (internal)
  - `ScytherDefaults.migrate(from: UserDefaults, to: UserDefaults)` (internal, static)
  - `ScytherDefaults.migrateIfNeeded(from: UserDefaults, to: UserDefaults)` (internal, static)
  - `ScytherDefaults.makeStore()` → `UserDefaults` (internal, static)

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Core/ScytherDefaultsTests.swift`:

```swift
//
//  ScytherDefaultsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class ScytherDefaultsTests: XCTestCase {
    private let sourceSuite = "com.scyther.tests.source"
    private let destinationSuite = "com.scyther.tests.destination"
    private var source: UserDefaults!
    private var destination: UserDefaults!

    override func setUp() {
        super.setUp()
        wipeSuites()
        source = UserDefaults(suiteName: sourceSuite)
        destination = UserDefaults(suiteName: destinationSuite)
    }

    override func tearDown() {
        source = nil
        destination = nil
        wipeSuites()
        super.tearDown()
    }

    private func wipeSuites() {
        UserDefaults.standard.removePersistentDomain(forName: sourceSuite)
        UserDefaults.standard.removePersistentDomain(forName: destinationSuite)
    }

    // MARK: - Constants

    func testSuiteNameIsStable() {
        XCTAssertEqual(ScytherDefaults.suiteName, "com.scyther.settings")
    }

    func testMigrationKeyIsStable() {
        XCTAssertEqual(ScytherDefaults.migrationKey, "Scyther.Defaults.DidMigrateFromStandard")
    }

    // MARK: - migrate(from:to:)

    func testMigrationCopiesPrefixedKeysToDestination() {
        source.set(true, forKey: "Scyther_grid_overlay_enabled")
        source.set("preset-a", forKey: "Scyther_Location_Spoofing_Route_Id")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertTrue(destination.bool(forKey: "Scyther_grid_overlay_enabled"))
        XCTAssertEqual(destination.string(forKey: "Scyther_Location_Spoofing_Route_Id"), "preset-a")
    }

    func testMigrationRemovesPrefixedKeysFromSource() {
        source.set(true, forKey: "Scyther_grid_overlay_enabled")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertNil(source.object(forKey: "Scyther_grid_overlay_enabled"))
    }

    func testMigrationIgnoresKeysWithoutThePrefix() {
        source.set("hunter2", forKey: "user_session_token")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(source.string(forKey: "user_session_token"), "hunter2")
        XCTAssertNil(destination.object(forKey: "user_session_token"))
    }

    func testMigrationMatchesPrefixCaseInsensitively() {
        source.set(1, forKey: "scyther.servers.currentId")
        source.set(2, forKey: "SCYTHER_shouting_key")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(destination.integer(forKey: "scyther.servers.currentId"), 1)
        XCTAssertEqual(destination.integer(forKey: "SCYTHER_shouting_key"), 2)
    }

    func testMigrationNeverOverwritesAnExistingDestinationValue() {
        source.set("stale", forKey: "Scyther_appearance_color_scheme")
        destination.set("fresh", forKey: "Scyther_appearance_color_scheme")

        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertEqual(destination.string(forKey: "Scyther_appearance_color_scheme"), "fresh")
        XCTAssertNil(source.object(forKey: "Scyther_appearance_color_scheme"))
    }

    func testMigrationIsIdempotent() {
        source.set(true, forKey: "Scyther_fps_counter_enabled")

        ScytherDefaults.migrate(from: source, to: destination)
        destination.set(false, forKey: "Scyther_fps_counter_enabled")
        ScytherDefaults.migrate(from: source, to: destination)

        XCTAssertFalse(destination.bool(forKey: "Scyther_fps_counter_enabled"))
    }

    // MARK: - migrateIfNeeded(from:to:)

    func testMigrateIfNeededSetsTheMigrationFlag() {
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        XCTAssertTrue(destination.bool(forKey: ScytherDefaults.migrationKey))
    }

    func testMigrateIfNeededRunsOnlyOnce() {
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        // Seed the source *after* the first run. A second call must not pick it up.
        source.set(true, forKey: "Scyther_grid_overlay_enabled")
        ScytherDefaults.migrateIfNeeded(from: source, to: destination)

        XCTAssertNil(destination.object(forKey: "Scyther_grid_overlay_enabled"))
        XCTAssertTrue(source.bool(forKey: "Scyther_grid_overlay_enabled"))
    }

    // MARK: - Store

    func testScytherStoreIsNotTheStandardStore() {
        XCTAssertFalse(UserDefaults.scyther === UserDefaults.standard)
    }

    func testScytherStoreWritesAreInvisibleToStandard() {
        let key = "Scyther_isolation_probe"
        UserDefaults.scyther.set(true, forKey: key)
        defer { UserDefaults.scyther.removeObject(forKey: key) }

        XCTAssertTrue(UserDefaults.scyther.bool(forKey: key))
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key])
    }
}
#endif
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/ScytherDefaultsTests
```

Expected: **compile failure**, `cannot find 'ScytherDefaults' in scope` and `type 'UserDefaults' has no member 'scyther'`. That is the correct failure at this stage.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Core/ScytherDefaults.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/ScytherDefaultsTests
```

Expected: `** TEST SUCCEEDED **`, 12 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Core/ScytherDefaults.swift Tests/ScytherTests/Core/ScytherDefaultsTests.swift
git commit -m "Add private UserDefaults suite with one-time migration from standard"
```

---

## Task 2: Point every Scyther call site at the new suite

**Files:**
- Modify (mechanical replacement of `UserDefaults.standard` → `UserDefaults.scyther`):
  - `Sources/Scyther/Features/LocationSpoofer/LocationSpoofer.swift` (23)
  - `Sources/Scyther/Features/AppearanceOverrides/AppearanceOverrides.swift` (10)
  - `Sources/Scyther/Features/GridOverlay/GridOverlay.swift` (8)
  - `Sources/Scyther/Core/InterfaceToolkit.swift` (8)
  - `Sources/Scyther/Features/TouchVisualiser/TouchVisualiserConfiguration.swift` (6)
  - `Sources/Scyther/Core/Scyther.swift` (5)
  - `Sources/Scyther/Features/FPSCounter/FPSCounter.swift` (4)
  - `Sources/Scyther/Features/FeatureFlags/FeatureToggle.swift` (4)
  - `Sources/Scyther/Features/DeepLinkTester/DeepLinkTester.swift` (4)
  - `Sources/Scyther/Features/CrashLogs/CrashLogger.swift` (4)
  - `Sources/Scyther/Features/FeatureFlags/FeatureFlagsViewModel.swift` (2)
  - `Sources/Scyther/Core/UIView+InterfaceToolkit.swift` (2)
- Modify: `Tests/ScytherTests/Features/FeatureFlagsTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `UserDefaults.scyther` from Task 1.
- Produces: no new API. After this task, no Scyther-owned value is written to `UserDefaults.standard`.

**Do NOT change these two files** — their `UserDefaults.standard` references are correct:
- `Sources/Scyther/Shared/Extensions/UserDefaults+Extensions.swift` — `stringStringDictionaryRepresentation` is a display helper called against whichever store the browser is showing.
- `Sources/Scyther/Features/CookieBrowser/CookieDetailsViewModel.swift` — its `synchronize()` flushes `HTTPCookieStorage`, unrelated to Scyther settings.

- [ ] **Step 1: Perform the replacement**

Every occurrence in these 12 files is a real code reference — none appear inside doc comments — so a blanket replacement is safe:

```bash
for f in \
  Sources/Scyther/Features/LocationSpoofer/LocationSpoofer.swift \
  Sources/Scyther/Features/AppearanceOverrides/AppearanceOverrides.swift \
  Sources/Scyther/Features/GridOverlay/GridOverlay.swift \
  Sources/Scyther/Core/InterfaceToolkit.swift \
  Sources/Scyther/Features/TouchVisualiser/TouchVisualiserConfiguration.swift \
  Sources/Scyther/Core/Scyther.swift \
  Sources/Scyther/Features/FPSCounter/FPSCounter.swift \
  Sources/Scyther/Features/FeatureFlags/FeatureToggle.swift \
  Sources/Scyther/Features/DeepLinkTester/DeepLinkTester.swift \
  Sources/Scyther/Features/CrashLogs/CrashLogger.swift \
  Sources/Scyther/Features/FeatureFlags/FeatureFlagsViewModel.swift \
  Sources/Scyther/Core/UIView+InterfaceToolkit.swift ; do
  sed -i '' 's/UserDefaults\.standard/UserDefaults.scyther/g' "$f"
done
```

- [ ] **Step 2: Verify the replacement is complete and correctly scoped**

```bash
grep -rn "UserDefaults.standard" --include="*.swift" Sources/
```

Expected: exactly two results, one in `Shared/Extensions/UserDefaults+Extensions.swift` and one in `Features/CookieBrowser/CookieDetailsViewModel.swift`. Any other result is a miss — fix it before continuing.

- [ ] **Step 3: Update the doc comments that now name the wrong store**

Several `///` blocks say "persisted to `UserDefaults`" or "stored in `UserDefaults.standard`". Update any that specifically name `UserDefaults.standard` to name `UserDefaults.scyther` instead:

```bash
grep -rn "UserDefaults.standard\|UserDefaults\`" --include="*.swift" Sources/Scyther/Features Sources/Scyther/Core | grep "///"
```

For each hit in the 12 migrated files, reword to reference Scyther's private store, e.g. in `Sources/Scyther/Core/Scyther.swift`:

```swift
/// This value is persisted across app launches in ``UserDefaults/scyther``, Scyther's
/// private preferences suite, so it survives the host app clearing its own defaults.
```

- [ ] **Step 4: Fix the Feature Flags test fixture, which still cleans the wrong store**

`Tests/ScytherTests/Features/FeatureFlagsTests.swift` currently wipes `UserDefaults.standard` in `setUp`/`tearDown`, and seeds values there. Since `FeatureToggle` and `FeatureFlags` now read the suite, every one of these tests would break. Replace `cleanupUserDefaults()` and every `UserDefaults.standard` reference in this file:

```swift
    private func cleanupUserDefaults() {
        let defaults = UserDefaults.scyther
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("Scyther_toggler_local_value_") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: FeatureFlags.overridesEnabledKey)
    }
```

Then apply the same replacement to the seeding calls in the test bodies:

```bash
sed -i '' 's/UserDefaults\.standard/UserDefaults.scyther/g' Tests/ScytherTests/Features/FeatureFlagsTests.swift
```

- [ ] **Step 5: Build and run the full test suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`. If `FeatureFlagsTests` fails, a `UserDefaults.standard` reference was missed in Step 4.

- [ ] **Step 6: Document the new storage in the README**

Add a top-level `## Preferences Storage` section to `README.md`, placed after `## Swift 6 Compatibility` and before `## Installation`, and add a matching entry to the Table of Contents:

```markdown
## Preferences Storage

Scyther never writes to `UserDefaults.standard`. Every setting it persists — feature flag
overrides, pinned menu items, spoofed locations, grid overlay configuration, appearance
overrides and the rest — lives in a private suite named `com.scyther.settings`.

This matters because apps commonly clear their own defaults when a user signs out:

```swift
// Both of these wipe the application domain only.
UserDefaults.standard.dictionaryRepresentation().keys
    .forEach(UserDefaults.standard.removeObject(forKey:))

UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
```

A named suite is a separate persistent domain, so neither call touches Scyther's state.
Your debugging setup survives sign-out.

The store is exposed if you need it directly:

```swift
UserDefaults.scyther.bool(forKey: "Scyther_grid_overlay_enabled")
```

### Migration from earlier versions

Versions before this change stored settings in `UserDefaults.standard`. The first time
Scyther's store is accessed it moves every key prefixed `scyther` (case-insensitive) out of
the standard store and into the suite, skipping any key the suite already has a value for,
then records that it has done so. Existing overrides and preferences carry across
automatically, and your app's standard domain is left cleaner than it was.

You can inspect and edit the suite from **Data → UserDefaults**, using the store picker at
the top of the screen.
```

- [ ] **Step 7: Commit**

```bash
git add -A Sources/ Tests/ README.md
git commit -m "Store all Scyther settings in the private preferences suite"
```

---

## Task 3: UserDefaults browser store picker

**Files:**
- Create: `Sources/Scyther/Features/UserDefaults/DefaultsStore.swift`
- Create: `Tests/ScytherTests/Features/UserDefaultsViewModelTests.swift`
- Modify: `Sources/Scyther/Features/UserDefaults/UserDefaultsViewModel.swift`
- Modify: `Sources/Scyther/Features/UserDefaults/UserDefaultsView.swift`

**Interfaces:**
- Consumes: `ScytherDefaults.suiteName`, `ScytherDefaults.keyPrefix`, `UserDefaults.scyther`.
- Produces:
  - `DefaultsStore` enum, cases `.app` and `.scyther`, conforming to `String, CaseIterable, Identifiable, Sendable`, with `var title: String` and `var defaults: UserDefaults`
  - `UserDefaultsViewModel.store` → `@Published var store: DefaultsStore`
  - `UserDefaultsViewModel.init(store: DefaultsStore = .app)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/UserDefaultsViewModelTests.swift`:

```swift
//
//  UserDefaultsViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class UserDefaultsViewModelTests: XCTestCase {
    private let appKey = "scyther_tests_app_only_key"
    private let scytherKey = "Scyther_tests_suite_only_key"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: appKey)
        UserDefaults.scyther.removeObject(forKey: scytherKey)
        super.tearDown()
    }

    func testAppStoreResolvesToStandard() {
        XCTAssertTrue(DefaultsStore.app.defaults === UserDefaults.standard)
    }

    func testScytherStoreResolvesToTheSuite() {
        XCTAssertTrue(DefaultsStore.scyther.defaults === UserDefaults.scyther)
    }

    func testEveryStoreHasATitle() {
        for store in DefaultsStore.allCases {
            XCTAssertFalse(store.title.isEmpty, "\(store) has no title")
        }
    }

    func testAppStoreLoadsKeysFromStandard() async {
        UserDefaults.standard.set("app", forKey: appKey)

        let viewModel = UserDefaultsViewModel(store: .app)
        await viewModel.loadDefaults()

        XCTAssertTrue(viewModel.keyValues.contains { $0.key == appKey })
    }

    func testScytherStoreLoadsKeysFromTheSuite() async {
        UserDefaults.scyther.set("suite", forKey: scytherKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertTrue(viewModel.keyValues.contains { $0.key == scytherKey })
    }

    func testScytherStoreDoesNotLeakStandardKeys() async {
        UserDefaults.standard.set("app", forKey: appKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertFalse(viewModel.keyValues.contains { $0.key == appKey })
    }

    func testScytherStoreExcludesGlobalDomainKeys() async {
        // AppleLanguages is inherited from NSGlobalDomain. Reading the suite via its
        // persistent domain must not surface it.
        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()

        XCTAssertFalse(viewModel.keyValues.contains { $0.key == "AppleLanguages" })
    }

    func testWritesRouteToTheSelectedStore() async {
        let viewModel = UserDefaultsViewModel(store: .scyther)
        viewModel.updateValue("written", forKey: scytherKey)

        XCTAssertEqual(UserDefaults.scyther.string(forKey: scytherKey), "written")
        XCTAssertNil(UserDefaults.standard.string(forKey: scytherKey))
    }

    func testDeletesRouteToTheSelectedStore() async {
        UserDefaults.scyther.set("doomed", forKey: scytherKey)

        let viewModel = UserDefaultsViewModel(store: .scyther)
        await viewModel.loadDefaults()
        viewModel.deleteKey(scytherKey)

        XCTAssertNil(UserDefaults.scyther.object(forKey: scytherKey))
        XCTAssertFalse(viewModel.keyValues.contains { $0.key == scytherKey })
    }
}
#endif
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/UserDefaultsViewModelTests
```

Expected: **compile failure**, `cannot find type 'DefaultsStore' in scope`.

- [ ] **Step 3: Create `DefaultsStore`**

Create `Sources/Scyther/Features/UserDefaults/DefaultsStore.swift`:

```swift
//
//  DefaultsStore.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// Identifies which `UserDefaults` store the UserDefaults browser is inspecting.
///
/// Scyther keeps its own settings in a private suite rather than the standard store, so the
/// browser needs to be able to show either one.
///
/// ## Topics
///
/// ### Cases
/// - ``app``
/// - ``scyther``
///
/// ### Properties
/// - ``title``
/// - ``defaults``
enum DefaultsStore: String, CaseIterable, Identifiable, Sendable {
    /// The host application's own defaults — `UserDefaults.standard`.
    case app

    /// Scyther's private preferences suite — ``UserDefaults/scyther``.
    case scyther

    /// Stable identifier, used for `Picker` selection and `ForEach`.
    var id: String { rawValue }

    /// The human-readable name shown in the store picker.
    var title: String {
        switch self {
        case .app: return "App"
        case .scyther: return "Scyther"
        }
    }

    /// The underlying store this case refers to.
    var defaults: UserDefaults {
        switch self {
        case .app: return .standard
        case .scyther: return .scyther
        }
    }
}
```

- [ ] **Step 4: Make the view model store-aware**

In `Sources/Scyther/Features/UserDefaults/UserDefaultsViewModel.swift`, add the `store` property and an initialiser above `keyValues`:

```swift
    /// The store currently being browsed.
    ///
    /// Changing this reloads ``keyValues`` from the newly selected store.
    @Published var store: DefaultsStore {
        didSet {
            guard oldValue != store else { return }
            Task { await loadDefaults() }
        }
    }

    /// Creates a view model browsing the given store.
    ///
    /// - Parameter store: The store to browse. Defaults to the host app's own defaults.
    init(store: DefaultsStore = .app) {
        self.store = store
        super.init()
    }
```

Replace `loadDefaults()` so `.scyther` reads the suite's persistent domain — `dictionaryRepresentation()` on a suite also returns inherited global-domain keys, which are not Scyther's and must not be shown or edited here:

```swift
    /// Loads all entries from the currently selected store.
    ///
    /// The application store is read via `dictionaryRepresentation()`, matching what the app
    /// itself sees. Scyther's suite is read via `persistentDomain(forName:)` so only keys
    /// actually written to the suite appear, without inherited global-domain noise.
    func loadDefaults() async {
        let entries: [String: Any]
        switch store {
        case .app:
            entries = UserDefaults.standard.dictionaryRepresentation()
        case .scyther:
            entries = UserDefaults.standard.persistentDomain(forName: ScytherDefaults.suiteName) ?? [:]
        }

        keyValues = entries
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { key, value in
                let valueType = Self.detectValueType(value)
                let displayValue = Self.displayString(for: value)
                return UserDefaultItem(key: key, rawValue: value, valueType: valueType, displayValue: displayValue)
            }
    }
```

Route the three mutating paths through `store.defaults`:

```swift
    func boolBinding(for key: String, currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                // Read through `self` rather than capturing `store` by value, so the binding
                // always reflects the currently selected store.
                self?.store.defaults.bool(forKey: key) ?? currentValue
            },
            set: { [weak self] newValue in
                guard let self else { return }
                self.store.defaults.set(newValue, forKey: key)
                Task { @MainActor in
                    await self.loadDefaults()
                }
            }
        )
    }

    func updateValue(_ value: Any, forKey key: String) {
        store.defaults.set(value, forKey: key)
        Task {
            await loadDefaults()
        }
    }

    func deleteKey(_ key: String) {
        store.defaults.removeObject(forKey: key)
        keyValues.removeAll { $0.key == key }
    }
```

Make the reset store-aware:

```swift
    /// Clears the currently selected store.
    ///
    /// For ``DefaultsStore/app`` this removes every key the host app created, keeping the
    /// `scyther` prefix filter as a safety net for any value an older Scyther left behind
    /// before migration. For ``DefaultsStore/scyther`` the entire suite is removed, which
    /// resets every Scyther setting including pinned items and feature flag overrides.
    ///
    /// > Warning: This action cannot be undone.
    func resetAllDefaults() {
        switch store {
        case .app:
            UserDefaults.standard.dictionaryRepresentation().keys
                .filter { !$0.lowercased().hasPrefix(ScytherDefaults.keyPrefix) }
                .forEach(UserDefaults.standard.removeObject(forKey:))
            UserDefaults.standard.synchronize()

        case .scyther:
            UserDefaults.standard.removePersistentDomain(forName: ScytherDefaults.suiteName)
        }

        Task {
            await loadDefaults()
        }
    }
```

Add `DefaultsStore` and `resetAllDefaults()` notes to the type's existing `## Topics` block so the DocC page stays accurate:

```swift
/// ### Store Selection
/// - ``store``
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/UserDefaultsViewModelTests
```

Expected: `** TEST SUCCEEDED **`, 9 tests passing.

- [ ] **Step 6: Add the picker to the view and convert the confirmation dialog to an alert**

In `Sources/Scyther/Features/UserDefaults/UserDefaultsView.swift`, add a store picker as the first section of the `List`, above `Section("Key/Values")`:

```swift
            Section {
                Picker("Store", selection: $viewModel.store) {
                    ForEach(DefaultsStore.allCases) { store in
                        Text(store.title).tag(store)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(viewModel.store == .app
                     ? "Values your app stored in UserDefaults.standard."
                     : "Values Scyther stored in its private com.scyther.settings suite.")
            }
```

Make the reset button and its footer reflect the selected store:

```swift
            if debouncedSearchText.isEmpty {
                Section {
                    Button(
                        viewModel.store == .app ? "Reset UserDefaults.standard" : "Reset all Scyther settings",
                        role: .destructive
                    ) {
                        showingResetConfirmation = true
                    }
                } footer: {
                    Text(viewModel.store == .app
                         ? "This will delete all values stored inside `UserDefaults.standard`, created by your app. Scyther's own settings live in a separate store and are not affected."
                         : "This will delete every setting Scyther has stored, including pinned menu items and feature flag overrides.")
                }
            }
```

Replace the `.confirmationDialog` block entirely — the project rule is alerts only:

```swift
        .alert("Reset UserDefaults?", isPresented: $showingResetConfirmation) {
            Button("Reset All", role: .destructive) {
                viewModel.resetAllDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.store == .app
                 ? "This will permanently delete your app's stored values. This action cannot be undone."
                 : "This will permanently delete every Scyther setting, including pinned menu items and feature flag overrides. This action cannot be undone.")
        }
```

Update the view's DocC comment, which currently says "resetting all non-Scyther values":

```swift
/// - Switching between the host app's defaults and Scyther's private suite
/// - Deleting individual entries or resetting the selected store
```

- [ ] **Step 7: Build and run the full suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Scyther/Features/UserDefaults/ Tests/ScytherTests/Features/UserDefaultsViewModelTests.swift
git commit -m "Add store picker to the UserDefaults browser"
```

---

## Task 4: `MenuItem`

**Files:**
- Create: `Sources/Scyther/Features/Menu/MenuItem.swift`
- Create: `Tests/ScytherTests/Features/MenuItemTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum MenuItem: Hashable, Identifiable` with 39 static cases plus `case developerOption(name: String)`
  - `MenuItem.id` → `String`
  - `MenuItem.init?(id: String)`
  - `MenuItem.title` → `String`
  - `MenuItem.icon` → `String?` (SF Symbol name, `nil` for rows that show no icon)
  - `MenuItem.pinnedRowID` → `String`
  - `MenuItem.allStaticCases` → `[MenuItem]`
  - `MenuItem.developerOptionPrefix` → `String` = `"developerOption."`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/MenuItemTests.swift`:

```swift
//
//  MenuItemTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class MenuItemTests: XCTestCase {

    // MARK: - Identity

    func testAllStaticCaseIdentifiersAreUnique() {
        let ids = MenuItem.allStaticCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Two menu items share an identifier")
    }

    func testAllStaticCaseIdentifiersAreNonEmpty() {
        for item in MenuItem.allStaticCases {
            XCTAssertFalse(item.id.isEmpty, "\(item) has an empty identifier")
        }
    }

    func testEveryStaticCaseRoundTripsThroughItsIdentifier() {
        for item in MenuItem.allStaticCases {
            XCTAssertEqual(MenuItem(id: item.id), item, "\(item) did not round-trip")
        }
    }

    func testDeveloperOptionRoundTrips() {
        let item = MenuItem.developerOption(name: "Reset Onboarding")
        XCTAssertEqual(MenuItem(id: item.id), item)
    }

    func testDeveloperOptionRoundTripsWithAwkwardNames() {
        let names = ["A.B.C", "has spaces", "emoji 🚀", "developerOption.nested"]
        for name in names {
            let item = MenuItem.developerOption(name: name)
            XCTAssertEqual(MenuItem(id: item.id), item, "\(name) did not round-trip")
        }
    }

    func testDeveloperOptionIdentifierIsNamespaced() {
        XCTAssertEqual(MenuItem.developerOption(name: "Panel").id, "developerOption.Panel")
    }

    func testUnknownIdentifierReturnsNil() {
        XCTAssertNil(MenuItem(id: "somethingThatWasRemovedInV2"))
    }

    func testEmptyDeveloperOptionNameReturnsNil() {
        XCTAssertNil(MenuItem(id: "developerOption."))
    }

    func testPinnedRowIdentifierIsDistinctFromTheIdentifier() {
        let item = MenuItem.featureFlags
        XCTAssertNotEqual(item.pinnedRowID, item.id)
        XCTAssertTrue(item.pinnedRowID.hasSuffix(item.id))
    }

    // MARK: - Presentation

    func testEveryStaticCaseHasANonEmptyTitle() {
        for item in MenuItem.allStaticCases {
            XCTAssertFalse(item.title.isEmpty, "\(item) has no title")
        }
    }

    func testDeveloperOptionTitleIsItsName() {
        XCTAssertEqual(MenuItem.developerOption(name: "Reset Onboarding").title, "Reset Onboarding")
    }

    func testNavigationItemsCarryAnIcon() {
        let navigationItems: [MenuItem] = [
            .networkLogs, .serverConfiguration, .environmentVariables, .featureFlags,
            .userDefaults, .cookies, .fileBrowser, .databaseBrowser, .keychainBrowser,
            .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs,
            .notificationLogger, .notificationTester, .fonts, .interfaceComponents,
            .gridOverlay, .fpsCounter, .touchVisualiser, .appearance
        ]
        for item in navigationItems {
            XCTAssertNotNil(item.icon, "\(item) should have an icon")
        }
    }

    func testDeviceAndApplicationInfoItemsHaveNoIcon() {
        let infoItems: [MenuItem] = [
            .osVersion, .hardware, .releaseYear, .uuid,
            .appIdPrefix, .displayName, .bundleId, .processId,
            .version, .buildNumber, .buildDate, .releaseType
        ]
        for item in infoItems {
            XCTAssertNil(item.icon, "\(item) should not have an icon")
        }
    }

    func testStaticCaseCountIsStable() {
        XCTAssertEqual(MenuItem.allStaticCases.count, 39)
    }
}
#endif
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuItemTests
```

Expected: **compile failure**, `cannot find type 'MenuItem' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/Menu/MenuItem.swift`:

```swift
//
//  MenuItem.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// A single row in the Scyther main menu.
///
/// Giving every row a stable identity is what makes pinning possible: an identifier can be
/// persisted, and the same case can be rendered both in its home section and in the "Pinned"
/// section without duplicating its definition.
///
/// ## Features
///
/// - Stable, persistable ``id`` for every row
/// - Lossless round-tripping via ``init(id:)``, returning `nil` for rows that no longer exist
/// - Single source of truth for each row's ``title`` and ``icon``
/// - Support for host-supplied rows via ``developerOption(name:)``
///
/// ## Usage
///
/// ```swift
/// let item = MenuItem.featureFlags
/// item.id       // "featureFlags"
/// item.title    // "Feature Flags"
/// item.icon     // "flag"
///
/// MenuItem(id: "featureFlags")   // .featureFlags
/// MenuItem(id: "removedInV2")    // nil
/// ```
///
/// ## Implementation Details
///
/// Dynamic values — a value row's description, a navigation row's destination, a toggle
/// row's binding — deliberately live in ``MenuView`` rather than here. This type owns only
/// what is stable across renders.
///
/// The device header shown at the top of the menu is not a `MenuItem`; it is a plain header
/// view and is not pinnable.
///
/// ## Topics
///
/// ### Identity
/// - ``id``
/// - ``init(id:)``
/// - ``pinnedRowID``
/// - ``allStaticCases``
///
/// ### Presentation
/// - ``title``
/// - ``icon``
enum MenuItem: Hashable, Identifiable {
    // Device
    case osVersion, hardware, releaseYear, uuid

    // Application
    case appIdPrefix, displayName, bundleId, processId
    case version, buildNumber, buildDate, releaseType

    // Development Tools
    case developerOption(name: String)

    // Networking
    case ipAddress, networkLogs, serverConfiguration, environmentVariables

    // Data
    case featureFlags, userDefaults, cookies, fileBrowser, databaseBrowser

    // Security
    case keychainBrowser

    // System Tools
    case locationSpoofer, consoleLogs, deepLinkTester, crashLogs

    // Notifications
    case notificationLogger, notificationTester, apnsToken, fcmToken

    // UI/UX
    case fonts, interfaceComponents, gridOverlay, fpsCounter
    case touchVisualiser, appearance
    case slowAnimations, showViewFrames, showViewSizes

    /// The identifier prefix distinguishing host-supplied rows from built-in ones.
    static let developerOptionPrefix = "developerOption."

    /// Every built-in row, in menu order.
    ///
    /// Excludes ``developerOption(name:)``, which is supplied at runtime by the host app via
    /// `Scyther.developerOptions`.
    static let allStaticCases: [MenuItem] = [
        .osVersion, .hardware, .releaseYear, .uuid,
        .appIdPrefix, .displayName, .bundleId, .processId,
        .version, .buildNumber, .buildDate, .releaseType,
        .ipAddress, .networkLogs, .serverConfiguration, .environmentVariables,
        .featureFlags, .userDefaults, .cookies, .fileBrowser, .databaseBrowser,
        .keychainBrowser,
        .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs,
        .notificationLogger, .notificationTester, .apnsToken, .fcmToken,
        .fonts, .interfaceComponents, .gridOverlay, .fpsCounter,
        .touchVisualiser, .appearance,
        .slowAnimations, .showViewFrames, .showViewSizes
    ]

    /// A stable identifier, safe to persist across app launches and Scyther versions.
    var id: String {
        switch self {
        case .osVersion: return "osVersion"
        case .hardware: return "hardware"
        case .releaseYear: return "releaseYear"
        case .uuid: return "uuid"
        case .appIdPrefix: return "appIdPrefix"
        case .displayName: return "displayName"
        case .bundleId: return "bundleId"
        case .processId: return "processId"
        case .version: return "version"
        case .buildNumber: return "buildNumber"
        case .buildDate: return "buildDate"
        case .releaseType: return "releaseType"
        case .developerOption(let name): return Self.developerOptionPrefix + name
        case .ipAddress: return "ipAddress"
        case .networkLogs: return "networkLogs"
        case .serverConfiguration: return "serverConfiguration"
        case .environmentVariables: return "environmentVariables"
        case .featureFlags: return "featureFlags"
        case .userDefaults: return "userDefaults"
        case .cookies: return "cookies"
        case .fileBrowser: return "fileBrowser"
        case .databaseBrowser: return "databaseBrowser"
        case .keychainBrowser: return "keychainBrowser"
        case .locationSpoofer: return "locationSpoofer"
        case .consoleLogs: return "consoleLogs"
        case .deepLinkTester: return "deepLinkTester"
        case .crashLogs: return "crashLogs"
        case .notificationLogger: return "notificationLogger"
        case .notificationTester: return "notificationTester"
        case .apnsToken: return "apnsToken"
        case .fcmToken: return "fcmToken"
        case .fonts: return "fonts"
        case .interfaceComponents: return "interfaceComponents"
        case .gridOverlay: return "gridOverlay"
        case .fpsCounter: return "fpsCounter"
        case .touchVisualiser: return "touchVisualiser"
        case .appearance: return "appearance"
        case .slowAnimations: return "slowAnimations"
        case .showViewFrames: return "showViewFrames"
        case .showViewSizes: return "showViewSizes"
        }
    }

    /// A namespaced identifier for rendering this item inside the "Pinned" section.
    ///
    /// Pinned rows remain in their home section, so the same item appears twice in one
    /// `List`. Namespacing the pinned copy keeps SwiftUI's row identity unambiguous.
    var pinnedRowID: String { "pinned.\(id)" }

    /// Reconstructs an item from a persisted identifier.
    ///
    /// - Parameter id: An identifier previously produced by ``id``.
    /// - Returns: The matching item, or `nil` if no such row exists. A `nil` result is
    ///   expected and harmless — it means a stored pin refers to a row removed in a later
    ///   version of Scyther.
    init?(id: String) {
        if id.hasPrefix(Self.developerOptionPrefix) {
            let name = String(id.dropFirst(Self.developerOptionPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .developerOption(name: name)
            return
        }

        guard let match = Self.allStaticCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    /// The row's display label.
    var title: String {
        switch self {
        case .osVersion: return "OS Version"
        case .hardware: return "Hardware"
        case .releaseYear: return "Release Year"
        case .uuid: return "UUID"
        case .appIdPrefix: return "App ID Prefix"
        case .displayName: return "Display Name"
        case .bundleId: return "Bundle ID"
        case .processId: return "Process ID"
        case .version: return "Version"
        case .buildNumber: return "Build Number"
        case .buildDate: return "Build Date"
        case .releaseType: return "Release Type"
        case .developerOption(let name): return name
        case .ipAddress: return "IP Address"
        case .networkLogs: return "Network Logs"
        case .serverConfiguration: return "Server Configuration"
        case .environmentVariables: return "Environment Variables"
        case .featureFlags: return "Feature Flags"
        case .userDefaults: return "UserDefaults"
        case .cookies: return "Cookies"
        case .fileBrowser: return "File Browser"
        case .databaseBrowser: return "Database Browser"
        case .keychainBrowser: return "Keychain Browser"
        case .locationSpoofer: return "Location Spoofer"
        case .consoleLogs: return "Console Logs"
        case .deepLinkTester: return "Deep Link Tester"
        case .crashLogs: return "Crash Logs"
        case .notificationLogger: return "Notification Logger"
        case .notificationTester: return "Notification Tester"
        case .apnsToken: return "APNS Token"
        case .fcmToken: return "FCM Token"
        case .fonts: return "Fonts"
        case .interfaceComponents: return "Interface Components"
        case .gridOverlay: return "Grid Overlay"
        case .fpsCounter: return "FPS Counter"
        case .touchVisualiser: return "Touch Visualiser"
        case .appearance: return "Appearance"
        case .slowAnimations: return "Slow Animations"
        case .showViewFrames: return "Show View Frames"
        case .showViewSizes: return "Show View Sizes"
        }
    }

    /// The SF Symbol shown alongside the row, or `nil` for rows that display no icon.
    ///
    /// Device and application information rows intentionally have no icon, matching the
    /// menu's existing appearance. ``developerOption(name:)`` also returns `nil` here — its
    /// icon comes from the host-supplied `DeveloperOption`, which may be a `UIImage` rather
    /// than an SF Symbol.
    var icon: String? {
        switch self {
        case .osVersion, .hardware, .releaseYear, .uuid,
             .appIdPrefix, .displayName, .bundleId, .processId,
             .version, .buildNumber, .buildDate, .releaseType,
             .developerOption:
            return nil
        case .ipAddress: return "network"
        case .networkLogs: return "text.page.badge.magnifyingglass"
        case .serverConfiguration: return "server.rack"
        case .environmentVariables: return "x.squareroot"
        case .featureFlags: return "flag"
        case .userDefaults: return "face.dashed"
        case .cookies: return "info.circle"
        case .fileBrowser: return "folder"
        case .databaseBrowser: return "cylinder.split.1x2"
        case .keychainBrowser: return "key"
        case .locationSpoofer: return "location.circle"
        case .consoleLogs: return "terminal"
        case .deepLinkTester: return "link"
        case .crashLogs: return "exclamationmark.triangle"
        case .notificationLogger: return "list.bullet"
        case .notificationTester: return "bell"
        case .apnsToken: return "applelogo"
        case .fcmToken: return "flame"
        case .fonts: return "textformat"
        case .interfaceComponents: return "apps.iphone"
        case .gridOverlay: return "rectangle.split.3x3"
        case .fpsCounter: return "speedometer"
        case .touchVisualiser: return "hand.point.up"
        case .appearance: return "paintbrush"
        case .slowAnimations: return "tortoise"
        case .showViewFrames: return "rectangle.dashed"
        case .showViewSizes: return "ruler"
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuItemTests
```

Expected: `** TEST SUCCEEDED **`, 14 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuItem.swift Tests/ScytherTests/Features/MenuItemTests.swift
git commit -m "Add MenuItem model giving every menu row a stable identity"
```

---

## Task 5: `MenuSection`

**Files:**
- Create: `Sources/Scyther/Features/Menu/MenuSection.swift`
- Create: `Tests/ScytherTests/Features/MenuViewModelTests.swift` (section tests only; pin tests are added in Task 6)

**Interfaces:**
- Consumes: `MenuItem` from Task 4.
- Produces:
  - `struct MenuSection: Identifiable` with `id: String`, `title: String`, `items: [MenuItem]`
  - `MenuSection.allSections(developerOptions: [DeveloperOption]) -> [MenuSection]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/MenuViewModelTests.swift`:

```swift
//
//  MenuViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class MenuViewModelTests: XCTestCase {

    // MARK: - Sections

    func testEveryStaticItemAppearsInExactlyOneSection() {
        let items = MenuSection.allSections(developerOptions: []).flatMap(\.items)

        XCTAssertEqual(Set(items).count, items.count, "An item appears in more than one section")
        XCTAssertEqual(Set(items), Set(MenuItem.allStaticCases), "Sections do not cover every item")
    }

    func testDeviceSectionIsFirst() {
        XCTAssertEqual(MenuSection.allSections(developerOptions: []).first?.title, "Device")
    }

    func testDevelopmentToolsSectionIsOmittedWhenThereAreNoDeveloperOptions() {
        let titles = MenuSection.allSections(developerOptions: []).map(\.title)
        XCTAssertFalse(titles.contains("Development Tools"))
    }

    func testDevelopmentToolsSectionIsIncludedWhenDeveloperOptionsExist() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let sections = MenuSection.allSections(developerOptions: options)

        let developmentTools = sections.first { $0.title == "Development Tools" }
        XCTAssertEqual(developmentTools?.items, [.developerOption(name: "Reset Onboarding")])
    }

    func testSectionTitlesAreInTheExpectedOrder() {
        let options = [DeveloperOption(name: "Panel", value: "x")]
        let titles = MenuSection.allSections(developerOptions: options).map(\.title)

        XCTAssertEqual(titles, [
            "Device",
            "Application",
            "Development Tools",
            "Networking",
            "Data",
            "Security",
            "System Tools",
            "Notifications",
            "UI/UX"
        ])
    }

    func testSectionIdentifiersAreUnique() {
        let ids = MenuSection.allSections(developerOptions: []).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
#endif
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuViewModelTests
```

Expected: **compile failure**, `cannot find 'MenuSection' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/Menu/MenuSection.swift`:

```swift
//
//  MenuSection.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// A titled group of rows in the Scyther main menu.
///
/// Describing the menu as data rather than as literal SwiftUI sections is what lets
/// ``MenuView`` render the same ``MenuItem`` in both its home section and the "Pinned"
/// section from a single row definition.
///
/// ## Usage
///
/// ```swift
/// for section in MenuSection.allSections(developerOptions: Scyther.developerOptions) {
///     print(section.title, section.items.count)
/// }
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``id``
/// - ``title``
/// - ``items``
///
/// ### Layout
/// - ``allSections(developerOptions:)``
struct MenuSection: Identifiable {
    /// Stable identifier, derived from the section's title.
    var id: String { title }

    /// The section header text.
    let title: String

    /// The rows in this section, in display order.
    let items: [MenuItem]

    /// The full menu layout, in display order.
    ///
    /// "Device" is always first — ``MenuView`` renders the device header inside it and
    /// inserts the "Pinned" section immediately afterwards.
    ///
    /// - Parameter developerOptions: The host app's custom options, from
    ///   `Scyther.developerOptions`. When empty, the "Development Tools" section is omitted
    ///   entirely rather than rendered blank.
    /// - Returns: Every section that should be displayed.
    static func allSections(developerOptions: [DeveloperOption]) -> [MenuSection] {
        var sections: [MenuSection] = [
            MenuSection(title: "Device", items: [
                .osVersion, .hardware, .releaseYear, .uuid
            ]),
            MenuSection(title: "Application", items: [
                .appIdPrefix, .displayName, .bundleId, .processId,
                .version, .buildNumber, .buildDate, .releaseType
            ])
        ]

        if !developerOptions.isEmpty {
            sections.append(
                MenuSection(
                    title: "Development Tools",
                    items: developerOptions.map { .developerOption(name: $0.name) }
                )
            )
        }

        sections.append(contentsOf: [
            MenuSection(title: "Networking", items: [
                .ipAddress, .networkLogs, .serverConfiguration, .environmentVariables
            ]),
            MenuSection(title: "Data", items: [
                .featureFlags, .userDefaults, .cookies, .fileBrowser, .databaseBrowser
            ]),
            MenuSection(title: "Security", items: [
                .keychainBrowser
            ]),
            MenuSection(title: "System Tools", items: [
                .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs
            ]),
            MenuSection(title: "Notifications", items: [
                .notificationLogger, .notificationTester, .apnsToken, .fcmToken
            ]),
            MenuSection(title: "UI/UX", items: [
                .fonts, .interfaceComponents, .gridOverlay, .fpsCounter,
                .touchVisualiser, .appearance,
                .slowAnimations, .showViewFrames, .showViewSizes
            ])
        ])

        return sections
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuViewModelTests
```

Expected: `** TEST SUCCEEDED **`, 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuSection.swift Tests/ScytherTests/Features/MenuViewModelTests.swift
git commit -m "Describe the main menu layout as data"
```

---

## Task 6: Pin state in `MenuViewModel`

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuViewModel.swift`
- Modify: `Tests/ScytherTests/Features/MenuViewModelTests.swift`

**Interfaces:**
- Consumes: `MenuItem`, `MenuSection`, `UserDefaults.scyther`.
- Produces:
  - `MenuViewModel.init(defaults: UserDefaults = .scyther)`
  - `MenuViewModel.pinnedItemsKey` → `String` = `"Scyther.Menu.PinnedItems"` (static, internal)
  - `MenuViewModel.pinnedItemIDs` → `@Published private(set) var [String]`
  - `MenuViewModel.sections` → `[MenuSection]`
  - `MenuViewModel.pinnedItems` → `[MenuItem]`
  - `MenuViewModel.isPinned(_ item: MenuItem) -> Bool`
  - `MenuViewModel.togglePin(for item: MenuItem)`

- [ ] **Step 1: Add the failing pin tests**

Append to `Tests/ScytherTests/Features/MenuViewModelTests.swift`, inside the `MenuViewModelTests` class, after the section tests:

```swift
    // MARK: - Pinning

    private var suiteName: String { "com.scyther.tests.menu" }

    private func makeDefaults() -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    private func wipeDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testNothingIsPinnedByDefault() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        XCTAssertTrue(viewModel.pinnedItemIDs.isEmpty)
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
    }

    func testPinningAppendsTheItem() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .featureFlags)

        XCTAssertTrue(viewModel.isPinned(.featureFlags))
        XCTAssertEqual(viewModel.pinnedItems, [.featureFlags])
    }

    func testUnpinningRemovesTheItem() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .featureFlags)

        XCTAssertFalse(viewModel.isPinned(.featureFlags))
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
    }

    func testPinnedItemsAreOrderedOldestFirst() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .fonts)

        XCTAssertEqual(viewModel.pinnedItems, [.crashLogs, .featureFlags, .fonts])
    }

    func testUnpinningDoesNotDisturbTheOrderOfOtherItems() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .fonts)
        viewModel.togglePin(for: .featureFlags)

        XCTAssertEqual(viewModel.pinnedItems, [.crashLogs, .fonts])
    }

    func testRepinningMovesTheItemToTheEnd() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .fonts)
        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .crashLogs)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts, .crashLogs])
    }

    func testPinStateSurvivesANewViewModel() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let first = MenuViewModel(defaults: defaults)
        first.togglePin(for: .keychainBrowser)
        first.togglePin(for: .cookies)

        let second = MenuViewModel(defaults: defaults)
        XCTAssertEqual(second.pinnedItems, [.keychainBrowser, .cookies])
    }

    func testPinsAreWrittenToTheInjectedStoreOnly() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let viewModel = MenuViewModel(defaults: defaults)
        viewModel.togglePin(for: .fonts)

        XCTAssertEqual(defaults.stringArray(forKey: MenuViewModel.pinnedItemsKey), ["fonts"])
    }

    func testStoredIdentifiersThatNoLongerResolveAreDropped() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()
        defaults.set(["fonts", "removedInV2", "cookies"], forKey: MenuViewModel.pinnedItemsKey)

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts, .cookies])
    }

    func testPinnedDeveloperOptionThatNoLongerExistsIsDropped() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        let defaults = makeDefaults()
        defaults.set(["developerOption.Gone", "fonts"], forKey: MenuViewModel.pinnedItemsKey)
        Scyther.developerOptions = []

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts])
    }

    func testPinnedDeveloperOptionThatStillExistsIsKept() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        let defaults = makeDefaults()
        defaults.set(["developerOption.Panel"], forKey: MenuViewModel.pinnedItemsKey)
        Scyther.developerOptions = [DeveloperOption(name: "Panel", value: "x")]

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.developerOption(name: "Panel")])
    }

    func testIsPinnedAgreesWithPinnedItemIdentifiers() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .gridOverlay)

        XCTAssertTrue(viewModel.isPinned(.gridOverlay))
        XCTAssertFalse(viewModel.isPinned(.fpsCounter))
        XCTAssertEqual(viewModel.pinnedItemIDs, [MenuItem.gridOverlay.id])
    }
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuViewModelTests
```

Expected: **compile failure**, `argument passed to call that takes no arguments` on `MenuViewModel(defaults:)`.

- [ ] **Step 3: Implement pin state**

In `Sources/Scyther/Features/Menu/MenuViewModel.swift`, add a `// MARK: - Menu Structure` block above `// MARK: - Network Properties`, and an initialiser. The existing `ViewModel` base class has a no-argument `init()` that calls `setup()`, so the new initialiser must assign stored properties before calling `super.init()`:

```swift
    // MARK: - Menu Structure

    /// The key backing ``pinnedItemIDs`` in Scyther's preferences store.
    static let pinnedItemsKey = "Scyther.Menu.PinnedItems"

    /// The store pinned item identifiers are read from and written to.
    private let defaults: UserDefaults

    /// The identifiers of pinned rows, in the order they were pinned.
    ///
    /// An array rather than a `Set` so that oldest-first pin order survives a relaunch.
    @Published private(set) var pinnedItemIDs: [String]

    /// The full menu layout, including any host-supplied developer options.
    var sections: [MenuSection] {
        MenuSection.allSections(developerOptions: Scyther.developerOptions)
    }

    /// The pinned rows, oldest pin first.
    ///
    /// Stored identifiers that no longer resolve to a row currently present in ``sections``
    /// are dropped. This covers both a feature removed in a later version of Scyther and a
    /// developer option the host app no longer registers.
    var pinnedItems: [MenuItem] {
        let available = Set(sections.flatMap(\.items))
        return pinnedItemIDs
            .compactMap(MenuItem.init(id:))
            .filter { available.contains($0) }
    }

    /// Creates a menu view model.
    ///
    /// - Parameter defaults: The store backing pin state. Defaults to Scyther's private
    ///   preferences suite; tests inject a throwaway suite.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
        self.pinnedItemIDs = defaults.stringArray(forKey: Self.pinnedItemsKey) ?? []
        super.init()
    }

    /// Whether the given row is pinned.
    ///
    /// - Parameter item: The row to check.
    /// - Returns: `true` when the row appears in the "Pinned" section.
    func isPinned(_ item: MenuItem) -> Bool {
        pinnedItemIDs.contains(item.id)
    }

    /// Pins or unpins a row, persisting the change immediately.
    ///
    /// Pinning appends the row to the end of the pinned list, so the "Pinned" section reads
    /// oldest pin first. Unpinning leaves the order of the remaining rows untouched.
    ///
    /// - Parameter item: The row to pin or unpin.
    func togglePin(for item: MenuItem) {
        if let index = pinnedItemIDs.firstIndex(of: item.id) {
            pinnedItemIDs.remove(at: index)
        } else {
            pinnedItemIDs.append(item.id)
        }
        defaults.set(pinnedItemIDs, forKey: Self.pinnedItemsKey)
    }
```

Extend the type's DocC comment with the new capability and topics:

```swift
/// - **Menu Structure**: Supplies the ordered section layout and the set of pinned rows
/// - **Pinning**: Persists pinned rows to Scyther's preferences suite, oldest pin first
```

```swift
/// ### Menu Structure
///
/// - ``sections``
/// - ``pinnedItems``
/// - ``pinnedItemIDs``
/// - ``isPinned(_:)``
/// - ``togglePin(for:)``
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuViewModelTests
```

Expected: `** TEST SUCCEEDED **`, 18 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuViewModel.swift Tests/ScytherTests/Features/MenuViewModelTests.swift
git commit -m "Track and persist pinned main menu items"
```

---

## Task 7: Render the menu from data, with a Pinned section

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `MenuItem`, `MenuSection`, `MenuViewModel.sections`, `.pinnedItems`, `.isPinned(_:)`, `.togglePin(for:)`.
- Produces: no new API.

- [ ] **Step 1: Replace the `body` with a data-driven layout**

In `Sources/Scyther/Features/Menu/MenuView.swift`, replace the entire `public var body: some View { ... }` — all eight hardcoded sections — with:

```swift
    public var body: some View {
        List {
            if let deviceSection = viewModel.sections.first {
                Section {
                    header
                    ForEach(deviceSection.items) { item in
                        pinnableRow(for: item)
                    }
                } header: {
                    Text(deviceSection.title)
                }
            }

            if !viewModel.pinnedItems.isEmpty {
                Section {
                    ForEach(viewModel.pinnedItems, id: \.pinnedRowID) { item in
                        pinnableRow(for: item)
                    }
                } header: {
                    Text("Pinned")
                }
            }

            ForEach(Array(viewModel.sections.dropFirst())) { section in
                Section {
                    ForEach(section.items) { item in
                        pinnableRow(for: item)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Scyther.hideMenu()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .navigationTitle("Scyther")
        .interactiveDismissDisabled()
    }
```

- [ ] **Step 2: Add the row builders**

Add these two methods immediately after `body`, before the existing `row(withLabel:...)` helper:

```swift
    /// Wraps a row in its pin/unpin swipe action.
    ///
    /// The action's label is derived from the row's current pin state rather than from which
    /// section it is being rendered in, because pinned rows remain in their home section — a
    /// pinned row therefore reads "Unpin" in both places.
    @ViewBuilder
    private func pinnableRow(for item: MenuItem) -> some View {
        rowContent(for: item)
            .swipeActions(edge: .trailing) {
                Button {
                    viewModel.togglePin(for: item)
                } label: {
                    Label(
                        viewModel.isPinned(item) ? "Unpin" : "Pin",
                        systemImage: viewModel.isPinned(item) ? "pin.slash" : "pin"
                    )
                }
                .tint(.blue)
            }
    }

    /// Builds a row that pushes a destination view.
    ///
    /// The label is derived entirely from the item, so every navigation row in the menu is
    /// laid out identically and only the destination varies.
    ///
    /// - Parameters:
    ///   - item: The row to render.
    ///   - destination: The view to push when the row is tapped. Built lazily.
    private func navigationRow<Destination: View>(
        for item: MenuItem,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            row(withLabel: item.title, icon: item.icon)
        }
    }

    /// The single definition of every menu row.
    ///
    /// ``MenuItem`` supplies each row's title and icon; this method supplies everything
    /// dynamic — a value row's description, a navigation row's destination, a toggle row's
    /// binding. Because there is one definition, the "Pinned" section and a row's home
    /// section always render identically.
    @ViewBuilder
    private func rowContent(for item: MenuItem) -> some View {
        switch item {
        // MARK: Device
        case .osVersion:
            row(withLabel: item.title, description: UIDevice.current.systemVersion)
        case .hardware:
            row(withLabel: item.title, description: UIDevice.current.modelName)
        case .releaseYear:
            row(withLabel: item.title, description: UIDevice.current.generation.withoutDecimals)
        case .uuid:
            row(withLabel: item.title, description: UIDevice.current.identifierForVendor?.uuidString)

        // MARK: Application
        case .appIdPrefix:
            row(withLabel: item.title, description: Bundle.main.seedId)
        case .displayName:
            row(withLabel: item.title, description: String(UIApplication.shared.appName))
        case .bundleId:
            row(withLabel: item.title, description: Bundle.main.bundleIdentifier)
        case .processId:
            row(withLabel: item.title, description: String(getpid()))
        case .version:
            row(withLabel: item.title, description: Bundle.main.versionNumber)
        case .buildNumber:
            row(withLabel: item.title, description: Bundle.main.buildNumber)
        case .buildDate:
            row(withLabel: item.title, description: Bundle.main.buildDate.formatted())
        case .releaseType:
            row(withLabel: item.title, description: AppEnvironment.configuration().rawValue)

        // MARK: Development Tools
        case .developerOption(let name):
            if let option = Scyther.developerOptions.first(where: { $0.name == name }) {
                developerOptionRow(option)
            }

        // MARK: Networking
        case .ipAddress:
            row(
                withLabel: item.title,
                description: viewModel.ipAddress,
                icon: item.icon,
                andLoadingState: viewModel.isLoadingIPAddress
            )
        case .networkLogs:
            navigationRow(for: item) { NetworkLogsView() }
        case .serverConfiguration:
            navigationRow(for: item) { ServerConfigurationView() }
        case .environmentVariables:
            navigationRow(for: item) { EnvironmentVariablesView() }

        // MARK: Data
        case .featureFlags:
            navigationRow(for: item) { FeatureFlagsView() }
        case .userDefaults:
            navigationRow(for: item) { UserDefaultsView() }
        case .cookies:
            navigationRow(for: item) { CookieBrowserView() }
        case .fileBrowser:
            navigationRow(for: item) { FileBrowserView() }
        case .databaseBrowser:
            navigationRow(for: item) { DatabaseBrowserView() }

        // MARK: Security
        case .keychainBrowser:
            navigationRow(for: item) { KeychainBrowserView() }

        // MARK: System Tools
        case .locationSpoofer:
            navigationRow(for: item) { LocationSpooferView() }
        case .consoleLogs:
            navigationRow(for: item) { ConsoleLoggerView() }
        case .deepLinkTester:
            navigationRow(for: item) { DeepLinkTesterView() }
        case .crashLogs:
            navigationRow(for: item) { CrashLogsView() }

        // MARK: Notifications
        case .notificationLogger:
            navigationRow(for: item) { NotificationLoggerView() }
        case .notificationTester:
            navigationRow(for: item) { NotificationTesterView() }
        case .apnsToken:
            row(withLabel: item.title, icon: item.icon)
        case .fcmToken:
            row(withLabel: item.title, icon: item.icon)

        // MARK: UI/UX
        case .fonts:
            navigationRow(for: item) { FontsView() }
        case .interfaceComponents:
            navigationRow(for: item) { InterfacePreviewsView() }
        case .gridOverlay:
            navigationRow(for: item) { GridOverlaySettingsView() }
        case .fpsCounter:
            navigationRow(for: item) { FPSCounterSettingsView() }
        case .touchVisualiser:
            navigationRow(for: item) { TouchVisualiserView() }
        case .appearance:
            navigationRow(for: item) { AppearanceOverridesView() }
        case .slowAnimations:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.slowAnimationsEnabled)
        case .showViewFrames:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.showViewFrames)
        case .showViewSizes:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.showViewSizes)
        }
    }
```

- [ ] **Step 2b: Widen `toggleRow` to accept an optional icon**

`MenuItem.icon` is `String?`, but the existing `toggleRow` takes a non-optional `String`. Replace it:

```swift
    func toggleRow(_ label: String, icon: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            if let icon {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Text(label)
            }
        }
    }
```

- [ ] **Step 3: Update the view's DocC comment**

The existing comment lists the sections. Add the pinning behaviour:

```swift
/// Any row can be pinned via a trailing swipe action. Pinned rows appear in a "Pinned"
/// section rendered directly beneath **Device**, and also remain in their home section, so
/// the menu's structure never changes shape as rows are pinned. Pins are ordered oldest
/// first and persist across launches in ``UserDefaults/scyther``.
```

- [ ] **Step 4: Build and run the full test suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Verify the menu visually in the example app**

The pinning behaviour is not covered by unit tests, so check it by hand:

```bash
xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Then run `Example/ScytherExample`, open the menu, and confirm each of:
1. Sections appear in the order Device, Application, (Development Tools), Networking, Data, Security, System Tools, Notifications, UI/UX — matching the menu before this change.
2. Swiping left on any row reveals a blue "Pin" action.
3. Pinning a row makes a "Pinned" section appear directly beneath Device, and the row **also stays** in its original section.
4. Both copies of the pinned row show "Unpin" when swiped.
5. Pinning a second and third row appends them below the first.
6. Unpinning from either copy removes the row from Pinned and leaves the others in order.
7. Pinning a toggle row (Slow Animations) puts a working switch in the Pinned section.
8. Force-quitting and relaunching preserves the pins in the same order.

- [ ] **Step 6: Document pinning in the README**

In `README.md`, under the section that documents the menu, add:

```markdown
### Pinning menu items

Any row in the main menu can be pinned. Swipe left on a row and tap **Pin**; a **Pinned**
section appears directly beneath **Device** containing your shortcuts.

Pinned rows stay in their original section as well, so the menu never changes shape — the
Pinned section is purely an additional shortcut. Rows appear in the order you pinned them,
oldest first. Swipe and tap **Unpin** on either copy to remove one.

Everything is pinnable, including information rows such as **Bundle ID**, inline toggles
such as **Slow Animations**, and any custom options you register via
`Scyther.developerOptions`.

Pins persist across launches in Scyther's private preferences suite, so they survive your
app clearing its own `UserDefaults`. See [Preferences Storage](#preferences-storage).
```

Add a matching Table of Contents entry.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuView.swift README.md
git commit -m "Make every main menu row pinnable"
```

---

## Task 8: Feature Flags — gate on overrides, keep pinned rows in place

**Files:**
- Modify: `Sources/Scyther/Features/FeatureFlags/FeatureFlagsViewModel.swift`
- Modify: `Sources/Scyther/Features/FeatureFlags/FeatureFlagsView.swift`
- Modify: `Tests/ScytherTests/Features/FeatureFlagsTests.swift`

**Interfaces:**
- Consumes: `UserDefaults.scyther`.
- Produces:
  - `FeatureFlagsViewModel.init(defaults: UserDefaults = .scyther)`
  - `FeatureToggleItem.pinnedRowID` → `String`
  - Removes `FeatureFlagsViewModel.unpinnedToggles` — nothing else references it.

Pin **ordering and storage are unchanged**: pins stay a `Set<String>` and the Pinned section
stays alphabetical, inherited from `toggles` being sorted by name. This is deliberately
different from the menu's oldest-first ordering.

- [ ] **Step 1: Write the failing tests**

Append to the `FeatureFlagsTests` class in `Tests/ScytherTests/Features/FeatureFlagsTests.swift`:

```swift
    // MARK: - Pinned toggles stay in the full list

    /// Flags register into the shared `Scyther.featureFlags` singleton and there is no
    /// public API to unregister them, so these tests use distinctive names and assert by
    /// containment rather than whole-array equality. Another test registering its own flags
    /// must not be able to break them.
    @MainActor
    private func makeSuite(named suiteName: String) -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return UserDefaults(suiteName: suiteName)!
    }

    @MainActor
    func testPinnedTogglesRemainInTheFullToggleList() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags")
        Scyther.featureFlags.register("ScytherTestPinned", remoteValue: true)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()
        viewModel.togglePin(for: "ScytherTestPinned")

        XCTAssertTrue(
            viewModel.pinnedToggles.contains { $0.name == "ScytherTestPinned" },
            "Pinned toggle is missing from the Pinned section"
        )
        XCTAssertTrue(
            viewModel.toggles.contains { $0.name == "ScytherTestPinned" && $0.isPinned },
            "Pinned toggle must remain in the full list, flagged as pinned"
        )
    }

    @MainActor
    func testPinnedTogglesAreOrderedAlphabeticallyNotByPinOrder() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags.order")
        Scyther.featureFlags.register("ScytherTestOrderZulu", remoteValue: true)
        Scyther.featureFlags.register("ScytherTestOrderAlpha", remoteValue: true)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()

        // Pin Zulu first. Alphabetical ordering must still put Alpha ahead of it.
        viewModel.togglePin(for: "ScytherTestOrderZulu")
        viewModel.togglePin(for: "ScytherTestOrderAlpha")

        let names = viewModel.pinnedToggles.map(\.name).filter { $0.hasPrefix("ScytherTestOrder") }
        XCTAssertEqual(names, ["ScytherTestOrderAlpha", "ScytherTestOrderZulu"])
    }

    @MainActor
    func testUnpinningLeavesTheToggleInTheFullList() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags.unpin")
        Scyther.featureFlags.register("ScytherTestUnpin", remoteValue: false)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()
        viewModel.togglePin(for: "ScytherTestUnpin")
        viewModel.togglePin(for: "ScytherTestUnpin")

        XCTAssertFalse(viewModel.pinnedToggles.contains { $0.name == "ScytherTestUnpin" })
        XCTAssertTrue(viewModel.toggles.contains { $0.name == "ScytherTestUnpin" })
    }

    @MainActor
    func testOverridesEnabledPropagatesToTheFeatureFlagsSubsystem() {
        let viewModel = FeatureFlagsViewModel()

        viewModel.overridesEnabled = true
        XCTAssertTrue(Scyther.featureFlags.localOverridesEnabled)

        viewModel.overridesEnabled = false
        XCTAssertFalse(Scyther.featureFlags.localOverridesEnabled)
    }
```

Note `overridesEnabled` writes through to the shared `Scyther.featureFlags` singleton and
therefore to the real suite, not the injected one — injection covers pin state only. The
existing `cleanupUserDefaults()` in `tearDown` already removes `FeatureFlags.overridesEnabledKey`,
so this leaves no residue.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/FeatureFlagsTests
```

Expected: **compile failure**, `argument passed to call that takes no arguments` on `FeatureFlagsViewModel(defaults:)`.

- [ ] **Step 3: Update the view model**

In `Sources/Scyther/Features/FeatureFlags/FeatureFlagsViewModel.swift`:

Add `pinnedRowID` to `FeatureToggleItem`:

```swift
    /// A namespaced identifier for rendering this toggle inside the "Pinned" section.
    ///
    /// Pinned toggles remain in the main list, so the same toggle appears twice in one
    /// `List`. Namespacing the pinned copy keeps SwiftUI's row identity unambiguous.
    var pinnedRowID: String { "pinned.\(name)" }
```

Delete `unpinnedToggles` entirely — it is now unused:

```swift
    /// Toggles that are not pinned.
    var unpinnedToggles: [FeatureToggleItem] {
        toggles.filter { !$0.isPinned }
    }
```

Replace the hardcoded store with an injected one. Change the `pinnedToggleNames` accessors to use `defaults` and add the initialiser:

```swift
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

    private var pinnedToggleNames: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Self.pinnedTogglesKey) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Self.pinnedTogglesKey)
        }
    }
```

Update the type's DocC `## Topics` block to drop `unpinnedToggles` and the "Implementation Details" paragraph that names `UserDefaults`:

```swift
/// Pin state is persisted to ``UserDefaults/scyther`` using the key
/// `Scyther.FeatureFlags.PinnedToggles` and is automatically restored when the view model
/// loads. Pinned toggles remain in the full ``toggles`` list, so a pinned toggle is shown
/// both in the "Pinned" section and in the main list.
```

- [ ] **Step 4: Run the view model tests and verify they pass**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/FeatureFlagsTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Gate the view on `overridesEnabled` and keep pinned rows in the list**

In `Sources/Scyther/Features/FeatureFlags/FeatureFlagsView.swift`, replace `filteredUnpinnedToggles` with a filter over the whole list:

```swift
    private var filteredToggles: [FeatureToggleItem] {
        guard !debouncedSearchText.isEmpty else { return viewModel.toggles }
        let search = debouncedSearchText.lowercased()
        return viewModel.toggles.filter { $0.name.lowercased().contains(search) }
    }
```

Replace `body` with a gated version. `.searchable` cannot be applied conditionally inline, so the list is extracted and the modifier applied on one branch only.

**The `Group` wrapper is load-bearing — do not remove it.** Flipping `overridesEnabled` swaps which branch is rendered, which destroys the branch's view identity along with any `.onChange`, `.onAppear` or `@State` attached inside it. Attaching the lifecycle modifiers to the `Group` gives them a stable identity that survives the swap, so the "clear the search text" handler actually fires. Attached to `list` instead, it would silently never run on the very transition it exists to handle.

```swift
    var body: some View {
        Group {
            if viewModel.overridesEnabled {
                list.searchable(text: $searchText, prompt: "Search toggles")
            } else {
                list
            }
        }
        .navigationTitle("Feature Flags")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onChange(of: viewModel.overridesEnabled) { enabled in
            guard !enabled else { return }
            searchText = ""
            debouncedSearchText = ""
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

    private var list: some View {
        List {
            Section {
                Toggle("Enable overrides", isOn: $viewModel.overridesEnabled)

                if viewModel.overridesEnabled {
                    Button("Reset all to Remote") {
                        viewModel.resetAllToRemote()
                    }
                }
            } header: {
                Text("Global Settings")
            } footer: {
                if !viewModel.overridesEnabled {
                    Text("Enable overrides to view and modify feature flags.")
                }
            }

            if viewModel.overridesEnabled {
                if !filteredPinnedToggles.isEmpty {
                    Section("Pinned") {
                        ForEach(filteredPinnedToggles, id: \.pinnedRowID) { toggle in
                            toggleRow(for: toggle)
                                .swipeActions(edge: .trailing) {
                                    pinButton(for: toggle)
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
                    } else if filteredToggles.isEmpty {
                        Text("No matching toggles")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredToggles) { toggle in
                            toggleRow(for: toggle)
                                .swipeActions(edge: .trailing) {
                                    pinButton(for: toggle)
                                }
                        }
                    }
                }
            }
        }
    }

    /// The pin/unpin swipe action for a toggle.
    ///
    /// The label reflects the toggle's pin state rather than which section it is rendered
    /// in, because pinned toggles remain in the main list.
    @ViewBuilder
    private func pinButton(for toggle: FeatureToggleItem) -> some View {
        Button {
            viewModel.togglePin(for: toggle.name)
        } label: {
            Label(
                toggle.isPinned ? "Unpin" : "Pin",
                systemImage: toggle.isPinned ? "pin.slash" : "pin"
            )
        }
        .tint(.blue)
    }
```

Note the "All toggles are pinned" branch is gone — it is now unreachable, because pinned
toggles remain in `filteredToggles`.

Update the view's DocC comment, which currently claims pinning moves toggles to the top:

```swift
/// - Pin frequently used toggles to an additional section at the top; pinned toggles remain
///   in the main list as well
/// - Search toggles by name
/// - Reset all toggles back to their remote values
///
/// While **Enable overrides** is off, the toggle list, the reset button and the search field
/// are hidden — local overrides have no effect in that state, so presenting an interactive
/// list would be misleading.
```

- [ ] **Step 6: Build and run the full test suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Verify the Feature Flags screen visually**

Run `Example/ScytherExample`, navigate to **Data → Feature Flags**, and confirm:
1. With overrides off: only "Enable overrides" is visible, with the explanatory footer beneath it. No reset button, no sections, no search field.
2. Turning overrides on reveals the reset button, the Toggles section and the search field.
3. Pinning a toggle adds a Pinned section **and** leaves the toggle in the Toggles list.
4. Both copies show "Unpin" when swiped, and unpinning from either removes the Pinned section entry.
5. Typing a search term, then turning overrides off and back on, leaves the search field empty and the full list visible.

- [ ] **Step 8: Update the README**

In the `### Feature Flags` section of `README.md`, add a note after the overrides documentation:

```markdown
The flag list is only shown while **Enable overrides** is on. With overrides off, local
values have no effect, so the list, the reset button and the search field are hidden.

Toggles can be pinned via a left swipe. Pinned toggles appear in a **Pinned** section at the
top of the list and also remain in the main list. Pins persist across launches in Scyther's
private preferences suite.
```

- [ ] **Step 9: Commit**

```bash
git add Sources/Scyther/Features/FeatureFlags/ Tests/ScytherTests/Features/FeatureFlagsTests.swift README.md
git commit -m "Gate the feature flag list behind the overrides toggle"
```

---

## Task 9: Final verification

**Files:** none modified unless a check fails.

- [ ] **Step 1: Confirm no Scyther *setting* is written to the standard store**

```bash
grep -rln "UserDefaults.standard" --include="*.swift" Sources/
```

Expected: exactly these five files, all of which reference the standard store legitimately:

| File | Why it is correct |
| --- | --- |
| `Core/ScytherDefaults.swift` | Names `.standard` as the migration *source*, as the fallback when the suite cannot be created, and in its DocC examples |
| `Features/UserDefaults/UserDefaultsViewModel.swift` | The browser reads the host app's defaults for the `.app` store |
| `Features/UserDefaults/UserDefaultsView.swift` | Store-selection copy naming the app's defaults |
| `Shared/Extensions/UserDefaults+Extensions.swift` | Display helper, called against whichever store is shown |
| `Features/CookieBrowser/CookieDetailsViewModel.swift` | `synchronize()` flushing `HTTPCookieStorage` |

The gate that actually matters: **none of the 12 files migrated in Task 2 may appear in this list.**

- [ ] **Step 2: Confirm no confirmation dialogs remain**

```bash
grep -rn "confirmationDialog" --include="*.swift" Sources/
```

Expected: `Features/UserDefaults/UserDefaultsView.swift` must NOT appear — Task 3 converted it to `.alert`.

Five pre-existing violations of the project's alerts-only rule remain in files this plan does not touch, and are deliberately left alone as out of scope:

| File | Line |
| --- | --- |
| `Features/CookieBrowser/CookieBrowserView.swift` | 63 |
| `Features/KeychainBrowser/KeychainBrowserView.swift` | 100, 216 |
| `Features/FileBrowser/FileBrowserView.swift` | 70 |
| `Features/FileBrowser/FileDetailView.swift` | 112 |

Report these in the final summary as pre-existing debt rather than fixing them here — converting five unrelated views would balloon this branch's diff and its review surface.

- [ ] **Step 3: Run the full test suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`, with all of `ScytherDefaultsTests`, `MenuItemTests`, `MenuViewModelTests`, `UserDefaultsViewModelTests` and `FeatureFlagsTests` passing.

- [ ] **Step 4: Build the documentation**

```bash
xcodebuild docbuild -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ./docbuild
```

Expected: `** BUILD SUCCEEDED **` with no DocC warnings about unresolved symbol links. A warning naming `unpinnedToggles` means a `## Topics` block still references the deleted property.

- [ ] **Step 5: Confirm the README is accurate**

Check that `README.md` contains a `## Preferences Storage` section, a `### Pinning menu items` section, the Feature Flags note, and that every new section has a Table of Contents entry.

- [ ] **Step 6: Commit anything outstanding**

```bash
git status --short
```

Expected: clean. If not, commit the remaining changes with a descriptive message.
