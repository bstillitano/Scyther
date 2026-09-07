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

    /// The share of its candidates a check has to have measured before it counts as having run.
    ///
    /// Half. The line has to be drawn somewhere and there is no standard to cite, so it is drawn at
    /// the point where the sentence "this check ran" stops being defensible: below half, most of
    /// what the check looked at was never read, and what came back is a minority report about a
    /// screen rather than a result for it. Drawing it any stricter would put a banner on every
    /// screen with a photograph or a video layer on it, where a real minority of elements genuinely
    /// cannot be measured and the rest were measured perfectly well.
    ///
    /// The rule this replaces was "every single candidate failed", which meant one successful
    /// measurement out of two hundred left the check counted as having run, ``isComplete`` true, and
    /// a green tick over a screen 199 of whose elements nobody looked at.
    internal nonisolated static let measuredFractionForACheckToHaveRun: Double = 0.5

    /// Which of `enabled` looked at candidates and read too few of them to call the check run.
    ///
    /// Contrast only, because it is the only check that reads pixels; the other two read the
    /// accessibility tree, where there is no such thing as a candidate it could not look at.
    ///
    /// A screen with nothing to measure — no text, no buttons — is silent rather than unmeasurable.
    /// "There was nothing to read" and "there was something and it could not be read" are different
    /// facts, and only the second says anything is missing from the report.
    ///
    /// - Parameters:
    ///   - enabled: The checks that ran.
    ///   - candidates: How many elements contrast was asked about.
    ///   - measured: How many of those it could actually read.
    /// - Returns: The checks that did not measure enough of the screen to have run.
    internal nonisolated static func checksUnmeasurableFromPartialMeasurement(from enabled: Set<AccessibilityCheck>,
                                                                             candidates: Int,
                                                                             measured: Int) -> Set<AccessibilityCheck> {
        guard enabled.contains(.contrast), candidates > 0 else { return [] }
        let fraction = Double(measured) / Double(candidates)
        guard fraction < measuredFractionForACheckToHaveRun else { return [] }
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
    /// - Returns: The audit's findings, whether the walk was truncated, which checks ran, which
    ///   were skipped because Scyther was covering the app, and which ran but could measure
    ///   nothing.
    @MainActor
    func auditKeyWindow() -> AccessibilityAuditor.Result {
        guard Self.canAuditKeyWindow(isTestCase: AppEnvironment.isTestCase,
                                     isAppStore: AppEnvironment.isAppStore) else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }
        guard let window = Self.keyWindow else {
            return AccessibilityAuditor.Result(findings: [], didHitLimit: false, checksRun: [])
        }

        let skipped = Self.checksSkippedWhileCovered(from: enabledChecks,
                                                    isCovering: ScytherPresentation.isCoveringScreen)
        let checks = enabledChecks.subtracting(skipped)

        // The pass's clock starts here, before the snapshot rather than after it. Capturing the
        // window is `drawHierarchy(afterScreenUpdates: true)` — a forced full re-render of the
        // whole window on the main thread, and the single most expensive thing a pass does. A
        // budget that only began once the walk started would exclude it from the one bound that
        // exists on how long the app is frozen.
        let auditor = AccessibilityAuditor()
        let deadline = auditor.now().addingTimeInterval(AccessibilityAuditor.budget)

        // Built inside the `if`, and dropped the moment the capture is known to have failed, so
        // the snapshot's bitmap is the only one alive at any moment and does not outlive a pass
        // it cannot be used for.
        var sampler: ContrastSampling?
        var unmeasurable: Set<AccessibilityCheck> = []
        if checks.contains(.contrast) {
            let windowSampler = WindowContrastSampler(window: window)
            unmeasurable = Self.checksUnmeasurableWithoutASnapshot(from: checks,
                                                                   didCaptureWindow: windowSampler.didCaptureWindow)
            sampler = unmeasurable.isEmpty ? windowSampler : nil
        }

        // Wrapped so the pass can be asked afterwards how much of the screen it actually read.
        // The auditor knows whether *every* candidate failed; it has no notion of "nearly every
        // one did", and that is the case that used to come back as a clean, complete report.
        let counting = sampler.map(MeasurementCountingSampler.init(wrapping:))

        // Contrast stays in `checks` even when there is nothing to sample: it *ran*, and was
        // reported as unmeasurable, which is a different claim from either "it found nothing" or
        // "you switched it off". With no sampler it simply measures nothing, so no finding can
        // come out of a bitmap that does not exist.
        let result = auditor.audit(root: window,
                                   checks: checks,
                                   sampler: counting,
                                   checksSkippedWhileCovered: skipped,
                                   checksUnmeasurable: unmeasurable,
                                   deadline: deadline)

        guard let counting else { return result }
        let partial = Self.checksUnmeasurableFromPartialMeasurement(from: checks,
                                                                    candidates: counting.candidates,
                                                                    measured: counting.measured)
        guard !partial.isEmpty else { return result }
        return AccessibilityAuditor.Result(findings: result.findings,
                                           didHitLimit: result.didHitLimit,
                                           checksRun: result.checksRun,
                                           checksSkippedWhileCovered: result.checksSkippedWhileCovered,
                                           checksUnmeasurable: result.checksUnmeasurable.union(partial))
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

/// A ``ContrastSampling`` that passes every crop straight through and counts how many of them
/// carried a measurement.
///
/// The count is the only way ``AccessibilityAudit/auditKeyWindow()`` can tell a check that read the
/// screen from one that read almost none of it. ``AccessibilityAuditor`` already counts candidates
/// and measurements for its own all-or-nothing rule, but it does not publish them, and its file is
/// the wrong place for a threshold about what the *report* may claim.
///
/// ## Why the readability test is taken on a subsample
///
/// A crop is unmeasurable when ``ContrastAnalyser/measure(pixels:)`` returns `nil`: either there
/// are no pixels, or everything in the region is within a hair of one colour. Answering that
/// exactly means linearising every pixel — three `pow` calls each, twelve thousand per crop — and
/// the auditor is about to do precisely that work again a line later, so asking exactly would
/// double the most expensive part of the pass on every screen, for a statistic.
///
/// Instead the question is put to a strided subsample of at most ``probePixels`` pixels, through
/// the same ``ContrastAnalyser/measure(pixels:)`` the real answer comes from, so the two can never
/// drift apart in their idea of what "readable" means. Flatness is the property being detected and
/// a flat crop is flat everywhere, so a sixteenth of it answers the same way as all of it; the cost
/// is a sixteenth of one measurement per candidate.
private final class MeasurementCountingSampler: ContrastSampling {
    /// How many pixels the readability probe looks at.
    ///
    /// 256 — a 16 × 16 grid over a crop the sampler has already capped at 64 × 64. Enough that a
    /// crop with glyphs in it lands on ink, few enough that the probe costs a fraction of the
    /// measurement it is standing in for.
    private static let probePixels = 256

    /// The sampler doing the real work.
    private let wrapped: ContrastSampling

    /// How many elements contrast was asked about.
    private(set) var candidates = 0

    /// How many of those came back with something to measure.
    private(set) var measured = 0

    /// Wraps `sampler`.
    ///
    /// - Parameter sampler: The sampler to pass every crop through to.
    init(wrapping sampler: ContrastSampling) {
        self.wrapped = sampler
    }

    /// Returns `wrapped`'s pixels for `frame`, having noted whether they carried a measurement.
    ///
    /// - Parameter frame: The region in window coordinates.
    /// - Returns: Exactly what `wrapped` returned, unchanged.
    func samples(in frame: CGRect) -> [RGB] {
        let pixels = wrapped.samples(in: frame)
        candidates += 1
        if Self.carriesAMeasurement(pixels) { measured += 1 }
        return pixels
    }

    /// Whether `pixels` has two colours in it to measure between.
    ///
    /// - Parameter pixels: One crop's pixels.
    /// - Returns: `true` when a measurement could be recovered from them.
    private static func carriesAMeasurement(_ pixels: [RGB]) -> Bool {
        guard !pixels.isEmpty else { return false }
        let step = max(1, pixels.count / probePixels)
        guard step > 1 else { return ContrastAnalyser.measure(pixels: pixels) != nil }

        var probe: [RGB] = []
        probe.reserveCapacity(pixels.count / step + 1)
        var index = 0
        while index < pixels.count {
            probe.append(pixels[index])
            index += step
        }
        return ContrastAnalyser.measure(pixels: probe) != nil
    }
}
#endif
