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
/// Identity and display copy are deliberately separate: ``id`` is a stable, language
/// independent token used for tinting and for SwiftUI's `ForEach` identity, while ``title``
/// is localised copy that changes with the user's language.
///
/// ## Usage
///
/// ```swift
/// for section in MenuSection.allSections(developerOptions: Scyther.developerOptions) {
///     print(section.id, section.title, section.items.count)
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
/// - ``MenuSectionID``
struct MenuSection: Identifiable {
    /// Stable, language independent identifier — see ``MenuSectionID``.
    ///
    /// Never derived from ``title``: the title is localised, so keying anything on it would
    /// break the moment the user switched language.
    let id: String

    /// The section header text, already localised.
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
            MenuSection(id: MenuSectionID.device, title: localized("Device"), items: [
                .osVersion, .hardware, .releaseYear, .uuid
            ]),
            MenuSection(id: MenuSectionID.application, title: localized("Application"), items: [
                .appIdPrefix, .displayName, .bundleId, .processId,
                .version, .buildNumber, .buildDate, .releaseType
            ])
        ]

        if !developerOptions.isEmpty {
            sections.append(
                MenuSection(
                    id: MenuSectionID.developmentTools,
                    title: localized("Development Tools"),
                    items: developerOptions.map { .developerOption(name: $0.name) }
                )
            )
        }

        sections.append(contentsOf: [
            MenuSection(id: MenuSectionID.networking, title: localized("Networking"), items: [
                .ipAddress, .networkLogs, .serverConfiguration, .environmentVariables
            ]),
            MenuSection(id: MenuSectionID.data, title: localized("Data"), items: [
                .featureFlags, .userDefaults, .cookies, .fileBrowser, .databaseBrowser
            ]),
            MenuSection(id: MenuSectionID.security, title: localized("Security"), items: [
                .keychainBrowser
            ]),
            MenuSection(id: MenuSectionID.systemTools, title: localized("System Tools"), items: [
                .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs
            ]),
            MenuSection(id: MenuSectionID.notifications, title: localized("Notifications"), items: [
                .notificationLogger, .notificationTester, .apnsToken, .fcmToken
            ]),
            MenuSection(id: MenuSectionID.uiux, title: localized("UI/UX"), items: [
                .fonts, .interfaceComponents, .gridOverlay, .fpsCounter,
                .touchVisualiser, .appearance, .language,
                .slowAnimations, .showViewFrames, .showViewSizes
            ])
        ])

        return sections
    }
}

/// The stable identifiers of every ``MenuSection``.
///
/// These tokens are the menu's structural vocabulary: ``MenuSection/tint(forID:)`` keys the
/// section tile colours on them, and ``MenuView`` uses them for SwiftUI row identity. They are
/// never shown to the user and never translated, so a section keeps its colour and its identity
/// in every language.
enum MenuSectionID {
    /// Hardware and OS information.
    static let device = "device"

    /// App metadata and build details.
    static let application = "application"

    /// The host app's custom `DeveloperOption` rows.
    static let developmentTools = "developmentTools"

    /// Network tools, logs, and configuration.
    static let networking = "networking"

    /// Feature flags, `UserDefaults`, cookies, files, and databases.
    static let data = "data"

    /// The Keychain browser.
    static let security = "security"

    /// Location spoofing, console logs, deep links, and crash logs.
    static let systemTools = "systemTools"

    /// The notification logger and tester.
    static let notifications = "notifications"

    /// Fonts, components, overlays, and appearance overrides.
    static let uiux = "uiux"

    /// The synthetic section ``MenuView`` renders for pinned rows.
    static let pinned = "pinned"
}
