@testable import Scyther
import UIKit
import XCTest

@MainActor
final class AccessibilityAuditorWalkTests: XCTestCase {

    /// A stand-in for a node of the accessibility tree.
    private final class Node: AuditNode {
        var isAccessibilityElementNode: Bool
        var accessibilityLabelText: String?
        var traits: UIAccessibilityTraits
        var frameInWindow: CGRect
        var isVisible: Bool
        var isScytherOwned: Bool
        var typeName: String
        var children: [AuditNode]

        init(label: String? = nil,
             traits: UIAccessibilityTraits = .none,
             frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
             isElement: Bool = false,
             isVisible: Bool = true,
             isScytherOwned: Bool = false,
             typeName: String = "Node",
             children: [AuditNode] = []) {
            self.isAccessibilityElementNode = isElement
            self.accessibilityLabelText = label
            self.traits = traits
            self.frameInWindow = frame
            self.isVisible = isVisible
            self.isScytherOwned = isScytherOwned
            self.typeName = typeName
            self.children = children
        }
    }

    func testAnElementIsALeafAndItsChildrenAreNotWalked() {
        let hidden = Node(label: "buried", isElement: true)
        let element = Node(label: "leaf", isElement: true, children: [hidden])
        let root = Node(children: [element])

        let walked = AccessibilityAuditor.unbudgeted().collect(root: root)

        XCTAssertEqual(walked.nodes.compactMap(\.accessibilityLabelText), ["leaf"])
    }

    func testAContainerIsDescendedInto() {
        let first = Node(label: "one", isElement: true)
        let second = Node(label: "two", isElement: true)
        let root = Node(children: [Node(children: [first]), second])

        let walked = AccessibilityAuditor.unbudgeted().collect(root: root)

        XCTAssertEqual(walked.nodes.compactMap(\.accessibilityLabelText), ["one", "two"])
    }

    /// Scyther's own UI is not the app under audit.
    func testScytherOwnedSubtreesAreSkippedWhole() {
        let inside = Node(label: "menu row", isElement: true)
        let root = Node(children: [Node(isScytherOwned: true, children: [inside])])

        XCTAssertTrue(AccessibilityAuditor.unbudgeted().collect(root: root).nodes.isEmpty)
    }

    func testInvisibleAndEmptyNodesAreSkipped() {
        let invisible = Node(label: "hidden", isElement: true, isVisible: false)
        let empty = Node(label: "zero", frame: .zero, isElement: true)
        let root = Node(children: [invisible, empty])

        XCTAssertTrue(AccessibilityAuditor.unbudgeted().collect(root: root).nodes.isEmpty)
    }

    /// A pathological hierarchy must not hang the app, and a truncated walk must say so.
    func testTheNodeCapStopsTheWalkAndIsReported() {
        let children = (0..<(AccessibilityAuditor.maximumNodes + 10)).map { _ in
            Node(label: "row", isElement: true) as AuditNode
        }
        let root = Node(children: children)

        let walked = AccessibilityAuditor.unbudgeted().collect(root: root)

        XCTAssertEqual(walked.nodes.count, AccessibilityAuditor.maximumNodes)
        XCTAssertTrue(walked.didHitLimit)
    }

    func testTheDepthCapStopsTheWalkAndIsReported() {
        var deepest: AuditNode = Node(label: "bottom", isElement: true)
        for _ in 0..<(AccessibilityAuditor.maximumDepth + 5) {
            deepest = Node(children: [deepest])
        }

        let walked = AccessibilityAuditor.unbudgeted().collect(root: deepest)

        XCTAssertTrue(walked.didHitLimit)
        XCTAssertTrue(walked.nodes.isEmpty, "the leaf sits below the cap")
    }

    /// A chain of exactly ``AccessibilityAuditor/maximumDepth`` and one of exactly one more, which
    /// together are what pin the cap to a number rather than to an inequality.
    ///
    /// The test above builds `maximumDepth + 5`, so its leaf sits at depth 105 and is out of reach
    /// of *any* cap below 105: halving `maximumDepth` — silently truncating every deep SwiftUI
    /// hierarchy and calling the result partial — left it green, and so did changing `<=` to `<`.
    /// A tree at exactly the cap has to be walked to its leaf with nothing reported, and one link
    /// deeper has to stop; nothing else satisfies both.
    ///
    /// - Parameter wrappers: How many containers to stack above the leaf.
    /// - Returns: The outermost container, whose leaf therefore sits at depth `wrappers`.
    private func chain(deep wrappers: Int) -> AuditNode {
        var deepest: AuditNode = Node(label: "bottom", isElement: true)
        for _ in 0..<wrappers { deepest = Node(children: [deepest]) }
        return deepest
    }

    func testATreeAtExactlyTheDepthCapIsWalkedToItsLeaf() {
        let walked = AccessibilityAuditor.unbudgeted().collect(root: chain(deep: AccessibilityAuditor.maximumDepth))

        XCTAssertEqual(walked.nodes.compactMap(\.accessibilityLabelText), ["bottom"],
                       "a tree at exactly the cap is inside it, so its leaf must be collected")
        XCTAssertFalse(walked.didHitLimit)
    }

    func testATreeOneLinkPastTheDepthCapIsStopped() {
        let walked = AccessibilityAuditor.unbudgeted().collect(root: chain(deep: AccessibilityAuditor.maximumDepth + 1))

        XCTAssertTrue(walked.nodes.isEmpty)
        XCTAssertTrue(walked.didHitLimit)
    }

    /// The three bounds are numbers the documentation quotes and a developer is told about, so they
    /// are asserted against those numbers rather than against themselves.
    ///
    /// Every other test names them symbolically — `budget + 0.1`, `maximumNodes + 10`,
    /// `maximumDepth + 5` — which is right for a test *about* the cap and useless as a record of
    /// what the cap is: `budget = 25.0`, `maximumNodes = 10` and `maximumDepth = 3` all left the
    /// suite green while making the README and the DocC page wrong.
    func testTheWalksBoundsAreTheNumbersTheDocumentationQuotes() {
        XCTAssertEqual(AccessibilityAuditor.maximumDepth, 100)
        XCTAssertEqual(AccessibilityAuditor.maximumNodes, 5_000)
        XCTAssertEqual(AccessibilityAuditor.budget, 0.25, accuracy: 0.000_1)
    }

    func testAWalkThatFinishesDoesNotClaimALimitWasHit() {
        let root = Node(children: [Node(label: "one", isElement: true)])
        XCTAssertFalse(AccessibilityAuditor.unbudgeted().collect(root: root).didHitLimit)
    }

    /// The node cap counts every container traversed, not just elements collected.
    /// A pathological tree of many container nodes can hit the cap even with few elements.
    func testTheNodeCapCountsContainersAndNotOnlyElements() {
        let containerCount = AccessibilityAuditor.maximumNodes + 100
        var children: [AuditNode] = []
        for i in 0..<containerCount {
            let element = Node(label: "element-\(i)", isElement: true)
            let container = Node(children: [element])
            children.append(container)
        }
        let root = Node(children: children)

        let walked = AccessibilityAuditor.unbudgeted().collect(root: root)

        XCTAssertTrue(walked.didHitLimit, "the cap should be hit")
        XCTAssertLessThan(walked.nodes.count, containerCount, "not all elements should be collected; cap stops before traversing all containers")
        // Each (container, element) pair costs 2 visits. At 5000 visits, only 2500 pairs fit.
        XCTAssertEqual(walked.nodes.count, AccessibilityAuditor.maximumNodes / 2, "exactly half the budget is collected, the rest consumed by container nodes")
    }

    /// A walk can be slow per node rather than long, and the node cap cannot see that. The
    /// clock is injected so this can be driven deterministically rather than by sleeping.
    func testAWalkThatRunsOutOfTimeStopsAndSaysSo() {
        var ticks = 0
        let start = Date()
        var auditor = AccessibilityAuditor.unbudgeted()
        auditor.now = {
            ticks += 1
            return start.addingTimeInterval(ticks > 5 ? AccessibilityAuditor.budget + 0.1 : 0)
        }

        let children = (0..<500).map { _ in Node(label: "row", isElement: true) as AuditNode }
        let walked = auditor.collect(root: Node(children: children))

        XCTAssertTrue(walked.didHitLimit)
        XCTAssertLessThan(walked.nodes.count, 500)
    }

    /// The budget must not fire on a walk that finishes inside it, or every report would claim
    /// to be truncated.
    func testAWalkInsideTheBudgetIsNotReportedAsTruncated() {
        let start = Date()
        var auditor = AccessibilityAuditor.unbudgeted()
        auditor.now = { start }

        let children = (0..<500).map { _ in Node(label: "row", isElement: true) as AuditNode }
        let walked = auditor.collect(root: Node(children: children))

        XCTAssertFalse(walked.didHitLimit)
        XCTAssertEqual(walked.nodes.count, 500)
    }
}
