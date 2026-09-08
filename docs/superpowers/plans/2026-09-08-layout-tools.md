# Layout Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two layout-inspection tools — a ruler that measures between two points snapping to real view edges, and a static overlay drawing the key window's safe-area insets and layout margins.

**Architecture:** Two `TopLevelView` overlays following the established `GridOverlayView` pattern, installed by `InterfaceToolkit` and reached from the menu's UI/UX section. All arithmetic that has a right answer lives in two pure types — `LayoutRulerGeometry` and `ViewProbe` — because an overlay's drawing cannot be inspected by a test and a drag gesture cannot be driven by one.

**Tech Stack:** Swift 6 language mode, complete strict concurrency, UIKit overlays, SwiftUI menu rows, XCTest, SPM (iOS-only).

**Spec:** `docs/superpowers/specs/2026-09-08-layout-tools-design.md`

## Global Constraints

- iOS 16 deployment floor. `ContentUnavailableView` is iOS 17 — guard any use with `#available(iOS 17.0, *)`. `onChange(of:)` takes the single-parameter closure form.
- Swift 6 complete strict concurrency. `@MainActor` on anything touching UIKit or SwiftUI; value types crossing actors conform to `Sendable`.
- Build and test for the booted iOS simulator only. `swift build` does not work — this is an iOS-only library requiring UIKit.
  Test command: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- MVVM + Repository. Separate view model files. One responsibility per file.
- **Use the stock SwiftUI component wherever one serves the need** (`Toggle`, `Picker`, `NavigationLink`, `LabeledContent`). Never hand-roll a row or control SwiftUI already provides.
- Every user-facing string goes through `localized(_:)`, with the key added to a new `Scripts/localization/strings/LayoutTools.json` fragment in all twelve languages (fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar), then `python3 Scripts/localization/build_catalog.py` run and the regenerated catalogue committed.
- DocC documentation on every member, including private ones, explaining *why* — not restating the signature.
- Update the README to reflect user-visible changes.
- **No `Claude-Session:` line, Claude mention, or co-author trailer in any commit message.** Check `git log -1 --format=%B` before reporting a task done.
- Both tools are off inside an XCTest process and on App Store builds, through the existing `AppEnvironment` checks.
- **`ViewProbe` must never read an accessibility property.** Asking a `UIView` for its accessibility children forces UIAccessibility to compute the subtree recursively, which hung the app in 4.3.0. The probe runs per touch-move — a far hotter path than the audit ever was.

---

### Task 1: The ruler's geometry

**Files:**
- Create: `Sources/Scyther/Features/LayoutTools/LayoutRulerGeometry.swift`
- Test: `Tests/ScytherTests/Features/LayoutRulerGeometryTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum LayoutRulerGeometry`
  - `enum LayoutRulerGeometry.Edge: String, Sendable` with cases `top`, `bottom`, `left`, `right`
  - `static func snapped(_ point: CGPoint, to rect: CGRect) -> (point: CGPoint, edge: Edge)`
  - `static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat`
  - `static func labelOrigin(midpoint: CGPoint, labelSize: CGSize, in bounds: CGSize) -> CGPoint`
  - `static let minimumMeasurableDistance: CGFloat = 1`

Edges are named `top`/`bottom`/`left`/`right`, not `leading`/`trailing`, deliberately: this is a physical measurement on a screen, and under the right-to-left mode Scyther itself ships, "leading" would name a different side than the one the developer's finger is next to.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/LayoutRulerGeometryTests.swift`:

```swift
//
//  LayoutRulerGeometryTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// The ruler draws what this returns and decides nothing itself, so these tests are the only
/// place the measurement's correctness is actually established — a drag cannot be driven by a
/// test in this project, and an overlay's drawing cannot be inspected by one.
final class LayoutRulerGeometryTests: XCTestCase {

    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: - Snapping

    func testAPointAboveARectSnapsToItsTopEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 40), to: rect)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 100))
    }

    func testAPointBelowARectSnapsToItsBottomEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 260), to: rect)
        XCTAssertEqual(result.edge, .bottom)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 200))
    }

    func testAPointLeftOfARectSnapsToItsLeftEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 20, y: 150), to: rect)
        XCTAssertEqual(result.edge, .left)
        XCTAssertEqual(result.point, CGPoint(x: 100, y: 150))
    }

    func testAPointRightOfARectSnapsToItsRightEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 400, y: 150), to: rect)
        XCTAssertEqual(result.edge, .right)
        XCTAssertEqual(result.point, CGPoint(x: 300, y: 150))
    }

    /// A finger inside a view still means an edge — you are measuring to the view, not to your
    /// fingertip — and the nearest one is the honest answer.
    func testAPointInsideARectSnapsToItsNearestEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 200, y: 115), to: rect)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.point, CGPoint(x: 200, y: 100))
    }

    /// The projection is clamped to the edge's own extent, so a point off the corner lands on the
    /// edge rather than on the infinite line through it.
    func testAPointOffACornerIsClampedOntoTheEdge() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 500, y: 20), to: rect)
        XCTAssertEqual(result.point.x, 300, accuracy: 0.001)
        XCTAssertEqual(result.point.y, 100, accuracy: 0.001)
    }

    func testAnEmptyRectSnapsToItsOwnOrigin() {
        let result = LayoutRulerGeometry.snapped(CGPoint(x: 50, y: 50), to: .zero)
        XCTAssertEqual(result.point, .zero)
    }

    // MARK: - Distance

    func testDistanceIsTheStraightLineBetweenTwoPoints() {
        let d = LayoutRulerGeometry.distance(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3, y: 4))
        XCTAssertEqual(d, 5, accuracy: 0.001)
    }

    func testDistanceIsZeroForTheSamePoint() {
        let d = LayoutRulerGeometry.distance(from: CGPoint(x: 7, y: 7), to: CGPoint(x: 7, y: 7))
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    // MARK: - Label placement

    func testTheLabelSitsAboveTheMidpointWhenThereIsRoom() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 300),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertEqual(origin.x, 160, accuracy: 0.001, "centred on the midpoint")
        XCTAssertLessThan(origin.y, 300, "above it")
    }

    /// A measurement near the top of the screen must not push its own label off it.
    func testTheLabelIsPushedInsideWhenItWouldLeaveTheTop() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 200, y: 4),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    func testTheLabelIsPushedInsideWhenItWouldLeaveTheRight() {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: CGPoint(x: 396, y: 300),
                                                     labelSize: CGSize(width: 80, height: 20),
                                                     in: CGSize(width: 400, height: 800))
        XCTAssertLessThanOrEqual(origin.x + 80, 400.001)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/LayoutRulerGeometryTests`

Expected: FAIL. Because the type does not exist yet, these fail to **compile** rather than on assertions — say exactly that in your report, and do not describe it as an assertion failure.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/LayoutTools/LayoutRulerGeometry.swift`:

```swift
//
//  LayoutRulerGeometry.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import CoreGraphics
import Foundation

/// Every decision the ruler makes that has a right answer.
///
/// The overlay draws what this returns and decides nothing itself. That split is not tidiness:
/// an overlay's drawing cannot be inspected by a test and a drag cannot be driven by one, so
/// arithmetic left in the view is arithmetic nothing can check. This codebase has reached the
/// same conclusion three times — `WaterfallStripGeometry`, `WaterfallDetailGeometry`, and the
/// waterfall's scrub-direction check — and each time the fix was to move the maths here.
///
/// ## Topics
///
/// ### Snapping
/// - ``snapped(_:to:)``
/// - ``Edge``
///
/// ### Measuring
/// - ``distance(from:to:)``
/// - ``minimumMeasurableDistance``
///
/// ### Drawing
/// - ``labelOrigin(midpoint:labelSize:in:)``
enum LayoutRulerGeometry {

    /// Which side of a view a measurement attached to.
    ///
    /// Named for the screen, not for the layout direction. `leading` would be the wrong word
    /// here: Scyther ships a right-to-left mode that mirrors the whole app, and under it a
    /// developer's finger next to the left of a view would be told it had snapped to the
    /// trailing edge. A measurement is physical, so its vocabulary is physical.
    enum Edge: String, Sendable {
        case top, bottom, left, right
    }

    /// Below this, a drag is a tap and draws nothing.
    ///
    /// Without a floor, resting a finger produces a `0.0 pt` measurement that looks like a
    /// result rather than an accident.
    static let minimumMeasurableDistance: CGFloat = 1

    /// The point on `rect`'s nearest edge to `point`, and which edge that was.
    ///
    /// Nearest by perpendicular distance, with the projection clamped to the edge's own extent —
    /// so a point off a corner lands on the corner rather than on the infinite line through the
    /// edge, which would report a measurement to somewhere the view is not.
    ///
    /// A point *inside* the rect still snaps outward to an edge. Measuring to a fingertip inside
    /// a view answers nothing; the developer means the view.
    ///
    /// - Parameters:
    ///   - point: The point in the same space as `rect`.
    ///   - rect: The hit view's frame in that space.
    /// - Returns: The snapped point and the edge it belongs to. An empty rect returns its own
    ///   origin, which is the only honest answer for a view with no edges.
    static func snapped(_ point: CGPoint, to rect: CGRect) -> (point: CGPoint, edge: Edge) {
        guard !rect.isEmpty else { return (rect.origin, .top) }

        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)

        let candidates: [(point: CGPoint, edge: Edge)] = [
            (CGPoint(x: clampedX, y: rect.minY), .top),
            (CGPoint(x: clampedX, y: rect.maxY), .bottom),
            (CGPoint(x: rect.minX, y: clampedY), .left),
            (CGPoint(x: rect.maxX, y: clampedY), .right)
        ]

        return candidates.min { distance(from: point, to: $0.point) < distance(from: point, to: $1.point) }
            ?? (rect.origin, .top)
    }

    /// The straight-line distance between two points, in points.
    ///
    /// - Parameters:
    ///   - start: One end.
    ///   - end: The other.
    static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Where a label of `labelSize` sits so it reads near `midpoint` without leaving `bounds`.
    ///
    /// Above the midpoint by preference, because a label below a measurement tends to sit under
    /// the finger that made it. Pushed back inside on every edge, since a measurement taken near
    /// the top of the screen would otherwise put its own answer off it.
    ///
    /// - Parameters:
    ///   - midpoint: The middle of the drawn measurement.
    ///   - labelSize: The label's size.
    ///   - bounds: The overlay's size.
    /// - Returns: The label's origin.
    static func labelOrigin(midpoint: CGPoint, labelSize: CGSize, in bounds: CGSize) -> CGPoint {
        let gap: CGFloat = 8
        let x = min(max(0, midpoint.x - labelSize.width / 2), max(0, bounds.width - labelSize.width))
        let y = min(max(0, midpoint.y - labelSize.height - gap), max(0, bounds.height - labelSize.height))
        return CGPoint(x: x, y: y)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same `-only-testing:ScytherTests/LayoutRulerGeometryTests` command. Expected: PASS, all thirteen.

- [ ] **Step 5: Run the full suite**

Run the full test command from Global Constraints. Expected: no failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/LayoutTools/LayoutRulerGeometry.swift \
        Tests/ScytherTests/Features/LayoutRulerGeometryTests.swift
git commit -m "Add the layout ruler's geometry

Every decision the ruler makes that has a right answer, in a pure type. An
overlay's drawing cannot be inspected by a test and a drag cannot be driven by
one, so arithmetic left in the view is arithmetic nothing checks."
```

---

### Task 2: The view probe

**Files:**
- Create: `Sources/Scyther/Features/LayoutTools/ViewProbe.swift`
- Test: `Tests/ScytherTests/Features/ViewProbeTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `enum ViewProbe` with `@MainActor static func view(at point: CGPoint, in root: UIView) -> UIView?`

The probe takes a root `UIView` rather than a `UIWindow` so a test can hand it a plain view tree without a window. The ruler passes its window.

**Reusing the ownership rule.** `UIView` already conforms to `AuditNode` and therefore already answers `isScytherOwned` — a rule that is memoised by class and was rewritten once after a name-based version let the accessibility audit draw error boxes over Scyther's own close button. Read that property; do not write a second ownership test and do not move the existing one. A second answer would drift from the first, and moving it risks re-breaking the audit for no gain.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewProbeTests.swift`:

```swift
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
}

@MainActor
final class ViewProbeTests: XCTestCase {

    /// A root holding one child at a known frame.
    private func makeTree(childFrame: CGRect) -> (root: UIView, child: UIView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let child = UIView(frame: childFrame)
        root.addSubview(child)
        return (root, child)
    }

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

    func testTheFrontmostOfTwoOverlappingViewsWins() {
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

    /// The rule the accessibility audit's hang taught, kept honest by a spy rather than by intent.
    func testTheProbeNeverAsksAViewForItsAccessibilityChildren() {
        AccessibilitySpyView.wasAsked = false
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let spy = AccessibilitySpyView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(spy)

        _ = ViewProbe.view(at: CGPoint(x: 50, y: 50), in: root)

        XCTAssertFalse(AccessibilitySpyView.wasAsked,
                       "the probe runs per touch-move; forcing an accessibility subtree hung the app once already")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/ViewProbeTests`. Expected: compile failure — `ViewProbe` does not exist. Report it as a compile failure.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/LayoutTools/ViewProbe.swift`:

```swift
//
//  ViewProbe.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import UIKit

/// Finds the host view under a point, so the ruler can snap to something real.
///
/// Deliberately not `UIView.hitTest(_:with:)`. That method answers "which view would receive
/// this touch", which is a different question: it respects `isUserInteractionEnabled`, so it
/// skips the labels and image views a developer most wants to measure, and it has no notion of
/// Scyther's own interface being off-limits.
///
/// **This must never read an accessibility property.** Asking a `UIView` for its accessibility
/// children makes UIAccessibility compute that view's subtree recursively. Doing so across a
/// real hierarchy is quadratic and hung the app when the accessibility audit shipped — and the
/// audit ran once per navigation, where this runs once per touch-move.
@MainActor
enum ViewProbe {

    /// The deepest visible host view containing `point`.
    ///
    /// Front-to-back, deepest match wins: a developer pointing at a label means the label, not
    /// the stack that contains it.
    ///
    /// Skips any view that is hidden, fully transparent, or one of Scyther's own. Ownership is
    /// answered by ``AuditNode/isScytherOwned``, which `UIView` already conforms to — a rule that
    /// is memoised by class and was rewritten once after a name-based version let the audit draw
    /// over Scyther's own close button. Reading it here rather than writing a second test is what
    /// keeps the two from drifting apart.
    ///
    /// - Parameters:
    ///   - point: The point, in `root`'s coordinate space.
    ///   - root: The view to search. The ruler passes its window.
    /// - Returns: The deepest match, or `nil` when `point` is outside `root` or `root` is itself
    ///   skipped.
    static func view(at point: CGPoint, in root: UIView) -> UIView? {
        guard root.bounds.contains(point), isEligible(root) else { return nil }

        for subview in root.subviews.reversed() {
            let converted = root.convert(point, to: subview)
            if let deeper = view(at: converted, in: subview) { return deeper }
        }

        return root
    }

    /// Whether a view can be measured against at all.
    ///
    /// Separate from the walk so the rule reads as one thing rather than three conditions inside
    /// a loop, and so a reader can see immediately that none of it touches accessibility.
    ///
    /// - Parameter view: The view to test.
    private static func isEligible(_ view: UIView) -> Bool {
        !view.isHidden && view.alpha > 0.01 && !view.isScytherOwned
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run with `-only-testing:ScytherTests/ViewProbeTests`. Expected: PASS, all eight.

If `isScytherOwned` is not visible from this file, do **not** duplicate the rule — report it and stop. It is a protocol requirement on `AuditNode`, which `UIView` conforms to in `Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift`, and both files are in the same module.

- [ ] **Step 5: Run the full suite, then commit**

```bash
git add Sources/Scyther/Features/LayoutTools/ViewProbe.swift \
        Tests/ScytherTests/Features/ViewProbeTests.swift
git commit -m "Add the view probe

Finds the host view under a point, front to back, deepest match. Not hitTest:
that answers which view would receive a touch, which skips the labels a
developer most wants to measure. Reuses the audit's ownership rule rather than
writing a second one, and a spy test keeps it off the accessibility tree."
```

---

### Task 3: Layout Guides

**Files:**
- Create: `Sources/Scyther/Features/LayoutTools/LayoutGuides.swift`
- Create: `Sources/Scyther/Features/LayoutTools/LayoutGuidesView.swift`
- Create: `Scripts/localization/strings/LayoutTools.json`
- Modify: `Sources/Scyther/Core/InterfaceToolkit.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuItem.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuViewModel.swift`
- Test: `Tests/ScytherTests/Features/LayoutGuidesTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces:
  - `final class LayoutGuides` with `static let instance`, `internal nonisolated var enabled: Bool`, and `nonisolated static let EnabledDefaultsKey = "Scyther_layout_guides_enabled"`
  - `internal class LayoutGuidesView: TopLevelView`
  - `LayoutGuidesView.guideLines(safeArea: UIEdgeInsets, margins: UIEdgeInsets, in bounds: CGRect) -> [GuideLine]`, a **static** pure function
  - `struct GuideLine: Equatable, Sendable { let start: CGPoint; let end: CGPoint; let value: CGFloat; let kind: Kind }` with `enum Kind { case safeArea, margin }`
  - `InterfaceToolkit.setupLayoutGuides()` and `InterfaceToolkit.showLayoutGuides()`
  - `MenuItem.layoutGuides`

Read `Sources/Scyther/Features/GridOverlay/GridOverlay.swift` and `Sources/Scyther/Shared/Components/GridOverlayView.swift` first. `LayoutGuides` mirrors the first; `LayoutGuidesView` mirrors the second, including `updateFrame()` and `draw(_:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/LayoutGuidesTests.swift`:

```swift
//
//  LayoutGuidesTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class LayoutGuidesTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    func testASafeAreaLineIsDrawnForEachNonZeroInset() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            margins: .zero,
            in: bounds
        )
        let safeArea = lines.filter { $0.kind == .safeArea }
        XCTAssertEqual(safeArea.count, 2)
        XCTAssertEqual(Set(safeArea.map(\.value)), [59, 34])
    }

    /// A line labelled `0.0 pt` flush against the screen edge is noise, and on a device with no
    /// home indicator the bottom inset genuinely is zero.
    func testAZeroInsetIsNotDrawn() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    func testMarginsAreDrawnSeparatelyFromSafeAreas() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .margin }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    func testATopInsetLineSpansTheFullWidthAtItsOwnDepth() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        let line = try? XCTUnwrap(lines.first)
        XCTAssertEqual(line?.start, CGPoint(x: 0, y: 59))
        XCTAssertEqual(line?.end, CGPoint(x: 400, y: 59))
    }

    func testNothingIsDrawnWhenEveryInsetIsZero() {
        let lines = LayoutGuidesView.guideLines(safeArea: .zero, margins: .zero, in: bounds)
        XCTAssertTrue(lines.isEmpty)
    }

    // MARK: - Settings

    func testTheGuidesAreOffByDefault() {
        let suite = "LayoutGuidesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(defaults.bool(forKey: LayoutGuides.EnabledDefaultsKey),
                       "an overlay that is quietly on is an overlay the developer will blame the app for")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/LayoutGuidesTests`. Expected: compile failure. Say so plainly.

- [ ] **Step 3: Write `LayoutGuides`**

Create `Sources/Scyther/Features/LayoutTools/LayoutGuides.swift`, mirroring `GridOverlay`:

```swift
//
//  LayoutGuides.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import Foundation

/// Whether the safe-area and layout-margin overlay is showing.
///
/// Its own setting rather than part of the ruler, because these are guides you want while
/// *using* the app — scrolling, navigating, watching a layout misbehave. The ruler's overlay
/// takes touches, so tying the guides to it would show them only when the app cannot be driven.
///
/// Settings are persisted in `UserDefaults.scyther`, Scyther's private suite, as the other
/// overlays' are.
final class LayoutGuides {

    /// UserDefaults key for the enabled state.
    nonisolated static let EnabledDefaultsKey = "Scyther_layout_guides_enabled"

    private init() { }

    /// The shared instance.
    static let instance = LayoutGuides()

    /// Whether the overlay is drawing.
    ///
    /// Persisted, so it survives a relaunch — unlike the ruler, which is not, because an overlay
    /// that eats touches and comes back after a restart is a trap. Guides only draw.
    internal nonisolated var enabled: Bool {
        get { UserDefaults.scyther.bool(forKey: LayoutGuides.EnabledDefaultsKey) }
        set { UserDefaults.scyther.setValue(newValue, forKey: LayoutGuides.EnabledDefaultsKey) }
    }
}
```

- [ ] **Step 4: Write `LayoutGuidesView`**

Create `Sources/Scyther/Features/LayoutTools/LayoutGuidesView.swift`. The pure function carries the rules; `draw(_:)` strokes what it returns and labels each line with `"\(Int(line.value)) pt"` through `localized(_:)`:

```swift
//
//  LayoutGuidesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import UIKit

/// One drawn guide: where it runs and what it measures.
struct GuideLine: Equatable, Sendable {
    /// What the line represents, which decides its colour.
    enum Kind: Sendable { case safeArea, margin }

    let start: CGPoint
    let end: CGPoint
    let value: CGFloat
    let kind: Kind
}

/// Draws the key window's safe-area insets and layout margins.
///
/// A `TopLevelView` like ``GridOverlayView``: no touches, no state beyond its setting, redrawn
/// on ``updateFrame()``.
internal class LayoutGuidesView: TopLevelView {

    /// Where every guide runs, for a given set of insets.
    ///
    /// Static and pure so the rules are testable: an overlay's `draw(_:)` cannot be inspected by
    /// a test, so anything decided inside it is decided unchecked.
    ///
    /// A zero inset draws nothing. A line labelled `0 pt` flush against the screen edge is noise,
    /// and on a device with no home indicator the bottom inset genuinely is zero.
    ///
    /// - Parameters:
    ///   - safeArea: The window's safe-area insets.
    ///   - margins: The root view's layout margins.
    ///   - bounds: The overlay's bounds.
    /// - Returns: The lines to stroke, safe-area lines first.
    static func guideLines(safeArea: UIEdgeInsets,
                           margins: UIEdgeInsets,
                           in bounds: CGRect) -> [GuideLine] {
        var lines: [GuideLine] = []

        func add(_ inset: CGFloat, _ kind: GuideLine.Kind, _ make: (CGFloat) -> (CGPoint, CGPoint)) {
            guard inset > 0 else { return }
            let (start, end) = make(inset)
            lines.append(GuideLine(start: start, end: end, value: inset, kind: kind))
        }

        for (insets, kind) in [(safeArea, GuideLine.Kind.safeArea), (margins, .margin)] {
            add(insets.top, kind) { (CGPoint(x: bounds.minX, y: $0), CGPoint(x: bounds.maxX, y: $0)) }
            add(insets.bottom, kind) { (CGPoint(x: bounds.minX, y: bounds.maxY - $0),
                                       CGPoint(x: bounds.maxX, y: bounds.maxY - $0)) }
            add(insets.left, kind) { (CGPoint(x: $0, y: bounds.minY), CGPoint(x: $0, y: bounds.maxY)) }
            add(insets.right, kind) { (CGPoint(x: bounds.maxX - $0, y: bounds.minY),
                                      CGPoint(x: bounds.maxX - $0, y: bounds.maxY)) }
        }

        return lines
    }

    internal override func updateFrame() {
        frame = superview?.bounds ?? .zero
        setNeedsDisplay()
    }
}
```

Add `isUserInteractionEnabled = false` and `accessibilityElementsHidden = true` in an initialiser, and implement `draw(_:)` to stroke each line and draw its label. Match `GridOverlayView`'s drawing idiom — read it rather than inventing one.

- [ ] **Step 5: Wire it into `InterfaceToolkit`**

Add beside `setupGridOverlay()`, following it exactly:

```swift
// MARK: - Layout Guides
extension InterfaceToolkit {
    /// Installs the guides overlay, hidden, and brings it to its current setting.
    @MainActor internal func setupLayoutGuides() {
        layoutGuidesView.isHidden = true
        topLevelViewsWrapper.addTopLevelView(topLevelView: layoutGuidesView)
        showLayoutGuides()
    }

    /// Applies ``LayoutGuides/enabled`` to the overlay.
    @MainActor internal func showLayoutGuides() {
        layoutGuidesView.isHidden = !LayoutGuides.instance.enabled
    }
}
```

and the stored view beside `gridOverlayView`:

```swift
    internal var layoutGuidesView: LayoutGuidesView = LayoutGuidesView()
```

Call `setupLayoutGuides()` wherever `setupGridOverlay()` is called.

- [ ] **Step 6: Add the menu row**

Add `case layoutGuides` to `MenuItem`, with `localized("Layout Guides")` in its title switch and an SF Symbol in its icon switch (`"ruler"` is taken by the ruler in Task 4 — use `"rectangle.dashed"`). Wire it into `MenuViewModel`'s UI/UX section as a `Toggle`, calling `InterfaceToolkit.instance.showLayoutGuides()` when it changes.

**Two toggle patterns exist in this codebase and you must pick the right one deliberately.** `showViewFrames` binds a `@Published` property straight to a static on `InterfaceToolkit`. The grid overlay instead goes through a facade property on `Scyther` (`Scyther.swift:761`) which reads and writes `GridOverlay.instance.enabled`. `LayoutGuides` mirrors `GridOverlay`, so it takes the second: add the facade property beside the grid's, and bind the menu to that. Read both call sites before writing either — if what you find differs from this description, follow the code and say so in your report.

- [ ] **Step 7: Add the localisation fragment**

Create `Scripts/localization/strings/LayoutTools.json` with `"Layout Guides"` and `"%lld pt"` in all twelve languages, matching a neighbouring fragment's shape exactly — read `Interface.json` first. Then:

```bash
python3 Scripts/localization/build_catalog.py
```

- [ ] **Step 8: Run the tests and the full suite, then commit**

```bash
git add Sources/Scyther/Features/LayoutTools/ Sources/Scyther/Core/InterfaceToolkit.swift \
        Sources/Scyther/Features/Menu/ Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/LayoutTools.json \
        Tests/ScytherTests/Features/LayoutGuidesTests.swift
git commit -m "Add the layout guides overlay

Safe-area insets and layout margins drawn over the key window, as their own
toggle beside the grid overlay. Zero insets are not drawn: a line labelled 0 pt
against the screen edge is noise."
```

---

### Task 4: The Layout Ruler

**Files:**
- Create: `Sources/Scyther/Features/LayoutTools/LayoutRuler.swift`
- Create: `Sources/Scyther/Features/LayoutTools/LayoutRulerOverlayView.swift`
- Modify: `Sources/Scyther/Core/InterfaceToolkit.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuItem.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuViewModel.swift`
- Modify: `Scripts/localization/strings/LayoutTools.json`
- Test: `Tests/ScytherTests/Features/LayoutRulerTests.swift`

**Interfaces:**
- Consumes: `LayoutRulerGeometry` (Task 1), `ViewProbe` (Task 2).
- Produces:
  - `final class LayoutRuler` with `static let instance`, `@MainActor var isActive: Bool`, `@MainActor var snaps: Bool` (default `true`)
  - `internal class LayoutRulerOverlayView: TopLevelView`
  - `LayoutRuler.measurement(from:to:in:snapping:) -> Measurement?`, a **static** function taking a root view, so it is testable
  - `struct Measurement: Equatable { let start: CGPoint; let end: CGPoint; let distance: CGFloat; let startDescription: String?; let endDescription: String? }`
  - `InterfaceToolkit.setupLayoutRuler()`, `InterfaceToolkit.showLayoutRuler()`
  - `MenuItem.layoutRuler`

Neither `isActive` nor `snaps` is persisted. A ruler that survives a relaunch is a tool the developer must remember to switch off, and the mode is a per-session choice.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/LayoutRulerTests.swift`:

```swift
//
//  LayoutRulerTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class LayoutRulerTests: XCTestCase {

    /// Two views 40pt apart vertically, in a root the probe can walk.
    private func makeTree() -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let top = UIView(frame: CGRect(x: 50, y: 100, width: 300, height: 60))
        let bottom = UIView(frame: CGRect(x: 50, y: 200, width: 300, height: 60))
        root.addSubview(top)
        root.addSubview(bottom)
        return root
    }

    func testASnappedMeasurementReportsTheGapBetweenTwoViews() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.distance, 40, accuracy: 0.001,
                       "160 to 200 is the real gap, whatever the finger did")
    }

    func testAFreeMeasurementKeepsThePointsItWasGiven() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: false)
        )
        XCTAssertEqual(measurement.start, CGPoint(x: 200, y: 150))
        XCTAssertEqual(measurement.end, CGPoint(x: 200, y: 210))
        XCTAssertEqual(measurement.distance, 60, accuracy: 0.001)
    }

    func testASnappedMeasurementNamesWhatItAttachedTo() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertNotNil(measurement.startDescription)
        XCTAssertNotNil(measurement.endDescription)
    }

    /// A free measurement has nothing to name, and inventing a name would be a lie.
    func testAFreeMeasurementNamesNothing() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: 10, y: 10),
                                    to: CGPoint(x: 10, y: 90),
                                    in: root,
                                    snapping: false)
        )
        XCTAssertNil(measurement.startDescription)
        XCTAssertNil(measurement.endDescription)
    }

    /// Resting a finger must not produce a 0.0 pt result that reads like an answer.
    func testATapProducesNoMeasurement() {
        let root = makeTree()
        XCTAssertNil(LayoutRuler.measurement(from: CGPoint(x: 200, y: 150),
                                             to: CGPoint(x: 200, y: 150),
                                             in: root,
                                             snapping: false))
    }

    /// Snapping with nothing under a point falls back to the free point rather than reporting a
    /// snap that did not happen.
    func testSnappingFallsBackWhenThereIsNoViewUnderAPoint() throws {
        let root = makeTree()
        let measurement = try XCTUnwrap(
            LayoutRuler.measurement(from: CGPoint(x: -50, y: -50),
                                    to: CGPoint(x: 200, y: 210),
                                    in: root,
                                    snapping: true)
        )
        XCTAssertEqual(measurement.start, CGPoint(x: -50, y: -50))
        XCTAssertNil(measurement.startDescription)
    }

    func testTheRulerIsInactiveAndSnappingByDefault() {
        XCTAssertFalse(LayoutRuler.instance.isActive)
        XCTAssertTrue(LayoutRuler.instance.snaps)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/LayoutRulerTests`. Expected: compile failure — report it as such.

- [ ] **Step 3: Write `LayoutRuler`**

Create `Sources/Scyther/Features/LayoutTools/LayoutRuler.swift` with the state and the pure `measurement(from:to:in:snapping:)`, which composes `ViewProbe` and `LayoutRulerGeometry`:

- probe each point; when snapping and a view is found, snap to its frame **converted into the root's space** and describe it as `"\(type(of: view)).\(edge.rawValue)"`;
- when not snapping, or when no view is found, keep the point and describe it as `nil`;
- return `nil` when the distance is below `LayoutRulerGeometry.minimumMeasurableDistance`.

Document why the description is built from the class name: a developer reading `UILabel.bottom → UIImageView.top` learns what the measurement attached to, and no better name is available without the view hierarchy inspector this spec deliberately excludes.

- [ ] **Step 4: Write `LayoutRulerOverlayView`**

Create `Sources/Scyther/Features/LayoutTools/LayoutRulerOverlayView.swift`: a `TopLevelView` with `isUserInteractionEnabled = true`, a `UIPanGestureRecognizer` driving `LayoutRuler.measurement(...)`, a `draw(_:)` that strokes the line and its label at `LayoutRulerGeometry.labelOrigin(...)`, and a control carrying **Done** and a **Snap / Free** `UISegmentedControl`.

Set `accessibilityViewIsModal = true` while active so VoiceOver does not wander into the app beneath an overlay it cannot see, and give Done a proper `accessibilityLabel`. The ruler has no non-visual equivalent — a drag between two screen points is not meaningful to a screen reader — but it must never trap anyone inside itself.

Clear the measurement in `updateFrame()`: after a rotation its endpoints describe a layout that no longer exists.

- [ ] **Step 5: Wire it into `InterfaceToolkit` and the menu**

Add `layoutRulerView`, `setupLayoutRuler()` and `showLayoutRuler()` following the Task 3 pattern. Add `MenuItem.layoutRuler` with `localized("Layout Ruler")` and the `"ruler"` SF Symbol, as a row that dismisses the menu and sets `LayoutRuler.instance.isActive = true`. Follow how the accessibility audit's row activates its overlay.

- [ ] **Step 6: Extend the localisation fragment**

Add `"Layout Ruler"`, `"Done"`, `"Snap"`, `"Free"` and `"%@ → %@"` to `Scripts/localization/strings/LayoutTools.json` in all twelve languages, then rebuild the catalogue.

- [ ] **Step 7: Run the tests and the full suite, then commit**

```bash
git add Sources/Scyther/Features/LayoutTools/ Sources/Scyther/Core/InterfaceToolkit.swift \
        Sources/Scyther/Features/Menu/ Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/LayoutTools.json \
        Tests/ScytherTests/Features/LayoutRulerTests.swift
git commit -m "Add the layout ruler

Drag to measure, snapping each endpoint to the nearest edge of the view under
it, so the number answers 'is this the 16 points I specified' rather than 'how
steady was my thumb'. Free mode stays for measuring into whitespace."
```

---

### Task 5: Documentation and verification on device

**Files:**
- Modify: `README.md`
- Modify: `Sources/Scyther/Scyther.docc/UIDebuggingTools.md`

**Interfaces:**
- Consumes: everything. Produces nothing.

- [ ] **Step 1: Update the README**

Add both tools to the UI/UX feature list: the guides as a toggle, the ruler as an interactive tool. State plainly that the ruler takes over touches while active and that Done exits it — a developer who does not know that will think the app has frozen.

- [ ] **Step 2: Update the DocC article**

`Sources/Scyther/Scyther.docc/UIDebuggingTools.md` covers the overlays. Add both, and record two things the next reader will otherwise undo: why the guides are a separate toggle rather than part of the ruler, and why `ViewProbe` is not `hitTest(_:with:)`.

- [ ] **Step 3: Build the example app**

```bash
cd Example && xcodebuild build -project ScytherExample.xcodeproj -scheme ScytherExample \
  -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-layout
```

- [ ] **Step 4: Walk the spec's seven checks**

From the spec's "Verification on device" section, in order, reporting what you saw for each:

1. Layout Guides' safe-area lines sit where the safe area actually ends.
2. The guides stay correct while scrolling and navigating, and survive a rotation.
3. A snapped drag between two labels reports their real gap and names both views.
4. A drag over Scyther's own control does not measure the control.
5. Free mode keeps the endpoints where they are put.
6. Done exits, and the shake gesture also reaches the menu while the overlay is active.
7. Rotating mid-measurement clears the measurement.

**Do not report this task done on a build you have not run.** Every serious defect in this codebase's recent interface work — a hang, dead rows, clipped text, an unusable default, a gesture that never fired — was found by running the app, not by reading the diff or the tests.

- [ ] **Step 5: Commit**

```bash
git add README.md Sources/Scyther/Scyther.docc/UIDebuggingTools.md
git commit -m "Document the layout tools"
```

---

## Self-Review

**Spec coverage.** Goal 1 (the ruler) is Tasks 1, 2 and 4; goal 2 (the guides) is Task 3. The three recorded decisions are honoured: the two specs stay separate (this plan is the ruler's alone), snapping is the default with free available (Task 4), and the guides are their own toggle (Task 3). Every edge case in the spec's table has a home — no key window and the snap fallback in Task 4, zero insets in Task 3, rotation clearing in Task 4 Step 4, the tap floor in Task 1. Accessibility is Task 4 Step 4; localisation is folded into Tasks 3 and 4; device verification is Task 5.

**Known gap, stated rather than hidden.** The spec says a finished measurement does not follow scrolling content. Nothing in this plan tests that, because it is a property of *not* wiring something up — there is no scroll observer to assert the absence of. Task 5's device walk is where it is actually checked, and check 7 is its nearest proxy.

**Type consistency.** `LayoutRulerGeometry.Edge`, `snapped(_:to:)`, `distance(from:to:)`, `labelOrigin(midpoint:labelSize:in:)` and `minimumMeasurableDistance` are used with those exact names in Tasks 1 and 4. `ViewProbe.view(at:in:)` is used with that signature in Tasks 2 and 4. `GuideLine` and `guideLines(safeArea:margins:in:)` appear only in Task 3. `LayoutGuides.EnabledDefaultsKey` is used in Task 3's tests and implementation.

**Two names verified against the code while writing this.** `UserDefaults.scyther` is real and is what `GridOverlay` reads and writes. `TopLevelViewsWrapper.addTopLevelView(topLevelView:)` takes that exact argument label. `Sources/Scyther/Scyther.docc/UIDebuggingTools.md` exists.

**One correction made during self-review.** Task 3 Step 6 originally said to follow `showViewFrames`. That was wrong: it uses a static on `InterfaceToolkit`, while the grid overlay — which `LayoutGuides` actually mirrors — goes through a facade property on `Scyther`. The step now names both and says which to take.
