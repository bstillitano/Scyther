@testable import Scyther
import SwiftUI
import UIKit
import XCTest

/// Verifies the adapters that connect the pure `AuditNode` model to real UIKit: a `UIView`'s
/// conformance, `AccessibilityElementNode`'s wrapping of synthetic accessibility elements, and
/// `WindowContrastSampler`'s reading of pixels from an actual window.
@MainActor
final class AuditNodeAdapterTests: XCTestCase {

    func testAViewReportsItsAccessibilityPropertiesThroughTheProtocol() {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        button.accessibilityLabel = "Close"
        button.isAccessibilityElement = true
        // A plain, unattached `UIButton` never resolves its own implicit `.button` trait outside
        // a live accessibility runtime (no window scene, no VoiceOver session in a unit test
        // host) — every system control's `accessibilityTraits` reads back `[]` here regardless
        // of type, title, or configuration. Setting the trait directly is what an app does when
        // it wants a guaranteed trait anyway, and it keeps this test about the adapter's
        // pass-through rather than about a UIKit runtime dependency this test host doesn't have.
        button.accessibilityTraits = .button

        let node: AuditNode = button

        XCTAssertTrue(node.isAccessibilityElementNode)
        XCTAssertEqual(node.accessibilityLabelText, "Close")
        XCTAssertTrue(node.traits.contains(.button))
        XCTAssertEqual(node.typeName, "UIButton")
    }

    func testAHiddenViewIsNotVisible() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.isHidden = true
        XCTAssertFalse((view as AuditNode).isVisible)
    }

    func testAFullyTransparentViewIsNotVisible() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.alpha = 0
        XCTAssertFalse((view as AuditNode).isVisible)
    }

    /// Scyther's own overlays are marked so the audit can leave them alone.
    func testScytherOwnedViewsAreRecognised() {
        let wrapper = TopLevelViewsWrapper(frame: .zero)
        XCTAssertTrue((wrapper as AuditNode).isScytherOwned)
        XCTAssertFalse((UIView() as AuditNode).isScytherOwned)
    }

    /// The defect: with live mode on and Scyther's own report open, the overlay stroked red error
    /// boxes over Scyther's close button. Every Scyther screen is SwiftUI, so the view a presented
    /// screen hangs off is `_UIHostingView<…>` — a private SwiftUI type naming Scyther nowhere —
    /// and a walk up `superview` alone stops there without ever reaching the controller above it.
    /// Ownership now comes from the owning view controller, so this is built for real rather than
    /// asserted against a type name.
    func testAViewInsideAScytherPresentedControllerIsScytherOwned() {
        let hosted = ScytherHostingController(rootView: Text("Scyther"))
        hosted.loadViewIfNeeded()
        let inside = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        hosted.view.addSubview(inside)

        XCTAssertTrue((hosted.view as AuditNode).isScytherOwned)
        XCTAssertTrue((inside as AuditNode).isScytherOwned)
    }

    /// The other half of the same rule: the app's own SwiftUI screens are the whole point of the
    /// audit, and hosting a view in a `UIHostingController` must not exempt it from anything.
    func testAViewInsideTheAppsOwnHostingControllerIsNotScytherOwned() {
        let hosted = UIHostingController(rootView: Text("App"))
        hosted.loadViewIfNeeded()
        let inside = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        hosted.view.addSubview(inside)

        XCTAssertFalse((hosted.view as AuditNode).isScytherOwned)
        XCTAssertFalse((inside as AuditNode).isScytherOwned)
    }

    /// Ownership has to come from *structure*, not from spelling — matching a type-name prefix is
    /// the guess that produced the defect above. `MarkerOnlyPresentedController`'s name mentions
    /// Scyther nowhere and it is not a `TopLevelView`, so the only thing that can identify it is
    /// the `ScytherPresentedUI` marker it adopts.
    func testOwnershipComesFromTheMarkerRatherThanFromTheTypeName() {
        let controller = MarkerOnlyPresentedController()
        controller.loadViewIfNeeded()
        let inside = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        controller.view.addSubview(inside)

        XCTAssertFalse(String(describing: type(of: controller)).hasPrefix("Scyther"))
        XCTAssertTrue((inside as AuditNode).isScytherOwned)
    }

    /// A SwiftUI screen vends synthetic accessibility elements rather than views, so the element
    /// side of the walk has to reach the owning controller too — otherwise the audit would skip
    /// Scyther's own `UIView`s and report its `Text`s.
    func testASyntheticElementInsideAScytherPresentedControllerIsScytherOwned() {
        let hosted = ScytherHostingController(rootView: Text("Scyther"))
        hosted.loadViewIfNeeded()
        let element = UIAccessibilityElement(accessibilityContainer: hosted.view as Any)

        XCTAssertTrue(AccessibilityElementNode(element: element).isScytherOwned)
    }

    /// A container that exposes accessibility children is walked through them, not its subviews.
    func testAccessibilityChildrenWinOverSubviews() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "synthetic"
        element.accessibilityFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        container.accessibilityElements = [element]

        let children = (container as AuditNode).children

        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.accessibilityLabelText, "synthetic")
    }

    /// A window not at the screen origin (Split View, Slide Over, Stage Manager, ...) must not
    /// leak `accessibilityFrame`'s screen coordinates into `frameInWindow` unconverted — the
    /// overlay box and the contrast sampler's crop both assume window-local coordinates.
    func testSyntheticElementFrameIsConvertedFromScreenToWindowCoordinates() {
        let window = UIWindow(frame: CGRect(x: 100, y: 50, width: 200, height: 200))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.addSubview(container)
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityFrame = CGRect(x: 120, y: 70, width: 40, height: 40)

        let node = AccessibilityElementNode(element: element)

        XCTAssertEqual(node.frameInWindow, CGRect(x: 20, y: 20, width: 40, height: 40))
    }

    /// This test used to claim the sampler read back the colour of what was drawn, and it never
    /// did. `ScytherTests` has no host app, so `drawHierarchy(in:afterScreenUpdates:)` returns
    /// `false` and paints nothing for any window a test can build; the black it asserted on came
    /// from the `CALayer.render(in:)` fallback, and would equally have come from a fully
    /// transparent pixel, whose red component un-premultiplies to zero. Two assertions, neither
    /// able to fail. The fallback is gone — it bypassed iOS's non-capturable-content protection
    /// and would rasterise a secure text field — so what is left to assert is the honest thing:
    /// the sampler admits it captured nothing rather than reaching for an API that would have.
    ///
    /// - Note: The colour-reading itself is covered in `WindowContrastSamplerSafetyTests` against
    ///   raw bytes, which is the only place in this host it can be covered at all.
    func testTheSamplerRefusesToInventPixelsForAWindowItCouldNotCapture() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.backgroundColor = .black
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.layoutIfNeeded()

        let sampler = WindowContrastSampler(window: window)

        XCTAssertFalse(sampler.didCaptureWindow)
        XCTAssertTrue(sampler.samples(in: CGRect(x: 10, y: 10, width: 20, height: 20)).isEmpty)
    }

    func testTheSamplerReturnsNothingForARegionOutsideTheWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let sampler = WindowContrastSampler(window: window)
        XCTAssertTrue(sampler.samples(in: CGRect(x: 500, y: 500, width: 10, height: 10)).isEmpty)
    }

    /// A genuinely large real view hierarchy: 40 containers of 40 `UILabel`s, 1,642 nodes in all.
    ///
    /// - Returns: The window at the top of it, already unhidden — a `UIWindow` starts out hidden
    ///   and the walk skips a node it cannot see, so without that the walk stops at the root.
    private func largeRealHierarchy() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        for _ in 0..<40 {
            let container = UIView(frame: root.bounds)
            for index in 0..<40 {
                let label = UILabel(frame: CGRect(x: 0, y: index * 20, width: 200, height: 18))
                label.text = "row \(index)" // scyther:unlocalised test fixture
                container.addSubview(label)
            }
            root.addSubview(container)
        }
        return window
    }

    /// The walk of a real hierarchy stops when the pass's deadline passes, rather than running it
    /// to the end.
    ///
    /// **What this replaces, and why.** There used to be a wall-clock assertion here —
    /// `elapsed < 1.0` over this same fixture — and it could not fail, for three reasons that all
    /// still hold. `collect(root:)` takes a deadline unconditionally and abandons itself at
    /// ``AccessibilityAuditor/budget``, so a walk of any hierarchy is *guaranteed by production* to
    /// finish inside a second and the assertion was true by construction. The threshold was four
    /// times the budget in any case, so it would not have objected to a pass four times over the
    /// bound the branch spent a wave installing. And a bare `xctest` process has no accessibility
    /// client, so the expensive call the fixture was built to provoke — `_accessibilityElements`
    /// computing a subtree — costs nothing here whatever the walk does.
    ///
    /// The clock is the honest instrument instead: driven by hand, this asserts that the deadline
    /// really does stop a walk of 1,642 *real* views, and that the stop is a stop rather than a
    /// flag raised while the walk carries on to the end.
    ///
    /// **What now guards the hang the old test was aimed at.**
    /// `testOnlyAViewWhoseClassImplementsThePairIsAskedToComputeItsChildren`, below, which asserts
    /// the actual rule — a class that has not overridden the `UIAccessibilityContainer` pair
    /// inherits `NSObject`'s implementation and is therefore never asked — against a call counter
    /// rather than against a stopwatch. `AuditNodeVisibilityTests` covers the rest of the same
    /// ground: the two container-cycle tests, and
    /// `testAContainerClaimingMoreElementsThanTheWalkCanHoldVendsNothing`.
    func testALargeRealHierarchyIsAbandonedAtTheDeadline() {
        let window = largeRealHierarchy()
        let start = Date()
        var readings = 0
        var auditor = AccessibilityAuditor.unbudgeted()
        auditor.now = {
            readings += 1
            return start.addingTimeInterval(readings > 200 ? AccessibilityAuditor.budget + 0.1 : 0)
        }

        let walked = auditor.collect(root: window)

        XCTAssertTrue(walked.didHitLimit, "a walk stopped by the deadline must say the report is partial")
        XCTAssertLessThan(readings, 300,
                          "the deadline must stop the walk, not be noticed once per node all the way down")
    }

    /// The other half: a real hierarchy that fits inside every bound is walked to the end and is
    /// not reported as truncated. Without this, a walk that gave up immediately would satisfy the
    /// test above.
    func testALargeRealHierarchyInsideEveryBoundIsNotReportedAsTruncated() {
        let window = largeRealHierarchy()
        let start = Date()
        var auditor = AccessibilityAuditor.unbudgeted()
        auditor.now = { start }

        XCTAssertFalse(auditor.collect(root: window).didHitLimit,
                       "1,642 nodes is inside the 5,000-node cap and 100-deep limit")
    }

    /// A `UIView` subclass that records every time it is asked to compute its accessibility
    /// children, standing in for what UIAccessibility does on a device.
    ///
    /// A bare `xctest` process has no window scene and no accessibility client, so
    /// `_accessibilityElements` never computes anything and `accessibilityElementCount()` answers
    /// `0` for every real view in microseconds — the exact call that costs a recursive subtree walk
    /// on a device costs nothing here. This class puts the cost back where the test host removed
    /// it, by counting the calls instead of timing them. Note what overriding the pair *means*,
    /// though: this class is by definition a custom accessibility container, so the walk is right
    /// to read it through the pair. What must never happen is a *stock* class being asked, because
    /// a stock class inherits `NSObject`'s implementation — the recursive subtree walk that hung
    /// the app.
    private final class ComputingView: UIView {
        /// How many times any instance has been asked to compute its accessibility children.
        static var computations = 0

        /// Records the call and answers as UIKit would for a container of subviews.
        override func accessibilityElementCount() -> Int {
            Self.computations += 1
            return subviews.count
        }

        /// Records the call and answers as UIKit would for a container of subviews.
        ///
        /// - Parameter index: The child to return.
        /// - Returns: The subview at `index`, or `nil` when there is none.
        override func accessibilityElement(at index: Int) -> Any? {
            Self.computations += 1
            return subviews.indices.contains(index) ? subviews[index] : nil
        }
    }

    /// The regression test for the hang, pointed at the rule that now prevents it.
    ///
    /// "Has no subviews" used to be the condition for asking a view to compute its accessibility
    /// children, and it was wrong in both directions: it missed every custom container that owns a
    /// single subview, and it sent every ordinary leaf view — the most numerous node on any screen
    /// — into the one call that is expensive. The condition is now whether the class implements the
    /// `UIAccessibilityContainer` pair at all, so `ComputingView`, which does, is read through it,
    /// and the hundred `UILabel`s here, which do not, are never asked at all. The hang is shut by
    /// the second half of that: a class that has not overridden the pair inherits `NSObject`'s
    /// implementation, and that is the one that walks the whole subtree.
    ///
    /// What this cannot assert is how many nodes came back. A bare `xctest` process has no
    /// accessibility client, so `isAccessibilityElement` answers `false` for every real `UILabel`
    /// here and the walk collects nothing whatever the rule is — an assertion on the count would
    /// pass for the wrong reason. The call counter and the class predicate are the two things this
    /// environment can actually see.
    func testOnlyAViewWhoseClassImplementsThePairIsAskedToComputeItsChildren() {
        ComputingView.computations = 0
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // A hidden window is skipped whole, and this test needs the walk to actually descend.
        window.isHidden = false
        let root = ComputingView(frame: window.bounds)
        window.addSubview(root)
        for _ in 0..<10 {
            let container = ComputingView(frame: root.bounds)
            for index in 0..<10 {
                let label = UILabel(frame: CGRect(x: 0, y: index * 20, width: 200, height: 18))
                label.text = "row \(index)" // scyther:unlocalised test fixture
                container.addSubview(label)
            }
            root.addSubview(container)
        }

        _ = AccessibilityAuditor.unbudgeted().collect(root: window)

        XCTAssertGreaterThan(ComputingView.computations, 0,
                             "a class that implements the pair is read through it, subviews or not")
        XCTAssertFalse(declaresAccessibilityElements(UILabel.self),
                       "a stock class inherits the implementation that walks the whole subtree, and is never asked")
        XCTAssertTrue(declaresAccessibilityElements(ComputingView.self))
    }

    /// Stopping short of `accessibilityElementCount()` must not cost the walk the elements it is
    /// there to find: a view that has actually *set* `accessibilityElements` — which is what
    /// SwiftUI's hosting view does for its synthetic `AccessibilityNode` elements — is still read
    /// through that property rather than through its subviews.
    func testAViewThatSetsAccessibilityElementsIsStillReadThroughThem() {
        ComputingView.computations = 0
        let container = ComputingView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "synthetic"
        element.accessibilityFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        container.accessibilityElements = [element]

        let children = (container as AuditNode).children

        XCTAssertEqual(children.map(\.accessibilityLabelText), ["synthetic"])
        XCTAssertEqual(ComputingView.computations, 0)
    }

    /// The other half of not asking a `UIView` to compute its accessibility children: doing so
    /// must not cost the walk the elements it is there to find.
    ///
    /// SwiftUI draws no `UILabel` for a `Text` — it vends synthetic `AccessibilityNode` elements
    /// instead — so if those were only reachable through `accessibilityElementCount()` the fix
    /// would have quietly emptied the audit for every SwiftUI app. They are not: SwiftUI *sets*
    /// `accessibilityElements` on its hosting view, which is the cheap stored property the walk
    /// still reads. This test is the evidence for that, against a real `UIHostingController`
    /// rather than against the claim.
    func testTheWalkFindsSwiftUIsSyntheticAccessibilityElements() throws {
        struct Sample: View {
            var body: some View {
                VStack {
                    Text(verbatim: "Hello world") // scyther:unlocalised test fixture
                    Button("Tap me") { } // scyther:unlocalised test fixture
                    Image(systemName: "star")
                        .accessibilityLabel("Star") // scyther:unlocalised test fixture
                }
            }
        }

        // Waits for SwiftUI to publish its three elements rather than looking once: a fixed wait
        // passed here and failed on CI's toolchain on every run since the audit landed. See
        // `HostedSwiftUIWindow`. The wait counts what SwiftUI set, so it stays independent of what
        // the walk below finds and cannot paper over a regression in it.
        let window = try HostedSwiftUIWindow.make(
            hosting: Sample(),
            isReady: { HostedSwiftUIWindow.publishedAccessibilityElementCount($0) >= 3 }
        )

        let walked = AccessibilityAuditor.unbudgeted().collect(root: window)
        let labels = Set(walked.nodes.compactMap(\.accessibilityLabelText))

        XCTAssertTrue(labels.isSuperset(of: ["Hello world", "Tap me", "Star"]),
                      "SwiftUI's synthetic elements must still be found, but got \(labels)")
    }
}

/// A controller Scyther presents whose *name* gives nothing away.
///
/// Exists only so `testOwnershipComesFromTheMarkerRatherThanFromTheTypeName` can prove the rule is
/// structural: if this is recognised as Scyther's, it can only be through the `ScytherPresentedUI`
/// marker, since nothing about the class is called `Scyther` and it inherits from no Scyther type.
private final class MarkerOnlyPresentedController: UIViewController, ScytherPresentedUI { }
