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
}
