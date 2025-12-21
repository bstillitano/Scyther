# Getting Started with Scyther

Add powerful debugging tools to your iOS app in minutes.

## Overview

Scyther is a debugging toolkit that provides runtime inspection and configuration tools. Once integrated, shake your device to access a comprehensive debug menu.

## Installation

Add Scyther to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/bstillitano/Scyther.git", branch: "main")
]
```

## Basic Setup

### SwiftUI

```swift
import SwiftUI
import Scyther

@main
struct MyApp: App {
    init() {
        Scyther.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### UIKit

```swift
import UIKit
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

## Opening the Debug Menu

Once started, **shake your device** (or press `Cmd + Ctrl + Z` in the simulator) to open the Scyther debug menu.

You can also open it programmatically:

```swift
Scyther.showMenu()
```

## Next Steps

- Configure ``FeatureFlags`` for runtime feature toggling
- Set up ``Servers`` for environment switching
- Use ``NetworkLogger`` to inspect network requests
- Enable ``LocationSpoofer`` for location-based testing
