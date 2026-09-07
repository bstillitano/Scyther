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

    /// The half of `point(inside:with:)` that matters, and the half nothing asserted: with a pill
    /// on screen, the pill takes its own touches and **everything else reaches the app**.
    ///
    /// This is the single worst thing this view can do. Reducing the guard to
    /// `!reportButton.isHidden` — dropping the `frame.contains(point)` — makes a full-screen
    /// overlay swallow every touch in the app the moment there is one finding, and the failure its
    /// own type-level documentation spends three paragraphs on left the whole suite green. The
    /// existing test covers only the no-findings case, where the pill is hidden and the answer is
    /// `false` for a reason that has nothing to do with the rectangle.
    func testAVisiblePillTakesOnlyItsOwnTouchesAndLetsTheRestReachTheApp() {
        let view = overlay()
        view.findings = [finding("one")]
        let pill = view.reportButton.frame

        XCTAssertFalse(view.reportButton.isHidden, "the fixture is only meaningful with a pill up")
        XCTAssertTrue(view.point(inside: CGPoint(x: pill.midX, y: pill.midY), with: nil),
                      "a tap on the pill is the one touch this view is entitled to")
        XCTAssertFalse(view.point(inside: CGPoint(x: 5, y: 5), with: nil),
                       "every other touch belongs to the app underneath")
        XCTAssertFalse(view.point(inside: CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 20), with: nil),
                       "including the bottom band a tab bar or primary button occupies")
        XCTAssertFalse(view.point(inside: CGPoint(x: pill.minX - 10, y: pill.midY), with: nil),
                       "and the pixels immediately beside the pill")
    }

    /// How many flash animations are on the overlay right now.
    ///
    /// ``AccessibilityAuditOverlayView/flash(_:)`` draws through a `CAShapeLayer` added straight to
    /// the view's own layer, which is exactly how it used to escape the rule `draw(_:)` follows, so
    /// counting those layers is counting the thing that was wrong. The pill is a `UIButton`, whose
    /// layer is a plain `CALayer`, so nothing else here answers to `CAShapeLayer`.
    ///
    /// - Parameter view: The overlay to inspect.
    /// - Returns: The number of flash layers currently attached.
    private func flashes(on view: AccessibilityAuditOverlayView) -> Int {
        (view.layer.sublayers ?? []).filter { $0 is CAShapeLayer }.count
    }

    /// The pill is the only interactive thing Scyther has ever put over the running app — the grid
    /// overlay and the FPS counter both switch interaction off — so wherever it sits, it takes the
    /// app's taps there. At the bottom centre it sat squarely on a `UITabBar` (49pt plus the home
    /// indicator's safe area, full width) and on the bottom primary button of every screen without
    /// one, which is where it was seen overlapping the example app's own tab bar.
    func testThePillStaysOutOfTheBandTheAppsOwnBottomControlsOccupy() {
        let view = overlay()
        view.findings = [finding("one")]

        let bottomControls = CGRect(x: 0, y: view.bounds.maxY - 100, width: view.bounds.width, height: 100)
        XCTAssertFalse(view.reportButton.frame.intersects(bottomControls),
                       "the pill must not sit where a tab bar or a bottom primary button does")
        XCTAssertTrue(view.bounds.contains(view.reportButton.frame),
                      "and it must still be somewhere a finger can reach it")
    }

    /// A `UIView`'s default `contentMode` is `.scaleToFill`, so a bounds change with no request for
    /// a fresh `draw(_:)` stretches the last render into the new shape. On a rotation that meant
    /// every box smeared from the portrait aspect ratio into the landscape one, offset from the
    /// element it described, for at least the re-audit's debounce — and permanently if that work
    /// item was cancelled before it fired. ``GridOverlayView``, which this view says it mirrors,
    /// has always redrawn here.
    func testChangingTheOverlaysFrameAsksForAFreshDrawing() {
        let view = RecordingOverlay(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let before = view.redrawRequests

        view.updateFrame()

        XCTAssertGreaterThan(view.redrawRequests, before,
                             "a resized overlay must redraw rather than stretch its last render")
    }

    /// A flash is the same box `draw(_:)` strokes, drawn through `Core Animation` instead of `Core
    /// Graphics` — and it used to be the one drawing path that never asked whether Scyther was in
    /// front of the app. Every production flash arrives in exactly that state, because the only way
    /// to ask for one is to tap a row in the report, so the box landed on Scyther's own report every
    /// single time.
    func testAFlashIsNotDrawnOverScythersOwnScreen() {
        let view = overlay()
        let coverage = CoverageStub()
        coverage.isCovering = true
        view.isCoveredByScyther = { coverage.isCovering }
        let target = finding("one")
        view.findings = [target]

        view.flash(target)

        XCTAssertEqual(flashes(on: view), 0, "no box may be drawn while Scyther is covering the app")
    }

    /// Refusing outright would make tapping a report row do nothing, ever. The flash is held until
    /// Scyther's screen goes away and then played over the app, which is the only surface where the
    /// box describes anything.
    func testAFlashAskedForWhileCoveredIsPlayedOnceScytherGoesAway() {
        let view = overlay()
        let coverage = CoverageStub()
        coverage.isCovering = true
        view.isCoveredByScyther = { coverage.isCovering }
        let target = finding("one")
        view.findings = [target]
        view.flash(target)

        coverage.isCovering = false
        view.refreshForCoverageChange()

        XCTAssertEqual(flashes(on: view), 1, "the flash the developer asked for should reach the app")
    }

    /// The report is frozen, so the finding a row hands back can be several passes old. Flashing its
    /// remembered frame draws a box around a rectangle nothing occupies any more, which is worse
    /// than drawing nothing.
    func testAFlashIsDroppedWhenItsElementIsNoLongerOnScreen() {
        let view = overlay()
        view.findings = [finding("still here")]

        view.flash(finding("gone"))

        XCTAssertEqual(flashes(on: view), 0)
    }

    /// A flash for an element that *is* still there is drawn where the element is now, not where the
    /// frozen report says it was.
    func testAFlashFollowsTheElementToItsCurrentFrame() throws {
        let view = overlay()
        let moved = AccessibilityFinding(check: .missingLabel,
                                         severity: .error,
                                         frame: CGRect(x: 200, y: 400, width: 30, height: 30),
                                         elementName: "one",
                                         detail: "detail")
        view.findings = [moved]

        view.flash(finding("one"))

        let shape = (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.first
        let box = try XCTUnwrap(shape?.path?.boundingBox)
        XCTAssertEqual(box.origin.x, 200, accuracy: 2)
        XCTAssertEqual(box.origin.y, 400, accuracy: 2)
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

    // MARK: - Repainting

    /// The overlay's backing store is the size of the screen — around 12 MiB at 3× — and every
    /// assignment to `findings` re-rendered the whole of it. Two passes over an unchanged screen
    /// produce equal findings with fresh `UUID`s, so nothing in the model could notice, and live
    /// mode re-renders it up to twice a second.
    func testAPassThatFoundTheSameThingsDoesNotRepaintTheOverlay() {
        let view = RecordingOverlay(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.findings = [finding("one"), finding("two")]
        let painted = view.redrawRequests

        view.findings = [finding("one"), finding("two")]

        XCTAssertEqual(view.redrawRequests, painted,
                       "an identical pass must not re-render the whole surface")

        view.findings = [finding("one")]

        XCTAssertGreaterThan(view.redrawRequests, painted, "a pass that found something else must")
    }

    // MARK: - Flashing The Right Element

    /// Duplicate labels on one screen are the norm: a list of rows each with a *More* control, a
    /// form of *Clear* buttons, two *Done* buttons. Every finding carries a fresh `UUID`, so a row
    /// tapped in a re-run report cannot match by identity and fell through to the first
    /// same-check, same-label finding in tree order — the wrong element, with nothing saying it was
    /// a guess.
    func testAFlashPicksTheNearestElementWhenTwoFindingsShareALabel() throws {
        let view = overlay()
        view.isCoveredByScyther = { false }
        let first = AccessibilityFinding(check: .missingLabel, severity: .error,
                                         frame: CGRect(x: 20, y: 0, width: 30, height: 30),
                                         elementName: "More", detail: "detail")
        let seventh = AccessibilityFinding(check: .missingLabel, severity: .error,
                                           frame: CGRect(x: 20, y: 600, width: 30, height: 30),
                                           elementName: "More", detail: "detail")
        view.findings = [first, seventh]

        // The frozen report's own copy of the seventh row: a different identity, the same label,
        // and a frame from a pass taken a moment earlier.
        let fromTheReport = AccessibilityFinding(check: .missingLabel, severity: .error,
                                                 frame: CGRect(x: 20, y: 602, width: 30, height: 30),
                                                 elementName: "More", detail: "detail")
        view.flash(fromTheReport)

        let shape = (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.first
        let box = try XCTUnwrap(shape?.path?.boundingBox)
        XCTAssertEqual(box.origin.y, 600, accuracy: 2,
                       "the flash must land on the row that was tapped, not the first one sharing its name")
    }

    /// A flash asked for while Scyther covers the app is held until Scyther's screen goes away. No
    /// pass runs in the meantime, so nothing cleared it: tap a row, wander round the rest of the
    /// menu for a while, dismiss Scyther, and a box flashes over the app with no connection to
    /// anything the developer has done recently.
    func testADeferredFlashIsForgottenRatherThanFiringMinutesLater() {
        let view = overlay()
        var clock = Date(timeIntervalSince1970: 0)
        view.now = { clock }
        let coverage = CoverageStub()
        coverage.isCovering = true
        view.isCoveredByScyther = { coverage.isCovering }
        let target = finding("one")
        view.findings = [target]
        view.flash(target)

        clock = clock.addingTimeInterval(AccessibilityAuditOverlayView.deferredFlashLifetime + 1)
        coverage.isCovering = false
        view.refreshForCoverageChange()

        XCTAssertEqual(flashes(on: view), 0,
                       "a tap the developer has forgotten must not flash a box minutes later")
    }

    /// A flash asked for a moment ago is still the tap the developer just made.
    func testADeferredFlashInsideItsLifetimeStillPlays() {
        let view = overlay()
        var clock = Date(timeIntervalSince1970: 0)
        view.now = { clock }
        let coverage = CoverageStub()
        coverage.isCovering = true
        view.isCoveredByScyther = { coverage.isCovering }
        let target = finding("one")
        view.findings = [target]
        view.flash(target)

        clock = clock.addingTimeInterval(AccessibilityAuditOverlayView.deferredFlashLifetime - 1)
        coverage.isCovering = false
        view.refreshForCoverageChange()

        XCTAssertEqual(flashes(on: view), 1)
    }

    // MARK: - Split View

    /// A finding's frame is in *window* coordinates; this view is sized to `TopLevelViewsWrapper`,
    /// which sizes itself to the whole screen. On iPad, in Split View or Slide Over, the app's
    /// window is a fraction of the display, so a box stroked straight into this view's own space
    /// lands wherever the window happens to sit within the screen rather than on the element.
    func testBoxesAreDrawnInTheWindowsSpaceRatherThanTheScreens() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // What the wrapper looks like when the app owns only part of the display.
        let wrapper = UIView(frame: CGRect(x: 120, y: 40, width: 390, height: 844))
        window.addSubview(wrapper)
        let view = AccessibilityAuditOverlayView(frame: .zero)
        view.isCoveredByScyther = { false }
        wrapper.addSubview(view)
        view.updateFrame()

        let target = AccessibilityFinding(check: .missingLabel, severity: .error,
                                          frame: CGRect(x: 200, y: 400, width: 30, height: 30),
                                          elementName: "one", detail: "detail")
        view.findings = [target]
        view.flash(target)

        let shape = (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.first
        let box = try XCTUnwrap(shape?.path?.boundingBox)
        XCTAssertEqual(box.origin.x, 80, accuracy: 1, "200 in the window is 80 in this view")
        XCTAssertEqual(box.origin.y, 360, accuracy: 1, "400 in the window is 360 in this view")
    }

    /// With the overlay aligned to the window — every iPhone, and an iPad app filling the display —
    /// the conversion is the identity it has always been.
    func testBoxesAreUnmovedWhenTheOverlayAndTheWindowAgree() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let view = AccessibilityAuditOverlayView(frame: .zero)
        view.isCoveredByScyther = { false }
        window.addSubview(view)
        view.updateFrame()

        let target = AccessibilityFinding(check: .missingLabel, severity: .error,
                                          frame: CGRect(x: 200, y: 400, width: 30, height: 30),
                                          elementName: "one", detail: "detail")
        view.findings = [target]
        view.flash(target)

        let shape = (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.first
        let box = try XCTUnwrap(shape?.path?.boundingBox)
        XCTAssertEqual(box.origin.x, 200, accuracy: 1)
        XCTAssertEqual(box.origin.y, 400, accuracy: 1)
    }
}

/// An overlay that counts how many times it was asked to redraw.
///
/// `setNeedsDisplay()` leaves no trace anywhere a test can read — the redraw happens on the next
/// run-loop turn, in a view with no window to draw into — so the only honest way to assert that it
/// was asked for is to be the view it was asked of.
@MainActor
private final class RecordingOverlay: AccessibilityAuditOverlayView {
    /// How many times a redraw has been asked for.
    var redrawRequests = 0

    override func setNeedsDisplay() {
        redrawRequests += 1
        super.setNeedsDisplay()
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
