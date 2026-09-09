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

    func testTheOutlineKeepsTheWindowsAspectRatio() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.width / outline.height, 0.5, accuracy: 0.001)
    }

    func testTheOutlineFitsInsideTheBox() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.height, 100, accuracy: 0.001, "height is the limiting dimension")
        XCTAssertEqual(outline.width, 50, accuracy: 0.001)
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
        let mapped = ViewPositionMap.rect(for: quarter, windowBounds: window, in: box)
        XCTAssertEqual(mapped.origin.x, 25, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 25, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 50, accuracy: 0.001)
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

    func testADegenerateWindowDoesNotDivideByZero() {
        let mapped = ViewPositionMap.rect(for: CGRect(x: 0, y: 0, width: 10, height: 10),
                                          windowBounds: .zero,
                                          in: box)
        XCTAssertEqual(mapped, .zero)
    }
}
