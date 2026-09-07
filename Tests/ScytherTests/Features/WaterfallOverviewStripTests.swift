//
//  WaterfallOverviewStripTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// The strip draws in a `Canvas`, which a unit test cannot inspect. Its geometry is therefore a
/// pure function, and this is what proves the drawing is right — the `Canvas` only fills the
/// rects this returns.
final class WaterfallOverviewStripTests: XCTestCase {

    private let size = CGSize(width: 300, height: 90)

    func testABarSitsAtItsShareOfTheSpan() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 10,
                                                  start: 15, duration: 30, span: 60,
                                                  size: size)
        XCTAssertEqual(rect.minX, 75, accuracy: 0.001)
        XCTAssertEqual(rect.width, 150, accuracy: 0.001)
    }

    func testRowsAreStackedDownTheStrip() {
        let first = WaterfallStripGeometry.barRect(index: 0, count: 3, start: 0, duration: 1,
                                                   span: 60, size: size)
        let last = WaterfallStripGeometry.barRect(index: 2, count: 3, start: 0, duration: 1,
                                                  span: 60, size: size)
        XCTAssertLessThan(first.minY, last.minY)
        XCTAssertLessThanOrEqual(last.maxY, size.height)
    }

    /// A 20ms request in a 60s log is a third of a pixel. It has to remain a dot: the strip's
    /// whole job is showing that something happened there.
    func testAVeryShortRequestKeepsAMinimumWidth() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 10,
                                                  start: 10, duration: 0.02, span: 60,
                                                  size: size)
        XCTAssertEqual(rect.width, WaterfallStripGeometry.minimumBarWidth, accuracy: 0.001)
    }

    func testBarsThinAsTheyGetMoreNumerousButNeverVanish() {
        let few = WaterfallStripGeometry.barRect(index: 0, count: 5, start: 0, duration: 1,
                                                 span: 60, size: size)
        let many = WaterfallStripGeometry.barRect(index: 0, count: 500, start: 0, duration: 1,
                                                  span: 60, size: size)
        XCTAssertEqual(few.height, WaterfallStripGeometry.maximumBarHeight, accuracy: 0.001,
                       "a short log should not draw hairlines")
        XCTAssertGreaterThanOrEqual(many.height, 1)
        XCTAssertLessThan(many.height, few.height)
    }

    func testABarNeverLeavesTheStrip() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 1,
                                                  start: 55, duration: 30, span: 60,
                                                  size: size)
        XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.001)
    }

    func testAZeroSpanDoesNotDivideByZero() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 1,
                                                  start: 0, duration: 0, span: 0,
                                                  size: size)
        XCTAssertTrue(rect.width.isFinite)
        XCTAssertTrue(rect.minX.isFinite)
        XCTAssertTrue(rect.minY.isFinite)
    }
}
