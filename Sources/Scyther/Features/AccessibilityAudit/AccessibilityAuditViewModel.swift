//
//  AccessibilityAuditViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation
import SwiftUI

/// One pass of the audit, with the moment it was taken.
///
/// The report opens onto the live overlay's last pass rather than taking one of its own — see
/// ``AccessibilityAuditViewModel/seed`` — and that pass is, by construction, older than the screen
/// reading it: no pass can run while Scyther covers the app, so the seed always predates the moment
/// the developer opened the report. Without the timestamp there was nothing on the screen, and
/// nothing in the model, able to say so; a report of twelve findings for rows that had been
/// scrolled off half a minute earlier presented itself as the current state of the app.
struct SeededAccessibilityPass: Sendable {
    /// What the pass found.
    let result: AccessibilityAuditor.Result

    /// When the pass was taken. Everything after this moment — a scroll, a table reload, a cell
    /// expanding — is not in ``result``.
    let takenAt: Date

    /// Creates a seeded pass.
    ///
    /// - Parameters:
    ///   - result: What the pass found.
    ///   - takenAt: When it was taken.
    init(result: AccessibilityAuditor.Result, takenAt: Date) {
        self.result = result
        self.takenAt = takenAt
    }
}

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
/// - It never hides that a check did not run. ``checksRun`` and the three lists worked out from
///   it — ``switchedOffChecks``, ``checksSkippedWhileCovered`` and ``checksUnmeasurable`` — exist so
///   an empty ``groups`` can mean "nothing was wrong", "nothing was looked at", or one of two
///   different kinds of "this could not be measured", and the screen can tell all four apart.
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

    /// The pass this report should open onto, when there is a better one than it could take for
    /// itself.
    ///
    /// The live overlay's last pass, taken while nothing of Scyther's covered the app, is that
    /// better pass: it is the one the pill counted and the one whose boxes the developer tapped
    /// through to get here. A report that ran its own pass instead opened onto a *different*
    /// answer — contrast dropped, because by then the screen behind it is Scyther's — which is how
    /// a pill reading "7 issues" came to open onto "No Issues Found" under a green tick.
    ///
    /// Returns `nil` when there is no such pass, which is every case except a live report: live
    /// mode off, or the menu opened before the first debounce elapsed. ``load()`` then runs its own.
    ///
    /// It carries the moment it was taken, because a seeded pass is always older than the screen
    /// showing it — see ``SeededAccessibilityPass``.
    private let seed: @MainActor () -> SeededAccessibilityPass?

    /// The settings the toggles at the top of the report read and write.
    ///
    /// Injected rather than reached for as ``AccessibilityAudit/instance`` so a test can hand this
    /// a manager over a throwaway `UserDefaults` suite — the same seam
    /// ``AccessibilityAudit/init(defaults:)`` exists for — instead of writing a developer's real
    /// settings while asserting what the report shows. Production passes the singleton.
    private let settings: AccessibilityAudit

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

    /// Every check that actually ran in the current report.
    ///
    /// The report's other lists are all worked out against this one. An empty set means nothing was
    /// looked at at all, which the screen has to lead with differently from a screen that was fully
    /// checked and came back clean — "no findings" and "nothing was looked at" must never read the
    /// same way, and a green tick over "No Issues Found" says the first while meaning the second.
    @Published private(set) var checksRun: Set<AccessibilityCheck> = []

    /// Every check that was switched on and still did not run, because Scyther's own UI was
    /// covering the app when the pass was made.
    ///
    /// Kept apart from ``skippedChecks`` because the screen has to say something different about
    /// each: one is a setting the developer chose and can undo from the toggles above, the other
    /// is a measurement Scyther declined to make because it would have measured its own dimming
    /// of the app rather than the app. Reporting the second as the first would tell a developer
    /// they had turned contrast off when they had not.
    @Published private(set) var checksSkippedWhileCovered: [AccessibilityCheck] = []

    /// Every check that was switched on, was not skipped, ran — and still measured nothing,
    /// because the screen could not be captured.
    ///
    /// A third reason, kept apart from the other two because it means something the other two do
    /// not. ``skippedChecks`` is a setting the developer chose. ``checksSkippedWhileCovered`` is a
    /// measurement Scyther declined to make because it would have measured its own dimming, and
    /// can be had by getting Scyther out of the way. This one is neither: the check was attempted
    /// and iOS returned no pixels — a window the system has never presented, or content it refuses
    /// to let anything capture — so there is nothing the developer can switch to make it work, and
    /// nothing here says anything at all about whether their screen is fine.
    @Published private(set) var checksUnmeasurable: [AccessibilityCheck] = []

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
            settings.liveEnabled = liveEnabled
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
    /// - Parameters:
    ///   - settings: The settings the toggles read and write. Defaults to the shared singleton.
    ///   - seed: The pass this report should open onto instead of taking one of its own, or `nil`
    ///     when there is none. Defaults to none.
    ///   - run: Performs one pass of the audit. Called by ``load()`` when there is no seed, and
    ///     once per call to ``rerun()`` — never on a timer, never in the background.
    init(settings: AccessibilityAudit = .instance,
         seed: @escaping @MainActor () -> SeededAccessibilityPass? = { nil },
         run: @escaping @MainActor () -> AccessibilityAuditor.Result) {
        self.run = run
        self.seed = seed
        self.settings = settings
        self.liveEnabled = settings.liveEnabled
        self.checkEnabled = Dictionary(
            uniqueKeysWithValues: AccessibilityCheck.allCases.map { ($0, settings.isEnabled($0)) }
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
    ///
    /// Opens onto the ``seed`` pass when there is one, without running anything: see that
    /// property for why the live overlay's own last pass is a better report than one this screen
    /// could take from underneath itself.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let seeded = seed() {
            apply(seeded.result, takenAt: seeded.takenAt, predatesThisScreen: true)
            return
        }
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
    ///
    /// The guard at the top is the only thing that actually stops two passes overlapping.
    /// `.disabled(isRunning)` on the **Re-run** button cannot: `isRunning` is published from
    /// inside this method, and the render that would grey the button out has to wait for the main
    /// actor, which this pass is holding. The button therefore stays drawn as enabled for the whole
    /// of the first pass — the one that starts during the navigation push — and a tap on it used to
    /// start a second pass that ran a second full walk, published `isRunning = false` while the
    /// first was still going, and replaced ``groups`` under a developer mid-read.
    private func performPass() async {
        guard !isRunning else { return }
        isRunning = true
        await Task.yield()
        let result = run()
        apply(result, takenAt: Date(), predatesThisScreen: false)
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
                self.settings.setEnabled(check, to: newValue)
            }
        )
    }

    // MARK: - What The Screen Shows

    /// The frozen report's groups, minus any check the developer has switched off since it ran.
    ///
    /// The toggles and the report share one screen, and the toggles take effect immediately while
    /// the report stays frozen until **Re-run**. Switching Contrast off and finding a Contrast
    /// section still listed directly beneath the switch reads as a toggle that did nothing, so the
    /// section goes; ``checksAwaitingRerun`` is what says the report is now behind the settings.
    var visibleGroups: [Group] {
        groups.filter { isChecked($0.check) }
    }

    /// Every check that is switched off right now.
    ///
    /// Read from the toggles rather than from the pass, so switching one back on takes
    /// "Switched off: Contrast" off the screen in the same breath — it used to sit there
    /// contradicting the switch three rows above it.
    var switchedOffChecks: [AccessibilityCheck] {
        AccessibilityCheck.allCases.filter { !isChecked($0) }
    }

    /// Every check that is switched on now but is not in this report, and could be if it were run
    /// again.
    ///
    /// The other half of letting the toggles move under a frozen report. Without it, switching
    /// Contrast on would simply remove the sentence saying it had not run and leave a report with
    /// no contrast in it and nothing saying why. Checks that were skipped for a reason re-running
    /// will not fix — ``checksSkippedWhileCovered`` and ``checksUnmeasurable`` — are left out, since
    /// their own banners already say more about them than this would.
    var checksAwaitingRerun: [AccessibilityCheck] {
        AccessibilityCheck.allCases.filter {
            isChecked($0)
                && !checksRun.contains($0)
                && !checksSkippedWhileCovered.contains($0)
                && !checksUnmeasurable.contains($0)
        }
    }

    /// Whether this report covers the whole screen and every check the developer has switched on.
    ///
    /// The one state in which an empty report may lead with a tick and the words "No Issues
    /// Found". Everything else — a check switched off, a check Scyther declined to measure, a check
    /// that could not be measured, a walk that stopped early, a toggle switched on since the pass —
    /// means something on this screen has not been looked at, and a tick would say the opposite.
    var isComplete: Bool {
        !didHitLimit
            && switchedOffChecks.isEmpty
            && checksSkippedWhileCovered.isEmpty
            && checksUnmeasurable.isEmpty
            && checksAwaitingRerun.isEmpty
    }

    /// Whether this report is the result of nothing having been checked at all.
    ///
    /// Every check off, or every check refused, produces exactly the same empty ``groups`` as a
    /// clean screen. They are not the same thing and the screen must not open with the same
    /// sentence for both.
    var nothingWasChecked: Bool {
        checksRun.isEmpty
    }

    /// When the pass this report is showing was taken, or `nil` when it has not run one yet.
    ///
    /// Every pass is timestamped, seeded or not, so the screen never has to guess how old the thing
    /// it is showing is. It is the seeded case the timestamp exists for — see
    /// ``passPredatesThisScreen`` — but a report that timestamped only *some* of its passes would
    /// have to say "unknown" for the rest, which is a worse answer than a true one.
    @Published private(set) var passTakenAt: Date?

    /// Whether this report is showing a pass that was already over before this screen opened.
    ///
    /// True for exactly the seeded case, and that case is not an edge: the report opens onto the
    /// live overlay's last pass — see ``seed`` — and no pass can run while Scyther covers the app,
    /// so the seed is always older than the tap that opened the report. Everything that changed the
    /// screen in between and did not change which view controllers are showing — a scroll, a table
    /// reload, a cell expanding — is missing from it, and the poll cannot see any of those. A report
    /// of twelve findings for rows that have been scrolled away is not wrong about the pass; it is
    /// wrong about *when*, and the screen has to say so.
    ///
    /// Cleared by ``rerun()``, which takes a pass of the screen as it is now.
    @Published private(set) var passPredatesThisScreen: Bool = false

    /// How many findings this report is holding back because their check has since been switched
    /// off.
    ///
    /// The toggles take effect immediately and the report stays frozen, so the two can disagree on
    /// one screen. Hiding the rows is right — a Contrast section listed directly under a Contrast
    /// switch that is off reads as a switch that did nothing — but hiding them *silently* is not:
    /// with every group hidden the report used to render "The checks that ran found nothing to
    /// report" over a pass that had found five things, and with only some hidden it simply got
    /// shorter with nothing explaining the gap.
    var hiddenFindingCount: Int {
        groups.filter { !isChecked($0.check) }.reduce(0) { $0 + $1.findings.count }
    }

    /// Which checks in this pass have findings the toggles are currently hiding.
    ///
    /// Read from ``groups`` rather than from ``switchedOffChecks``, because a check that is off and
    /// found nothing is hiding nothing and has no business being named here.
    var checksHidingFindings: [AccessibilityCheck] {
        groups.map(\.check).filter { !isChecked($0) }
    }

    /// Whether anything in this pass is being held back by the toggles.
    var isHidingFindings: Bool { hiddenFindingCount > 0 }

    /// The wording for a report that is holding findings back: how many, and which switch is
    /// holding them.
    ///
    /// Counts findings rather than groups, because the number that matters to a developer reading a
    /// report that just went from seven rows to two is the five that went.
    var hiddenFindingsDescription: String {
        let names = ListFormatter.localizedString(byJoining: checksHidingFindings.map(\.title))
        return localized("\(hiddenFindingCount) findings in this pass are hidden. Switched off since it ran: \(names).")
    }

    // MARK: - Copy

    /// The empty state's headline. See ``emptyStateDescription`` for the four cases.
    ///
    /// Hiding is tested first because it is the most specific: a pass that found things and is
    /// showing none of them is not a pass that found nothing, whatever else is true of it.
    var emptyStateTitle: String {
        if isHidingFindings { return localized("Findings Hidden") }
        if nothingWasChecked { return localized("Nothing Was Checked") }
        if isComplete { return localized("No Issues Found") }
        return localized("No Issues In What Was Checked")
    }

    /// The empty state's symbol.
    ///
    /// `checkmark.circle` is reserved for the one case that passed everything. A report that is
    /// hiding findings gets `eye.slash`, the same symbol the covered banner uses, because that is
    /// what it is: something real, not shown. Everything else gets `questionmark.circle`, which is
    /// what an unanswered question looks like — the point being that it is not a result about the
    /// app.
    var emptyStateSymbol: String {
        if isHidingFindings { return "eye.slash" }
        return isComplete ? "checkmark.circle" : "questionmark.circle"
    }

    /// The empty state's explanation.
    ///
    /// Four cases, in order of how specific they are:
    ///
    /// - **Findings hidden.** The pass found things and the toggles are hiding all of them. This
    ///   branch exists because the screen used to fall through to the next one and assert that the
    ///   checks which ran had found nothing to report, about a pass that had found five things.
    /// - **Nothing ran.** Every check switched off, or every check refused.
    /// - **Something ran, but not everything.** A check switched off, skipped, or unmeasurable, or
    ///   a walk a cap stopped early. The part that was checked was clean; the rest was never
    ///   reached.
    /// - **Everything ran and found nothing.** The one case that has earned a tick — and even it
    ///   says what the audit cannot see, because a developer must not be able to read a clean
    ///   report as "my app is accessible".
    ///
    /// It names the checks the developer switched off, because nothing else on the screen does. It
    /// does not name the checks Scyther skipped or could not measure, or say that the walk stopped
    /// early: those each have their own banner, in more detail than belongs under a headline.
    var emptyStateDescription: String {
        if isHidingFindings { return hiddenFindingsDescription }
        let switchedOff = switchedOffChecks
        if nothingWasChecked {
            guard !switchedOff.isEmpty else { return localized("No check on this screen could be run.") }
            let names = ListFormatter.localizedString(byJoining: switchedOff.map(\.title))
            return localized("No check ran. Switched off: \(names).")
        }
        if !switchedOff.isEmpty {
            let names = ListFormatter.localizedString(byJoining: switchedOff.map(\.title))
            return localized("The checks that ran found nothing to report. Switched off: \(names).")
        }
        if !isComplete {
            return localized("The checks that ran found nothing to report.")
        }
        return localized("No issues found by the checks that ran. The audit only sees what your app exposed to accessibility, cannot judge whether a label is meaningful, and only sees this screen as it is now.")
    }

    /// The wording for a report describing the app as it was before this screen opened.
    ///
    /// Says what is missing rather than only that time has passed: "older" is not actionable,
    /// "anything you have scrolled past since is not in here" is.
    var stalePassDescription: String {
        localized("This is the last pass taken over your app, from before this screen opened. Anything that changed since — a scroll, a reload — is not in it.")
    }

    /// The covered banner's wording: which checks were skipped, and what to switch on to have
    /// them measured against the real screen.
    ///
    /// The live-mode toggle is named through ``localized(_:comment:)`` rather than spelled out in
    /// the sentence, so a developer reading Scyther in French is pointed at the French toggle
    /// sitting a few rows above rather than at an English one that is not there.
    var coveredDescription: String {
        let names = ListFormatter.localizedString(byJoining: checksSkippedWhileCovered.map(\.title))
        let liveToggle = localized("Show Issues On Screen")
        return localized("\(names) not measured while Scyther is covering the app: the colors behind this screen are Scyther's, not your app's. Switch on \(liveToggle) to measure the real screen instead.")
    }

    /// The unmeasurable banner's wording: which checks ran without being able to measure anything,
    /// and that this says nothing about whether the screen is fine.
    /// Worded to be true of every way the measurement can fail, because ``checksUnmeasurable`` has
    /// three producers and one banner. It is raised when the window could not be captured at all,
    /// when it captured fine and every candidate came back unreadable, and when it captured fine
    /// and too few candidates could be read for the check to have run — and the old wording ("this
    /// screen could not be captured, so there were no pixels to read") is false of the second and
    /// the third. What all three share is that the check could not read enough of the screen, and
    /// that what it did not read is missing from the report rather than passing it.
    var unmeasurableDescription: String {
        let names = ListFormatter.localizedString(byJoining: checksUnmeasurable.map(\.title))
        return localized("\(names) ran but could not read enough of this screen to report on it. What it did not measure is missing from this report, not passing it.")
    }

    /// The wording for a check switched on since the pass: which one, and what to do about it.
    ///
    /// Names the **Re-run** button through ``localized(_:comment:)`` rather than spelling it out,
    /// for the same reason ``coveredDescription`` names the live toggle that way: a developer
    /// reading Scyther in German should be pointed at the German button in the toolbar above.
    var awaitingRerunDescription: String {
        let names = ListFormatter.localizedString(byJoining: checksAwaitingRerun.map(\.title))
        let rerun = localized("Re-run")
        return localized("\(names) switched on after this report was run. Tap \(rerun) to include it.")
    }

    /// Replaces ``groups``, ``didHitLimit``, ``checksRun``, ``checksSkippedWhileCovered`` and
    /// ``checksUnmeasurable`` with what `result` found.
    ///
    /// The two lists of skipped checks are ordered by ``AccessibilityCheck/allCases`` rather than
    /// left in whatever order a `Set` iterates in, so the screen names them the same way twice
    /// running.
    ///
    /// - Parameters:
    ///   - result: One pass of the audit.
    ///   - takenAt: When that pass was taken.
    ///   - predatesThisScreen: Whether the pass was already over before this screen opened, which
    ///     is true of a seeded pass and false of one this screen took for itself.
    private func apply(_ result: AccessibilityAuditor.Result,
                       takenAt: Date,
                       predatesThisScreen: Bool) {
        let findingsByCheck = Dictionary(grouping: result.findings, by: \.check)
        groups = AccessibilityCheck.allCases.compactMap { check in
            guard let findings = findingsByCheck[check], !findings.isEmpty else { return nil }
            return Group(check: check, findings: findings.sorted { $0.severity > $1.severity })
        }
        didHitLimit = result.didHitLimit
        checksRun = result.checksRun
        checksSkippedWhileCovered = AccessibilityCheck.allCases.filter(result.checksSkippedWhileCovered.contains)
        checksUnmeasurable = AccessibilityCheck.allCases.filter(result.checksUnmeasurable.contains)
        passTakenAt = takenAt
        passPredatesThisScreen = predatesThisScreen
    }
}
