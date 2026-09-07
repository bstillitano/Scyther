@testable import Scyther
import UIKit
import XCTest

@MainActor
final class AccessibilityAuditorChecksTests: XCTestCase {

    /// A stand-in for a node of the accessibility tree.
    ///
    /// Conforms to ``AuditNodeDetails`` as well, so a test can hand the rules a real point size
    /// or an accessibility value the way a `UILabel` would, without a window or a render.
    private final class Node: AuditNode, AuditNodeDetails {
        var isAccessibilityElementNode: Bool
        var accessibilityLabelText: String?
        var traits: UIAccessibilityTraits
        var frameInWindow: CGRect
        var isVisible: Bool
        var isScytherOwned: Bool
        var typeName: String
        var children: [AuditNode]
        var auditFontPointSize: CGFloat?
        var auditFontIsBold: Bool
        var auditDrawsText: Bool
        var auditAccessibilityValue: String?

        init(label: String? = nil,
             traits: UIAccessibilityTraits = .none,
             frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
             isElement: Bool = false,
             isVisible: Bool = true,
             isScytherOwned: Bool = false,
             typeName: String = "Node",
             fontPointSize: CGFloat? = nil,
             isBold: Bool = false,
             drawsText: Bool = false,
             value: String? = nil,
             children: [AuditNode] = []) {
            self.isAccessibilityElementNode = isElement
            self.accessibilityLabelText = label
            self.traits = traits
            self.frameInWindow = frame
            self.isVisible = isVisible
            self.isScytherOwned = isScytherOwned
            self.typeName = typeName
            self.auditFontPointSize = fontPointSize
            self.auditFontIsBold = isBold
            self.auditDrawsText = drawsText
            self.auditAccessibilityValue = value
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

    func testATargetWellUnderTheMinimumIsAnError() {
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

    /// A target between the AA floor and Apple's 44 is short of guidance but not of any
    /// standard, so it is a warning.
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

    /// Large text passes at 3:1, and "large" is WCAG's rule — 18pt — read off the element, not
    /// guessed from how tall its frame happens to be. The two nodes here are the same height on
    /// purpose: only the point size separates them.
    func testLargeTextIsHeldToTheLowerThreshold() {
        let midGrey = RGB(red: 0.5, green: 0.5, blue: 0.5)
        let white = RGB(red: 1, green: 1, blue: 1)
        let sampler = StubSampler(pixels: Array(repeating: white, count: 80) + Array(repeating: midGrey, count: 20))
        let large = Node(label: "Title", traits: .staticText,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 30), isElement: true,
                         fontPointSize: 18)
        let small = Node(label: "Body", traits: .staticText,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 30), isElement: true,
                         fontPointSize: 17)

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

// MARK: - Verdicts

@MainActor
extension AccessibilityAuditorChecksTests {

    /// Pixels that measure about 3.35:1 — conformant for a non-text element under WCAG 1.4.11,
    /// and a failure for body text under 1.4.3. Every threshold test below turns on that gap.
    private var midThresholdPixels: [RGB] {
        let grey = RGB(red: 0.55, green: 0.55, blue: 0.55)
        let white = RGB(red: 1, green: 1, blue: 1)
        return Array(repeating: white, count: 80) + Array(repeating: grey, count: 20)
    }

    /// WCAG 1.4.3 exempts "an inactive user interface component" outright, so a greyed-out
    /// button is not a contrast defect however low it measures.
    func testADisabledControlIsNotContrastFlagged() {
        let disabled = Node(label: "Continue", traits: [.staticText, .notEnabled],
                            frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [disabled]), checks: [.contrast], sampler: sampler).findings

        XCTAssertTrue(findings.isEmpty, "WCAG 1.4.3 does not apply to an inactive component")
    }

    /// An icon-only button draws no text, so it is graded under WCAG 1.4.11 at 3:1 — having a
    /// label is evidence that it is *not* text, not evidence that it is.
    func testAnIconOnlyButtonIsHeldToTheNonTextThreshold() {
        let icon = Node(label: "Share", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 20, height: 20), isElement: true)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [icon]), checks: [.contrast], sampler: sampler).findings

        XCTAssertTrue(findings.isEmpty, "3.35:1 clears 1.4.11's 3:1 for non-text content")
    }

    /// The same pixels behind real text are a failure, so the two thresholds are genuinely
    /// distinguished rather than both being lenient.
    func testTextIsStillHeldToTheFourAndAHalfThreshold() {
        let text = Node(label: "Body copy", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [text]), checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.count, 1)
    }

    /// WCAG 2.5.8 exempts a target that sits inline in a sentence, and nobody makes body-copy
    /// links 44pt tall — so a link is never worse than a warning.
    func testAnInlineLinkIsNeverMoreThanAWarning() {
        let link = Node(label: "Terms of Service", traits: .link,
                        frame: CGRect(x: 0, y: 0, width: 120, height: 18), isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [link]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// A custom control whose author set `isAccessibilityElement` and forgot the traits is the
    /// half-done job the trait gate used to score as finished.
    func testAnElementWithNoTraitsAndNoLabelIsStillAFinding() {
        let untraited = Node(traits: .none, frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                             isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [untraited]), checks: [.missingLabel], sampler: nil).findings

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity, .error)
    }

    /// WCAG 2.5.8 AA sets the floor at 24pt, which is the only number in this rule anyone can
    /// cite; below it is an error.
    func testATargetUnderTwentyFourPointsIsAnError() {
        let tiny = Node(label: "Close", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 44, height: 20), isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [tiny]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .error)
    }

    /// The boundary itself: 24 is the AA minimum, so exactly 24 is short of Apple's 44 but not
    /// short of any guideline — a warning.
    func testATargetAtTwentyFourPointsIsAWarning() {
        let boundary = Node(label: "Close", traits: .button,
                            frame: CGRect(x: 0, y: 0, width: 24, height: 24), isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [boundary]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// Height is line count plus padding, not point size. A wrapped body paragraph is tall and
    /// is still body copy, and grading it at 3:1 is a level too lenient in exactly the place a
    /// low-vision reader is hurt most.
    func testATallLabelIsNotTreatedAsLargeText() {
        let wrapped = Node(label: "Two lines of ordinary body copy", traits: .staticText,
                           frame: CGRect(x: 0, y: 0, width: 200, height: 40), isElement: true)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [wrapped]), checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.count, 1, "a tall label is a wrapped label, not a large one")
    }
}

// MARK: - Thresholds, values and the budget

@MainActor
extension AccessibilityAuditorChecksTests {

    /// 14pt bold is large text under WCAG, and the descriptor knows it even though the size
    /// alone does not.
    func testBoldTextIsLargeAtFourteenPoints() {
        let bold = Node(label: "Heading", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true,
                        fontPointSize: 14, isBold: true)
        let regular = Node(label: "Heading", traits: .staticText,
                           frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true,
                           fontPointSize: 14)
        let sampler = StubSampler(pixels: midThresholdPixels)
        let auditor = AccessibilityAuditor()

        XCTAssertTrue(auditor.audit(root: Node(children: [bold]), checks: [.contrast], sampler: sampler).findings.isEmpty)
        XCTAssertEqual(auditor.audit(root: Node(children: [regular]), checks: [.contrast], sampler: sampler).findings.count, 1)
    }

    /// A button that draws a title is text, whatever its traits say, so it keeps the strict
    /// threshold that the icon-only case gives up.
    func testAButtonWithATitleIsStillGradedAsText() {
        let titled = Node(label: "Continue", traits: .button,
                          frame: CGRect(x: 0, y: 0, width: 200, height: 44), isElement: true,
                          drawsText: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [titled]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertEqual(findings.count, 1, "a padded button's title is still body text")
    }

    /// Text whose size cannot be read stays at the strict threshold rather than being guessed
    /// into the lenient one: the relaxation can only ever hide a failure.
    func testTextWithNoReadableSizeKeepsTheStrictThreshold() {
        let unknown = Node(label: "Something", traits: .staticText,
                           frame: CGRect(x: 0, y: 0, width: 200, height: 60), isElement: true)

        let findings = AccessibilityAuditor()
            .audit(root: Node(children: [unknown]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertEqual(findings.count, 1)
    }

    /// An element with a value reads that value, so it is not nameless in the way the check
    /// exists to catch.
    func testAnElementWithAValueButNoLabelIsExempt() {
        let slider = Node(traits: .adjustable, frame: CGRect(x: 0, y: 0, width: 200, height: 44),
                          isElement: true, value: "50%")

        XCTAssertTrue(AccessibilityAuditor()
            .audit(root: Node(children: [slider]), checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    /// A real `UILabel` supplies its own point size, which is the case the rule is actually for.
    func testAUILabelReportsItsOwnFontSize() {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 15)
        label.text = "Hello"

        XCTAssertEqual(label.auditFontPointSize, 15)
        XCTAssertTrue(label.auditFontIsBold)
        XCTAssertTrue(label.auditDrawsText)
    }

    /// An icon-only button has a name and no text, and that is exactly what the threshold turns
    /// on.
    func testAUIButtonWithNoTitleDrawsNoText() {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "Share"

        XCTAssertFalse(button.auditDrawsText)
    }

    /// A contrast check that looked at candidates and could read none of them has not passed
    /// them. Seven distinct ways of failing to measure used to render exactly like a clean
    /// screen.
    func testAContrastCheckThatMeasuresNothingSaysSo() {
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let result = AccessibilityAuditor()
            .audit(root: Node(children: [text]), checks: [.contrast], sampler: StubSampler(pixels: []))

        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.checksUnmeasurable, [.contrast])
    }

    /// One element it could read is enough: the report only has to say "I measured nothing" when
    /// it measured nothing.
    func testAContrastCheckThatMeasuresSomethingIsNotUnmeasurable() {
        let readable = Node(label: "Hello", traits: .staticText,
                            frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let result = AccessibilityAuditor()
            .audit(root: Node(children: [readable]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertTrue(result.checksUnmeasurable.isEmpty)
    }

    /// A screen with no text at all is silent rather than unmeasurable: there was nothing to
    /// measure, which is not the same as failing to measure it.
    func testAScreenWithNoTextIsNotReportedAsUnmeasurable() {
        let image = Node(label: "Sunset", traits: .image,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 200), isElement: true)

        let result = AccessibilityAuditor()
            .audit(root: Node(children: [image]), checks: [.contrast], sampler: StubSampler(pixels: []))

        XCTAssertTrue(result.checksUnmeasurable.isEmpty)
    }

    /// A sampler that spends the main thread the way the real one does — a crop and a render per
    /// element — so the budget can be tested where it is actually spent.
    private final class SlowSampler: ContrastSampling {
        let pixels: [RGB]
        let onSample: () -> Void

        init(pixels: [RGB], onSample: @escaping () -> Void) {
            self.pixels = pixels
            self.onSample = onSample
        }

        func samples(in frame: CGRect) -> [RGB] {
            onSample()
            return pixels
        }
    }

    /// The budget has to bound the whole pass. The walk is property reads; the per-element loop
    /// crops and rasterises a bitmap for every text element, up to 5,000 of them, and a deadline
    /// checked only inside the walk never reached any of it.
    func testTheBudgetStopsThePerElementLoopAndSaysSo() {
        let start = Date()
        var elapsed: TimeInterval = 0
        var auditor = AccessibilityAuditor()
        auditor.now = { start.addingTimeInterval(elapsed) }
        let sampler = SlowSampler(pixels: midThresholdPixels) {
            elapsed = AccessibilityAuditor.budget + 0.1
        }
        let children = (0..<50).map { index in
            Node(label: "Row \(index)", traits: .staticText,
                 frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true) as AuditNode
        }

        let result = auditor.audit(root: Node(children: children), checks: [.contrast], sampler: sampler)

        XCTAssertTrue(result.didHitLimit, "a pass that ran out of time must say it is partial")
        XCTAssertEqual(result.findings.count, 1, "it stops rather than measuring all fifty")
    }

    /// The budget must not fire on a pass that finishes inside it, or every report would claim to
    /// be truncated.
    func testAPassInsideTheBudgetIsNotReportedAsTruncated() {
        let start = Date()
        var auditor = AccessibilityAuditor()
        auditor.now = { start }
        let children = (0..<50).map { index in
            Node(label: "Row \(index)", traits: .staticText,
                 frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true) as AuditNode
        }

        let result = auditor.audit(root: Node(children: children), checks: [.contrast],
                                   sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertFalse(result.didHitLimit)
        XCTAssertEqual(result.findings.count, 50)
    }
}
