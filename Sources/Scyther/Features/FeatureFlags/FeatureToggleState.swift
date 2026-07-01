//
//  FeatureToggleState.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation

/// The override state selected for a feature toggle in the Scyther UI.
///
/// A toggle can be pinned to an explicit local override (``on`` / ``off``) or left to follow
/// its remote value (``remote``). This three-state model backs the dropdown menu button shown
/// for each flag, replacing the previous on/off switch.
///
/// ## Semantics
///
/// - ``on`` — a local override forcing the flag to `true`.
/// - ``off`` — a local override forcing the flag to `false`.
/// - ``remote`` — no local override; the flag follows its ``FeatureToggle/remoteValue``.
///
/// ## Topics
///
/// ### Cases
/// - ``on``
/// - ``off``
/// - ``remote``
///
/// ### Display
/// - ``displayName``
enum FeatureToggleState: String, CaseIterable, Identifiable, Sendable {
    /// A local override forcing the flag on (`true`).
    case on

    /// A local override forcing the flag off (`false`).
    case off

    /// No local override; the flag follows its remote value.
    case remote

    /// A stable identifier for use in SwiftUI `ForEach`/`Picker` iteration.
    var id: String { rawValue }

    /// The user-facing label shown in the dropdown menu.
    var displayName: String {
        switch self {
        case .on: return "True"
        case .off: return "False"
        case .remote: return "Remote"
        }
    }
}
