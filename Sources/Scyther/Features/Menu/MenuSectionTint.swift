//
//  MenuSectionTint.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import SwiftUI

extension MenuSection {
    /// The tile colour for rows belonging to a section, keyed by section title.
    ///
    /// Every row's icon tile is tinted with its *home* section's colour, giving each
    /// section a distinct identity the way the iOS Settings app colours its icons.
    /// Rows rendered outside their home section — the "Pinned" section and search
    /// results — keep their home colour, so a row is recognisable wherever it appears.
    ///
    /// - Parameter title: A section title, as produced by
    ///   ``allSections(developerOptions:)``. Unknown titles fall back to the app's
    ///   accent colour rather than failing.
    /// - Returns: The section's tile colour.
    static func tint(forTitle title: String) -> Color {
        switch title {
        case "Device": return .gray
        case "Application": return .indigo
        case "Development Tools": return .brown
        case "Networking": return .blue
        case "Data": return .orange
        case "Security": return .green
        case "System Tools": return .purple
        case "Notifications": return .red
        case "UI/UX": return .teal
        default: return .accentColor
        }
    }

    /// This section's tile colour — see ``tint(forTitle:)``.
    var tint: Color { Self.tint(forTitle: title) }
}

extension MenuItem {
    /// The row's tile colour — its home section's ``MenuSection/tint``.
    ///
    /// A computed sibling of ``title`` and ``icon``, so a row's whole presentation
    /// reads off the item itself. Home sections of built-in rows are static layout
    /// (``MenuSection/allSections(developerOptions:)``), and a developer option always
    /// lives in "Development Tools", so no live menu state is needed.
    var tint: Color {
        if case .developerOption = self {
            return MenuSection.tint(forTitle: "Development Tools")
        }
        let home = MenuSection.allSections(developerOptions: []).first { $0.items.contains(self) }
        return home?.tint ?? .accentColor
    }
}
