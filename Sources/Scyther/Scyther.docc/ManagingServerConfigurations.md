# Managing Server Configurations

Switch between backend environments without recompiling your app.

@Metadata {
    @PageColor(green)
}

## Overview

During development, you often need to switch between different backend environments (development, staging, production). Scyther's server configuration system makes this seamless.

> Note: The ``Servers`` subsystem is an `actor`, requiring `await` for all access to ensure thread safety.

## Registering Servers

Define your server environments with their associated variables:

```swift
await Scyther.servers.register(id: "development", variables: [
    "API_URL": "https://dev-api.example.com",
    "WEBSOCKET_URL": "wss://dev-ws.example.com",
    "DEBUG_MODE": "true",
    "LOG_LEVEL": "verbose"
])

await Scyther.servers.register(id: "staging", variables: [
    "API_URL": "https://staging-api.example.com",
    "WEBSOCKET_URL": "wss://staging-ws.example.com",
    "DEBUG_MODE": "true",
    "LOG_LEVEL": "info"
])

await Scyther.servers.register(id: "production", variables: [
    "API_URL": "https://api.example.com",
    "WEBSOCKET_URL": "wss://ws.example.com",
    "DEBUG_MODE": "false",
    "LOG_LEVEL": "error"
])
```

## Accessing Configuration

Get the current server and its variables:

```swift
// Get current server ID
let currentServer = await Scyther.servers.currentId

// Get a specific variable
let apiURL = await Scyther.servers.variables["API_URL"]

// Get all variables for current server
let allVars = await Scyther.servers.variables
```

## Using Variables in Your App

Create a configuration manager that reads from Scyther:

```swift
actor APIConfiguration {
    static let shared = APIConfiguration()

    var baseURL: URL {
        get async {
            let urlString = await Scyther.servers.variables["API_URL"]
                ?? "https://api.example.com"
            return URL(string: urlString)!
        }
    }

    var isDebugMode: Bool {
        get async {
            let value = await Scyther.servers.variables["DEBUG_MODE"]
            return value == "true"
        }
    }
}
```

## Responding to Server Changes

Implement ``ScytherDelegate`` to handle server switches:

```swift
class AppCoordinator: ScytherDelegate {
    init() {
        Scyther.delegate = self
    }

    func scytherDidSwitchServer(to serverId: String) {
        Task {
            // Reconfigure networking
            await APIClient.shared.reconfigure()

            // Clear cached data
            CacheManager.shared.clearAll()

            // Re-authenticate if needed
            await AuthManager.shared.refreshToken()

            // Notify the app
            NotificationCenter.default.post(
                name: .serverConfigurationChanged,
                object: serverId
            )
        }
    }
}
```

## Programmatic Server Switching

Switch servers programmatically if needed:

```swift
// Switch to a specific server
await Scyther.servers.setCurrent(id: "staging")

// Check available servers
let servers = await Scyther.servers.all
for server in servers {
    print("Server: \(server.id)")
}
```

## Environment Variables Display

You can also display custom environment variables in the Scyther menu:

```swift
Scyther.environmentVariables = [
    "API_VERSION": "v2",
    "FEATURE_SET": "premium",
    "AB_TEST_GROUP": "B",
    "BUILD_CONFIG": ProcessInfo.processInfo.environment["BUILD_CONFIG"] ?? "Debug"
]
```

These appear under **Networking > Environment Variables** in the menu.

## Best Practices

### 1. Register All Environments

Even if you typically only use one environment, register all of them to make switching easy for QA testing.

### 2. Use Consistent Variable Names

```swift
// All servers should have the same keys
let requiredKeys = ["API_URL", "WEBSOCKET_URL", "DEBUG_MODE"]
```

### 3. Handle Missing Variables Gracefully

```swift
let apiURL = await Scyther.servers.variables["API_URL"]
    ?? "https://api.example.com" // Fallback
```

### 4. Persist Selection

Scyther automatically persists the selected server across app launches.

## See Also

- ``Servers``
- ``ServerConfiguration``
- ``ScytherDelegate``

