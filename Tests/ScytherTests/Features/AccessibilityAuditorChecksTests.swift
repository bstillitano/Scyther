@testable import Scyther
import UIKit
import XCTest

@MainActor
final class AccessibilityAuditorChecksTests: XCTestCase {

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

    func testAButtonWithNoLabelIsAnError() {
        let root = Node(children: [Node(traits: .button, isElement: true)])

        let findings = AccessibilityAuditor().audit(root: root, checks: [.missingLabel], sampler: nil).findings

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.check, .missingLabel)
        XCTAssertEqual(findings.first?.severity, .error)
    }

    func testAWhitespaceLabelIsNoLabelAtAll() {
        let root = Node(children: [Node(label: "   ", traits: .image, isElement: true)])
        XCTAssertEqual(AccessibilityAuditor().audit(root: root, checks: [.missingLabel], sampler: nil).findings.count, 1)
    }

    /// Static text carries its content as its label; there is nothing missing.
    func testStaticTextIsExemptFromTheLabelCheck() {
        let root = Node(children: [Node(traits: .staticText, isElement: true)])
        XCTAssertTrue(AccessibilityAuditor().audit(root: root, checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    func testALabelledButtonPasses() {
        let root = Node(children: [Node(label: "Close", traits: .button, isElement: true)])
        XCTAssertTrue(AccessibilityAuditor().audit(root: root, checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    func testATargetUnderThirtyTwoPointsIsAnError() {
        let small = Node(label: "Close", traits: .button,
                         frame: CGRect(x: 0, y: 0, width: 20, height: 20), isElement: true)

        let findings = AccessibilityAuditor().audit(root: Node(children: [small]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .error)
        XCTAssertTrue(findings.first?.detail.contains("20") == true, "the finding reports what it measured")
    }

    func testATargetBetweenThirtyTwoAndFortyFourPointsIsAWarning() {
        let short = Node(label: "Close", traits: .button,
                         frame: CGRect(x: 0, y: 0, width: 44, height: 36), isElement: true)

        let findings = AccessibilityAuditor().audit(root: Node(children: [short]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testAFortyFourPointTargetPasses() {
        let fine = Node(label: "Close", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 44, height: 44), isElement: true)
        XCTAssertTrue(AccessibilityAuditor().audit(root: Node(children: [fine]), checks: [.touchTarget], sampler: nil).findings.isEmpty)
    }

    /// The boundary itself: `shortest < 32` is an error, so exactly 32 is a warning, not an error.
    func testAThirtyTwoPointTargetIsAWarningNotAnError() {
        let boundary = Node(label: "Close", traits: .button,
                            frame: CGRect(x: 0, y: 0, width: 32, height: 32), isElement: true)

        let findings = AccessibilityAuditor().audit(root: Node(children: [boundary]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// Static text is not tapped, so its size is not a target.
    func testTextIsExemptFromTheTargetCheck() {
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10), isElement: true)
        XCTAssertTrue(AccessibilityAuditor().audit(root: Node(children: [text]), checks: [.touchTarget], sampler: nil).findings.isEmpty)
    }

    /// A check that is switched off is not run, and the result says which ones did run.
    func testOnlyTheRequestedChecksRun() {
        let bad = Node(traits: .button, frame: CGRect(x: 0, y: 0, width: 10, height: 10), isElement: true)

        let result = AccessibilityAuditor().audit(root: Node(children: [bad]), checks: [.touchTarget], sampler: nil)

        XCTAssertEqual(result.findings.map(\.check), [.touchTarget])
        XCTAssertEqual(result.checksRun, [.touchTarget])
    }

    /// An element with no label is named by what it is and where it is, or the finding that says
    /// "this has no label" would itself have nothing to point at.
    func testAnUnlabelledElementIsNamedByItsTypeAndPosition() {
        let node = Node(traits: .button, frame: CGRect(x: 12, y: 34, width: 10, height: 10),
                        isElement: true, typeName: "UIButton")

        let findings = AccessibilityAuditor().audit(root: Node(children: [node]), checks: [.missingLabel], sampler: nil).findings

        XCTAssertTrue(findings.first?.elementName.contains("UIButton") == true)
        XCTAssertTrue(findings.first?.elementName.contains("12") == true)
    }

    /// A sampler that hands back the same pixels for anything asked of it.
    private struct StubSampler: ContrastSampling {
        let pixels: [RGB]
        func samples(in frame: CGRect) -> [RGB] { pixels }
    }

    func testLowContrastTextIsAWarningWithBothColoursNamed() {
        let grey = RGB(red: 0.6, green: 0.6, blue: 0.6)
        let white = RGB(red: 1, green: 1, blue: 1)
        let sampler = StubSampler(pixels: Array(repeating: white, count: 80) + Array(repeating: grey, count: 20))
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [text]), checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.first?.check, .contrast)
        XCTAssertEqual(findings.first?.severity, .warning, "the measurement is an estimate")
        XCTAssertTrue(findings.first?.detail.contains("#") == true, "both sampled colours are reported")
    }

    /// Large text passes at 3:1, so a ratio between the two thresholds is a finding on small
    /// text and not on large.
    func testLargeTextIsHeldToTheLowerThreshold() {
        let midGrey = RGB(red: 0.5, green: 0.5, blue: 0.5)
        let white = RGB(red: 1, green: 1, blue: 1)
        let sampler = StubSampler(pixels: Array(repeating: white, count: 80) + Array(repeating: midGrey, count: 20))
        let large = Node(label: "Title", traits: .staticText,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 30), isElement: true)
        let small = Node(label: "Body", traits: .staticText,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true)

        let auditor = AccessibilityAuditor()
        XCTAssertTrue(auditor.audit(root: Node(children: [large]), checks: [.contrast], sampler: sampler).findings.isEmpty)
        XCTAssertEqual(auditor.audit(root: Node(children: [small]), checks: [.contrast], sampler: sampler).findings.count, 1)
    }

    /// A photograph is not text, and a ratio taken across one means nothing.
    func testNonTextElementsAreNotMeasured() {
        let sampler = StubSampler(pixels: [RGB(red: 0, green: 0, blue: 0), RGB(red: 1, green: 1, blue: 1)])
        let image = Node(label: "Sunset", traits: .image,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 200), isElement: true)

        XCTAssertTrue(AccessibilityAuditor().audit(root: Node(children: [image]), checks: [.contrast], sampler: sampler).findings.isEmpty)
    }
}
