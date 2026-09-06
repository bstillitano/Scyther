# Accessibility Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the developer, on the screen they are looking at, the accessibility defects a VoiceOver or Switch Control user would hit — elements with no label, touch targets under 44pt, and text below WCAG AA contrast — as live boxes over the app and as a frozen, readable report.

**Architecture:** A pure auditor walks an `AuditNode` tree (the accessibility tree, adapted) and returns findings; a `UIView` conformance adapts the real key window to that protocol, so every check is unit-testable with no simulator UI. A `TopLevelView` on `InterfaceToolkit`'s existing `topLevelViewsWrapper` draws the boxes, exactly as the grid overlay does, and a SwiftUI screen reached from **UI/UX** reads the findings.

**Tech Stack:** Swift 6 (complete strict concurrency), iOS 16 floor, SwiftUI + UIKit, XCTest, String Catalogues via `Scripts/localization/build_catalog.py`.

**Spec:** `docs/superpowers/specs/2026-09-06-accessibility-audit-design.md`

## Global Constraints

- iOS only. Build and test with `xcodebuild -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO`. `swift build` does not work.
- Swift 6 language mode, complete strict concurrency. UIKit-touching types are `@MainActor`.
- Every user-facing string goes through `localized(_:)`, with the key added to `Scripts/localization/strings/AccessibilityAudit.json` in all twelve languages (`fr`, `de`, `es`, `it`, `pt-BR`, `nl`, `ja`, `zh-Hans`, `zh-Hant`, `ko`, `ru`, `ar`), then `python3 Scripts/localization/build_catalog.py`.
- A string that embeds a measurement is one key with an interpolation, never concatenation.
- DocC on every type, property and method, including `private` ones.
- MVVM: one view model per view, in its own file.
- Stock SwiftUI components wherever the system provides one. Never hand-roll a row or control SwiftUI already has. Building something the system does not provide is fine and expected.
- Alerts, never `.confirmationDialog`.
- Thresholds, verbatim from the spec: 44pt touch targets; error below 32pt, warning from 32pt to 44pt; contrast 4.5:1, or 3:1 when the element's frame is at least 24pt tall; depth cap 100; node cap 5,000; downsample cap 64 × 64; debounce 0.5s.
- `UserDefaults.scyther` keys: `Scyther_accessibility_audit_live`, `Scyther_accessibility_audit_missing_labels`, `Scyther_accessibility_audit_touch_targets`, `Scyther_accessibility_audit_contrast`.
- No Claude attribution, session URLs or co-author trailers in any commit message.
- Update `README.md` and `Sources/Scyther/Scyther.docc/` for user-visible behaviour.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityCheck.swift` | The three checks and the severity scale. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityFinding.swift` | One defect, with its measured detail. |
| `Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift` | The protocol the auditor walks, plus the `UIView`/`NSObject` adapters. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditor.swift` | The walk and the label/target checks. |
| `Sources/Scyther/Features/AccessibilityAudit/ContrastAnalyser.swift` | Luminance, clustering, ratio. Pure maths over pixels. |
| `Sources/Scyther/Features/AccessibilityAudit/WindowContrastSampler.swift` | One window snapshot per pass; crops and downsamples per element. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAudit.swift` | The singleton: settings, persistence, and `auditKeyWindow()`. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditOverlayView.swift` | The `TopLevelView`: boxes and the count pill. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditView.swift` | The report screen. |
| `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditViewModel.swift` | Its view model: grouping, freezing, re-run. |
| `Sources/Scyther/Core/InterfaceToolkit.swift` | Hosts the overlay, like the grid overlay. |
| `Sources/Scyther/Features/Menu/*` | The **UI/UX** row and its search entries. |

---

### Task 1: The finding vocabulary

**Files:**
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityCheck.swift`
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityFinding.swift`
- Create: `Scripts/localization/strings/AccessibilityAudit.json`
- Test: `Tests/ScytherTests/Features/AccessibilityFindingTests.swift`

**Interfaces:**
- Produces: `AccessibilityCheck` (`.missingLabel`, `.touchTarget`, `.contrast`; `title: String`, `defaultsKey: String`, `id: String`), `AccessibilitySeverity` (`.warning`, `.error`; `Comparable`), `AccessibilityFinding(check:severity:frame:elementName:detail:)` with `id: UUID`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ScytherTests/Features/AccessibilityFindingTests.swift
@testable import Scyther
import XCTest

final class AccessibilityFindingTests: XCTestCase {

    func testEveryCheckHasItsOwnDefaultsKey() {
        let keys = Set(AccessibilityCheck.allCases.map(\.defaultsKey))
        XCTAssertEqual(keys.count, AccessibilityCheck.allCases.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("Scyther_accessibility_audit_") })
    }

    /// An error sorts above a warning, so the report can lead with what matters.
    func testAnErrorOutranksAWarning() {
        XCTAssertTrue(AccessibilitySeverity.error > AccessibilitySeverity.warning)
    }

    /// Two findings about the same element are still two findings.
    func testFindingsAreIdentifiedIndividually() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let first = AccessibilityFinding(check: .touchTarget, severity: .error, frame: frame,
                                         elementName: "Close", detail: "10.0 × 10.0pt")
        let second = AccessibilityFinding(check: .touchTarget, severity: .error, frame: frame,
                                          elementName: "Close", detail: "10.0 × 10.0pt")
        XCTAssertNotEqual(first.id, second.id)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/AccessibilityFindingTests`
Expected: compile failure — `AccessibilityCheck` does not exist.

- [ ] **Step 3: Write the types**

```swift
// AccessibilityCheck.swift
import Foundation

/// One thing the audit looks for.
///
/// Each check is switched on and off on its own, and a check that is off is not run at all —
/// which is why the report names the checks that did not run: "no findings" and "nothing was
/// looked at" must never read the same way.
enum AccessibilityCheck: String, CaseIterable, Sendable, Identifiable {
    /// An element VoiceOver cannot name.
    case missingLabel
    /// A target smaller than a finger.
    case touchTarget
    /// Text too close in colour to what is behind it.
    case contrast

    /// The raw value, so SwiftUI can key rows on it.
    var id: String { rawValue }

    /// The check's name, as the report and the settings screen show it.
    var title: String {
        switch self {
        case .missingLabel: return localized("Missing Labels")
        case .touchTarget: return localized("Touch Targets")
        case .contrast: return localized("Contrast")
        }
    }

    /// Where this check's on/off state is persisted in `UserDefaults.scyther`.
    var defaultsKey: String {
        switch self {
        case .missingLabel: return "Scyther_accessibility_audit_missing_labels"
        case .touchTarget: return "Scyther_accessibility_audit_touch_targets"
        case .contrast: return "Scyther_accessibility_audit_contrast"
        }
    }
}

/// How much a finding matters.
///
/// Two levels, not five. A finding is either something a user cannot work around — a control
/// with no name — or something that might be deliberate, and a scale finer than that would be
/// a judgement the toolkit is not in a position to make.
enum AccessibilitySeverity: Int, Comparable, Sendable {
    /// Worth looking at; may be deliberate, or may be an estimate.
    case warning = 0
    /// Broken for somebody.
    case error = 1

    static func < (lhs: AccessibilitySeverity, rhs: AccessibilitySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

```swift
// AccessibilityFinding.swift
import CoreGraphics
import Foundation

/// One defect the audit found, on one element.
///
/// Carries what was measured rather than only what failed: `32.0 × 32.0pt` tells the developer
/// how far off the target is, where "too small" tells them nothing they can act on.
struct AccessibilityFinding: Identifiable, Sendable, Equatable {
    /// A fresh identity per finding. Two findings about one element are still two findings.
    let id: UUID

    /// Which check produced it.
    let check: AccessibilityCheck

    /// How much it matters.
    let severity: AccessibilitySeverity

    /// The element's frame in window coordinates, which is where the overlay draws.
    let frame: CGRect

    /// What to call the element: its accessibility label, or its type and position when it has
    /// none — which is precisely the case the missing-label check exists to report.
    let elementName: String

    /// The measurement, already localised and formatted.
    let detail: String

    /// Creates a finding.
    ///
    /// - Parameters:
    ///   - check: The check that produced it.
    ///   - severity: How much it matters.
    ///   - frame: The element's frame in window coordinates.
    ///   - elementName: What to call the element in the report.
    ///   - detail: The localised measurement.
    init(check: AccessibilityCheck,
         severity: AccessibilitySeverity,
         frame: CGRect,
         elementName: String,
         detail: String) {
        self.id = UUID()
        self.check = check
        self.severity = severity
        self.frame = frame
        self.elementName = elementName
        self.detail = detail
    }
}
```

- [ ] **Step 4: Add the localisation fragment**

Create `Scripts/localization/strings/AccessibilityAudit.json` with the three titles above, each with all twelve languages and a `comment`. Follow the shape of `Scripts/localization/strings/Breakpoints.json` exactly. Then run:

```bash
python3 Scripts/localization/build_catalog.py
```

- [ ] **Step 5: Run the tests and watch them pass**

Run the same `-only-testing` command. Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/AccessibilityAudit Tests/ScytherTests/Features/AccessibilityFindingTests.swift Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Name the accessibility checks and what they find"
```

---

### Task 2: The walk

**Files:**
- Create: `Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift`
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditor.swift`
- Test: `Tests/ScytherTests/Features/AccessibilityAuditorWalkTests.swift`

**Interfaces:**
- Consumes: `AccessibilityFinding`, `AccessibilityCheck` from Task 1.
- Produces: `AuditNode` protocol; `AccessibilityAuditor.collect(root:) -> (nodes: [AuditNode], didHitLimit: Bool)`; `AccessibilityAuditor.maximumDepth = 100`; `AccessibilityAuditor.maximumNodes = 5000`.

The `UIView` conformance is **Task 5**. This task is the protocol and the traversal only, tested with doubles.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/AccessibilityAuditorWalkTests.swift
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
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `… -only-testing:ScytherTests/AccessibilityAuditorWalkTests`
Expected: compile failure — `AuditNode` does not exist.

- [ ] **Step 3: Write the protocol and the walk**

```swift
// AuditNode.swift
import UIKit

/// One node of the tree the audit walks.
///
/// The audit walks the *accessibility* tree, not the view tree: a SwiftUI `Text` is not a
/// `UILabel`, and a walk over `subviews` finds a drawing layer with no label, no traits and
/// nothing to check. This protocol is what the checks see, so every one of them is testable
/// against a handful of values rather than against a running app.
@MainActor
protocol AuditNode {
    /// Whether this node is itself an accessibility element — a leaf, in VoiceOver's terms.
    var isAccessibilityElementNode: Bool { get }

    /// The label VoiceOver would read, if any.
    var accessibilityLabelText: String? { get }

    /// What VoiceOver is told this element is.
    var traits: UIAccessibilityTraits { get }

    /// The node's frame in window coordinates, which is where the overlay draws.
    var frameInWindow: CGRect { get }

    /// Whether the node can be seen: on screen, not hidden, not fully transparent.
    var isVisible: Bool { get }

    /// Whether the node belongs to Scyther rather than to the app under audit.
    var isScytherOwned: Bool { get }

    /// The node's type, for naming an element that has no label.
    var typeName: String { get }

    /// The nodes below this one: accessibility children where there are any, subviews otherwise.
    var children: [AuditNode] { get }
}
```

```swift
// AccessibilityAuditor.swift
import UIKit

/// Walks a tree of ``AuditNode`` and reports what is wrong with it.
///
/// Pure with respect to UIKit: it is handed a root and returns findings, so every rule in it can
/// be tested against a tree of doubles with no window, no simulator UI and no timing.
@MainActor
struct AccessibilityAuditor {
    /// How deep the walk goes before it gives up.
    ///
    /// A hierarchy deeper than this is either pathological or cyclic, and hanging the app the
    /// developer is debugging is worse than an incomplete answer — as long as the answer says it
    /// is incomplete.
    static let maximumDepth = 100

    /// How many nodes the walk visits before it gives up, for the same reason.
    static let maximumNodes = 5000

    /// Every element worth checking, in tree order.
    ///
    /// - Parameter root: The node to walk from, usually the key window.
    /// - Returns: The elements found, and whether a cap stopped the walk before it finished.
    func collect(root: AuditNode) -> (nodes: [AuditNode], didHitLimit: Bool) {
        var found: [AuditNode] = []
        var didHitLimit = false
        var visited = 0

        func walk(_ node: AuditNode, depth: Int) {
            guard !didHitLimit else { return }
            guard depth <= Self.maximumDepth else {
                didHitLimit = true
                return
            }
            guard !node.isScytherOwned, node.isVisible, !node.frameInWindow.isEmpty else { return }

            visited += 1
            guard visited <= Self.maximumNodes else {
                didHitLimit = true
                return
            }

            if node.isAccessibilityElementNode {
                found.append(node)
                return
            }

            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return (found, didHitLimit)
    }
}
```

- [ ] **Step 4: Run them and watch them pass**

Expected: 7 tests pass. If `testTheNodeCapStopsTheWalkAndIsReported` returns 5,001 nodes, the cap is being applied after the append rather than before — fix the auditor, not the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/AccessibilityAudit Tests/ScytherTests/Features/AccessibilityAuditorWalkTests.swift
git commit -m "Walk the accessibility tree, and stop before it can hang the app"
```

---

### Task 3: The label and touch-target checks

**Files:**
- Modify: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditor.swift`
- Modify: `Scripts/localization/strings/AccessibilityAudit.json`
- Test: `Tests/ScytherTests/Features/AccessibilityAuditorChecksTests.swift`

**Interfaces:**
- Consumes: `collect(root:)`, `AccessibilityFinding`, `AccessibilityCheck`.
- Produces: `AccessibilityAuditor.Result` (`findings: [AccessibilityFinding]`, `didHitLimit: Bool`, `checksRun: Set<AccessibilityCheck>`), and `audit(root:checks:sampler:)` where `sampler` is `nil` for now and typed in Task 4.

Reuse the `Node` double from Task 2 by copying it into this file — the two suites are read separately and neither should reach into the other.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/AccessibilityAuditorChecksTests.swift
// (Copy the `Node` double from AccessibilityAuditorWalkTests.swift.)

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
```

- [ ] **Step 2: Run them and watch them fail**

Expected: compile failure — `audit(root:checks:sampler:)` does not exist.

- [ ] **Step 3: Implement the checks**

Add to `AccessibilityAuditor`:

```swift
    /// What one pass found.
    struct Result: Sendable {
        /// Every defect, in tree order.
        let findings: [AccessibilityFinding]

        /// Whether a cap stopped the walk. A partial result that does not say so is a lie.
        let didHitLimit: Bool

        /// Which checks actually ran, so an empty report can say what was looked at.
        let checksRun: Set<AccessibilityCheck>
    }

    /// The traits that mark an element a user is meant to name and reach.
    private static let interactiveTraits: UIAccessibilityTraits = [.button, .link, .adjustable]

    /// The traits that mark an element a user is meant to be able to name.
    private static let nameableTraits: UIAccessibilityTraits =
        [.button, .link, .image, .searchField, .adjustable, .keyboardKey]

    /// Apple's minimum comfortable target, in points.
    private static let minimumTargetSide: CGFloat = 44

    /// Below this, a target is not slightly short — it is a miss.
    private static let seriouslySmallSide: CGFloat = 32

    /// Audits a tree.
    ///
    /// - Parameters:
    ///   - root: The node to walk from.
    ///   - checks: The checks to run. One that is not named here is not run at all.
    ///   - sampler: How pixels are read for the contrast check, or `nil` when contrast is not
    ///     being run.
    /// - Returns: The findings, whether the walk was truncated, and which checks ran.
    func audit(root: AuditNode,
               checks: Set<AccessibilityCheck>,
               sampler: ContrastSampling?) -> Result {
        let walked = collect(root: root)
        var findings: [AccessibilityFinding] = []

        for node in walked.nodes {
            if checks.contains(.missingLabel), let finding = missingLabelFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.touchTarget), let finding = touchTargetFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.contrast), let sampler,
               let finding = contrastFinding(for: node, sampler: sampler) {
                findings.append(finding)
            }
        }

        return Result(findings: findings, didHitLimit: walked.didHitLimit, checksRun: checks)
    }

    /// The finding for an element VoiceOver could not name, if there is one.
    ///
    /// - Parameter node: The element to check.
    /// - Returns: The finding, or `nil` when the element is named or exempt.
    private func missingLabelFinding(for node: AuditNode) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.nameableTraits).isEmpty else { return nil }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed?.isEmpty ?? true else { return nil }

        return AccessibilityFinding(
            check: .missingLabel,
            severity: .error,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("VoiceOver reads this element with no name.")
        )
    }

    /// The finding for a target smaller than a finger, if there is one.
    ///
    /// - Parameter node: The element to check.
    /// - Returns: The finding, or `nil` when the target is big enough or is not a target.
    private func touchTargetFinding(for node: AuditNode) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.interactiveTraits).isEmpty else { return nil }
        let size = node.frameInWindow.size
        guard size.width < Self.minimumTargetSide || size.height < Self.minimumTargetSide else {
            return nil
        }

        let shortest = min(size.width, size.height)
        return AccessibilityFinding(
            check: .touchTarget,
            severity: shortest < Self.seriouslySmallSide ? .error : .warning,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("\(Self.points(size.width)) × \(Self.points(size.height))pt, under the 44 × 44pt minimum.")
        )
    }

    /// What to call an element in the report.
    ///
    /// An element with no label is named by what it is and where it is, because the finding that
    /// says "this has nothing to call it" cannot then have nothing to call it.
    ///
    /// - Parameter node: The element to name.
    /// - Returns: Its label, or its type and origin.
    private static func name(for node: AuditNode) -> String {
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        let origin = node.frameInWindow.origin
        return localized("\(node.typeName) at \(points(origin.x)), \(points(origin.y))")
    }

    /// A measurement, to one decimal place.
    ///
    /// - Parameter value: The value in points.
    /// - Returns: The formatted number.
    private static func points(_ value: CGFloat) -> String {
        String(format: "%.1f", value) // scyther:unlocalised a number, formatted
    }
```

Add the three new keys to the localisation fragment in all twelve languages and rebuild the catalogue. The touch-target and element-name strings are single keys with interpolations, so their word order can change per language.

- [ ] **Step 4: Run them and watch them pass**

Expected: 10 tests pass, plus Task 2's 7.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/AccessibilityAudit Tests/ScytherTests/Features/AccessibilityAuditorChecksTests.swift Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Report elements with no name and targets under 44pt"
```

---

### Task 4: The contrast check

**Files:**
- Create: `Sources/Scyther/Features/AccessibilityAudit/ContrastAnalyser.swift`
- Modify: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditor.swift`
- Modify: `Scripts/localization/strings/AccessibilityAudit.json`
- Test: `Tests/ScytherTests/Features/ContrastAnalyserTests.swift`

**Interfaces:**
- Produces: `RGB(red:green:blue:)` (each `0...1`), `ContrastSampling` (`@MainActor func samples(in frame: CGRect) -> [RGB]`), `ContrastMeasurement(ratio:foreground:background:)`, `ContrastAnalyser.luminance(_:)`, `ContrastAnalyser.measure(pixels:)`.
- Consumes: `AccessibilityAuditor.audit(root:checks:sampler:)` from Task 3, which now uses the sampler.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/ContrastAnalyserTests.swift
@testable import Scyther
import XCTest

final class ContrastAnalyserTests: XCTestCase {

    private let black = RGB(red: 0, green: 0, blue: 0)
    private let white = RGB(red: 1, green: 1, blue: 1)

    /// The two anchors of the WCAG scale.
    func testBlackOnWhiteIsTwentyOneToOne() {
        let pixels = Array(repeating: white, count: 90) + Array(repeating: black, count: 10)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertEqual(measured?.ratio ?? 0, 21, accuracy: 0.05)
    }

    func testOneColourHasNoRatioToReport() {
        XCTAssertNil(ContrastAnalyser.measure(pixels: Array(repeating: white, count: 100)))
    }

    func testNoPixelsHaveNoRatioToReport() {
        XCTAssertNil(ContrastAnalyser.measure(pixels: []))
    }

    /// The larger group is the background, whichever way round the colours are.
    func testTheMajorityColourIsTheBackground() {
        let pixels = Array(repeating: black, count: 95) + Array(repeating: white, count: 5)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertEqual(measured?.background.red ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(measured?.foreground.red ?? 0, 1, accuracy: 0.01)
    }

    /// Mid grey on white fails AA; the check has to be able to say so.
    func testGreyOnWhiteFallsBelowTheAAThreshold() {
        let grey = RGB(red: 0.6, green: 0.6, blue: 0.6)
        let pixels = Array(repeating: white, count: 80) + Array(repeating: grey, count: 20)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertLessThan(measured?.ratio ?? 99, 4.5)
    }

    /// The WCAG relative-luminance formula, at both ends.
    func testLuminanceMatchesTheWCAGFormula() {
        XCTAssertEqual(ContrastAnalyser.luminance(black), 0, accuracy: 0.0001)
        XCTAssertEqual(ContrastAnalyser.luminance(white), 1, accuracy: 0.0001)
    }
}
```

And, in `AccessibilityAuditorChecksTests.swift`, a check that the auditor uses the sampler:

```swift
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
        let midGrey = RGB(red: 0.45, green: 0.45, blue: 0.45)
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
```

Verify the mid-grey values above produce ratios that straddle 3:1 and 4.5:1 when you run the test; if they do not, adjust the grey in the test — not the thresholds.

- [ ] **Step 2: Run them and watch them fail**

Expected: compile failure — `ContrastAnalyser` does not exist.

- [ ] **Step 3: Write the analyser**

```swift
// ContrastAnalyser.swift
import CoreGraphics
import Foundation

/// One sampled pixel, in extended-range-free sRGB components from `0` to `1`.
struct RGB: Equatable, Sendable {
    /// The red component.
    let red: Double
    /// The green component.
    let green: Double
    /// The blue component.
    let blue: Double
}

/// Where the contrast check gets its pixels.
///
/// A protocol rather than a concrete snapshot so the maths can be tested against known bitmaps —
/// black on white, grey on grey, a gradient — with no window and no rendering.
@MainActor
protocol ContrastSampling {
    /// The pixels drawn inside `frame`, already downsampled.
    ///
    /// - Parameter frame: The region in window coordinates.
    /// - Returns: The pixels, or an empty array when the region cannot be read.
    func samples(in frame: CGRect) -> [RGB]
}

/// What one measurement found.
struct ContrastMeasurement: Equatable, Sendable {
    /// The WCAG contrast ratio, from 1 to 21.
    let ratio: Double
    /// The mean colour of the smaller group — the ink.
    let foreground: RGB
    /// The mean colour of the larger group — the page.
    let background: RGB
}

/// Turns pixels into a contrast ratio.
///
/// Deliberately naive about what it is looking at: it splits the pixels into a light group and a
/// dark group and compares their means. That is right for text on a flat background, which is
/// what it is pointed at, and approximate for anything else — which is why every finding it
/// produces is a warning that says it is an estimate.
enum ContrastAnalyser {
    /// WCAG's relative luminance.
    ///
    /// - Parameter colour: The colour to measure.
    /// - Returns: Its luminance, `0` for black and `1` for white.
    static func luminance(_ colour: RGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red)
            + 0.7152 * linear(colour.green)
            + 0.0722 * linear(colour.blue)
    }

    /// The ratio between two luminances, lighter over darker.
    ///
    /// - Parameters:
    ///   - first: One luminance.
    ///   - second: The other.
    /// - Returns: The ratio, from 1 to 21.
    static func ratio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Measures a region's contrast.
    ///
    /// Splits the pixels at the midpoint between the darkest and lightest luminance present, calls
    /// the larger group the background and the smaller the foreground, and compares their mean
    /// colours.
    ///
    /// - Parameter pixels: The region's pixels.
    /// - Returns: The measurement, or `nil` when there are no pixels or they are all one colour —
    ///   in which case there is no contrast to report rather than a contrast of 1.
    static func measure(pixels: [RGB]) -> ContrastMeasurement? {
        guard !pixels.isEmpty else { return nil }

        let luminances = pixels.map(luminance)
        guard let darkest = luminances.min(), let lightest = luminances.max(),
              lightest - darkest > 0.005 else { return nil }

        let midpoint = (darkest + lightest) / 2
        var dark: [RGB] = []
        var light: [RGB] = []
        for (pixel, value) in zip(pixels, luminances) {
            if value < midpoint { dark.append(pixel) } else { light.append(pixel) }
        }
        guard !dark.isEmpty, !light.isEmpty else { return nil }

        let background = dark.count >= light.count ? mean(dark) : mean(light)
        let foreground = dark.count >= light.count ? mean(light) : mean(dark)

        return ContrastMeasurement(ratio: ratio(luminance(foreground), luminance(background)),
                                   foreground: foreground,
                                   background: background)
    }

    /// The mean of a group of pixels.
    ///
    /// - Parameter pixels: The group. Must not be empty.
    /// - Returns: Their average colour.
    private static func mean(_ pixels: [RGB]) -> RGB {
        let count = Double(pixels.count)
        return RGB(red: pixels.reduce(0) { $0 + $1.red } / count,
                   green: pixels.reduce(0) { $0 + $1.green } / count,
                   blue: pixels.reduce(0) { $0 + $1.blue } / count)
    }
}

extension RGB {
    /// The colour as `#RRGGBB`, for a finding to quote.
    var hexDescription: String {
        String(format: "#%02X%02X%02X", // scyther:unlocalised a hex colour
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }
}
```

- [ ] **Step 4: Wire it into the auditor**

```swift
    /// The traits that mark an element that draws text worth measuring.
    private static let textTraits: UIAccessibilityTraits = [.staticText, .button]

    /// The height at which text is treated as large, and held to the lower threshold.
    ///
    /// WCAG's "large" is a point size, which cannot be read off an accessibility element. The
    /// element's height is the closest an outside observer gets, and it is stated as an estimate
    /// rather than dressed up as the real rule.
    private static let largeTextHeight: CGFloat = 24

    /// The finding for text too close in colour to what is behind it, if there is one.
    ///
    /// - Parameters:
    ///   - node: The element to measure.
    ///   - sampler: Where the pixels come from.
    /// - Returns: The finding, or `nil` when the element is not text, cannot be read, or passes.
    private func contrastFinding(for node: AuditNode, sampler: ContrastSampling) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.textTraits).isEmpty else { return nil }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }

        guard let measured = ContrastAnalyser.measure(pixels: sampler.samples(in: node.frameInWindow)) else {
            return nil
        }

        let threshold = node.frameInWindow.height >= Self.largeTextHeight ? 3.0 : 4.5
        guard measured.ratio < threshold else { return nil }

        return AccessibilityFinding(
            check: .contrast,
            severity: .warning,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("About \(Self.ratio(measured.ratio)):1, under \(Self.ratio(threshold)):1. Estimated from \(measured.foreground.hexDescription) on \(measured.background.hexDescription).")
        )
    }

    /// A ratio, to one decimal place.
    ///
    /// - Parameter value: The ratio.
    /// - Returns: The formatted number.
    private static func ratio(_ value: Double) -> String {
        String(format: "%.1f", value) // scyther:unlocalised a number, formatted
    }
```

Add the new key to the fragment in all twelve languages and rebuild the catalogue.

- [ ] **Step 5: Run them and watch them pass**

Expected: 6 analyser tests plus 3 new auditor tests pass, and Tasks 2–3 stay green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/AccessibilityAudit Tests/ScytherTests/Features Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Estimate text contrast from what was actually drawn"
```

---

### Task 5: Adapting the real tree, and sampling the real window

**Files:**
- Modify: `Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift`
- Create: `Sources/Scyther/Features/AccessibilityAudit/WindowContrastSampler.swift`
- Test: `Tests/ScytherTests/Features/AuditNodeAdapterTests.swift`

**Interfaces:**
- Produces: `UIView: AuditNode` conformance; `AccessibilityElementNode` (wrapping an `NSObject` accessibility element); `WindowContrastSampler(window:)` conforming to `ContrastSampling`.
- Consumes: everything from Tasks 2–4.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/AuditNodeAdapterTests.swift
@testable import Scyther
import UIKit
import XCTest

@MainActor
final class AuditNodeAdapterTests: XCTestCase {

    func testAViewReportsItsAccessibilityPropertiesThroughTheProtocol() {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        button.accessibilityLabel = "Close"
        button.isAccessibilityElement = true

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

    /// The sampler reads back what was drawn.
    func testTheSamplerReadsTheColourOfWhatWasDrawn() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.backgroundColor = .black
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.layoutIfNeeded()

        let sampler = WindowContrastSampler(window: window)
        let pixels = sampler.samples(in: CGRect(x: 10, y: 10, width: 20, height: 20))

        XCTAssertFalse(pixels.isEmpty)
        XCTAssertEqual(pixels.first?.red ?? 1, 0, accuracy: 0.05)
    }

    func testTheSamplerReturnsNothingForARegionOutsideTheWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let sampler = WindowContrastSampler(window: window)
        XCTAssertTrue(sampler.samples(in: CGRect(x: 500, y: 500, width: 10, height: 10)).isEmpty)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Expected: compile failure — `UIView` does not conform to `AuditNode`.

- [ ] **Step 3: Write the adapters**

Append to `AuditNode.swift` a `UIView: AuditNode` conformance and an `AccessibilityElementNode` struct wrapping an `NSObject`:

- `isAccessibilityElementNode` → `isAccessibilityElement`.
- `accessibilityLabelText` → `accessibilityLabel`.
- `traits` → `accessibilityTraits`.
- `frameInWindow` → for a view, `superview?.convert(frame, to: nil) ?? frame`; for an element, `accessibilityFrame`, which is already in screen coordinates.
- `isVisible` → `!isHidden && alpha > 0.01`.
- `isScytherOwned` → `self is TopLevelViewsWrapper || self is TopLevelView || String(describing: type(of: self)).hasPrefix("Scyther")`, or any ancestor that is.
- `typeName` → `String(describing: type(of: self))`.
- `children` → `accessibilityElements` mapped to `AccessibilityElementNode` when non-empty; otherwise `accessibilityElementCount() > 0` mapped through `accessibilityElement(at:)`; otherwise `subviews`.

Write `WindowContrastSampler` to take one `UIGraphicsImageRenderer` snapshot of the window in `init`, keep the `CGImage`, and in `samples(in:)` crop to the frame (in image pixels, scaled by the window's `contentScaleFactor`), downsample to at most 64 × 64 by striding, and return `RGB` values. Return `[]` when the crop is empty or outside the image.

- [ ] **Step 4: Run them and watch them pass**

Expected: 7 tests pass. `testTheSamplerReadsTheColourOfWhatWasDrawn` needs the window on screen; if the snapshot comes back empty in the test host, render with `window.layer.render(in:)` rather than `drawHierarchy(afterScreenUpdates:)` — note in the code why.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/AccessibilityAudit Tests/ScytherTests/Features/AuditNodeAdapterTests.swift
git commit -m "Adapt the real accessibility tree and window to the auditor"
```

---

### Task 6: Settings, and the overlay on screen

**Files:**
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAudit.swift`
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditOverlayView.swift`
- Modify: `Sources/Scyther/Core/InterfaceToolkit.swift`
- Test: `Tests/ScytherTests/Features/AccessibilityAuditSettingsTests.swift`

**Interfaces:**
- Produces: `AccessibilityAudit.instance`; `init(defaults: UserDefaults = .scyther)`; `nonisolated var liveEnabled: Bool`; `nonisolated func isEnabled(_ check: AccessibilityCheck) -> Bool`; `nonisolated func setEnabled(_ check: AccessibilityCheck, to isEnabled: Bool)`; `var enabledChecks: Set<AccessibilityCheck>`; `@MainActor func auditKeyWindow() -> AccessibilityAuditor.Result`; `AccessibilityAuditOverlayView` with `var findings: [AccessibilityFinding]`, `var onOpenReport: (() -> Void)?`, `func flash(_ finding: AccessibilityFinding)`.
- Consumes: Tasks 1–5.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/AccessibilityAuditSettingsTests.swift
@testable import Scyther
import XCTest

@MainActor
final class AccessibilityAuditSettingsTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AccessibilityAuditSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testEveryCheckIsOnByDefault() {
        let audit = AccessibilityAudit(defaults: defaults)
        XCTAssertEqual(audit.enabledChecks, Set(AccessibilityCheck.allCases))
    }

    func testLiveModeIsOffByDefault() {
        XCTAssertFalse(AccessibilityAudit(defaults: defaults).liveEnabled)
    }

    func testSwitchingACheckOffLeavesTheOthersOn() {
        let audit = AccessibilityAudit(defaults: defaults)
        audit.setEnabled(.contrast, to: false)

        XCTAssertEqual(audit.enabledChecks, [.missingLabel, .touchTarget])
        XCTAssertFalse(audit.isEnabled(.contrast))
    }

    func testSettingsSurviveANewInstance() {
        AccessibilityAudit(defaults: defaults).setEnabled(.touchTarget, to: false)
        XCTAssertFalse(AccessibilityAudit(defaults: defaults).isEnabled(.touchTarget))
    }

    /// Switching every check off is not the same as switching the audit off, and the audit must
    /// not pretend a screen passed when nothing was run.
    func testWithNoChecksOnNothingIsRun() {
        let audit = AccessibilityAudit(defaults: defaults)
        AccessibilityCheck.allCases.forEach { audit.setEnabled($0, to: false) }
        XCTAssertTrue(audit.enabledChecks.isEmpty)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

- [ ] **Step 3: Write the singleton and the overlay**

`AccessibilityAudit` follows `GridOverlay` exactly: `static let instance`, `nonisolated` computed properties over `UserDefaults`, and a `defaults`-injecting initialiser so tests get a throwaway suite. Setting `liveEnabled` calls `InterfaceToolkit.instance.showAccessibilityAudit()` from a `Task { @MainActor in … }`, as `GridOverlay.enabled` does.

`auditKeyWindow()` resolves the key window, builds a `WindowContrastSampler` for it when `.contrast` is on, and returns `AccessibilityAuditor().audit(root: window, checks: enabledChecks, sampler: sampler)`. It returns an empty result when `AppEnvironment.isTestCase` — nothing walks a window during a test run.

`AccessibilityAuditOverlayView: TopLevelView` draws one rounded stroke per finding (red `.systemRed` for errors, amber `.systemOrange` for warnings, 2pt, 4pt corner radius) and a capsule pill at the bottom centre reading the count, which calls `onOpenReport`. `updateFrame()` sets its frame to the superview's bounds. Boxes are drawn in `draw(_:)`; the pill is a real `UIButton` subview so it is tappable. Everything except the pill has `isUserInteractionEnabled = false`. `flash(_:)` animates one box's stroke to full opacity and back twice over 0.6s.

`InterfaceToolkit` gains `accessibilityAuditView`, `setupAccessibilityAudit()` and `showAccessibilityAudit()`, mirroring the grid overlay, plus the debounced re-audit: a `Timer`-free coalescing hop (`DispatchWorkItem` cancelled and rescheduled 0.5s out) triggered from `updateFrame()` and `UIWindow.didBecomeVisibleNotification`.

- [ ] **Step 4: Run them and watch them pass**

- [ ] **Step 5: Build and look at it**

```bash
xcodebuild build -project Example/ScytherExample.xcodeproj -scheme ScytherExample -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Install, launch, switch live mode on through the settings screen from Task 7, and take a screenshot. Boxes must sit over the app, the pill must be tappable, and the app underneath must still scroll.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther Tests/ScytherTests/Features/AccessibilityAuditSettingsTests.swift
git commit -m "Draw the audit over the running app"
```

---

### Task 7: The report screen

**Files:**
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditView.swift`
- Create: `Sources/Scyther/Features/AccessibilityAudit/AccessibilityAuditViewModel.swift`
- Modify: `Scripts/localization/strings/AccessibilityAudit.json`
- Test: `Tests/ScytherTests/Features/AccessibilityAuditViewModelTests.swift`

**Interfaces:**
- Produces: `AccessibilityAuditViewModel(run:)` where `run: @escaping @MainActor () -> AccessibilityAuditor.Result` — the audit is injected as a closure so the view model is testable with no window; the screen passes `{ AccessibilityAudit.instance.auditKeyWindow() }`. Exposes `@Published private(set) var groups: [AccessibilityAuditViewModel.Group]`, `@Published private(set) var didHitLimit: Bool`, `@Published private(set) var skippedChecks: [AccessibilityCheck]`, `func load()`, `func rerun()`, `var onFlash: ((AccessibilityFinding) -> Void)?`, `func flash(_ finding: AccessibilityFinding)`; and `struct Group: Identifiable { let check: AccessibilityCheck; let findings: [AccessibilityFinding] }`.
- Consumes: `AccessibilityAudit`, `AccessibilityFinding`, `AccessibilityAuditor.Result`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ScytherTests/Features/AccessibilityAuditViewModelTests.swift
@testable import Scyther
import XCTest

@MainActor
final class AccessibilityAuditViewModelTests: XCTestCase {

    private func finding(_ check: AccessibilityCheck,
                         _ severity: AccessibilitySeverity,
                         _ name: String) -> AccessibilityFinding {
        AccessibilityFinding(check: check, severity: severity,
                             frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                             elementName: name, detail: "detail")
    }

    private func result(_ findings: [AccessibilityFinding],
                        didHitLimit: Bool = false,
                        checksRun: Set<AccessibilityCheck> = Set(AccessibilityCheck.allCases))
    -> AccessibilityAuditor.Result {
        AccessibilityAuditor.Result(findings: findings, didHitLimit: didHitLimit, checksRun: checksRun)
    }

    /// Findings are grouped by check, errors first inside each group, so the report leads with
    /// what is broken rather than with whatever the walk happened to reach first.
    func testFindingsAreGroupedByCheckWithErrorsFirst() {
        let findings = [
            finding(.touchTarget, .warning, "warn"),
            finding(.missingLabel, .error, "label"),
            finding(.touchTarget, .error, "error")
        ]
        let viewModel = AccessibilityAuditViewModel { self.result(findings) }
        viewModel.load()

        XCTAssertEqual(viewModel.groups.map(\.check), [.missingLabel, .touchTarget])
        XCTAssertEqual(viewModel.groups.last?.findings.map(\.elementName), ["error", "warn"])
    }

    /// The report is frozen. Findings that move while they are being read are useless, so a new
    /// pass happens only when it is asked for.
    func testTheReportDoesNotChangeUntilItIsRerun() {
        var passes = 0
        let viewModel = AccessibilityAuditViewModel {
            passes += 1
            return self.result([self.finding(.missingLabel, .error, "pass \(passes)")])
        }
        viewModel.load()
        viewModel.load()

        XCTAssertEqual(passes, 1)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 1")

        viewModel.rerun()

        XCTAssertEqual(passes, 2)
        XCTAssertEqual(viewModel.groups.first?.findings.first?.elementName, "pass 2")
    }

    /// "No findings" and "nothing was looked at" must not read the same, so the empty state is
    /// handed the checks that did not run.
    func testTheEmptyStateNamesTheChecksThatWereSwitchedOff() {
        let viewModel = AccessibilityAuditViewModel {
            self.result([], checksRun: [.missingLabel])
        }
        viewModel.load()

        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(Set(viewModel.skippedChecks), [.touchTarget, .contrast])
    }

    func testNothingIsReportedAsSkippedWhenEveryCheckRan() {
        let viewModel = AccessibilityAuditViewModel { self.result([]) }
        viewModel.load()

        XCTAssertTrue(viewModel.skippedChecks.isEmpty)
    }

    /// A truncated walk says so rather than presenting a partial result as complete.
    func testATruncatedWalkIsReported() {
        let viewModel = AccessibilityAuditViewModel {
            self.result([self.finding(.contrast, .warning, "text")], didHitLimit: true)
        }
        viewModel.load()

        XCTAssertTrue(viewModel.didHitLimit)
    }

    /// Tapping a row asks the overlay behind to flash that element's box.
    func testFlashingARowReachesTheOverlay() {
        let viewModel = AccessibilityAuditViewModel { self.result([]) }
        var flashed: AccessibilityFinding?
        viewModel.onFlash = { flashed = $0 }

        let target = finding(.contrast, .warning, "text")
        viewModel.flash(target)

        XCTAssertEqual(flashed?.id, target.id)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

- [ ] **Step 3: Write the view model and the screen**

The screen is a `List`: a section per check, each row a title-over-subtitle `VStack` (element name over detail) in the two-line shape `MenuView.searchResultLabel` uses, with a severity dot; a footer on the contrast section stating that its ratios are estimates; a **Re-run** button in the toolbar; `ContentUnavailableView` (behind `#available(iOS 17.0, *)`, with the hand-built fallback the other screens use) for an empty result, naming any skipped check; and a banner row when `didHitLimit` is true. Tapping a row calls `flash(_:)`.

- [ ] **Step 4: Run them and watch them pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther Tests Scripts Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Read the audit's findings in a frozen report"
```

---

### Task 8: The menu row, and the documentation

**Files:**
- Modify: `Sources/Scyther/Features/Menu/MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift`
- Modify: `README.md`, `Sources/Scyther/Scyther.docc/` (a new `AccessibilityAuditing.md` article, referenced from the toolkit's article index)
- Test: `Tests/ScytherTests/Features/MenuSectionTests.swift` (existing suite)

**Interfaces:**
- Consumes: `AccessibilityAuditView`.

- [ ] **Step 1: Add the row**

`MenuItem.accessibilityAudit`, in `allStaticCases` and in the **UI/UX** section after `.touchVisualiser`; `id` `"accessibilityAudit"`; title `localized("Accessibility Audit")`; icon `"figure.stand"`; destination `AccessibilityAuditView()`; a `navigationRow(for:)` case; search keywords `["a11y", "voiceover", "contrast", "labels", "touch targets"]` and sub-page entries for the three check names and the live toggle.

- [ ] **Step 2: Run the menu suite and watch it stay green**

The existing `MenuSectionTests` assert every item appears in exactly one section and that ids are unique; a new row that breaks either is a mistake in this step.

- [ ] **Step 3: Document it**

A README section under UI/UX describing the three checks, their thresholds, the live overlay and the report, and — plainly — that contrast is an estimate sampled from what was drawn. A DocC article covering the same ground with the reasoning, in the shape of `NetworkDebugging.md`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Scyther README.md
git commit -m "Reach the accessibility audit from the menu, and document it"
```

---

### Task 9: A screen with real defects, and verification on device

**Files:**
- Modify: `Example/ScytherExample/Sources/ContentView.swift`

- [ ] **Step 1: Add the defects**

A section in the example app carrying, deliberately and labelled as such: an icon-only button with no accessibility label, a 30 × 30pt tappable button, and a `Text` in `Color(white: 0.72)` on the default background.

- [ ] **Step 2: Verify by hand**

Build, install, launch. Switch live mode on. Confirm: three boxes appear over the three defects and nowhere else; the pill reads `3`; tapping it opens the report; the report groups them under the right checks; tapping a row flashes the right box; switching contrast off and re-running drops that finding and the empty state names it; the app underneath still scrolls and taps through.

Take a screenshot of the overlay and one of the report.

- [ ] **Step 3: Run the whole suite**

```bash
xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: every test passes, including the 1,273 that were passing before this plan started.

- [ ] **Step 4: Commit**

```bash
git add Example
git commit -m "Give the example app defects worth auditing"
```
