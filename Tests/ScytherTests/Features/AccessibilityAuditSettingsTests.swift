@testable import Scyther
import XCTest

@MainActor
final class AccessibilityAuditSettingsTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AccessibilityAuditSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testEveryCheckIsOnByDefault() {
        let audit = AccessibilityAudit(defaults: defaults)
        XCTAssertEqual(audit.enabledChecks, Set(AccessibilityCheck.allCases))
    }

    func testLiveModeIsOffByDefault() {
        XCTAssertFalse(AccessibilityAudit(defaults: defaults).liveEnabled)
    }

    func testSwitchingACheckOffLeavesTheOthersOn() {
        let audit = AccessibilityAudit(defaults: defaults)
        audit.setEnabled(.contrast, to: false)

        XCTAssertEqual(audit.enabledChecks, [.missingLabel, .touchTarget])
        XCTAssertFalse(audit.isEnabled(.contrast))
    }

    func testSettingsSurviveANewInstance() {
        AccessibilityAudit(defaults: defaults).setEnabled(.touchTarget, to: false)
        XCTAssertFalse(AccessibilityAudit(defaults: defaults).isEnabled(.touchTarget))
    }

    /// Switching every check off is not the same as switching the audit off, and the audit must
    /// not pretend a screen passed when nothing was run.
    func testWithNoChecksOnNothingIsRun() {
        let audit = AccessibilityAudit(defaults: defaults)
        AccessibilityCheck.allCases.forEach { audit.setEnabled($0, to: false) }
        XCTAssertTrue(audit.enabledChecks.isEmpty)
    }

    // MARK: - Skipping Checks While Scyther Covers The App

    /// With nothing of Scyther's on screen the audit measures the app itself, so nothing is
    /// skipped and contrast is answered from the real pixels.
    func testNothingIsSkippedWhileScytherIsNotCovering() {
        let skipped = AccessibilityAudit.checksSkippedWhileCovered(from: Set(AccessibilityCheck.allCases),
                                                                  isCovering: false)
        XCTAssertTrue(skipped.isEmpty)
    }

    /// Contrast is sampled from a snapshot of the window, and a Scyther modal dims everything
    /// behind it — so while one is up the only honest answer is not to answer. Missing labels and
    /// touch targets come from the accessibility tree, which the dimming cannot touch, so they
    /// keep running.
    func testOnlyContrastIsSkippedWhileScytherIsCovering() {
        let skipped = AccessibilityAudit.checksSkippedWhileCovered(from: Set(AccessibilityCheck.allCases),
                                                                  isCovering: true)
        XCTAssertEqual(skipped, [.contrast])
    }

    /// A check the developer already switched off is not additionally reported as skipped for
    /// being covered: it was never going to run, and saying so twice in two different ways would
    /// make the report contradict itself.
    func testACheckThatIsAlreadyOffIsNotReportedAsCovered() {
        let skipped = AccessibilityAudit.checksSkippedWhileCovered(from: [.missingLabel, .touchTarget],
                                                                  isCovering: true)
        XCTAssertTrue(skipped.isEmpty)
    }
}

/// Covers the two decisions ``AccessibilityAudit/auditKeyWindow()`` makes before it is allowed to
/// look at anything: which builds may be audited at all, and what to report when the window could
/// not be snapshotted.
///
/// Both are tested through the pure entry points rather than through `auditKeyWindow()` itself,
/// because neither input can be faked in this host: `AppEnvironment.isTestCase` is unconditionally
/// `true` under XCTest and `isAppStore` unconditionally `false`, so a test that called
/// `auditKeyWindow()` would return on the first guard and could never reach the App Store branch
/// to fail on it.
@MainActor
final class AccessibilityAuditProductionSafetyTests: XCTestCase {

    /// The defect: `auditKeyWindow()` guarded `isTestCase` and nothing else. Live mode persists in
    /// the `com.scyther.settings` suite, which survives sign-out by design, so a host shipping
    /// `Scyther.start(allowProductionBuilds: true)` rasterised real users' screens every half
    /// second. This is the one Scyther feature that reads the screen as pixels, so it carries its
    /// own guard rather than relying on `start()`'s.
    func testAnAppStoreBuildIsNeverAudited() {
        XCTAssertFalse(AccessibilityAudit.canAuditKeyWindow(isTestCase: false, isAppStore: true))
    }

    /// The pre-existing rule, kept: a test's fabricated window is not the app anyone is debugging.
    func testATestBuildIsNeverAudited() {
        XCTAssertFalse(AccessibilityAudit.canAuditKeyWindow(isTestCase: true, isAppStore: false))
        XCTAssertFalse(AccessibilityAudit.canAuditKeyWindow(isTestCase: true, isAppStore: true))
    }

    /// A development build — the only one the audit exists for — still runs.
    func testADevelopmentBuildIsAudited() {
        XCTAssertTrue(AccessibilityAudit.canAuditKeyWindow(isTestCase: false, isAppStore: false))
    }

    /// With the `CALayer.render(in:)` fallback gone, a refused snapshot is a real failure. Contrast
    /// has to be reported as unmeasured: with no pixels every element reads as one flat colour and
    /// a screen nobody measured would otherwise be reported as a screen that passed.
    func testContrastIsReportedAsSkippedWhenTheWindowCouldNotBeSnapshotted() {
        let skipped = AccessibilityAudit.checksUnmeasurableWithoutASnapshot(from: [.contrast, .missingLabel, .touchTarget],
                                                                      didCaptureWindow: false)

        XCTAssertEqual(skipped, [.contrast])
    }

    /// The tree-based checks do not need pixels, so a failed snapshot must not silence them.
    func testTheChecksThatNeedNoPixelsStillRunWithoutASnapshot() {
        let skipped = AccessibilityAudit.checksUnmeasurableWithoutASnapshot(from: [.missingLabel, .touchTarget],
                                                                      didCaptureWindow: false)

        XCTAssertTrue(skipped.isEmpty)
    }

    /// A successful snapshot skips nothing.
    func testNothingIsSkippedWhenTheSnapshotSucceeded() {
        let skipped = AccessibilityAudit.checksUnmeasurableWithoutASnapshot(from: [.contrast, .missingLabel],
                                                                      didCaptureWindow: true)

        XCTAssertTrue(skipped.isEmpty)
    }

    /// A check the developer had already switched off is not resurrected into the skipped list —
    /// the report says different things about the two, and conflating them would misreport a
    /// setting the developer chose.
    func testACheckThatWasNotEnabledIsNotReportedAsSkipped() {
        let skipped = AccessibilityAudit.checksUnmeasurableWithoutASnapshot(from: [.missingLabel],
                                                                      didCaptureWindow: false)

        XCTAssertFalse(skipped.contains(.contrast))
    }

    // MARK: - When A Check Has Genuinely Run

    /// One measurement out of two hundred candidates left contrast counted as a check that ran, so
    /// the report showed a green tick with no banner over a screen 199 of whose elements were never
    /// read. A check that measured a small minority of what it looked at has not run.
    func testAContrastCheckThatCouldReadAlmostNothingHasNotRun() {
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.contrast, .missingLabel, .touchTarget], candidates: 200, measured: 1)

        XCTAssertEqual(unmeasurable, [.contrast])
    }

    /// The existing total-failure case still lands in the same bucket, from the same rule.
    func testAContrastCheckThatReadNothingAtAllHasNotRun() {
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.contrast], candidates: 200, measured: 0)

        XCTAssertEqual(unmeasurable, [.contrast])
    }

    /// A check that read most of what it looked at has run. A stricter line than this would put a
    /// banner on every screen with a photograph on it.
    func testAContrastCheckThatReadMostOfTheScreenHasRun() {
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.contrast], candidates: 200, measured: 180)

        XCTAssertTrue(unmeasurable.isEmpty)
    }

    /// Exactly at the line, a check has run: the threshold is the point below which it has not.
    func testAContrastCheckAtTheThresholdHasRun() {
        let candidates = 200
        let measured = Int((Double(candidates) * AccessibilityAudit.measuredFractionForACheckToHaveRun).rounded(.up))
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.contrast], candidates: candidates, measured: measured)

        XCTAssertTrue(unmeasurable.isEmpty)
    }

    /// A screen with no text on it at all measured nothing because there was nothing to measure.
    /// That is a different fact from a screen it could not read, and it stays silent.
    func testAScreenWithNothingToMeasureIsNotReportedAsUnmeasurable() {
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.contrast], candidates: 0, measured: 0)

        XCTAssertTrue(unmeasurable.isEmpty)
    }

    /// Contrast is the only check that reads pixels, so it is the only one this rule can be about.
    func testOnlyContrastIsJudgedOnHowMuchItMeasured() {
        let unmeasurable = AccessibilityAudit.checksUnmeasurableFromPartialMeasurement(
            from: [.missingLabel, .touchTarget], candidates: 200, measured: 0)

        XCTAssertTrue(unmeasurable.isEmpty)
    }
}
