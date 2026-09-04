# Localisation

Scyther's own menu ships translated, independently of your app.

@Metadata {
    @PageColor(green)
}

## Overview

Every piece of chrome Scyther draws — menu rows, section headers, search results, buttons,
alerts, empty states — is read from a String Catalog rather than hard-coded English, so the
debug menu can follow either the device's language or a language forced from the `LanguageView`
page. This is entirely separate from localising your own app: Scyther's catalog only covers
Scyther's own copy.

## Supported languages

Scyther ships English (the source language) plus:

- French (`fr`)
- German (`de`)
- Spanish (`es`)
- Italian (`it`)
- Brazilian Portuguese (`pt-BR`)
- Dutch (`nl`)
- Japanese (`ja`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)
- Korean (`ko`)
- Russian (`ru`)
- Arabic (`ar`)

The list is authoritative in two places that must agree: `LANGUAGES` in
`Scripts/localization/build_catalog.py` and `ScytherLocalization.supportedLanguages`.

## How strings are resolved

Every user-facing string in the package is written as `localized("Your English text")` rather
than a bare string literal. That function:

1. Looks the key up as a `String.LocalizationValue` — so Xcode's tooling still recognises it as a
   catalog entry, and any interpolation becomes a `%@` / `%lld` format placeholder.
2. Resolves it against ``LanguageOverride/effectiveBundle`` instead of the default `.module`
   bundle — the forced language's `.lproj` sub-bundle when an override is active from the Language
   page, otherwise the sub-bundle matching the device's own preferred languages.
3. Falls back to the English source text if the key or the language is missing from the catalog.

Two automated checks keep this honest. A lint test walks every file under `Sources/Scyther` and
fails the test suite if a SwiftUI `Text`, `Label`, or similar literal bypasses `localized(_:)`. A
catalog test fails if any key in `Localizable.xcstrings` is missing one of the twelve languages
above.

Translation quality is a separate concern from coverage: every non-English string the generator
writes is marked `needs_review` rather than `translated`, because the translations were
machine-authored. The catalog test only enforces that a translation *exists* for every key and
language — it does not check that a `needs_review` string has been read by a native speaker.

## Adding a string

1. Call `localized("Your English text")` at the call site, in place of the literal.
2. Add the key, with all twelve languages, to the fragment for that module under
   `Scripts/localization/strings/` (a small JSON file per feature).
3. Run `python3 Scripts/localization/build_catalog.py`, which merges every fragment into
   `Sources/Scyther/Resources/Localizable.xcstrings`. Commit the regenerated catalog alongside the
   fragment — CI fails if they disagree.

## Adding a language

1. Add the language's BCP 47 code to `LANGUAGES` in `Scripts/localization/build_catalog.py`.
2. Add the same code to `ScytherLocalization.supportedLanguages`.
3. Fill in that language's value for every key in every fragment under
   `Scripts/localization/strings/`, then run the generator. The catalog test will fail until every
   existing key has an entry for the new language.

## The Language page

`LanguageView` — reached from **UI/UX → Language** in the menu — lists the host app's own
declared localisations as a native inline picker, resolved from `Bundle.main.localizations`
through ``LanguageOverride/availableLanguages``. Selecting a row calls
``LanguageOverride/setPreferredLanguage(_:)``, which writes a single-element `AppleLanguages`
array to standard `UserDefaults`.

That write changes the *host app's* language the next time it launches; iOS reads
`AppleLanguages` at process start, so it does not affect a view already on screen. Scyther's own
menu does not wait for a relaunch — because it resolves strings through
``LanguageOverride/effectiveBundle`` rather than a bundle frozen at launch, it switches
immediately, which is why the menu and the still-running host app can briefly show different
languages. The page then presents an alert explaining that the app-wide change needs a relaunch,
with **Later** and a destructive **Quit App** action. Quitting the app is never automatic: it only
happens if the user explicitly taps **Quit App** in that alert.

``LanguageOverride/reset()`` clears the override, in both the system defaults and Scyther's own
bookkeeping key, and switches the menu back to the device's language immediately.

## Programmatic access

The same override is available outside the UI as ``Scyther/localization``:

```swift
Scyther.localization.setPreferredLanguage("fr")   // forces French app-wide on next launch
Scyther.localization.preferredLanguage            // "fr", or nil for the device default
Scyther.localization.reset()                       // back to the device language
```

## Limitations

- **No live re-render of host UI.** Setting a language only writes `AppleLanguages`; it does not
  tear down and rebuild your app's view hierarchy. A view already on screen keeps showing its
  original language until the app relaunches. Only Scyther's own menu updates immediately.
- **Search keywords stay English.** The alias keywords the menu's search index matches against
  (for example "remote config", "sqlite", "env var") are not localised — they are jargon a
  developer types regardless of interface language, and they are never displayed as UI text.

## Topics

### Override

- ``LanguageOverride``
- ``Scyther/localization``
