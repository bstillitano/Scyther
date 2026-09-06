//
//  AccessibilityAuditOverlayViewTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 6/9/2026.
//

@testable import Scyther
import UIKit
import XCTest

/// Covers how the live overlay lays out its count pill.
///
/// The pill is the overlay's only interactive element and the only thing on it made of text, and
/// it read as "2 issue" over "s" on a real device: laid out at the width its *previous*, shorter
/// title needed, it wrapped. These tests are about the geometry that let that happen, not about
/// what the pill says.
@MainActor
final class AccessibilityAuditOverlayViewTests: XCTestCase {

    /// One finding, in a frame the overlay can draw a box around.
    private func finding(_ name: String) -> AccessibilityFinding {
        AccessibilityFinding(check: .missingLabel,
                             severity: .error,
                             frame: CGRect(x: 10, y: 10, width: 30, height: 30),
                             elementName: name,
                             detail: "detail")
    }

    /// An overlay sized like a phone, as `TopLevelViewsWrapper` would size it.
    private func overlay() -> AccessibilityAuditOverlayView {
        let overlay = AccessibilityAuditOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        overlay.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return overlay
    }

    /// The pill has to be at least as wide as its own title needs on one line. Anything narrower
    /// is the state that produced "2 issue" / "s".
    func testThePillIsWideEnoughForItsWholeTitleOnOneLine() {
        let view = overlay()
        view.findings = [finding("one"), finding("two")]

        let unbounded = view.reportButton.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertGreaterThanOrEqual(view.reportButton.frame.width, unbounded.width)
        XCTAssertLessThanOrEqual(view.reportButton.frame.height, unbounded.height)
    }

    /// A count that grows past the width the last one needed must widen the pill rather than wrap
    /// inside it — the exact transition that used to break, since the pill is laid out from the
    /// size the button reported for the title it had a moment ago.
    func testThePillGrowsWhenItsCountGetsLonger() {
        let view = overlay()
        view.findings = [finding("one")]
        let narrow = view.reportButton.frame

        view.findings = (0..<1000).map { finding("finding \($0)") }
        let wide = view.reportButton.frame

        XCTAssertGreaterThan(wide.width, narrow.width)
        XCTAssertEqual(wide.height, narrow.height, accuracy: 0.5)
    }

    /// With nothing found there is no pill, so there is nothing on screen for a touch to land on
    /// and every touch reaches the app underneath.
    func testThePillIsHiddenWithNoFindings() {
        let view = overlay()
        view.findings = []

        XCTAssertTrue(view.reportButton.isHidden)
        XCTAssertFalse(view.point(inside: view.reportButton.frame.origin, with: nil))
    }
}
