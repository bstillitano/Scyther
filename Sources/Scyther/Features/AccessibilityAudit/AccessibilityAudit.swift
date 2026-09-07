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
/// - Note: These settings are bound to by the toggles at the top of ``AccessibilityAuditView``,
///   reachable from the menu at **UI/UX → Accessibility Audit**, and read by
///   ``InterfaceToolkit`` when it decides whether to draw the live overlay.
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
/// - ``canAuditKeyWindow(isTestCase:isAppStore:)``
/// - ``checksNeedingAnUncoveredScreen``
/// - ``checksSkippedWhileCovered(from:isCovering:)``
/// - ``checksUnmeasurableWithoutASnapshot(from:didCaptureWindow:)``
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

    /// A sampler, and whether the window it was taken from could actually be read.
    ///
    /// Two values rather than one because the pass has to tell "here are the pixels" apart from
    /// "iOS declined to give me any" — see
    /// ``AccessibilityAudit/checksUnmeasurableWithoutASnapshot(from:didCaptureWindow:)`` — and the
    /// second is a fact about the capture rather than something a `ContrastSampling` is asked.
    internal struct ContrastSource {
        /// Where the contrast check reads pixels from.
        let sampler: ContrastSampling

        /// Whether the window snapshot behind it succeeded.
        let didCaptureWindow: Bool

        /// Creates a source.
        ///
        /// - Parameters:
        ///   - sampler: Where the pixels come from.
        ///   - didCaptureWindow: Whether the snapshot succeeded.
        init(sampler: ContrastSampling, didCaptureWindow: Bool) {
            self.sampler = sampler
            self.didCaptureWindow = didCaptureWindow
        }
    }

    /// How a pass gets its pixels, when it needs any.
    ///
    /// A seam, and the only way to assert the thing this wave is actually about: `ScytherTests` has
    /// no host app, so `drawHierarchy(in:afterScreenUpdates:)` paints nothing and
    /// `WindowContrastSampler` costs almost nothing to construct there. A test that timed a live
    /// pass, or that inspected the findings it produced, would pass identically whether or not the
    /// snapshot was ever taken. Counting calls to this closure is the one question with the same
    /// answer in a test process and on a device.
    ///
    /// Production is unaffected: the default builds the real sampler.
    internal var makeContrastSource: @MainActor (UIWindow) -> ContrastSource = { window in
        let sampler = WindowContrastSampler(window: window)
        return ContrastSource(sampler: sampler, didCaptureWindow: sampler.didCaptureWindow)
    }

    /// Reads the current time, so a test can spend a pass's budget deterministically.
    ///
    /// The same seam, and for the same reason, as ``AccessibilityAuditor/now``: a wall-clock budget
    /// tested against the wall clock either sleeps or flakes. It matters more here than there,
    /// because the budget's whole job on this path is to bound something a test cannot make slow —
    /// the window snapshot — and the only way to write that test is to let it move the clock by
    /// hand from inside ``makeContrastSource``.
    internal var now: () -> Date = Date.init

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

    /// The checks that can only be answered honestly when nothing of Scyther's is on screen.
    ///
    /// Contrast alone. It is measured by snapshotting the window and reading the pixels behind
    /// each element, and a modally presented screen dims and scales everything behind it — so
    /// while Scyther's menu, or its own report, is up, those pixels are the app seen *through*
    /// Scyther. That is how a screen of ordinary section headers came back as "About 1.2:1 …
    /// #0A0A0B on #1B1B1D": two near-identical greys that exist nowhere in the app and only in
    /// Scyther's dimming of it.
    ///
    /// Missing labels and touch targets are read from the accessibility tree rather than from
    /// pixels, so nothing covering the screen can change their answer, and they keep running.
    internal nonisolated static let checksNeedingAnUncoveredScreen: Set<AccessibilityCheck> = [.contrast]

    /// Which of `enabled` must be skipped because Scyther's own UI is covering the app.
    ///
    /// Split out from ``auditKeyWindow()`` so the rule itself can be tested: `auditKeyWindow()`
    /// deliberately does nothing at all under a test — see its own documentation — which would
    /// otherwise leave this decision as the one part of the audit no test can reach.
    ///
    /// - Parameters:
    ///   - enabled: The checks the developer has switched on.
    ///   - isCovering: Whether Scyther's own UI is in front of the app, per
    ///     ``ScytherPresentation/isCoveringScreen``.
    /// - Returns: The enabled checks to skip, which is empty whenever nothing of Scyther's is on
    ///   screen.
    internal nonisolated static func checksSkippedWhileCovered(from enabled: Set<AccessibilityCheck>,
                                                              isCovering: Bool) -> Set<AccessibilityCheck> {
        guard isCovering else { return [] }
        return enabled.intersection(checksNeedingAnUncoveredScreen)
    }

    // MARK: - What A Pass Is For, And What It May Cost

    /// Why a pass is being taken, which is what decides what it may afford to do.
    ///
    /// The two are not variations on one pass. A live pass runs on every navigation, unasked, while
    /// the developer is using their app; a report pass runs once, because the developer tapped
    /// something and is waiting for an answer. They can therefore afford completely different
    /// amounts of main thread, and pretending otherwise is what made the live overlay freeze the
    /// app for most of a second every time the screen changed.
    internal enum Purpose: Sendable {
        /// The pass behind the live overlay and its count pill, run on every navigation.
        case live

        /// The pass behind the report screen, run when the developer asks for one.
        case report
    }

    /// The checks a live pass leaves to the report.
    ///
    /// Contrast, and contrast only, because contrast is the only check that reads pixels. Getting
    /// those pixels means `drawHierarchy(in:afterScreenUpdates: true)` over the whole window — a
    /// forced full re-render on the main thread, measured at 436ms of an 800ms pass on a real
    /// screen. Live mode takes a pass on every navigation, so the developer paid that every time
    /// they moved, for a check whose answer they were not looking at yet.
    ///
    /// Missing labels and touch targets read the accessibility tree and geometry. They need no
    /// pixels, no snapshot, and no budget beyond the walk itself, which is why they are the two
    /// that stay on the path that runs unasked.
    ///
    /// This is deliberately *not* the same set as ``checksNeedingAnUncoveredScreen``, even though
    /// both happen to hold contrast alone: that one is about whether an answer would be *honest*,
    /// this one is about whether it can be *afforded*. A future check that reads pixels through
    /// something other than a window snapshot would belong to one and not the other.
    internal nonisolated static let checksDeferredToTheReport: Set<AccessibilityCheck> = [.contrast]

    /// Which of `enabled` a pass taken for `purpose` actually runs.
    ///
    /// Deferring a check to the report is not a way of switching it back on: a check the developer
    /// has turned off is absent from `enabled` and is therefore in neither pass.
    ///
    /// - Parameters:
    ///   - purpose: Why the pass is being taken.
    ///   - enabled: The checks the developer has switched on.
    /// - Returns: The checks to run.
    internal nonisolated static func checks(for purpose: Purpose,
                                            from enabled: Set<AccessibilityCheck>) -> Set<AccessibilityCheck> {
        switch purpose {
        case .live: return enabled.subtracting(checksDeferredToTheReport)
        case .report: return enabled
        }
    }

    /// How long a pass taken for `purpose` may hold the main thread.
    ///
    /// - Parameter purpose: Why the pass is being taken.
    /// - Returns: The budget, in seconds — see ``AccessibilityAuditor/budget`` and
    ///   ``AccessibilityAuditor/reportBudget`` for why they are different numbers.
    internal nonisolated static func budget(for purpose: Purpose) -> TimeInterval {
        switch purpose {
        case .live: return AccessibilityAuditor.budget
        case .report: return AccessibilityAuditor.reportBudget
        }
    }

    /// Whether a pass running `checks` has to rasterise the window.
    ///
    /// The single most expensive thing a pass does, and it exists for one check. Asking this as a
    /// question of the *checks* rather than of the purpose is what makes "contrast switched off"
    /// and "contrast deferred" cost the same nothing: neither builds a sampler.
    ///
    /// - Parameter checks: The checks the pass is about to run.
    /// - Returns: `true` only when something in `checks` needs pixels.
    internal nonisolated static func needsAWindowSnapshot(checks: Set<AccessibilityCheck>) -> Bool {
        !checks.intersection(checksDeferredToTheReport).isEmpty
    }

    /// Whether the audit is allowed to look at this build's screen at all.
    ///
    /// Two builds it must refuse, for opposite reasons.
    ///
    /// A **test** build, because a test's `UIWindow` is a fabricated one with no relation to the
    /// app the developer is actually debugging: walking it would either report meaningless
    /// findings about test scaffolding or waste time on a window no developer will ever look at
    /// through this overlay.
    ///
    /// An **App Store** build, because this is the one Scyther feature that reads the user's
    /// screen as pixels. Every other entry point into the audit is already gated: `start()`
    /// returns early on an App Store build, and `InterfaceToolkit.instance` is never constructed
    /// otherwise. The hole is `Scyther.start(allowProductionBuilds: true)` — a documented,
    /// supported option — combined with ``liveEnabled``, which persists in the
    /// `com.scyther.settings` suite and survives sign-out and a standard-defaults clear by design.
    /// A host that shipped both would rasterise real users' screens every half-second. So the
    /// audit carries its own belt-and-braces guard, in the shape ``TouchVisualiserConfiguration``
    /// already uses for its logging: an App Store build refuses regardless of what is persisted.
    ///
    /// Split out as a pure function of two booleans because neither can be faked in the test host
    /// — `isTestCase` is unconditionally `true` there and `isAppStore` unconditionally `false` —
    /// so a test going in through ``auditKeyWindow()`` could never reach, let alone fail on, the
    /// App Store branch.
    ///
    /// - Parameters:
    ///   - isTestCase: Whether the process is running under XCTest, per ``AppEnvironment/isTestCase``.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    /// - Returns: `true` only when the screen may be walked and snapshotted.
    internal nonisolated static func canAuditKeyWindow(isTestCase: Bool, isAppStore: Bool) -> Bool {
        !isTestCase && !isAppStore
    }

    /// Which of `enabled` ran but could measure nothing, because the window could not be
    /// snapshotted.
    ///
    /// Contrast is the only check that needs pixels, and `drawHierarchy(in:afterScreenUpdates:)`
    /// can decline to produce them — for a window the system has never presented, or for content
    /// iOS refuses to let anything capture. Scyther used to answer that by falling back to
    /// `CALayer.render(in:)`, which is not subject to those refusals and so rasterised secure text
    /// entry along with everything else. The fallback is gone, which means the failure is now
    /// real and has to be reported: with no pixels, every element reads as one flat colour,
    /// ``ContrastAnalyser/measure(pixels:)`` returns `nil` for each, and an unmeasured screen
    /// would otherwise be reported as a clean one.
    ///
    /// The result feeds ``AccessibilityAuditor/Result/checksUnmeasurable`` rather than
    /// ``AccessibilityAuditor/Result/checksSkippedWhileCovered``, which is where it used to land.
    /// Both buckets say "Scyther did not answer this", but they say *why* differently, and the
    /// covered bucket's reason — "while Scyther is covering the app" — is simply untrue of a
    /// capture that failed on a screen with nothing of Scyther's on it. A wrong reason sends a
    /// developer to dismiss a menu that is not there.
    ///
    /// - Parameters:
    ///   - enabled: The checks that would otherwise run.
    ///   - didCaptureWindow: Whether the snapshot succeeded, per
    ///     ``WindowContrastSampler/didCaptureWindow``.
    /// - Returns: The checks that could measure nothing, which is empty whenever the snapshot
    ///   succeeded.
    internal nonisolated static func checksUnmeasurableWithoutASnapshot(from enabled: Set<AccessibilityCheck>,
                                                                       didCaptureWindow: Bool) -> Set<AccessibilityCheck> {
        guard !didCaptureWindow else { return [] }
        return enabled.intersection(checksNeedingAnUncoveredScreen)
    }

    /// Which of `enabled` read some of what they were asked about, but not all of it.
    ///
    /// Contrast only, because it is the only check that reads pixels; the other two read the
    /// accessibility tree, where there is no such thing as a candidate it could not look at.
    ///
    /// **This is coverage, not a verdict.** The rule it replaces declared the whole check
    /// unmeasurable — banner, no tick, and the report worded as though nothing had been read —
    /// whenever fewer than half its candidates could be measured. Combined with the analyser's
    /// (correct) refusal of a crop it cannot trust — a gradient, a photograph, a glyph it only
    /// caught at partial coverage — that threshold threw away real findings' standing: a screen
    /// where contrast measured a handful of elements and *found a genuine defect* was described in
    /// the same words as one where the capture had failed outright. A measurement that was made is
    /// a fact about the app whatever fraction of its neighbours could not be made, so the check now
    /// reports what it found and says separately how much of the screen it read.
    ///
    /// "Could not measure" is left to the one case that really is an absence of any answer —
    /// nothing measured at all — which ``AccessibilityAuditor/audit(root:checks:sampler:checksSkippedWhileCovered:checksUnmeasurable:deadline:)``
    /// raises for itself from the same counts.
    ///
    /// A screen every element of which was read is silent here, and so is a screen with nothing to
    /// measure: neither has anything missing from its report.
    ///
    /// The counts come from ``AccessibilityAuditor/Result/contrastCandidates`` and
    /// ``AccessibilityAuditor/Result/contrastMeasurements`` — the pass's own tally, one per element,
    /// taken from the same call the findings came from. They are deliberately not re-derived from a
    /// probe of the sampler's crops: a probe answers a slightly different question from the
    /// analyser, and this rule's whole job is to say what the *report* may claim about what the
    /// analyser did.
    ///
    /// - Parameters:
    ///   - enabled: The checks that ran.
    ///   - candidates: How many elements contrast was asked about.
    ///   - measured: How many of those it could actually read.
    /// - Returns: The checks that read part of the screen, which is at most `[.contrast]`.
    internal nonisolated static func checksPartiallyMeasured(from enabled: Set<AccessibilityCheck>,
                                                            candidates: Int,
                                                            measured: Int) -> Set<AccessibilityCheck> {
        guard enabled.contains(.contrast), candidates > 0 else { return [] }
        guard measured > 0, measured < candidates else { return [] }
        return [.contrast]
    }

    /// Audits the key window right now.
    ///
    /// Returns an empty result — no findings, no truncation, no checks run — on any build that
    /// may not be looked at; see ``canAuditKeyWindow(isTestCase:isAppStore:)``.
    ///
    /// A check that cannot be measured honestly from here is not measured at all: see
    /// ``checksNeedingAnUncoveredScreen`` and ``checksUnmeasurableWithoutASnapshot(from:didCaptureWindow:)``.
    /// It is reported as skipped rather than silently dropped, so the report can say why — a
    /// contrast ratio invented by Scyther's own dimming, or by a snapshot that never happened, is
    /// worse than an admitted gap.
    ///
    /// - Parameter purpose: Why the pass is being taken — see ``Purpose``. A live pass runs missing
    ///   labels and touch targets and takes no snapshot at all; a report pass runs everything the
    ///   developer has switched on.
    /// - Returns: The audit's findings, whether the walk was truncated, which checks ran, which
    ///   were skipped because Scyther was covering the app, and which ran but could measure
    ///   nothing.
    @MainActor
    func auditKeyWindow(purpose: Purpose) -> AccessibilityAuditor.Result {
        guard Self.canAuditKeyWindow(isTestCase: AppEnvironment.isTestCase,
                                     isAppStore: AppEnvironment.isAppStore) else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }
        guard let window = Self.keyWindow else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }
        return audit(window: window, purpose: purpose)
    }

    /// Audits `window` for `purpose`.
    ///
    /// Split out of ``auditKeyWindow(purpose:)`` because that method refuses to do anything at all
    /// under a test — see ``canAuditKeyWindow(isTestCase:isAppStore:)`` — which left the whole
    /// shape of a pass, including the decision this wave is about, as the one part of the audit no
    /// test could reach. Everything expensive or conditional lives here, over a window a test can
    /// hand in, and behind the ``makeContrastSource`` and ``now`` seams a test can replace.
    ///
    /// - Parameters:
    ///   - window: The window to walk and, for a report pass, to snapshot.
    ///   - purpose: Why the pass is being taken.
    /// - Returns: What the pass found.
    @MainActor
    internal func audit(window: UIWindow, purpose: Purpose) -> AccessibilityAuditor.Result {
        let wanted = Self.checks(for: purpose, from: enabledChecks)
        let skipped = Self.checksSkippedWhileCovered(from: wanted,
                                                     isCovering: ScytherPresentation.isCoveringScreen)
        let checks = wanted.subtracting(skipped)

        // The pass's clock starts here, before the snapshot rather than after it, and is read again
        // the moment the snapshot returns. Capturing the window is
        // `drawHierarchy(afterScreenUpdates: true)` — a forced full re-render of the whole window on
        // the main thread, and the single most expensive thing a pass does. Starting the clock
        // before it is not enough on its own: nothing can interrupt a capture once it has begun, so
        // the budget's job is to notice afterwards that it is gone and stop rather than spend a
        // second helping of it on the walk.
        var auditor = AccessibilityAuditor()
        auditor.now = now
        let deadline = now().addingTimeInterval(Self.budget(for: purpose))

        // Built inside the `if`, and dropped the moment the capture is known to have failed, so
        // the snapshot's bitmap is the only one alive at any moment and does not outlive a pass
        // it cannot be used for. A pass that runs no check needing pixels never gets here at all,
        // which is the whole of what makes a live pass cheap.
        var sampler: ContrastSampling?
        var unmeasurable: Set<AccessibilityCheck> = []
        if Self.needsAWindowSnapshot(checks: checks) {
            let source = makeContrastSource(window)
            unmeasurable = Self.checksUnmeasurableWithoutASnapshot(from: checks,
                                                                   didCaptureWindow: source.didCaptureWindow)
            sampler = unmeasurable.isEmpty ? source.sampler : nil
        }

        // Contrast stays in `checks` even when there is nothing to sample: it *ran*, and was
        // reported as unmeasurable, which is a different claim from either "it found nothing" or
        // "you switched it off". With no sampler it simply measures nothing, so no finding can
        // come out of a bitmap that does not exist.
        let result = auditor.audit(root: window,
                                   checks: checks,
                                   sampler: sampler,
                                   checksSkippedWhileCovered: skipped,
                                   checksUnmeasurable: unmeasurable,
                                   deadline: deadline)

        // How much of the screen the check read is carried on the result as two counts and read by
        // the report — see ``checksPartiallyMeasured(from:candidates:measured:)``. It used to be
        // turned into a verdict here, by rewriting the result to call contrast unmeasurable
        // whenever it had read fewer than half its candidates, which discarded the standing of
        // every finding it *had* made. Nothing is rewritten now: the pass says what it measured and
        // what it could not, and the report says both.
        return result
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
