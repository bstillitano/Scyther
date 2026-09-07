//
//  AccessibilityAuditViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 6/9/2026.
//

@testable import Scyther
import XCTest

@MainActor
final class AccessibilityAuditViewModelTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    /// Settings over a throwaway suite.
    ///
    /// The toggles at the top of the report write straight through to `AccessibilityAudit`, so a
    /// test that asserted anything about them through the shared singleton would be writing a
    /// developer's real settings — and reading whatever the last test left there. The view model
    /// takes its settings as an injection point for exactly this.
    private var settings: AccessibilityAudit!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AccessibilityAuditViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AccessibilityAudit(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// A view model over the throwaway settings, with no seeded pass.
    ///
    /// - Parameter run: What one pass of the audit returns.
    /// - Returns: The view model to assert against.
    private func viewModel(run: @escaping @MainActor () -> AccessibilityAuditor.Result)
    -> AccessibilityAuditViewModel {
        AccessibilityAuditViewModel(settings: settings, run: run)
    }

    private func finding(_ check: AccessibilityCheck,
                         _ severity: AccessibilitySeverity,
                         _ name: String) -> AccessibilityFinding {
        AccessibilityFinding(check: check, severity: severity,
                             frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                             elementName: name, detail: "detail")
    }

    private func result(_ findings: [AccessibilityFinding],
                        didHitLimit: Bool = false,
                        checksRun: Set<AccessibilityCheck> = Set(AccessibilityCheck.allCases),
                        checksSkippedWhileCovered: Set<AccessibilityCheck> = [],
                        checksUnmeasurable: Set<AccessibilityCheck> = [])
    -> AccessibilityAuditor.Result {
        AccessibilityAuditor.Result(findings: findings,
                                    didHitLimit: didHitLimit,
                                    checksRun: checksRun,
                                    checksSkippedWhileCovered: checksSkippedWhileCovered,
                                    checksUnmeasurable: checksUnmeasurable)
    }

    /// A pass the report can open onto, taken at `takenAt`.
    ///
    /// - Parameters:
    ///   - findings: What the pass found.
    ///   - takenAt: When it was taken. Defaults to a fixed instant so a test that does not care
    ///     about the age still gets a deterministic one.
    /// - Returns: The seeded pass.
    private func seeded(_ findings: [AccessibilityFinding],
                        takenAt: Date = Date(timeIntervalSince1970: 1_000)) -> SeededAccessibilityPass {
        SeededAccessibilityPass(result: result(findings), takenAt: takenAt)
    }

    /// Findings are grouped by check, errors first inside each group, so the report leads with
    /// what is broken rather than with whatever the walk happened to reach first.
    func testFindingsAreGroupedByCheckWithErrorsFirst() async {
        let findings = [
            finding(.touchTarget, .warning, "warn"),
            finding(.missingLabel, .error, "label"),
            finding(.touchTarget, .error, "error")
        ]
        let viewModel = viewModel { self.result(findings) }
        await viewModel.load()

        XCTAssertEqual(viewModel.groups.map(\.check), [.missingLabel, .touchTarget])
        XCTAssertEqual(viewModel.groups.last?.findings.map(\.elementName), ["error", "warn"])
    }

    /// The report is frozen. Findings that move while they are being read are useless, so a new
    /// pass happens only when it is asked for.
    func testTheReportDoesNotChangeUntilItIsRerun() async {
        var passes = 0
        let viewModel = viewModel {
            passes += 1
            return self.result([self.finding(.missingLabel, .error, "pass \(passes)")])
        }
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(passes, 1)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 1")

        await viewModel.rerun()

        XCTAssertEqual(passes, 2)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 2")
    }

    /// "No findings" and "nothing was looked at" must not read the same, so the empty state names
    /// the checks that did not run — and says a different thing depending on whether anything ran
    /// at all.
    ///
    /// The `checksRun:` argument is load-bearing here, which it stopped being when this test was
    /// reduced to a round-trip of the settings it had just written: `[.missingLabel]` is what makes
    /// this the "something ran and found nothing" state rather than the "nothing ran" one, and
    /// swapping it for `[]` turns the headline into `Nothing Was Checked` and fails the assertion
    /// below.
    func testTheEmptyStateNamesTheChecksThatWereSwitchedOff() async {
        settings.setEnabled(.touchTarget, to: false)
        settings.setEnabled(.contrast, to: false)
        let viewModel = viewModel {
            self.result([], checksRun: [.missingLabel])
        }
        await viewModel.load()

        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(Set(viewModel.switchedOffChecks), [.touchTarget, .contrast])
        XCTAssertFalse(viewModel.nothingWasChecked, "Missing Labels ran, so something was looked at")
        XCTAssertEqual(viewModel.emptyStateTitle, localized("No Issues In What Was Checked"))

        let description = viewModel.emptyStateDescription
        XCTAssertTrue(description.contains(AccessibilityCheck.touchTarget.title), description)
        XCTAssertTrue(description.contains(AccessibilityCheck.contrast.title), description)
        XCTAssertFalse(description.contains(AccessibilityCheck.missingLabel.title),
                       "the one check that ran must not be named as switched off")
    }

    /// The same shape with nothing having run: the pass, not the toggles, decides which of the two
    /// sentences the screen leads with.
    func testTheEmptyStateSaysNothingRanWhenThePassRanNothing() async {
        for check in AccessibilityCheck.allCases {
            settings.setEnabled(check, to: false)
        }
        let viewModel = viewModel { self.result([], checksRun: []) }
        await viewModel.load()

        XCTAssertEqual(viewModel.emptyStateTitle, localized("Nothing Was Checked"))
    }

    // MARK: - A Report That Is Hiding Findings

    /// The report is frozen and the toggles are not. Switching a check off after the pass hides its
    /// findings, and the empty state then said "The checks that ran found nothing to report" about a
    /// pass that had found five things — both clauses false about the pass in hand. A report that is
    /// hiding findings has to say it is hiding them.
    func testAReportHidingEveryFindingSaysSoRatherThanSayingNothingWasFound() async {
        let viewModel = viewModel {
            self.result((0..<5).map { self.finding(.contrast, .warning, "caption \($0)") })
        }
        await viewModel.load()

        viewModel.checkBinding(for: .contrast).wrappedValue = false

        XCTAssertTrue(viewModel.visibleGroups.isEmpty)
        XCTAssertEqual(viewModel.hiddenFindingCount, 5)
        XCTAssertEqual(viewModel.checksHidingFindings, [.contrast])
        XCTAssertEqual(viewModel.emptyStateSymbol, "eye.slash",
                       "a hidden report is not an unanswered question and is certainly not a tick")
        XCTAssertEqual(viewModel.emptyStateTitle, localized("Findings Hidden"))
        XCTAssertTrue(viewModel.emptyStateDescription.contains("5"),
                      viewModel.emptyStateDescription)
    }

    /// The partial case: some groups hidden, so the empty state is never reached and the report
    /// simply gets shorter with nothing explaining the gap.
    func testAReportThatLostSomeRowsToTheTogglesSaysHowManyItIsHiding() async {
        let viewModel = viewModel {
            self.result((0..<5).map { self.finding(.contrast, .warning, "caption \($0)") }
                        + [self.finding(.touchTarget, .error, "chevron")])
        }
        await viewModel.load()

        viewModel.checkBinding(for: .contrast).wrappedValue = false

        XCTAssertEqual(viewModel.visibleGroups.map(\.check), [.touchTarget],
                       "the shortened report is correct; it just has to say why it is short")
        XCTAssertEqual(viewModel.hiddenFindingCount, 5)
        XCTAssertTrue(viewModel.hiddenFindingsDescription.contains("5"),
                      viewModel.hiddenFindingsDescription)
        XCTAssertTrue(viewModel.hiddenFindingsDescription.contains(AccessibilityCheck.contrast.title),
                      viewModel.hiddenFindingsDescription)
    }

    /// Nothing is hidden until a toggle hides it, so an untouched report says nothing about hiding.
    func testAnUntouchedReportIsNotHidingAnything() async {
        let viewModel = viewModel { self.result([self.finding(.contrast, .warning, "caption")]) }
        await viewModel.load()

        XCTAssertEqual(viewModel.hiddenFindingCount, 0)
        XCTAssertTrue(viewModel.checksHidingFindings.isEmpty)
    }

    // MARK: - What A Clean Report May Claim

    /// "Every enabled check passed." is a claim about the app. The audit cannot see an element the
    /// app never exposed to accessibility, cannot judge whether a label is meaningful, and only sees
    /// what is on screen now — so the one state that has earned a tick still has to say what it did
    /// not look at, or a developer reads a clean report as "my app is accessible".
    func testTheSuccessStateNamesWhatTheAuditCannotSee() async {
        let viewModel = viewModel { self.result([]) }
        await viewModel.load()

        XCTAssertTrue(viewModel.isComplete)
        XCTAssertEqual(viewModel.emptyStateSymbol, "checkmark.circle")

        let description = viewModel.emptyStateDescription
        XCTAssertNotEqual(description, localized("Every enabled check passed."),
                          "an unqualified pass over a tool with known blind spots is a certificate")
        XCTAssertTrue(description.contains("exposed"), description)
        XCTAssertTrue(description.contains("meaningful"), description)
        XCTAssertTrue(description.contains("now"), description)
    }

    // MARK: - Two Producers, One Banner

    /// `checksUnmeasurable` is raised both when there were no pixels at all and when there were
    /// pixels that could not be read. The banner used to assert the first — "this screen could not
    /// be captured, so there were no pixels to read" — every clause of which is false of the second.
    func testTheUnmeasurableBannerIsTrueOfBothWaysAMeasurementCanFail() async {
        let viewModel = viewModel { self.result([], checksUnmeasurable: [.contrast]) }
        await viewModel.load()

        let description = viewModel.unmeasurableDescription
        XCTAssertTrue(description.contains(AccessibilityCheck.contrast.title), description)
        XCTAssertFalse(description.contains("could not be captured"),
                       "a screen that captured fine and read as flat colour is not an uncaptured screen")
        XCTAssertFalse(description.contains("no pixels"),
                       "there were pixels; they could not be read")
    }

    // MARK: - The Age Of The Pass

    /// The report opens onto the live overlay's last pass, which is always older than the screen
    /// reading it: no pass can run while Scyther covers the app. A scroll between the pass and the
    /// tap on the pill leaves a report of rows that are no longer on screen, presented as current.
    func testASeededReportKnowsItIsShowingAPassOlderThanTheScreen() async {
        let takenAt = Date(timeIntervalSince1970: 5_000)
        let pass = seeded([finding(.contrast, .warning, "caption")], takenAt: takenAt)
        let viewModel = AccessibilityAuditViewModel(settings: settings, seed: { pass }) {
            self.result([])
        }

        await viewModel.load()

        XCTAssertEqual(viewModel.passTakenAt, takenAt)
        XCTAssertTrue(viewModel.passPredatesThisScreen)
    }

    /// A report that took its own pass is describing the screen it is sitting on, so it says
    /// nothing about age.
    func testAReportThatTookItsOwnPassIsNotMarkedAsOlderThanTheScreen() async {
        let viewModel = viewModel { self.result([]) }
        await viewModel.load()

        XCTAssertNotNil(viewModel.passTakenAt, "every pass is timestamped, seeded or not")
        XCTAssertFalse(viewModel.passPredatesThisScreen)
    }

    /// **Re-run** replaces the seeded pass with one taken now, so the banner about the old one goes.
    func testRerunningClearsTheOlderThanTheScreenBanner() async {
        let pass = seeded([finding(.contrast, .warning, "caption")])
        let viewModel = AccessibilityAuditViewModel(settings: settings, seed: { pass }) {
            self.result([])
        }
        await viewModel.load()
        XCTAssertTrue(viewModel.passPredatesThisScreen)

        await viewModel.rerun()

        XCTAssertFalse(viewModel.passPredatesThisScreen)
    }

    func testNothingIsReportedAsSkippedWhenEveryCheckRan() async {
        let viewModel = viewModel { self.result([]) }
        await viewModel.load()

        XCTAssertTrue(viewModel.switchedOffChecks.isEmpty)
        XCTAssertTrue(viewModel.checksSkippedWhileCovered.isEmpty)
        XCTAssertTrue(viewModel.checksAwaitingRerun.isEmpty)
        XCTAssertTrue(viewModel.isComplete, "everything ran, so this report may lead with a tick")
    }

    /// A check that was on and still did not run — because Scyther's own screen was over the app
    /// when the pass was made — is reported on its own, never as one the developer switched off.
    /// Telling a developer they had turned contrast off when they had not is a small lie the
    /// report has no business telling.
    func testACheckSkippedWhileCoveredIsNotReportedAsSwitchedOff() async {
        let viewModel = viewModel {
            self.result([],
                        checksRun: [.missingLabel, .touchTarget],
                        checksSkippedWhileCovered: [.contrast])
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.checksSkippedWhileCovered, [.contrast])
        XCTAssertTrue(viewModel.switchedOffChecks.isEmpty)
    }

    /// The two reasons a check did not run are reported separately even when both apply at once,
    /// because the screen says something different about each.
    func testSwitchedOffAndCoveredChecksAreReportedApart() async {
        settings.setEnabled(.touchTarget, to: false)
        let viewModel = viewModel {
            self.result([],
                        checksRun: [.missingLabel],
                        checksSkippedWhileCovered: [.contrast])
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.checksSkippedWhileCovered, [.contrast])
        XCTAssertEqual(viewModel.switchedOffChecks, [.touchTarget])
    }

    /// A third reason, and it must not be confused with either of the other two. A check that ran
    /// and could measure nothing — because iOS returned no pixels for the screen — is not a setting
    /// the developer chose, and is not something they can fix by getting Scyther out of the way.
    func testACheckThatCouldNotBeMeasuredIsKeptApartFromBothOtherReasons() async {
        let viewModel = viewModel {
            self.result([],
                        checksRun: [.missingLabel, .touchTarget],
                        checksUnmeasurable: [.contrast])
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.checksUnmeasurable, [.contrast])
        XCTAssertTrue(viewModel.checksSkippedWhileCovered.isEmpty)
        XCTAssertTrue(viewModel.switchedOffChecks.isEmpty)
        XCTAssertTrue(viewModel.checksAwaitingRerun.isEmpty,
                      "re-running will not produce pixels that iOS refused to hand over")
        XCTAssertFalse(viewModel.isComplete, "an unmeasured screen has not passed anything")
    }

    /// A truncated walk reached only part of the screen, so the part it did not reach was never
    /// checked. The report used to say "Every enabled check passed" here, directly under the orange
    /// banner saying the walk had stopped early.
    func testATruncatedWalkIsNeverReportedAsComplete() async {
        let viewModel = viewModel { self.result([], didHitLimit: true) }
        await viewModel.load()

        XCTAssertTrue(viewModel.didHitLimit)
        XCTAssertFalse(viewModel.isComplete)
        XCTAssertFalse(viewModel.nothingWasChecked, "part of the screen really was checked")
    }

    /// Every check switched off produces exactly the same empty report as a clean screen, and used
    /// to be presented with the same green tick and the same "No Issues Found". Nothing ran.
    func testEveryCheckSwitchedOffReadsAsNothingChecked() async {
        for check in AccessibilityCheck.allCases {
            settings.setEnabled(check, to: false)
        }
        let viewModel = viewModel { self.result([], checksRun: []) }
        await viewModel.load()

        XCTAssertTrue(viewModel.nothingWasChecked)
        XCTAssertFalse(viewModel.isComplete)
        XCTAssertEqual(Set(viewModel.switchedOffChecks), Set(AccessibilityCheck.allCases))
    }

    /// The toggles take effect immediately; the report stays frozen until **Re-run**. A Contrast
    /// section listed directly beneath a Contrast switch that is off reads as a switch that did
    /// nothing, so the section goes.
    func testSwitchingACheckOffHidesItsFindingsFromTheFrozenReport() async {
        let viewModel = viewModel {
            self.result([self.finding(.contrast, .warning, "caption"),
                         self.finding(.missingLabel, .error, "button")])
        }
        await viewModel.load()
        XCTAssertEqual(viewModel.visibleGroups.map(\.check), [.missingLabel, .contrast])

        viewModel.checkBinding(for: .contrast).wrappedValue = false

        XCTAssertEqual(viewModel.visibleGroups.map(\.check), [.missingLabel])
        XCTAssertEqual(viewModel.groups.map(\.check), [.missingLabel, .contrast],
                       "the pass itself is still frozen; only what is shown changed")
    }

    /// The other half of the same defect: switching a check back on used to leave "Switched off:
    /// Contrast" sitting underneath the switch that now reads on. It goes — and because switching
    /// it on cannot conjure findings the pass never looked for, the report says so instead.
    func testSwitchingACheckOnAsksForARerunRatherThanLeavingItNamedAsOff() async {
        settings.setEnabled(.contrast, to: false)
        let viewModel = viewModel { self.result([], checksRun: [.missingLabel, .touchTarget]) }
        await viewModel.load()
        XCTAssertEqual(viewModel.switchedOffChecks, [.contrast])

        viewModel.checkBinding(for: .contrast).wrappedValue = true

        XCTAssertTrue(viewModel.switchedOffChecks.isEmpty)
        XCTAssertEqual(viewModel.checksAwaitingRerun, [.contrast])
        XCTAssertFalse(viewModel.isComplete)
    }

    /// A truncated walk says so rather than presenting a partial result as complete.
    func testATruncatedWalkIsReported() async {
        let viewModel = viewModel {
            self.result([self.finding(.contrast, .warning, "text")], didHitLimit: true)
        }
        await viewModel.load()

        XCTAssertTrue(viewModel.didHitLimit)
    }

    /// Tapping a row asks the overlay behind to flash that element's box.
    func testFlashingARowReachesTheOverlay() {
        let viewModel = viewModel { self.result([]) }
        var flashed: AccessibilityFinding?
        viewModel.onFlash = { flashed = $0 }

        let target = finding(.contrast, .warning, "text")
        viewModel.flash(target)

        XCTAssertEqual(flashed?.id, target.id)
    }

    /// The defect this whole task exists for: the walk must not run inside the caller's own turn
    /// on the main actor. `.onFirstAppear` starts during the navigation push, so a pass that runs
    /// straight through holds the main thread until it finishes and the push never animates. A
    /// competing main-actor task standing in for that transition has to get its turn first.
    func testThePassYieldsTheMainActorBeforeItWalks() async {
        let order = Recorder()
        let viewModel = viewModel {
            order.steps.append("walk")
            return self.result([])
        }

        async let loaded: Void = viewModel.load()
        async let transitioned: Void = Task { @MainActor in order.steps.append("transition") }.value
        _ = await (loaded, transitioned)

        XCTAssertEqual(order.steps, ["transition", "walk"],
                       "the transition must get the main actor before the walk takes it")
    }

    /// The screen shows a spinner rather than an empty report while a pass is in flight, and puts
    /// it away again once there is an answer. Read from inside the walk itself, because that is
    /// the only moment the flag is meant to be up.
    func testTheReportSaysItIsRunningWhileThePassIsInFlight() async {
        let recorder = Recorder()
        let viewModel = viewModel {
            recorder.isRunningDuringTheWalk = recorder.viewModel?.isRunning
            return self.result([])
        }
        recorder.viewModel = viewModel

        XCTAssertFalse(viewModel.isRunning)
        await viewModel.load()

        XCTAssertEqual(recorder.isRunningDuringTheWalk, true, "the spinner must be up while the walk runs")
        XCTAssertFalse(viewModel.isRunning, "and down once there is an answer")
    }

    /// **Re-run** is guarded by `.disabled(isRunning)`, and that guard cannot work: `isRunning` is
    /// published from inside the pass, and the render that would grey the button out has to wait
    /// for the main actor the pass is holding. So the button stays drawn as enabled for the whole
    /// of the first pass — the one that starts during the navigation push — and a tap on it started
    /// a second walk that published `isRunning = false` while the first was still going and
    /// replaced the report under a developer mid-read.
    func testASecondPassCannotStartWhileOneIsAlreadyRunning() async {
        var passes = 0
        let viewModel = viewModel {
            passes += 1
            return self.result([])
        }

        async let first: Void = viewModel.load()
        async let second: Void = viewModel.rerun()
        _ = await (first, second)

        XCTAssertEqual(passes, 1, "the second tap must not start a second overlapping walk")
    }

    /// The pill counts a pass taken with nothing of Scyther's on screen, so it includes contrast.
    /// The report used to run its *own* pass on opening, by which time it was itself the thing
    /// covering the app, so contrast was dropped — which is how a pill reading "7 issues" opened
    /// onto "No Issues Found". Opening onto the pass the pill counted is what makes the two agree.
    func testTheReportOpensOntoTheLivePassRatherThanTakingItsOwn() async {
        var passes = 0
        let live = seeded([finding(.contrast, .warning, "caption")])
        let viewModel = AccessibilityAuditViewModel(settings: settings, seed: { live }) {
            passes += 1
            return self.result([])
        }

        await viewModel.load()

        XCTAssertEqual(passes, 0, "the report must not take a pass of its own over the seeded one")
        XCTAssertEqual(viewModel.visibleGroups.map(\.check), [.contrast])
    }

    /// A developer who asks for a fresh measurement gets one. **Re-run** goes to the audit even
    /// when the report opened onto the live overlay's pass; the banners explain what a pass taken
    /// from under Scyther's own sheet cannot include.
    func testRerunTakesAFreshPassEvenWhenTheReportWasSeeded() async {
        let live = seeded([finding(.contrast, .warning, "caption")])
        let viewModel = AccessibilityAuditViewModel(settings: settings, seed: { live }) {
            self.result([self.finding(.missingLabel, .error, "button")])
        }
        await viewModel.load()

        await viewModel.rerun()

        XCTAssertEqual(viewModel.visibleGroups.map(\.check), [.missingLabel])
    }

    /// Notes what happened during a pass, from inside the audit closure.
    ///
    /// A reference type rather than a captured `var` so the audit closure and a competing
    /// main-actor task write to the same storage rather than to copies of it, and so the closure
    /// can reach the view model that owns it without capturing it before it exists.
    @MainActor
    private final class Recorder {
        /// What ran, in the order it ran.
        var steps: [String] = []

        /// The view model under test, set after it is constructed.
        var viewModel: AccessibilityAuditViewModel?

        /// What ``AccessibilityAuditViewModel/isRunning`` read as while the walk was happening.
        var isRunningDuringTheWalk: Bool?
    }
}
