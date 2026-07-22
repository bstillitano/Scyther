//
//  MenuSection.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// A titled group of rows in the Scyther main menu.
///
/// Describing the menu as data rather than as literal SwiftUI sections is what lets
/// ``MenuView`` render the same ``MenuItem`` in both its home section and the "Pinned"
/// section from a single row definition.
///
/// ## Usage
///
/// ```swift
/// for section in MenuSection.allSections(developerOptions: Scyther.developerOptions) {
///     print(section.title, section.items.count)
/// }
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``id``
/// - ``title``
/// - ``items``
///
/// ### Layout
/// - ``allSections(developerOptions:)``
struct MenuSection: Identifiable {
    /// Stable identifier, derived from the section's title.
    var id: String { title }

    /// The section header text.
    let title: String

    /// The rows in this section, in display order.
    let items: [MenuItem]

    /// The full menu layout, in display order.
    ///
    /// "Device" is always first — ``MenuView`` renders the device header inside it and
    /// inserts the "Pinned" section immediately afterwards.
    ///
    /// - Parameter developerOptions: The host app's custom options, from
    ///   `Scyther.developerOptions`. When empty, the "Development Tools" section is omitted
    ///   entirely rather than rendered blank.
    /// - Returns: Every section that should be displayed.
    static func allSections(developerOptions: [DeveloperOption]) -> [MenuSection] {
        var sections: [MenuSection] = [
            MenuSection(title: "Device", items: [
                .osVersion, .hardware, .releaseYear, .uuid
            ]),
            MenuSection(title: "Application", items: [
                .appIdPrefix, .displayName, .bundleId, .processId,
                .version, .buildNumber, .buildDate, .releaseType
            ])
        ]

        if !developerOptions.isEmpty {
            sections.append(
                MenuSection(
                    title: "Development Tools",
                    items: developerOptions.map { .developerOption(name: $0.name) }
                )
            )
        }

        sections.append(contentsOf: [
            MenuSection(title: "Networking", items: [
                .ipAddress, .networkLogs, .serverConfiguration, .environmentVariables
            ]),
            MenuSection(title: "Data", items: [
                .featureFlags, .userDefaults, .cookies, .fileBrowser, .databaseBrowser
            ]),
            MenuSection(title: "Security", items: [
                .keychainBrowser
            ]),
            MenuSection(title: "System Tools", items: [
                .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs
            ]),
            MenuSection(title: "Notifications", items: [
                .notificationLogger, .notificationTester, .apnsToken, .fcmToken
            ]),
            MenuSection(title: "UI/UX", items: [
                .fonts, .interfaceComponents, .gridOverlay, .fpsCounter,
                .touchVisualiser, .appearance,
                .slowAnimations, .showViewFrames, .showViewSizes
            ])
        ])

        return sections
    }
}
