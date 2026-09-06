//
//  AccessibilityAudit.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import UIKit

/// A singleton manager for the accessibility audit's settings and for running it against the
/// live app.
///
/// `AccessibilityAudit` follows the same shape as ``GridOverlay``: a shared ``instance`` backed
/// by `UserDefaults.scyther`, `nonisolated` computed properties so a host app or a background
/// queue can read and write settings without hopping to the main actor first, and a `Task { …
/// }` hop back onto the main actor whenever a setting change needs to touch UIKit. It differs
/// from ``GridOverlay`` in one way: its initialiser takes the `UserDefaults` store explicitly,
/// so a test can hand it a throwaway suite rather than mutating the shared one.
///
/// ```swift
/// // Turn the live overlay on
/// AccessibilityAudit.instance.liveEnabled = true
///
/// // Switch one check off, leaving the others running
/// AccessibilityAudit.instance.setEnabled(.contrast, to: false)
/// ```
///
/// - Note: This task does not build a settings screen — nothing in Scyther's menu reaches these
///   properties yet. They exist so the settings screen a later task builds has something to bind
///   to, and so ``InterfaceToolkit`` has something to read when it decides whether to draw the
///   overlay.
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
/// - ``init(defaults:)``
///
/// ### Live Mode
/// - ``liveEnabled``
///
/// ### Per-Check Settings
/// - ``isEnabled(_:)``
/// - ``setEnabled(_:to:)``
/// - ``enabledChecks``
///
/// ### Running the Audit
/// - ``auditKeyWindow()``
@MainActor
internal final class AccessibilityAudit: Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)

    /// UserDefaults key for storing whether the live overlay is switched on.
    nonisolated static let LiveEnabledDefaultsKey: String = "Scyther_accessibility_audit_live_enabled"

    /// The shared singleton instance of `AccessibilityAudit`, backed by `UserDefaults.scyther`.
    ///
    /// Every part of Scyther other than a test reads and writes settings through this instance,
    /// so a setting changed from the (future) settings screen is immediately visible to
    /// ``InterfaceToolkit``.
    static let instance = AccessibilityAudit()

    /// The store this instance's settings are persisted to.
    ///
    /// Declared `nonisolated(unsafe)` rather than actor-isolated so the `nonisolated` computed
    /// properties below — ``liveEnabled``, ``isEnabled(_:)``, ``setEnabled(_:to:)`` — can read
    /// and write it without a main-actor hop. `(unsafe)` rather than plain `nonisolated` because
    /// `UserDefaults` predates `Sendable` and the compiler cannot verify it, not because this
    /// type does anything actually unsafe with it: it is a `let`, so the reference itself never
    /// changes after `init`, and `UserDefaults` is documented as thread-safe on its own —
    /// exactly the reasoning ``GridOverlay`` and every other Scyther settings singleton already
    /// relies on for `UserDefaults.scyther` itself.
    private nonisolated(unsafe) let defaults: UserDefaults

    /// Creates a settings manager over `defaults`.
    ///
    /// Production code has no reason to call this directly — use ``instance``. It exists so a
    /// test can construct a manager over a throwaway `UserDefaults` suite instead of mutating
    /// the shared store, the same way every other Scyther settings test works.
    ///
    /// - Parameter defaults: The store to read and write settings from. Defaults to
    ///   `UserDefaults.scyther`.
    init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
    }

    /// Controls whether the accessibility audit runs continuously against the live app and
    /// draws its findings as an overlay.
    ///
    /// Setting this to `true` audits the key window immediately and re-audits it whenever the
    /// screen's layout is likely to have changed — see
    /// ``InterfaceToolkit/scheduleAccessibilityReaudit()``. The value is persisted to
    /// `UserDefaults.scyther` and restored on app launch, and — mirroring
    /// ``GridOverlay/enabled`` exactly — a change hops onto the main actor to tell
    /// ``InterfaceToolkit`` to show or hide the overlay, since `InterfaceToolkit` and the
    /// overlay view it owns are both UIKit and therefore main-actor-only.
    internal nonisolated var liveEnabled: Bool {
        get {
            defaults.bool(forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        }
        set {
            defaults.setValue(newValue, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
            Task { @MainActor in InterfaceToolkit.instance.showAccessibilityAudit() }
        }
    }

    /// Whether `check` is switched on.
    ///
    /// A check with nothing stored yet reads as `true`: every check ships on, so a developer
    /// who has never opened the (future) settings screen still gets the full audit rather than
    /// a silently empty one. This is why the read cannot use `UserDefaults.bool(forKey:)`
    /// directly — that method itself defaults absence to `false`, which is exactly backwards
    /// for a set of checks that are on unless a developer has explicitly turned one off.
    ///
    /// - Parameter check: The check to read.
    /// - Returns: `true` when the check is on, including when nothing has been stored for it.
    internal nonisolated func isEnabled(_ check: AccessibilityCheck) -> Bool {
        guard let stored = defaults.object(forKey: check.defaultsKey) as? Bool else { return true }
        return stored
    }

    /// Switches `check` on or off, leaving every other check untouched.
    ///
    /// - Parameters:
    ///   - check: The check to change.
    ///   - isEnabled: `true` to run the check, `false` to skip it.
    internal nonisolated func setEnabled(_ check: AccessibilityCheck, to isEnabled: Bool) {
        defaults.setValue(isEnabled, forKey: check.defaultsKey)
    }

    /// Every check that is currently switched on.
    ///
    /// This is exactly what ``auditKeyWindow()`` passes to ``AccessibilityAuditor/audit(root:checks:sampler:)``
    /// as `checks`, and it can be empty: switching every check off is not the same as switching
    /// the audit off — see ``AccessibilityAuditor/Result/checksRun``, which is how the (future)
    /// report screen tells "nothing was wrong" apart from "nothing was looked at".
    internal var enabledChecks: Set<AccessibilityCheck> {
        Set(AccessibilityCheck.allCases.filter(isEnabled))
    }

    /// Audits the key window right now.
    ///
    /// Returns an empty result — no findings, no truncation, no checks run — while a test is
    /// running. A test's `UIWindow` is a fabricated one with no relation to the app the
    /// developer is actually debugging, so walking it would either report meaningless findings
    /// about test scaffolding or, worse, waste time on a window that no developer will ever look
    /// at through this overlay. Production and the example app always audit the real key window.
    ///
    /// - Returns: The audit's findings, whether the walk was truncated, and which checks ran.
    @MainActor
    func auditKeyWindow() -> AccessibilityAuditor.Result {
        guard !AppEnvironment.isTestCase else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }
        guard let window = Self.keyWindow else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }

        let checks = enabledChecks
        let sampler: ContrastSampling? = checks.contains(.contrast) ? WindowContrastSampler(window: window) : nil
        return AccessibilityAuditor().audit(root: window, checks: checks, sampler: sampler)
    }

    /// The app's key window, resolved the same way `InterfaceToolkit` and `Scyther` itself do.
    ///
    /// Repeated in each of those types rather than shared, matching how they already each keep
    /// their own private copy — there is no existing shared accessor to reuse, and one is not
    /// worth introducing for a single-expression lookup.
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
