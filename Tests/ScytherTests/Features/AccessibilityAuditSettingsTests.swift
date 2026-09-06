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
