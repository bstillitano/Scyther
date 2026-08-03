# Global Menu Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS-Settings-style global search on `MenuView` covering every main-menu row and curated static sub-page rows, each result showing a `Section → Page` breadcrumb.

**Architecture:** A pure-data `MenuSearchIndex` derives main-menu entries from `MenuSection.allSections` and appends a curated list of static sub-page rows. `MenuViewModel` exposes `searchText`/`searchResults`; `MenuView` gains `.searchable` and swaps its section list for result rows while a query is active. Sub-page results push their containing page via a `destination(for:)` helper extracted from the existing row rendering.

**Tech Stack:** Swift 6, SwiftUI, XCTest. iOS-only SPM library — build/test with `xcodebuild`, never `swift build`/`swift test`.

**Spec:** `docs/superpowers/specs/2026-08-03-menu-global-search-design.md`

## Global Constraints

- Package targets **iOS 16**; `ContentUnavailableView` must be gated `if #available(iOS 17.0, *)` with a fallback (existing pattern: `CrashLogsView.swift:92`).
- Build/test destination: the **booted simulator** if one exists (`xcrun simctl list devices booted`), else `platform=iOS Simulator,name=iPhone 17 Pro`. All commands below use the named destination — substitute the booted device if present.
- Test command shape: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- All new types get docc documentation matching the density of `MenuItem.swift`/`MenuSection.swift`.
- Test files wrap contents in `#if !os(macOS)` / `#endif` (existing convention).
- MVVM: view state lives in the view model; filtering logic lives in the index (testable without UI).

---

### Task 1: `MenuSearchEntry` model

**Files:**
- Create: `Sources/Scyther/Features/Menu/MenuSearchEntry.swift`
- Create: `Tests/ScytherTests/Features/MenuSearchIndexTests.swift`

**Interfaces:**
- Consumes: `MenuItem` (existing enum, `Hashable`, has `id: String`, `title: String`, `icon: String?`).
- Produces: `struct MenuSearchEntry: Identifiable, Hashable, Sendable` with `title: String`, `breadcrumb: [String]`, `icon: String?`, `target: MenuItem`, `isSubpageEntry: Bool`, computed `id: String` (`"\(target.id).\(title)"`) and `breadcrumbText: String` (components joined with `" → "`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/MenuSearchIndexTests.swift`:

```swift
//
//  MenuSearchIndexTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 3/8/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class MenuSearchIndexTests: XCTestCase {

    // MARK: - MenuSearchEntry

    func testEntryIdentifierCombinesTargetAndTitle() {
        let entry = MenuSearchEntry(
            title: "Grid Color",
            breadcrumb: ["UI/UX", "Grid Overlay"],
            icon: "rectangle.split.3x3",
            target: .gridOverlay,
            isSubpageEntry: true
        )
        XCTAssertEqual(entry.id, "gridOverlay.Grid Color")
    }

    func testBreadcrumbTextJoinsComponentsWithArrows() {
        let entry = MenuSearchEntry(
            title: "Grid Color",
            breadcrumb: ["UI/UX", "Grid Overlay"],
            icon: nil,
            target: .gridOverlay,
            isSubpageEntry: true
        )
        XCTAssertEqual(entry.breadcrumbText, "UI/UX → Grid Overlay")
    }
}
#endif
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuSearchIndexTests 2>&1 | tail -20`
Expected: BUILD FAILURE — `cannot find 'MenuSearchEntry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/Menu/MenuSearchEntry.swift`:

```swift
//
//  MenuSearchEntry.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

/// A single searchable row in the global menu search index.
///
/// Entries come in two flavours, distinguished by ``isSubpageEntry``:
/// - **Main-page entries** represent a row on the main menu itself. Their ``target``
///   is that row, and ``MenuView`` renders them through its normal row definition so
///   toggles stay live and value rows show their values.
/// - **Sub-page entries** represent a static row *inside* a settings page — for
///   example "Grid Color" inside Grid Overlay. Their ``target`` is the page that
///   contains the row, and tapping the result navigates to that page.
///
/// ## Topics
///
/// ### Identity
/// - ``id``
///
/// ### Presentation
/// - ``title``
/// - ``breadcrumb``
/// - ``breadcrumbText``
/// - ``icon``
///
/// ### Resolution
/// - ``target``
/// - ``isSubpageEntry``
struct MenuSearchEntry: Identifiable, Hashable, Sendable {
    /// The text shown as the result's title, and matched against the search query.
    let title: String

    /// The navigation path shown beneath the title, outermost first.
    ///
    /// Main-page entries carry a single component (their section's title, e.g.
    /// `["Networking"]`); sub-page entries carry two (`["UI/UX", "Grid Overlay"]`).
    let breadcrumb: [String]

    /// The SF Symbol shown alongside the result, or `nil` for icon-less rows.
    let icon: String?

    /// The menu row this result resolves to.
    ///
    /// Main-page entries target themselves; sub-page entries target the page
    /// containing the matched row.
    let target: MenuItem

    /// Whether this entry represents a row inside ``target`` rather than the
    /// main-page row itself.
    let isSubpageEntry: Bool

    /// Stable identity: the target's identifier plus the title, because sub-page
    /// entries share a ``target`` with each other and with the page's own entry.
    var id: String { "\(target.id).\(title)" }

    /// The breadcrumb rendered as a single line, components joined with "→".
    var breadcrumbText: String { breadcrumb.joined(separator: " → ") }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuSearchEntry.swift Tests/ScytherTests/Features/MenuSearchIndexTests.swift
git commit -m "Add MenuSearchEntry model for global menu search"
```

---

### Task 2: `MenuSearchIndex` — derived main-menu entries

**Files:**
- Create: `Sources/Scyther/Features/Menu/MenuSearchIndex.swift`
- Modify: `Tests/ScytherTests/Features/MenuSearchIndexTests.swift`

**Interfaces:**
- Consumes: `MenuSection.allSections(developerOptions:)`, `MenuSearchEntry` (Task 1), `DeveloperOption` (existing; `DeveloperOption(name: "X", value: "y")` constructs one in tests).
- Produces: `enum MenuSearchIndex` with `static func entries(developerOptions: [DeveloperOption]) -> [MenuSearchEntry]`. In this task it returns **main-page entries only**; Task 3 appends sub-page entries.

- [ ] **Step 1: Write the failing tests**

Append inside the test class in `MenuSearchIndexTests.swift`:

```swift
    // MARK: - Main-menu derivation

    private var mainPageEntries: [MenuSearchEntry] {
        MenuSearchIndex.entries(developerOptions: []).filter { !$0.isSubpageEntry }
    }

    func testEveryStaticItemHasExactlyOneMainPageEntry() {
        let targets = mainPageEntries.map(\.target)
        XCTAssertEqual(targets.count, MenuItem.allStaticCases.count)
        XCTAssertEqual(Set(targets), Set(MenuItem.allStaticCases))
    }

    func testMainPageEntriesCarryTheirSectionTitleAsBreadcrumb() {
        let sections = MenuSection.allSections(developerOptions: [])
        for entry in mainPageEntries {
            let home = sections.first { $0.items.contains(entry.target) }
            XCTAssertEqual(entry.breadcrumb, [home?.title ?? ""], "\(entry.title) has the wrong breadcrumb")
        }
    }

    func testMainPageEntriesUseTheItemTitleAndIcon() {
        for entry in mainPageEntries {
            XCTAssertEqual(entry.title, entry.target.title)
            XCTAssertEqual(entry.icon, entry.target.icon)
        }
    }

    func testEntryIdentifiersAreUnique() {
        let ids = MenuSearchIndex.entries(developerOptions: []).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Two search entries share an identifier")
    }

    func testDeveloperOptionsAreIndexedWhenSupplied() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let entries = MenuSearchIndex.entries(developerOptions: options)

        let entry = entries.first { $0.target == .developerOption(name: "Reset Onboarding") }
        XCTAssertEqual(entry?.title, "Reset Onboarding")
        XCTAssertEqual(entry?.breadcrumb, ["Development Tools"])
        XCTAssertEqual(entry?.isSubpageEntry, false)
    }

    func testDeveloperOptionsAreAbsentWhenNoneAreSupplied() {
        let entries = MenuSearchIndex.entries(developerOptions: [])
        XCTAssertFalse(entries.contains { $0.breadcrumb.first == "Development Tools" })
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuSearchIndexTests 2>&1 | tail -20`
Expected: BUILD FAILURE — `cannot find 'MenuSearchIndex' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/Menu/MenuSearchIndex.swift`:

```swift
//
//  MenuSearchIndex.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

/// The global search index for the Scyther main menu.
///
/// The index has two parts:
/// - **Main-menu entries** are derived from ``MenuSection/allSections(developerOptions:)``
///   — one entry per row, carrying its section title as the breadcrumb. Because they are
///   derived, they can never drift from the real menu layout.
/// - **Sub-page entries** are a hand-curated list of the static rows inside settings
///   pages (see `subpageTitles`). Dynamic content — network log entries, UserDefaults
///   keys, files, fonts, host-supplied server configurations — is deliberately not
///   indexed, matching how the iOS Settings app treats app content.
///
/// ## Topics
///
/// ### Building the index
/// - ``entries(developerOptions:)``
///
/// ### Searching
/// - ``entries(matching:developerOptions:)``
enum MenuSearchIndex {
    /// Every searchable entry: one per main-menu row, followed by the curated
    /// sub-page entries.
    ///
    /// - Parameter developerOptions: The host app's custom options, so the
    ///   "Development Tools" rows are searchable exactly when they are visible.
    /// - Returns: All entries, in menu order.
    static func entries(developerOptions: [DeveloperOption]) -> [MenuSearchEntry] {
        let sections = MenuSection.allSections(developerOptions: developerOptions)
        return sections.flatMap { section in
            section.items.map { item in
                MenuSearchEntry(
                    title: item.title,
                    breadcrumb: [section.title],
                    icon: item.icon,
                    target: item,
                    isSubpageEntry: false
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2.
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuSearchIndex.swift Tests/ScytherTests/Features/MenuSearchIndexTests.swift
git commit -m "Derive main-menu search entries from the section layout"
```

---

### Task 3: Curated sub-page entries

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuSearchIndex.swift`
- Modify: `Tests/ScytherTests/Features/MenuSearchIndexTests.swift`

**Interfaces:**
- Produces: `entries(developerOptions:)` now also returns sub-page entries (`isSubpageEntry == true`), appended after the main-page entries. Internal `subpageTitles: [(target: MenuItem, titles: [String])]`.

- [ ] **Step 1: Write the failing tests**

Append inside the test class:

```swift
    // MARK: - Sub-page entries

    private var subpageEntries: [MenuSearchEntry] {
        MenuSearchIndex.entries(developerOptions: []).filter(\.isSubpageEntry)
    }

    func testSubpageEntriesExist() {
        XCTAssertFalse(subpageEntries.isEmpty)
    }

    func testSubpageEntriesTargetRealMenuItems() {
        for entry in subpageEntries {
            XCTAssertTrue(
                MenuItem.allStaticCases.contains(entry.target),
                "\(entry.title) targets a menu item that does not exist"
            )
        }
    }

    func testSubpageBreadcrumbsAreSectionThenPage() {
        let sections = MenuSection.allSections(developerOptions: [])
        for entry in subpageEntries {
            let home = sections.first { $0.items.contains(entry.target) }
            XCTAssertEqual(
                entry.breadcrumb,
                [home?.title ?? "", entry.target.title],
                "\(entry.title) has the wrong breadcrumb"
            )
        }
    }

    func testSubpageEntriesInheritTheirTargetIcon() {
        for entry in subpageEntries {
            XCTAssertEqual(entry.icon, entry.target.icon, "\(entry.title) has the wrong icon")
        }
    }

    func testGridOverlaySubpageRowsAreIndexed() {
        let titles = subpageEntries.filter { $0.target == .gridOverlay }.map(\.title)
        XCTAssertEqual(titles, ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuSearchIndexTests 2>&1 | tail -20`
Expected: FAIL — `testSubpageEntriesExist` and `testGridOverlaySubpageRowsAreIndexed` fail (no sub-page entries yet). The other new tests vacuously pass; that's fine.

- [ ] **Step 3: Write the implementation**

In `MenuSearchIndex.swift`, add below `entries(developerOptions:)` (inside the enum), and append `+ subpageEntries(in: sections)` to the return:

```swift
    static func entries(developerOptions: [DeveloperOption]) -> [MenuSearchEntry] {
        let sections = MenuSection.allSections(developerOptions: developerOptions)
        let mainPageEntries = sections.flatMap { section in
            section.items.map { item in
                MenuSearchEntry(
                    title: item.title,
                    breadcrumb: [section.title],
                    icon: item.icon,
                    target: item,
                    isSubpageEntry: false
                )
            }
        }
        return mainPageEntries + subpageEntries(in: sections)
    }

    /// The static rows inside settings sub-pages, keyed by the page's menu item.
    ///
    /// Hand-curated: when a settings page gains or loses a static row, update its
    /// titles here. Titles should match the visible row labels closely enough that
    /// searching what the user can read finds the page.
    private static let subpageTitles: [(target: MenuItem, titles: [String])] = [
        (.gridOverlay, ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"]),
        (.fpsCounter, ["Enable FPS Counter", "FPS Counter Position"]),
        (.touchVisualiser, [
            "Show Screen Touches", "Log Screen Touches",
            "Show Touch Duration", "Show Touch Radius"
        ]),
        (.appearance, [
            "Color Scheme", "Dynamic Type", "Override Text Size",
            "Increase Contrast", "Reset to System Defaults"
        ]),
        (.locationSpoofer, [
            "Enable Location Spoofing", "Location Presets", "Custom Location"
        ]),
        (.notificationTester, [
            "Request Notification Permission", "Send Push Notification",
            "Badge Count", "Cancel Scheduled Notifications", "Clear Badge & Notifications"
        ]),
        (.deepLinkTester, ["Open URL", "Deep Link Presets", "Deep Link History"])
    ]

    /// Builds the sub-page entries, resolving each target's home section from the
    /// live layout so breadcrumbs can never drift from the real menu.
    private static func subpageEntries(in sections: [MenuSection]) -> [MenuSearchEntry] {
        subpageTitles.flatMap { target, titles -> [MenuSearchEntry] in
            guard let home = sections.first(where: { $0.items.contains(target) }) else {
                return []
            }
            return titles.map { title in
                MenuSearchEntry(
                    title: title,
                    breadcrumb: [home.title, target.title],
                    icon: target.icon,
                    target: target,
                    isSubpageEntry: true
                )
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2.
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuSearchIndex.swift Tests/ScytherTests/Features/MenuSearchIndexTests.swift
git commit -m "Index static sub-page rows for global menu search"
```

---

### Task 4: Query matching

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuSearchIndex.swift`
- Modify: `Tests/ScytherTests/Features/MenuSearchIndexTests.swift`

**Interfaces:**
- Produces: `static func entries(matching query: String, developerOptions: [DeveloperOption]) -> [MenuSearchEntry]` — case- and diacritic-insensitive `localizedStandardContains` over title and breadcrumb components; empty/whitespace query returns `[]`.

- [ ] **Step 1: Write the failing tests**

Append inside the test class:

```swift
    // MARK: - Matching

    private func results(for query: String) -> [MenuSearchEntry] {
        MenuSearchIndex.entries(matching: query, developerOptions: [])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(results(for: "").isEmpty)
    }

    func testWhitespaceQueryReturnsNothing() {
        XCTAssertTrue(results(for: "   \n").isEmpty)
    }

    func testTitleMatchIsCaseInsensitive() {
        XCTAssertTrue(results(for: "GRID COLOR").contains { $0.title == "Grid Color" })
    }

    func testTitleMatchIsDiacriticInsensitive() {
        XCTAssertTrue(results(for: "gríd cölor").contains { $0.title == "Grid Color" })
    }

    func testBreadcrumbComponentsMatch() {
        // "grid overlay" appears only in breadcrumbs of sub-page entries and in the
        // page's own title; all Grid Overlay sub-page rows must surface.
        let matches = results(for: "grid overlay").filter(\.isSubpageEntry)
        XCTAssertEqual(
            Set(matches.map(\.title)),
            ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"]
        )
    }

    func testQueryIsTrimmedBeforeMatching() {
        XCTAssertTrue(results(for: "  feature flags  ").contains { $0.target == .featureFlags })
    }

    func testDeveloperOptionsAreSearchable() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let matches = MenuSearchIndex.entries(matching: "onboarding", developerOptions: options)
        XCTAssertTrue(matches.contains { $0.target == .developerOption(name: "Reset Onboarding") })
    }

    func testUnmatchedQueryReturnsNothing() {
        XCTAssertTrue(results(for: "zzzzzz-no-such-row").isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuSearchIndexTests 2>&1 | tail -20`
Expected: BUILD FAILURE — no `entries(matching:developerOptions:)`.

- [ ] **Step 3: Write the implementation**

Add to `MenuSearchIndex`:

```swift
    /// The entries matching a search query.
    ///
    /// Matching uses `localizedStandardContains` — case-insensitive,
    /// diacritic-insensitive, locale-aware — against the entry's title and each
    /// breadcrumb component, so searching "grid" surfaces every row under Grid
    /// Overlay as well as the page itself.
    ///
    /// - Parameters:
    ///   - query: The user's search text. Leading and trailing whitespace is
    ///     ignored; an effectively empty query matches nothing.
    ///   - developerOptions: The host app's custom options — see ``entries(developerOptions:)``.
    /// - Returns: Matching entries, in menu order.
    static func entries(
        matching query: String,
        developerOptions: [DeveloperOption]
    ) -> [MenuSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return entries(developerOptions: developerOptions).filter { entry in
            entry.title.localizedStandardContains(trimmed)
                || entry.breadcrumb.contains { $0.localizedStandardContains(trimmed) }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2.
Expected: PASS (21 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuSearchIndex.swift Tests/ScytherTests/Features/MenuSearchIndexTests.swift
git commit -m "Add query matching to the menu search index"
```

---

### Task 5: `MenuViewModel` search state

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuViewModel.swift`
- Modify: `Tests/ScytherTests/Features/MenuViewModelTests.swift`

**Interfaces:**
- Consumes: `MenuSearchIndex.entries(matching:developerOptions:)` (Task 4); the view model's existing private `developerOptions` snapshot.
- Produces: `@Published var searchText: String` (initially `""`) and `var searchResults: [MenuSearchEntry]` on `MenuViewModel`.

- [ ] **Step 1: Write the failing tests**

Append to `MenuViewModelTests.swift` inside the class:

```swift
    // MARK: - Search

    func testSearchResultsAreEmptyByDefault() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearchResultsReflectTheSearchText() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.searchText = "feature flags"

        XCTAssertTrue(viewModel.searchResults.contains { $0.target == .featureFlags })
    }

    func testSearchResultsUseTheDeveloperOptionsSnapshot() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        Scyther.developerOptions = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let viewModel = MenuViewModel(defaults: makeDefaults())

        // Mutating the global after init must not change what search sees — the view
        // model searches the same snapshot `sections` renders from.
        Scyther.developerOptions = []
        viewModel.searchText = "onboarding"

        XCTAssertTrue(viewModel.searchResults.contains {
            $0.target == .developerOption(name: "Reset Onboarding")
        })
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/MenuViewModelTests 2>&1 | tail -20`
Expected: BUILD FAILURE — `MenuViewModel` has no `searchText`.

- [ ] **Step 3: Write the implementation**

In `MenuViewModel.swift`, add a new `// MARK: - Search` block after the Menu Structure section (after `togglePin(for:)`/before `reloadPinnedItemIDs()` is fine):

```swift
    // MARK: - Search

    /// The current global-search query, bound to `MenuView`'s search field.
    @Published var searchText: String = ""

    /// The search results for ``searchText``.
    ///
    /// Delegates to ``MenuSearchIndex/entries(matching:developerOptions:)`` using the
    /// same developer-options snapshot ``sections`` is built from, so a host-supplied
    /// row is searchable exactly when it is visible. Empty while ``searchText`` is
    /// empty or whitespace.
    var searchResults: [MenuSearchEntry] {
        MenuSearchIndex.entries(matching: searchText, developerOptions: developerOptions)
    }
```

Also add `- ``searchText`` ` and `- ``searchResults`` ` lines to the class-level docc `## Topics` under a new `### Search` heading.

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2.
Expected: PASS (all MenuViewModelTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuViewModel.swift Tests/ScytherTests/Features/MenuViewModelTests.swift
git commit -m "Expose global search state on MenuViewModel"
```

---

### Task 6: `MenuView` search UI

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuView.swift`

**Interfaces:**
- Consumes: `viewModel.searchText`, `viewModel.searchResults` (Task 5), `MenuSearchEntry` (Task 1).
- Produces: `.searchable` menu; internal `destination(for: MenuItem)` view builder (also reused by `navigationRow`).

No new unit tests — this task is pure SwiftUI wiring over already-tested state; verified by building and running on the simulator.

- [ ] **Step 1: Extract `destination(for:)` and simplify `navigationRow`**

In `MenuView.swift`, replace the existing `navigationRow(for:destination:)` with:

```swift
    /// Builds a row that pushes a destination view.
    ///
    /// The label is derived entirely from the item, so every navigation row in the
    /// menu is laid out identically and only the destination varies.
    private func navigationRow(for item: MenuItem) -> some View {
        NavigationLink {
            destination(for: item)
        } label: {
            row(withLabel: item.title, icon: item.icon)
        }
    }

    /// The single item→destination mapping, shared by ``navigationRow(for:)`` and
    /// search results (a sub-page result pushes the page containing the matched row).
    ///
    /// Items that are not navigation rows (value rows, toggles, tokens, developer
    /// options) return an `EmptyView`; no search entry targets them for navigation.
    @ViewBuilder
    func destination(for item: MenuItem) -> some View {
        switch item {
        case .networkLogs: NetworkLogsView()
        case .serverConfiguration: ServerConfigurationView()
        case .environmentVariables: EnvironmentVariablesView()
        case .featureFlags: FeatureFlagsView()
        case .userDefaults: UserDefaultsView()
        case .cookies: CookieBrowserView()
        case .fileBrowser: FileBrowserView()
        case .databaseBrowser: DatabaseBrowserView()
        case .keychainBrowser: KeychainBrowserView()
        case .locationSpoofer: LocationSpooferView()
        case .consoleLogs: ConsoleLoggerView()
        case .deepLinkTester: DeepLinkTesterView()
        case .crashLogs: CrashLogsView()
        case .notificationLogger: NotificationLoggerView()
        case .notificationTester: NotificationTesterView()
        case .fonts: FontsView()
        case .interfaceComponents: InterfacePreviewsView()
        case .gridOverlay: GridOverlaySettingsView()
        case .fpsCounter: FPSCounterSettingsView()
        case .touchVisualiser: TouchVisualiserView()
        case .appearance: AppearanceOverridesView()
        default: EmptyView()
        }
    }
```

Then update every navigation case in `rowContent(for:)` from
`navigationRow(for: item) { SomeView() }` to `navigationRow(for: item)` (the
destination now comes from `destination(for:)`; the developer-option case and all
non-navigation cases are unchanged).

- [ ] **Step 2: Add `.searchable` and the results list**

In `MenuView.swift`:

Add above `body`:

```swift
    /// Whether the menu is showing search results instead of its sections.
    ///
    /// Driven by the query text rather than `@Environment(\.isSearching)`: focusing
    /// the empty search field keeps the browsable menu visible, matching Settings.
    private var isSearchActive: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
```

Restructure `body` so the `List` content switches on `isSearchActive`, and attach
`.searchable` after the `List`'s closing brace (before `.toolbar`):

```swift
    public var body: some View {
        List {
            if isSearchActive {
                searchResultsSection
            } else {
                menuSections
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search")
        .toolbar { /* unchanged */ }
        // remaining modifiers unchanged
    }

    /// The normal browsing content: device header, Pinned, and every menu section.
    /// This is the exact content the `List` held before search was added.
    @ViewBuilder
    private var menuSections: some View {
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
```

- [ ] **Step 3: Render result rows**

Add to `MenuView.swift`:

```swift
    /// The search results, or a "no results" placeholder.
    ///
    /// Result rows are deliberately not pinnable — pinning stays a browsing gesture,
    /// matching the iOS Settings app.
    @ViewBuilder
    private var searchResultsSection: some View {
        if viewModel.searchResults.isEmpty {
            noResults
        } else {
            Section {
                ForEach(viewModel.searchResults) { entry in
                    searchResultRow(for: entry)
                }
            }
        }
    }

    /// A single search result.
    ///
    /// Main-page entries reuse ``rowContent(for:)`` so a toggle result is a live
    /// toggle and a value result shows its value; sub-page entries push the page
    /// containing the matched row via ``destination(for:)``.
    @ViewBuilder
    private func searchResultRow(for entry: MenuSearchEntry) -> some View {
        if entry.isSubpageEntry {
            NavigationLink {
                destination(for: entry.target)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let icon = entry.icon {
                        Label(entry.title, systemImage: icon)
                    } else {
                        Text(entry.title)
                    }
                    breadcrumb(for: entry)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                rowContent(for: entry.target)
                breadcrumb(for: entry)
            }
        }
    }

    /// The navigation path shown beneath a result's title, e.g. "UI/UX → Grid Overlay".
    private func breadcrumb(for entry: MenuSearchEntry) -> some View {
        Text(entry.breadcrumbText)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    /// Shown when the query matches nothing.
    @ViewBuilder
    private var noResults: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text("No results for \"\(viewModel.searchText)\"")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
```

- [ ] **Step 4: Update `MenuView`'s docc header**

Extend the type-level documentation comment with a short paragraph:

```
/// A search field (iOS-Settings style) filters a global index covering every menu row
/// and the static rows inside settings sub-pages; each result shows its navigation
/// path, and sub-page results push the page containing the matched row.
```

- [ ] **Step 5: Build and run the full test suite**

```bash
xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/Menu/MenuView.swift
git commit -m "Add global search UI to the main menu"
```

---

### Task 7: README + final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Global Search to the README**

Find the feature list in `README.md` (look for the section listing features like Feature Flags, Network Logs, etc.) and add, matching the surrounding format:

```markdown
- **Global Search** - Search every menu row and settings sub-page from the main menu, iOS-Settings style, with navigation breadcrumbs on each result
```

- [ ] **Step 2: Run the full test suite one final time**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: TEST SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document global menu search in the README"
```
