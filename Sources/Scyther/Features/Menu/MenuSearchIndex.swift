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
                    isSubpageEntry: false
                )
            }
        }
        return mainPageEntries + subpageEntries(in: sections)
    }

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
