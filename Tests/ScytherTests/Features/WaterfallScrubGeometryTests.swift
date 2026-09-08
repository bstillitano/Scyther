//
//  WaterfallScrubGeometryTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers `WaterfallScrubGeometry.isHorizontal(width:height:)`, the decision boundary behind
/// `WaterfallOverviewStrip`'s `.scrub` interaction.
///
/// This is the one part of `WaterfallOverviewStrip.scrubGesture(width:onScrub:)` a test can reach
/// at all: the rest of that gesture lives inside a `DragGesture`'s `onChanged` closure, which
/// SwiftUI gives no way to synthesise a value for and drive as if a finger produced it. What is
/// pinned here is the actual ratio at which a drag stops counting as horizontal — the mechanism
/// that lets the strip's window-scrubbing drag live inside a scrolling `List` without capturing
/// every scroll that happens to start over it, which is what `.scrub` used to do before this fix.
/// Nothing here exercises `DragGesture`'s own `minimumDistance` behaviour, and nothing here
/// confirms the gesture actually wins or loses arbitration against a real `List`'s pan on a real
/// touch screen — that was reasoned from documentation, not observed, and needs a device pass.
final class WaterfallScrubGeometryTests: XCTestCase {

    /// A drag running straight along the horizontal axis, with no vertical component at all,
    /// clears any dominance margin trivially.
    func testAPureHorizontalDragIsHorizontal() {
        XCTAssertTrue(WaterfallScrubGeometry.isHorizontal(width: 40, height: 0))
    }

    /// A drag running straight down, with no horizontal component at all, is the case this rule
    /// exists to leave alone — the enclosing `List`'s own scroll.
    func testAPureVerticalDragIsNotHorizontal() {
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 0, height: 40))
    }

    /// `WaterfallScrubGeometry.horizontalDominance` is `2`: the horizontal component must be at
    /// least double the vertical one. This pins the boundary itself, not just its documented
    /// value, against exactly `2×` on both sides of the tie.
    func testTheDominanceRatioIsTheExactBoundary() {
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 20, height: 10),
                       "exactly double must not count — the comparison is strictly greater than")
        XCTAssertTrue(WaterfallScrubGeometry.isHorizontal(width: 20.001, height: 10),
                      "a hair past double must count")
    }

    /// A drag at 45° — equal horizontal and vertical travel — sits in the ambiguous middle this
    /// rule was deliberately widened to exclude, rather than the naive "more horizontal than
    /// vertical" (`1×`) reading a less conservative margin would have allowed.
    func testADiagonalDragAtFortyFiveDegreesIsNotHorizontal() {
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 30, height: 30))
    }

    /// A drag noticeably more horizontal than vertical, but short of the `2×` margin, is still
    /// left alone — the whole point of widening the margin past a naive `1×` tie-break.
    func testAMostlyHorizontalDragUnderTheMarginIsNotHorizontal() {
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 30, height: 20))
    }

    /// The sign of either component must not matter: a leftward drag is exactly as horizontal as
    /// a rightward one, and a drag that has looped back upward is exactly as vertical as one that
    /// only ever moved down.
    func testTheSignOfEitherComponentIsIgnored() {
        XCTAssertTrue(WaterfallScrubGeometry.isHorizontal(width: -40, height: 5))
        XCTAssertTrue(WaterfallScrubGeometry.isHorizontal(width: 40, height: -5))
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 5, height: -40))
    }

    /// No movement at all — the very first sample a real gesture could report before
    /// `minimumDistance` is satisfied — must not read as horizontal by some accident of the
    /// comparison; there is nothing to be horizontal about yet.
    func testNoMovementAtAllIsNotHorizontal() {
        XCTAssertFalse(WaterfallScrubGeometry.isHorizontal(width: 0, height: 0))
    }
}
