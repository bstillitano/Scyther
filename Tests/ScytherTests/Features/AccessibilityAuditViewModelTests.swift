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
    func testFindingsAreGroupedByCheckWithErrorsFirst() {
        let findings = [
            finding(.touchTarget, .warning, "warn"),
            finding(.missingLabel, .error, "label"),
            finding(.touchTarget, .error, "error")
        ]
        let viewModel = AccessibilityAuditViewModel { self.result(findings) }
        viewModel.load()

        XCTAssertEqual(viewModel.groups.map(\.check), [.missingLabel, .touchTarget])
        XCTAssertEqual(viewModel.groups.last?.findings.map(\.elementName), ["error", "warn"])
    }

    /// The report is frozen. Findings that move while they are being read are useless, so a new
    /// pass happens only when it is asked for.
    func testTheReportDoesNotChangeUntilItIsRerun() {
        var passes = 0
        let viewModel = AccessibilityAuditViewModel {
            passes += 1
            return self.result([self.finding(.missingLabel, .error, "pass \(passes)")])
        }
        viewModel.load()
        viewModel.load()

        XCTAssertEqual(passes, 1)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 1")

        viewModel.rerun()

        XCTAssertEqual(passes, 2)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 2")
    }

    /// "No findings" and "nothing was looked at" must not read the same, so the empty state is
    /// handed the checks that did not run.
    func testTheEmptyStateNamesTheChecksThatWereSwitchedOff() {
        let viewModel = AccessibilityAuditViewModel {
            self.result([], checksRun: [.missingLabel])
        }
        viewModel.load()

        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(Set(viewModel.skippedChecks), [.touchTarget, .contrast])
    }

    func testNothingIsReportedAsSkippedWhenEveryCheckRan() {
        let viewModel = AccessibilityAuditViewModel { self.result([]) }
        viewModel.load()

        XCTAssertTrue(viewModel.skippedChecks.isEmpty)
    }

    /// A truncated walk says so rather than presenting a partial result as complete.
    func testATruncatedWalkIsReported() {
        let viewModel = AccessibilityAuditViewModel {
            self.result([self.finding(.contrast, .warning, "text")], didHitLimit: true)
        }
        viewModel.load()

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
}
