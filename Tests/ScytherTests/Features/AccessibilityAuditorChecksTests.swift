@testable import Scyther
import SwiftUI
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
        var auditDrawsText: Bool?
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
             drawsText: Bool? = nil,
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

        let findings = AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.missingLabel], sampler: nil).findings

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.check, .missingLabel)
        XCTAssertEqual(findings.first?.severity, .error)
    }

    func testAWhitespaceLabelIsNoLabelAtAll() {
        let root = Node(children: [Node(label: "   ", traits: .image, isElement: true)])
        XCTAssertEqual(AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.missingLabel], sampler: nil).findings.count, 1)
    }

    /// Static text carries its content as its label; there is nothing missing.
    func testStaticTextIsExemptFromTheLabelCheck() {
        let root = Node(children: [Node(traits: .staticText, isElement: true)])
        XCTAssertTrue(AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    func testALabelledButtonPasses() {
        let root = Node(children: [Node(label: "Close", traits: .button, isElement: true)])
        XCTAssertTrue(AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    func testATargetWellUnderTheMinimumIsAnError() {
        let small = Node(label: "Close", traits: .button,
                         frame: CGRect(x: 0, y: 0, width: 20, height: 20), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [small]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .error)
        XCTAssertTrue(findings.first?.detail.contains("20") == true, "the finding reports what it measured")
    }

    func testATargetBetweenThirtyTwoAndFortyFourPointsIsAWarning() {
        let short = Node(label: "Close", traits: .button,
                         frame: CGRect(x: 0, y: 0, width: 44, height: 36), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [short]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testAFortyFourPointTargetPasses() {
        let fine = Node(label: "Close", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 44, height: 44), isElement: true)
        XCTAssertTrue(AccessibilityAuditor.unbudgeted().audit(root: Node(children: [fine]), checks: [.touchTarget], sampler: nil).findings.isEmpty)
    }

    /// A target between the AA floor and Apple's 44 is short of guidance but not of any
    /// standard, so it is a warning.
    func testAThirtyTwoPointTargetIsAWarningNotAnError() {
        let boundary = Node(label: "Close", traits: .button,
                            frame: CGRect(x: 0, y: 0, width: 32, height: 32), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [boundary]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// Static text is not tapped, so its size is not a target.
    func testTextIsExemptFromTheTargetCheck() {
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10), isElement: true)
        XCTAssertTrue(AccessibilityAuditor.unbudgeted().audit(root: Node(children: [text]), checks: [.touchTarget], sampler: nil).findings.isEmpty)
    }

    /// A check that is switched off is not run, and the result says which ones did run.
    func testOnlyTheRequestedChecksRun() {
        let bad = Node(traits: .button, frame: CGRect(x: 0, y: 0, width: 10, height: 10), isElement: true)

        let result = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [bad]), checks: [.touchTarget], sampler: nil)

        XCTAssertEqual(result.findings.map(\.check), [.touchTarget])
        XCTAssertEqual(result.checksRun, [.touchTarget])
    }

    /// An element with no label is named by what it is and where it is, or the finding that says
    /// "this has no label" would itself have nothing to point at.
    func testAnUnlabelledElementIsNamedByItsTypeAndPosition() {
        let node = Node(traits: .button, frame: CGRect(x: 12, y: 34, width: 10, height: 10),
                        isElement: true, typeName: "UIButton")

        let findings = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [node]), checks: [.missingLabel], sampler: nil).findings

        XCTAssertTrue(findings.first?.elementName.contains("UIButton") == true)
        XCTAssertTrue(findings.first?.elementName.contains("12") == true)
    }

    /// A sampler that hands back the same pixels for anything asked of it.
    private struct StubSampler: ContrastSampling {
        let pixels: [RGB]
        func samples(in frame: CGRect) -> [RGB] { pixels }
    }

    /// The same, but recording every rectangle it was asked about.
    ///
    /// ``StubSampler`` ignores its `frame`, so nothing asserted that
    /// `contrastOutcome(for:sampler:)` passes the element's resolved frame to the sampler at all —
    /// and in production `WindowContrastSampler.samples(in:)` returns `[]` for a rectangle that
    /// does not overlap the window, so passing `.zero`, or an untranslated frame, deletes every
    /// contrast finding on the screen and reads as "your app has no contrast problems". That is
    /// also the one untested link in the geometry chain wave C built `frameInWindow` to get right.
    private final class RecordingSampler: ContrastSampling {
        /// The pixels handed back for every request.
        let pixels: [RGB]

        /// Every rectangle this sampler was asked about, in order.
        private(set) var frames: [CGRect] = []

        /// Creates a sampler over `pixels`.
        ///
        /// - Parameter pixels: What to return for any request.
        init(pixels: [RGB]) { self.pixels = pixels }

        /// Records `frame` and returns ``pixels``.
        ///
        /// - Parameter frame: The region asked about, in window coordinates.
        /// - Returns: ``pixels``, unchanged.
        func samples(in frame: CGRect) -> [RGB] {
            frames.append(frame)
            return pixels
        }
    }

    /// The contrast check has to sample where the element actually *is*.
    func testTheContrastCheckSamplesTheElementsResolvedFrameInTheWindow() {
        let frame = CGRect(x: 37, y: 91, width: 120, height: 18)
        let text = Node(label: "Body copy", traits: .staticText, frame: frame, isElement: true)
        let sampler = RecordingSampler(pixels: midThresholdPixels)

        _ = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [text]),
                                         checks: [.contrast],
                                         sampler: sampler)

        XCTAssertEqual(sampler.frames, [frame],
                       "the sampler must be asked about the frame the walk resolved, once")
    }

    func testLowContrastTextIsAWarningWithBothColoursNamed() {
        let grey = RGB(red: 0.6, green: 0.6, blue: 0.6)
        let white = RGB(red: 1, green: 1, blue: 1)
        let sampler = StubSampler(pixels: Array(repeating: white, count: 80) + Array(repeating: grey, count: 20))
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
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

        let auditor = AccessibilityAuditor.unbudgeted()
        XCTAssertTrue(auditor.audit(root: Node(children: [large]), checks: [.contrast], sampler: sampler).findings.isEmpty)
        XCTAssertEqual(auditor.audit(root: Node(children: [small]), checks: [.contrast], sampler: sampler).findings.count, 1)
    }

    /// A photograph is not text, and a ratio taken across one means nothing.
    func testNonTextElementsAreNotMeasured() {
        let sampler = StubSampler(pixels: [RGB(red: 0, green: 0, blue: 0), RGB(red: 1, green: 1, blue: 1)])
        let image = Node(label: "Sunset", traits: .image,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 200), isElement: true)

        XCTAssertTrue(AccessibilityAuditor.unbudgeted().audit(root: Node(children: [image]), checks: [.contrast], sampler: sampler).findings.isEmpty)
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

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [disabled]), checks: [.contrast], sampler: sampler).findings

        XCTAssertTrue(findings.isEmpty, "WCAG 1.4.3 does not apply to an inactive component")
    }

    /// An icon-only button draws no text, so it is graded under WCAG 1.4.11 at 3:1 — having a
    /// label is evidence that it is *not* text, not evidence that it is.
    func testAnIconOnlyButtonIsHeldToTheNonTextThreshold() {
        let icon = Node(label: "Share", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 20, height: 20), isElement: true,
                        drawsText: false)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [icon]), checks: [.contrast], sampler: sampler).findings

        XCTAssertTrue(findings.isEmpty, "3.35:1 clears 1.4.11's 3:1 for non-text content")
    }

    /// The same pixels behind real text are a failure, so the two thresholds are genuinely
    /// distinguished rather than both being lenient.
    func testTextIsStillHeldToTheFourAndAHalfThreshold() {
        let text = Node(label: "Body copy", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true)
        let sampler = StubSampler(pixels: midThresholdPixels)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [text]), checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.count, 1)
    }

    /// WCAG 2.5.8 exempts a target that sits inline in a sentence, and nobody makes body-copy
    /// links 44pt tall — so a link is never worse than a warning.
    func testAnInlineLinkIsNeverMoreThanAWarning() {
        let link = Node(label: "Terms of Service", traits: .link,
                        frame: CGRect(x: 0, y: 0, width: 120, height: 18), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [link]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// A custom control whose author set `isAccessibilityElement` and forgot the traits is the
    /// half-done job the trait gate used to score as finished.
    func testAnElementWithNoTraitsAndNoLabelIsStillAFinding() {
        let untraited = Node(traits: .none, frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                             isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [untraited]), checks: [.missingLabel], sampler: nil).findings

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity, .error)
    }

    /// WCAG 2.5.8 AA sets the floor at 24pt, which is the only number in this rule anyone can
    /// cite; below it is an error.
    func testATargetUnderTwentyFourPointsIsAnError() {
        let tiny = Node(label: "Close", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 44, height: 20), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [tiny]), checks: [.touchTarget], sampler: nil).findings

        XCTAssertEqual(findings.first?.severity, .error)
    }

    /// The boundary itself: 24 is the AA minimum, so exactly 24 is short of Apple's 44 but not
    /// short of any guideline — a warning.
    func testATargetAtTwentyFourPointsIsAWarning() {
        let boundary = Node(label: "Close", traits: .button,
                            frame: CGRect(x: 0, y: 0, width: 24, height: 24), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
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

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [wrapped]), checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.count, 1, "a tall label is a wrapped label, not a large one")
    }

    /// A grey whose contrast against white is exactly `ratio`.
    ///
    /// WCAG's ratio is `(L₁ + 0.05) / (L₂ + 0.05)`, so against white the ink's relative luminance
    /// is `1.05 / ratio − 0.05`; the sRGB transfer function inverts to
    /// `1.055 · L^(1/2.4) − 0.055` everywhere above the linear toe, which every value here is.
    /// Built rather than written out so the fixtures cannot drift from the numbers they claim.
    ///
    /// - Parameter ratio: The contrast ratio wanted against white.
    /// - Returns: The grey that produces it.
    private func greyMeasuring(_ ratio: Double) -> RGB {
        let luminance = 1.05 / ratio - 0.05
        let component = 1.055 * pow(luminance, 1 / 2.4) - 0.055
        return RGB(red: component, green: component, blue: component)
    }

    /// Twenty per cent ink of `colour`, eighty per cent white — the shape of an ordinary crop, and
    /// the shape the analyser identifies the ink from.
    ///
    /// - Parameter colour: The ink.
    /// - Returns: One hundred pixels.
    private func inkOnWhite(_ colour: RGB) -> [RGB] {
        Array(repeating: RGB(red: 1, green: 1, blue: 1), count: 80) + Array(repeating: colour, count: 20)
    }

    /// WCAG 1.4.3's 4.5:1 is a *number*, and until now nothing on the branch said so.
    ///
    /// Every threshold test turned on one fixture at ≈3.35:1 plus one at ≈3.98:1, which between
    /// them require only `textRatio > 3.98`. Nothing bounded it above: `textRatio = 21` — flag all
    /// text except pure black on white — left the whole suite green. A pair either side of 4.5
    /// bounds it from both directions, and pins the `<` in `guard measured.ratio < threshold` at
    /// the same time.
    func testTheTextThresholdIsWCAGsFourAndAHalfToOne() {
        func findings(atRatio ratio: Double) -> Int {
            let text = Node(label: "Body copy", traits: .staticText,
                            frame: CGRect(x: 0, y: 0, width: 200, height: 16), isElement: true)
            return AccessibilityAuditor.unbudgeted().audit(root: Node(children: [text]),
                                                checks: [.contrast],
                                                sampler: StubSampler(pixels: inkOnWhite(greyMeasuring(ratio))))
                .findings.count
        }

        XCTAssertEqual(findings(atRatio: 4.4), 1, "4.4:1 is below WCAG 1.4.3's 4.5 and must be reported")
        XCTAssertEqual(findings(atRatio: 4.6), 0, "4.6:1 clears it and must not be")
    }

    /// And WCAG 1.4.11's 3:1 for non-text content, for the same reason and with more at stake:
    /// nothing required `relaxedRatio` to be above **1**, and at 1.0 the non-text check is off
    /// altogether — no icon, chevron or control boundary is ever flagged, and the report is the
    /// clean bill of health nobody earned that this branch's own documentation keeps citing.
    func testTheNonTextThresholdIsWCAGsThreeToOne() {
        func findings(atRatio ratio: Double) -> Int {
            let icon = Node(label: "Share", traits: .button,
                            frame: CGRect(x: 0, y: 0, width: 44, height: 44), isElement: true,
                            drawsText: false)
            return AccessibilityAuditor.unbudgeted().audit(root: Node(children: [icon]),
                                                checks: [.contrast],
                                                sampler: StubSampler(pixels: inkOnWhite(greyMeasuring(ratio))))
                .findings.count
        }

        XCTAssertEqual(findings(atRatio: 2.9), 1, "2.9:1 is below WCAG 1.4.11's 3 and must be reported")
        XCTAssertEqual(findings(atRatio: 3.1), 0, "3.1:1 clears it and must not be")
    }
}

// MARK: - How much of the screen contrast actually read

@MainActor
extension AccessibilityAuditorChecksTests {

    /// A sampler that answers differently for different rectangles.
    ///
    /// A list of pairs rather than a dictionary because `CGRect` only conforms to `Hashable` from
    /// iOS 18, and this library's floor is 16.
    private struct FrameKeyedSampler: ContrastSampling {
        /// What to return for each frame; anything not listed comes back empty.
        let byFrame: [(frame: CGRect, pixels: [RGB])]

        /// Returns the pixels registered for `frame`.
        ///
        /// - Parameter frame: The region asked about.
        /// - Returns: The registered pixels, or `[]`.
        func samples(in frame: CGRect) -> [RGB] {
            byFrame.first { $0.frame == frame }?.pixels ?? []
        }
    }

    /// The pass publishes, per element, how many candidates contrast was asked about and how many
    /// of them it could read.
    ///
    /// The report needs this to tell a check that read the screen from one that read almost none of
    /// it, and it used to re-derive it: a wrapper counted the sampler's *crops* and asked the
    /// analyser again on a strided subsample of each. That counted regions rather than elements —
    /// a row of four labels counted four times — and answered a slightly different question from
    /// the one the findings came from. The pass already knows; this asserts it says so.
    func testAPassPublishesHowManyElementsContrastCouldRead() {
        let readable = CGRect(x: 0, y: 0, width: 100, height: 16)
        let flat = CGRect(x: 0, y: 20, width: 100, height: 16)
        let root = Node(children: [
            Node(label: "Readable", traits: .staticText, frame: readable, isElement: true),
            Node(label: "Flat", traits: .staticText, frame: flat, isElement: true)
        ])
        let sampler = FrameKeyedSampler(byFrame: [
            (readable, midThresholdPixels),
            (flat, Array(repeating: RGB(red: 1, green: 1, blue: 1), count: 100))
        ])

        let result = AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.contrast], sampler: sampler)

        XCTAssertEqual(result.contrastCandidates, 2, "both elements were text the check was asked about")
        XCTAssertEqual(result.contrastMeasurements, 1, "only one of them had two colours in it")
    }

    /// An element the check does not grade at all is not a candidate, so a screen of photographs is
    /// not a screen contrast failed to read.
    func testAnElementContrastDoesNotGradeIsNotCountedAsACandidate() {
        let image = Node(label: "Sunset", traits: .image,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 200), isElement: true)

        let result = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [image]),
                                                  checks: [.contrast],
                                                  sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(result.contrastCandidates, 0)
        XCTAssertEqual(result.contrastMeasurements, 0)
    }

    /// The floor on a crop and the threshold on a screen have to be talking about the same crop.
    ///
    /// ``ContrastAnalyser/smallestUsefulSample`` refuses a crop of fewer than sixteen pixels,
    /// because below that a "group" is one or two pixels and its mode is noise. The report's
    /// measured-fraction threshold used to be fed by a probe over a *subsample* of each crop, so on
    /// small elements the two rules ran over two different populations and an element whose full
    /// crop measures perfectly well could be counted unreadable — a screen of small controls then
    /// carried an unmeasurable banner over a check that had in fact read all of it. Taking the
    /// count from the pass makes them the same rule by construction, and this is the fixture that
    /// says so: exactly the smallest crop the analyser accepts, measured, and counted as measured.
    func testASmallElementWhoseCropIsAtTheAnalysersFloorIsCountedAsMeasured() {
        let grey = RGB(red: 0.55, green: 0.55, blue: 0.55)
        let white = RGB(red: 1, green: 1, blue: 1)
        let pixels = Array(repeating: white, count: 13) + Array(repeating: grey, count: 3)
        XCTAssertEqual(pixels.count, ContrastAnalyser.smallestUsefulSample,
                       "the fixture is only meaningful sitting exactly on the floor")

        let small = Node(label: "12", traits: .staticText,
                         frame: CGRect(x: 0, y: 0, width: 8, height: 8), isElement: true)
        let result = AccessibilityAuditor.unbudgeted().audit(root: Node(children: [small]),
                                                  checks: [.contrast],
                                                  sampler: StubSampler(pixels: pixels))

        XCTAssertEqual(result.contrastMeasurements, 1, "the analyser accepts this crop, so the count must too")
        XCTAssertTrue(AccessibilityAudit.checksPartiallyMeasured(
            from: [.contrast],
            candidates: result.contrastCandidates,
            measured: result.contrastMeasurements
        ).isEmpty, "and a check that read everything it was asked about has full coverage")
    }

    /// The other side of the same join, and the rule that changed: a pass that could read only one
    /// crop out of four **keeps the finding it made** and reports its coverage. It used to be
    /// declared unmeasurable outright — banner, no tick, worded as though nothing had been read —
    /// which threw away the standing of a real defect because the elements *around* it happened to
    /// be a photograph.
    func testAPassThatCouldReadOnePartOfTheScreenStillReportsWhatItFound() {
        let readable = CGRect(x: 0, y: 0, width: 100, height: 16)
        let root = Node(children: (0..<4).map { index in
            Node(label: "row \(index)", traits: .staticText,
                 frame: CGRect(x: 0, y: index * 20, width: 100, height: 16), isElement: true)
        })
        let sampler = FrameKeyedSampler(byFrame: [(readable, midThresholdPixels)])

        let result = AccessibilityAuditor.unbudgeted().audit(root: root, checks: [.contrast], sampler: sampler)

        XCTAssertEqual(result.contrastCandidates, 4)
        XCTAssertEqual(result.contrastMeasurements, 1)
        XCTAssertEqual(result.findings.count, 1, "the one crop it could read failed, and that is a defect")
        XCTAssertTrue(result.checksUnmeasurable.isEmpty,
                      "a check that measured something has not failed to measure")
        XCTAssertEqual(AccessibilityAudit.checksPartiallyMeasured(
            from: [.contrast],
            candidates: result.contrastCandidates,
            measured: result.contrastMeasurements
        ), [.contrast], "and the report has to say how much of the screen that was")
    }

    /// Nothing measured at all is still an absence of an answer rather than a result, and stays
    /// out of the coverage rule: it is the unmeasurable banner's case, not this one's.
    func testAPassThatMeasuredNothingIsUnmeasurableRatherThanPartlyMeasured() {
        let root = Node(children: [Node(label: "Body copy", traits: .staticText,
                                        frame: CGRect(x: 0, y: 0, width: 100, height: 16),
                                        isElement: true)])

        let result = AccessibilityAuditor.unbudgeted().audit(root: root,
                                                  checks: [.contrast],
                                                  sampler: StubSampler(pixels: []))

        XCTAssertEqual(result.checksUnmeasurable, [.contrast])
        XCTAssertTrue(AccessibilityAudit.checksPartiallyMeasured(
            from: [.contrast],
            candidates: result.contrastCandidates,
            measured: result.contrastMeasurements
        ).isEmpty, "the two states are exclusive, or the report shows two banners for one gap")
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
        let auditor = AccessibilityAuditor.unbudgeted()

        XCTAssertTrue(auditor.audit(root: Node(children: [bold]), checks: [.contrast], sampler: sampler).findings.isEmpty)
        XCTAssertEqual(auditor.audit(root: Node(children: [regular]), checks: [.contrast], sampler: sampler).findings.count, 1)
    }

    /// A button that draws a title is text, whatever its traits say, so it keeps the strict
    /// threshold that the icon-only case gives up.
    func testAButtonWithATitleIsStillGradedAsText() {
        let titled = Node(label: "Continue", traits: .button,
                          frame: CGRect(x: 0, y: 0, width: 200, height: 44), isElement: true,
                          drawsText: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [titled]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertEqual(findings.count, 1, "a padded button's title is still body text")
    }

    /// Text whose size cannot be read stays at the strict threshold rather than being guessed
    /// into the lenient one: the relaxation can only ever hide a failure.
    func testTextWithNoReadableSizeKeepsTheStrictThreshold() {
        let unknown = Node(label: "Something", traits: .staticText,
                           frame: CGRect(x: 0, y: 0, width: 200, height: 60), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [unknown]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertEqual(findings.count, 1)
    }

    /// An element with a value reads that value, so it is not nameless in the way the check
    /// exists to catch.
    func testAnElementWithAValueButNoLabelIsExempt() {
        let slider = Node(traits: .adjustable, frame: CGRect(x: 0, y: 0, width: 200, height: 44),
                          isElement: true, value: "50%")

        XCTAssertTrue(AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [slider]), checks: [.missingLabel], sampler: nil).findings.isEmpty)
    }

    /// A real `UILabel` supplies its own point size, which is the case the rule is actually for.
    func testAUILabelReportsItsOwnFontSize() {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 15)
        label.text = "Hello"

        XCTAssertEqual(label.auditFontPointSize, 15)
        XCTAssertTrue(label.auditFontIsBold)
        XCTAssertEqual(label.auditDrawsText, true)
    }

    /// An icon-only button has a name and no text, and that is exactly what the threshold turns
    /// on.
    func testAUIButtonWithNoTitleDrawsNoText() {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "Share"

        XCTAssertEqual(button.auditDrawsText, false)
    }

    /// A contrast check that looked at candidates and could read none of them has not passed
    /// them. Seven distinct ways of failing to measure used to render exactly like a clean
    /// screen.
    func testAContrastCheckThatMeasuresNothingSaysSo() {
        let text = Node(label: "Hello", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let result = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [text]), checks: [.contrast], sampler: StubSampler(pixels: []))

        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.checksUnmeasurable, [.contrast])
    }

    /// One element it could read is enough: the report only has to say "I measured nothing" when
    /// it measured nothing.
    func testAContrastCheckThatMeasuresSomethingIsNotUnmeasurable() {
        let readable = Node(label: "Hello", traits: .staticText,
                            frame: CGRect(x: 0, y: 0, width: 80, height: 16), isElement: true)

        let result = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [readable]), checks: [.contrast], sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertTrue(result.checksUnmeasurable.isEmpty)
    }

    /// A screen with no text at all is silent rather than unmeasurable: there was nothing to
    /// measure, which is not the same as failing to measure it.
    func testAScreenWithNoTextIsNotReportedAsUnmeasurable() {
        let image = Node(label: "Sunset", traits: .image,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 200), isElement: true)

        let result = AccessibilityAuditor.unbudgeted()
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
        var auditor = AccessibilityAuditor.unbudgeted()
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
        var auditor = AccessibilityAuditor.unbudgeted()
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

// MARK: - Round two: the trait gate, the unknown default, and what a finding says

@MainActor
extension AccessibilityAuditorChecksTests {

    /// A sampler that answers one nominated rectangle with one set of pixels and everything else
    /// with another, so a test can put a failure behind exactly one label of a row.
    private struct RegionSampler: ContrastSampling {
        let region: CGRect
        let inRegion: [RGB]
        let elsewhere: [RGB]

        func samples(in frame: CGRect) -> [RGB] { frame == region ? inRegion : elsewhere }
    }

    /// The single most damaging thing round two found. A `UITableViewCell` that makes itself one
    /// VoiceOver stop carries `.none` traits; the old rule sampled only `.staticText` and
    /// `.button`, and the walk stops at the cell so the labels inside it were never visited
    /// either. On the most ordinary screen in iOS — a list — *nothing* was contrast-checked and
    /// the report printed a green tick.
    func testACombinedRowWithNoTextTraitIsStillContrastChecked() {
        let row = Node(label: "Jane Appleseed, unread", traits: .none,
                       frame: CGRect(x: 0, y: 0, width: 375, height: 60), isElement: true)

        let result = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [row]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(result.findings.count, 1, "a list row is where an app's text actually lives")
    }

    /// A text field carries neither of the old traits either, and its entered text and placeholder
    /// are exactly the low-contrast greys that need checking.
    func testATextFieldIsContrastChecked() {
        let field = Node(label: "Email", traits: .none,
                         frame: CGRect(x: 0, y: 0, width: 300, height: 34), isElement: true,
                         drawsText: true)

        let result = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [field]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(result.findings.count, 1)
    }

    /// Unknown text-ness now resolves the way unknown point size always did: strictly. Every
    /// SwiftUI element is a synthetic one that conforms to nothing, so `Button("Continue")` — a
    /// `.button` trait, no `.staticText`, nothing readable — was graded at 3:1 and a 3.35:1 title
    /// passed. The same shape covers every cell that sets `.button` to become one VoiceOver stop.
    func testAButtonThatCannotSayWhetherItDrawsTextIsGradedAsText() {
        let swiftUIButton = Node(label: "Continue", traits: .button,
                                 frame: CGRect(x: 0, y: 0, width: 200, height: 44), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [swiftUIButton]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertEqual(findings.count, 1, "only an affirmative \"I draw no text\" earns 3:1")
    }

    /// The relaxation is kept for the one element SwiftUI *can* be identified by: an icon-only
    /// button carries `.image` alongside `.button`, and a graphic is graded at 1.4.11's 3:1.
    func testASyntheticIconButtonKeepsTheNonTextThreshold() {
        let icon = Node(label: "Share", traits: [.button, .image],
                        frame: CGRect(x: 0, y: 0, width: 44, height: 44), isElement: true)

        XCTAssertTrue(AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [icon]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels)).findings.isEmpty)
    }

    /// A finding that withholds the large-text allowance has to say it did. Without this a
    /// developer sees "About 3.4:1, under 4.5:1" on a 34pt heading that conforms at 3:1 and has no
    /// way to work out why.
    func testAFindingSaysWhenTheLargeTextAllowanceWasWithheldForWantOfASize() {
        let heading = Node(label: "Welcome", traits: .staticText,
                           frame: CGRect(x: 0, y: 0, width: 300, height: 40), isElement: true)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [heading]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertTrue(findings.first?.detail.contains("large-text") == true,
                      "an unexplained conservative verdict reads as a bug in the tool")
    }

    /// And it says nothing of the sort when the size really was read, or the note would appear on
    /// every finding and mean nothing.
    func testAFindingWithAKnownSizeCarriesNoSuchNote() {
        let body = Node(label: "Body copy", traits: .staticText,
                        frame: CGRect(x: 0, y: 0, width: 300, height: 20), isElement: true,
                        fontPointSize: 13)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [body]), checks: [.contrast],
                   sampler: StubSampler(pixels: midThresholdPixels)).findings

        XCTAssertFalse(findings.first?.detail.contains("large-text") == true)
    }

    /// The error and the warning cite different numbers, and the developer has to be shown which.
    /// One string reading "under the 44 × 44pt minimum" for both meant the 24pt line — the whole
    /// point of the severity split — appeared nowhere at all.
    func testTheTwoTouchTargetSeveritiesCiteDifferentStandards() {
        let tiny = Node(label: "Close", traits: .button,
                        frame: CGRect(x: 0, y: 0, width: 20, height: 20), isElement: true)
        let short = Node(label: "Close", traits: .button,
                         frame: CGRect(x: 0, y: 0, width: 36, height: 36), isElement: true)
        let auditor = AccessibilityAuditor.unbudgeted()

        let error = auditor.audit(root: Node(children: [tiny]), checks: [.touchTarget], sampler: nil).findings.first
        let warning = auditor.audit(root: Node(children: [short]), checks: [.touchTarget], sampler: nil).findings.first

        XCTAssertEqual(error?.severity, .error)
        XCTAssertTrue(error?.detail.contains("24 × 24") == true, "the AA floor is the citable number")
        XCTAssertEqual(warning?.severity, .warning)
        XCTAssertTrue(warning?.detail.contains("44 × 44") == true)
        XCTAssertNotEqual(error?.detail, warning?.detail)
    }

    /// An element the sampler could read nothing usable from is unmeasurable, never a pass. The
    /// analyser refuses a gradient, a photograph and near-black bar material, and every one of
    /// those has to arrive at the report as "could not measure".
    func testAnUntrustworthyCropIsReportedAsUnmeasurableRatherThanPassed() {
        // Two 8-bit steps of dither, which is what a caption behind a navigation bar looks like.
        let dither = Array(repeating: RGB(red: 0x04 / 255, green: 0x04 / 255, blue: 0x04 / 255), count: 80)
            + Array(repeating: RGB(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255), count: 20)
        let caption = Node(label: "Scrolled under the bar", traits: .staticText,
                           frame: CGRect(x: 32, y: 30, width: 333, height: 30), isElement: true)

        let result = AccessibilityAuditor.unbudgeted()
            .audit(root: Node(children: [caption]), checks: [.contrast], sampler: StubSampler(pixels: dither))

        XCTAssertTrue(result.findings.isEmpty, "no confident number from an untrustworthy crop")
        XCTAssertEqual(result.checksUnmeasurable, [.contrast], "and never silently a pass")
    }
}

// MARK: - Sampling the text that is actually drawn

@MainActor
extension AccessibilityAuditorChecksTests {

    /// A real cell, built the way UIKit apps build one: the cell is the VoiceOver stop and the
    /// text lives in labels inside it.
    private func combinedRow() -> (row: UIView, title: UILabel, subtitle: UILabel) {
        let row = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 60))
        row.isAccessibilityElement = true
        row.accessibilityLabel = "Jane Appleseed, 2 unread" // scyther:unlocalised test fixture
        let title = UILabel(frame: CGRect(x: 60, y: 8, width: 200, height: 20))
        title.font = .systemFont(ofSize: 17)
        title.text = "Jane Appleseed" // scyther:unlocalised test fixture
        let subtitle = UILabel(frame: CGRect(x: 60, y: 32, width: 200, height: 16))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.text = "2 unread" // scyther:unlocalised test fixture
        row.addSubview(title)
        row.addSubview(subtitle)
        return (row, title, subtitle)
    }

    /// The descent finds the text a combined element draws, and finds only that: the row itself
    /// draws none, so measuring its whole rectangle would be measuring 95% background beside an
    /// avatar and a chevron.
    func testTheDescentFindsTheLabelsInsideACombinedRow() {
        let row = combinedRow()

        let regions = AccessibilityAuditor.drawnTextViews(in: row.row)

        XCTAssertEqual(regions.count, 2)
        XCTAssertTrue(regions.contains { $0 === row.title })
        XCTAssertTrue(regions.contains { $0 === row.subtitle })
    }

    /// A hidden label is not on screen and is not sampled.
    func testTheDescentSkipsHiddenText() {
        let row = combinedRow()
        row.subtitle.isHidden = true

        XCTAssertEqual(AccessibilityAuditor.drawnTextViews(in: row.row).map { $0 === row.title }, [true])
    }

    /// Descending is what recovers the point size the combined element could never supply, so the
    /// 13pt subtitle is graded at 4.5:1 rather than at the row's unknown.
    func testEachDrawnLabelIsGradedByItsOwnPointSize() {
        let row = combinedRow()

        XCTAssertEqual(row.title.auditFontPointSize, 17)
        XCTAssertEqual(row.subtitle.auditFontPointSize, 13)
    }

    /// The finding is reported at the failing text's own frame rather than at the row's, so the
    /// overlay boxes the label the developer has to fix.
    func testTheFindingBoxesTheTextThatFailedNotTheWholeRow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        window.isHidden = false
        let row = combinedRow()
        window.addSubview(row.row)
        let clean = Array(repeating: RGB(red: 1, green: 1, blue: 1), count: 80)
            + Array(repeating: RGB(red: 0, green: 0, blue: 0), count: 20)
        let sampler = RegionSampler(region: row.subtitle.frameInWindow,
                                    inRegion: midThresholdPixels,
                                    elsewhere: clean)

        let findings = AccessibilityAuditor.unbudgeted()
            .audit(root: window, checks: [.contrast], sampler: sampler).findings

        XCTAssertEqual(findings.count, 1, "one element still produces at most one finding")
        XCTAssertEqual(findings.first?.frame, row.subtitle.frameInWindow)
        XCTAssertEqual(findings.first?.elementName, "Jane Appleseed, 2 unread",
                       "named by the element VoiceOver lands on, not by the label inside it")
    }

    /// A `UIButton` whose title was set with `setAttributedTitle(_:for:)` draws text. Reading
    /// `currentTitle` — which is `nil` for that path and unreliable for `UIButton.Configuration` —
    /// answered "draws no text" and quietly dropped "Forgot password?" a threshold level.
    func testAnAttributedButtonTitleCountsAsDrawnText() {
        let button = UIButton(type: .system)
        button.setAttributedTitle(NSAttributedString(string: "Forgot password?"), for: .normal) // scyther:unlocalised test fixture

        XCTAssertEqual(button.auditDrawsText, true)
    }

    /// `UILabel.font` is the fallback typeface and has nothing to do with the runs in
    /// `attributedText`. A 20pt fallback over 11pt runs was graded at 3:1 and passed at 3.2:1; the
    /// smallest run is the size the strict threshold has to hold for.
    func testAnAttributedLabelIsGradedByItsSmallestRun() {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20)
        let text = NSMutableAttributedString(string: "Heading", // scyther:unlocalised test fixture
                                             attributes: [.font: UIFont.systemFont(ofSize: 28)])
        text.append(NSAttributedString(string: " footnote", // scyther:unlocalised test fixture
                                       attributes: [.font: UIFont.systemFont(ofSize: 11)]))
        label.attributedText = text

        XCTAssertEqual(label.auditFontPointSize, 11)
    }

    /// UIKit shrinks a label that adjusts to fit without ever changing `font`, so a 20pt label can
    /// be rendering at 10pt. WCAG's rule is about the size on the screen.
    func testALabelThatShrinksToFitIsGradedAtTheSizeItCanShrinkTo() {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20)
        label.text = "A very long string that will not fit" // scyther:unlocalised test fixture
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5

        XCTAssertEqual(label.auditFontPointSize, 10)
    }
}

// MARK: - Cost

@MainActor
extension AccessibilityAuditorChecksTests {

    /// A node that counts how many times its frame is read.
    private final class CountingNode: AuditNode, AuditNodeDetails {
        var reads = 0
        var isAccessibilityElementNode = true
        var accessibilityLabelText: String? = "Row" // scyther:unlocalised test fixture
        var traits: UIAccessibilityTraits = .staticText
        var isVisible = true
        var isScytherOwned = false
        var typeName = "CountingNode" // scyther:unlocalised test fixture
        var children: [AuditNode] = []

        var frameInWindow: CGRect {
            reads += 1
            return CGRect(x: 0, y: 0, width: 20, height: 20)
        }
    }

    /// `frameInWindow` is an ancestor climb, not a property read — two of them for a view under
    /// Scyther's sheet, and a container-chain walk for a synthetic element. The walk read it, then
    /// the visibility test read it again, then each of the three checks and the naming helper read
    /// it again: up to eight climbs per node, and at the 5,000-node cap hundreds of thousands of
    /// pointer chases inside a quarter-second budget.
    func testAnElementsFrameIsResolvedOncePerPass() {
        let node = CountingNode()
        let root = Node(children: [node])

        _ = AccessibilityAuditor.unbudgeted().audit(root: root,
                                         checks: [.missingLabel, .touchTarget, .contrast],
                                         sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(node.reads, 1, "every rule reads the frame the walk already resolved")
    }
}

// MARK: - The shape SwiftUI actually puts on screen

@MainActor
extension AccessibilityAuditorChecksTests {

    /// The descent added to sample a combined UIKit cell label by label looks for text-drawing
    /// `UIView`s, and SwiftUI has none: it draws its text into private layers and hangs synthetic
    /// `UIAccessibilityElement`s off the hosting view. Nothing may be allowed to make that descent
    /// the *only* way an element becomes measurable, or contrast goes dark on the commonest UI
    /// framework in use and the report says so in a banner rather than in findings.
    ///
    /// The rule this pins: descend when there is something to descend into, otherwise measure the
    /// element's own frame. An element with a non-empty label that is not an image is text as far
    /// as this check is concerned, whatever drew it.
    func testASyntheticElementOverAViewWithNoTextViewsIsStillMeasured() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 400))
        window.isHidden = false
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 400))
        window.addSubview(host)
        let text = UIAccessibilityElement(accessibilityContainer: host)
        text.accessibilityLabel = "Hard to read text" // scyther:unlocalised test fixture
        text.accessibilityTraits = .staticText
        text.accessibilityFrame = CGRect(x: 16, y: 40, width: 200, height: 20)
        host.accessibilityElements = [text]

        XCTAssertTrue(AccessibilityAuditor.drawnTextViews(in: host).isEmpty,
                      "the fixture is only meaningful with no drawn text view to find")

        let result = AccessibilityAuditor.unbudgeted().audit(root: window,
                                                  checks: [.contrast],
                                                  sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(result.contrastCandidates, 1, "a labelled synthetic element is text")
        XCTAssertEqual(result.contrastMeasurements, 1)
        XCTAssertEqual(result.findings.count, 1)
    }

    /// The same claim, made against SwiftUI itself rather than against a hand-built stand-in for
    /// it, because the stand-in is only worth anything if it is the shape SwiftUI really produces.
    /// A `List` of `Text` vends `AccessibilityNode`s — synthetic elements, `.staticText`, no
    /// `UILabel` anywhere in the hierarchy — and every one of them has to be measured.
    func testARealSwiftUIListIsContrastMeasuredElementByElement() throws {
        // Waits for both rows to be published rather than giving SwiftUI a fixed half-second: that
        // was long enough on the development toolchain and never long enough on CI's, which is how
        // this test was red on every CI run since the audit landed. See `HostedSwiftUIWindow`.
        let window = try HostedSwiftUIWindow.make(
            hosting: List {
                Text("Hard to read text") // scyther:unlocalised test fixture
                Text("Another line") // scyther:unlocalised test fixture
            },
            isReady: { HostedSwiftUIWindow.publishedAccessibilityElementCount($0) >= 2 }
        )

        let auditor = AccessibilityAuditor.unbudgeted()
        let walked = auditor.collect(root: window)
        XCTAssertFalse(walked.nodes.isEmpty, "SwiftUI put no accessibility elements on screen at all")
        XCTAssertTrue(walked.nodes.allSatisfy { !($0 is UIView) },
                      "the fixture is only meaningful while SwiftUI's elements are synthetic")

        let result = auditor.audit(root: window,
                                   checks: [.contrast],
                                   sampler: StubSampler(pixels: midThresholdPixels))

        XCTAssertEqual(result.contrastCandidates, walked.nodes.count,
                       "every element SwiftUI drew text into is a candidate")
        XCTAssertEqual(result.contrastMeasurements, result.contrastCandidates)
        XCTAssertEqual(result.findings.count, result.contrastCandidates)
    }
}
