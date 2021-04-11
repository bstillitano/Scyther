<p align="center">
  <img width="200" height="200" src="https://cdn.bulbagarden.net/upload/thumb/b/ba/123Scyther.png/600px-123Scyther.png">
</p>

# Scyther

<p align="left">
  <img src="https://img.shields.io/badge/platform-iOS-blue"> <img src="https://img.shields.io/badge/spm-main-green"> <img src="https://img.shields.io/github/license/bstillitano/Scyther">
</p>

Just like scyther, this menu helps you cut through bugs, in your iOS app. Scyther is a fully fledged debug menu that provides tools for developers, UAT (QA) members/testers, UI/UX teams, backend developers and even frontend developers who use your app. Made with 💙 in Sydney, Australia 🇦🇺.

- [Quick Start](#quick-start)
- [Demo](#demo)
- [Features](#features)
- [Requirements](#requirements)
- [Communication](#communication)
- [Installation](#installation)
- [Documentation](#documentation) - Coming Soon
- [FAQ](#faq)
- [Credits](#credits)
- [License](#license)

## Quick Start

I recommend only running Scyther on non release/App Store builds of your iOS application. Running the library on public facing versions of your app has the potential to introduce security issues if you store/transmit secure data over a network. To achieve this, for developers of all skill levels, I have included a convenience which abstracts that logic into a single line. See below:

``` swift
import Scyther

// AppDelegate.swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        /// Run Scyther only on non AppStore builds to avoid introducing potential security issues into our app.
        if !AppEnvironment.isAppStore {
            Scyther.instance.start()
        }

        return true
    }
```

Once you have added the above code to your `AppDelegate.swift` file, simply run your app on a simulator or physical device. Once it's running, simply shake your device (`Cmd + Option + Z`) on the simulator) and you'll be presented with the Scyther debug menu for your app.

## Demo

There is a full-featured demo included in this repo. See the [Scyther Playground](https://github.com/bstillitano/Scyther/tree/improvement/readme/Scyther%20Playground) project. Note that some of the features included in the demo may not be required for your implementation. They've been included only as a reference for what Scyther is capable of and how to implement said features.

## Features

#### Application

- [x] Display Bundle Identifier
- [x] Display App Version
- [x] Display Build Number
- [x] Display Process ID
- [x] Display Release Type (Debug/TestFlight/Release)
- [x] Display Build Date

#### Networking

- [x] Display Public IP Address
- [x] Network Logging
- [x] Server/Environment Configuration

#### Data

- [x] Feature Flagging
- [x] Manage User Defaults
- [x] Manage Cookies (HTTPCookieStorage)
- [ ] Clear App Data (Coming Soon)
- [ ] Manage App Files (Coming Soon)
- [ ] Manage CoreData (Coming Soon)

#### Security

- [ ] Manage Keychain Items (Coming Soon)

#### System

- [ ] Console Logs (Coming Soon)
- [ ] Performance Logs (Coming Soon)
- [ ] Crash Logs (Coming Soon)
- [ ] Location Spoofing (Coming Soon)

#### Support

- [ ] App Feedback (Coming Soon)

#### UI/UX

- [x] Push Notification Tester
- [x] View Available Fonts
- [x] Interface Component Catalog
- [x] Grid Overlay
- [x] Show View Frames
- [x] Slow Animations
- [ ] Show Screen Touches (Coming Soon)

#### Development Tools

- [x] Insert Your Own, App Specific, Tools

### Requirements

- iOS 11.0+
- Xcode 11+
- Swift 5.1+

### Communication

- If you need **help with a Scyther feature**, open an issue here on GitHub and follow the guide. The more detail the better!
- If you'd like to **discuss Scyther best practices**, open an issue here on GitHub and follow the guide. The more detail the better!
- If you'd like to **discuss a feature request**, open an issue here on GitHub and follow the guide. The more detail the better!
- If you **found a bug**, open an issue here on GitHub and follow the guide. The more detail the better!
- If you **want to contribute**, submit a pull request!

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies. 

Once you have your Swift package set up, adding Scyther as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/bstillitano/Scyther.git", branch: "main")
]
```

## FAQ

### Why is Scyther free?

If you want to be blunt, `resumé`. But, to be a little more philosophical, I myself once relied on open-source libraries to build apps. Call it "giving back" if you will. Open-source is what makes the world go round (literally). Scyther is however licensed under the MIT license which comes with some important stipulations about protecting intellectual property/copyrights. [See LICENSE](https://github.com/bstillitano/Scyther/blob/master/LICENSE) for details.

### Will Scyther get my app rejected by the App Store?

Scyther uses no private APIs and has been developed with shipability in mind. Scyhter is being, and has been for some time, on production applications without issues from the App Store© review team. If your app does get rejected ***specifically*** for using Scyther, raise an issue, and it will be looked into with top priority.

### What's the origin of the name Scyther?

Scyther is named after the [Pokemon Scyther](https://pokemondb.net/pokedex/scyther), a bug type Pokémon that is known for its cutting ability. One of my [all-time favourite co-workers](https://github.com/danielmoi) loved Pokémon and recommended Scyther. In short, there is no good reason for the name.

### Why does Scyther exist?

Working on some very widely used and distributed codebases, I noticed just how powerful some of the tooling, that the teams developing these apps had developed internally, was. This coupled with experience at startups and some time on small projects, I noticed a huge gap when it came to readily-available tools/libraries for small teams and junior developers that help answer the constant questions that mobile developers get asked. This library is all about enabling testers/users to help themselves before reaching out to developers.

## Credits

Scyther is owned and maintained by [Brandon Stillitano](http://github.com/bstillitano). You can follow me on Twitter at [@bstillita](https://twitter.com/bstillita) for project updates and releases.

## Security Disclosure

If you believe you have identified a security vulnerability with Scyther, you should report it as soon as possible via email to b.stillitano95@gmail.com. Please do not post it to a public issue tracker.

## License

Scyther is released under the MIT license. [See LICENSE](https://github.com/bstillitano/Scyther/blob/master/LICENSE) for details.