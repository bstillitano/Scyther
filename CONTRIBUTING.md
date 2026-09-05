# Contributing to Scyther

Thanks for helping out. This page covers the conventions a change is expected to follow and
the commands to verify one.

## Getting set up

Scyther is an iOS-only Swift package. `swift build` will not work — the target requires UIKit,
so everything is built and tested against a simulator.

```bash
# Build the library
xcodebuild build -scheme Scyther \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO

# Run the test suite
xcodebuild test -scheme Scyther \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO

# Build the example app
xcodebuild build -project Example/ScytherExample.xcodeproj -scheme ScytherExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO

# Build the documentation
xcodebuild docbuild -scheme Scyther \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./docbuild
```

If a simulator is already booted, target it by UDID instead of by name — it is faster and
avoids a cold boot.

`Example/ScytherExample` is the fastest way to see a change on screen. It registers feature
flags, servers, environment variables and a SwiftData store, so most menu pages have real
content to render.

## Conventions

**Architecture.** MVVM with a repository layer. View models live in their own files, separate
from the views that use them, and new models get their own file too. Follow separation of
concerns rather than growing an existing file.

**Concurrency.** The package builds in Swift 6 language mode with strict concurrency. UI
singletons are `@MainActor`; `Servers` and `NetworkLogger` are actors. Anything shared across
isolation domains needs to be genuinely `Sendable`, not asserted to be.

**Tests.** Every change adds or updates tests. Tests should exercise real behaviour rather
than assert against mocks.

**Documentation.** Every new type, property and method gets DocC comments matching the density
of the surrounding code. Update the README for anything user-visible.

**UI.** Use SwiftUI's `ShareLink` rather than building a share sheet. Use alerts, never
`.confirmationDialog`.

## Localised strings

Scyther's interface ships in thirteen languages, so **any user-facing string must go through
`localized(_:)`** rather than being passed to SwiftUI directly:

```swift
Text(localized("Network Logs"))
LabeledContent(localized("Requests"), value: "\(count)")
```

Add the key, with every supported language, to the fragment for the module you are working in
under `Scripts/localization/strings/`, then regenerate the catalog:

```bash
python3 Scripts/localization/build_catalog.py
```

Edit the fragments, never `Sources/Scyther/Resources/Localizable.xcstrings` directly — CI
regenerates the catalog and fails on any drift.

Two tests keep this honest, and both run in the normal suite: one fails if a SwiftUI literal
bypasses `localized(_:)`, and one fails if any key is missing a language or has mismatched
format placeholders. A literal that genuinely is not copy — a `UserDefaults` key, a payload
field name — opts out with a `// scyther:unlocalised <reason>` comment on that line.

Strings that stay untranslated by convention: technical tokens (`HAR`, `cURL`, `JSON`,
`UUID`, `UserDefaults`, HTTP method names), file and folder names, log output, SF Symbol
names, and the Scyther brand itself.

Corrections to existing translations are very welcome — most were machine-authored and are
marked `needs_review` in the catalog. Make them in the fragment and regenerate.

## Pull requests

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Make the change, with tests and documentation.
4. Run the full test suite and build the example app.
5. Open a pull request describing what changed and how you verified it.

## Reporting issues

Use GitHub Issues, and include the device model, iOS version, and Scyther version, along with
minimal reproduction steps.

For security vulnerabilities, email b.stillitano95@gmail.com directly rather than opening a
public issue.
