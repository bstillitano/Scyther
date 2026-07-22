//
//  MenuItem.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// A single row in the Scyther main menu.
///
/// Giving every row a stable identity is what makes pinning possible: an identifier can be
/// persisted, and the same case can be rendered both in its home section and in the "Pinned"
/// section without duplicating its definition.
///
/// ## Features
///
/// - Stable, persistable ``id`` for every row
/// - Lossless round-tripping via ``init(id:)``, returning `nil` for rows that no longer exist
/// - Single source of truth for each row's ``title`` and ``icon``
/// - Support for host-supplied rows via ``developerOption(name:)``
///
/// ## Usage
///
/// ```swift
/// let item = MenuItem.featureFlags
/// item.id       // "featureFlags"
/// item.title    // "Feature Flags"
/// item.icon     // "flag"
///
/// MenuItem(id: "featureFlags")   // .featureFlags
/// MenuItem(id: "removedInV2")    // nil
/// ```
///
/// ## Implementation Details
///
/// Dynamic values — a value row's description, a navigation row's destination, a toggle
/// row's binding — deliberately live in ``MenuView`` rather than here. This type owns only
/// what is stable across renders.
///
/// The device header shown at the top of the menu is not a `MenuItem`; it is a plain header
/// view and is not pinnable.
///
/// ## Topics
///
/// ### Identity
/// - ``id``
/// - ``init(id:)``
/// - ``pinnedRowID``
/// - ``allStaticCases``
///
/// ### Presentation
/// - ``title``
/// - ``icon``
enum MenuItem: Hashable, Identifiable {
    // Device
    case osVersion, hardware, releaseYear, uuid

    // Application
    case appIdPrefix, displayName, bundleId, processId
    case version, buildNumber, buildDate, releaseType

    // Development Tools

    /// A host-supplied row from `Scyther.developerOptions`, identified by its ``DeveloperOption/name``.
    ///
    /// - Note: Because the pin identifier is derived from `name` (see ``id``), renaming a
    ///   developer option in the host app silently drops any pin on it — the old identifier
    ///   no longer resolves via ``init(id:)``, and behaves like any other stale pin.
    case developerOption(name: String)

    // Networking
    case ipAddress, networkLogs, serverConfiguration, environmentVariables

    // Data
    case featureFlags, userDefaults, cookies, fileBrowser, databaseBrowser

    // Security
    case keychainBrowser

    // System Tools
    case locationSpoofer, consoleLogs, deepLinkTester, crashLogs

    // Notifications
    case notificationLogger, notificationTester, apnsToken, fcmToken

    // UI/UX
    case fonts, interfaceComponents, gridOverlay, fpsCounter
    case touchVisualiser, appearance
    case slowAnimations, showViewFrames, showViewSizes

    /// The identifier prefix distinguishing host-supplied rows from built-in ones.
    static let developerOptionPrefix = "developerOption."

    /// Every built-in row, in menu order.
    ///
    /// Excludes ``developerOption(name:)``, which is supplied at runtime by the host app via
    /// `Scyther.developerOptions`.
    static let allStaticCases: [MenuItem] = [
        .osVersion, .hardware, .releaseYear, .uuid,
        .appIdPrefix, .displayName, .bundleId, .processId,
        .version, .buildNumber, .buildDate, .releaseType,
        .ipAddress, .networkLogs, .serverConfiguration, .environmentVariables,
        .featureFlags, .userDefaults, .cookies, .fileBrowser, .databaseBrowser,
        .keychainBrowser,
        .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs,
        .notificationLogger, .notificationTester, .apnsToken, .fcmToken,
        .fonts, .interfaceComponents, .gridOverlay, .fpsCounter,
        .touchVisualiser, .appearance,
        .slowAnimations, .showViewFrames, .showViewSizes
    ]

    /// A stable identifier, safe to persist across app launches and Scyther versions.
    var id: String {
        switch self {
        case .osVersion: return "osVersion"
        case .hardware: return "hardware"
        case .releaseYear: return "releaseYear"
        case .uuid: return "uuid"
        case .appIdPrefix: return "appIdPrefix"
        case .displayName: return "displayName"
        case .bundleId: return "bundleId"
        case .processId: return "processId"
        case .version: return "version"
        case .buildNumber: return "buildNumber"
        case .buildDate: return "buildDate"
        case .releaseType: return "releaseType"
        case .developerOption(let name): return Self.developerOptionPrefix + name
        case .ipAddress: return "ipAddress"
        case .networkLogs: return "networkLogs"
        case .serverConfiguration: return "serverConfiguration"
        case .environmentVariables: return "environmentVariables"
        case .featureFlags: return "featureFlags"
        case .userDefaults: return "userDefaults"
        case .cookies: return "cookies"
        case .fileBrowser: return "fileBrowser"
        case .databaseBrowser: return "databaseBrowser"
        case .keychainBrowser: return "keychainBrowser"
        case .locationSpoofer: return "locationSpoofer"
        case .consoleLogs: return "consoleLogs"
        case .deepLinkTester: return "deepLinkTester"
        case .crashLogs: return "crashLogs"
        case .notificationLogger: return "notificationLogger"
        case .notificationTester: return "notificationTester"
        case .apnsToken: return "apnsToken"
        case .fcmToken: return "fcmToken"
        case .fonts: return "fonts"
        case .interfaceComponents: return "interfaceComponents"
        case .gridOverlay: return "gridOverlay"
        case .fpsCounter: return "fpsCounter"
        case .touchVisualiser: return "touchVisualiser"
        case .appearance: return "appearance"
        case .slowAnimations: return "slowAnimations"
        case .showViewFrames: return "showViewFrames"
        case .showViewSizes: return "showViewSizes"
        }
    }

    /// A namespaced identifier for rendering this item inside the "Pinned" section.
    ///
    /// Pinned rows remain in their home section, so the same item appears twice in one
    /// `List`. Namespacing the pinned copy keeps SwiftUI's row identity unambiguous.
    var pinnedRowID: String { "pinned.\(id)" }

    /// Reconstructs an item from a persisted identifier.
    ///
    /// - Parameter id: An identifier previously produced by ``id``.
    /// - Returns: The matching item, or `nil` if no such row exists. A `nil` result is
    ///   expected and harmless — it means a stored pin refers to a row removed in a later
    ///   version of Scyther.
    init?(id: String) {
        if id.hasPrefix(Self.developerOptionPrefix) {
            let name = String(id.dropFirst(Self.developerOptionPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .developerOption(name: name)
            return
        }

        guard let match = Self.allStaticCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    /// The row's display label.
    var title: String {
        switch self {
        case .osVersion: return "OS Version"
        case .hardware: return "Hardware"
        case .releaseYear: return "Release Year"
        case .uuid: return "UUID"
        case .appIdPrefix: return "App ID Prefix"
        case .displayName: return "Display Name"
        case .bundleId: return "Bundle ID"
        case .processId: return "Process ID"
        case .version: return "Version"
        case .buildNumber: return "Build Number"
        case .buildDate: return "Build Date"
        case .releaseType: return "Release Type"
        case .developerOption(let name): return name
        case .ipAddress: return "IP Address"
        case .networkLogs: return "Network Logs"
        case .serverConfiguration: return "Server Configuration"
        case .environmentVariables: return "Environment Variables"
        case .featureFlags: return "Feature Flags"
        case .userDefaults: return "UserDefaults"
        case .cookies: return "Cookies"
        case .fileBrowser: return "File Browser"
        case .databaseBrowser: return "Database Browser"
        case .keychainBrowser: return "Keychain Browser"
        case .locationSpoofer: return "Location Spoofer"
        case .consoleLogs: return "Console Logs"
        case .deepLinkTester: return "Deep Link Tester"
        case .crashLogs: return "Crash Logs"
        case .notificationLogger: return "Notification Logger"
        case .notificationTester: return "Notification Tester"
        case .apnsToken: return "APNS Token"
        case .fcmToken: return "FCM Token"
        case .fonts: return "Fonts"
        case .interfaceComponents: return "Interface Components"
        case .gridOverlay: return "Grid Overlay"
        case .fpsCounter: return "FPS Counter"
        case .touchVisualiser: return "Touch Visualiser"
        case .appearance: return "Appearance"
        case .slowAnimations: return "Slow Animations"
        case .showViewFrames: return "Show View Frames"
        case .showViewSizes: return "Show View Sizes"
        }
    }

    /// The SF Symbol shown alongside the row, or `nil` for rows that display no icon.
    ///
    /// Device and application information rows intentionally have no icon, matching the
    /// menu's existing appearance. ``developerOption(name:)`` also returns `nil` here — its
    /// icon comes from the host-supplied `DeveloperOption`, which may be a `UIImage` rather
    /// than an SF Symbol.
    var icon: String? {
        switch self {
        case .osVersion, .hardware, .releaseYear, .uuid,
             .appIdPrefix, .displayName, .bundleId, .processId,
             .version, .buildNumber, .buildDate, .releaseType,
             .developerOption:
            return nil
        case .ipAddress: return "network"
        case .networkLogs: return "text.page.badge.magnifyingglass"
        case .serverConfiguration: return "server.rack"
        case .environmentVariables: return "x.squareroot"
        case .featureFlags: return "flag"
        case .userDefaults: return "face.dashed"
        case .cookies: return "info.circle"
        case .fileBrowser: return "folder"
        case .databaseBrowser: return "cylinder.split.1x2"
        case .keychainBrowser: return "key"
        case .locationSpoofer: return "location.circle"
        case .consoleLogs: return "terminal"
        case .deepLinkTester: return "link"
        case .crashLogs: return "exclamationmark.triangle"
        case .notificationLogger: return "list.bullet"
        case .notificationTester: return "bell"
        case .apnsToken: return "applelogo"
        case .fcmToken: return "flame"
        case .fonts: return "textformat"
        case .interfaceComponents: return "apps.iphone"
        case .gridOverlay: return "rectangle.split.3x3"
        case .fpsCounter: return "speedometer"
        case .touchVisualiser: return "hand.point.up"
        case .appearance: return "paintbrush"
        case .slowAnimations: return "tortoise"
        case .showViewFrames: return "rectangle.dashed"
        case .showViewSizes: return "ruler"
        }
    }
}
