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
}

@MainActor
final class ViewProbeTests: XCTestCase {

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

    /// The rule the accessibility audit's hang taught, kept honest by a spy rather than by intent.
    func testTheProbeNeverAsksAViewForItsAccessibilityChildren() {
        AccessibilitySpyView.wasAsked = false
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let spy = AccessibilitySpyView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(spy)

        _ = ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root)

        XCTAssertFalse(AccessibilitySpyView.wasAsked,
                       "the probe runs per touch-move; forcing an accessibility subtree hung the app once already")
    }
}
