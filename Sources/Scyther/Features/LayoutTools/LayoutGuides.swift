//
//  LayoutGuides.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import Foundation

/// Whether the safe-area and layout-margin overlay is showing.
///
/// Its own setting rather than part of the ruler, because these are guides you want while
/// *using* the app — scrolling, navigating, watching a layout misbehave. The ruler's overlay
/// takes touches, so tying the guides to it would show them only when the app cannot be driven.
///
/// Settings are persisted in `UserDefaults.scyther`, Scyther's private suite, as the other
/// overlays' are.
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Configuration
/// - ``enabled``
///
/// ### UserDefaults Keys
/// - ``EnabledDefaultsKey``
@MainActor
internal final class LayoutGuides: Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)

    /// UserDefaults key for the enabled state.
    nonisolated static let EnabledDefaultsKey = "Scyther_layout_guides_enabled"

    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// The shared instance.
    static let instance = LayoutGuides()

    /// Whether the overlay is drawing.
    ///
    /// Persisted, so it survives a relaunch — unlike the ruler, which is not, because an overlay
    /// that eats touches and comes back after a restart is a trap. Guides only draw.
    ///
    /// The setter pushes the change straight to ``InterfaceToolkit/showLayoutGuides()``, on the
    /// main actor, the same way ``GridOverlay/enabled`` pushes to
    /// ``InterfaceToolkit/showGridOverlay()``. Without that push, flipping this property from
    /// outside the menu — the public `Scyther.interface.layoutGuidesEnabled` facade, or a test —
    /// would persist the new value but leave whatever the overlay was already showing on screen
    /// until something else happened to call ``InterfaceToolkit/showLayoutGuides()`` for an
    /// unrelated reason. Dispatched with `Task` rather than called inline because this setter is
    /// `nonisolated` — it has to be callable off the main actor — while the overlay it drives is
    /// UIKit state that only the main actor may touch.
    internal nonisolated var enabled: Bool {
        get {
            return UserDefaults.scyther.bool(forKey: LayoutGuides.EnabledDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: LayoutGuides.EnabledDefaultsKey)
            Task { @MainActor in InterfaceToolkit.instance.showLayoutGuides() }
        }
    }
}
