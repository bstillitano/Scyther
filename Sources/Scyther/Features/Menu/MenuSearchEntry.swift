//
//  MenuSearchEntry.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

/// A single searchable row in the global menu search index.
///
/// Entries come in two flavours, distinguished by ``isSubpageEntry``:
/// - **Main-page entries** represent a row on the main menu itself. Their ``target``
///   is that row, and ``MenuView`` renders them through its normal row definition so
///   toggles stay live and value rows show their values.
/// - **Sub-page entries** represent a static row *inside* a settings page — for
///   example "Grid Color" inside Grid Overlay. Their ``target`` is the page that
///   contains the row, and tapping the result navigates to that page.
///
/// ## Topics
///
/// ### Identity
/// - ``id``
///
/// ### Presentation
/// - ``title``
/// - ``breadcrumb``
/// - ``breadcrumbText``
/// - ``icon``
///
/// ### Resolution
/// - ``target``
/// - ``isSubpageEntry``
struct MenuSearchEntry: Identifiable, Hashable, Sendable {
    /// The text shown as the result's title, and matched against the search query.
    let title: String

    /// The navigation path shown beneath the title, outermost first.
    ///
    /// Main-page entries carry a single component (their section's title, e.g.
    /// `["Networking"]`); sub-page entries carry two (`["UI/UX", "Grid Overlay"]`).
    let breadcrumb: [String]

    /// The SF Symbol shown alongside the result, or `nil` for icon-less rows.
    let icon: String?

    /// The menu row this result resolves to.
    ///
    /// Main-page entries target themselves; sub-page entries target the page
    /// containing the matched row.
    let target: MenuItem

    /// Whether this entry represents a row inside ``target`` rather than the
    /// main-page row itself.
    let isSubpageEntry: Bool

    /// Alias terms this entry also matches — jargon a developer might type instead
    /// of the visible title, e.g. "remote config" for Feature Flags or "env var"
    /// for Environment Variables. Not displayed anywhere.
    var keywords: [String] = []

    /// Stable identity: the target's identifier plus the title, because sub-page
    /// entries share a ``target`` with each other and with the page's own entry.
    var id: String { "\(target.id).\(title)" }

    /// The breadcrumb rendered as a single line, components joined with "→".
    var breadcrumbText: String { breadcrumb.joined(separator: " → ") }
}
