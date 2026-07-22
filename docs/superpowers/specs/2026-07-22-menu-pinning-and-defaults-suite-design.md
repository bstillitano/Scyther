# Pinnable Main Menu Items & Private Preferences Suite

**Date:** 2026-07-22
**Status:** Approved

## Overview

Two changes to Scyther:

1. **Private preferences suite** — all of Scyther's persisted settings move out of
   `UserDefaults.standard` into a dedicated suite, so host apps that wipe the standard
   domain on sign-out no longer destroy Scyther's state.
2. **Pinnable main menu items** — any row in `MenuView` can be pinned to a new "Pinned"
   section rendered second in the list, mirroring the existing Feature Flags pinning UX.

Part 1 lands first: menu pin state is persisted into the new suite.

---

## Part 1 — Private Preferences Suite

### Problem

Scyther persists roughly 82 values across 13 files into `UserDefaults.standard`. Apps
commonly clear the entire standard domain when a user signs out, using either:

- iterating `UserDefaults.standard.dictionaryRepresentation()` and removing each key, or
- `UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)`

Both operate on the **app domain only**. A named suite is a separate persistent domain and
is untouched by either, so moving Scyther's state into one fully solves the problem.

### Design

**New file: `Sources/Scyther/Core/ScytherDefaults.swift`**

```swift
public extension UserDefaults {
    /// Scyther's private preferences store, isolated from `UserDefaults.standard`.
    static let scyther: UserDefaults = ScytherDefaults.makeStore()
}

internal enum ScytherDefaults {
    static let suiteName = "com.scyther.settings"
    static let keyPrefix = "scyther"                              // matched case-insensitively
    static let migrationKey = "Scyther.Defaults.DidMigrateFromStandard"

    static func makeStore() -> UserDefaults
    static func migrate(from source: UserDefaults, to destination: UserDefaults)
}
```

`makeStore()` returns `UserDefaults(suiteName: suiteName)`, falling back to
`UserDefaults.standard` if initialisation returns `nil`. Before returning, it runs the
one-time migration.

On iOS a named suite is written to `<container>/Library/Preferences/com.scyther.settings.plist`
inside the app's own sandbox, so a fixed name carries no cross-app collision risk.

### Migration

`migrate(from:to:)` is a pure function over two stores so it can be driven by tests with
throwaway suites. It is invoked once, guarded by `migrationKey` stored in the destination:

1. Read `source.persistentDomain(forName: Bundle.main.bundleIdentifier)`. This is used in
   preference to `dictionaryRepresentation()`, which would also return inherited
   global-domain keys that do not belong to the app.
2. For each key whose lowercased form has the prefix `scyther`:
   - write it to the destination **only if the destination has no existing value for that
     key** — never clobber newer state;
   - remove it from the source.
3. Set `migrationKey` to `true` in the destination.

All of Scyther's existing keys are consistently prefixed (`Scyther_*`, `Scyther.*`,
`scyther.*`), which the existing `UserDefaultsViewModel.resetAllDefaults()` filter already
relies on, so prefix matching is a safe migration predicate.

### Call-site changes

`UserDefaults.standard` → `UserDefaults.scyther` across:

| File | Sites |
| --- | --- |
| `Features/LocationSpoofer/LocationSpoofer.swift` | 23 |
| `Features/AppearanceOverrides/AppearanceOverrides.swift` | 10 |
| `Features/GridOverlay/GridOverlay.swift` | 8 |
| `Core/InterfaceToolkit.swift` | 8 |
| `Features/TouchVisualiser/TouchVisualiserConfiguration.swift` | 6 |
| `Core/Scyther.swift` | 5 |
| `Features/FPSCounter/FPSCounter.swift` | 4 |
| `Features/FeatureFlags/FeatureToggle.swift` | 4 |
| `Features/DeepLinkTester/DeepLinkTester.swift` | 4 |
| `Features/CrashLogs/CrashLogger.swift` | 4 |
| `Features/FeatureFlags/FeatureFlagsViewModel.swift` | 2 |
| `Core/UIView+InterfaceToolkit.swift` | 2 |

Two sites deliberately stay on `.standard`:

- `Shared/Extensions/UserDefaults+Extensions.swift` — `stringStringDictionaryRepresentation`
  is a browser display helper invoked against whichever store is being shown.
- `Features/CookieBrowser/CookieDetailsViewModel.swift` — its `synchronize()` call flushes
  `HTTPCookieStorage`, unrelated to Scyther settings.

`UserDefaults.scyther` is a `static let` on an extension, so it is reachable from the
`nonisolated` accessors in `Scyther.swift`, `InterfaceToolkit.swift` and
`UIView+InterfaceToolkit.swift` without a main-actor hop, preserving the existing
concurrency design. If Foundation's `UserDefaults` does not carry a `Sendable` conformance
under this SDK, the property is declared `nonisolated(unsafe) static let` — `UserDefaults`
is documented as thread-safe.

### UserDefaults browser store picker

Once Scyther's settings leave the standard domain they become invisible in the browser, so
`UserDefaultsView` gains a store selector.

- New `DefaultsStore` enum with cases `.app` and `.scyther`, exposed as a `@Published`
  property on `UserDefaultsViewModel` and rendered as a segmented `Picker` above the list.
- `.app` loads via `UserDefaults.standard.dictionaryRepresentation()` (unchanged behaviour).
- `.scyther` loads via `persistentDomain(forName: ScytherDefaults.suiteName)` so only
  Scyther's own keys appear, without inherited global-domain noise.
- Reads, writes, boolean bindings and deletes all route to the selected store.
- `resetAllDefaults()` becomes store-aware:
  - `.app` — current behaviour retained, including the `!hasPrefix("scyther")` filter, which
    remains as a safety net for any un-migrated stragglers.
  - `.scyther` — offers "Reset all Scyther settings", clearing the suite, behind its own
    alert with distinct copy.

---

## Part 2 — Pinnable Main Menu Items

### Problem

`MenuView.swift` is approximately 40 literal `NavigationLink` / row declarations across 8
hardcoded sections. Rows have no identity, so they cannot be persisted as pins or rendered
outside their home section.

### Design decisions

| Decision | Choice |
| --- | --- |
| What is pinnable | Every row, including static info rows, inline toggles and custom developer options |
| Pinned row behaviour | Stays in its home section; the Pinned section is an additional shortcut |
| Gesture | Trailing swipe action, matching Feature Flags |
| Pinned section position | Second — after "Device", before "Application" |
| Pinned section ordering | Order pinned, oldest first |

### `MenuItem`

**New file: `Sources/Scyther/Features/Menu/MenuItem.swift`**

```swift
enum MenuItem: Hashable, Identifiable {
    case osVersion, hardware, releaseYear, uuid                      // Device
    case appIdPrefix, displayName, bundleId, processId,
         version, buildNumber, buildDate, releaseType                // Application
    case developerOption(name: String)                               // Development Tools
    case ipAddress, networkLogs, serverConfiguration,
         environmentVariables                                        // Networking
    case featureFlags, userDefaults, cookies, fileBrowser,
         databaseBrowser                                             // Data
    case keychainBrowser                                             // Security
    case locationSpoofer, consoleLogs, deepLinkTester, crashLogs     // System Tools
    case notificationLogger, notificationTester, apnsToken, fcmToken // Notifications
    case fonts, interfaceComponents, gridOverlay, fpsCounter,
         touchVisualiser, appearance, slowAnimations,
         showViewFrames, showViewSizes                               // UI/UX

    var id: String              // stable identifier, persisted
    init?(id: String)           // round-trips; returns nil for unknown identifiers
    var title: String
    var icon: String?
}
```

39 static items plus dynamic `developerOption(name:)`, whose id is `"developerOption.<name>"`.

The device header (app icon, device name, model) is **not** a `MenuItem` — it remains a
plain header view inside the Device section and is not pinnable.

`MenuItem` owns `title` and `icon` so they have a single definition and can be asserted in
tests. Everything genuinely dynamic — a value row's description, a navigation row's
destination, a toggle row's binding — is supplied by the view.

### `MenuSection`

**New file: `Sources/Scyther/Features/Menu/MenuSection.swift`**

```swift
struct MenuSection: Identifiable {
    var id: String { title }
    let title: String
    let items: [MenuItem]
}
```

The ordered section layout (Device, Application, Development Tools, Networking, Data,
Security, System Tools, Notifications, UI/UX) is built here. The Development Tools section
is populated from `Scyther.developerOptions` at build time and omitted when empty, matching
current behaviour.

### `MenuViewModel` additions

```swift
@Published private(set) var pinnedItemIDs: [String]   // array preserves pin order
var sections: [MenuSection]
var pinnedItems: [MenuItem]                           // ids → items, dropping unknown ids
func isPinned(_ item: MenuItem) -> Bool
func togglePin(for item: MenuItem)                    // append on pin, remove on unpin
init(defaults: UserDefaults = .scyther)               // injectable for tests
```

Pin state persists to key `Scyther.Menu.PinnedItems` in `UserDefaults.scyther` as a
`[String]`. An array rather than a `Set` is used so oldest-first pin order survives a
relaunch.

`pinnedItems` maps stored ids back through `MenuItem.init?(id:)` and silently drops any that
no longer resolve. This covers a removed feature after an upgrade and a renamed developer
option in the host app.

### `MenuView` changes

The body becomes data-driven. A single `@ViewBuilder func rowContent(for: MenuItem)` switch
holds one definition per row and is rendered from both the home section and the Pinned
section:

```
Section("Device")  { header; ForEach(sections[0].items) { rowContent(for:) } }
Section("Pinned")  { ForEach(pinnedItems) { rowContent(for:) } }   // only when non-empty
ForEach(sections.dropFirst()) { section in
    Section(section.title) { ForEach(section.items) { rowContent(for:) } }
}
```

Every row carries the same trailing swipe action. Its label is derived from
`isPinned(item)`, so a pinned row reads "Unpin" (`pin.slash`) in both the Pinned section and
its home section, and an unpinned row reads "Pin" (`pin`). Tint is `.blue`, matching
Feature Flags.

Because pinned items remain in their home section, the same `MenuItem` renders twice in one
`List`. The Pinned `ForEach` uses a namespaced row identifier (`"pinned.<id>"`) so SwiftUI's
row identity is unambiguous.

The existing `row(withLabel:description:icon:andLoadingState:)`, `toggleRow(_:icon:isOn:)`,
`developerOptionRow(_:)` and `developerOptionLabel(_:)` helpers are retained and called from
`rowContent(for:)`.

### Feature Flags alignment

#### Gating the list on `overridesEnabled`

While `overridesEnabled` is `false`, local overrides have no effect, so presenting an
interactive flag list is misleading. Everything except the "Enable overrides" toggle is
hidden:

- The "Pinned" and "Toggles" sections are omitted entirely.
- The "Reset all to Remote" button is hidden, leaving "Global Settings" with a single row.
- `.searchable` **is** applied unconditionally — the search field stays visible even while the
  list is hidden. `searchText` and `debouncedSearchText` are still cleared when overrides are
  switched off, so re-enabling never reveals a list silently filtered by a stale query.

  Rationale for keeping the search field always present: applying `.searchable` conditionally
  forces `body` to branch between two view shapes, and flipping the toggle then swaps which
  branch renders — destroying that branch's view identity along with any `.onChange`,
  `.onAppear` or `@State` attached inside it. The search-clearing handler would silently
  never fire on the exact transition it exists to handle, and no test would catch it. A
  single unconditional shape removes that failure mode entirely. A momentarily inert search
  field is a smaller cost than structurally fragile view identity.
- The "Global Settings" section gains a **footer** reading along the lines of
  "Enable overrides to view and modify feature flags." The footer is shown only while
  overrides are off; once enabled the flags are visible and self-explanatory, so it is
  omitted.

The placeholder rows inside the "Toggles" section ("No toggles configured", "No matching
toggles") are unaffected — they only ever render when overrides are on.

#### Pinned rows stay in place

Only one behavioural change, to match the menu's "stays in place" semantics:

- `FeatureFlagsViewModel.unpinnedToggles` is removed.
- `FeatureFlagsView`'s "Toggles" section renders all toggles (search-filtered), so a pinned
  flag appears in both "Pinned" and "Toggles".
- The now-unreachable "All toggles are pinned" empty state is deleted. The "No toggles
  configured" and "No matching toggles" states are retained.

Feature Flags pin **ordering and storage are unchanged**: pins remain a `Set<String>` and
the Pinned section remains alphabetical, inherited from `toggles` being sorted by name. The
menu's oldest-first ordering is intentionally different; the two lists have different
character and this was an explicit decision.

`FeatureFlagsViewModel` does gain `init(defaults: UserDefaults = .scyther)` so its pin
persistence can be tested without touching the real suite, and its pin key moves into the
new suite along with everything else.

---

## Testing

New test files:

- **`Tests/ScytherTests/Core/ScytherDefaultsTests.swift`**
  - migration copies `scyther`-prefixed keys from source to destination
  - migration removes the copied keys from the source
  - migration ignores keys without the prefix, in both directions
  - migration never overwrites an existing destination value
  - migration is idempotent — a second run is a no-op
  - prefix matching is case-insensitive (`Scyther_`, `scyther.`)

- **`Tests/ScytherTests/Features/MenuItemTests.swift`**
  - all ids are unique across every case
  - `init?(id:)` round-trips every case, including `developerOption` names containing dots
    and spaces
  - `init?(id:)` returns `nil` for an unrecognised id
  - every item has a non-empty title

- **`Tests/ScytherTests/Features/MenuViewModelTests.swift`**
  - every `MenuItem` case appears in exactly one section — guards against a case being added
    without being rendered
  - Development Tools section is omitted when `Scyther.developerOptions` is empty and
    populated when it is not
  - pinning appends; unpinning removes; order is oldest-first and stable across further pins
  - pin state round-trips through an injected `UserDefaults` store
  - stored ids that no longer resolve are dropped from `pinnedItems` without affecting the
    rest
  - `isPinned` agrees with `pinnedItemIDs`

Updated test files:

- **`FeatureFlagsViewModelTests`** — pinned toggles remain present in the full `toggles`
  array; pinned ordering stays alphabetical; toggling `overridesEnabled` propagates to
  `Scyther.featureFlags.localOverridesEnabled` in both directions, which is the value the
  view's gating reads.
- **`UserDefaultsViewModelTests`** (new if absent) — switching `DefaultsStore` loads from the
  correct domain; writes and deletes land in the selected store; `.scyther` enumeration
  excludes global-domain keys.

Both `MenuViewModel` and `FeatureFlagsViewModel` take an injectable `UserDefaults` so no test
mutates the real `com.scyther.settings` suite.

## Documentation

- DocC comments on `ScytherDefaults`, `UserDefaults.scyther`, `MenuItem`, `MenuSection`,
  `DefaultsStore` and every new view model member, matching the density of surrounding code.
- README: a "Pinning menu items" subsection under the menu documentation, and a new
  "Preferences Storage" section covering the suite name, the isolation guarantee against
  standard-domain wipes, and the automatic one-time migration.

## Out of Scope

- Reordering pinned items by drag.
- A public API for host apps to override the suite name or point Scyther at an app group.
- Pinning anything outside the main menu and Feature Flags.
- Changing Feature Flags' pin ordering or storage representation.
