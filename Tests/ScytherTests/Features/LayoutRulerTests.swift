//
//  LayoutRulerTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class LayoutRulerTests: XCTestCase {

    /// Two views 40pt apart vertically, in a root the probe can walk.
    private func makeTree() -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let top = UIView(frame: CGRect(x: 50, y: 100, width: 300, height: 60))
        let bottom = UIView(frame: CGRect(x: 50, y: 200, width: 300, height: 60))
        root.addSubview(top)
        root.addSubview(bottom)
        return root
    }

    func testASnappedMeasurementReportsTheGapBetweenTwoViews() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.distance, 40, accuracy: 0.001,
                       "160 to 200 is the real gap, whatever the finger did")
    }

    func testAFreeMeasurementKeepsThePointsItWasGiven() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: false)
        )
        XCTAssertEqual(measurement.start, CGPoint(x: 200, y: 150))
        XCTAssertEqual(measurement.end, CGPoint(x: 200, y: 210))
        XCTAssertEqual(measurement.distance, 60, accuracy: 0.001)
    }

    func testASnappedMeasurementNamesWhatItAttachedTo() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertNotNil(measurement.startDescription)
        XCTAssertNotNil(measurement.endDescription)
    }

    /// A free measurement has nothing to name, and inventing a name would be a lie.
    func testAFreeMeasurementNamesNothing() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 10, y: 10),
                                    to: CGPoint(x: 10, y: 90),
                                    in: root,
                                    snapping: false)
        )
        XCTAssertNil(measurement.startDescription)
        XCTAssertNil(measurement.endDescription)
    }

    /// Resting a finger must not produce a 0.0 pt result that reads like an answer.
    func testATapProducesNoMeasurement() {
        let root = makeTree()
        XCTAssertNil(LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                             to: CGPoint(x: 200, y: 150),
                                             in: root,
                                             snapping: false))
    }

    /// Snapping with nothing under a point falls back to the free point rather than reporting a
    /// snap that did not happen.
    func testSnappingFallsBackWhenThereIsNoViewUnderAPoint() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: -50, y: -50),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.start, CGPoint(x: -50, y: -50))
        XCTAssertNil(measurement.startDescription)
    }

    func testTheRulerIsInactiveAndSnappingByDefault() {
        XCTAssertFalse(LayoutRuler.instance.isActive)
        XCTAssertTrue(LayoutRuler.instance.snaps)
    }

    /// The description names the class and the edge, because that is the only name available
    /// without the view hierarchy inspector this spec excludes.
    func testASnapDescribesTheClassAndTheEdgeItAttachedTo() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.startDescription, "UIView.bottom")
        XCTAssertEqual(measurement.endDescription, "UIView.top")
    }

    /// Scyther's own interface is never what the developer meant to measure — see the probe's
    /// ownership rule, which this composes rather than re-implements.
    ///
    /// The overlay covers the whole screen while it is active, so "skip it" cannot mean "give up":
    /// it means keep looking underneath, and find the app view the developer was pointing at.
    func testTheRulerMeasuresTheAppUnderneathScythersOwnInterface() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let appView = UIView(frame: CGRect(x: 0, y: 200, width: 400, height: 100))
        root.addSubview(appView)

        let ours = LayoutRulerOverlayView(frame: root.bounds)
        ours.setActive(true)
        root.addSubview(ours)

        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 100, y: 280),
                                    to: CGPoint(x: 100, y: 500),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.start, CGPoint(x: 100, y: 300),
                       "The app view's bottom edge, not the overlay's own")
        XCTAssertEqual(measurement.startDescription, "UIView.bottom",
                       "A snap onto the ruler itself would read LayoutRulerOverlayView.top")
    }

    // MARK: - The Overlay

    func testTheOverlayIsHiddenAndSilentToVoiceOverUntilItIsActivated() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertTrue(overlay.isHidden)
        XCTAssertFalse(overlay.accessibilityViewIsModal)
    }

    /// Modal only while it is on screen: an overlay that eats every touch must not let VoiceOver
    /// wander into an app it is covering, and must not trap anyone when it is not.
    func testActivatingTheOverlayMakesItModalToVoiceOver() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        overlay.setActive(true)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertTrue(overlay.accessibilityViewIsModal)

        overlay.setActive(false)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertFalse(overlay.accessibilityViewIsModal)
    }

    /// An overlay inside a superview it tracks, which is how it lives in `TopLevelViewsWrapper`.
    ///
    /// Sizing has to come from a real superview for these tests to mean anything: `init(frame:)`
    /// runs `updateFrame()`, which with no superview falls back to `UIScreen.main.bounds`, so the
    /// frame passed to the initialiser is gone before the first line of a test runs. The previous
    /// version of the rotation test below did exactly that and passed for a reason unrelated to
    /// rotation.
    private func makeHostedOverlay(size: CGSize) -> (superview: UIView, overlay: LayoutRulerOverlayView) {
        let superview = UIView(frame: CGRect(origin: .zero, size: size))
        let overlay = LayoutRulerOverlayView(frame: .zero)
        superview.addSubview(overlay)
        return (superview, overlay)
    }

    private func aMeasurement() -> LayoutRuler.Measurement {
        LayoutRuler.Measurement(start: .zero,
                                end: CGPoint(x: 10, y: 10),
                                distance: 14,
                                startDescription: nil,
                                endDescription: nil)
    }

    /// After a rotation the endpoints describe a layout that no longer exists.
    func testARealSizeChangeClearsTheMeasurement() {
        let (superview, overlay) = makeHostedOverlay(size: CGSize(width: 400, height: 800))
        XCTAssertEqual(overlay.bounds.size, CGSize(width: 400, height: 800),
                       "the overlay has to be tracking its superview before the size change means anything")

        overlay.measurement = aMeasurement()
        superview.bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        overlay.updateFrame()

        XCTAssertNil(overlay.measurement)
    }

    /// The companion to the test above, and the one that pins the actual defect:
    /// `UIDevice.orientationDidChangeNotification` fires for face-up, face-down and for rotations a
    /// portrait-locked app never honours, and `TopLevelViewsWrapper` calls `updateFrame()` on every
    /// child for each one. None of those moves a view, so none of them may erase an answer the
    /// developer is still reading.
    func testAnUpdateThatChangesNoSizeKeepsTheMeasurement() {
        let (_, overlay) = makeHostedOverlay(size: CGSize(width: 400, height: 800))
        overlay.measurement = aMeasurement()

        overlay.updateFrame()

        XCTAssertNotNil(overlay.measurement, "laying the phone flat must not wipe a finished measurement")
    }

    /// Deactivating clears it too: a measurement left behind would be redrawn against whatever
    /// the app is showing the next time the ruler is switched on.
    func testDeactivatingClearsTheMeasurement() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        overlay.setActive(true)
        overlay.measurement = LayoutRuler.Measurement(start: .zero,
                                                      end: CGPoint(x: 10, y: 10),
                                                      distance: 14,
                                                      startDescription: nil,
                                                      endDescription: nil)
        overlay.setActive(false)
        XCTAssertNil(overlay.measurement)
    }

    /// The escape hatch behind the escape hatch: the overlay swallows every touch, so while
    /// Scyther's own menu is in front of the app it must swallow none of them.
    func testTheOverlayTakesNoTouchesWhileScytherIsCoveringTheApp() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        overlay.setActive(true)
        XCTAssertTrue(overlay.point(inside: CGPoint(x: 200, y: 400), with: nil))

        overlay.isCoveredByScyther = { true }
        XCTAssertFalse(overlay.point(inside: CGPoint(x: 200, y: 400), with: nil),
                       "shake opens the menu over the ruler; the menu has to be usable")
    }

    /// The measurement survives a modal coming and going — unlike a rotation, the app underneath
    /// has not moved — but its readout is hidden while Scyther is in front of it.
    func testCoverageHidesTheReadoutWithoutDiscardingTheMeasurement() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        overlay.setActive(true)
        overlay.measurement = LayoutRuler.Measurement(start: .zero,
                                                      end: CGPoint(x: 0, y: 40),
                                                      distance: 40,
                                                      startDescription: nil,
                                                      endDescription: nil)

        overlay.isCoveredByScyther = { true }
        overlay.refreshForCoverageChange()
        XCTAssertNotNil(overlay.measurement)

        overlay.isCoveredByScyther = { false }
        overlay.refreshForCoverageChange()
        XCTAssertNotNil(overlay.measurement)
    }

    /// The wrapper is kept at the front of the key window, so the control can end up floating over
    /// Scyther's own menu — where it looks like part of it.
    func testTheControlIsHiddenWhileScytherIsCoveringTheApp() {
        let overlay = LayoutRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        overlay.setActive(true)
        XCTAssertFalse(overlay.controlContainer.isHidden)

        overlay.isCoveredByScyther = { true }
        overlay.refreshForCoverageChange()
        XCTAssertTrue(overlay.controlContainer.isHidden)

        overlay.isCoveredByScyther = { false }
        overlay.refreshForCoverageChange()
        XCTAssertFalse(overlay.controlContainer.isHidden)
    }

    func testAFreeMeasurementReadsAsADistanceAlone() {
        let measurement = LayoutRuler.Measurement(start: .zero,
                                                  end: CGPoint(x: 0, y: 40),
                                                  distance: 40,
                                                  startDescription: nil,
                                                  endDescription: nil)
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: measurement), "40 pt")
    }

    func testASnappedMeasurementReadsAsBothViewsAndTheDistance() {
        let measurement = LayoutRuler.Measurement(start: .zero,
                                                  end: CGPoint(x: 0, y: 40),
                                                  distance: 40,
                                                  startDescription: "UILabel.bottom",
                                                  endDescription: "UIImageView.top")
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: measurement),
                       "UILabel.bottom → UIImageView.top\n40 pt")
    }

    /// The one string this feature invented: an endpoint that snapped and one that did not.
    func testAHalfSnappedMeasurementNamesTheEndThatAttachedToNothing() {
        let startSnapped = LayoutRuler.Measurement(start: .zero,
                                                   end: CGPoint(x: 0, y: 40),
                                                   distance: 40,
                                                   startDescription: "UILabel.bottom",
                                                   endDescription: nil)
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: startSnapped),
                       "UILabel.bottom → free point\n40 pt")

        let endSnapped = LayoutRuler.Measurement(start: .zero,
                                                 end: CGPoint(x: 0, y: 40),
                                                 distance: 40,
                                                 startDescription: nil,
                                                 endDescription: "UILabel.top")
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: endSnapped),
                       "free point → UILabel.top\n40 pt")
    }

    /// A fractional gap is the interesting one: a ruler that rounded `16.5` to `16` would hide
    /// exactly the discrepancy someone reached for it to find.
    func testAFractionalDistanceKeepsOneDecimal() {
        let measurement = LayoutRuler.Measurement(start: .zero,
                                                  end: CGPoint(x: 0, y: 16.5),
                                                  distance: 16.5,
                                                  startDescription: nil,
                                                  endDescription: nil)
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: measurement), "16.5 pt")
    }

    // MARK: - Placement

    /// A measurement taken near the bottom of the screen must not put its own answer behind the
    /// control: `LayoutRulerGeometry.labelOrigin` clamps to the overlay's bounds and knows nothing
    /// about the floating control, so the overlay lifts the readout clear of it.
    func testTheReadoutIsKeptClearOfTheControl() {
        let (_, overlay) = makeHostedOverlay(size: CGSize(width: 400, height: 800))
        overlay.setActive(true)
        overlay.layoutIfNeeded()
        XCTAssertFalse(overlay.controlContainer.frame.isEmpty, "the control has to be laid out to be avoided")

        // A short measurement whose midpoint sits inside the control's own frame.
        let midpoint = CGPoint(x: overlay.controlContainer.frame.midX, y: overlay.controlContainer.frame.midY)
        overlay.measurement = LayoutRuler.Measurement(start: CGPoint(x: midpoint.x, y: midpoint.y - 10),
                                                      end: CGPoint(x: midpoint.x, y: midpoint.y + 10),
                                                      distance: 20,
                                                      startDescription: nil,
                                                      endDescription: nil)

        XCTAssertFalse(overlay.readoutLabel.frame.intersects(overlay.controlContainer.frame),
                       "the readout would be behind an opaque blur")
    }

    // MARK: - No Key Window

    /// The spec's edge case: "Neither tool activates; the menu row reports it rather than appearing
    /// to work." A test process has no key window with Scyther's wrapper in it, which is exactly
    /// the condition — so this is the real thing rather than a simulated one.
    func testActivatingWithNoWindowToDrawOverReportsItAndDoesNotActivate() {
        XCTAssertFalse(InterfaceToolkit.instance.canShowLayoutRuler,
                       "the overlay is in no window in a test process, which is the case under test")

        let viewModel = MenuViewModel()
        viewModel.activateLayoutRuler()

        XCTAssertTrue(viewModel.showsLayoutRulerUnavailableAlert)
        XCTAssertFalse(LayoutRuler.instance.isActive,
                       "activating with nothing to draw over would leave no visible Done to switch it off again")
    }

}
