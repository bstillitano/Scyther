# Localisation of Scyther's UI + App Language Override

**Date:** 2026-09-04
**Status:** Approved design — ready for implementation planning

## Summary

1. **Localise every user-facing string in Scyther** into twelve languages through a String
   Catalog in the package, resolved via one helper so SwiftUI and UIKit call sites behave
   the same way and can follow a runtime locale override.
2. **Add a Language override** to the debug menu that forces the host app's language via
   `AppleLanguages`, re-renders Scyther's own menu in that language immediately, and offers
   to quit the app so the change takes effect everywhere.

## Background

Confirmed in code on 2026-09-04:

- There are **no** `.strings`, `.stringsdict`, or `.xcstrings` files in `Sources`, no
  `defaultLocalization` in `Package.swift`, and no calls to `NSLocalizedString`,
  `String(localized:)`, or `LocalizedStringResource`. The only `Bundle.module` uses load GPX
  fixtures for the location spoofer.
- Roughly **430** user-facing literals are passed straight to `Text`, `Button`, `Label`,
  `Section`, `LabeledContent`, `Toggle`, `TextField`, `ShareLink`, `NavigationLink`,
  `.navigationTitle`, `.alert`, `.accessibilityLabel`, `SharePreview`, and `.searchable(prompt:)`.
  About 25 of them interpolate values. Four UIKit labels (`title =`, `text =`, `setTitle`) exist.
- **8 enums** expose `displayName`-style computed properties with English text
  (status classes, duration buckets, recency windows, filter dimensions and groups, GraphQL
  kinds, host modes, content types).
- **Menu titles** live in `MenuItem.title` and `MenuSection(title:)`. Global search
  (`MenuSearchIndex`) matches titles, breadcrumbs, and an English keyword table.
- `Package.swift` already processes a `Resources` folder (currently only `Map Routes`).
- Swift 6 language mode with strict concurrency is enforced on both targets.

SwiftUI resolves `LocalizedStringKey` literals against `Bundle.main`, and most SwiftUI
initialisers (`Button(_:)`, `Label(_:systemImage:)`, `Section(_:)`, `LabeledContent(_:value:)`,
`.navigationTitle(_:)`, `.alert(_:isPresented:)`) have **no `bundle:` parameter**. A package
therefore cannot rely on implicit lookups; strings must be resolved explicitly through the
package bundle.

## Goals

- Every string a user can see in Scyther's UI is localised, including enum display names,
  menu titles, alerts, accessibility labels, share previews, and interpolated/pluralised text.
- Ship complete translations for: French (`fr`), German (`de`), Spanish (`es`), Italian (`it`),
  Brazilian Portuguese (`pt-BR`), Dutch (`nl`), Japanese (`ja`), Simplified Chinese (`zh-Hans`),
  Traditional Chinese (`zh-Hant`), Korean (`ko`), Russian (`ru`), Arabic (`ar`). English (`en`)
  is the source language and the key.
- A Language page in the menu that lists the host app's declared localisations, applies a
  choice through `AppleLanguages`, updates Scyther's menu at once, and offers to quit.
- A public `Scyther.localization` facade mirroring the other subsystems.
- Tests that keep the catalog complete and stop new unlocalised literals from landing.

## Non-Goals

- Pseudo-localisation, string-length stress, or an RTL preview mode (on ice).
- Translating the README, DocC, or the example app's own copy.
- Localising developer-facing data: log lines written by `logMessage`, HAR content, cURL
  commands, exported file names, error messages surfaced from Foundation, or the `Scyther`
  brand name.
- Live re-rendering of the **host app's** already-visible views after a language change.
  iOS does not support this without a relaunch; the feature is explicit about it.
- Per-app locale/region/calendar overrides beyond language. Region follows the device.

## Design

### Component 1: String Catalog + package configuration

- `Package.swift`: add `defaultLocalization: "en"` to the package declaration. The existing
  `.process("Resources")` rule picks up the catalog.
- New file `Sources/Scyther/Resources/Localizable.xcstrings` (JSON, `version: "1.0"`,
  `sourceLanguage: "en"`). Keys are the English source text. Each key carries the twelve
  target languages with `state: "needs_review"` so native speakers can approve later; strings
  in that state still compile and ship.
- Interpolated strings use `String.LocalizationValue` placeholders (`%lld`, `%@`, `%.0f`).
  Counted strings ("%lld requests", "%lld selected") carry `plural` variations in every
  language whose grammar needs them (English, French, German, Spanish, Italian, Portuguese,
  Dutch, Russian with `one`/`few`/`many`/`other`, Arabic with `zero`/`one`/`two`/`few`/`many`/`other`;
  Japanese, Chinese, and Korean use `other` only).
- Keys are unique English sentences. Where the same English word is used with two meanings
  ("Type" the content-type chip versus "Type" a GraphQL operation type), the key gets a
  disambiguating comment and, if needed, a distinct source string.

### Component 2: `ScytherLocalization` helper (new, isolated)

New file `Sources/Scyther/Core/ScytherLocalization.swift`.

```swift
/// Resolves Scyther's own UI copy from the package catalog, honouring the language override.
func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String
```

- Implementation: `String(localized: key, bundle: LanguageOverride.shared.effectiveBundle)`, where
  `effectiveBundle` is the `<language>.lproj` sub-bundle of `Bundle.module` for the forced
  language (falling back to `Bundle.module` when no override is set or the language is not in
  the catalog). Reading from the sub-bundle is what lets Scyther's menu switch language without a
  relaunch. Note: the `locale:` parameter of `String(localized:)` only formats interpolated
  arguments; it does not choose the language table, so it is not used for switching.
- Takes `String.LocalizationValue`, so a literal at the call site is typed as a localisation
  value and Xcode's compiler-driven catalog sync recognises it. Interpolations become
  format placeholders automatically.
- `comment` is documentation only; it is not used at runtime.
- Free function rather than a `Text` extension because `Button`, `Label`, `Section`,
  `LabeledContent`, `.navigationTitle`, and alerts all need a plain `String`, and one spelling
  everywhere is simpler to lint.

### Component 3: Call-site conversion (all modules)

- Every literal in the initialisers listed in Background becomes `localized("…")`, and the
  SwiftUI initialiser receives a `String` (verbatim). Example:
  `Text("Network logs")` → `Text(localized("Network logs"))`;
  `LabeledContent("Requests", value: "\(count)")` → `LabeledContent(localized("Requests"), value: "\(count)")`;
  `Text("Preparing archive of \(n) requests…")` → `Text(localized("Preparing archive of \(n) requests…"))`.
- Enum `displayName` properties return `localized(...)`.
- `MenuItem.title`, `MenuSection` titles, `DeveloperOption`-independent section headers, and
  `MenuSearchIndex` breadcrumbs go through the helper. Search keywords stay English; the
  localised title and breadcrumb already participate in matching, so search works in both.
- UIKit strings (four) use the same helper.
- Strings that are **not** UI copy stay untouched: `UserDefaults` keys, file names, HAR
  fields, cURL text, log messages, URL scheme identifiers, SF Symbol names, and test fixtures.

### Component 4: `LanguageOverride` (new, isolated) + `Scyther.localization` facade

New file `Sources/Scyther/Features/Localization/LanguageOverride.swift`.

```swift
@MainActor
public final class LanguageOverride: ObservableObject {
    public static let shared: LanguageOverride
    /// The BCP 47 identifier forced via AppleLanguages, or nil for the system default.
    @Published public private(set) var preferredLanguage: String?
    /// Localisations the host app declares (Bundle.main.localizations minus "Base"), sorted by localised name.
    public var availableLanguages: [String]
    /// The locale Scyther's own strings resolve with: the override if set, otherwise nil (bundle default).
    public var effectiveLocale: Locale?
    /// The bundle Scyther's own strings are read from: the override language's .lproj inside the
    /// module bundle when set and present, otherwise the module bundle itself.
    public var effectiveBundle: Bundle
    public func setPreferredLanguage(_ identifier: String?)
    public func reset()
}
```

- `setPreferredLanguage` writes `[identifier]` to `UserDefaults.standard` under `AppleLanguages`
  (the key iOS reads at launch) and remembers the choice in `UserDefaults.scyther` under
  `Scyther.Localization.PreferredLanguage` so the page can show "override active" even if the
  host app rewrites `AppleLanguages`. `reset()` removes both.
- Because `AppleLanguages` is the system key, this is deliberately **not** migrated into the
  private suite; the private key is bookkeeping only.
- Read-only helpers for display: `currentLanguageDisplayName`, `currentRegionDisplayName`,
  and `displayName(for identifier:)` using `Locale.current.localizedString(forIdentifier:)`
  and the language's own name via `Locale(identifier:).localizedString(forIdentifier:)`.
- `Scyther.swift` gains `public static let localization = LanguageOverride.shared`, listed
  with the other facades and in the README's architecture table.

### Component 5: Language page (view + view model)

New files `Sources/Scyther/Features/Localization/LanguageView.swift` and
`LanguageViewModel.swift`.

- Menu: a `.language` `MenuItem` (title "Language", icon `globe`, tint from the UI/UX section)
  added to the **UI/UX** section after Appearance. Search keywords: `locale`, `translation`,
  `localisation`, `localization`, `i18n`, `l10n`, `region`.
- Page sections:
  - **Current**: `LabeledContent` rows for Language (effective, e.g. "Français (France)") and
    Region (device region).
  - **App language**: a checklist of `System Default` plus one row per
    `availableLanguages` entry showing the language's native name with the localised name as a
    secondary line. Selected row shows a checkmark. If the host app declares only English, the
    section footer says so.
  - **Reset**: a destructive-styled button, shown only while an override is set.
- Selecting a row calls `setPreferredLanguage`, then presents an alert
  "Relaunch required" / "The app language changes the next time it launches. Scyther's menu has
  already switched." with **Later** (cancel) and **Quit App** (destructive), which calls
  `exit(0)`. Alerts only; no confirmation dialogs.
- **Immediate re-render of Scyther's menu:** `MenuView` observes `LanguageOverride.shared` and
  applies `.id(preferredLanguage)` at its root together with
  `.environment(\.locale, effectiveLocale ?? .current)` and
  `.environment(\.layoutDirection, …)` for Arabic, so every string is recomputed and layout
  flips for RTL.

### Component 6: Example app

- Add `CFBundleLocalizations` for the twelve languages plus `en` to the example app's
  `Info.plist`, and a minimal `Localizable.xcstrings` with two example-app strings translated,
  so `Bundle.main.localizations` is populated and the Language page has content to show.

### Component 7: Tests

- `Tests/ScytherTests/Core/ScytherLocalizationTests.swift`
  - `localized("Network logs")` returns "Journaux réseau" when the override locale is `fr`.
  - Falls back to English for an unknown locale.
  - Interpolated key resolves with the argument substituted.
- `Tests/ScytherTests/Core/LocalizableCatalogTests.swift` (parses the catalog JSON from
  `Bundle.module`)
  - Every key has every one of the twelve languages with a non-empty value.
  - Placeholder multiset (`%lld`, `%@`, `%.0f`, positional variants) matches the English source
    in every language and every plural variation.
  - No two keys differ only by trailing punctuation or case (catches accidental duplicates).
- `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift`
  - Walks `Sources/Scyther` (path derived from `#filePath`), and fails on any occurrence of the
    listed SwiftUI initialisers or modifiers followed directly by a string literal, except in
    an allow list of files or lines marked `// scyther:unlocalised` with a reason. Keeps the
    catalog honest as new views land.
- `Tests/ScytherTests/Features/LanguageOverrideTests.swift`
  - Uses an injected `UserDefaults` suite pair. Setting a language writes `AppleLanguages`
    and the bookkeeping key; reset clears both; `availableLanguages` excludes `Base` and sorts
    by display name; `effectiveLocale` is nil without an override; `effectiveBundle` is the
    module bundle without an override, the `fr.lproj` sub-bundle with `fr`, and the module
    bundle again for a language the catalog does not contain.
- `Tests/ScytherTests/Features/LanguageViewModelTests.swift`
  - Rows are built from the override; selecting a row sets the language and flags the
    relaunch alert; reset hides the reset row.

### Documentation

- README: new **Localisation** subsection (supported languages, how to add one, the
  `localized` helper convention, the lint test) and a **Language** entry under UI/UX Tools;
  `Scyther.localization` in the architecture table.
- DocC: new article `Localisation.md` covering the same for contributors, plus `///` blocks
  on every new type and member.
- CLAUDE.md: one line under Making Code Changes: "ALWAYS route user-facing strings through
  `localized(_:)` and add the key to `Localizable.xcstrings` with all languages."

## Rollout order

1. Catalog and helper with English only, converting one module (NetworkLogger) end to end, with
   the lint test scoped to that module. Proves the mechanism.
2. Convert the remaining modules; widen the lint test to all of `Sources/Scyther`.
3. Add the twelve translations and the catalog integrity tests.
4. Language override feature, menu entry, example app localisations, docs.

Each step builds and passes the full suite on the booted simulator before the next begins.

## Risks and mitigations

- **Volume.** ~430 keys × 12 languages ≈ 5,000 translated strings. Mitigated by generating the
  catalog from a script over a single source table, and by the integrity tests.
- **Semantic collisions.** Same English word, different meaning. Mitigated by comments and, where
  necessary, distinct source strings; the catalog test flags near-duplicates.
- **Xcode catalog sync.** When the package is opened in Xcode with "Use Compiler to Extract Swift
  Strings" on, Xcode may rewrite the catalog on build. The helper's `String.LocalizationValue`
  parameter keeps extraction consistent with the hand-written keys.
- **`exit(0)` in a library.** Only ever called from the explicit destructive alert action the user
  tapped, never automatically. Documented in the API.
- **Right-to-left.** Arabic exercises RTL in Scyther's own menu via the layout-direction
  environment; visual issues found there are follow-ups, not blockers.
