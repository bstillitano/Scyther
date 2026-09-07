//
//  WaterfallDetailGeometryTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// Covers `WaterfallDetailGeometry.barRect(start:duration:window:size:)`, the detail list's own
/// equivalent of `WaterfallStripGeometry`'s bar and window geometry.
///
/// This function used to be `WaterfallDetailRow.barRect(in:)`, a private method a `GeometryReader`
/// swallowed — untestable without building a view. Extracting it is what makes the defect this
/// file's second test pins possible to catch at all: the same left-edge-pulled-back-after-the-
/// floor shape `WaterfallOverviewStripTests` already pins for `WaterfallStripGeometry`.
final class WaterfallDetailGeometryTests: XCTestCase {

    private let size = CGSize(width: 300, height: 44)

    /// A window one hundred seconds wide, the whole span, unzoomed.
    private func window(duration: TimeInterval = 100) -> WaterfallWindow {
        WaterfallWindow(start: 0, duration: duration, span: 100, narrowest: 0)
    }

    func testABarSitsAtItsPositionInTheWindow() {
        let rect = WaterfallDetailGeometry.barRect(start: 10, duration: 20, window: window(), size: size)
        // scale = 300 / 100 = 3; x = 10 * 3 = 30; width = 20 * 3 = 60
        XCTAssertEqual(rect.minX, 30, accuracy: 0.001)
        XCTAssertEqual(rect.width, 60, accuracy: 0.001)
    }

    /// A request shorter than the floor still has to register as a rectangle rather than
    /// vanishing into the row's own hairline.
    func testAVeryShortRequestKeepsTheDetailMinimumWidth() {
        let rect = WaterfallDetailGeometry.barRect(start: 10, duration: 0.001, window: window(), size: size)
        XCTAssertEqual(rect.width, WaterfallChartStyle.detailMinimumBarWidth, accuracy: 0.001)
    }

    /// The defect fixed twice already elsewhere, ported here: because
    /// ``WaterfallWindow/contains(start:duration:)`` is inclusive of the window's right edge, a
    /// request starting exactly there is part of `visibleRows` and computes a raw `x` of exactly
    /// `size.width`. The old `WaterfallDetailRow.barRect(in:)` applied the width floor *after*
    /// clamping `x`, so the floored rect's far edge ran past `size.width` — invisible once the
    /// row's own `.clipped()` removed it, leaving a row with a label, a duration, and no bar. `x`
    /// has to be pulled back *before* the floor is applied so the two clamps cannot fight.
    func testAVeryShortRequestAtTheVeryEndStillKeepsTheMinimumWidth() {
        let rect = WaterfallDetailGeometry.barRect(start: 99.999, duration: 0.0005, window: window(), size: size)
        XCTAssertEqual(rect.width, WaterfallChartStyle.detailMinimumBarWidth, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.001)
    }

    /// A request already in flight when the window opens is drawn flush to the leading edge
    /// rather than starting at a negative `x`.
    func testARequestStartingBeforeTheWindowIsClippedToTheLeadingEdge() {
        let rect = WaterfallDetailGeometry.barRect(start: -10, duration: 20, window: window(), size: size)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
    }

    /// A request outliving the window is drawn flush to the trailing edge rather than running
    /// past it.
    func testARequestOutlivingTheWindowIsClippedToTheTrailingEdge() {
        let rect = WaterfallDetailGeometry.barRect(start: 90, duration: 50, window: window(), size: size)
        XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.001)
    }

    func testAZeroDurationWindowDoesNotDivideByZero() {
        let rect = WaterfallDetailGeometry.barRect(start: 0, duration: 1, window: window(duration: 0), size: size)
        XCTAssertEqual(rect, .zero)
    }

    func testAZeroWidthPlotDoesNotDivideByZero() {
        let rect = WaterfallDetailGeometry.barRect(start: 0, duration: 1, window: window(),
                                                    size: CGSize(width: 0, height: 44))
        XCTAssertEqual(rect, .zero)
    }
}
