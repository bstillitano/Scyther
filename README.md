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
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Usage Guide](#detailed-usage-guide)
  - [Feature Flags](#feature-flags)
  - [Server Configuration](#server-configuration)
  - [Network Logging](#network-logging)
  - [Console Logging](#console-logging)
  - [Crash Logging](#crash-logging)
  - [Database Browser](#database-browser)
  - [Location Spoofing](#location-spoofing)
  - [Push Notification Testing](#push-notification-testing)
  - [UI Debugging Tools](#ui-debugging-tools)
  - [Custom Developer Options](#custom-developer-options)
  - [Environment Variables](#environment-variables)
- [Menu Invocation](#menu-invocation)
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
- Request/response body (formatted for JSON)
- Status code and timing
- cURL command for reproduction

#### Log Retention

Network logs are automatically cleaned up to prevent disk bloat:

- **7-day retention**: Log files older than 7 days are automatically deleted on app startup
- **Manual cleanup**: Clearing logs via the UI also deletes all associated files from disk
- **Files managed**: `SessionLog.log`, request body files, and response body files

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
LocationSpoofer.instance.spoofedLocation = .london
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
// Simple test notification
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
| `Scyther.console` | `Console` | Console output capture |
| `Scyther.crashes` | `Crashes` | Crash logging and viewing |
| `Scyther.database` | `DatabaseBrowsing` | Database browser and adapter registration |
| `Scyther.interface` | `Interface` | UI debugging tools |
| `Scyther.location` | `LocationSpoofing` | Location spoofing |
| `Scyther.notifications` | `Notifications` | Push notification testing |
| `Scyther.appearance` | `Appearance` | Appearance overrides (dark/light mode, Dynamic Type) |
| `Scyther.deepLinks` | `DeepLinks` | Deep link testing with QR scanner |

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

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
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
