//
//  NetworkRuleStoreFailure.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Something ``NetworkRuleStore`` could not do, phrased for the developer looking at the menu.
///
/// Every one of these was once swallowed by a `try?`: an encode that threw left the in-memory
/// rules and the persisted blob disagreeing, and a blob that would not decode quietly became an
/// empty list. A debugging tool that lies about its own state costs more time than the bug being
/// chased, so the store records what went wrong and ``NetworkRulesView`` says it out loud.
///
/// ## Topics
///
/// ### Cases
/// - ``rulesNotSaved``
/// - ``rulesNotLoaded``
/// - ``bodyNotWritten``
///
/// ### Presentation
/// - ``title``
/// - ``message``
enum NetworkRuleStoreFailure: String, Identifiable, Equatable, Sendable {
    /// The rules could not be encoded, so `UserDefaults` still holds the previous blob.
    case rulesNotSaved

    /// The persisted blob could not be decoded, so the list started empty.
    ///
    /// The blob itself is kept rather than overwritten — see ``NetworkRuleStore``.
    case rulesNotLoaded

    /// A mock response body could not be written to disk, so the override was not stored.
    case bodyNotWritten

    /// A stable identity, so the alert redraws when one failure replaces another.
    var id: String { rawValue }

    /// The alert's title.
    var title: String {
        switch self {
        case .rulesNotSaved: return localized("Overrides Not Saved")
        case .rulesNotLoaded: return localized("Overrides Not Loaded")
        case .bodyNotWritten: return localized("Override Not Saved")
        }
    }

    /// The alert's body copy, which says what the developer has actually lost.
    var message: String {
        switch self {
        case .rulesNotSaved:
            return localized("Your overrides could not be written to preferences, so this change will not survive a relaunch.")
        case .rulesNotLoaded:
            return localized("The saved overrides could not be read, so the list started empty. They have been set aside rather than deleted.")
        case .bodyNotWritten:
            return localized("The mock response body could not be written to disk, so the override was not saved.")
        }
    }
}
