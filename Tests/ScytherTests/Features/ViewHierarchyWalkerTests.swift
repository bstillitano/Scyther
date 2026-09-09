//
//  ViewHierarchyWalkerTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewHierarchyWalkerTests: XCTestCase {

    private let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func makeRoot() -> UIView {
        UIView(frame: windowBounds)
    }

    func testTheTreeMirrorsTheViewHierarchy() {
        let root = makeRoot()
        let middle = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let leaf = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 50))
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.children.count, 1)
        XCTAssertEqual(snapshot.root.children[0].children.count, 1)
        XCTAssertEqual(snapshot.nodeCount, 3)
    }

    func testDepthCountsAncestorsFromTheRoot() {
        let root = makeRoot()
        let middle = UIView()
        let leaf = UIView()
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.depth, 0)
        XCTAssertEqual(snapshot.root.children[0].depth, 1)
        XCTAssertEqual(snapshot.root.children[0].children[0].depth, 2)
    }

    func testFramesAreReportedInWindowSpace() {
        let root = makeRoot()
        let middle = UIView(frame: CGRect(x: 50, y: 100, width: 200, height: 200))
        let leaf = UIView(frame: CGRect(x: 10, y: 20, width: 30, height: 40))
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let leafNode = snapshot.root.children[0].children[0]

        XCTAssertEqual(leafNode.frameInWindow, CGRect(x: 60, y: 120, width: 30, height: 40),
                       "the leaf's own frame is in its parent's space; the node's is in the window's")
    }

    func testAHiddenViewIsFlagged() {
        let root = makeRoot()
        let hidden = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        hidden.isHidden = true
        root.addSubview(hidden)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isHidden)
    }

    /// Invisibility is inherited. A child of a fully transparent parent cannot be seen, however
    /// opaque it is itself, and a badge that said otherwise would send you hunting for a view
    /// that is not on screen.
    func testAChildOfATransparentAncestorIsFlaggedHidden() {
        let root = makeRoot()
        let faded = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        faded.alpha = 0
        let child = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        faded.addSubview(child)
        root.addSubview(faded)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let childNode = snapshot.root.children[0].children[0]

        XCTAssertTrue(childNode.isHidden)
        XCTAssertEqual(childNode.className, "UIView")
    }

    func testAZeroSizeViewIsFlagged() {
        let root = makeRoot()
        let collapsed = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        root.addSubview(collapsed)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isZeroSize)
        XCTAssertFalse(snapshot.root.children[0].isHidden,
                       "zero-size and hidden are different states and are badged differently")
    }

    func testAViewOutsideTheWindowIsFlaggedOffScreen() {
        let root = makeRoot()
        let away = UIView(frame: CGRect(x: 0, y: 900, width: 100, height: 50))
        root.addSubview(away)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isOffScreen)
    }

    func testAViewPartlyOnScreenIsNotOffScreen() {
        let root = makeRoot()
        let straddling = UIView(frame: CGRect(x: 0, y: 780, width: 100, height: 50))
        root.addSubview(straddling)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertFalse(snapshot.root.children[0].isOffScreen,
                       "twenty points of it are visible, so it is on screen")
    }

    func testALabelsTextIsCarried() {
        let root = makeRoot()
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "GraphQL Demo"
        root.addSubview(label)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.children[0].text, "GraphQL Demo")
    }

    func testAButtonsTitleIsCarried() throws {
        let root = makeRoot()
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        button.setTitle("Run GraphQL Query", for: .normal)
        root.addSubview(button)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let buttonNode = try XCTUnwrap(snapshot.root.children.first)

        XCTAssertEqual(buttonNode.text, "Run GraphQL Query")
    }

    func testAPlainViewCarriesNoText() {
        let root = makeRoot()
        root.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertNil(snapshot.root.children[0].text)
    }

    /// The first thing you would otherwise find in the tree is the inspector itself.
    ///
    /// The ownership test is injected here rather than overridden on a subclass: `isScytherOwned`
    /// is a computed property on an `extension UIView: AuditNode`, and Swift does not allow a
    /// subclass to override a member declared in an extension. Production call sites use the
    /// default and therefore the real rule.
    func testScytherOwnedSubtreesAreSkipped() {
        let root = makeRoot()
        let ours = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ours.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        root.addSubview(ours)
        root.addSubview(UIView(frame: CGRect(x: 0, y: 200, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root,
                                                    windowBounds: windowBounds,
                                                    isOwned: { $0 === ours })

        XCTAssertEqual(snapshot.root.children.count, 1,
                       "the owned view and everything beneath it is gone, the host view stays")
        XCTAssertEqual(snapshot.nodeCount, 2)
    }

    /// The default really is the shared rule, not a stub that only the tests exercise.
    func testTheDefaultOwnershipTestIsScytherOwn() {
        let root = makeRoot()
        root.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.nodeCount, 2, "a plain UIView is not Scyther's, so nothing is skipped")
    }

    func testTheSideTableResolvesANodeBackToItsView() {
        let root = makeRoot()
        let child = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        root.addSubview(child)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertIdentical(snapshot.view(for: snapshot.root.children[0].id), child)
    }

    /// The point of the weak table: a snapshot must not be why a screen stays in memory.
    ///
    /// `removeFromSuperview()` autoreleases the view as part of its own bookkeeping — a
    /// documented UIKit implementation detail, not anything this walker does — so the release
    /// needs an explicit pool the way the rest of this suite drains one for the same reason
    /// (see `NetworkRuleInterceptorTests`, `BreakpointCoordinatorTests`); without it the
    /// dangling reference would still show up here, inside the same test method's own scope.
    func testTheSideTableDoesNotKeepAViewAlive() {
        let root = makeRoot()
        var child: UIView? = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        root.addSubview(child!)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let id = snapshot.root.children[0].id

        autoreleasepool {
            child!.removeFromSuperview()
            child = nil
        }

        XCTAssertNil(snapshot.view(for: id))
    }

    /// The accessibility audit hung this app in 4.3.0 by asking views for their accessibility
    /// children. This proves the walk never asks — kept honest by a spy rather than by intent.
    func testTheWalkNeverReadsAnAccessibilityProperty() {
        let root = makeRoot()
        let spy = AccessibilitySpyView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        root.addSubview(spy)

        _ = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(spy.accessibilityReads, 0)
    }
}

/// Counts every accessibility member the walk could reach through the container protocol.
private final class AccessibilitySpyView: UIView {
    var accessibilityReads = 0

    override var accessibilityElements: [Any]? {
        get { accessibilityReads += 1; return super.accessibilityElements }
        set { super.accessibilityElements = newValue }
    }

    override func accessibilityElementCount() -> Int {
        accessibilityReads += 1
        return super.accessibilityElementCount()
    }

    override func accessibilityElement(at index: Int) -> Any? {
        accessibilityReads += 1
        return super.accessibilityElement(at: index)
    }

    override var accessibilityLabel: String? {
        get { accessibilityReads += 1; return super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }
}
