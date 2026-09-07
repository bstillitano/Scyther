@testable import Scyther
import UIKit
import XCTest

/// Covers what a pass is allowed to *cost*, which is a separate question from what it finds.
///
/// The measurement this suite exists for: one live pass held the main thread for about 800ms, of
/// which 436ms was `WindowContrastSampler`'s window snapshot — a forced full re-render of the
/// window, taken before the pass's own deadline had ever been consulted. Live mode runs a pass on
/// every navigation, so the developer's app froze for most of a second each time they moved.
///
/// Everything here is either a pure entry point or an injected seam, deliberately. `ScytherTests`
/// has no host app: `drawHierarchy(in:afterScreenUpdates:)` paints nothing, `contentScaleFactor`
/// is 1 and `UIApplication.shared.connectedScenes` is empty, so any test that leaned on real
/// rendering would pass whether or not the snapshot was ever taken — which is the one thing this
/// suite has to be able to tell apart.
@MainActor
final class AccessibilityAuditPassCostTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AccessibilityAuditPassCostTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            ScytherPresentation.presentationMeasurementSpace()
        }
    }

    /// A window a test can run a pass over. Unhidden because the walk skips what it cannot see.
    ///
    /// - Returns: A 390 × 844 window at the screen origin.
    private func testWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }

    // MARK: - What each purpose runs

    /// The whole point of the split. Missing labels and touch targets read the accessibility tree
    /// and geometry; only contrast needs pixels, and pixels cost most of a second.
    func testALivePassRunsTheTwoChecksThatNeedNoPixels() {
        let checks = AccessibilityAudit.checks(for: .live, from: Set(AccessibilityCheck.allCases))
        XCTAssertEqual(checks, [.missingLabel, .touchTarget])
    }

    /// The report is the moment the developer asked for an answer, so it runs all three.
    func testAReportPassRunsEveryCheckThatIsSwitchedOn() {
        let checks = AccessibilityAudit.checks(for: .report, from: Set(AccessibilityCheck.allCases))
        XCTAssertEqual(checks, Set(AccessibilityCheck.allCases))
    }

    /// Deferring contrast to the report is not a way of switching it back on. A developer who
    /// turned it off gets it in neither pass.
    func testAContrastCheckThatIsSwitchedOffRunsInNeitherPass() {
        XCTAssertFalse(AccessibilityAudit.checks(for: .live, from: [.missingLabel]).contains(.contrast))
        XCTAssertFalse(AccessibilityAudit.checks(for: .report, from: [.missingLabel]).contains(.contrast))
    }

    /// The snapshot is taken for exactly one reason, so a set of checks that does not contain
    /// contrast must not cause one.
    func testOnlyAPassThatRunsContrastNeedsASnapshot() {
        XCTAssertFalse(AccessibilityAudit.needsAWindowSnapshot(checks: [.missingLabel, .touchTarget]))
        XCTAssertTrue(AccessibilityAudit.needsAWindowSnapshot(checks: [.missingLabel, .contrast]))
    }

    // MARK: - The seam that proves no snapshot is taken

    /// The most important test in the suite: a live pass must not construct a sampler at all.
    ///
    /// Asserted through the injected factory rather than by timing, because in a hostless test
    /// process the real snapshot costs nothing and would pass this vacuously.
    func testALivePassNeverAsksForPixels() {
        let audit = AccessibilityAudit(defaults: defaults)
        var asked = 0
        audit.makeContrastSource = { window in
            asked += 1
            return AccessibilityAudit.ContrastSource(sampler: WindowContrastSampler(window: window),
                                                     didCaptureWindow: false)
        }

        let result = audit.audit(window: testWindow(), purpose: .live)

        XCTAssertEqual(asked, 0, "a live pass must take no snapshot")
        XCTAssertEqual(result.checksRun, [.missingLabel, .touchTarget])
    }

    /// And the other half: the report pass does ask, once.
    func testAReportPassAsksForPixelsOnce() {
        let audit = AccessibilityAudit(defaults: defaults)
        var asked = 0
        audit.makeContrastSource = { window in
            asked += 1
            return AccessibilityAudit.ContrastSource(sampler: WindowContrastSampler(window: window),
                                                     didCaptureWindow: true)
        }

        let result = audit.audit(window: testWindow(), purpose: .report)

        XCTAssertEqual(asked, 1)
        XCTAssertTrue(result.checksRun.contains(.contrast))
    }

    /// Contrast switched off means no pixels are read even on the report's own pass — the sampler
    /// is the expensive part and there is nothing to spend it on.
    func testAReportPassWithContrastOffTakesNoSnapshot() {
        let audit = AccessibilityAudit(defaults: defaults)
        audit.setEnabled(.contrast, to: false)
        var asked = 0
        audit.makeContrastSource = { window in
            asked += 1
            return AccessibilityAudit.ContrastSource(sampler: WindowContrastSampler(window: window),
                                                     didCaptureWindow: true)
        }

        _ = audit.audit(window: testWindow(), purpose: .report)

        XCTAssertEqual(asked, 0)
    }

    // MARK: - The budget covers the snapshot

    /// A live pass has no snapshot in it, so it keeps the quarter-second that bounds how long the
    /// main thread may be held while the developer is navigating.
    func testALivePassKeepsTheQuarterSecondBudget() {
        XCTAssertEqual(AccessibilityAudit.budget(for: .live), AccessibilityAuditor.budget)
    }

    /// A report pass has the snapshot in it, and 436ms of snapshot does not fit inside a 250ms
    /// budget: bounding the pass at the live figure would have made every report an empty,
    /// truncated one. The report is asked for explicitly, so it gets a budget that can hold what
    /// it actually does.
    func testAReportPassIsBudgetedForTheSnapshotItTakes() {
        XCTAssertEqual(AccessibilityAudit.budget(for: .report), AccessibilityAuditor.reportBudget)
        XCTAssertGreaterThan(AccessibilityAuditor.reportBudget, AccessibilityAuditor.budget)
    }

    /// The defect this fixes: the snapshot ran before the deadline was ever consulted, so the one
    /// bound on how long a pass may hold the main thread could not see the most expensive thing a
    /// pass does. The clock is now read again the moment the snapshot returns, and a snapshot that
    /// spent the whole budget raises the same truncation flag every other limit raises.
    func testASnapshotThatSpendsTheWholeBudgetTruncatesThePass() {
        let audit = AccessibilityAudit(defaults: defaults)
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        audit.now = { clock }
        audit.makeContrastSource = { window in
            clock = clock.addingTimeInterval(AccessibilityAuditor.reportBudget + 1)
            return AccessibilityAudit.ContrastSource(sampler: WindowContrastSampler(window: window),
                                                     didCaptureWindow: true)
        }

        let result = audit.audit(window: testWindow(), purpose: .report)

        XCTAssertTrue(result.didHitLimit, "a pass with no budget left must say so")
        XCTAssertTrue(result.findings.isEmpty)
    }

    /// And the honest converse: a snapshot that comes back inside the budget leaves the pass to
    /// run normally, so the flag means what it says.
    func testASnapshotInsideTheBudgetDoesNotTruncateThePass() {
        let audit = AccessibilityAudit(defaults: defaults)
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        audit.now = { clock }
        audit.makeContrastSource = { window in
            clock = clock.addingTimeInterval(0.4)
            return AccessibilityAudit.ContrastSource(sampler: WindowContrastSampler(window: window),
                                                     didCaptureWindow: true)
        }

        let result = audit.audit(window: testWindow(), purpose: .report)

        XCTAssertFalse(result.didHitLimit)
    }
}
