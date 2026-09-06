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

    private func finding(_ check: AccessibilityCheck,
                         _ severity: AccessibilitySeverity,
                         _ name: String) -> AccessibilityFinding {
        AccessibilityFinding(check: check, severity: severity,
                             frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                             elementName: name, detail: "detail")
    }

    private func result(_ findings: [AccessibilityFinding],
                        didHitLimit: Bool = false,
                        checksRun: Set<AccessibilityCheck> = Set(AccessibilityCheck.allCases))
    -> AccessibilityAuditor.Result {
        AccessibilityAuditor.Result(findings: findings, didHitLimit: didHitLimit, checksRun: checksRun)
    }

    /// Findings are grouped by check, errors first inside each group, so the report leads with
    /// what is broken rather than with whatever the walk happened to reach first.
    func testFindingsAreGroupedByCheckWithErrorsFirst() async {
        let findings = [
            finding(.touchTarget, .warning, "warn"),
            finding(.missingLabel, .error, "label"),
            finding(.touchTarget, .error, "error")
        ]
        let viewModel = AccessibilityAuditViewModel { self.result(findings) }
        await viewModel.load()

        XCTAssertEqual(viewModel.groups.map(\.check), [.missingLabel, .touchTarget])
        XCTAssertEqual(viewModel.groups.last?.findings.map(\.elementName), ["error", "warn"])
    }

    /// The report is frozen. Findings that move while they are being read are useless, so a new
    /// pass happens only when it is asked for.
    func testTheReportDoesNotChangeUntilItIsRerun() async {
        var passes = 0
        let viewModel = AccessibilityAuditViewModel {
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

    /// "No findings" and "nothing was looked at" must not read the same, so the empty state is
    /// handed the checks that did not run.
    func testTheEmptyStateNamesTheChecksThatWereSwitchedOff() async {
        let viewModel = AccessibilityAuditViewModel {
            self.result([], checksRun: [.missingLabel])
        }
        await viewModel.load()

        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(Set(viewModel.skippedChecks), [.touchTarget, .contrast])
    }

    func testNothingIsReportedAsSkippedWhenEveryCheckRan() async {
        let viewModel = AccessibilityAuditViewModel { self.result([]) }
        await viewModel.load()

        XCTAssertTrue(viewModel.skippedChecks.isEmpty)
    }

    /// A truncated walk says so rather than presenting a partial result as complete.
    func testATruncatedWalkIsReported() async {
        let viewModel = AccessibilityAuditViewModel {
            self.result([self.finding(.contrast, .warning, "text")], didHitLimit: true)
        }
        await viewModel.load()

        XCTAssertTrue(viewModel.didHitLimit)
    }

    /// Tapping a row asks the overlay behind to flash that element's box.
    func testFlashingARowReachesTheOverlay() {
        let viewModel = AccessibilityAuditViewModel { self.result([]) }
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
        let viewModel = AccessibilityAuditViewModel {
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
        let viewModel = AccessibilityAuditViewModel {
            recorder.isRunningDuringTheWalk = recorder.viewModel?.isRunning
            return self.result([])
        }
        recorder.viewModel = viewModel

        XCTAssertFalse(viewModel.isRunning)
        await viewModel.load()

        XCTAssertEqual(recorder.isRunningDuringTheWalk, true, "the spinner must be up while the walk runs")
        XCTAssertFalse(viewModel.isRunning, "and down once there is an answer")
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
