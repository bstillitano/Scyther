//
//  ViewProbeTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// A `UIView` that records whether anything asked it for its accessibility children.
///
/// The probe runs on every touch-move. Asking a view for its accessibility children makes
/// UIAccessibility compute that view's subtree recursively — the exact thing that hung the app
/// when the accessibility audit shipped in 4.3.0, on a far colder path than this one. This spy
/// is how that stays true rather than merely intended.
///
/// It covers exactly the three members that make up the quadratic hazard: reading
/// `accessibilityElements`, and the paired `UIAccessibilityContainer` methods
/// `accessibilityElementCount()` and `accessibilityElement(at:)` — `NSObject`'s default
/// implementation of that pair is what triggers `_accessibilityElements`'s recursive subtree
/// computation, and a caller could reach either one without going through the other. It does
/// *not* instrument `isAccessibilityElement`, `accessibilityLabel`, `accessibilityTraits`, or
/// `accessibilityFrame`: those are plain stored properties on `NSObject`/`UIView`, not part of
/// the container pathway, so touching them proves nothing about the hazard this spy exists to
/// catch — instrumenting them would be noise, not rigour.
private final class AccessibilitySpyView: UIView {
    nonisolated(unsafe) static var wasAsked = false

    override var accessibilityElements: [Any]? {
        get { Self.wasAsked = true; return super.accessibilityElements }
        set { super.accessibilityElements = newValue }
    }

    override func accessibilityElementCount() -> Int {
        Self.wasAsked = true
        return super.accessibilityElementCount()
    }

    override func accessibilityElement(at index: Int) -> Any? {
        Self.wasAsked = true
        return super.accessibilityElement(at: index)
    }
}

@MainActor
final class ViewProbeTests: XCTestCase {

    /// Resets the spy's flag before every test, not just the one that reads it.
    ///
    /// XCTest runs test methods alphabetically rather than in declaration order, so a reset
    /// living only at the call site of the one test that reads `wasAsked` would silently leak
    /// stale state into a second test added later that reused the spy without its own reset
    /// line. `setUp()` runs before every method regardless of who adds what, so the flag can
    /// never leak between tests.
    override func setUp() {
        super.setUp()
        AccessibilitySpyView.wasAsked = false
    }

    /// A root holding one child at a known frame.
    private func makeTree(childFrame: CGRect) -> (root: UIView, child: UIView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let child = UIView(frame: childFrame)
        root.addSubview(child)
        return (root, child)
    }

    func testTheDeepestViewUnderThePointIsReturned() {
        let (root, child) = makeTree(childFrame: CGRect(x: 50, y: 50, width: 100, height: 100))
        let grandchild = UIView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        child.addSubview(grandchild)

        let hit = ViewProbe.view(at: CGPoint(x: 70, y: 70), in: root)

        XCTAssertTrue(hit === grandchild, "a developer pointing at a label means the label")
    }

    func testAPointOverNoChildReturnsTheRoot() {
        let (root, _) = makeTree(childFrame: CGRect(x: 50, y: 50, width: 10, height: 10))
        let hit = ViewProbe.view(at: CGPoint(x: 300, y: 700), in: root)
        XCTAssertTrue(hit === root)
    }

    func testTheFrontmostOfTwoOverlappingViewsWins() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let back = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let front = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(back)
        root.addSubview(front)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === front)
    }

    func testAHiddenViewIsSkipped() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        child.isHidden = true
        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === root)
    }

    func testAFullyTransparentViewIsSkipped() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        child.alpha = 0
        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === root)
    }

    /// Measuring the ruler against its own overlay is the obvious failure, and `TopLevelView` is
    /// what every Scyther overlay inherits from.
    func testAScytherOwnedViewIsSkipped() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let ours = TopLevelView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        root.addSubview(ours)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === root)
    }

    func testAPointOutsideTheRootReturnsNothing() {
        let (root, _) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(ViewProbe.view(at: CGPoint(x: -10, y: -10), in: root))
    }

    /// Pins the documented limitation on `view(at:in:)`: descending into a subview is gated on
    /// the point falling inside that subview's *own* bounds, even when the subview does not
    /// clip. A badge pinned at a negative inset — visually on screen, painted outside its
    /// non-clipping parent's bounds — is therefore unreachable once the point lands outside the
    /// parent, matching UIKit's own `hitTest(_:with:)` rather than a defect to fix here.
    func testAnOverflowingGrandchildOutsideItsNonClippingParentsBoundsIsUnreachable() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let container = UIView(frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        XCTAssertFalse(container.clipsToBounds, "the overflow only matters when nothing clips it away")
        let badge = UIView(frame: CGRect(x: -20, y: -20, width: 20, height: 20))
        root.addSubview(container)
        container.addSubview(badge)

        // The badge occupies (80, 80)-(100, 100) in root coordinates: on screen, but outside
        // container's own frame of (100, 100)-(150, 150).
        let hit = ViewProbe.view(at: CGPoint(x: 90, y: 90), in: root)

        XCTAssertTrue(hit === root, "the walk cannot descend into container once the point misses its bounds, so the visible badge is never reached")
    }

    // MARK: - Painting

    /// The defect that made the ruler useless on iOS 26 before this rule existed: a plain SwiftUI
    /// `TabView` puts a full-screen, unpainted `FloatingBarHostingView` in front of the whole app,
    /// and the deepest-match rule returned it for every point on the screen.
    func testAnUnpaintedViewInFrontDoesNotBeatAPaintedViewBehindIt() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let painted = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        painted.backgroundColor = .red
        let passthrough = UIView(frame: root.bounds)
        root.addSubview(painted)
        root.addSubview(passthrough)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === painted,
                      "the container hosting a floating tab bar is not what the developer is pointing at")
    }

    /// A `.clear` background is a background colour that paints nothing, and it is what the
    /// containers this rule passes over most often have.
    func testAClearBackgroundDoesNotCountAsPainting() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let painted = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        painted.backgroundColor = .red
        let passthrough = UIView(frame: root.bounds)
        passthrough.backgroundColor = .clear
        root.addSubview(painted)
        root.addSubview(passthrough)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === painted)
    }

    /// The preference is a preference, not a filter: a screen of bare containers still answers.
    func testAHierarchyThatPaintsNothingStillReturnsTheDeepestView() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === child)
    }

    /// A painted view deeper inside an unpainted one is still the deepest match — descending is
    /// never gated on the parent painting anything, since an unpainted container is exactly what a
    /// painted view usually sits in.
    func testThePaintPreferenceStillDescendsThroughUnpaintedContainers() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let grandchild = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        grandchild.backgroundColor = .blue
        child.addSubview(grandchild)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === grandchild)
    }

    /// The rule the accessibility audit's hang taught, kept honest by a spy rather than by intent.
    func testTheProbeNeverAsksAViewForItsAccessibilityChildren() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let spy = AccessibilitySpyView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(spy)

        _ = ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root)

        XCTAssertFalse(AccessibilitySpyView.wasAsked,
                       "the probe runs per touch-move; forcing an accessibility subtree hung the app once already")
    }
}
