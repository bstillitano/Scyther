//
//  ViewPositionMapTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

final class ViewPositionMapTests: XCTestCase {

    /// iPhone-shaped window in a square box: the outline is letterboxed, not stretched.
    private let window = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let box = CGSize(width: 100, height: 100)

    // Every expectation below is derived from these numbers by hand. `outlineInset` takes a tenth
    // off each edge, leaving an 80 × 80 interior, so the scale is min(80/400, 80/800) = 0.1, the
    // outline is 40 × 80, and centring it in the 100 × 100 box puts its origin at (30, 10).

    func testTheOutlineKeepsTheWindowsAspectRatio() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.width / outline.height, 0.5, accuracy: 0.001)
    }

    func testTheOutlineIsLetterboxedIntoTheBoxsInterior() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.height, 80, accuracy: 0.001, "height is the limiting dimension")
        XCTAssertEqual(outline.width, 40, accuracy: 0.001, "stretched to the interior it would be 80")
    }

    /// The margin is not decoration: it is where an off-screen frame gets drawn. Without it the
    /// outline fills the box in its limiting dimension and anything past the fold is clipped away.
    func testTheOutlineLeavesRoomAroundItselfOnEverySide() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertGreaterThan(outline.minY, 0)
        XCTAssertLessThan(outline.maxY, box.height)
        XCTAssertGreaterThan(outline.minX, 0)
        XCTAssertLessThan(outline.maxX, box.width)
    }

    func testTheOutlineIsCentredInTheBox() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.midX, 50, accuracy: 0.001)
        XCTAssertEqual(outline.midY, 50, accuracy: 0.001)
    }

    func testAFullScreenFrameFillsTheOutline() {
        let mapped = ViewPositionMap.rect(for: window, windowBounds: window, in: box)
        XCTAssertEqual(mapped, ViewPositionMap.outlineRect(forWindowBounds: window, in: box))
    }

    func testAFrameIsScaledAndOffsetIntoTheOutline() {
        // Top-left quarter of the window.
        let quarter = CGRect(x: 0, y: 0, width: 200, height: 400)
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        let mapped = ViewPositionMap.rect(for: quarter, windowBounds: window, in: box)

        XCTAssertEqual(mapped.origin.x, 30, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, 10, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 20, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 40, accuracy: 0.001)

        // The same expectation as the relationship those numbers stand for: a quarter of the
        // window is a quarter of the outline, pinned to the outline's own corner rather than the
        // box's.
        XCTAssertEqual(mapped.origin.x, outline.origin.x, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, outline.origin.y, accuracy: 0.001)
        XCTAssertEqual(mapped.width, outline.width / 2, accuracy: 0.001)
        XCTAssertEqual(mapped.height, outline.height / 2, accuracy: 0.001)
    }

    /// An off-screen view must map *outside* the outline rather than being clamped onto its edge.
    /// Clamping would draw a view that is 900 points down as though it sat at the bottom of the
    /// screen, which is a different and wrong answer.
    func testAnOffScreenFrameMapsOutsideTheOutline() {
        let away = CGRect(x: 0, y: 900, width: 100, height: 50)
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        let mapped = ViewPositionMap.rect(for: away, windowBounds: window, in: box)
        XCTAssertGreaterThan(mapped.minY, outline.maxY)
    }

    /// The case the inset exists for: a view that has just dropped below the fold is drawn past
    /// the outline **and still inside the box**, so the reader sees a mark below the screen rather
    /// than an outline with nothing on it.
    func testAFrameJustBelowTheFoldIsStillDrawnInsideTheBox() {
        let below = CGRect(x: 0, y: 800, width: 100, height: 44)
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        let mapped = ViewPositionMap.rect(for: below, windowBounds: window, in: box)

        XCTAssertGreaterThanOrEqual(mapped.minY, outline.maxY, "it must not be clamped onto the outline")
        XCTAssertLessThanOrEqual(mapped.maxY, box.height, "and it must not be clipped away")
    }

    func testADegenerateWindowDoesNotDivideByZero() {
        let mapped = ViewPositionMap.rect(for: CGRect(x: 0, y: 0, width: 10, height: 10),
                                          windowBounds: .zero,
                                          in: box)
        XCTAssertEqual(mapped, .zero)
    }
}
