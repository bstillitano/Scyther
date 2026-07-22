//
//  DefaultsStore.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/7/2026.
//

import Foundation

/// Identifies which `UserDefaults` store the UserDefaults browser is inspecting.
///
/// Scyther keeps its own settings in a private suite rather than the standard store, so the
/// browser needs to be able to show either one.
///
/// ## Topics
///
/// ### Cases
/// - ``app``
/// - ``scyther``
///
/// ### Properties
/// - ``title``
/// - ``defaults``
enum DefaultsStore: String, CaseIterable, Identifiable, Sendable {
    /// The host application's own defaults — `UserDefaults.standard`.
    case app

    /// Scyther's private preferences suite — `UserDefaults.scyther`.
    case scyther

    /// Stable identifier, used for `Picker` selection and `ForEach`.
    var id: String { rawValue }

    /// The human-readable name shown in the store picker.
    var title: String {
        switch self {
        case .app: return "App"
        case .scyther: return "Scyther"
        }
    }

    /// The underlying store this case refers to.
    var defaults: UserDefaults {
        switch self {
        case .app: return .standard
        case .scyther: return .scyther
        }
    }
}
