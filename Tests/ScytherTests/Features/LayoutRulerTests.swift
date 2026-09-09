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
        let readout = LayoutRulerOverlayView.readout(for: measurement)
        XCTAssertEqual(readout.distance, "40 pt")
        XCTAssertNil(readout.names, "a free measurement attached to nothing and has nothing to name")
    }

    /// The distance and the names are separate lines because they have separate rules: the
    /// distance is always shown in full, the names may be truncated.
    func testASnappedMeasurementReadsAsBothViewsAndTheDistance() {
        let measurement = LayoutRuler.Measurement(start: .zero,
                                                  end: CGPoint(x: 0, y: 40),
                                                  distance: 40,
                                                  startDescription: "UILabel.bottom",
                                                  endDescription: "UIImageView.top")
        let readout = LayoutRulerOverlayView.readout(for: measurement)
        XCTAssertEqual(readout.distance, "40 pt")
        XCTAssertEqual(readout.names, "UILabel.bottom → UIImageView.top")
    }

    /// Every name long enough to need truncating is a private UIKit class, and the underscore is
    /// the one character in it that tells a developer nothing.
    func testALeadingUnderscoreIsStrippedFromAName() {
        let measurement = LayoutRuler.Measurement(
            start: .zero,
            end: CGPoint(x: 0, y: 40),
            distance: 40,
            startDescription: "_UICollectionViewListLayoutSectionBackgroundColorDecorationView.bottom",
            endDescription: "_UITouchPassthroughView.top"
        )
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: measurement).names,
                       "UICollectionViewListLayoutSectionBackgroundColorDecorationView.bottom → UITouchPassthroughView.top")
    }

    /// The one string this feature invented: an endpoint that snapped and one that did not.
    func testAHalfSnappedMeasurementNamesTheEndThatAttachedToNothing() {
        let startSnapped = LayoutRuler.Measurement(start: .zero,
                                                   end: CGPoint(x: 0, y: 40),
                                                   distance: 40,
                                                   startDescription: "UILabel.bottom",
                                                   endDescription: nil)
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: startSnapped).names,
                       "UILabel.bottom → free point")

        let endSnapped = LayoutRuler.Measurement(start: .zero,
                                                 end: CGPoint(x: 0, y: 40),
                                                 distance: 40,
                                                 startDescription: nil,
                                                 endDescription: "UILabel.top")
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: endSnapped).names,
                       "free point → UILabel.top")
    }

    /// A fractional gap is the interesting one: a ruler that rounded `16.5` to `16` would hide
    /// exactly the discrepancy someone reached for it to find.
    func testAFractionalDistanceKeepsOneDecimal() {
        let measurement = LayoutRuler.Measurement(start: .zero,
                                                  end: CGPoint(x: 0, y: 16.5),
                                                  distance: 16.5,
                                                  startDescription: nil,
                                                  endDescription: nil)
        XCTAssertEqual(LayoutRulerOverlayView.readout(for: measurement).distance, "16.5 pt")
    }

    // MARK: - The Readout's Width

    /// The defect this cap exists for: a snap onto a SwiftUI list row names a class over sixty
    /// characters long, twice, and the readout ran off both edges of the screen with the distance
    /// buried in the middle of it.
    func testALongNamesLineIsCappedToTheOverlayLessItsMargins() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 40,
                                                        names: 4000,
                                                        availableWidth: 402)
        // The cap gives up the margin on each side *and* the padding the box draws around the
        // content, so the box itself still fits inside the overlay less its margins.
        let expected = 402 - (LayoutRulerOverlayView.ReadoutMargin + LayoutRulerOverlayView.ReadoutPadding) * 2
        XCTAssertEqual(width, expected)
    }

    /// A readout that fits keeps its natural width — the cap is a limit, not a size.
    func testAReadoutThatFitsIsNotWidened() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 40,
                                                        names: 120,
                                                        availableWidth: 402)
        XCTAssertEqual(width, 120)
    }

    /// A free measurement has no names line, so the distance alone decides the width.
    func testTheDistanceAloneDecidesTheWidthOfAFreeMeasurement() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 40,
                                                        names: 0,
                                                        availableWidth: 402)
        XCTAssertEqual(width, 40)
    }

    /// Landscape has room for a readout no one can read at a glance: around 830 points, wide
    /// enough for a long private UIKit class name at each end to fit without ever reaching the
    /// names label's middle truncation, so the readout stops being a label and becomes a strip laid
    /// across the app it is measuring. The cap is the smaller of the room available and a width the
    /// eye can take in, not the room alone.
    func testALandscapeReadoutIsCappedByTheFixedMaximumRatherThanTheRoom() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 40,
                                                        names: 4000,
                                                        availableWidth: 874)
        XCTAssertEqual(width, LayoutRulerOverlayView.ReadoutMaximumContentWidth)
    }

    /// The other half of that `min`: the room still has to be able to win. A narrow overlay caps
    /// below the fixed maximum, or the readout overhangs a small screen.
    func testTheRoomStillWinsWhenItIsNarrowerThanTheFixedMaximum() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 40,
                                                        names: 4000,
                                                        availableWidth: 402)
        XCTAssertLessThan(width, LayoutRulerOverlayView.ReadoutMaximumContentWidth)
    }

    /// The cap wins even against the distance. It cannot bite in practice — a number and a unit
    /// are never that wide — but a readout wider than the screen answers nothing at all.
    func testTheCapAppliesToAnAbsurdlyNarrowOverlay() {
        let width = LayoutRulerOverlayView.readoutWidth(distance: 400,
                                                        names: 0,
                                                        availableWidth: 20)
        XCTAssertEqual(width, 0, "never negative, and never wider than there is room for")
    }

    /// The end-to-end statement of the same rule, through the view: whatever the names say, the
    /// readout stays on screen.
    func testAReadoutWithEnormousNamesStaysWithinTheOverlay() {
        let (_, overlay) = makeHostedOverlay(size: CGSize(width: 402, height: 874))
        overlay.setActive(true)
        overlay.layoutIfNeeded()

        let long = String(repeating: "_UICollectionViewListLayoutSectionBackgroundColorDecorationView", count: 3)
        overlay.measurement = LayoutRuler.Measurement(start: CGPoint(x: 200, y: 300),
                                                      end: CGPoint(x: 200, y: 360),
                                                      distance: 60,
                                                      startDescription: "\(long).bottom",
                                                      endDescription: "\(long).top")

        let margin = LayoutRulerOverlayView.ReadoutMargin
        let frame = overlay.readoutContainer.frame
        XCTAssertTrue(overlay.bounds.contains(frame),
                      "the readout ran off the screen: \(frame) in \(overlay.bounds)")
        XCTAssertLessThanOrEqual(frame.width, overlay.bounds.width - margin * 2)
        XCTAssertGreaterThanOrEqual(frame.minX, margin, "the margin it reserved is the margin it keeps")
        XCTAssertLessThanOrEqual(frame.maxX, overlay.bounds.width - margin)
    }

    /// A measurement taken hard against an edge must not push its readout flush against it.
    func testAReadoutNearAnEdgeStaysInsideTheMargins() {
        let (_, overlay) = makeHostedOverlay(size: CGSize(width: 402, height: 874))
        overlay.setActive(true)
        overlay.layoutIfNeeded()

        overlay.measurement = LayoutRuler.Measurement(start: CGPoint(x: 400, y: 300),
                                                      end: CGPoint(x: 400, y: 360),
                                                      distance: 60,
                                                      startDescription: "UIView.right",
                                                      endDescription: "UIView.right")

        let margin = LayoutRulerOverlayView.ReadoutMargin
        XCTAssertLessThanOrEqual(overlay.readoutContainer.frame.maxX, overlay.bounds.width - margin)
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

        XCTAssertFalse(overlay.readoutContainer.frame.intersects(overlay.controlContainer.frame),
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

    /// The same spec rule for the other tool. The guides' row cannot raise an alert — a `Toggle`
    /// has moved the flag by the time it calls back — so it says the same thing by being disabled,
    /// and this is the property `MenuView` disables it on.
    func testTheGuidesRowIsUnavailableWithNoWindowToDrawOver() {
        XCTAssertFalse(InterfaceToolkit.instance.canShowLayoutGuides,
                       "the overlay is in no window in a test process, which is the case under test")
        XCTAssertFalse(MenuViewModel().canShowLayoutGuides)
    }

}
