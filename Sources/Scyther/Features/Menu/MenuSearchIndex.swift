//
//  MenuSearchIndex.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

/// The global search index for the Scyther main menu.
///
/// The index has two parts:
/// - **Main-menu entries** are derived from ``MenuSection/allSections(developerOptions:)``
///   — one entry per row, carrying its section title as the breadcrumb. Because they are
///   derived, they can never drift from the real menu layout.
/// - **Sub-page entries** are a hand-curated list of the static rows inside settings
///   pages (see `subpageTitles`). Dynamic content — network log entries, UserDefaults
///   keys, files, fonts, host-supplied server configurations — is deliberately not
///   indexed, matching how the iOS Settings app treats app content.
///
/// ## Topics
///
/// ### Building the index
/// - ``entries(developerOptions:)``
///
/// ### Searching
/// - ``entries(matching:developerOptions:)``
enum MenuSearchIndex {
    /// Every searchable entry: one per main-menu row, followed by the curated
    /// sub-page entries.
    ///
    /// - Parameter developerOptions: The host app's custom options, so the
    ///   "Development Tools" rows are searchable exactly when they are visible.
    /// - Returns: All entries, in menu order.
    static func entries(developerOptions: [DeveloperOption]) -> [MenuSearchEntry] {
        let sections = MenuSection.allSections(developerOptions: developerOptions)
        let mainPageEntries = sections.flatMap { section in
            section.items.map { item in
                MenuSearchEntry(
                    title: item.title,
                    breadcrumb: [section.title],
                    icon: item.icon,
                    target: item,
                    isSubpageEntry: false,
                    keywords: keywords[item] ?? []
                )
            }
        }
        return mainPageEntries + subpageEntries(in: sections)
    }

    /// The entries matching a search query.
    ///
    /// Matching uses `localizedStandardContains` — case-insensitive,
    /// diacritic-insensitive, locale-aware — against the entry's title, each
    /// breadcrumb component, and each alias keyword, so searching "grid" surfaces
    /// every row under Grid Overlay and searching "remote config" surfaces Feature
    /// Flags. Keywords match in both directions: a query containing a keyword
    /// ("environment env var") and a keyword containing the query ("env va") both hit.
    ///
    /// - Parameters:
    ///   - query: The user's search text. Leading and trailing whitespace is
    ///     ignored; an effectively empty query matches nothing.
    ///   - developerOptions: The host app's custom options — see ``entries(developerOptions:)``.
    /// - Returns: Matching entries, in menu order.
    static func entries(
        matching query: String,
        developerOptions: [DeveloperOption]
    ) -> [MenuSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return entries(developerOptions: developerOptions).filter { entry in
            entry.title.localizedStandardContains(trimmed)
                || entry.breadcrumb.contains { $0.localizedStandardContains(trimmed) }
                || entry.keywords.contains {
                    $0.localizedStandardContains(trimmed) || trimmed.localizedStandardContains($0)
                }
        }
    }

    /// Alias terms per row — jargon a developer might type instead of the visible
    /// title. Hand-curated, matched case- and diacritic-insensitively.
    static let keywords: [MenuItem: [String]] = [
        .uuid: ["identifier", "idfv", "device id"],
        .bundleId: ["bundle identifier", "app id"],
        .version: ["build", "release"],
        .buildNumber: ["build"],
        .releaseType: ["configuration", "testflight", "app store", "debug"],
        .ipAddress: ["ip", "network address"],
        .networkLogs: ["http", "requests", "responses", "traffic", "api", "charles", "proxy"],
        .serverConfiguration: ["backend", "staging", "production", "base url", "endpoint"],
        .environmentVariables: ["env", "env var", "env vars", "environment"],
        .featureFlags: ["remote config", "experiments", "toggles", "flags", "ab test", "launch darkly"],
        .userDefaults: ["preferences", "prefs", "defaults", "nsuserdefaults", "plist"],
        .cookies: ["http cookies"],
        .fileBrowser: ["files", "documents", "sandbox", "caches"],
        .databaseBrowser: ["sqlite", "core data", "coredata", "swiftdata", "db"],
        .keychainBrowser: ["secure storage", "credentials", "passwords", "secrets"],
        .locationSpoofer: ["gps", "fake location", "mock location", "coordinates", "geo"],
        .consoleLogs: ["stdout", "stderr", "print", "logs", "logging"],
        .deepLinkTester: ["url scheme", "universal link", "deeplink", "deep link"],
        .crashLogs: ["crashes", "exceptions", "stack trace"],
        .notificationLogger: ["push", "apns", "payload"],
        .notificationTester: ["push", "apns", "local notification"],
        .apnsToken: ["push token", "device token"],
        .fcmToken: ["firebase", "push token"],
        .fonts: ["typography", "typefaces", "text styles"],
        .interfaceComponents: ["previews", "components", "design system"],
        .gridOverlay: ["alignment", "layout grid"],
        .fpsCounter: ["frame rate", "performance", "hitches"],
        .touchVisualiser: ["touches", "taps", "gestures"],
        .appearance: ["dark mode", "light mode", "theme", "dynamic type", "contrast"],
        .slowAnimations: ["animation speed"],
        .showViewFrames: ["debug view", "borders", "layout"],
        .showViewSizes: ["dimensions", "layout"]
    ]

    /// The static rows inside settings sub-pages, keyed by the page's menu item.
    ///
    /// Hand-curated: when a settings page gains or loses a static row, update its
    /// titles here. Titles should match the visible row labels closely enough that
    /// searching what the user can read finds the page.
    private static let subpageTitles: [(target: MenuItem, titles: [String])] = [
        (.gridOverlay, ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"]),
        (.fpsCounter, ["Enable FPS Counter", "FPS Counter Position"]),
        (.touchVisualiser, [
            "Show Screen Touches", "Log Screen Touches",
            "Show Touch Duration", "Show Touch Radius"
        ]),
        (.appearance, [
            "Color Scheme", "Dynamic Type", "Override Text Size",
            "Increase Contrast", "Reset to System Defaults"
        ]),
        (.locationSpoofer, [
            "Enable Location Spoofing", "Location Presets", "Custom Location"
        ]),
        (.notificationTester, [
            "Request Notification Permission", "Send Push Notification",
            "Badge Count", "Cancel Scheduled Notifications", "Clear Badge & Notifications"
        ]),
        (.deepLinkTester, ["Open URL", "Deep Link Presets", "Deep Link History"])
    ]

    /// Builds the sub-page entries, resolving each target's home section from the
    /// live layout so breadcrumbs can never drift from the real menu.
    private static func subpageEntries(in sections: [MenuSection]) -> [MenuSearchEntry] {
        subpageTitles.flatMap { target, titles -> [MenuSearchEntry] in
            guard let home = sections.first(where: { $0.items.contains(target) }) else {
                return []
            }
            return titles.map { title in
                MenuSearchEntry(
                    title: title,
                    breadcrumb: [home.title, target.title],
                    icon: target.icon,
                    target: target,
                    isSubpageEntry: true
                )
            }
        }
    }
}
