//
//  LanguageViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Combine
import Foundation
import UIKit

/// One selectable row on the Language page.
struct LanguageRow: Identifiable, Hashable, Sendable {
    /// The language identifier, or ``LanguageViewModel/systemDefaultID``.
    let id: String
    /// The language's name in itself, e.g. "français".
    let nativeName: String
    /// The language's name in the current locale, e.g. "French".
    let localizedName: String
}

/// View model backing ``LanguageView``.
///
/// Lists the host app's declared localisations after a System Default row, applies a selection
/// through ``LanguageOverride``, and raises the relaunch alert. Quitting is only ever triggered by
/// the alert's destructive action.
final class LanguageViewModel: ViewModel {
    /// The id of the row that clears the override.
    static let systemDefaultID = "system"

    /// The override this page edits.
    let override: LanguageOverride

    /// Whether the "Relaunch required" alert is presented.
    @Published var showingRelaunchAlert: Bool = false

    private var cancellable: AnyCancellable?

    /// Creates the view model.
    ///
    /// - Parameter override: The override to edit. Defaults to the shared instance.
    init(override: LanguageOverride = .shared) {
        self.override = override
        super.init()
        cancellable = override.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The rows to display: System Default first, then the host app's languages.
    var rows: [LanguageRow] {
        let system = LanguageRow(
            id: Self.systemDefaultID,
            nativeName: localized("System Default"),
            localizedName: localized("Follow the device language")
        )
        let languages = override.availableLanguages.map {
            LanguageRow(id: $0, nativeName: override.nativeDisplayName(for: $0), localizedName: override.displayName(for: $0))
        }
        return [system] + languages
    }

    /// Whether the host app declares any language beyond the base localisation.
    var hasLanguages: Bool { !override.availableLanguages.isEmpty }

    /// Whether an override is currently set.
    var canReset: Bool { override.preferredLanguage != nil }

    /// The effective language name for the Current section.
    var currentLanguage: String { override.currentLanguageDisplayName }

    /// The device region name for the Current section.
    var currentRegion: String { override.currentRegionDisplayName }

    /// Whether a row is the active choice.
    ///
    /// - Parameter row: The row to check.
    func isSelected(_ row: LanguageRow) -> Bool {
        (override.preferredLanguage ?? Self.systemDefaultID) == row.id
    }

    /// Applies a row's language and raises the relaunch alert.
    ///
    /// - Parameter row: The tapped row.
    func select(_ row: LanguageRow) {
        if row.id == Self.systemDefaultID {
            override.reset()
        } else {
            override.setPreferredLanguage(row.id)
        }
        showingRelaunchAlert = true
    }

    /// Clears the override without raising the alert.
    func reset() {
        override.reset()
    }

    /// Terminates the process so the host app relaunches in the chosen language.
    ///
    /// Only called from the destructive action of the relaunch alert.
    func quitApp() {
        exit(0)
    }
}
