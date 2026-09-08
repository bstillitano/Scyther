//
//  LayoutRulerGeometryTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// The ruler draws what this returns and decides nothing itself, so these tests are the only
/// place the measurement's correctness is actually established — a drag cannot be driven by a
/// test in this project, and an overlay's drawing cannot be inspected by one.
final class LayoutRulerGeometryTests: XCTestCase {

    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: - Snapping

    func testAPointAboveARectSnapsToItsTopEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 40), to: rect)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 100))
    }

    func testAPointBelowARectSnapsToItsBottomEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 260), to: rect)
        XCTAssertEqual(result.edge, .bottom)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 200))
    }

    func testAPointLeftOfARectSnapsToItsLeftEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 20, y: 150), to: rect)
        XCTAssertEqual(result.edge, .left)
        XCTAssertEqual(result.point, CGPoint(x: 100, y: 150))
    }

    func testAPointRightOfARectSnapsToItsRightEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 400, y: 150), to: rect)
        XCTAssertEqual(result.edge, .right)
        XCTAssertEqual(result.point, CGPoint(x: 300, y: 150))
    }

    /// A finger inside a view still means an edge — you are measuring to the view, not to your
    /// fingertip — and the nearest one is the honest answer.
    func testAPointInsideARectSnapsToItsNearestEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 115), to: rect)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 100))
    }

    /// The projection is clamped to the edge's own extent, so a point off the corner lands on the
    /// edge rather than on the infinite line through it.
    func testAPointOffACornerIsClampedOntoTheEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 500, y: 20), to: rect)
        XCTAssertEqual(result.point.x, 300, accuracy: 0.001)
        XCTAssertEqual(result.point.y, 100, accuracy: 0.001)
    }

    func testAnEmptyRectSnapsToItsOwnOrigin() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 50, y: 50), to: .zero)
        XCTAssertEqual(result.point, .zero)
    }

    // MARK: - Distance

    func testDistanceIsTheStraightLineBetweenTwoPoints() {
        let d = LayoutRulerGeometry.distance(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3, y: 4))
        XCTAssertEqual(d, 5, accuracy: 0.001)
    }

    func testDistanceIsZeroForTheSamePoint() {
        let d = LayoutRulerGeometry.distance(from: CGPoint(x: 7, y: 7), to: CGPoint(x: 7, y: 7))
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    // MARK: - Label placement

    func testTheLabelSitsAboveTheMidpointWhenThereIsRoom() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 300),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertEqual(origin.x, 160, accuracy: 0.001, "centred on the midpoint")
        XCTAssertLessThan(origin.y, 300, "above it")
    }

    /// A measurement near the top of the screen must not push its own label off it.
    func testTheLabelIsPushedInsideWhenItWouldLeaveTheTop() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 4),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    func testTheLabelIsPushedInsideWhenItWouldLeaveTheRight() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 396, y: 300),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertLessThanOrEqual(origin.x + 80, 400.001)
    }
}
