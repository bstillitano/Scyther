@testable import Scyther
import UIKit
import XCTest

/// Covers what the walk *finds* and what it refuses to find: the accessibility properties an app
/// uses to hide things from VoiceOver, the container pattern Apple documents, the geometry the
/// audit measures, and the two ancestor walks an app can turn into a cycle.
///
/// Deliberately separate from `AuditNodeAdapterTests`, which covers the adapters' pass-through of
/// UIKit properties. Everything here is built out of real views because every one of these rules
/// reads a UIKit property that an `AuditNode` double cannot have — the exception is the node-cap
/// test at the end, which is about counting and uses a double for exactly that reason.
@MainActor
final class AuditNodeVisibilityTests: XCTestCase {

    /// Puts the coverage probe back after a test has replaced it, so one test cannot leave every
    /// later one measuring in a presentation space that is not there.
    override func tearDown() {
        ScytherPresentation.isCoveringScreenProbe = { ScytherPresentation.isCoveringScreen }
        super.tearDown()
    }

    /// A window a test can hang a hierarchy off. Unhidden because the walk skips what it cannot
    /// see, and every visibility rule below is measured against this window's bounds.
    ///
    /// - Returns: A 390 × 844 window at the screen origin.
    private func testWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }

    // MARK: - Content the app has hidden from VoiceOver

    /// The card pattern: a container sets `accessibilityElementsHidden` so VoiceOver reads one
    /// summary instead of six fragments. The walk read neither that property nor its iOS 17 block
    /// form anywhere in `Sources/`, so it descended and filed a finding for each of the six —
    /// against elements VoiceOver cannot reach.
    func testAViewThatHidesItsContentsVendsNoChildren() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        container.accessibilityElementsHidden = true
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        XCTAssertTrue((container as AuditNode).children.isEmpty)
    }

    /// The same property on a synthetic container, which can set it just as a view can — both are
    /// declared on `NSObject`'s `UIAccessibility` category.
    func testASyntheticContainerThatHidesItsContentsVendsNoChildren() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let parent = UIAccessibilityElement(accessibilityContainer: container)
        let child = UIAccessibilityElement(accessibilityContainer: parent)
        child.accessibilityLabel = "buried" // scyther:unlocalised test fixture
        parent.accessibilityElements = [child]
        parent.accessibilityElementsHidden = true

        XCTAssertTrue(AccessibilityElementNode(element: parent).children.isEmpty)
    }

    /// `accessibilityViewIsModal` tells VoiceOver to ignore every sibling subtree, which is how an
    /// in-app dialog or bottom sheet makes the screen behind it unreachable. Nothing read it, so
    /// every control underneath such a dialog was audited and boxed behind it.
    func testAModalChildHidesItsSiblings() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let behind = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let dialog = UIView(frame: CGRect(x: 20, y: 300, width: 350, height: 200))
        dialog.accessibilityViewIsModal = true
        root.addSubview(behind)
        root.addSubview(dialog)

        let children = (root as AuditNode).children

        XCTAssertEqual(children.count, 1)
        XCTAssertTrue(children.first as? UIView === dialog)
    }

    /// A dismissed dialog an app keeps around hidden still carries the flag, and honouring it
    /// would empty the audit for the whole screen — an empty report reads as "nothing is wrong",
    /// which is the worst thing this tool can say when it is wrong.
    func testAnInvisibleModalDoesNotHideItsSiblings() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let dismissed = UIView(frame: CGRect(x: 20, y: 300, width: 350, height: 200))
        dismissed.accessibilityViewIsModal = true
        dismissed.isHidden = true
        root.addSubview(content)
        root.addSubview(dismissed)

        XCTAssertEqual((root as AuditNode).children.count, 2)
    }

    /// Assigning an empty array is the documented way to say "this container vends nothing" — and
    /// the old `!elements.isEmpty` test read that instruction as "not set" and walked the subviews
    /// the app had just asked it not to.
    func testAnEmptyAccessibilityElementsArrayHidesTheSubtree() {
        let banner = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        banner.addSubview(UIImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        banner.accessibilityElements = []

        XCTAssertTrue((banner as AuditNode).children.isEmpty)
    }

    // MARK: - Apple's documented container pattern

    /// A view that draws its own content and vends `UIAccessibilityElement`s from
    /// `accessibilityElement(at:)` without setting `accessibilityElements` — a chart, seat map,
    /// calendar grid or keypad. It has no subviews, so refusing to ask the pair lost every element
    /// it vends and reported the screen clean.
    func testALeafViewThatOnlyImplementsTheContainerPairIsStillRead() {
        let chart = VendingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let point = UIAccessibilityElement(accessibilityContainer: chart)
        point.accessibilityLabel = "Seat 3A" // scyther:unlocalised test fixture
        chart.vended = [point]

        XCTAssertEqual((chart as AuditNode).children.map(\.accessibilityLabelText), ["Seat 3A"])
    }

    /// The other side of that fix, and the reason it is conditioned on having no subviews: asking
    /// a view with a subtree makes UIAccessibility compute the whole subtree, which is what hung
    /// the app when this shipped. Only leaves are asked.
    func testAViewWithSubviewsIsStillNeverAskedToComputeItsChildren() {
        VendingLeafView.computations = 0
        let container = VendingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        XCTAssertEqual((container as AuditNode).children.count, 1)
        XCTAssertEqual(VendingLeafView.computations, 0)
    }

    /// A leaf that vends nothing is the ordinary case — every `UIView` in an app — and must cost
    /// an empty answer rather than a wrong one.
    func testALeafViewThatVendsNothingHasNoChildren() {
        let plain = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue((plain as AuditNode).children.isEmpty)
    }

    // MARK: - Container cycles

    /// `accessibilityContainer` is an app-settable weak reference, so an element can be its own
    /// container. Both ancestor walks followed it with no cycle detection and no cap, on the main
    /// thread, inside a single property read — a hard hang that none of the walk's three caps can
    /// interrupt. This test does not fail without the fix; it never returns.
    func testAnElementThatContainsItselfDoesNotHangTheOwnershipWalk() {
        let element = UIAccessibilityElement(accessibilityContainer: NSObject())
        element.accessibilityContainer = element
        element.accessibilityFrame = CGRect(x: 1, y: 2, width: 3, height: 4)

        let node = AccessibilityElementNode(element: element)

        XCTAssertFalse(node.isScytherOwned)
        XCTAssertEqual(node.frameInWindow, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    /// The same hang one link further out: two elements that contain each other.
    func testATwoElementContainerCycleDoesNotHangTheOwnershipWalk() {
        let first = UIAccessibilityElement(accessibilityContainer: NSObject())
        let second = UIAccessibilityElement(accessibilityContainer: first)
        first.accessibilityContainer = second

        XCTAssertFalse(AccessibilityElementNode(element: first).isScytherOwned)
        XCTAssertFalse(AccessibilityElementNode(element: second).isScytherOwned)
    }

    // MARK: - Off screen and clipped

    /// A `UITableView` keeps a screen's worth of cells alive above and below the viewport and a
    /// `NavigationStack` parks the outgoing screen off canvas. Both are unhidden, opaque and have
    /// real non-empty window frames, and both were reported and boxed.
    func testAViewScrolledOffTheWindowIsNotVisible() {
        let window = testWindow()
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 5000))
        window.addSubview(content)
        let recycled = UIView(frame: CGRect(x: 0, y: 4000, width: 390, height: 44))
        let onScreen = UIView(frame: CGRect(x: 0, y: 100, width: 390, height: 44))
        content.addSubview(recycled)
        content.addSubview(onScreen)

        XCTAssertFalse((recycled as AuditNode).isVisible)
        XCTAssertTrue((onScreen as AuditNode).isVisible, "the row that is on screen must survive")
    }

    /// Clipping is the other half, and it is not the same test: this row is well inside the
    /// window and still invisible, because the container it sits in clips.
    func testAViewClippedAwayByAnAncestorIsNotVisible() {
        let window = testWindow()
        let clipper = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        clipper.clipsToBounds = true
        window.addSubview(clipper)
        let hidden = UIView(frame: CGRect(x: 0, y: 600, width: 390, height: 44))
        let shown = UIView(frame: CGRect(x: 0, y: 20, width: 390, height: 44))
        clipper.addSubview(hidden)
        clipper.addSubview(shown)

        XCTAssertFalse((hidden as AuditNode).isVisible)
        XCTAssertTrue((shown as AuditNode).isVisible)
    }

    /// A synthetic element is drawn *inside* the view that vends it, so that view's own clipping
    /// decides whether the element can be seen — a SwiftUI row scrolled out of a `List` vends
    /// elements exactly like the visible ones.
    func testASyntheticElementClippedAwayByItsContainerIsNotVisible() {
        let window = testWindow()
        let clipper = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        clipper.clipsToBounds = true
        window.addSubview(clipper)

        let scrolledAway = UIAccessibilityElement(accessibilityContainer: clipper)
        scrolledAway.accessibilityFrame = CGRect(x: 0, y: 600, width: 200, height: 40)
        let onScreen = UIAccessibilityElement(accessibilityContainer: clipper)
        onScreen.accessibilityFrame = CGRect(x: 0, y: 20, width: 200, height: 40)

        XCTAssertFalse(AccessibilityElementNode(element: scrolledAway).isVisible)
        XCTAssertTrue(AccessibilityElementNode(element: onScreen).isVisible)
    }

    /// An element whose container is attached to no window has nothing to be off the edge of, and
    /// must not be silently dropped — the old behaviour for every detached hierarchy, including
    /// most of this suite's.
    func testAnElementWithNoWindowStaysVisible() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityFrame = CGRect(x: 0, y: 0, width: 10, height: 10)

        XCTAssertTrue(AccessibilityElementNode(element: element).isVisible)
    }

    // MARK: - Geometry

    /// The systematic one. Opening the report presents a page sheet, and UIKit builds the card
    /// behind a page sheet by scaling the presenting view controller's view — the app under audit.
    /// Measured through it, a compliant 44 × 44pt control read about 40.5pt and was reported as a
    /// touch-target error that does not exist in the app.
    func testGeometryIgnoresScythersOwnPresentationTransform() {
        ScytherPresentation.isCoveringScreenProbe = { true }
        let window = testWindow()
        let presenting = UIView(frame: window.bounds)
        window.addSubview(presenting)
        presenting.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        presenting.addSubview(control)

        let measured = (control as AuditNode).frameInWindow

        XCTAssertEqual(measured.width, 44, accuracy: 0.01)
        XCTAssertEqual(measured.height, 44, accuracy: 0.01)
        XCTAssertEqual(measured.origin.x, 40, accuracy: 0.01)
        XCTAssertEqual(measured.origin.y, 100, accuracy: 0.01)
    }

    /// The correction is Scyther's alone. When Scyther is not on screen, a transform belongs to
    /// the app, and a control an app really does draw at 92 % really is 40.5pt across — removing
    /// that would be inventing compliance rather than measuring it.
    func testTheAppsOwnTransformIsStillMeasuredThrough() {
        ScytherPresentation.isCoveringScreenProbe = { false }
        let window = testWindow()
        let scaled = UIView(frame: window.bounds)
        window.addSubview(scaled)
        scaled.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        scaled.addSubview(control)

        XCTAssertEqual((control as AuditNode).frameInWindow.width, 44 * 0.92, accuracy: 0.01)
    }

    /// `frame` is documented as undefined under a non-identity transform, so the conversion starts
    /// from `bounds` — the form that is defined in every case.
    ///
    /// Characterisation rather than regression: UIKit happens to answer a rotated view's `frame`
    /// with the same axis-aligned bounding box the defined conversion produces, so this could not
    /// have failed before the change and is not claimed to have. What it pins down is that the
    /// bounding box really is what the audit measures — a rotated 44pt control is measured at the
    /// 62.2pt box around it, which is a known limitation of measuring rectangles rather than an
    /// accident — and that nothing here is reading a property Apple does not define.
    func testGeometryUnderARotationIsTheDefinedBoundingBox() {
        ScytherPresentation.isCoveringScreenProbe = { false }
        let window = testWindow()
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        let control = UIView(frame: CGRect(x: 100, y: 100, width: 44, height: 44))
        host.addSubview(control)
        control.transform = CGAffineTransform(rotationAngle: .pi / 4)

        let measured = (control as AuditNode).frameInWindow

        XCTAssertEqual(measured.width, 44 * CGFloat(2).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(measured.height, 44 * CGFloat(2).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(measured.midX, 122, accuracy: 0.01, "rotation is about the centre")
        XCTAssertEqual(measured.midY, 122, accuracy: 0.01)
    }

    // MARK: - Ownership

    /// The name rule is memoised per class now that it was costing a metatype demangle and a
    /// `String` allocation per ancestor per node. Memoised means the same answers, twice, and a
    /// different answer for a different class.
    func testTheNameRuleGivesTheSameAnswerEveryTimeItIsAsked() {
        XCTAssertTrue((ScytherNamedOverlayView() as AuditNode).isScytherOwned)
        XCTAssertFalse((UIView() as AuditNode).isScytherOwned)
        XCTAssertTrue((ScytherNamedOverlayView() as AuditNode).isScytherOwned)
        XCTAssertFalse((UIView() as AuditNode).isScytherOwned)
    }

    // MARK: - The node cap

    /// The cap's own documentation says it counts every node visited, and it did not: the counter
    /// sat below the skip guard, so hidden, off-screen and Scyther-owned nodes paid their full
    /// per-node cost — an ownership walk and a frame conversion each — and counted for nothing. A
    /// pooled cache of hidden subviews could therefore run the walk out of wall clock while the
    /// cap it was supposed to trip never fired.
    func testNodesTheWalkSkipsStillCountTowardsTheNodeCap() {
        let pooled = (0..<(AccessibilityAuditor.maximumNodes + 100)).map { _ in
            CountingNode(isVisible: false) as AuditNode
        }
        let root = CountingNode(children: pooled)

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertTrue(walked.didHitLimit, "a pool of skipped nodes must still trip the cap")
        XCTAssertTrue(walked.nodes.isEmpty)
    }

    /// A stand-in for a node, for the one test above that is about counting rather than about
    /// UIKit. Mirrors `AccessibilityAuditorWalkTests.Node`, which is private to that suite.
    private final class CountingNode: AuditNode {
        var isAccessibilityElementNode: Bool { false }
        var accessibilityLabelText: String? { nil }
        var traits: UIAccessibilityTraits { .none }
        var frameInWindow: CGRect { CGRect(x: 0, y: 0, width: 10, height: 10) }
        let isVisible: Bool
        var isScytherOwned: Bool { false }
        var typeName: String { "CountingNode" }
        let children: [AuditNode]

        /// Creates a node.
        ///
        /// - Parameters:
        ///   - isVisible: Whether the walk should keep it.
        ///   - children: The nodes below it.
        init(isVisible: Bool = true, children: [AuditNode] = []) {
            self.isVisible = isVisible
            self.children = children
        }
    }
}

/// A view that draws its own content and vends accessibility elements the way
/// `UIAccessibilityContainer.h` documents, counting how often it is asked.
///
/// The count is what makes the leaf exception testable in a target with no host app: a bare
/// `xctest` process has no accessibility client, so the call that costs a recursive subtree walk
/// on a device costs nothing here and cannot be caught by timing it.
private final class VendingLeafView: UIView {
    /// How many times any instance has been asked to compute its accessibility children.
    static var computations = 0

    /// The elements this view vends.
    var vended: [UIAccessibilityElement] = []

    /// Records the call and answers with the vended elements.
    ///
    /// - Returns: How many elements this view vends.
    override func accessibilityElementCount() -> Int {
        Self.computations += 1
        return vended.count
    }

    /// Records the call and answers with the vended element.
    ///
    /// - Parameter index: The element to return.
    /// - Returns: The element at `index`, or `nil` when there is none.
    override func accessibilityElement(at index: Int) -> Any? {
        Self.computations += 1
        return vended.indices.contains(index) ? vended[index] : nil
    }
}

/// One of Scyther's own overlays, recognised by the `"Scyther"` name prefix rather than by a
/// marker — the rule the per-class memoisation had to preserve exactly.
private final class ScytherNamedOverlayView: UIView { }
