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
        return sections.flatMap { section in
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
    }
}
