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

    // MARK: - The fallback pass
    //
    // Every tree below is built from bare `UIView`s with no background, no rendered contents, no
    // border and no shadow, so nothing in it satisfies `paints(_:)`: the probe's first pass finds
    // nothing anywhere under the point and its second — the original deepest-match rule — answers.
    // That is deliberate rather than incidental. These tests state the fallback's semantics and the
    // skip rules both passes share (`isEligible`), and they are the same assertions Task 2 shipped,
    // so a change to the two-pass structure that broke the original rule still fails here. The
    // primary pass has its own section below, including painted counterparts of each skip rule.

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

    /// Front-to-back order decides between two candidates the probe cannot otherwise tell apart.
    ///
    /// Read this together with ``testAnUnpaintedViewInFrontOfAPaintedOneLoses``, which is the same
    /// scenario asserting the *back* view wins. They are not in contradiction: here neither view
    /// paints anything, so the question is only which is in front; there the front view paints
    /// nothing and the back one does, and the primary pass prefers the one that is visibly there.
    /// The name says "unpainted" so the difference is legible from the test list.
    func testTheFrontmostOfTwoOverlappingUnpaintedViewsWins() {
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

    // MARK: - The primary pass
    //
    // These trees contain something that paints, so the probe's first pass answers — the path every
    // touch takes in a real app. Each skip rule from the fallback section has a painted counterpart
    // here, because `isEligible` is shared by both passes and a rule proven only on the branch that
    // rarely executes is only half proven.

    /// The defect that made the ruler useless on iOS 26 before this rule existed: a plain SwiftUI
    /// `TabView` and `List` put a full-screen, unpainted container — `_UITouchPassthroughView`, or
    /// `FloatingBarHostingView` on the native floating-bar path — in front of the whole app, and
    /// the deepest-match rule returned it for every point on the screen.
    func testAnUnpaintedViewInFrontOfAPaintedOneLoses() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let painted = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        painted.backgroundColor = .red
        let passthrough = UIView(frame: root.bounds)
        root.addSubview(painted)
        root.addSubview(passthrough)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === painted,
                      "the container hosting a floating tab bar is not what the developer is pointing at")
    }

    /// The clause the whole rule rests on in production, exercised on its own.
    ///
    /// A rendered `UILabel` — the spec's own example of what a developer means to measure — has a
    /// `.clear` background, not a `nil` one, so it fails the background check and qualifies *only*
    /// through `layer.contents`. Every other test in this file qualifies its views through
    /// `backgroundColor`, so without this one an edit that dropped or reordered the `contents`
    /// check would leave the suite green while the ruler silently snapped to painted ancestors
    /// instead of labels on every real screen. The view here therefore sets `layer.contents` and
    /// nothing else.
    func testAViewThatPaintsOnlyThroughItsLayerContentsIsPreferred() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let rendered = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        rendered.layer.contents = try onePixelImage()
        XCTAssertNil(rendered.backgroundColor, "the point is that contents alone carries this")

        let passthrough = UIView(frame: root.bounds)
        root.addSubview(rendered)
        root.addSubview(passthrough)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === rendered)
    }

    /// The same clause, on a real `UILabel` in a real window rather than on a stand-in.
    ///
    /// Skipped rather than failed when the platform declines to render into the layer, matching
    /// ``HostedSwiftUIWindow``'s precedent: a test process's window is not always committed to the
    /// render server, and "this toolchain did not draw" is not a defect in the probe.
    func testARenderedLabelIsReturnedRatherThanItsPaintedContainer() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let container = UIView(frame: window.bounds)
        container.backgroundColor = .white
        let label = UILabel(frame: CGRect(x: 20, y: 100, width: 200, height: 40))
        label.text = "Title"
        container.addSubview(label)

        let root = UIViewController()
        root.view = container
        window.rootViewController = root
        window.makeKeyAndVisible()
        container.layoutIfNeeded()
        label.layer.setNeedsDisplay()
        label.layer.displayIfNeeded()

        try XCTSkipIf(label.layer.contents == nil,
                      "This toolchain did not render the label into its layer, so the clause under test cannot be reached here.")
        XCTAssertNotEqual(label.backgroundColor?.cgColor.alpha, 1,
                          "a label's background is clear, which is why `contents` is what admits it")

        let hit = ViewProbe.view(at: CGPoint(x: 100, y: 120), in: container)
        XCTAssertTrue(hit === label, "pointing at a label means the label, not the white container behind it")
    }

    func testAHiddenPaintedViewIsSkipped() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        child.backgroundColor = .red
        child.isHidden = true
        let behind = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        behind.backgroundColor = .blue
        root.insertSubview(behind, belowSubview: child)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === behind)
    }

    func testAFullyTransparentPaintedViewIsSkipped() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        child.backgroundColor = .red
        child.alpha = 0
        let behind = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        behind.backgroundColor = .blue
        root.insertSubview(behind, belowSubview: child)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === behind)
    }

    /// The rule that stops the ruler measuring itself, proven on the pass production takes: the
    /// ruler's own overlay paints a control and a measurement over the whole screen.
    func testAScytherOwnedPaintedViewIsSkipped() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let app = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        app.backgroundColor = .blue
        let ours = TopLevelView(frame: root.bounds)
        ours.backgroundColor = .red
        root.addSubview(app)
        root.addSubview(ours)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === app)
    }

    /// Deepest-match still holds on the primary pass: a painted view inside a painted view is the
    /// answer, not its parent.
    func testTheDeepestPaintedViewWins() {
        let (root, child) = makeTree(childFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        child.backgroundColor = .red
        let grandchild = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        grandchild.backgroundColor = .green
        child.addSubview(grandchild)

        XCTAssertTrue(ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root) === grandchild)
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

    /// A one-pixel image, the smallest thing that makes `layer.contents` non-nil.
    private func onePixelImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: 1,
                                              height: 1,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
