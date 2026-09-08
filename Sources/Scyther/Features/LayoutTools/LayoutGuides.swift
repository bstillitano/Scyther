//
//  LayoutGuides.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

#if !os(macOS)
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
/// This type has no `AppEnvironment` check of its own, on purpose. Safety is inherited from
/// ``InterfaceToolkit/start()``, which is only reached from `Scyther.start()` — gated on
/// `AppEnvironment.isAppStore`/`allowProductionBuilds` — the same way `GridOverlay` and
/// `FPSCounter` are protected. A second, local check here would be a second answer that can
/// drift from the first; one gate, inherited, is the whole toolkit's convention.
///
/// That inherited gate is `isAppStore` only, and there is deliberately no `isTestCase` check
/// anywhere on this path, where ``AccessibilityAudit/canAuditKeyWindow(isTestCase:isAppStore:)``
/// carries one. The audit needs it because it *runs* — walking a window and rasterising it —
/// whenever something asks it to, including from a test that constructs a fabricated `UIWindow`.
/// This overlay runs nothing: it is a view installed by `Scyther.start()`, which a test process
/// never calls, so in a test there is no overlay, no wrapper and no window to draw over, and a
/// local gate would guard a path that cannot be reached rather than one that can.
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
/// - ``init(defaults:)``
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

    /// The shared instance, backed by `UserDefaults.scyther`.
    ///
    /// Every part of Scyther other than a test reads and writes settings through this instance.
    static let instance = LayoutGuides()

    /// The store this instance's settings are persisted to.
    ///
    /// Declared `nonisolated(unsafe)` rather than actor-isolated so the `nonisolated` computed
    /// property below — ``enabled`` — can read and write it without a main-actor hop.
    /// `(unsafe)` because `UserDefaults` predates `Sendable` and the compiler cannot verify it,
    /// not because this type does anything actually unsafe with it: it is a `let`, so the
    /// reference itself never changes after `init`, and `UserDefaults` is documented as
    /// thread-safe on its own — the same reasoning every other Scyther settings singleton
    /// already relies on for `UserDefaults.scyther` itself.
    private nonisolated(unsafe) let defaults: UserDefaults

    /// Creates a settings manager over `defaults`.
    ///
    /// Production code has no reason to call this directly — use ``instance``. It exists so a
    /// test can construct a manager over a throwaway `UserDefaults` suite instead of mutating
    /// the shared store, the way `AccessibilityAudit.init(defaults:)` and every other Scyther
    /// settings test works. Before this initialiser existed, ``enabled`` read and wrote
    /// `UserDefaults.scyther` directly, and the only test this type had could not distinguish
    /// its own key ever being read from an empty suite answering `false` for any key whatsoever.
    ///
    /// - Parameter defaults: The store to read and write settings from. Defaults to
    ///   `UserDefaults.scyther`.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
    }

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
    /// UIKit state that only the main actor may touch. That push always drives the *shared*
    /// ``instance``'s overlay, even when called on a throwaway test instance — the same
    /// behaviour ``AccessibilityAudit/liveEnabled``'s setter has, and harmless in a test process
    /// where `InterfaceToolkit`'s overlay is never installed.
    internal nonisolated var enabled: Bool {
        get {
            return defaults.bool(forKey: LayoutGuides.EnabledDefaultsKey)
        }
        set {
            defaults.setValue(newValue, forKey: LayoutGuides.EnabledDefaultsKey)
            Task { @MainActor in InterfaceToolkit.instance.showLayoutGuides() }
        }
    }
}
#endif
