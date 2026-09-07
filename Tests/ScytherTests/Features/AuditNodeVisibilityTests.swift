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

    /// Puts the presentation probe back after a test has replaced it, so one test cannot leave
    /// every later one measuring in a presentation space that is not there.
    override func tearDown() {
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            ScytherPresentation.presentationMeasurementSpace()
        }
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

    /// The two visibility rules had to become one. `honouringModality` decided a modal was live
    /// with `!isHidden && alpha > 0.01`; the walk decided visibility with a stricter rule that also
    /// culls off-window and clipped content. A custom sheet left in the hierarchy at
    /// `translationX: 0, y: 900` passes the first and fails the second, so every sibling was
    /// discarded in its favour and it was then culled itself — an empty report, `didHitLimit`
    /// false, and a green "Every enabled check passed" over a screen nothing looked at.
    func testAModalThatTheWalkWouldCullDoesNotHideItsSiblings() {
        let window = testWindow()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let content = UIView(frame: window.bounds)
        let parked = UIView(frame: CGRect(x: 20, y: 900, width: 350, height: 200))
        parked.accessibilityViewIsModal = true
        root.addSubview(content)
        root.addSubview(parked)

        XCTAssertEqual((root as AuditNode).children.count, 2)
    }

    /// Apps set `accessibilityViewIsModal` where it belongs — on the dialog — and add the dialog
    /// inside a dimming container, or let UIKit put a presented controller's view inside a
    /// `UITransitionView`. A filter that only inspects one container's immediate children never
    /// sees the flag in either shape, and audits the whole screen behind the dialog.
    func testAModalNestedInsideAContainerHidesTheContainersSiblings() {
        let window = testWindow()
        let behind = UIView(frame: window.bounds)
        let dimming = UIView(frame: window.bounds)
        let dialog = UIView(frame: CGRect(x: 20, y: 300, width: 350, height: 200))
        dialog.accessibilityViewIsModal = true
        dimming.addSubview(dialog)
        window.addSubview(behind)
        window.addSubview(dimming)

        let children = (window as AuditNode).children

        XCTAssertEqual(children.count, 1)
        XCTAssertTrue(children.first as? UIView === dimming)
    }

    /// `accessibilityElementsHidden` hides the elements *contained within* a node, not the node
    /// itself. Characterisation rather than regression — the walk already had this right — but
    /// nothing pinned the second half of it, and the card pattern is only correct if the card is
    /// still checked after its six fragments are dropped.
    func testAViewThatHidesItsContentsIsStillCheckedItself() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        card.isAccessibilityElement = true
        card.accessibilityElementsHidden = true
        card.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        root.addSubview(card)

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertEqual(walked.nodes.count, 1)
        XCTAssertTrue(walked.nodes.first as? UIView === card)
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

    /// "No subviews" was the wrong discriminator. A chart with a title label, a seat map with a
    /// background image, a cell that vends its drawn sub-parts while holding a selected-background
    /// view — every one of them has a subview and every one of them was invisible to the audit,
    /// which is the whole class of hand-rolled view the exception exists to catch.
    func testAContainerThatVendsElementsIsReadEvenWhenItHasSubviews() {
        let chart = VendingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        chart.addSubview(UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 20)))
        let point = UIAccessibilityElement(accessibilityContainer: chart)
        point.accessibilityLabel = "Seat 3A" // scyther:unlocalised test fixture
        chart.vended = [point]

        XCTAssertEqual((chart as AuditNode).children.map(\.accessibilityLabelText), ["Seat 3A"])
    }

    /// The reason the old rule existed, kept: asking a view that has *not* implemented the pair
    /// makes UIAccessibility compute its whole subtree, which is what hung the app when this
    /// shipped. The discriminator is now whether the class overrides the pair at all, so every
    /// stock UIKit class — the overwhelming majority of nodes on any screen — is never asked. This
    /// is the one test in the suite that has to run against the real Objective-C runtime, and it
    /// does: `class_getMethodImplementation` answers about UIKit's actual method tables.
    func testStockViewClassesAreNeverAskedToComputeTheirChildren() {
        XCTAssertFalse(declaresAccessibilityElements(UIView.self))
        XCTAssertFalse(declaresAccessibilityElements(UILabel.self))
        XCTAssertFalse(declaresAccessibilityElements(UIScrollView.self))
        XCTAssertFalse(declaresAccessibilityElements(UITableView.self))
        XCTAssertFalse(declaresAccessibilityElements(UICollectionView.self))
        XCTAssertFalse(declaresAccessibilityElements(UIStackView.self))
        XCTAssertTrue(declaresAccessibilityElements(VendingLeafView.self))
    }

    /// A container is not believed when it claims to vend more elements than the walk could hold
    /// anyway. The array was materialised inside a single `children` read, before the walk could
    /// count a node or read the clock even once, so a claim of 100,000 was a hang the caps could
    /// not reach.
    func testAContainerClaimingMoreElementsThanTheWalkCanHoldVendsNothing() {
        let absurd = VendingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        absurd.vended = (0..<(AccessibilityAuditor.maximumNodes + 1)).map { _ in
            UIAccessibilityElement(accessibilityContainer: absurd)
        }

        XCTAssertTrue((absurd as AuditNode).children.isEmpty)
    }

    /// A container at exactly the cap is still believed, so the cap is a number rather than an
    /// inequality: without this, the test above passes for a cap of one.
    func testAContainerAtExactlyTheCapIsStillRead() {
        let atTheLimit = CountingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let real = UIAccessibilityElement(accessibilityContainer: atTheLimit)
        real.accessibilityLabel = "first" // scyther:unlocalised test fixture
        real.accessibilityFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        atTheLimit.claimedCount = AccessibilityAuditor.maximumNodes
        atTheLimit.first = real

        XCTAssertEqual((atTheLimit as AuditNode).children.compactMap(\.accessibilityLabelText), ["first"])
    }

    /// `NSObject`'s own `accessibilityElementCount()` answers `NSNotFound` when it has nothing to
    /// say, and `NSNotFound` is `Int.max` to a `for` loop.
    ///
    /// This is the guard wave C's fix rests on — re-enabling the container pair for leaf views is
    /// only safe because the count is sanity-capped — and nothing tested it. Note honestly what
    /// removing the guard does: `(0..<NSNotFound).compactMap` is a hang, not a failure, so this
    /// test cannot be *watched* going red. It is a regression guard, and the cap it guards is
    /// pinned to a number by the two tests above it.
    func testAContainerClaimingNSNotFoundChildrenVendsNothing() {
        let nonsense = CountingLeafView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        nonsense.claimedCount = NSNotFound

        XCTAssertTrue((nonsense as AuditNode).children.isEmpty)
        XCTAssertGreaterThan(NSNotFound, AccessibilityAuditor.maximumNodes,
                             "the cap is only a guard against NSNotFound while it is below it")
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

    /// The r2 defect measured on device: a caption scrolled underneath a navigation bar was
    /// measured as though it were on screen and reported as "about 1.0:1, `#0A0A0A` on `#040404`".
    /// A `List` inside a `NavigationStack` fills the window and scrolls its content *under* the
    /// bar, so the caption is inside the scroll view's bounds and inside the window — nothing in
    /// the clipping rule can see a sibling drawn on top of it.
    func testAViewScrolledUnderAnOpaqueBarIsNotVisible() {
        let window = testWindow()
        let scroll = UIScrollView(frame: window.bounds)
        scroll.clipsToBounds = true
        window.addSubview(scroll)
        let caption = UIView(frame: CGRect(x: 32, y: 30, width: 333, height: 30))
        scroll.addSubview(caption)
        let navigationBar = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        navigationBar.backgroundColor = .black
        window.addSubview(navigationBar)

        XCTAssertFalse((caption as AuditNode).isVisible)
    }

    /// The other side of it: a bar that does not actually cover the element leaves it alone. An
    /// occlusion rule that culled anything a bar merely *overlapped* would throw away the top row
    /// of every scrolling screen there is.
    func testAViewOnlyPartlyUnderABarIsStillVisible() {
        let window = testWindow()
        let scroll = UIScrollView(frame: window.bounds)
        window.addSubview(scroll)
        let caption = UIView(frame: CGRect(x: 32, y: 80, width: 333, height: 60))
        scroll.addSubview(caption)
        let navigationBar = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        navigationBar.backgroundColor = .black
        window.addSubview(navigationBar)

        XCTAssertTrue((caption as AuditNode).isVisible)
    }

    /// A transparent view drawn on top covers nothing. `UIView.isOpaque` defaults to `true` on
    /// every view in the process, so it is the *material* a view draws — a background colour, a
    /// blur — that decides, not what the view claims about its own compositing.
    func testAColourlessViewDrawnOnTopDoesNotOccludeAnything() {
        let window = testWindow()
        let caption = UIView(frame: CGRect(x: 32, y: 30, width: 333, height: 30))
        window.addSubview(caption)
        window.addSubview(UIView(frame: window.bounds))

        XCTAssertTrue((caption as AuditNode).isVisible)
    }

    /// A container that does not clip cannot bound its children, which is exactly what
    /// `clippedRegion` says by intersecting only `clipsToBounds` ancestors. Pruning the subtree on
    /// the container's own frame said the opposite, and lost every child of a stretchy header laid
    /// out above the window with its content pinned back into view.
    func testANonClippingContainerWhoseChildrenAreOnScreenIsStillWalked() {
        let window = testWindow()
        let header = UIView(frame: CGRect(x: 0, y: -250, width: 390, height: 200))
        window.addSubview(header)
        let pinned = UIView(frame: CGRect(x: 0, y: 260, width: 390, height: 44))
        header.addSubview(pinned)

        XCTAssertTrue((header as AuditNode).isVisible, "its child is on screen, so it must be walked")
        XCTAssertTrue((pinned as AuditNode).isVisible)
    }

    /// And the case that keeps the rule honest: a non-clipping container whose children are off
    /// screen too — a recycled table-view cell, which is what the off-screen cull was written for
    /// — is still pruned.
    func testANonClippingContainerWithNothingOnScreenIsStillPruned() {
        let window = testWindow()
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 5000))
        window.addSubview(content)
        let recycled = UIView(frame: CGRect(x: 0, y: 4000, width: 390, height: 44))
        content.addSubview(recycled)
        recycled.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44)))

        XCTAssertFalse((recycled as AuditNode).isVisible)
    }

    // MARK: - Geometry

    /// The systematic one. Opening the report presents a page sheet, and UIKit builds the card
    /// behind a page sheet by scaling the presenting view controller's view — the app under audit.
    /// Measured through it, a compliant 44 × 44pt control read about 40.5pt and was reported as a
    /// touch-target error that does not exist in the app.
    func testGeometryIgnoresScythersOwnPresentationTransform() {
        let window = testWindow()
        let presenting = UIView(frame: window.bounds)
        window.addSubview(presenting)
        presenting.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        ScytherPresentation.presentationMeasurementSpaceProbe = { presenting }
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
        ScytherPresentation.presentationMeasurementSpaceProbe = { nil }
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
        ScytherPresentation.presentationMeasurementSpaceProbe = { nil }
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

    /// The correction has to be the presentation's own transform and nothing else. UIKit does not
    /// scale the presenting view behind a page sheet in a regular-width environment, and never for
    /// a full-screen presentation — so "remove the outermost transform while Scyther is up" deleted
    /// the app's own drawer or zoom transform instead, and a control an app really does draw at
    /// 36pt was measured at 44 and its finding disappeared.
    func testTheAppsOwnTransformSurvivesAPresentationThatTransformsNothing() {
        ScytherPresentation.presentationMeasurementSpaceProbe = { nil }
        let window = testWindow()
        let presenting = UIView(frame: window.bounds)
        window.addSubview(presenting)
        let drawer = UIView(frame: window.bounds)
        presenting.addSubview(drawer)
        drawer.transform = CGAffineTransform(scaleX: 0.83, y: 0.83)
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        drawer.addSubview(control)

        XCTAssertEqual((control as AuditNode).frameInWindow.width, 44 * 0.83, accuracy: 0.01)
    }

    /// The pass's dominant cost is asked-and-answered questions, and this one was asked three
    /// times for a single node: once by `isVisible`, once by the `frameInWindow` inside it, and
    /// once by the walk's own `frameInWindow` read. It is a fact about the *screen*, not about the
    /// node, so a node resolves it once and hands it to everything that needs it.
    func testDecidingVisibilityAsksAboutScythersPresentationOnce() {
        var asked = 0
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            asked += 1
            return nil
        }
        let window = testWindow()
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        host.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        host.addSubview(control)

        _ = (control as AuditNode).isVisible

        XCTAssertEqual(asked, 1)
    }

    /// The correction is the presentation's own, and it applies to what is *inside* the
    /// presentation's space and nothing else. "Scyther is on screen somewhere" is a fact about the
    /// process, not about this node's ancestors, and using it to authorise removing an outermost
    /// transform deleted transforms belonging to subtrees the presentation never touched.
    func testAViewOutsideScythersPresentationKeepsItsOwnTransform() {
        let window = testWindow()
        let presenting = UIView(frame: window.bounds)
        presenting.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        window.addSubview(presenting)
        let zoomed = UIView(frame: window.bounds)
        window.addSubview(zoomed)
        zoomed.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        zoomed.addSubview(control)
        ScytherPresentation.presentationMeasurementSpaceProbe = { presenting }

        XCTAssertEqual((control as AuditNode).frameInWindow.width, 22, accuracy: 0.01)
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

/// A leaf view that claims a number of accessibility children without having to build them.
///
/// ``VendingLeafView`` derives its count from an array, so it cannot express the two answers that
/// matter here: a count above the cap, which would mean allocating five thousand elements to make
/// the point, and `NSNotFound`, which cannot be an array count at all.
@MainActor
private final class CountingLeafView: UIView {
    /// What this view claims when asked how many elements it vends.
    var claimedCount = 0

    /// The one element it can actually produce, at index zero.
    var first: UIAccessibilityElement?

    /// Answers ``claimedCount``, however absurd it is.
    ///
    /// - Returns: The claimed count.
    override func accessibilityElementCount() -> Int { claimedCount }

    /// Answers ``first`` at index zero and nothing anywhere else.
    ///
    /// - Parameter index: The element to return.
    /// - Returns: ``first`` when `index` is zero, otherwise `nil`.
    override func accessibilityElement(at index: Int) -> Any? { index == 0 ? first : nil }
}

/// One of Scyther's own overlays, recognised by the `"Scyther"` name prefix rather than by a
/// marker — the rule the per-class memoisation had to preserve exactly.
private final class ScytherNamedOverlayView: UIView { }
