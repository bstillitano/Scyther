//
//  LayoutGuidesTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class LayoutGuidesTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    // MARK: - Line Placement

    func testASafeAreaLineIsDrawnForEachNonZeroInset() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            margins: .zero,
            in: bounds
        )
        let safeArea = lines.filter { $0.kind == .safeArea }
        XCTAssertEqual(safeArea.count, 2)
        XCTAssertEqual(Set(safeArea.map(\.value)), [59, 34])
    }

    /// A line labelled `0.0 pt` flush against the screen edge is noise, and on a device with no
    /// home indicator the bottom inset genuinely is zero.
    func testAZeroInsetIsNotDrawn() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    func testMarginsAreDrawnSeparatelyFromSafeAreas() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .margin }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    /// Corrected from the brief: uses `try XCTUnwrap` on a `throws` test rather than `try?`
    /// swallowing the unwrap failure, so an empty `lines` result fails loudly at the unwrap
    /// rather than silently comparing `nil` against a concrete point two lines later.
    func testATopInsetLineSpansTheFullWidthAtItsOwnDepth() throws {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.start, CGPoint(x: 0, y: 59))
        XCTAssertEqual(line.end, CGPoint(x: 400, y: 59))
    }

    func testNothingIsDrawnWhenEveryInsetIsZero() {
        let lines = LayoutGuidesView.guideLines(safeArea: .zero, margins: .zero, in: bounds)
        XCTAssertTrue(lines.isEmpty)
    }

    /// The pure function has no memory of a previous call. A rotation's real bug was never
    /// here — it was the overlay's own `bounds` and `window` reads going stale — but this pins
    /// down that `guideLines` itself carries nothing forward: called once with portrait-shaped
    /// bounds and insets and again with landscape-shaped ones, the second call's lines describe
    /// only the landscape input, not a mix of the two.
    func testGuideLinesCarriesNothingForwardBetweenOrientations() {
        let portraitBounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let landscapeBounds = CGRect(x: 0, y: 0, width: 874, height: 402)

        _ = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            margins: .zero,
            in: portraitBounds
        )

        let landscapeLines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 0, left: 62, bottom: 20, right: 62),
            margins: .zero,
            in: landscapeBounds
        )

        XCTAssertEqual(Set(landscapeLines.map(\.value)), [62, 20])
        for line in landscapeLines {
            XCTAssertLessThanOrEqual(line.start.x, landscapeBounds.width)
            XCTAssertLessThanOrEqual(line.end.x, landscapeBounds.width)
            XCTAssertLessThanOrEqual(line.start.y, landscapeBounds.height)
            XCTAssertLessThanOrEqual(line.end.y, landscapeBounds.height)
        }
    }

    // MARK: - Rounding

    /// `Int(...)` truncation would print a sub-point inset as `"0 pt"` — exactly the noise the
    /// zero-inset rule exists to prevent. Rounding is what the visibility guard is written
    /// against, so an inset that rounds down to zero is not drawn at all.
    func testASubPointInsetThatRoundsToZeroIsNotDrawn() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 0.3, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        XCTAssertTrue(lines.isEmpty)
    }

    /// An inset that rounds *up* to a whole point is drawn, and ``GuideLine/roundedValue`` — what
    /// the label actually reads — reflects the rounded value rather than the truncated one.
    func testAnInsetThatRoundsUpIsDrawnWithTheRoundedValue() throws {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 0.6, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.value, 0.6)
        XCTAssertEqual(line.roundedValue, 1)
    }

    /// `20.33` truncates to `20`, which happens to be right by coincidence; `20.6` is the case
    /// that actually distinguishes rounding from truncation.
    func testASubPointRemainderRoundsRatherThanTruncates() throws {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 20.6, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.roundedValue, 21, "truncation would read 20, which is the bug")
    }

    // MARK: - Coincident Lines (Kind)

    /// Colour alone cannot separate two lines drawn at identical coordinates — the line stroked
    /// second simply paints over the line stroked first. A dash pattern means both stay visible
    /// regardless of paint order.
    func testOnlyMarginLinesAreDashed() {
        XCTAssertFalse(GuideLine.Kind.safeArea.isDashed)
        XCTAssertTrue(GuideLine.Kind.margin.isDashed)
    }

    /// The two kinds' labels sit at different fractions along the line, so a margin line
    /// coincident with a safe-area line still reads as two measurements instead of the second
    /// erasing the first — without moving where either line is actually drawn.
    func testSafeAreaAndMarginLabelsSitAtDifferentFractionsAlongACoincidentLine() {
        let start = CGPoint(x: 0, y: 100)
        let end = CGPoint(x: 400, y: 100)
        let safeArea = GuideLine(start: start, end: end, value: 16, kind: .safeArea)
        let margin = GuideLine(start: start, end: end, value: 16, kind: .margin)

        XCTAssertEqual(safeArea.labelMidpoint.x, 400.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(safeArea.labelMidpoint.y, 100)
        XCTAssertEqual(margin.labelMidpoint.x, 800.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(margin.labelMidpoint.y, 100)
        XCTAssertNotEqual(safeArea.labelMidpoint, margin.labelMidpoint)
    }

    // MARK: - Label Placement

    /// The layout ruler already solves keeping a label inside the screen —
    /// `LayoutRulerGeometry.labelOrigin(midpoint:labelSize:in:margin:)`. This asserts the guides
    /// actually route through it rather than solving clipping a second, different way: a label
    /// near the left edge must not have any part of its frame off-screen, and must not sit flush
    /// against it either — the margin the guides pass is theirs, but the clamp applying it is the
    /// ruler's.
    func testALabelNearTheLeftEdgeIsKeptFullyOnScreen() {
        let line = GuideLine(start: CGPoint(x: 16, y: 0), end: CGPoint(x: 16, y: 800), value: 16, kind: .margin)
        let frame = LayoutGuidesView.labelFrame(for: line, labelSize: CGSize(width: 40, height: 18), in: bounds.size)

        XCTAssertGreaterThanOrEqual(frame.minX, LayoutGuidesView.LabelMargin)
        XCTAssertLessThanOrEqual(frame.maxX, bounds.width - LayoutGuidesView.LabelMargin)
    }

    /// The same on the right edge, where a naive "centre on the midpoint" placement overflows
    /// the far edge instead of the near one.
    func testALabelNearTheRightEdgeIsKeptFullyOnScreen() {
        let line = GuideLine(start: CGPoint(x: 390, y: 0), end: CGPoint(x: 390, y: 800), value: 10, kind: .safeArea)
        let frame = LayoutGuidesView.labelFrame(for: line, labelSize: CGSize(width: 40, height: 18), in: bounds.size)

        XCTAssertGreaterThanOrEqual(frame.minX, LayoutGuidesView.LabelMargin)
        XCTAssertLessThanOrEqual(frame.maxX, bounds.width - LayoutGuidesView.LabelMargin)
    }

    /// The defect this margin closes. Before it, the guides called the shared clamp with no margin
    /// at all and a label on a line near an edge was placed flush against the screen — the exact
    /// behaviour the ruler had already diagnosed and fixed in a second, private clamp of its own.
    /// A right-margin line at `x = 384` with a 40 pt label used to land at `maxX = 400`, touching
    /// the edge.
    func testALabelOnALineAgainstTheRightEdgeIsNotPlacedFlushAgainstIt() {
        let line = GuideLine(start: CGPoint(x: 384, y: 0), end: CGPoint(x: 384, y: 800), value: 16, kind: .margin)
        let frame = LayoutGuidesView.labelFrame(for: line, labelSize: CGSize(width: 40, height: 18), in: bounds.size)

        XCTAssertEqual(frame.maxX, bounds.width - LayoutGuidesView.LabelMargin, accuracy: 0.001)
    }

    // MARK: - Frame Tracking (F1/F2 regression)

    /// Before the fix, `updateFrame()` ran only once, from `init(frame:)`, where `superview` is
    /// always `nil` — so the overlay's frame stayed `.zero` for its whole life unless the device
    /// happened to rotate. `didMoveToSuperview()` is what gives it a real frame the moment it is
    /// actually installed.
    ///
    /// `TopLevelViewsWrapper.updateFrame()` always sizes itself to `UIScreen.main.bounds`,
    /// ignoring whatever frame it is constructed with — and `LayoutGuidesView`'s own
    /// pre-attachment fallback reads the same `UIScreen.main.bounds`, so the two would coincide
    /// even without the fix under test. The wrapper is deliberately resized to something else
    /// immediately afterwards, so this test can only pass because ``LayoutGuidesView`` actually
    /// asked its superview, not because both happened to read the same screen.
    func testTheOverlayAcquiresTheWrappersFrameAsSoonAsItIsAdded() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        window.addSubview(wrapper)
        wrapper.frame = CGRect(x: 0, y: 0, width: 123, height: 456)

        let guides = LayoutGuidesView()
        XCTAssertNotEqual(guides.frame, wrapper.bounds, "the assertion below would be vacuous otherwise")

        wrapper.addTopLevelView(topLevelView: guides)

        XCTAssertEqual(guides.frame, wrapper.bounds)
    }

    /// Before the fix, a rotation left the overlay's frame — and everything `draw(_:)` measured
    /// from it — describing the *previous* orientation, because nothing but a notification of
    /// uncertain ordering ever told it to resize. `autoresizingMask` plus `layoutSubviews()`
    /// track the wrapper's size structurally, with no notification involved at all.
    func testTheOverlayTracksTheWrapperThroughASimulatedRotation() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        window.addSubview(wrapper)

        let guides = LayoutGuidesView()
        wrapper.addTopLevelView(topLevelView: guides)
        let portrait = wrapper.bounds
        XCTAssertEqual(guides.frame, portrait)

        // Simulate a rotation to landscape by swapping the wrapper's own dimensions, the way
        // `TopLevelViewsWrapper.updateFrame()` would after `UIScreen.main.bounds` itself rotates.
        let landscape = CGRect(x: 0, y: 0, width: portrait.height, height: portrait.width)
        wrapper.frame = landscape
        guides.layoutIfNeeded()

        XCTAssertEqual(guides.frame, landscape)

        // And back to portrait.
        wrapper.frame = portrait
        guides.layoutIfNeeded()

        XCTAssertEqual(guides.frame, portrait)
    }

    /// `updateFrame()` is still called directly by
    /// `TopLevelViewsWrapper.deviceDidChangeOrientation`, and `TopLevelView` requires the
    /// override, so it has to keep working — including before there is a superview, when it must
    /// not fall back to `.zero`.
    func testUpdateFrameFallsBackToTheScreenWhenThereIsNoSuperviewYet() {
        let guides = LayoutGuidesView()
        XCTAssertNotEqual(guides.frame, .zero)
        XCTAssertEqual(guides.frame, UIScreen.main.bounds)
    }

    // MARK: - Settings

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "LayoutGuidesTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The settings singleton itself, against a throwaway suite — not a bare read of the suite,
    /// which is `false` for every key whatsoever on an empty suite and would pass just as well if
    /// `LayoutGuides.enabled` read a different key, or a different default, entirely.
    func testTheGuidesAreOffByDefault() {
        XCTAssertFalse(LayoutGuides(defaults: defaults).enabled,
                       "an overlay that is quietly on is an overlay the developer will blame the app for")
    }

    func testEnablingPersistsToTheGivenDefaults() {
        let guides = LayoutGuides(defaults: defaults)
        guides.enabled = true

        XCTAssertTrue(defaults.bool(forKey: LayoutGuides.EnabledDefaultsKey))
    }

    func testSettingsSurviveANewInstance() {
        LayoutGuides(defaults: defaults).enabled = true
        XCTAssertTrue(LayoutGuides(defaults: defaults).enabled)
    }

    func testDisablingClearsThePersistedValue() {
        let guides = LayoutGuides(defaults: defaults)
        guides.enabled = true
        guides.enabled = false

        XCTAssertFalse(LayoutGuides(defaults: defaults).enabled)
    }
}
