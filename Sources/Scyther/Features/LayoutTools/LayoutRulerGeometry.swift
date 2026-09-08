//
//  LayoutRulerGeometry.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import CoreGraphics
import Foundation

/// Every decision the ruler makes that has a right answer.
///
/// The overlay draws what this returns and decides nothing itself. That split is not tidiness:
/// an overlay's drawing cannot be inspected by a test and a drag cannot be driven by one, so
/// arithmetic left in the view is arithmetic nothing can check. This codebase has reached the
/// same conclusion three times — `WaterfallStripGeometry`, `WaterfallDetailGeometry`, and the
/// waterfall's scrub-direction check — and each time the fix was to move the maths here.
///
/// ## Topics
///
/// ### Snapping
/// - ``snapped(_:to:)``
/// - ``Edge``
///
/// ### Measuring
/// - ``distance(from:to:)``
/// - ``minimumMeasurableDistance``
///
/// ### Drawing
/// - ``labelOrigin(midpoint:labelSize:in:)``
enum LayoutRulerGeometry {

    /// Which side of a view a measurement attached to.
    ///
    /// Named for the screen, not for the layout direction. `leading` would be the wrong word
    /// here: Scyther ships a right-to-left mode that mirrors the whole app, and under it a
    /// developer's finger next to the left of a view would be told it had snapped to the
    /// trailing edge. A measurement is physical, so its vocabulary is physical.
    enum Edge: String, Sendable {
        case top, bottom, left, right
    }

    /// Below this, a drag is a tap and draws nothing.
    ///
    /// Without a floor, resting a finger produces a `0.0 pt` measurement that looks like a
    /// result rather than an accident.
    static let minimumMeasurableDistance: CGFloat = 1

    /// The point on `rect`'s nearest edge to `point`, and which edge that was.
    ///
    /// Nearest by straight-line distance among the four candidate projections, one per edge, each
    /// clamped to that edge's own extent before it is measured against — so a point off a corner
    /// lands on the corner rather than on the infinite line through the edge, which would report
    /// a measurement to somewhere the view is not. Clamping happens before the distance
    /// comparison runs, not after the nearest edge is chosen, which is what makes the clamp
    /// genuine rather than incidental: every candidate the comparison sees is already a point that
    /// actually lies on the rect's boundary.
    ///
    /// A point *inside* the rect still snaps outward to an edge. Measuring to a fingertip inside
    /// a view answers nothing; the developer means the view.
    ///
    /// - Parameters:
    ///   - point: The point to snap, in the same coordinate space as `rect`.
    ///   - rect: The hit view's frame in that space.
    /// - Returns: The snapped point and the edge it belongs to. An empty rect (zero width or
    ///   height) returns its own origin with an arbitrary edge, since a view with no extent has
    ///   no edges to choose between and the origin is the only point on it.
    static func snapped(_ point: CGPoint, to rect: CGRect) -> (point: CGPoint, edge: Edge) {
        guard !rect.isEmpty else { return (rect.origin, .top) }

        // Clamped once per axis, shared by both edges on that axis: the top and bottom
        // candidates both slide along x, the left and right candidates both slide along y.
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)

        let candidates: [(point: CGPoint, edge: Edge)] = [
            (CGPoint(x: clampedX, y: rect.minY), .top),
            (CGPoint(x: clampedX, y: rect.maxY), .bottom),
            (CGPoint(x: rect.minX, y: clampedY), .left),
            (CGPoint(x: rect.maxX, y: clampedY), .right)
        ]

        return candidates.min { distance(from: point, to: $0.point) < distance(from: point, to: $1.point) }
            ?? (rect.origin, .top)
    }

    /// The straight-line distance between two points, in points.
    ///
    /// Pulled out of ``snapped(_:to:)`` because that function needs it four times per call and a
    /// caller building the label text needs the same number, computed the same way.
    ///
    /// - Parameters:
    ///   - start: One end.
    ///   - end: The other end.
    static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Where a label of `labelSize` sits so it reads near `midpoint` without leaving `bounds`.
    ///
    /// Placed above the midpoint by preference, and offset by a small gap rather than sitting
    /// flush against it: a label drawn under the line it describes tends to land under the
    /// finger that drew it, and a label with no gap reads as touching the line rather than
    /// labelling it. Pushed back inside on every edge afterwards, since a measurement taken near
    /// the top or a side of the screen would otherwise place its own answer off it.
    ///
    /// - Parameters:
    ///   - midpoint: The middle of the drawn measurement, in the overlay's coordinate space.
    ///   - labelSize: The label's rendered size.
    ///   - bounds: The overlay's size, in the same space as `midpoint`.
    /// - Returns: The label's origin, clamped so the whole label stays within `bounds`.
    static func labelOrigin(midpoint: CGPoint, labelSize: CGSize, in bounds: CGSize) -> CGPoint {
        /// Vertical breathing room between the measurement line and its label.
        let gap: CGFloat = 8

        let x = min(max(0, midpoint.x - labelSize.width / 2), max(0, bounds.width - labelSize.width))
        let y = min(max(0, midpoint.y - labelSize.height - gap), max(0, bounds.height - labelSize.height))
        return CGPoint(x: x, y: y)
    }
}
