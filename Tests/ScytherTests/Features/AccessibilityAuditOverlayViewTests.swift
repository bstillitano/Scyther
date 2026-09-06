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

    /// Whether ``AccessibilityAuditOverlayView/draw(_:)`` put any ink on the page at all.
    ///
    /// Renders the view's own `draw(_:)` into a transparent bitmap and looks for a single non-zero
    /// byte. Deliberately asks the drawing code itself rather than reading a "would I draw?" flag:
    /// the defect was boxes visibly stroked across Scyther's own report, so the assertion should be
    /// about pixels. Any byte rather than specifically alpha, because a cleared context is
    /// all-zero regardless of which channel order the renderer picked.
    ///
    /// - Parameter view: The overlay to render.
    /// - Returns: `true` when anything at all was drawn.
    private func drawsAnything(_ view: AccessibilityAuditOverlayView) -> Bool {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            view.draw(view.bounds)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }
        return (0..<CFDataGetLength(data)).contains { bytes[$0] != 0 }
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

    /// Every box describes an element of the app *underneath*. While Scyther's own menu or its own
    /// report is in front, the overlay — which `InterfaceToolkit` keeps above everything in the key
    /// window — would stroke those boxes across Scyther's own close and Re-run buttons, pointing at
    /// rectangles where nothing they describe is on screen any more. Live mode stays on; only the
    /// drawing stops, and it comes back the moment Scyther's screen goes away.
    func testTheOverlayDrawsNothingWhileScytherIsCoveringTheApp() {
        let view = overlay()
        let coverage = CoverageStub()
        view.isCoveredByScyther = { coverage.isCovering }
        view.findings = [finding("one"), finding("two")]

        XCTAssertTrue(drawsAnything(view), "An uncovered overlay with findings should draw its boxes.")
        XCTAssertFalse(view.reportButton.isHidden)

        coverage.isCovering = true
        view.refreshForCoverageChange()

        XCTAssertFalse(drawsAnything(view), "No box should be drawn while Scyther is covering the app.")
        XCTAssertTrue(view.reportButton.isHidden, "The pill would sit over Scyther's own screen and steal its touches.")
        XCTAssertEqual(view.findings.count, 2, "Only the drawing is suppressed — the findings are still the app's.")

        coverage.isCovering = false
        view.refreshForCoverageChange()

        XCTAssertTrue(drawsAnything(view), "The boxes should come back once Scyther's screen goes away.")
        XCTAssertFalse(view.reportButton.isHidden)
    }
}

/// A stand-in for ``ScytherPresentation/isCoveringScreen`` the test can flip.
///
/// A reference type so the closure handed to the overlay reads the *current* answer rather than
/// the one that was true when it was created — the transition in both directions is the whole
/// point of the test.
@MainActor
private final class CoverageStub {
    /// Whether Scyther is pretending to cover the app.
    var isCovering = false
}
