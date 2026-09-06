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

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertEqual(walked.nodes.compactMap(\.accessibilityLabelText), ["leaf"])
    }

    func testAContainerIsDescendedInto() {
        let first = Node(label: "one", isElement: true)
        let second = Node(label: "two", isElement: true)
        let root = Node(children: [Node(children: [first]), second])

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertEqual(walked.nodes.compactMap(\.accessibilityLabelText), ["one", "two"])
    }

    /// Scyther's own UI is not the app under audit.
    func testScytherOwnedSubtreesAreSkippedWhole() {
        let inside = Node(label: "menu row", isElement: true)
        let root = Node(children: [Node(isScytherOwned: true, children: [inside])])

        XCTAssertTrue(AccessibilityAuditor().collect(root: root).nodes.isEmpty)
    }

    func testInvisibleAndEmptyNodesAreSkipped() {
        let invisible = Node(label: "hidden", isElement: true, isVisible: false)
        let empty = Node(label: "zero", frame: .zero, isElement: true)
        let root = Node(children: [invisible, empty])

        XCTAssertTrue(AccessibilityAuditor().collect(root: root).nodes.isEmpty)
    }

    /// A pathological hierarchy must not hang the app, and a truncated walk must say so.
    func testTheNodeCapStopsTheWalkAndIsReported() {
        let children = (0..<(AccessibilityAuditor.maximumNodes + 10)).map { _ in
            Node(label: "row", isElement: true) as AuditNode
        }
        let root = Node(children: children)

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertEqual(walked.nodes.count, AccessibilityAuditor.maximumNodes)
        XCTAssertTrue(walked.didHitLimit)
    }

    func testTheDepthCapStopsTheWalkAndIsReported() {
        var deepest: AuditNode = Node(label: "bottom", isElement: true)
        for _ in 0..<(AccessibilityAuditor.maximumDepth + 5) {
            deepest = Node(children: [deepest])
        }

        let walked = AccessibilityAuditor().collect(root: deepest)

        XCTAssertTrue(walked.didHitLimit)
        XCTAssertTrue(walked.nodes.isEmpty, "the leaf sits below the cap")
    }

    func testAWalkThatFinishesDoesNotClaimALimitWasHit() {
        let root = Node(children: [Node(label: "one", isElement: true)])
        XCTAssertFalse(AccessibilityAuditor().collect(root: root).didHitLimit)
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

        let walked = AccessibilityAuditor().collect(root: root)

        XCTAssertTrue(walked.didHitLimit, "the cap should be hit")
        XCTAssertLessThan(walked.nodes.count, containerCount, "not all elements should be collected; cap stops before traversing all containers")
        // Each (container, element) pair costs 2 visits. At 5000 visits, only 2500 pairs fit.
        XCTAssertEqual(walked.nodes.count, AccessibilityAuditor.maximumNodes / 2, "exactly half the budget is collected, the rest consumed by container nodes")
    }
}
