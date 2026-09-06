//
//  AccessibilityAuditViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation
import SwiftUI

/// Drives the accessibility audit's report screen.
///
/// The audit itself is injected as a closure — ``init(run:)`` — rather than this type calling
/// ``AccessibilityAudit/auditKeyWindow()`` directly. A view model that reaches into a singleton
/// for its data can only be tested by standing up a real `UIWindow`; one that is handed a
/// closure can be tested with a canned ``AccessibilityAuditor/Result`` and no window at all,
/// which is how every test in `AccessibilityAuditViewModelTests` works. The screen itself passes
/// `{ AccessibilityAudit.instance.auditKeyWindow() }`.
///
/// Two things this type deliberately does *not* do:
/// - It never re-audits on its own. ``load()`` runs the audit once and ``groups`` stays exactly
///   as that pass left it until ``rerun()`` is called — see that method's own documentation for
///   why a report that moves while it is being read is worse than a stale one.
/// - It never hides that a check did not run. ``skippedChecks`` exists so an empty ``groups``
///   can mean "nothing was wrong" or "nothing was looked at" and the screen can tell those apart.
///
/// The settings toggles the report screen shows above its findings — live mode and the three
/// per-check switches — are mirrored here as `@Published` state (``liveEnabled``,
/// ``checkBinding(for:)``) the same way every other Scyther settings screen mirrors its
/// singleton, e.g. `TouchVisualiserViewModel` and `GridOverlayViewModel`. This is separate from
/// the injected `run` closure: the toggles read and write ``AccessibilityAudit/instance``
/// directly because they are simple, synchronous settings, where the audit itself is the one
/// piece of behaviour worth swapping out for a test.
@MainActor
final class AccessibilityAuditViewModel: ViewModel {
    /// One check's findings, in the order the report shows them.
    ///
    /// A flat, ungrouped list would bury a lone `.error` among a screen of `.warning` rows from
    /// whichever check happened to walk the tree first. Grouping by check, and sorting each
    /// group's own findings with errors first, means the report always leads with what is
    /// actually broken.
    struct Group: Identifiable {
        /// Which check produced every finding in this group.
        let check: AccessibilityCheck

        /// This check's findings, errors before warnings.
        let findings: [AccessibilityFinding]

        /// One group per check, so the check itself is a stable, unique identity.
        var id: AccessibilityCheck { check }
    }

    /// Runs one pass of the audit. Injected so this type never has to touch a real window — see
    /// the type-level documentation.
    private let run: @MainActor () -> AccessibilityAuditor.Result

    /// Whether ``load()`` has already run once.
    ///
    /// Without this, a view redrawing and calling ``load()`` again — SwiftUI does this more
    /// often than a caller expects — would silently replace the report the developer is reading
    /// with a fresh pass. Only ``rerun()`` is allowed to do that, and only because it is asked
    /// for explicitly.
    private var hasLoaded = false

    /// The current report's findings, grouped by check and ordered ``AccessibilityCheck/allCases``
    /// first, skipping any check with nothing to show.
    @Published private(set) var groups: [Group] = []

    /// Whether the walk that produced ``groups`` was stopped early by
    /// ``AccessibilityAuditor``'s node or depth cap.
    ///
    /// A truncated walk that presents itself as a complete one would tell the developer their
    /// screen is clean when the audit simply never reached the rest of it.
    @Published private(set) var didHitLimit: Bool = false

    /// Every check that did not run in the current report, because a developer switched it off
    /// before running the audit.
    ///
    /// Named explicitly, rather than left for the developer to infer from an empty ``groups``,
    /// because "no findings" and "nothing was looked at" must never read the same way.
    @Published private(set) var skippedChecks: [AccessibilityCheck] = []

    /// Every check that was switched on and still did not run, because Scyther's own UI was
    /// covering the app when the pass was made.
    ///
    /// Kept apart from ``skippedChecks`` because the screen has to say something different about
    /// each: one is a setting the developer chose and can undo from the toggles above, the other
    /// is a measurement Scyther declined to make because it would have measured its own dimming
    /// of the app rather than the app. Reporting the second as the first would tell a developer
    /// they had turned contrast off when they had not.
    @Published private(set) var checksSkippedWhileCovered: [AccessibilityCheck] = []

    /// Whether a pass is in flight right now, so the screen can show a progress indicator
    /// instead of an empty report it does not yet have an answer for.
    ///
    /// "No issues found" and "not finished looking" must not read the same way, exactly as
    /// ``skippedChecks`` exists so "nothing was wrong" and "nothing was looked at" do not.
    @Published private(set) var isRunning = false

    /// Mirrors ``AccessibilityAudit/liveEnabled`` for the toggle at the top of the report screen.
    ///
    /// Writing this writes straight through to the singleton, exactly like
    /// `TouchVisualiserViewModel.visualiseTouches`, so switching it on starts drawing boxes over
    /// the running app immediately rather than waiting for the next time this screen loads.
    @Published var liveEnabled: Bool {
        didSet {
            AccessibilityAudit.instance.liveEnabled = liveEnabled
        }
    }

    /// Mirrors ``AccessibilityAudit/isEnabled(_:)`` for every ``AccessibilityCheck``, keyed by
    /// check, so ``checkBinding(for:)`` has `@Published` state to hand `Toggle` rather than
    /// re-reading `UserDefaults` on every redraw.
    @Published private var checkEnabled: [AccessibilityCheck: Bool]

    /// Called when a row is tapped, so the screen can forward the flash to the live overlay.
    ///
    /// Left as a plain closure rather than this type reaching into `InterfaceToolkit` itself: the
    /// view model has no business knowing there is a UIKit overlay behind it, only that *something*
    /// wants to know which finding was tapped. The screen wires this to
    /// `InterfaceToolkit.instance.accessibilityAuditView.flash(_:)`.
    var onFlash: ((AccessibilityFinding) -> Void)?

    /// Creates a report view model over `run`.
    ///
    /// - Parameter run: Performs one pass of the audit. Called once by ``load()`` and once per
    ///   call to ``rerun()`` — never on a timer, never in the background.
    init(run: @escaping @MainActor () -> AccessibilityAuditor.Result) {
        self.run = run
        self.liveEnabled = AccessibilityAudit.instance.liveEnabled
        self.checkEnabled = Dictionary(
            uniqueKeysWithValues: AccessibilityCheck.allCases.map { ($0, AccessibilityAudit.instance.isEnabled($0)) }
        )
        super.init()
    }

    /// Runs the audit once and stores its result, unless ``load()`` has already run.
    ///
    /// Safe to call from `.onFirstAppear` every time the screen appears: only the very first
    /// call after this instance was created does anything, so navigating back to an
    /// already-loaded report finds it exactly as it was left. `hasLoaded` is raised before the
    /// suspension in ``performPass()``, not after it, so a second `.onFirstAppear` arriving while
    /// the first pass is still in flight cannot start a second one.
    ///
    /// `async` on purpose — see ``performPass()`` for why the walk must not happen inside the
    /// caller's own turn on the main actor.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await performPass()
    }

    /// Runs ``load()`` when the screen first appears, per the ``ViewModel`` lifecycle every
    /// other Scyther screen uses.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await load()
    }

    /// Runs the audit again and replaces the current report with its result.
    ///
    /// The only way ``groups``, ``didHitLimit`` and ``skippedChecks`` change after the first
    /// ``load()`` — see the type-level documentation for why a report otherwise stays frozen.
    func rerun() async {
        await performPass()
    }

    /// Publishes that a pass is running, gives the main actor back, then runs it and publishes
    /// the result.
    ///
    /// The `Task.yield()` in the middle is the whole point of this method. The audit reads UIKit
    /// accessibility, so it can only run on the main actor; `.onFirstAppear` starts its work in a
    /// `Task` that begins on the main actor *during* the navigation push, so a pass that runs
    /// straight through holds the main thread for its whole duration and the push never animates
    /// — which is why a slow walk read to a developer as a frozen app rather than a slow screen.
    /// Yielding first lets the transition finish and the spinner appear, and only then spends
    /// whatever the walk costs.
    ///
    /// This does not loosen the frozen-report contract: still one `run()` per call, still nothing
    /// re-walking on its own — the pass is merely a turn later than it used to be.
    private func performPass() async {
        isRunning = true
        await Task.yield()
        let result = run()
        apply(result)
        isRunning = false
    }

    /// Forwards `finding` to ``onFlash``, so tapping its row asks the overlay to flash its box.
    ///
    /// - Parameter finding: The finding whose row was tapped.
    func flash(_ finding: AccessibilityFinding) {
        onFlash?(finding)
    }

    /// Whether `check` is currently switched on, per ``checkEnabled``.
    ///
    /// - Parameter check: The check to read.
    /// - Returns: `true` when the check is enabled.
    func isChecked(_ check: AccessibilityCheck) -> Bool {
        checkEnabled[check] ?? true
    }

    /// A two-way `Binding` for `check`'s toggle, reading and writing both ``checkEnabled`` and
    /// ``AccessibilityAudit/instance`` in one step.
    ///
    /// Handing the screen a `Binding` rather than a getter and a setter keeps `AccessibilityAuditView`
    /// down to a plain `Toggle(check.title, isOn: viewModel.checkBinding(for: check))` for each
    /// check, matching how the rest of Scyther's settings screens bind their toggles.
    ///
    /// - Parameter check: The check the toggle controls.
    /// - Returns: A binding backed by ``checkEnabled``.
    func checkBinding(for check: AccessibilityCheck) -> Binding<Bool> {
        Binding(
            get: { self.isChecked(check) },
            set: { newValue in
                self.checkEnabled[check] = newValue
                AccessibilityAudit.instance.setEnabled(check, to: newValue)
            }
        )
    }

    /// Replaces ``groups``, ``didHitLimit``, ``skippedChecks`` and ``checksSkippedWhileCovered``
    /// with what `result` found.
    ///
    /// Both lists of skipped checks are ordered by ``AccessibilityCheck/allCases`` rather than
    /// left in whatever order a `Set` iterates in, so the screen names them the same way twice
    /// running.
    ///
    /// - Parameter result: One pass of the audit.
    private func apply(_ result: AccessibilityAuditor.Result) {
        let findingsByCheck = Dictionary(grouping: result.findings, by: \.check)
        groups = AccessibilityCheck.allCases.compactMap { check in
            guard let findings = findingsByCheck[check], !findings.isEmpty else { return nil }
            return Group(check: check, findings: findings.sorted { $0.severity > $1.severity })
        }
        didHitLimit = result.didHitLimit
        checksSkippedWhileCovered = AccessibilityCheck.allCases.filter(result.checksSkippedWhileCovered.contains)
        // A check skipped because Scyther was in the way is not a check the developer switched
        // off, and must not be listed as one.
        skippedChecks = AccessibilityCheck.allCases.filter {
            !result.checksRun.contains($0) && !result.checksSkippedWhileCovered.contains($0)
        }
    }
}
