<a href="https://github.com/bstillitano/scizor"><img src=".github/scizor-banner.svg" alt="Looking for the Android version? Get Scizor for Android" width="100%" /></a>

<p align="center">
  <img width="200" height="200" src="https://github.com/bstillitano/Scyther/raw/main/Scyther.png">
</p>

# Scyther

[![CI](https://github.com/bstillitano/Scyther/actions/workflows/ci.yml/badge.svg)](https://github.com/bstillitano/Scyther/actions/workflows/ci.yml)
[![documentation](https://img.shields.io/badge/docs-scyther.io-blue)](https://scyther.io/documentation/scyther) ![platform-badge](https://img.shields.io/badge/platform-iOS-blue) ![license-badge](https://img.shields.io/github/license/bstillitano/Scyther) ![swift-badge](https://img.shields.io/badge/swift-6.0-orange)

A comprehensive iOS debugging toolkit that helps you cut through bugs in your iOS app. Scyther provides tools for developers, QA testers, UI/UX teams, and backend developers. Made with love in Sydney, Australia.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Preferences Storage](#preferences-storage)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Usage Guide](#detailed-usage-guide)
  - [Feature Flags](#feature-flags)
  - [Server Configuration](#server-configuration)
  - [Network Logging](#network-logging)
  - [Traffic Stats](#traffic-stats)
  - [Request Overrides](#request-overrides)
  - [Request Replay](#request-replay)
  - [Breakpoints](#breakpoints)
  - [Network Conditioning](#network-conditioning)
  - [Console Logging](#console-logging)
  - [Crash Logging](#crash-logging)
  - [Database Browser](#database-browser)
  - [Data Browsers](#data-browsers)
  - [Location Spoofing](#location-spoofing)
  - [Push Notification Testing](#push-notification-testing)
  - [UI Debugging Tools](#ui-debugging-tools)
  - [Custom Developer Options](#custom-developer-options)
  - [Environment Variables](#environment-variables)
- [Menu Invocation](#menu-invocation)
  - [Pinning menu items](#pinning-menu-items)
  - [Menu language](#menu-language)
- [API Reference](#api-reference)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Features

### Device & Application Info
- Display device model, OS version, and hardware details
- Show bundle identifier, app version, and build number
- Display process ID and release type (Debug/TestFlight/App Store)
- Show build date and app ID prefix

### Networking
- **Network Logging**: Automatically intercept and log all HTTP requests/responses
- **Request Details**: View headers, body, timing, and response codes
- **cURL Export**: Generate cURL commands for any captured request
- **Log Export**: Share the captured requests as a zip containing a HAR 1.2 file, raw bodies, and a cURL command per request, with best-effort redaction and a sensitivity warning
- **Filter Chips**: Narrow the network log by method, status class, host, content type, API kind, GraphQL operation, duration, exact status code, or recency from glass chips pinned above the list, or edit every filter at once from the all-filters sheet
- **Traffic Stats**: A chart button on Network Logs opens the figures for whatever the list is showing — failure rate, median and 95th percentile duration, bytes received, the slowest endpoints, a per-host breakdown, and a waterfall of the recent requests on a shared axis
- **Request Overrides**: Mock responses, serve local files, rewrite headers, and add latency, throttling or random failures to matching requests — combined on one override — from the menu or from code
- **Save as Mock**: Turn any captured response into a disabled mock override in one tap, and import a HAR file as a whole set of them
- **Request Replay**: Reopen any captured request in an editor, change its method, URL, headers or body, and send it again — the resent request is logged with a `REPLAY` badge and listed on the original with its status, duration and size deltas
- **Breakpoints**: Hold a matching request before it is sent, or a matching response before the app sees it, edit method, URL, headers, status or body in place, then continue or fail it with an error of your choosing — every hold has a timeout, and none of it ever runs during a test
- **Network Conditioning**: Degrade every intercepted request at once — latency, a bandwidth ceiling and a failure rate, with the presets Network Link Conditioner made familiar
- **Server Configuration**: Switch between development, staging, and production environments
- **IP Address**: Display the device's public IP address

### Data Management
- **Feature Flags**: Register and override feature flags at runtime
- **UserDefaults Browser**: View and modify UserDefaults values
- **Cookie Browser**: Inspect and manage HTTP cookies
- **Keychain Browser**: View keychain items (read-only for security)
- **File Browser**: Browse app sandbox (Documents, Library, Caches, tmp)
- **Database Browser**: Browse SQLite, CoreData, and SwiftData databases with full CRUD support

### System Tools
- **Location Spoofing**: Fake GPS coordinates for testing location-based features
- **Preset Locations**: 20+ major cities worldwide
- **Custom Locations**: Set any coordinate manually
- **Route Simulation**: Simulate movement along predefined routes
- **Deep Link Tester**: Test custom URL schemes and universal links with QR scanner
- **Crash Logging**: Capture and view uncaught exceptions on subsequent app launches

### Notifications
- **Push Notification Tester**: Schedule local test notifications
- **Notification Logger**: View received notification payloads
- **Token Display**: View APNS and FCM device tokens

### UI/UX Tools
- **Grid Overlay**: Display alignment grid over your UI
- **FPS Counter**: Real-time frame rate overlay with color-coded performance indicators
- **Touch Visualizer**: Show touch points for demos and recordings
- **View Frames**: Highlight view boundaries with colored borders
- **View Sizes**: Display view dimensions as labels
- **Slow Animations**: Reduce animation speed for debugging
- **Appearance Overrides**: Force dark/light mode, high contrast, and Dynamic Type sizes
- **Font Browser**: View all available system fonts
- **Interface Previews**: Browse registered UI components
- **Language**: Force the app's language from the debug menu (applies on next launch; Scyther's own menu switches immediately)

### Development Tools
- **Console Logger**: Capture and view stdout/stderr output
- **Custom Options**: Add your own debug options to the menu

## Requirements

- iOS 16.0+
- Xcode 16+
- Swift 6.0+

## Swift 6 Compatibility

Scyther is fully compatible with Swift 6 strict concurrency checking. The library uses modern Swift concurrency patterns throughout:

### Concurrency Architecture

| Component | Isolation | Notes |
|-----------|-----------|-------|
| `Scyther` | `@MainActor` | Main entry point, UI presentation |
| `Scyther.servers` | `actor` | Thread-safe server configuration |
| `NetworkLogger` | `actor` | Thread-safe request logging with `AsyncStream` |
| `Scyther.featureFlags` | `@MainActor` | Feature flag management |
| `Scyther.network` | `@MainActor` | Network facade |
| `Scyther.console` | `@MainActor` | Console capture facade |
| `Scyther.crashes` | `@MainActor` | Crash logging facade |
| `Scyther.interface` | `@MainActor` | UI tools facade |
| `Scyther.location` | `@MainActor` | Location spoofing facade |
| `Scyther.localization` | `@unchecked Sendable` | `LanguageOverride`, lock-guarded language override facade |

### Working with Actors

The `Servers` subsystem is an actor, requiring `await` for all access:

```swift
// Register servers (requires await)
await Scyther.servers.register(id: "dev", variables: ["API_URL": "https://dev.api.com"])

// Access current configuration (requires await)
let currentServer = await Scyther.servers.currentId
let apiURL = await Scyther.servers.variables["API_URL"]
```

### Sendable Conformance

Key public types conform to `Sendable` for safe cross-actor usage:

- `ServerConfiguration` - Server environment configuration
- `Location` - GPS coordinate data
- `Route` - Location simulation routes
- `ConsoleLogEntry` - Captured console output
- `CrashLogEntry` - Captured crash data

### Performance Optimizations

Scyther uses `nonisolated` properties for UserDefaults-backed settings to avoid actor hop overhead in hot paths. This ensures the debugging tools don't impact your app's UI performance.

### Localisation

Scyther's own interface is available in twelve languages besides English: French, German,
Spanish, Italian, Brazilian Portuguese, Dutch, Japanese, Simplified and Traditional Chinese,
Korean, Russian, and Arabic. It picks one the same way any app does — from the language the
user is running — so a developer on a French device opens a French debug menu without
configuring anything. Arabic lays the menu out right to left.

Every non-English string was machine-authored and is marked `needs_review` in the catalog
rather than `translated`. Treat them as a working draft until a native speaker has approved
them.

#### The Language page

**UI/UX → Language** lists your app's own localisations and switches between them, so a tester
can check a screen in Japanese without changing the device language or reinstalling.

The switch takes effect app-wide on the next launch, so the page offers to quit — **Later** or
**Quit App**, and Scyther never quits on its own. Scyther's menu switches immediately, which
means it can briefly be in a different language than the screen behind it. That is expected:
iOS reads the app's language once at launch, and no app can retranslate views already on
screen without restarting.

#### `Scyther.localization`

The override is also available programmatically, as `Scyther.localization` (`LanguageOverride`):

```swift
Scyther.localization.setPreferredLanguage("fr")  // forces French app-wide on next launch
Scyther.localization.preferredLanguage           // "fr", or nil for the device default
Scyther.localization.availableLanguages          // the host app's declared localisations
Scyther.localization.reset()                     // back to the device language
```

`Scyther.notifications.scheduleTest(title:body:delay:sound:incrementBadge:)` takes optional
`title` and `body`; omitting either (or passing `nil`) falls back to Scyther's own localised
sample notification copy instead of English placeholder text.

The example app at `Example/ScytherExample` ships its own
`Example/ScytherExample/Resources/Localizable.xcstrings`, so it is fully localised in the same
languages independently of the package's own catalog.

#### Adding or correcting a translation

Strings live in per-module fragments under `Scripts/localization/strings/`, which
`Scripts/localization/build_catalog.py` merges into the shipped String Catalog. Edit the
fragment and re-run the generator rather than editing the catalog directly — CI regenerates
it and fails on any drift.

To add a string, call `localized("Your English text")` at the call site and add the key with
every supported language to that module's fragment. To add a language, list its code in the
generator's `LANGUAGES` and in `ScytherLocalization.supportedLanguages`, then fill in every
fragment. A test fails the suite if a SwiftUI literal bypasses `localized(_:)`, and another
fails if any key is missing a language.

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
automatically, and your app's standard domain is left cleaner than it was. This prefix match
is the one place migration touches data it did not write itself: a key your own app happens
to store under a `scyther`-prefixed name would also be moved.

You can inspect and edit the suite from **Data → UserDefaults**, using the store picker at
the top of the screen.

## Installation

### Swift Package Manager

Add Scyther to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bstillitano/Scyther.git", branch: "main")
]
```

Or in Xcode:
1. Go to **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/bstillitano/Scyther.git`
3. Select the `main` branch

## Quick Start

### Basic Setup

```swift
import Scyther

@main
struct MyApp: App {
    init() {
        // Start Scyther (automatically disabled on App Store builds)
        Scyther.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

For UIKit apps:

```swift
import Scyther

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Scyther.start()
        return true
    }
}
```

### Opening the Menu

Once started, **shake your device** (or press `Cmd + Ctrl + Z` in the simulator) to open the Scyther debug menu.

You can also open it programmatically:

```swift
Scyther.showMenu()
```

## Detailed Usage Guide

### Feature Flags

Register feature flags from your remote configuration system and allow developers to override them locally.

#### Registering Flags

```swift
// After fetching your remote config
Scyther.featureFlags.register("new_checkout_flow", remoteValue: true)
Scyther.featureFlags.register("dark_mode_v2", remoteValue: false)
```

#### Checking Flag Values

```swift
if Scyther.featureFlags.isEnabled("new_checkout_flow") {
    showNewCheckoutFlow()
} else {
    showLegacyCheckoutFlow()
}
```

#### Enabling Local Overrides

```swift
// Allow users to toggle flags in the Scyther UI
Scyther.featureFlags.localOverridesEnabled = true

// Programmatically set a local override
Scyther.featureFlags.setLocalValue(true, for: "dark_mode_v2")

// Clear a single override, reverting the flag to its remote value
Scyther.featureFlags.clearLocalValue(for: "dark_mode_v2")

// Clear every override at once
Scyther.featureFlags.clearAllLocalValues()
```

In the Scyther UI, each flag is controlled by a **True / False / Remote** dropdown menu.
Choosing **Remote** clears that flag's local override so it follows its remote value, and the
**Reset all to Remote** button clears every override in one tap. The **Enable overrides** toggle
at the top gates whether these local values are applied by `isEnabled(_:)`.

The flag sections and the reset button are only shown while **Enable overrides** is on. With
overrides off, local values have no effect, so the list and the reset button are hidden; the
search field remains visible either way.

Toggles can be pinned via a left swipe. Pinned toggles appear in a **Pinned** section at the
top of the list and also remain in the main list. Pins persist across launches in Scyther's
private preferences suite.

#### Reading an Override Off the Main Actor

`Scyther.featureFlags` is `@MainActor`-isolated, but you can read a flag's developer
override from any thread or actor via `localOverride(for:)`. It is `nonisolated` because it
reads only `UserDefaults`-backed state. It returns `nil` when global overrides are off or the
flag was never overridden — meaning "use your own value":

```swift
// Safe from a background context — no main-actor hop required.
let override = Scyther.featureFlags.localOverride(for: "dark_mode_v2")
let darkModeV2 = override ?? myRemoteConfig.darkModeV2   // override wins when present
```

#### Accessing All Flags

```swift
for flag in Scyther.featureFlags.all {
    print("\(flag.name): remote=\(flag.remoteValue), local=\(flag.localValue)")
}
```

---

### Server Configuration

Switch between different backend environments without recompiling.

#### Registering Servers

```swift
await Scyther.servers.register(id: "development", variables: [
    "API_URL": "https://dev-api.example.com",
    "WEBSOCKET_URL": "wss://dev-ws.example.com",
    "DEBUG_MODE": "true"
])

await Scyther.servers.register(id: "staging", variables: [
    "API_URL": "https://staging-api.example.com",
    "WEBSOCKET_URL": "wss://staging-ws.example.com",
    "DEBUG_MODE": "true"
])

await Scyther.servers.register(id: "production", variables: [
    "API_URL": "https://api.example.com",
    "WEBSOCKET_URL": "wss://ws.example.com",
    "DEBUG_MODE": "false"
])
```

#### Accessing Current Configuration

```swift
// Get current server ID
let currentServer = await Scyther.servers.currentId

// Get a specific variable
let apiURL = await Scyther.servers.variables["API_URL"]

// Get all variables for current server
let allVars = await Scyther.servers.variables
```

#### Responding to Server Changes

Implement the `ScytherDelegate` to respond when users switch servers:

```swift
class AppCoordinator: ScytherDelegate {
    init() {
        Scyther.delegate = self
    }

    func scytherDidSwitchServer(to serverId: String) {
        // Reconfigure your networking layer
        APIClient.shared.configure(with: serverId)

        // Clear cached data
        CacheManager.shared.clearAll()

        // Optionally restart the app or re-authenticate
        AuthManager.shared.refreshToken()
    }
}
```

---

### Network Logging

All HTTP requests made through `URLSession` are automatically intercepted and logged.

#### Accessing Network Data

```swift
// Get the device's public IP address
let ip = await Scyther.network.ipAddress
print("Device IP: \(ip)")
```

#### Viewing Requests in Code

Network requests are displayed in the Scyther UI under **Network Logs**. Each request shows:

- URL and HTTP method
- Request/response headers
- Request/response body — both a structured **Browse** view (JSON tree) and a raw **View** view
- Status code and timing
- cURL command for reproduction, shareable from the export button in the navigation bar or the "Export cURL request" row at the bottom of the page

Above the list, a row of filter chips narrows the log: Method, Status, Host, Type, API, GraphQL,
Duration, Code, and Recency. Tapping a chip opens a sheet with a multi-select checklist;
selections apply immediately and combine with the search field. Active chips are fully tinted
and show the selected value, or a count when several are selected; the Clear chip is red. Method, host, and exact status code options are built from the
captured requests, so you only ever choose from values that exist. The Host list has an Include /
Exclude control in its header, so the selected hosts can act as an allow list or a deny list. An icon-only chip at the start
of the row opens a Filters sheet listing every dimension, grouped into Request, Response, and Timing, with
its current selection; each row pushes that dimension's checklist. A Clear chip appears whenever a filter is active.

The export button in the navigation bar shares the requests currently shown (so search and
filters narrow the archive) as `<App-Name>-Network-Log-<timestamp>.zip`, named after the host app. The zip holds a HAR 1.2
file that opens in Charles, Proxyman, or Chrome DevTools, plus a folder per request with the raw
request body, raw response body, and a cURL command. The export sheet shows progress while the
zip is built, and a Redaction toggle (on by default) replaces common tokens, cookies, passwords,
and API keys in headers, URLs, bodies, and cURL commands with `REDACTED`, as a best-effort attempt
rather than a guarantee. Because the archive can include full headers, cookies, tokens, and
bodies, tapping Export shows a sensitivity alert before the system share sheet opens.

#### GraphQL Support

GraphQL operations are detected automatically — either by the request body shape (a JSON
payload with a `query` field) or by a `graphql`/`gql` URL path. When a request is recognised
as GraphQL:

- **Request list**: the row shows the **operation name** with a coloured **query / mutation /
  subscription** lozenge, instead of just the shared endpoint URL (the URL moves to a subtitle).
  Batched operations show as `Batch (N operations)`.
- **Request details**: a dedicated **GraphQL** section displays the operation name, type, and a
  **Browse variables** link that opens the structured data browser on the operation's `variables`.
- **Search**: the search field matches the GraphQL operation name in addition to URL, status
  code, and method.

Detection covers `POST` JSON request bodies; GraphQL-over-GET / persisted queries are not
currently detected.

#### Structured data browser

The **Browse request body**, **Browse response body** and **Browse variables** links open a
structured data browser that drills into nested arrays and dictionaries. Its chrome is
localised — the title, the search prompt, the empty-section text, the Copy action, the
`Array` and `Dictionary` value labels and the `Array Data` / `Dictionary Data` headers of a
nested level — while the payload itself is shown exactly as it was sent or received: keys,
values, array indices, `true` / `false` / `null` and JSON text are never translated.

#### Log Retention

Network logs are automatically cleaned up to prevent disk bloat:

- **7-day retention**: Log files older than 7 days are automatically deleted on app startup
- **Manual cleanup**: Clearing logs via the UI also deletes all associated files from disk
- **Files managed**: `SessionLog.log`, request body files, and response body files

---

### Traffic Stats

The chart button in the **Network Logs** toolbar opens **Traffic Stats**: what is slow, what is
failing, and what was happening at the same time as what. Everything is computed from the requests
already in memory, so it adds no capture, no storage and no cost to the request path.

The screen describes **the list you were looking at**. The log's search field and filter chips
narrow the requests before the figures are computed, so filtering to one host turns the summary
into that host's summary. The caption under the title says which it is — `8 requests`, or
`21 of 340 requests` when a filter is on.

#### What the figures mean

| Row | Meaning |
| --- | --- |
| Requests | Every request in the filtered set, stubbed or not |
| Stubbed | How many of them a request override answered without touching the network |
| Failures | Requests that came back at 400 or above, plus loads that ended with no response at all |
| Failure rate | Failures over the requests that actually went to the network |
| Pending | Requests still in flight |
| Median / 95th Percentile | Round-trip duration, nearest rank |
| Fastest / Slowest | Shown instead of the percentiles below five completed requests |
| Bytes Received | Total response body length received over the network, whatever the bytes are |
| Elapsed | Wall-clock time from the first measured request starting to the last one finishing |

**Pending and failed are exclusive.** A load carries a response date whether or not a response
arrived, so a request that ended in an error is a *failure* and one that has not come back yet is
*pending*. Neither is counted as a zero-duration completion, which would flatter every latency
figure.

**Stubbed responses are counted but never measured.** A response a request override synthesised
never left the device: its duration measures Scyther rather than the server, and its status code
was authored rather than returned. Averaging it into "slowest endpoints" or an error rate would
make both lie, so a stub is counted in *Requests* and *Stubbed* and left out of every duration,
failure and byte total, and out of the host and endpoint breakdowns entirely — *Elapsed*
included, so a stub answered an hour after the last real request does not report an hour of
network activity that never happened.

**Percentiles use the nearest rank**, not interpolation, so every duration reported is one a
request actually took. **Below five completed requests there are no percentiles at all** — a
median of three samples is noise — and the summary shows the fastest and slowest round trips
instead.

#### The waterfall

One bar per request, the most recent forty, on a shared seconds axis: bars that overlap were in
flight at the same time, and a staircase means the calls were serialised. Each bar is labelled
with its duration and coloured by outcome — succeeded, failed, pending or stubbed. A request that
has not come back yet runs to the end of the axis, which is the moment the chart was computed,
because its real end is not known. A request that failed is drawn for as long as it actually ran,
not as one still running.

#### The breakdowns

**Slowest Endpoints** groups requests by `METHOD host/path` with the query string dropped and any
numeric or UUID path segment collapsed to `:id`, so `/users/1` and `/users/2` aggregate rather
than producing one endpoint per record. A GraphQL operation carries its name —
`POST api.example.com/graphql (GetUser)` — because every operation in a GraphQL API is posted to
the same path and the name is what identifies the call. Each row shows the request count, the
median, and — as the figure beside it — the slowest round trip.

**By Host** puts the worst offender first: most failures, then slowest median. Each row shows the
request count, how many failed, and the host's median round trip.

Stats describe the current session only. The log is an in-memory FIFO, so nothing is persisted
across launches and there are no trends over time.

---

### Request Overrides

Network logging shows what the app asked for and what came back. **Request Overrides**, under
**Networking → Request Overrides**, changes it — mocking endpoints, serving local files, rewriting
headers and degrading the connection without touching the app's networking code. The API type is
called `NetworkRule`, so an override in the menu is a rule in code.

Each override matches on HTTP method, host, path and query. An omitted facet places no
constraint, and host and path accept `*` as a wildcard. Overrides are evaluated top to bottom, and
dragging a row is what changes precedence:

- The **first** matching stub — a mock or a map local — wins and short-circuits the network.
- The **first** matching condition supplies the latency, bandwidth ceiling and failure rate;
  conditions are not stacked.
- **Every** matching header rewrite applies, and the **last** override to name a header decides
  what happens to it — a later `set` beats an earlier `remove` exactly as it beats an earlier
  `set`, and a later `remove` beats an earlier `set`. Header names are compared
  case-insensitively, so `Authorization` and `authorization` are one header. Within one rewrite
  there is no order to appeal to, so headers are set before any are removed and a header named in
  both ends up removed.

#### What Matching Compares

- Method, host and path are compared **case-insensitively**. Query names are compared
  **case-sensitively**, because a query name is data rather than protocol.
- The path is compared **percent-encoded**, exactly as it travels. `%2F` is therefore not a
  separator — `/v1/a%2Fb` is one segment and does not satisfy a rule for `/v1/a/b` — and a path
  copied out of the log, out of a HAR or off an address bar matches the request it came from. A
  path typed with a literal space will not.
- A **trailing slash is part of the path**: `/v1/users` and `/v1/users/` are different paths, and
  `/v1/users*` matches both. A URL with no path at all, `https://api.example.com`, is matched
  as `/`.
- Every query pair listed must be present. A repeated key is satisfied by **any** of its
  occurrences, so `page=2` matches `?page=1&page=2`, and a key present with no value — `?flag` —
  reads as an empty value. Values are compared percent-decoded.
- A pattern left **blank** places no constraint at all, exactly as leaving the facet out does.

#### Actions Compose

An override carries a stub, a header rewrite and a condition **independently**, each with its own
switch in the editor. Mock and map local are the one pair that cannot both apply, because they
would both be answering the same request; everything else combines, so "mock this endpoint and
make it slow" is one override rather than an impossibility.

A stub no longer suppresses the rest:

- **A condition applies to a stubbed response.** Its latency delays the synthesised answer — added
  to the stub's own delay, then clamped once — its failure rate can fail it, and its bandwidth
  ceiling paces the synthetic body.
- **A header rewrite is recorded on the logged request but has no wire effect** when the request
  is stubbed, because nothing is sent. The log still shows the request as it would have gone out.

The log's **Overrides** row credits everything that actually contributed, which for a stubbed
request is the stub first and then whatever else applied to it. An override carrying several
actions is named once. Each credit is its own row: one the store still holds pushes its editor
and follows a rename made through it, and one whose override has since been deleted — or that has
none, like the global conditioning — is named but inert.

| Action | What it does |
| --- | --- |
| **Mock Response** | Answers with a status code, headers and a body typed into the editor, after an optional delay. Headers are a dictionary, so a mock cannot repeat a header name — a HAR import keeps the last of a repeated `Set-Cookie`. |
| **Map Local File** | Answers with the contents of a file, with a status code and `Content-Type`. The file is chosen with the system file importer and **copied into Scyther's rules directory**, so the override keeps working after the document moves or goes away and no security-scoped bookmark is needed. A path supplied from code is used as given; an unreadable path, or one over 10 MB, falls through to the real network. |
| **Rewrite Headers** | Sets and removes headers on the outgoing request. |
| **Network Condition** | Adds latency, caps bandwidth in KB/s, and fails a fraction of matching requests with a `URLError`. Latency and a stub's delay are capped at 30 seconds together, and are waited out without holding a thread. The latency is applied first and the failure rolled after it, so "slow and flaky" is slow before it is flaky, and a rate of `1` never lets a request through. |

A bandwidth ceiling is likewise honoured for at most 30 seconds of added delay per response, so
that a debug tool cannot appear to have hung. A body larger than `30 × bandwidthKBps` kilobytes
stops being paced part-way through and the rest is forwarded as fast as it arrives, which makes
the effective rate a function of body size: 1 MB at 10 KB/s takes about 30 seconds, not the 100
the ceiling implies. Pacing is measured across the whole response rather than per delivery, so a
response whose bytes have averaged out under the ceiling is never delayed, however the source
chose to chunk them; a response that has been idle banks at most one second of that idle as
credit, so a long-poll or an SSE stream is throttled rather than released in bursts.

#### In the Editor

- **An override has to name an endpoint.** It is not savable until it is named, given a host, path
  or query, and given something to do. A facet that matches everything however it is spelled — a
  path of `*` set to Wildcard, or `/` set to Contains — does not count, because an override
  applied to every request in the app is the hazard the guard exists to prevent. A method on its
  own does not count either.
- **A mock body that is not text is left alone.** A body holding bytes that are not valid UTF-8 —
  a captured image, most often — is shown as a size rather than opened in the text editor, because
  editing it as text would write every one of those bytes back as a replacement character. So is
  a body larger than a megabyte, which is more than anyone edits by hand.
- **The map local file is one row.** It reads *Choose File* until something is chosen and then
  shows the name of the document that was picked, not the name of the copy Scyther keeps. Tapping
  it opens the picker either way, so replacing a file is the same gesture as choosing one.
- **The `Content-Type` is picked, not typed.** The types a developer actually mocks are offered in
  a picker, with **Custom** revealing a free-text field for anything else. Picking a file fills it
  in from the document's type, so `response.json` arrives as `application/json`.
- Status codes are stored inside `100...599`, and a negative or non-numeric delay is stored as
  zero.

#### Saving a Captured Request as a Mock

The request details page carries a **Save as mock** button whenever the response came off the
wire. It opens the override editor pre-filled from the capture: matching that request's method,
host and path exactly, answering with its status code, headers and body. The query string is left
unconstrained, and headers describing the wire encoding (`Content-Encoding`, `Content-Length`,
`Transfer-Encoding`) are dropped, because the stored body is the one `URLSession` already decoded.

The override arrives **disabled** — nothing changes until it is switched on, from the editor or
with a swipe on the list.

A response an override already synthesised cannot be saved as a mock. Those rows are marked
instead: a pink **MOCKED** badge in the log list, and an **Overrides** row in the details
page's Developer Info section naming every override that shaped the request.

An override that shapes a request **without answering it** — a header rewrite, or a network
condition — leaves the row looking like ordinary traffic otherwise, so it carries a brown
**OVERRIDDEN** badge instead. The four badges use four colours nothing else in the log wears, so
`MOCKED`, `OVERRIDDEN`, `REPLAY` and `HELD` can appear together on one row and still be read
apart. A stubbed row never wears `OVERRIDDEN`, because `MOCKED` already says what happened.

#### Importing a HAR File

**Import from HAR**, in the add menu of the overrides list, reads a HAR 1.2 document — one
exported by Scyther, or captured in Charles, Proxyman or Chrome DevTools — and turns each entry
into a mock override named `<METHOD> <path>` matching that method, host and path. Every imported
override arrives disabled.

Entries are read one at a time, so the things a real capture contains — an aborted request with no
`response` object, a multipart upload whose `postData` carries `params` and no `text`, an entry
whose URL cannot be parsed — cost those entries and nothing else rather than discarding the whole
import. The alert reports both numbers: how many overrides were added, and how many entries
produced none.

A response body labelled `encoding: "base64"` is decoded even when it is wrapped across lines, the
way Charles and other MIME-style encoders write it. Text that plainly is not base64 is taken as
the literal body it is rather than decoded into bytes that came from nowhere.

#### The Master Switch

**Enable Request Overrides**, at the top of the list, suspends every override at once without
deleting any of them — the quickest way to tell whether a behaviour belongs to the app or to an
override. It is persisted across launches.

The count badge on the menu's **Request Overrides** row follows this switch: it reports how many
overrides are *being applied*, so turning the switch off empties it however many overrides are
enabled behind it.

#### Registering Overrides in Code

`Scyther.network.rules` is the programmatic entry point. Like every other Scyther singleton it is
`@MainActor`-isolated, and every member of it is inert until `Scyther.start()` has run — which it
does not do on an App Store build. The calls below can sit unguarded in `didFinishLaunching`: on a
release build they read back nothing, write nothing to preferences, and put no file in the user's
container.

```swift
// Persisted: written to UserDefaults, listed in the menu, survives relaunch. The
// identifier is a constant, so relaunching updates this override instead of adding
// another copy of it beside the first.
let emptyCart = UUID(uuidString: "6F0B0C3E-4C1E-4E3D-9C0B-0F5E7A9D2B41")!
Scyther.network.rules.add(
    .mock(id: emptyCart,
          name: "Empty cart",
          matching: .path("/api/cart"),
          returning: .json(#"{"items": []}"#))
)

// This launch only: never written to disk, listed read-only under "Registered in Code".
Scyther.network.rules.addTransient(
    .headers(name: "Staging auth",
             matching: .host("*.staging.example.com"),
             set: ["Authorization": "Bearer test-token"])
)

// Several actions at once: build the rule directly rather than through the
// single-action conveniences above.
Scyther.network.rules.add(
    NetworkRule(name: "Slow cart",
                match: .path("/api/cart"),
                actions: NetworkRuleActions(stub: .mock(.json("{}")),
                                            condition: NetworkCondition(latency: 3)))
)

// Read, edit and clear.
let overrides = Scyther.network.rules.all
Scyther.network.rules.remove(id: overrides[0].id)
Scyther.network.rules.isEnabled = false   // suspend everything, delete nothing
```

`add(_:)` **persists** the override and shows it in the menu, where it can be edited, reordered or
deleted. `addTransient(_:)` does **not**: transient overrides live only for the launch that
registered them, appear read-only under "Registered in Code", and are evaluated after every
persisted override. Use the transient form for anything the app registers for itself.

Both are an **upsert** on `NetworkRule.id`: an override whose identifier is already known replaces
that override in place, and whatever body file the replaced override owned is reclaimed unless
another override still points at it. Code that runs on every launch should therefore pass a
constant `id`, as the example above does — an override built without one gets a fresh identifier
each time, so a call in `didFinishLaunching` would store another copy of the same override on every
launch.

An identifier lives in **exactly one** of the two lists. Registering a transient override under an
identifier the persisted list holds moves it across, and vice versa: the last registration wins
outright, rather than leaving two copies that `remove(id:)` can only half delete.

`MockResponse.json(_:)` writes nothing when it is built. The bytes travel with the value and are
written when the override holding it is added or updated, so a response that is never stored leaves
nothing on disk. If those bytes cannot be written the override is **not** stored — `add(_:)` and
`update(_:)` return `false` and the menu says so — because an override pointing at a body that is
not there would answer with the right status code and an empty body.

Overrides are persisted as JSON, which cannot express an infinite or NaN number. A latency, delay
or failure rate that is not finite — `1e400` typed into the editor parses to `inf` — is replaced
with `0` on the way in, rather than being allowed to fail the write for every override at once.
Global conditioning is sanitised the same way. If a write does fail, or if the saved overrides
cannot be read at launch, the overrides screen says so; an unreadable blob is set aside under its
own preferences key rather than overwritten, and a second one is added beside the first rather
than replacing it. While anything is set aside the orphan sweep stands down, so the bodies those
overrides point at are kept along with them. Discarding every override discards the set-aside
configurations too, and is what lets the sweep start reclaiming again — from the alert itself,
which offers **Delete All Overrides**, or from `Scyther.network.rules.removeAll()`.

#### Stubbing a UI Test

Transient overrides make a UI test hermetic without running a stub server.

> **Register after `Scyther.start()`, not before.** Every member of `Scyther.network.rules` is
> inert until `start()` has run, and `add(_:)`, `addTransient(_:)` and `update(_:)` are all
> `@discardableResult` — so a block placed *above* `start()` compiles, runs, warns about nothing,
> and registers nothing. Since the block below sits behind a launch argument it reads as though it
> could go anywhere in `didFinishLaunching`; it cannot. If you want the compiler's help, read the
> `Bool` these return: `false` means nothing was stored.

```swift
// In the app, in didFinishLaunching, *after* Scyther.start().
Scyther.start()

if ProcessInfo.processInfo.arguments.contains("-UITestStubs") {
    Scyther.network.rules.isEnabled = true
    let registered = Scyther.network.rules.addTransient(
        .mock(name: "Profile",
              matching: .host("api.example.com", path: "/v1/profile", methods: ["GET"]),
              returning: .json(#"{"name": "Ada"}"#))
    )
    assert(registered, "Scyther.start() must run before any override is registered")

    Scyther.network.rules.addTransient(
        .condition(name: "Slow uploads",
                   matching: .path("/v1/upload", methods: ["POST"]),
                   NetworkCondition(latency: 2, failureRate: 0.5))
    )
}
```

```swift
// In the test.
let app = XCUIApplication()
app.launchArguments += ["-UITestStubs"]
app.launch()
```

Because they are transient, the *overrides* do not survive the launch that registered them: a stub
left behind by a failing run cannot quietly break the next one. The master switch is a different
matter — `isEnabled` is persisted, so setting it here leaves it on for the developer's next
ordinary launch as well. That is usually what you want, since it is on by default; if a run may
have turned it off, set it explicitly as the snippet does rather than assuming.

> **Note**: Overrides apply only to traffic Scyther intercepts — `URLSession` traffic through a
> standard configuration. A custom `URLSessionConfiguration` that does not carry Scyther's
> `URLProtocol` bypasses overrides exactly as it bypasses logging.

---

### Request Replay

The request details page carries a **Replay this request** button. It opens an editor pre-filled
from the capture — method, URL, headers and body — and sends whatever is left there when the
confirm button is tapped.

#### The Editor

- **Method** — a picker of the common verbs, plus **Other** for anything the server invented.
- **URL** — a single-line field. The confirm button is disabled, and a warning appears, while what
  has been typed will not parse into an absolute HTTP URL.
- **Headers** — one row per captured header, editable, swipe-deletable, with an add row. Headers
  `URLSession` owns — `Content-Length`, `Host` and `Connection` — are shown but disabled, and are
  dropped rather than sent, because editing them has no effect. A duplicated header name travels
  as the one comma-joined field HTTP defines rather than one row silently winning.
- **Body** — a row opening the same text editor the rest of the toolkit uses, showing a byte
  count. The logger only ever writes a UTF-8 request body to disk, so a binary body — a protobuf,
  a multipart upload — is not recoverable from the capture and the replay goes out without one.
  The editor says so on the row, in the section's footer, and in a confirmation before sending,
  rather than quietly sending a request the developer did not ask for; typing a body of your own
  retires the warning.

#### What Happens on Send

A replay goes out on an ordinary `URLSession` and is captured by the interceptor exactly as
traffic the app makes is. That has two consequences worth stating plainly:

- **A replay is its own entry in the log**, marked with a teal `REPLAY` badge — the same treatment
  the pink `MOCKED` badge gets, in the one other colour nothing in the log competes for.
- **Enabled overrides apply to a replay**, because nothing about it is special-cased. Replay a
  request that a mock matches and you get the mock, with both badges on the row. The editor says
  so in a footer, so a developer comparing a replay against an original knows whether they are
  looking at the network or at their own override.

A request whose response an override synthesised has no **Replay this request** button: the
override would simply synthesise the same response again.

Because resending a `POST`, `PATCH` or `DELETE` can repeat whatever it changed, any method
outside `GET`, `HEAD` and `OPTIONS` warns in the editor and asks for confirmation in an alert
naming the method before anything is sent. So does a replay whose body could not be captured, and
one aimed at a URL Scyther does not intercept — an ignored host, or a scheme that is not HTTP —
which would be sent and never appear in the log. The editor's footer and the confirmation show the
same list of warnings, so they cannot tell you different things.

#### Comparing

The original's details page grows a **Replays** section listing every replay of it currently in
the log, each row naming the replay's method and status and carrying the signed duration and size
deltas — replay minus original — and linking to that replay's own page. A replay's page carries a
**Replayed from** row linking the other way, or says the original is no longer in the log if it
has since been cleared.

Both sections track the log as it changes, so a replay that lands seconds after the editor
dismissed appears without leaving the page.

A row whose exchange Scyther shaped says so, in the log's own badge words — `Original: MOCKED`,
`Replay: HELD OVERRIDDEN`. A mocked response never left the device and a held one waited for a
developer to press a button, so a delta across either measures Scyther rather than the server, and
the section that exists for comparison should not report it as though it did not.

### Breakpoints

**Networking → Breakpoints** is the feature people reach for Charles or Proxyman to get: a
matching request stops before it is sent, or a matching response stops before the app sees any of
it, and the editor appears over whatever is on screen so it can be read and changed in place.

It is the one thing in the toolkit that deliberately holds the app up, so the master switch
**defaults to off** and the menu row shows how many breakpoints are being applied.

#### Setting one

A breakpoint is matching plus a stage. Matching is the same `NetworkRuleMatch` a request override
uses — methods, host, path, query, with the same wildcard and percent-encoding semantics — so a
match copied from an override behaves identically here.

| Field | What it does |
| --- | --- |
| **Stage** | `Request` holds it on the way out, `Response` on the way back, `Both` holds twice. |
| **Timeout** | 5 to 300 seconds, 60 by default. It cannot be switched off. |

The editor refuses to save a breakpoint with no name, or one whose match names no endpoint — a
match that applies to everything would hold every request the app makes, one after another, for
the timeout each.

#### When one fires

The editor is presented over the key window, wherever the developer is in the app. One held
exchange opens straight into its own page; several are listed and can be worked through in any
order. Each page shows which breakpoint holds it, a live countdown to the automatic continue, and
the exchange itself: method, URL, headers and body for a request; status, headers and body for a
response.

There are four ways out, and doing nothing is one of them:

- the **confirm button** continues with whatever has been edited;
- **Continue Without Changes** passes the exchange on exactly as it arrived;
- **Abort** fails it with a `URLError` you pick, exactly as though the network had produced it;
- the **timeout** continues it unchanged, so a forgotten breakpoint cannot leave the app hanging.

A log entry that was held carries an indigo `HELD` badge, beside `MOCKED` and `REPLAY`, and the
log records what the app actually sent and received — the edit, not the original.

#### Breaking on a Captured Request

The request details page carries a **Break on requests like this** button, beside **Save as mock**
and **Replay this request**. It opens the breakpoint editor pre-filled from the capture: the same
matcher a mock built from that page uses — its method, host and path exactly, with the query left
unconstrained — holding the request stage, for the default minute.

Unlike a mock, it arrives **enabled**: a breakpoint announces itself by stopping the request and
putting a screen in front of you, so there is nothing to switch on afterwards and nothing hidden
if you forget to. Nothing is written until the editor is confirmed either way.

It is offered wherever the entry has a URL, including one an override answered — seeing what the
app *sent* to a stubbed endpoint is one of the things a breakpoint is for.

#### What it does not do

- **Nothing blocks.** A held request does not occupy the thread it was intercepted on. The pause
  is a stored continuation, so a breakpoint left open costs a suspended request and nothing else,
  and cancelling the request cancels the pause.
- **A held response buffers.** Bytes cannot be un-forwarded, so a response breakpoint withholds
  the whole body and hands it over once. Above 10 MB the pause is skipped and logged. The editor
  says so when the stage is chosen.
- **It never fires during tests.** Breakpoints report as off inside an XCTest process, so one left
  enabled cannot hang CI, and they are off on App Store builds along with the rest of Scyther.
- **A stubbed request is not held.** An override answers it without anything going in flight.
- **A pause taken while the app is not active is skipped** and logged: a held request the
  developer cannot see is indistinguishable from a hang. Only that one pause is skipped — an
  exchange already open in the editor survives a glance at Control Centre or the app switcher.
  Anything still held when the app actually goes to the background is continued unchanged there
  and then, rather than waiting out its timeout somewhere nobody can see it.

### Network Conditioning

**Networking → Network Conditioning** degrades **every** request Scyther intercepts, which is what
Network Link Conditioner does without needing a Mac or a provisioning profile. The menu row shows
the active preset, or `Off`, so conditioning is never quietly on.

The screen carries a master switch, a preset picker, and the three numbers underneath it:

| Preset | Latency | Ceiling | Failures |
| --- | --- | --- | --- |
| **Wi-Fi** | 0.01 s | none | none |
| **4G** | 0.05 s | 1,500 KB/s | none |
| **3G** | 0.1 s | 100 KB/s | none |
| **EDGE** | 0.4 s | 30 KB/s | none |
| **Very bad network** | 0.5 s | 125 KB/s | 10% |

Picking a preset fills the three fields in; editing any of them makes the picker read **Custom**
again, because that is what it now is. Custom is not something you pick — it is the *absence* of a
preset — so the picker lists it only while it is what the numbers say, rather than offering a
choice that would change nothing and then snap back.

A request the global condition slowed or failed carries the brown `OVERRIDDEN` badge in the log,
credited as **Network Conditioning** in the details page's **Overrides** row. It names it without
offering a link, because it is a screen rather than an override — but the log never shows a
conditioned request as ordinary traffic.

The global condition is a **floor**, not an addition. A request override whose own condition
matches replaces it outright, so one endpoint can still be conditioned differently — or barely at
all — while the rest of the app is on EDGE. An override that matches but carries no condition
leaves the global one in place.

It is off by default, persisted across launches, and has its own switch: **Enable Request
Overrides** does not reach it, and neither does turning every override off.

---

### Console Logging

Capture all `print()` statements and console output.

#### Accessing Logs

```swift
// Get all captured logs
let logs = Scyther.console.logs

for entry in logs {
    print("[\(entry.source.rawValue)] \(entry.formattedTimestamp): \(entry.message)")
}
```

#### Managing Console Capture

```swift
// Stop capturing (if needed)
Scyther.console.stopCapturing()

// Clear all logs
Scyther.console.clear()
```

---

### Crash Logging

Capture uncaught exceptions and view them on subsequent app launches. This is useful for debugging crashes that occur during development and testing.

#### How It Works

Scyther uses `NSSetUncaughtExceptionHandler` to intercept Objective-C and Swift exceptions before the app terminates. When a crash occurs:

1. Exception details are captured (name, reason, stack trace)
2. Device and app information is recorded
3. Data is saved to UserDefaults immediately
4. On next launch, the crash is visible in Scyther's Crash Logs viewer

#### ⚠️ Important: Initialization Order

**If you use other crash reporting tools** (Firebase Crashlytics, Sentry, Bugsnag, Instabug, etc.), the order you initialize them matters.

Crash reporters work by setting an exception handler. Only one handler can be active at a time, but handlers can "chain" by saving and forwarding to the previous handler.

**Scyther must be started AFTER other crash reporters:**

```swift
import Firebase
import Sentry
import Scyther

@main
struct MyApp: App {
    init() {
        // 1. Initialize other crash reporters FIRST
        FirebaseApp.configure()
        SentrySDK.start { options in
            options.dsn = "your-dsn"
        }

        // 2. Start Scyther LAST
        // Scyther will capture crashes AND forward them to the previous handlers
        Scyther.start()
    }
}
```

**Why this order?**
- Scyther saves the existing handler (e.g., Crashlytics) when it starts
- When a crash occurs, Scyther logs it locally, then forwards to Crashlytics
- Both systems receive the crash data

**If you start Scyther first**, your other crash reporter will overwrite Scyther's handler, and Scyther won't capture crashes.

#### Accessing Crash Logs

```swift
// Get all captured crashes (newest first)
let crashes = Scyther.crashes.all

// Get crash count
let count = Scyther.crashes.count

// Clear all crash logs
Scyther.crashes.clear()
```

#### Crash Log Details

Each crash log includes:
- Exception name and reason
- Full stack trace (searchable with highlighting)
- App version and build number
- iOS version and device model
- Timestamp

The stack trace is searchable - use the search bar to filter frames and find specific methods, classes, or frameworks. Matching text is highlighted for easy identification.

#### Testing Crash Capture

In debug builds, you can trigger a test crash:

```swift
#if DEBUG
Scyther.crashes.triggerTestCrash()
#endif
```

#### Limitations

- **Swift errors**: Only captures `NSException`-based crashes. Pure Swift `fatalError()` or `preconditionFailure()` may not be captured.
- **Symbolication**: Stack traces contain memory addresses. Use Xcode's crash log tools for symbolicated traces.
- **Storage**: Up to 50 crashes are stored (oldest are removed automatically).

---

### File Browser

Browse the app sandbox from **System Tools → File Browser**: the `Documents`, `Library`,
`Caches` and `tmp` roots, any subdirectory, and a detail screen per file with its attributes,
a text, JSON, property list or image preview, Quick Look, Share, Copy Path and Delete.

---

### Database Browser

Browse SQLite, CoreData, and SwiftData databases with full CRUD support. The Database Browser automatically discovers databases in your app's container and provides a visual interface for inspecting and modifying data.

#### Automatic Discovery

Databases are automatically discovered in common locations:
- `Library/Application Support/` (SwiftData, CoreData stores)
- `Documents/` (user-created databases)
- `Library/` (other app data)

The browser detects database types:
- **SQLite**: Plain `.sqlite`, `.sqlite3`, `.db` files
- **CoreData**: Detected via `Z_`-prefixed system tables
- **SwiftData**: Detected via Swift-specific metadata

#### Features

- **Schema Browser**: View tables, columns, types, primary keys, foreign keys, and indexes
- **Record Browser**: Paginated viewing of table records with sorting
- **CRUD Operations**: Add, edit, and delete records (for writable databases)
- **SQL Query Editor**: Execute raw SQL queries with formatted results
- **Swipe-to-Delete**: Quick record deletion with confirmation

#### Custom Database Adapters

For third-party databases like Realm or Firebase, you can create custom adapters without adding dependencies to Scyther:

```swift
// In your app, create an adapter conforming to DatabaseBrowserAdapter
class RealmDatabaseAdapter: DatabaseBrowserAdapter {
    var identifier: String { "my-realm-db" }
    var displayName: String { "My Realm Database" }
    var databaseType: DatabaseType { .custom("Realm") }
    var supportsRawSQL: Bool { false }
    var supportsWrite: Bool { true }
    var filePath: String? { realm.configuration.fileURL?.path }

    func tables() async throws -> [TableInfo] {
        // Return your Realm object schema as TableInfo
    }

    func schema(for table: String) async throws -> TableSchema {
        // Return column info for the specified table
    }

    func records(in table: String, offset: Int, limit: Int, orderBy: String?, ascending: Bool) async throws -> [DatabaseRecord] {
        // Query and return records
    }

    // Implement other protocol methods...
}

// Register the adapter with Scyther
Scyther.database.registerAdapter(RealmDatabaseAdapter(realm: myRealm))
```

#### Protocol Requirements

The `DatabaseBrowserAdapter` protocol requires:

| Method | Description |
|--------|-------------|
| `tables()` | Return all tables/collections |
| `schema(for:)` | Return schema for a table |
| `records(in:offset:limit:orderBy:ascending:)` | Fetch paginated records |
| `insert(into:values:)` | Insert a new record |
| `update(in:primaryKey:values:)` | Update an existing record |
| `delete(from:primaryKey:)` | Delete a record |
| `executeQuery(_:)` | Execute raw SQL (if supported) |

---

### Data Browsers

Three screens inspect the values your app has already stored: **Data → UserDefaults**,
**Security → Keychain Browser** and **Data → Cookies**.

---

### Location Spoofing

Fake GPS coordinates for testing location-based features.

#### Enabling Location Spoofing

```swift
// Enable spoofing
Scyther.location.spoofingEnabled = true

// Set a preset location
Scyther.location.spoofedLocation = Location(
    id: "sydney",
    name: "Sydney, Australia",
    latitude: -33.8688,
    longitude: 151.2093
)
```

#### Using Preset Locations

Scyther includes 20+ preset locations:

```swift
// Available presets
LocationSpoofer.instance.spoofedLocation = .sydney
LocationSpoofer.instance.spoofedLocation = .tokyo
LocationSpoofer.instance.spoofedLocation = .newYork
LocationSpoofer.instance.spoofedLocation = .oslo
LocationSpoofer.instance.spoofedLocation = .berlin
// ... and many more
```

#### Custom Locations

```swift
// Set custom coordinates
let customLocation = Location(
    id: "office",
    name: "Company HQ",
    latitude: 37.7749,
    longitude: -122.4194
)
Scyther.location.spoofedLocation = customLocation
```

#### Adding Developer Locations

```swift
// Add locations that appear in the Scyther UI
LocationSpoofer.instance.addLocation(Location(
    id: "test-store",
    name: "Test Store Location",
    latitude: 40.7128,
    longitude: -74.0060
))
```

#### Route Simulation

Simulate movement along a route:

```swift
LocationSpoofer.instance.spoofedRoute = .driveCityToSuburb
```

---

### Deep Link Testing

Test custom URL schemes and universal links directly from the Scyther menu.

#### Opening Deep Links

```swift
// Open a deep link programmatically
await Scyther.deepLinks.open("myapp://profile/123")
```

#### Configuring Presets

Add commonly-used deep links for quick access:

```swift
Scyther.deepLinks.presets = [
    DeepLinkPreset(name: "Home", url: "myapp://home"),
    DeepLinkPreset(name: "Profile", url: "myapp://profile/123"),
    DeepLinkPreset(name: "Settings", url: "myapp://settings"),
    DeepLinkPreset(name: "Checkout", url: "myapp://checkout"),
]
```

The Deep Link Tester also includes:
- **QR Code Scanner**: Scan QR codes containing deep links
- **History**: Previously tested links are saved for quick re-use
- **Success/Failure Feedback**: Visual indication of whether the link opened

> **Note**: To use the QR code scanner, your app must include `NSCameraUsageDescription` in its Info.plist with a description explaining camera usage (e.g., "Used to scan QR codes for deep link testing").

---

### Push Notification Testing

Schedule local test notifications to verify your notification handling.

#### Scheduling Test Notifications

```swift
// Simple test notification. Omit title and body to use Scyther's own localised copy.
Scyther.notifications.scheduleTest(
    title: "Order Update",
    body: "Your order #12345 has shipped!",
    delay: 5  // seconds
)

// With all options
Scyther.notifications.scheduleTest(
    title: "New Message",
    body: "You have a new message from John",
    delay: 10,
    sound: true,
    incrementBadge: true
)
```

#### Viewing Logged Notifications

```swift
for notification in Scyther.notifications.logged {
    print("Title: \(notification.aps.alert.title)")
    print("Body: \(notification.aps.alert.body)")
}
```

#### Setting Device Tokens

Display tokens in the Scyther UI:

```swift
// In your AppDelegate
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    Scyther.apnsToken = token
}

// For Firebase
Messaging.messaging().token { token, error in
    if let token = token {
        Scyther.fcmToken = token
    }
}
```

---

### UI Debugging Tools

#### Grid Overlay

Display an alignment grid over your UI:

```swift
// Enable grid overlay
Scyther.interface.gridOverlayEnabled = true

// Customize grid appearance (via GridOverlay singleton)
GridOverlay.instance.size = 8        // Grid size in points
GridOverlay.instance.opacity = 0.5   // Grid opacity (0.0 - 1.0)
GridOverlay.instance.colorScheme = .blue
```

#### FPS Counter

Display a real-time frame rate indicator to monitor rendering performance:

```swift
// Enable FPS counter
FPSCounter.instance.enabled = true

// Change position (topLeft, topRight, bottomLeft, bottomRight)
FPSCounter.instance.position = .bottomRight
```

The counter is color-coded for quick performance assessment:
- **Green** (55+ FPS): Excellent performance
- **Yellow** (30-54 FPS): Acceptable, may need optimization
- **Red** (<30 FPS): Poor performance, needs investigation

#### Touch Visualizer

Show visual indicators for touch events (great for screen recordings):

```swift
// Enable touch visualization
Scyther.interface.touchVisualizerEnabled = true

// Customize appearance
var config = TouchVisualiserConfiguration()
config.showsTouchDuration = true
config.touchIndicatorColor = .systemBlue
TouchVisualiser.instance.config = config
```

#### Debug View Frames and Sizes

These are available as toggles in the Scyther menu under **UI/UX**:

- **Slow Animations**: Reduces animation speed to 10%
- **Show View Frames**: Adds colored borders to all views
- **Show View Sizes**: Displays width/height labels on views

#### Appearance Overrides

Test how your app looks under different appearance settings without changing device settings:

```swift
// Force dark mode
Scyther.appearance.colorScheme = .dark

// Force light mode
Scyther.appearance.colorScheme = .light

// Follow system (default)
Scyther.appearance.colorScheme = .system
```

**High Contrast Mode** (iOS 17+):

```swift
// Enable high contrast
Scyther.appearance.highContrastEnabled = true
```

**Dynamic Type Override** (iOS 17+):

Test all 12 content size categories, including 5 accessibility sizes:

```swift
// Test with extra large text
Scyther.appearance.contentSizeCategory = .extraExtraExtraLarge

// Test with accessibility sizes
Scyther.appearance.contentSizeCategory = .accessibilityExtraLarge

// Reset to system default
Scyther.appearance.contentSizeCategory = nil
```

All appearance settings are persisted across app launches and can be configured via the Scyther menu under **UI/UX > Appearance**.

---

### Custom Developer Options

Add your own debug options to the Scyther menu.

#### Value-Based Options

Display static information:

```swift
Scyther.developerOptions = [
    DeveloperOption(
        name: "User ID",
        value: UserManager.shared.currentUserId ?? "Not logged in",
        icon: UIImage(systemName: "person.circle")
    ),
    DeveloperOption(
        name: "Session Token",
        value: String(AuthManager.shared.token?.prefix(20) ?? "None") + "...",
        icon: UIImage(systemName: "key")
    ),
    DeveloperOption(
        name: "Cache Size",
        value: CacheManager.shared.formattedSize,
        icon: UIImage(systemName: "internaldrive")
    )
]
```

#### View Controller Options

Navigate to custom debug screens:

```swift
Scyther.developerOptions.append(
    DeveloperOption(
        name: "Debug Settings",
        icon: UIImage(systemName: "gear"),
        viewController: DebugSettingsViewController()
    )
)

Scyther.developerOptions.append(
    DeveloperOption(
        name: "Analytics Events",
        icon: UIImage(systemName: "chart.bar"),
        viewController: AnalyticsDebugViewController()
    )
)
```

---

### Environment Variables

Display custom environment variables in the Scyther menu.

```swift
Scyther.environmentVariables = [
    "API_VERSION": "v2",
    "FEATURE_SET": "premium",
    "AB_TEST_GROUP": "B",
    "BUILD_CONFIGURATION": "Debug",
    "ANALYTICS_ENABLED": "true"
]
```

These are displayed under **Networking > Environment Variables** in the menu.

---

## Menu Invocation

### Shake Gesture (Default)

By default, shaking the device opens the Scyther menu.

```swift
// This is the default
Scyther.invocationGesture = .shake
```

### Custom Gesture

For custom trigger mechanisms:

```swift
Scyther.invocationGesture = .custom

// Then trigger manually from your own gesture handler
func handleSecretGesture() {
    Scyther.showMenu()
}
```

### Programmatic Control

```swift
// Show the menu
Scyther.showMenu()

// Show from a specific view controller
Scyther.showMenu(from: self)

// Hide the menu
Scyther.hideMenu()

// Check menu state
if Scyther.isPresented {
    Scyther.hideMenu()
}
```

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

### Menu language

Scyther's menu follows your app. If your app is localised into any of the twelve languages
Scyther ships, the menu appears in whichever one the user is running; otherwise it follows
the device language and falls back to English. There is nothing to configure and no setup
step — adding a localisation to your app is enough.

Rows you register through `Scyther.developerOptions` display the name you pass in, unchanged,
so localise that string yourself if you want it translated alongside the rest.

To read the menu in a language your app does not ship, or to check how your own screens look
in one, use **UI/UX → Language**. See [Localisation](#localisation).

---

## API Reference

### Scyther (Main Entry Point)

| Property/Method | Type | Description |
|----------------|------|-------------|
| `start(allowProductionBuilds:)` | `@MainActor static func` | Initializes Scyther |
| `showMenu(from:)` | `static func` | Presents the debug menu |
| `hideMenu(animated:completion:)` | `static func` | Dismisses the debug menu |
| `isStarted` | `Bool` | Whether Scyther has been started |
| `isPresented` | `Bool` | Whether the menu is currently showing |
| `delegate` | `ScytherDelegate?` | Delegate for receiving events |
| `invocationGesture` | `ScytherGesture` | Gesture to open menu (`.shake` or `.custom`) |
| `developerOptions` | `[DeveloperOption]` | Custom menu options |
| `environmentVariables` | `[String: String]` | Custom environment variables |
| `apnsToken` | `String?` | APNS device token |
| `fcmToken` | `String?` | FCM device token |

### Subsystems

| Subsystem | Access | Description |
|-----------|--------|-------------|
| `Scyther.featureFlags` | `FeatureFlags` | Feature flag management |
| `Scyther.servers` | `Servers` | Server configuration |
| `Scyther.network` | `Network` | Network logging |
| `Scyther.network.rules` | `NetworkRules` | Request overrides — mocks, map local, header rewrites and per-endpoint conditioning, composed on one override |
| `Scyther.console` | `Console` | Console output capture |
| `Scyther.crashes` | `Crashes` | Crash logging and viewing |
| `Scyther.database` | `DatabaseBrowsing` | Database browser and adapter registration |
| `Scyther.interface` | `Interface` | UI debugging tools |
| `Scyther.location` | `LocationSpoofing` | Location spoofing |
| `Scyther.notifications` | `Notifications` | Push notification testing |
| `Scyther.appearance` | `Appearance` | Appearance overrides (dark/light mode, Dynamic Type) |
| `Scyther.deepLinks` | `DeepLinks` | Deep link testing with QR scanner |
| `Scyther.localization` | `LanguageOverride` | App language override |

---

## Architecture for Contributors

### Source Organization

Scyther follows a clean architecture pattern with three main directories:

```
Sources/Scyther/
├── Core/               # Main entry point, InterfaceToolkit, AppEnvironment
├── Features/           # 18+ feature modules (NetworkLogger, FeatureFlags, etc.)
└── Shared/            # Reusable components, extensions, models
    ├── Components/    # SwiftUI components
    ├── Extensions/    # Swift/UIKit extensions
    ├── Models/        # Data models
    ├── SwiftUI/       # SwiftUI utilities (ViewModel, etc.)
    └── ViewModifiers/ # Custom view modifiers
```

Each feature follows a consistent pattern:

```
FeatureName/
├── FeatureName.swift      # Core logic, singleton
├── FeatureNameView.swift  # SwiftUI UI
├── FeatureNameViewModel.swift  # View model (if needed)
└── Supporting files...
```

### ViewModel Pattern

Scyther uses a base `ViewModel` class located at `Sources/Scyther/Shared/SwiftUI/ViewModel.swift` that provides structured lifecycle management for SwiftUI views.

#### Lifecycle Methods

The `ViewModel` class provides four lifecycle hooks:

1. `setup()` - Called during `init()`, for synchronous setup
2. `onFirstAppear()` - Called once on first view appearance
3. `onAppear()` - Called every time the view appears
4. `onSubsequentAppear()` - Called on appearances after the first

#### Usage

Subclass `ViewModel` for any feature that needs lifecycle management:

```swift
class MyFeatureViewModel: ViewModel {
    @Published var data: [Item] = []
    @Published var isLoading = false

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadInitialData()
    }

    override func onSubsequentAppear() async {
        await super.onSubsequentAppear()
        await refreshData()
    }

    private func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        // Load data...
    }
}
```

Use with the `onFirstAppear` view modifier:

```swift
struct MyFeatureView: View {
    @StateObject private var viewModel = MyFeatureViewModel()

    var body: some View {
        List(viewModel.data) { item in
            Text(item.name)
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}
```

The base `ViewModel` class is marked `@MainActor` to ensure all lifecycle methods and published properties execute on the main thread.

### Singleton Pattern

Every feature uses a shared singleton instance:

```swift
static let instance = FeatureName()  // or .shared
private init() { }
```

This ensures a single source of truth and simplifies access patterns.

---

## FAQ

### Why is Scyther free?

Open-source is what makes the world go round. I built Scyther to give back to the community that helped me grow as a developer.

### Will Scyther get my app rejected?

No. Scyther uses no private APIs and has been shipping in production apps for years without App Store issues. By default, it's automatically disabled on App Store builds.

### Can I run Scyther in production?

We recommend against it, but you can enable it:

```swift
Scyther.start(allowProductionBuilds: true)
```

**Warning**: This could expose sensitive debugging information to end users.

### What's the origin of the name?

Named after the [Pokemon Scyther](https://pokemondb.net/pokedex/scyther), a bug-type known for its cutting ability - just like this library cuts through bugs!

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the build and test commands, the architecture and
testing conventions a change is expected to follow, and how to add or correct a localised
string.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make the change, with tests and documentation
4. Run the test suite and build the example app
5. Open a Pull Request

### Reporting Issues

- Use GitHub Issues for bug reports
- Include device model, iOS version, and Scyther version
- Provide minimal reproduction steps

---

## Security

If you discover a security vulnerability, please email b.stillitano95@gmail.com directly. Do not open a public issue.

---

## License

Scyther is released under the MIT license. See [LICENSE](LICENSE) for details.

---

## Credits

Scyther is maintained by [Brandon Stillitano](https://github.com/bstillitano).

- Website: [scyther.io](https://scyther.io)
- Contact: [scyther.io/contact.html](https://scyther.io/contact.html)
