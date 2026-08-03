# Global Search in the Main Menu

**Date:** 2026-08-03
**Status:** Approved

## Overview

`MenuView` gains an iOS-Settings-style search field. Typing filters a global index that
covers every row on the main menu **and** the static settings rows inside sub-pages
(e.g. "Grid Color" inside Grid Overlay). Each result shows a breadcrumb beneath its
title — `UI/UX → Grid Overlay` — and tapping a sub-page result pushes the page that
contains the matched row. Dynamic content (network log entries, UserDefaults keys,
files, fonts, host-supplied server configurations) is not indexed, matching how the
iOS Settings app treats app content.

Decisions made during brainstorming:

- **Tap behaviour:** a sub-page result navigates to its containing page. No
  scroll-to/highlight anchoring in v1.
- **Scope:** main-menu rows (info rows, toggles, navigation rows, developer options)
  plus hand-curated static rows from settings sub-pages.
- **Approach:** a curated static index as data (`MenuSearchIndex`), not runtime view
  introspection and not a per-feature protocol. The index is a single file; it can be
  split per-feature later without touching the UI.

## Architecture

Two new files in `Sources/Scyther/Features/Menu/`, plus changes to `MenuView` and
`MenuViewModel`.

### `MenuSearchEntry.swift`

```swift
/// A single searchable row in the global menu search index.
struct MenuSearchEntry: Identifiable, Hashable, Sendable {
    /// Stable identity: target id plus title (sub-page entries share a target).
    var id: String { "\(target.id).\(title)" }

    /// The text shown as the result's title, and matched against the query.
    let title: String

    /// The navigation path shown beneath the title, e.g. ["UI/UX", "Grid Overlay"].
    /// Main-page rows have a single component (their section title).
    let breadcrumb: [String]

    /// SF Symbol for the result row, or nil for icon-less rows.
    let icon: String?

    /// The menu row this result resolves to. Main-page entries target themselves;
    /// sub-page entries target the page containing the matched row.
    let target: MenuItem

    /// Whether this entry represents the main-page row itself (rendered via the
    /// existing rowContent, so toggles stay live and value rows show values) or a
    /// row inside the target page (rendered as a NavigationLink to the target).
    let isSubpageEntry: Bool
}
```

### `MenuSearchIndex.swift`

Builds the full entry list and performs matching. Pure data + pure functions —
no UI, fully unit-testable.

```swift
enum MenuSearchIndex {
    /// All entries: one per main-menu row (derived from
    /// MenuSection.allSections(developerOptions:)) followed by the curated
    /// sub-page entries below.
    static func entries(developerOptions: [DeveloperOption]) -> [MenuSearchEntry]

    /// Case- and diacritic-insensitive filtering using localizedStandardContains,
    /// matched against the title and each breadcrumb component. Empty/whitespace
    /// query returns [].
    static func entries(
        matching query: String,
        developerOptions: [DeveloperOption]
    ) -> [MenuSearchEntry]
}
```

Main-menu entries are **derived**, never listed by hand: every `MenuItem` in
`MenuSection.allSections` becomes an entry with `breadcrumb: [section.title]`,
`icon: item.icon`, `target: item`, `isSubpageEntry: false`. Developer options flow
through exactly as they appear in sections, so the "Development Tools" section is
searchable too.

Curated sub-page entries (each `isSubpageEntry: true`, icon inherited from the
target item):

| Target | Titles |
|---|---|
| `.gridOverlay` | Enable Grid, Grid Size, Grid Opacity, Grid Color |
| `.fpsCounter` | Enable FPS Counter, FPS Counter Position |
| `.touchVisualiser` | Show Screen Touches, Log Screen Touches, Show Touch Duration, Show Touch Radius |
| `.appearance` | Color Scheme, Dynamic Type, Override Text Size, Increase Contrast, Reset to System Defaults |
| `.locationSpoofer` | Enable Location Spoofing, Location Presets, Custom Location |
| `.notificationTester` | Request Notification Permission, Send Push Notification, Badge Count, Cancel Scheduled Notifications, Clear Badge & Notifications |
| `.deepLinkTester` | Open URL, Deep Link Presets, Deep Link History |

The breadcrumb for a sub-page entry is `[home section title, target.title]`, e.g.
`["UI/UX", "Grid Overlay"]`, resolved from `MenuSection.allSections` so it can never
drift from the real menu layout.

### `MenuViewModel` changes

- `@Published var searchText: String = ""`
- `var searchResults: [MenuSearchEntry]` — delegates to
  `MenuSearchIndex.entries(matching:developerOptions:)` using the view model's
  existing snapshot of developer options.

No new persistence; search state is transient.

### `MenuView` changes

- `.searchable(text: $viewModel.searchText)` on the existing `List`, with
  `@Environment(\.isSearching)` handled via a small inner view (the environment value
  is only set inside the searchable modifier's content).
- While searching (non-empty trimmed query), the section list is replaced by result
  rows; when the query matches nothing, `ContentUnavailableView.search(text:)` is
  shown (gated behind `#available(iOS 17.0, *)` with a plain-text fallback, matching
  the existing pattern in `CrashLogsView`; the package targets iOS 16).
- Result row rendering:
  - **Main-page entry** — reuses the existing `rowContent(for:)` (live toggles,
    value rows with values, navigation rows pushing their real destination) with the
    breadcrumb rendered beneath in caption/secondary style, components joined by "→".
  - **Sub-page entry** — a `NavigationLink` whose label is title + breadcrumb and
    whose destination is the containing page.
- To avoid duplicating the item→view mapping, the destination-building `switch`
  currently inline in `rowContent(for:)` is extracted into a
  `destination(for: MenuItem)` helper used by both `rowContent` and sub-page results.
- Search result rows are **not pinnable** (no swipe action), matching iOS Settings.
- The device header and Pinned section only render in the browsing (non-searching)
  state.

## Edge cases

- Empty or whitespace-only query → normal menu, untouched.
- Query matches a breadcrumb component (e.g. "grid") → all rows under that page
  match, same as iOS Settings.
- Developer options registered by the host app appear in results; when none are
  registered no "Development Tools" entries exist (mirrors section behaviour).
- `.developerOption` targets render through the existing `developerOptionRow`, so a
  value-type option shows its value and a view-type option navigates.

## Testing

`Tests/ScytherTests/MenuSearchIndexTests.swift` (new) and additions to the existing
menu view model tests:

- Every static `MenuItem` appears in the index exactly once as a main-page entry.
- Sub-page entries all have `isSubpageEntry == true`, a two-component breadcrumb whose
  first component equals the target's home section title, and a target that exists in
  `MenuSection.allSections`.
- Matching is case-insensitive and diacritic-insensitive.
- Breadcrumb matching: "grid overlay" surfaces the sub-page entries under Grid Overlay.
- Empty and whitespace queries return no results.
- Developer options: included when supplied, absent when not.
- `MenuViewModel.searchResults` reflects `searchText` and the snapshotted developer
  options.

Build and full test suite run against the booted iOS simulator. Docc documentation on
all new/changed types; README gains a Global Search feature mention.
