<p align="center">
  <img width="200" height="200" src="https://github.com/bstillitano/Scyther/raw/main/Scyther.png">
</p>

# Scyther

[![bitrise-build-badge](https://app.bitrise.io/app/ea64d6f99435533d/status.svg?token=a5U0AgWUxliydR5tNHrPyw&branch=main)](https://app.bitrise.io/app/ea64d6f99435533d)
[![documentation-badge](https://raw.githubusercontent.com/bstillitano/Scyther/main/docs/badge.svg)](https://scyther.io) ![platform-badge](https://img.shields.io/badge/platform-iOS-blue) ![license-badge](https://img.shields.io/github/license/bstillitano/Scyther) ![spm-badge](https://img.shields.io/badge/spm-main-black)

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

### System Tools
- **Location Spoofing**: Fake GPS coordinates for testing location-based features
- **Preset Locations**: 20+ major cities worldwide
- **Custom Locations**: Set any coordinate manually
- **Route Simulation**: Simulate movement along predefined routes

### Notifications
- **Push Notification Tester**: Schedule local test notifications
- **Notification Logger**: View received notification payloads
- **Token Display**: View APNS and FCM device tokens

### UI/UX Tools
- **Grid Overlay**: Display alignment grid over your UI
- **Touch Visualizer**: Show touch points for demos and recordings
- **View Frames**: Highlight view boundaries with colored borders
- **View Sizes**: Display view dimensions as labels
- **Slow Animations**: Reduce animation speed for debugging
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
| `Scyther.interface` | `Interface` | UI debugging tools |
| `Scyther.location` | `LocationSpoofing` | Location spoofing |
| `Scyther.notifications` | `Notifications` | Push notification testing |

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

Follow [@bstillita](https://twitter.com/bstillita) on Twitter for updates.
