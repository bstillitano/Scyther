//
//  WaterfallCardShapeTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import UIKit
import XCTest

/// Covers the shape that gives the full-log page its grouped card.
///
/// The page is a `ScrollView`, not a `List`, so nothing draws the inset rounded card that every
/// other block on Traffic Stats sits in — the bars floated on the plain background and read as a
/// different component rather than the same chart with more room. The card is assembled from its
/// ends: the pinned ruler rounds the top two corners, the last row rounds the bottom two, and
/// every row between them rounds none. Getting that wrong is invisible until the page is looked
/// at, so the three cases are pinned here instead.
final class WaterfallCardShapeTests: XCTestCase {

    /// The rectangle every case is measured in.
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

    /// A row in the middle of the card has square corners, or the card would be a stack of
    /// separate pills rather than one continuous block.
    func testARowInTheMiddleOfTheCardIsAPlainRectangle() {
        let shape = WaterfallCardShape(corners: [], radius: 10)
        XCTAssertEqual(shape.path(in: rect).description, Path(rect).description)
    }

    /// The last row closes the card, so its bottom corners are cut away and its top corners are
    /// left square to meet the row above.
    func testTheLastRowRoundsOnlyItsBottomCorners() {
        let shape = WaterfallCardShape(corners: [.bottomLeft, .bottomRight], radius: 10)
        let path = shape.path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 20)), "the middle of the row is still drawn")
        XCTAssertTrue(path.contains(CGPoint(x: 0.5, y: 0.5)),
                      "the top corners meet the row above, so they stay square")
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 39.5)),
                       "the bottom corner is rounded away")
    }

    /// The pinned ruler opens the card the same way, from the other end.
    func testTheRulerRoundsOnlyItsTopCorners() {
        let shape = WaterfallCardShape(corners: [.topLeft, .topRight], radius: 10)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 0.5)), "the top corner is rounded away")
        XCTAssertTrue(path.contains(CGPoint(x: 0.5, y: 39.5)),
                      "the bottom corners meet the rows below, so they stay square")
    }
}
