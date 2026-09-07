@testable import Scyther
import UIKit
import XCTest

/// Covers what one node costs the walk, which is the half of a pass left over once the window
/// snapshot has moved off the live path.
///
/// Everything here counts questions rather than timing them. A hostless `xctest` process answers
/// most of these questions far more cheaply than a device does — there is no accessibility client,
/// no scene and no renderer — so a timing assertion would measure nothing, where a count of how
/// many times a node was *asked* is the same number on both.
@MainActor
final class AccessibilityAuditWalkCostTests: XCTestCase {

    override func tearDown() {
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            ScytherPresentation.presentationMeasurementSpace()
        }
        CountingResponderView.nextReads = 0
        super.tearDown()
    }

    /// A window a test can hang a hierarchy off.
    ///
    /// - Returns: A 390 × 844 window at the screen origin.
    private func testWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }

    // MARK: - Geometry

    /// The frame and the visibility answer come from one question, not two.
    ///
    /// Asking separately meant every node resolved Scyther's presentation space twice and
    /// converted its own bounds twice — the same two answers, computed from the same inputs, one
    /// line apart.
    func testAskingWhetherANodeIsVisibleAndWhereItIsCostsOneSpaceResolution() {
        var asked = 0
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            asked += 1
            return nil
        }
        let window = testWindow()
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        window.addSubview(control)

        let frame = (control as AuditNode).frameInWindowIfVisible

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(frame, CGRect(x: 40, y: 100, width: 44, height: 44))
    }

    /// A node nothing can be seen of answers with no frame, and does not pay for one.
    func testAHiddenNodeAnswersWithNoFrameAndResolvesNoSpace() {
        var asked = 0
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            asked += 1
            return nil
        }
        let window = testWindow()
        let control = UIView(frame: CGRect(x: 40, y: 100, width: 44, height: 44))
        control.isHidden = true
        window.addSubview(control)

        XCTAssertNil((control as AuditNode).frameInWindowIfVisible)
        XCTAssertEqual(asked, 0, "a hidden node is decided before any geometry is resolved")
    }

    /// And the walk uses it: one resolution per node visited, where it used to be two.
    func testTheWalkResolvesThePresentationSpaceOncePerNode() {
        var asked = 0
        ScytherPresentation.presentationMeasurementSpaceProbe = {
            asked += 1
            return nil
        }
        let window = testWindow()
        window.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44)))
        window.addSubview(UIView(frame: CGRect(x: 0, y: 100, width: 44, height: 44)))

        _ = AccessibilityAuditor.unbudgeted().collect(root: window)

        XCTAssertEqual(asked, 3, "the window and its two subviews, once each")
    }

    // MARK: - Accessibility properties

    /// Every accessibility property read is a string-keyed lookup behind a dispatch barrier, and
    /// the rules were reading the same two properties five and six times per element: the walk,
    /// then each check, then the helper that names the element in the finding.
    func testEachRuleReadsANodesLabelAndTraitsOnce() {
        let leaf = CountingLeaf()
        let root = CountingLeaf(isElement: false, children: [leaf])

        let result = AccessibilityAuditor.unbudgeted().audit(root: root,
                                                  checks: [.missingLabel, .touchTarget],
                                                  sampler: nil)

        XCTAssertEqual(result.findings.count, 2, "an unnamed 10 × 10 button fails both rules")
        XCTAssertEqual(leaf.labelReads, 1)
        XCTAssertEqual(leaf.traitReads, 1)
        XCTAssertEqual(leaf.elementReads, 1)
    }

    // MARK: - Ownership

    /// Scyther-ownership is inherited, and the walk descends from a node it has already cleared —
    /// so a child only has to be climbed as far as its parent, not all the way to the window.
    ///
    /// Climbing the whole responder chain for every node made the cost quadratic in the depth of
    /// the screen, on the one question whose answer is `false` for every node in an app.
    func testTheOwnershipClimbStopsAtAnAncestorAlreadyKnownClean() {
        let window = testWindow()
        var parent: UIView = window
        for _ in 0..<12 {
            let view = CountingResponderView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            parent.addSubview(view)
            parent = view
        }
        CountingResponderView.nextReads = 0

        _ = AccessibilityAuditor.unbudgeted().collect(root: window)

        XCTAssertLessThanOrEqual(CountingResponderView.nextReads, 24,
                                 "each of the twelve views should climb about one link, not twelve")
    }
}

/// A node that counts how often each of its accessibility properties is read.
///
/// A double rather than a `UIView` because the count is the whole assertion: UIKit's own
/// properties cannot be instrumented, and the rules read them through ``AuditNode`` anyway.
@MainActor
private final class CountingLeaf: AuditNode {
    /// How many times ``accessibilityLabelText`` has been read.
    private(set) var labelReads = 0

    /// How many times ``traits`` has been read.
    private(set) var traitReads = 0

    /// How many times ``isAccessibilityElementNode`` has been read.
    private(set) var elementReads = 0

    /// Whether this node is a leaf VoiceOver lands on.
    private let isElement: Bool

    /// The nodes below it.
    let children: [AuditNode]

    /// Creates a counting node.
    ///
    /// - Parameters:
    ///   - isElement: Whether the walk should treat it as a leaf and check it.
    ///   - children: The nodes below it.
    init(isElement: Bool = true, children: [AuditNode] = []) {
        self.isElement = isElement
        self.children = children
    }

    var isAccessibilityElementNode: Bool {
        elementReads += 1
        return isElement
    }

    var accessibilityLabelText: String? {
        labelReads += 1
        return nil
    }

    var traits: UIAccessibilityTraits {
        traitReads += 1
        return .button
    }

    var frameInWindow: CGRect { CGRect(x: 0, y: 0, width: 10, height: 10) }

    var isVisible: Bool { true }

    var isScytherOwned: Bool { false }

    var typeName: String { "CountingLeaf" } // scyther:unlocalised test fixture
}

/// A view that counts how often its responder chain is climbed.
///
/// `UIResponder.next` is the one link the ownership walk actually costs, and it is overridable,
/// which makes it the honest thing to count.
private final class CountingResponderView: UIView {
    /// How many times any instance has been asked for the next responder.
    nonisolated(unsafe) static var nextReads = 0

    override var next: UIResponder? {
        CountingResponderView.nextReads += 1
        return super.next
    }
}
