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
    /// edge rather than on the infinite line through it. The top and right candidates land on the
    /// same corner point here, tying; `.top` wins because it comes first in the candidate order.
    func testAPointOffACornerIsClampedOntoTheEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 500, y: 20), to: rect)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point.x, 300, accuracy: 0.001)
        XCTAssertEqual(result.point.y, 100, accuracy: 0.001)
    }

    /// A genuine four-way tie, not a coincidence of a corner: at the exact centre of a square
    /// rect all four edges are equidistant, so this is the tie-break's array order — top, then
    /// bottom, then left, then right — with nothing else to break it.
    func testAPointAtTheCentreOfASquareRectTiesAllFourEdgesAndTopWins() {
        let square = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 100, y: 100), to: square)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 100, y: 0))
    }

    func testAnEmptyRectSnapsToItsOwnOrigin() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 50, y: 50), to: .zero)
        XCTAssertEqual(result.point, .zero)
    }

    /// `CGRect.isEmpty` is true for this rect (zero width), but it is not edgeless: it is a view
    /// squeezed to a vertical line by a broken constraint — exactly what a ruler exists to
    /// measure. The left and right candidates coincide because there is no width between them,
    /// and `.left` wins that tie by array order, but the snapped point itself is a genuine
    /// measurement, not a fallback.
    func testAZeroWidthTallRectStillSnapsToARealEdge() {
        let sliver = CGRect(x: 100, y: 100, width: 0, height: 100)
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 50, y: 150), to: sliver)
        XCTAssertEqual(result.edge, .left)
        XCTAssertEqual(result.point, CGPoint(x: 100, y: 150))
    }

    /// The same case rotated: a view squeezed to a horizontal line still has real left and right
    /// edges, and the coincident top/bottom candidates still produce a genuine snapped point.
    func testAZeroHeightWideRectStillSnapsToARealEdge() {
        let sliver = CGRect(x: 100, y: 100, width: 200, height: 0)
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 150), to: sliver)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 100))
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
                                                     in: CGSize(width: 400, height: 800),
                                                     margin: 0)
        XCTAssertEqual(origin.x, 160, accuracy: 0.001, "centred on the midpoint")
        XCTAssertLessThan(origin.y, 300, "above it")
    }

    /// A measurement near the top of the screen must not push its own label off it.
    func testTheLabelIsPushedInsideWhenItWouldLeaveTheTop() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 4),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800),
                                                     margin: 0)
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    func testTheLabelIsPushedInsideWhenItWouldLeaveTheRight() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 396, y: 300),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800),
                                                     margin: 0)
        XCTAssertLessThanOrEqual(origin.x + 80, 400.001)
    }

    /// The margin is the whole reason this function takes one: both callers want their label kept
    /// off the edge rather than merely inside it, and before it was a parameter the ruler took its
    /// own inset in a second, private clamp afterwards while the guides took none at all. A label
    /// that would otherwise be pushed flush against an edge stops at the margin instead — on both
    /// axes, and on the near edge as well as the far one.
    func testTheMarginIsHonouredOnEveryEdge() {
        let bounds = CGSize(width: 400, height: 800)
        let labelSize = CGSize(width: 80, height: 20)

        let right = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 396, y: 300),
                                                    labelSize: labelSize,
                                                    in: bounds,
                                                    margin: 16)
        XCTAssertEqual(right.x + labelSize.width, bounds.width - 16, accuracy: 0.001)

        let left = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 4, y: 300),
                                                   labelSize: labelSize,
                                                   in: bounds,
                                                   margin: 16)
        XCTAssertEqual(left.x, 16, accuracy: 0.001)

        let top = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 4),
                                                  labelSize: labelSize,
                                                  in: bounds,
                                                  margin: 16)
        XCTAssertEqual(top.y, 16, accuracy: 0.001)

        let bottom = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 900),
                                                     labelSize: labelSize,
                                                     in: bounds,
                                                     margin: 16)
        XCTAssertEqual(bottom.y + labelSize.height, bounds.height - 16, accuracy: 0.001)
    }

    /// A label bigger than the space it is drawn in — plausible at accessibility text sizes on a
    /// small measurement — has no room for the inside-push clamp to satisfy on either axis, so it
    /// pins to the near edge and overflows the far one instead of computing a negative origin that
    /// would overflow both. With no margin the near edge is `0`.
    func testALabelLargerThanItsBoundsPinsToTheOriginAndOverflowsTheFarEdge() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 30, y: 15),
                                                     labelSize: CGSize(width: 100, height: 50),
                                                     in: CGSize(width: 60, height: 30),
                                                     margin: 0)
        XCTAssertEqual(origin, .zero)
    }

    /// The same case with a margin: the near edge the label pins to is the margin, not `0`, so a
    /// label too big to fit still starts where a label that fits would have.
    func testALabelLargerThanItsBoundsPinsToTheMarginRatherThanTheEdge() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 30, y: 15),
                                                     labelSize: CGSize(width: 100, height: 50),
                                                     in: CGSize(width: 60, height: 30),
                                                     margin: 16)
        XCTAssertEqual(origin, CGPoint(x: 16, y: 16))
    }
}
