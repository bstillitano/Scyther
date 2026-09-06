//
//  AccessibilityAuditReportPresenterTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 6/9/2026.
//

@testable import Scyther
import UIKit
import XCTest

/// Covers the pill's one job — opening the report — through
/// ``AccessibilityAuditReportPresenter/presentReport``, the seam that stands in for UIKit.
///
/// Presenting for real in a test would need a window, a root controller and an animation to
/// finish, and would prove only that UIKit presents things. What is worth proving is what this
/// feature actually got wrong: that the pill's closure is wired to something at all, and that a
/// second tap does not stack a second report on top of the first.
@MainActor
final class AccessibilityAuditReportPresenterTests: XCTestCase {

    /// Counts presentations and decides whether each one reports having reached the screen.
    private final class PresentationLog {
        /// How many times the report was asked to be presented.
        private(set) var presented = 0

        /// What the next presentation should report. `false` stands for a refusal — no key
        /// window, or an anchor already busy.
        var succeeds = true

        /// Records one presentation and reports whether it got there.
        func record() -> Bool {
            presented += 1
            return succeeds
        }
    }

    /// The report opens when the pill is tapped.
    func testTappingThePillOpensTheReport() {
        let log = PresentationLog()
        let presenter = AccessibilityAuditReportPresenter()
        presenter.presentReport = { _ in log.record() }

        presenter.openReport()

        XCTAssertEqual(log.presented, 1)
    }

    /// A second tap while the report is up does nothing. UIKit would happily accept a second
    /// presentation over the first, leaving the developer two identical reports deep with two
    /// dismissals between them and the app.
    func testASecondTapDoesNotOpenASecondReport() {
        let log = PresentationLog()
        let presenter = AccessibilityAuditReportPresenter()
        presenter.presentReport = { _ in log.record() }

        presenter.openReport()
        presenter.openReport()

        XCTAssertEqual(log.presented, 1)
    }

    /// A presentation that never reached the screen must not lock the pill out for the rest of
    /// the session: the developer taps again, and this time it opens.
    func testARefusedPresentationIsTriedAgainOnTheNextTap() {
        let log = PresentationLog()
        let presenter = AccessibilityAuditReportPresenter()
        presenter.presentReport = { _ in log.record() }

        log.succeeds = false
        presenter.openReport()
        log.succeeds = true
        presenter.openReport()
        presenter.openReport()

        XCTAssertEqual(log.presented, 2)
    }

    /// The defect this task exists for: the overlay declared `onOpenReport` and invoked it on
    /// tap, and nothing in the package ever assigned it, so the pill was dead. Setting the
    /// overlay up must leave the closure wired to something that opens the report.
    func testSettingUpTheOverlayWiresThePillToTheReport() {
        let toolkit = InterfaceToolkit.instance
        let presenter = AccessibilityAuditReportPresenter.shared
        let original = presenter.presentReport
        defer { presenter.presentReport = original }

        let log = PresentationLog()
        // Reports a refusal, so this test leaves the shared presenter exactly as it found it:
        // believing nothing is on screen, which is true — nothing was ever presented.
        log.succeeds = false
        presenter.presentReport = { _ in log.record() }

        toolkit.setupAccessibilityAudit()

        XCTAssertNotNil(toolkit.accessibilityAuditView.onOpenReport)
        toolkit.accessibilityAuditView.onOpenReport?()
        XCTAssertEqual(log.presented, 1)
    }
}
