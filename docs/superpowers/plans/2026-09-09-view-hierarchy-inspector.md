# View Hierarchy Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A browsable snapshot of the key window's view hierarchy, reachable from the Scyther menu, where selecting a view reports its geometry, appearance and responder context.

**Architecture:** A `@MainActor` walker builds an immutable, `Sendable` tree of `ViewNode` values from the key window, holding no strong references to any `UIView`; a weak side table on the snapshot maps node identity back to a live view for the one operation that needs it, the thumbnail. Everything with a right answer — search and its ancestor paths, the position map's arithmetic, the indentation cap — lives in a pure type a test can reach, and the SwiftUI pages call those and decide nothing.

**Tech Stack:** Swift 6 (complete strict concurrency), SwiftUI + UIKit, XCTest, SPM (iOS only).

**Spec:** `docs/superpowers/specs/2026-09-09-view-hierarchy-inspector-design.md`

## Global Constraints

- Swift 6 language mode, complete strict concurrency. iOS 16 deployment floor — `ContentUnavailableView` and `MagnifyGesture` are iOS 17 and need `#available` guards.
- iOS-only builds. `swift build` does not work; use `xcodebuild`.
- Build: `xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Test: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- ALWAYS use the stock SwiftUI component when one serves the need (`List`, `DisclosureGroup`, `LabeledContent`, `NavigationLink`, `.searchable`, `.refreshable`). NEVER hand-roll a row or control SwiftUI already provides.
- NEVER use `.confirmationDialog`; use alerts.
- ALWAYS create separate view model files; MVVM + Repository; SoC.
- ALWAYS add/update tests. ALWAYS add/update DocC. ALWAYS update the README.
- Every user-facing string goes through `localized(_:)`, with its key added to `Scripts/localization/strings/ViewHierarchy.json` in all twelve languages, then `python3 Scripts/localization/build_catalog.py` run to rebuild `Sources/Scyther/Resources/Localizable.xcstrings`.
- The twelve language codes, exactly: `fr`, `de`, `es`, `it`, `pt-BR`, `nl`, `ja`, `zh-Hans`, `zh-Hant`, `ko`, `ru`, `ar`. English is the key itself and is not listed.
- `build_catalog.py` **hard-fails on a key defined in two fragments.** Before adding any key, `grep -rn '"<the key>"' Scripts/localization/strings/` and pick a different wording if it is already owned elsewhere.
- NEVER build a key by string interpolation — `localized("\(n) pt")` cannot resolve. Use one key with a format specifier and `String(format:)`.
- British spelling in new naming (`colour`, not `color`), except where it would break an Apple API name.
- **The walk must never touch the accessibility tree.** Asking a `UIView` for accessibility children forces `UIAccessibility` to compute a subtree recursively and hung this app in 4.3.0.
- **No Claude attribution, no session URL, no co-author trailer in any commit message.**

---

## File Structure

`Sources/Scyther/Features/ViewHierarchy/` (all new):

| File | Responsibility |
| --- | --- |
| `ViewNode.swift` | Pure, `Sendable` snapshot node + the indentation cap. No UIKit beyond `CGRect`. |
| `ViewNodeSearch.swift` | Pure. Query → matches with ancestor paths. |
| `ViewHierarchyWalker.swift` | `@MainActor`. Builds a `ViewHierarchySnapshot` from a root view. |
| `ViewHierarchySnapshot.swift` | `@MainActor` reference type: the root node, when it was taken, and the weak node→view side table. |
| `ViewPositionMap.swift` | Pure. A window-space frame scaled into an outline box. |
| `ViewThumbnailRenderer.swift` | `@MainActor`. Renders one view on demand, capped. |
| `ViewContext.swift` | `@MainActor`. Owning controller and responder chain for a view. |
| `ViewDetailView.swift` / `ViewDetailViewModel.swift` | The detail page. |
| `ViewHierarchyView.swift` / `ViewHierarchyViewModel.swift` | The tree page. |

Modified: `MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift`, `Tests/ScytherTests/Features/MenuItemTests.swift`, `README.md`, `Sources/Scyther/Scyther.docc/UIDebuggingTools.md`, `Scripts/localization/strings/ViewHierarchy.json` (new), `Sources/Scyther/Resources/Localizable.xcstrings`.

Task order is leaf-first: the pure types, then the walker, then the renderers, then the detail page, then the tree page that navigates to it, then documentation and the device walk.

---

### Task 1: `ViewNode` and `ViewNodeSearch`

**Files:**
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewNode.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewNodeSearch.swift`
- Test: `Tests/ScytherTests/Features/ViewNodeSearchTests.swift`

**Interfaces:**
- Consumes: `String.searchMatches(_:)` from `Sources/Scyther/Shared/Extensions/String+SearchMatching.swift` — case- and diacritic-insensitive, underscores treated as spaces.
- Produces:
  - `struct ViewNode: Identifiable, Equatable, Sendable` with `let id: ObjectIdentifier`, `className: String`, `frameInWindow: CGRect`, `depth: Int`, `text: String?`, `isHidden: Bool`, `isZeroSize: Bool`, `isOffScreen: Bool`, `children: [ViewNode]`
  - `ViewNode.maximumIndentationDepth: Int` (= 8) and `static func indentationLevel(forDepth depth: Int) -> Int`
  - `enum ViewNodeSearch` with `struct Match: Equatable, Sendable { let node: ViewNode; let path: [String] }` and `static func matches(for query: String, in root: ViewNode) -> [Match]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewNodeSearchTests.swift`:

```swift
//
//  ViewNodeSearchTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

final class ViewNodeSearchTests: XCTestCase {

    /// A three-deep tree: window → scroll view → stack view → {label, button}.
    ///
    /// Built from real `UIView`s only to get distinct `ObjectIdentifier`s; nothing here
    /// reads a view, so the test stays a test of the pure type.
    private func makeTree() -> ViewNode {
        let objects = (0..<5).map { _ in UIView() }
        func node(_ index: Int,
                  _ className: String,
                  depth: Int,
                  text: String? = nil,
                  children: [ViewNode] = []) -> ViewNode {
            ViewNode(id: ObjectIdentifier(objects[index]),
                     className: className,
                     frameInWindow: CGRect(x: 0, y: 0, width: 100, height: 20),
                     depth: depth,
                     text: text,
                     isHidden: false,
                     isZeroSize: false,
                     isOffScreen: false,
                     children: children)
        }
        let label = node(3, "UILabel", depth: 3, text: "GraphQL Demo")
        let button = node(4, "UIButton", depth: 3, text: "Run GraphQL Query")
        let stack = node(2, "UIStackView", depth: 2, children: [label, button])
        let scroll = node(1, "UIScrollView", depth: 1, children: [stack])
        return node(0, "UIWindow", depth: 0, children: [scroll])
    }

    func testAClassNameMatchIsFound() {
        let matches = ViewNodeSearch.matches(for: "stackview", in: makeTree())
        XCTAssertEqual(matches.map(\.node.className), ["UIStackView"])
    }

    func testCarriedTextIsMatchedToo() {
        let matches = ViewNodeSearch.matches(for: "graphql", in: makeTree())
        XCTAssertEqual(matches.map(\.node.className), ["UILabel", "UIButton"],
                       "both the label's text and the button's title carry the word")
    }

    func testAMatchCarriesItsAncestorPathRootFirstAndExcludingItself() throws {
        let match = try XCTUnwrap(
            ViewNodeSearch.matches(for: "Run GraphQL", in: makeTree()).first
        )
        XCTAssertEqual(match.path, ["UIWindow", "UIScrollView", "UIStackView"])
        XCTAssertEqual(match.node.className, "UIButton")
    }

    func testTheRootItselfCanMatchAndHasAnEmptyPath() throws {
        let match = try XCTUnwrap(ViewNodeSearch.matches(for: "UIWindow", in: makeTree()).first)
        XCTAssertTrue(match.path.isEmpty)
    }

    func testResultsAreInTreeOrder() {
        let matches = ViewNodeSearch.matches(for: "ui", in: makeTree())
        XCTAssertEqual(matches.map(\.node.className),
                       ["UIWindow", "UIScrollView", "UIStackView", "UILabel", "UIButton"],
                       "depth-first, parents before children, so the list reads like the tree")
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(ViewNodeSearch.matches(for: "UISTACKVIEW", in: makeTree()).count, 1)
    }

    /// An empty or whitespace query is not "match everything" — it is "not searching".
    func testAnEmptyQueryMatchesNothing() {
        XCTAssertTrue(ViewNodeSearch.matches(for: "", in: makeTree()).isEmpty)
        XCTAssertTrue(ViewNodeSearch.matches(for: "   ", in: makeTree()).isEmpty)
    }

    func testAQueryMatchingNothingReturnsNothing() {
        XCTAssertTrue(ViewNodeSearch.matches(for: "zzzz", in: makeTree()).isEmpty)
    }

    func testIndentationStopsIncreasingAfterTheCap() {
        XCTAssertEqual(ViewNode.indentationLevel(forDepth: 0), 0)
        XCTAssertEqual(ViewNode.indentationLevel(forDepth: 8), 8)
        XCTAssertEqual(ViewNode.indentationLevel(forDepth: 9), 8)
        XCTAssertEqual(ViewNode.indentationLevel(forDepth: 40), 8)
    }

    /// The cap is cosmetic. A node's real depth must survive it, because the ancestor
    /// path in search is what tells you where a deep node actually lives.
    func testTheCapDoesNotChangeAReportedDepth() {
        let object = UIView()
        let deep = ViewNode(id: ObjectIdentifier(object),
                            className: "UIView",
                            frameInWindow: .zero,
                            depth: 40,
                            text: nil,
                            isHidden: false,
                            isZeroSize: true,
                            isOffScreen: false,
                            children: [])
        XCTAssertEqual(deep.depth, 40)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/ViewNodeSearchTests`

Expected: a **compile failure**, not an assertion failure — `Cannot find 'ViewNode' in scope` and `Cannot find 'ViewNodeSearch' in scope`. Report it as a compile failure; that is the correct red step when the types do not exist yet.

- [ ] **Step 3: Write `ViewNode`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewNode.swift`:

```swift
//
//  ViewNode.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// One view in a hierarchy snapshot.
///
/// A value type that deliberately holds **no reference to the `UIView` it describes**. A tree
/// that strongly held views would keep an entire screen alive for as long as the inspector's
/// page was open; the one operation that needs the real view — the thumbnail — goes through
/// ``ViewHierarchySnapshot``'s weak side table instead.
///
/// `id` is the described view's `ObjectIdentifier`, which is `Sendable` and is exactly the
/// question the side table asks. It is an identity token, not a reference: it says nothing about
/// whether the view is still alive.
struct ViewNode: Identifiable, Equatable, Sendable {
    /// The identity of the view this node describes.
    let id: ObjectIdentifier

    /// The view's class name, as `String(describing: type(of: view))`.
    let className: String

    /// The view's frame converted into the window's coordinate space.
    let frameInWindow: CGRect

    /// How many ancestors sit between this node and the root. The root is `0`.
    let depth: Int

    /// Text the view carries itself — a `UILabel`'s `text`, a `UIButton`'s current title —
    /// or `nil`. Never read from an accessibility property.
    let text: String?

    /// Whether the view is invisible: `isHidden`, or an effective alpha at or below `0.01`
    /// anywhere in its ancestry.
    let isHidden: Bool

    /// Whether the view has a zero width or a zero height.
    let isZeroSize: Bool

    /// Whether the view's window-space frame does not intersect the window's bounds.
    let isOffScreen: Bool

    /// This node's children, in subview order.
    let children: [ViewNode]

    /// The view's size, in points.
    var size: CGSize { frameInWindow.size }

    // MARK: - Indentation

    /// The deepest level the tree indents to.
    ///
    /// Beyond this, indentation stops growing. A hierarchy forty levels deep would otherwise
    /// push a class name off the right of a phone, and the row's own label is worth more than
    /// a faithful indent. The real depth is untouched, and search's ancestor path carries the
    /// full chain for anyone who needs it.
    static let maximumIndentationDepth: Int = 8

    /// How far to indent a row at `depth`, capped at ``maximumIndentationDepth``.
    ///
    /// - Parameter depth: The node's real depth.
    /// - Returns: The indentation level to draw, never greater than the cap.
    static func indentationLevel(forDepth depth: Int) -> Int {
        min(max(depth, 0), maximumIndentationDepth)
    }
}
#endif
```

- [ ] **Step 4: Write `ViewNodeSearch`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewNodeSearch.swift`:

```swift
//
//  ViewNodeSearch.swift
//  Scyther
//

#if !os(macOS)
import Foundation

/// Finds views in a snapshot by class name or by the text they carry.
///
/// Pure and separate from the page, because the rules here have right answers a test can check:
/// what matches, in what order, and what path is reported for a hit. A hit deep in a hierarchy
/// is useless without knowing where it lives, so every match carries its ancestor chain.
enum ViewNodeSearch {
    /// One search hit and the chain of ancestors above it.
    struct Match: Equatable, Sendable {
        /// The node that matched.
        let node: ViewNode

        /// The class names of the node's ancestors, root first, **excluding the node itself**.
        /// Empty when the root is the match.
        let path: [String]
    }

    /// Every node matching `query`, depth-first, parents before children.
    ///
    /// An empty or whitespace-only query returns nothing rather than everything: a blank search
    /// field means "not searching", and answering it with the entire tree would bury the page.
    ///
    /// Matching uses ``Swift/String/searchMatches(_:)``, the same rule the Cookie Browser and
    /// Environment Variables pages use, so a query behaves identically wherever it is typed.
    ///
    /// - Parameters:
    ///   - query: The user's search text.
    ///   - root: The snapshot's root node.
    /// - Returns: Matches in tree order.
    static func matches(for query: String, in root: ViewNode) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [Match] = []

        func walk(_ node: ViewNode, path: [String]) {
            if node.className.searchMatches(trimmed) || (node.text?.searchMatches(trimmed) ?? false) {
                results.append(Match(node: node, path: path))
            }
            let childPath = path + [node.className]
            for child in node.children { walk(child, path: childPath) }
        }

        walk(root, path: [])
        return results
    }
}
#endif
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/ViewNodeSearchTests`

Expected: 10 tests, 0 failures.

- [ ] **Step 6: Run the full suite**

Run the full `xcodebuild test` command from Global Constraints. Expected: all tests pass, no new warnings.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/ViewHierarchy/ Tests/ScytherTests/Features/ViewNodeSearchTests.swift
git commit -m "Add the view hierarchy's node and search

A snapshot node that holds no UIView, so browsing a tree cannot keep a
screen alive, and a search that reports each hit's ancestor path, because a
match forty levels down is useless without knowing where it lives."
```

---

### Task 2: `ViewHierarchyWalker` and `ViewHierarchySnapshot`

**Files:**
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewHierarchySnapshot.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyWalker.swift`
- Test: `Tests/ScytherTests/Features/ViewHierarchyWalkerTests.swift`

**Interfaces:**
- Consumes: `ViewNode` (Task 1). `UIView.isScytherOwned` — a `Bool` property from `AuditNode.swift`'s `AuditNode` conformance, already used by `ViewProbe.isEligible(_:)` at `Sources/Scyther/Features/LayoutTools/ViewProbe.swift:139`.
- Produces:
  - `@MainActor final class ViewHierarchySnapshot` with `let root: ViewNode`, `let takenAt: Date`, `let nodeCount: Int`, and `func view(for id: ObjectIdentifier) -> UIView?`
  - `@MainActor enum ViewHierarchyWalker` with `static func snapshot(of root: UIView, windowBounds: CGRect) -> ViewHierarchySnapshot` and `static func snapshot(of window: UIWindow) -> ViewHierarchySnapshot`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewHierarchyWalkerTests.swift`:

```swift
//
//  ViewHierarchyWalkerTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewHierarchyWalkerTests: XCTestCase {

    private let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func makeRoot() -> UIView {
        UIView(frame: windowBounds)
    }

    func testTheTreeMirrorsTheViewHierarchy() {
        let root = makeRoot()
        let middle = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let leaf = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 50))
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.children.count, 1)
        XCTAssertEqual(snapshot.root.children[0].children.count, 1)
        XCTAssertEqual(snapshot.nodeCount, 3)
    }

    func testDepthCountsAncestorsFromTheRoot() {
        let root = makeRoot()
        let middle = UIView()
        let leaf = UIView()
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.depth, 0)
        XCTAssertEqual(snapshot.root.children[0].depth, 1)
        XCTAssertEqual(snapshot.root.children[0].children[0].depth, 2)
    }

    func testFramesAreReportedInWindowSpace() {
        let root = makeRoot()
        let middle = UIView(frame: CGRect(x: 50, y: 100, width: 200, height: 200))
        let leaf = UIView(frame: CGRect(x: 10, y: 20, width: 30, height: 40))
        middle.addSubview(leaf)
        root.addSubview(middle)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let leafNode = snapshot.root.children[0].children[0]

        XCTAssertEqual(leafNode.frameInWindow, CGRect(x: 60, y: 120, width: 30, height: 40),
                       "the leaf's own frame is in its parent's space; the node's is in the window's")
    }

    func testAHiddenViewIsFlagged() {
        let root = makeRoot()
        let hidden = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        hidden.isHidden = true
        root.addSubview(hidden)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isHidden)
    }

    /// Invisibility is inherited. A child of a fully transparent parent cannot be seen, however
    /// opaque it is itself, and a badge that said otherwise would send you hunting for a view
    /// that is not on screen.
    func testAChildOfATransparentAncestorIsFlaggedHidden() {
        let root = makeRoot()
        let faded = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        faded.alpha = 0
        let child = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        faded.addSubview(child)
        root.addSubview(faded)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let childNode = snapshot.root.children[0].children[0]

        XCTAssertTrue(childNode.isHidden)
        XCTAssertEqual(childNode.className, "UIView")
    }

    func testAZeroSizeViewIsFlagged() {
        let root = makeRoot()
        let collapsed = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        root.addSubview(collapsed)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isZeroSize)
        XCTAssertFalse(snapshot.root.children[0].isHidden,
                       "zero-size and hidden are different states and are badged differently")
    }

    func testAViewOutsideTheWindowIsFlaggedOffScreen() {
        let root = makeRoot()
        let away = UIView(frame: CGRect(x: 0, y: 900, width: 100, height: 50))
        root.addSubview(away)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertTrue(snapshot.root.children[0].isOffScreen)
    }

    func testAViewPartlyOnScreenIsNotOffScreen() {
        let root = makeRoot()
        let straddling = UIView(frame: CGRect(x: 0, y: 780, width: 100, height: 50))
        root.addSubview(straddling)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertFalse(snapshot.root.children[0].isOffScreen,
                       "twenty points of it are visible, so it is on screen")
    }

    func testALabelsTextIsCarried() {
        let root = makeRoot()
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "GraphQL Demo"
        root.addSubview(label)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.root.children[0].text, "GraphQL Demo")
    }

    func testAButtonsTitleIsCarried() throws {
        let root = makeRoot()
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        button.setTitle("Run GraphQL Query", for: .normal)
        root.addSubview(button)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let buttonNode = try XCTUnwrap(snapshot.root.children.first)

        XCTAssertEqual(buttonNode.text, "Run GraphQL Query")
    }

    func testAPlainViewCarriesNoText() {
        let root = makeRoot()
        root.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertNil(snapshot.root.children[0].text)
    }

    /// The first thing you would otherwise find in the tree is the inspector itself.
    ///
    /// The ownership test is injected here rather than overridden on a subclass: `isScytherOwned`
    /// is a computed property on an `extension UIView: AuditNode`, and Swift does not allow a
    /// subclass to override a member declared in an extension. Production call sites use the
    /// default and therefore the real rule.
    func testScytherOwnedSubtreesAreSkipped() {
        let root = makeRoot()
        let ours = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ours.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        root.addSubview(ours)
        root.addSubview(UIView(frame: CGRect(x: 0, y: 200, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root,
                                                    windowBounds: windowBounds,
                                                    isOwned: { $0 === ours })

        XCTAssertEqual(snapshot.root.children.count, 1,
                       "the owned view and everything beneath it is gone, the host view stays")
        XCTAssertEqual(snapshot.nodeCount, 2)
    }

    /// The default really is the shared rule, not a stub that only the tests exercise.
    func testTheDefaultOwnershipTestIsScytherOwn() {
        let root = makeRoot()
        root.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(snapshot.nodeCount, 2, "a plain UIView is not Scyther's, so nothing is skipped")
    }

    func testTheSideTableResolvesANodeBackToItsView() {
        let root = makeRoot()
        let child = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        root.addSubview(child)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertIdentical(snapshot.view(for: snapshot.root.children[0].id), child)
    }

    /// The point of the weak table: a snapshot must not be why a screen stays in memory.
    func testTheSideTableDoesNotKeepAViewAlive() {
        let root = makeRoot()
        var child: UIView? = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        root.addSubview(child!)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let id = snapshot.root.children[0].id

        child!.removeFromSuperview()
        child = nil

        XCTAssertNil(snapshot.view(for: id))
    }

    /// The accessibility audit hung this app in 4.3.0 by asking views for their accessibility
    /// children. This proves the walk never asks — kept honest by a spy rather than by intent.
    func testTheWalkNeverReadsAnAccessibilityProperty() {
        let root = makeRoot()
        let spy = AccessibilitySpyView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        root.addSubview(spy)

        _ = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        XCTAssertEqual(spy.accessibilityReads, 0)
    }
}

/// Counts every accessibility member the walk could reach through the container protocol.
private final class AccessibilitySpyView: UIView {
    var accessibilityReads = 0

    override var accessibilityElements: [Any]? {
        get { accessibilityReads += 1; return super.accessibilityElements }
        set { super.accessibilityElements = newValue }
    }

    override func accessibilityElementCount() -> Int {
        accessibilityReads += 1
        return super.accessibilityElementCount()
    }

    override func accessibilityElement(at index: Int) -> Any? {
        accessibilityReads += 1
        return super.accessibilityElement(at: index)
    }

    override var accessibilityLabel: String? {
        get { accessibilityReads += 1; return super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }
}
```

**Confirmed while writing this plan:** `isScytherOwned` is a computed property on `extension UIView: AuditNode` (`Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift:836` and `:932`), and Swift does not permit a subclass to override a member declared in an extension. So the walker takes the test as a parameter:

```swift
static func snapshot(of root: UIView,
                     windowBounds: CGRect,
                     isOwned: (UIView) -> Bool = { $0.isScytherOwned }) -> ViewHierarchySnapshot
```

Only the one test passes a stub; every production call site uses the default, and `testTheDefaultOwnershipTestIsScytherOwn` proves the default is wired to the real rule rather than to something permissive.

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/ViewHierarchyWalkerTests`. Expected: compile failure — `Cannot find 'ViewHierarchyWalker' in scope`.

- [ ] **Step 3: Write `ViewHierarchySnapshot`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewHierarchySnapshot.swift`:

```swift
//
//  ViewHierarchySnapshot.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// One walk of a view hierarchy, and the means to get back to a live view from it.
///
/// The tree itself is ``ViewNode`` values holding no references. This type owns the one bridge
/// back to UIKit that the inspector needs — the thumbnail — and keeps it **weak**, so a snapshot
/// left open on a screen the user has since navigated away from does not keep that screen alive.
/// A node whose view has gone resolves to `nil`, and the detail page reports that rather than
/// rendering an empty box.
@MainActor
final class ViewHierarchySnapshot {
    /// The root of the walked tree.
    let root: ViewNode

    /// When the walk ran. The page shows this, because a snapshot that does not say it is a
    /// snapshot is a lie.
    let takenAt: Date

    /// How many nodes the tree holds, including the root.
    let nodeCount: Int

    /// Weak boxes keyed by node identity.
    private let views: [ObjectIdentifier: WeakView]

    /// A weak reference in a box, so it can live in a dictionary.
    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - root: The walked tree.
    ///   - views: Every node's identity mapped to its view.
    ///   - takenAt: When the walk ran. Defaults to now.
    init(root: ViewNode, views: [ObjectIdentifier: UIView], takenAt: Date = Date()) {
        self.root = root
        self.takenAt = takenAt
        self.views = views.mapValues(WeakView.init)

        func count(_ node: ViewNode) -> Int {
            1 + node.children.reduce(0) { $0 + count($1) }
        }
        self.nodeCount = count(root)
    }

    /// The live view a node describes, or `nil` if it has been deallocated since the walk.
    ///
    /// - Parameter id: The node's identity.
    /// - Returns: The view, while it still exists.
    func view(for id: ObjectIdentifier) -> UIView? {
        views[id]?.view
    }
}
#endif
```

- [ ] **Step 4: Write `ViewHierarchyWalker`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyWalker.swift`:

```swift
//
//  ViewHierarchyWalker.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Builds a ``ViewHierarchySnapshot`` from a live view hierarchy.
///
/// **Everything this reads is a cheap stored property**: `subviews`, `frame`, `isHidden`,
/// `alpha`, and a text property on two concrete types. It must never touch the accessibility
/// tree. Asking a `UIView` for its accessibility children forces `UIAccessibility` to compute a
/// subtree recursively, which is what hung this app in 4.3.0 — and a hierarchy walk is that
/// mistake's natural home.
@MainActor
enum ViewHierarchyWalker {
    /// Walks the key window.
    ///
    /// - Parameter window: The window to snapshot.
    /// - Returns: The snapshot.
    static func snapshot(of window: UIWindow) -> ViewHierarchySnapshot {
        snapshot(of: window, windowBounds: window.bounds)
    }

    /// Walks any root, measuring against the bounds given.
    ///
    /// Split from ``snapshot(of:)-(UIWindow)`` so the rules can be exercised against a synthetic
    /// hierarchy without standing up a window.
    ///
    /// - Parameters:
    ///   - root: The view to walk.
    ///   - windowBounds: The bounds every frame is converted into and measured against.
    /// - Returns: The snapshot.
    ///   - isOwned: The ownership test. Defaults to the shared ``AuditNode/isScytherOwned`` rule;
    ///     injectable only because that property lives on an extension and cannot be overridden
    ///     by a test subclass.
    static func snapshot(of root: UIView,
                         windowBounds: CGRect,
                         isOwned: (UIView) -> Bool = { $0.isScytherOwned }) -> ViewHierarchySnapshot {
        var views: [ObjectIdentifier: UIView] = [:]

        func node(for view: UIView, depth: Int, ancestorsHidden: Bool) -> ViewNode {
            let frame = view.superview.map { $0.convert(view.frame, to: root) } ?? view.frame
            let hidden = ancestorsHidden || view.isHidden || view.alpha <= 0.01

            let children = view.subviews
                .filter { !isOwned($0) }
                .map { node(for: $0, depth: depth + 1, ancestorsHidden: hidden) }

            views[ObjectIdentifier(view)] = view

            return ViewNode(id: ObjectIdentifier(view),
                            className: String(describing: type(of: view)),
                            frameInWindow: frame,
                            depth: depth,
                            text: text(of: view),
                            isHidden: hidden,
                            isZeroSize: frame.width == 0 || frame.height == 0,
                            isOffScreen: !frame.intersects(windowBounds),
                            children: children)
        }

        let tree = node(for: root, depth: 0, ancestorsHidden: false)
        return ViewHierarchySnapshot(root: tree, views: views)
    }

    /// Text the view carries itself.
    ///
    /// Read from concrete types only. An accessibility label would be a richer answer and is
    /// exactly the property this walk must not touch.
    ///
    /// - Parameter view: The view to read.
    /// - Returns: Its text, or `nil`.
    private static func text(of view: UIView) -> String? {
        switch view {
        case let label as UILabel: return label.text
        case let button as UIButton: return button.currentTitle
        case let field as UITextField: return field.text
        default: return nil
        }
    }
}
#endif
```

Two details that matter and are easy to get wrong:

- The frame conversion uses `root` as the destination, so the root's own node has its untouched frame and every descendant is measured in the same space. `view.superview.map` handles the root, which has no superview inside the walk.
- The Scyther filter is applied to `subviews` **before** recursing, so an owned view's whole subtree disappears with it rather than its children being re-parented into the tree.

- [ ] **Step 5: Run the tests to verify they pass**

Run with `-only-testing:ScytherTests/ViewHierarchyWalkerTests`. Expected: 16 tests, 0 failures.

- [ ] **Step 6: Run the full suite**

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/ViewHierarchy/ Tests/ScytherTests/Features/ViewHierarchyWalkerTests.swift
git commit -m "Walk a view hierarchy into a snapshot

Cheap stored properties only, and never the accessibility tree — that is
the walk that hung the app in 4.3.0. The snapshot's node-to-view table is
weak, so an open inspector is never the reason a screen stays in memory."
```

---

### Task 3: `ViewPositionMap`, `ViewThumbnailRenderer` and `ViewContext`

**Files:**
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewPositionMap.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewThumbnailRenderer.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewContext.swift`
- Test: `Tests/ScytherTests/Features/ViewPositionMapTests.swift`
- Test: `Tests/ScytherTests/Features/ViewContextTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum ViewPositionMap` with `static func outlineRect(forWindowBounds: CGRect, in box: CGSize) -> CGRect` and `static func rect(for frameInWindow: CGRect, windowBounds: CGRect, in box: CGSize) -> CGRect`
  - `@MainActor enum ViewThumbnailRenderer` with `static let maximumSize = CGSize(width: 512, height: 512)`, `enum Thumbnail: Equatable { case image(UIImage), hidden, zeroSize, unavailable }`, and `static func thumbnail(of view: UIView?, isHidden: Bool, isZeroSize: Bool) -> Thumbnail`
  - `@MainActor enum ViewContext` with `static func owningController(of view: UIView) -> UIViewController?`, `static func responderChain(from view: UIView) -> [String]`, `static func isFirstResponder(_ view: UIView) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewPositionMapTests.swift`:

```swift
//
//  ViewPositionMapTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

final class ViewPositionMapTests: XCTestCase {

    /// iPhone-shaped window in a square box: the outline is letterboxed, not stretched.
    private let window = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let box = CGSize(width: 100, height: 100)

    func testTheOutlineKeepsTheWindowsAspectRatio() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.width / outline.height, 0.5, accuracy: 0.001)
    }

    func testTheOutlineFitsInsideTheBox() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.height, 100, accuracy: 0.001, "height is the limiting dimension")
        XCTAssertEqual(outline.width, 50, accuracy: 0.001)
    }

    func testTheOutlineIsCentredInTheBox() {
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        XCTAssertEqual(outline.midX, 50, accuracy: 0.001)
        XCTAssertEqual(outline.midY, 50, accuracy: 0.001)
    }

    func testAFullScreenFrameFillsTheOutline() {
        let mapped = ViewPositionMap.rect(for: window, windowBounds: window, in: box)
        XCTAssertEqual(mapped, ViewPositionMap.outlineRect(forWindowBounds: window, in: box))
    }

    func testAFrameIsScaledAndOffsetIntoTheOutline() {
        // Top-left quarter of the window.
        let quarter = CGRect(x: 0, y: 0, width: 200, height: 400)
        let mapped = ViewPositionMap.rect(for: quarter, windowBounds: window, in: box)
        XCTAssertEqual(mapped.origin.x, 25, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 25, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 50, accuracy: 0.001)
    }

    /// An off-screen view must map *outside* the outline rather than being clamped onto its edge.
    /// Clamping would draw a view that is 900 points down as though it sat at the bottom of the
    /// screen, which is a different and wrong answer.
    func testAnOffScreenFrameMapsOutsideTheOutline() {
        let away = CGRect(x: 0, y: 900, width: 100, height: 50)
        let outline = ViewPositionMap.outlineRect(forWindowBounds: window, in: box)
        let mapped = ViewPositionMap.rect(for: away, windowBounds: window, in: box)
        XCTAssertGreaterThan(mapped.minY, outline.maxY)
    }

    func testADegenerateWindowDoesNotDivideByZero() {
        let mapped = ViewPositionMap.rect(for: CGRect(x: 0, y: 0, width: 10, height: 10),
                                          windowBounds: .zero,
                                          in: box)
        XCTAssertEqual(mapped, .zero)
    }
}
```

Create `Tests/ScytherTests/Features/ViewContextTests.swift`:

```swift
//
//  ViewContextTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewContextTests: XCTestCase {

    func testTheOwningControllerIsFoundThroughTheResponderChain() {
        let controller = UIViewController()
        let child = UIView()
        controller.view.addSubview(child)

        XCTAssertIdentical(ViewContext.owningController(of: child), controller)
    }

    func testTheNearestControllerWinsWhenControllersAreNested() {
        let parent = UIViewController()
        let child = UIViewController()
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)

        let leaf = UIView()
        child.view.addSubview(leaf)

        XCTAssertIdentical(ViewContext.owningController(of: leaf), child,
                           "the answer to 'which screen is this from' is the closest one")
    }

    func testAnOrphanViewHasNoOwningController() {
        XCTAssertNil(ViewContext.owningController(of: UIView()))
    }

    func testTheResponderChainIsReportedNearestFirst() {
        let controller = UIViewController()
        let child = UIView()
        controller.view.addSubview(child)

        let chain = ViewContext.responderChain(from: child)

        XCTAssertEqual(chain.first, "UIView")
        XCTAssertTrue(chain.contains("UIViewController"))
        XCTAssertLessThan(chain.firstIndex(of: "UIView") ?? .max,
                          chain.firstIndex(of: "UIViewController") ?? .max)
    }

    func testAViewThatIsNotFirstResponderSaysSo() {
        XCTAssertFalse(ViewContext.isFirstResponder(UIView()))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/ViewPositionMapTests -only-testing:ScytherTests/ViewContextTests`. Expected: compile failure — the types do not exist.

- [ ] **Step 3: Write `ViewPositionMap`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewPositionMap.swift`:

```swift
//
//  ViewPositionMap.swift
//  Scyther
//

#if !os(macOS)
import CoreGraphics

/// Places a view's frame on a scaled outline of the screen.
///
/// Pure, because this is arithmetic with a right answer and a `View`'s drawing is not something
/// a test can inspect. The page draws what this returns and decides nothing.
enum ViewPositionMap {
    /// The screen outline, letterboxed to fit `box` while keeping the window's proportions.
    ///
    /// Stretching the outline to fill the box would misreport every position on it, which is the
    /// one thing this drawing exists to get right.
    ///
    /// - Parameters:
    ///   - windowBounds: The window the frames are measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The outline's rect within `box`, or `.zero` for a degenerate window.
    static func outlineRect(forWindowBounds windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let scale = min(box.width / windowBounds.width, box.height / windowBounds.height)
        let size = CGSize(width: windowBounds.width * scale, height: windowBounds.height * scale)
        return CGRect(x: (box.width - size.width) / 2,
                      y: (box.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// A window-space frame mapped onto the outline.
    ///
    /// A frame outside the window maps outside the outline and is **not** clamped to its edge:
    /// a view nine hundred points below the fold is not the same answer as a view at the bottom
    /// of the screen, and drawing them identically would say it was.
    ///
    /// - Parameters:
    ///   - frameInWindow: The view's frame in window space.
    ///   - windowBounds: The window the frame is measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The frame's rect within `box`, or `.zero` for a degenerate window.
    static func rect(for frameInWindow: CGRect, windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let outline = outlineRect(forWindowBounds: windowBounds, in: box)
        let scale = min(box.width / windowBounds.width, box.height / windowBounds.height)

        return CGRect(x: outline.minX + (frameInWindow.minX - windowBounds.minX) * scale,
                      y: outline.minY + (frameInWindow.minY - windowBounds.minY) * scale,
                      width: frameInWindow.width * scale,
                      height: frameInWindow.height * scale)
    }
}
#endif
```

- [ ] **Step 4: Write `ViewThumbnailRenderer`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewThumbnailRenderer.swift`:

```swift
//
//  ViewThumbnailRenderer.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Renders a single view to an image, on demand.
///
/// **This is the one expensive thing the inspector does.** Rendering a view is rasterisation, on
/// the same list of costs as the accessibility audit's recursive subtree walk. It runs for the
/// selected view only — never per row, never eagerly for the tree — is capped, and does not wait
/// for screen updates.
@MainActor
enum ViewThumbnailRenderer {
    /// The largest image produced, in points. A larger view is scaled to fit, so a full-screen
    /// view costs no more than a button.
    static let maximumSize = CGSize(width: 512, height: 512)

    /// What there is to show for a view.
    ///
    /// The three failure cases are distinct on purpose: the page says *which* it is, rather than
    /// presenting an empty box as though it were the view's true appearance.
    enum Thumbnail: Equatable {
        /// A rendered image.
        case image(UIImage)

        /// The view is invisible, so there is nothing to render.
        case hidden

        /// The view has no area, so there is nothing to render.
        case zeroSize

        /// The view has been deallocated since the snapshot was taken.
        case unavailable
    }

    /// Renders `view`, or says why it cannot.
    ///
    /// - Parameters:
    ///   - view: The live view, or `nil` when the snapshot's weak reference has gone.
    ///   - isHidden: The node's hidden flag.
    ///   - isZeroSize: The node's zero-size flag.
    /// - Returns: The image, or the reason there is not one.
    static func thumbnail(of view: UIView?, isHidden: Bool, isZeroSize: Bool) -> Thumbnail {
        guard let view else { return .unavailable }
        guard !isZeroSize, view.bounds.width > 0, view.bounds.height > 0 else { return .zeroSize }
        guard !isHidden else { return .hidden }

        let scale = min(1, min(maximumSize.width / view.bounds.width,
                               maximumSize.height / view.bounds.height))
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            view.layer.render(in: context.cgContext)
        }
        return .image(image)
    }
}
#endif
```

`layer.render(in:)` is used rather than `drawHierarchy(in:afterScreenUpdates:)` deliberately: the latter can force a screen update and is the slower, more disruptive of the two. It does not capture visual effects such as blur, which is an acceptable loss for a thumbnail.

- [ ] **Step 5: Write `ViewContext`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewContext.swift`:

```swift
//
//  ViewContext.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Where a view sits in the app, beyond its geometry.
///
/// Often the fastest answer to "which screen is this actually from" in a deep navigation stack,
/// and much cheaper than the Auto Layout inspection this feature deliberately does not do.
@MainActor
enum ViewContext {
    /// The nearest view controller above `view` in the responder chain.
    ///
    /// Nearest rather than outermost: in a nested container the answer to "which screen is this"
    /// is the child, not the navigation controller that happens to contain everything.
    ///
    /// - Parameter view: The view to trace from.
    /// - Returns: The owning controller, or `nil` for a view not yet in a chain.
    static func owningController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view.next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    /// The class names of the responder chain starting at `view`, nearest first.
    ///
    /// - Parameter view: The view to trace from.
    /// - Returns: Class names, beginning with the view's own.
    static func responderChain(from view: UIView) -> [String] {
        var names: [String] = []
        var responder: UIResponder? = view
        while let current = responder {
            names.append(String(describing: type(of: current)))
            responder = current.next
        }
        return names
    }

    /// Whether the view is currently first responder.
    ///
    /// - Parameter view: The view to ask.
    /// - Returns: `true` when it holds first responder status.
    static func isFirstResponder(_ view: UIView) -> Bool {
        view.isFirstResponder
    }
}
#endif
```

- [ ] **Step 6: Run the tests to verify they pass**

Run with `-only-testing:ScytherTests/ViewPositionMapTests -only-testing:ScytherTests/ViewContextTests`. Expected: 12 tests, 0 failures.

- [ ] **Step 7: Run the full suite, then commit**

```bash
git add Sources/Scyther/Features/ViewHierarchy/ Tests/ScytherTests/Features/ViewPositionMapTests.swift Tests/ScytherTests/Features/ViewContextTests.swift
git commit -m "Add the inspector's position map, thumbnail and context

The position map letterboxes rather than stretching, and lets an off-screen
view map off the outline instead of clamping it to the edge — a view nine
hundred points below the fold is not the same answer as one at the bottom
of the screen."
```

---

### Task 4: The detail page

**Files:**
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewDetailViewModel.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewDetailView.swift`
- Create: `Scripts/localization/strings/ViewHierarchy.json`
- Modify: `Sources/Scyther/Resources/Localizable.xcstrings` (generated)
- Test: `Tests/ScytherTests/Features/ViewDetailViewModelTests.swift`

**Interfaces:**
- Consumes: `ViewNode` (Task 1), `ViewHierarchySnapshot` (Task 2), `ViewPositionMap`, `ViewThumbnailRenderer`, `ViewContext` (Task 3).
- Produces: `@MainActor final class ViewDetailViewModel: ViewModel` with `init(node: ViewNode, snapshot: ViewHierarchySnapshot, windowBounds: CGRect)`, `@Published private(set) var thumbnail: ViewThumbnailRenderer.Thumbnail`, `@Published private(set) var geometry: [DetailField]`, `appearance: [DetailField]`, `context: [DetailField]`, `behaviour: [DetailField]`, and `struct DetailField: Identifiable, Equatable { let id: String; let label: String; let value: String }`. `struct ViewDetailView: View` with `init(node: ViewNode, snapshot: ViewHierarchySnapshot, windowBounds: CGRect)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewDetailViewModelTests.swift`:

```swift
//
//  ViewDetailViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewDetailViewModelTests: XCTestCase {

    private let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func makeModel(configure: (UIView) -> Void = { _ in }) -> ViewDetailViewModel {
        let root = UIView(frame: windowBounds)
        let subject = UIView(frame: CGRect(x: 16, y: 100, width: 200, height: 44))
        configure(subject)
        root.addSubview(subject)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        return ViewDetailViewModel(node: snapshot.root.children[0],
                                   snapshot: snapshot,
                                   windowBounds: windowBounds)
    }

    func testGeometryReportsTheFrameInWindowSpace() async {
        let model = makeModel()
        await model.onFirstAppear()

        let frame = model.geometry.first { $0.id == "frame" }
        XCTAssertEqual(frame?.value, "16, 100, 200 × 44")
    }

    func testAppearanceReportsAlphaAndHidden() async {
        let model = makeModel { $0.alpha = 0.5 }
        await model.onFirstAppear()

        XCTAssertEqual(model.appearance.first { $0.id == "alpha" }?.value, "0.5")
        XCTAssertNotNil(model.appearance.first { $0.id == "hidden" })
    }

    func testAVisibleViewRendersAThumbnail() async {
        let model = makeModel { $0.backgroundColor = .red }
        await model.onFirstAppear()

        guard case .image = model.thumbnail else {
            return XCTFail("a visible, sized view should render")
        }
    }

    /// The honesty rule: say which of the three reasons there is nothing to show, rather than
    /// presenting an empty box as though it were the view's appearance.
    func testAHiddenViewReportsHiddenRatherThanRendering() async {
        let model = makeModel { $0.isHidden = true }
        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .hidden)
    }

    func testAZeroSizeViewReportsZeroSize() async {
        let root = UIView(frame: windowBounds)
        let collapsed = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        root.addSubview(collapsed)
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let model = ViewDetailViewModel(node: snapshot.root.children[0],
                                        snapshot: snapshot,
                                        windowBounds: windowBounds)

        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .zeroSize)
    }

    func testAViewDeallocatedSinceTheSnapshotReportsUnavailable() async {
        let root = UIView(frame: windowBounds)
        var subject: UIView? = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        root.addSubview(subject!)
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let node = snapshot.root.children[0]

        subject!.removeFromSuperview()
        subject = nil

        let model = ViewDetailViewModel(node: node, snapshot: snapshot, windowBounds: windowBounds)
        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .unavailable)
    }

    func testContextNamesTheOwningController() async {
        let controller = UIViewController()
        controller.view.frame = windowBounds
        let subject = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        controller.view.addSubview(subject)

        let snapshot = ViewHierarchyWalker.snapshot(of: controller.view, windowBounds: windowBounds)
        let model = ViewDetailViewModel(node: snapshot.root.children[0],
                                        snapshot: snapshot,
                                        windowBounds: windowBounds)
        await model.onFirstAppear()

        XCTAssertEqual(model.context.first { $0.id == "controller" }?.value, "UIViewController")
    }

    func testEveryFieldCarriesADistinctIdentity() async {
        let model = makeModel()
        await model.onFirstAppear()

        let ids = (model.geometry + model.appearance + model.context + model.behaviour).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate ids would collapse rows in the List")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/ViewDetailViewModelTests`. Expected: compile failure.

- [ ] **Step 3: Add the localisation fragment**

Create `Scripts/localization/strings/ViewHierarchy.json`. Every key below must carry all twelve languages using exactly these codes: `fr`, `de`, `es`, `it`, `pt-BR`, `nl`, `ja`, `zh-Hans`, `zh-Hant`, `ko`, `ru`, `ar`.

**Before adding any key, run `grep -rn '"<key>"' Scripts/localization/strings/` — `build_catalog.py` hard-fails on a key defined in two fragments.** `Done`, `Search`, `Cancel` and similar short words are very likely already owned by another fragment; if a key collides, reword this feature's copy rather than moving the other fragment's key.

The exact structure, with two keys worked in full as the pattern for the rest:

```json
{
  "View Hierarchy": {
    "comment": "Menu row and page title for the view hierarchy inspector",
    "fr": "Hiérarchie des vues",
    "de": "View-Hierarchie",
    "es": "Jerarquía de vistas",
    "it": "Gerarchia delle viste",
    "pt-BR": "Hierarquia de views",
    "nl": "Weergavehiërarchie",
    "ja": "ビュー階層",
    "zh-Hans": "视图层级",
    "zh-Hant": "視圖層級",
    "ko": "뷰 계층",
    "ru": "Иерархия представлений",
    "ar": "التسلسل الهرمي للعروض"
  },
  "Nothing to show — this view is hidden": {
    "comment": "Shown in place of a thumbnail when the selected view is invisible",
    "fr": "Rien à afficher — cette vue est masquée",
    "de": "Nichts anzuzeigen – diese View ist ausgeblendet",
    "es": "Nada que mostrar: esta vista está oculta",
    "it": "Niente da mostrare — questa vista è nascosta",
    "pt-BR": "Nada a exibir — esta view está oculta",
    "nl": "Niets te tonen — deze weergave is verborgen",
    "ja": "表示するものがありません — このビューは非表示です",
    "zh-Hans": "无内容可显示 — 此视图已隐藏",
    "zh-Hant": "無內容可顯示 — 此視圖已隱藏",
    "ko": "표시할 내용 없음 — 이 뷰는 숨겨져 있습니다",
    "ru": "Нечего показать — это представление скрыто",
    "ar": "لا شيء لعرضه — هذا العرض مخفي"
  }
}
```

The complete key list this feature needs, all in the same shape:

- Page and navigation: `View Hierarchy`
- Search: `Search classes and text`, `No views match %@`
- Badges: `hidden`, `zero size`, `off screen`
- Snapshot header: `%lld views`, `Snapshot taken %@`
- Detail section headers: `Where it is`, `Geometry`, `Appearance`, `Context`, `Behaviour`
- Thumbnail states: `Nothing to show — this view is hidden`, `Nothing to show — this view has zero size`, `This view no longer exists`
- Field labels: `Frame`, `Bounds`, `Centre`, `Safe area`, `Layout margins`, `Alpha`, `Hidden`, `Background`, `Corner radius`, `Clips to bounds`, `Content mode`, `Text content`, `Font`, `Text colour`, `Controller`, `Responder chain`, `First responder`, `Interaction`, `Tag`
- Values: for booleans and empty values, **do not add `Yes`, `No` or `None` — all three already exist**
  and `build_catalog.py` will hard-fail. `Yes` and `No` are owned by `DataBrowsers.json`, `None` by
  `NetworkRules.json`, and `Text` by `Shared.json`. Reuse the existing keys by calling
  `localized("Yes")`, `localized("No")` and `localized("None")` — a key lives in one fragment but
  resolves from the single flat catalogue, so calling it from this feature is correct and is what
  the Layout Ruler did with `Done`. For the same reason, name this feature's text field label
  something other than `Text` — `Text content` — since `Shared.json` owns `Text`.

  Verified by `grep -rn '"<key>"' Scripts/localization/strings/` while this plan was written; run it
  again for every other key before adding it, in case a fragment has moved since.

Note `%lld` for counts and `%@` for interpolated strings, formatted with `String(format: localized("..."), value)`. Never build a key by interpolation.

Then rebuild the catalogue:

```bash
python3 Scripts/localization/build_catalog.py
```

- [ ] **Step 4: Write `ViewDetailViewModel`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewDetailViewModel.swift`. It subclasses `ViewModel` (see `Sources/Scyther/Shared/.../ViewModel.swift` — lifecycle is `setup()`, `onFirstAppear()`, `onAppear()`, `onSubsequentAppear()`), and populates its published arrays in `onFirstAppear()`.

Requirements, each of which has a test above:

- `DetailField` carries a **stable, distinct `id`** — `"frame"`, `"bounds"`, `"alpha"`, `"controller"`, and so on — because duplicate ids collapse rows in a `List`.
- `geometry` reports `frame` as `"16, 100, 200 × 44"` (origin x, origin y, width × height, using `×` not `x`), plus `bounds`, `centre`, safe-area insets and layout margins read from the live view when it still exists.
- `appearance` reports `alpha`, `hidden`, `background`, `corner radius`, `clips to bounds`, `content mode`, and for a view carrying text, its `text`, `font` and `text colour`. **Alpha is formatted with `String(format: "%g", alpha)`** — `"0.5"`, `"1"`, `"0.05"` — so the value has no trailing zeros and Task 4's test asserts against a stated format rather than a guessed one.
- `context` reports the owning controller's class name via `ViewContext.owningController(of:)`, the responder chain via `ViewContext.responderChain(from:)`, and first-responder status.
- `behaviour` reports `isUserInteractionEnabled` and `tag`.
- `thumbnail` is produced **once**, in `onFirstAppear()`, by `ViewThumbnailRenderer.thumbnail(of:isHidden:isZeroSize:)`, passing `snapshot.view(for: node.id)`. Never in a computed property, which would re-rasterise on every SwiftUI re-render.
- Fields whose value needs the live view and whose view has gone are omitted rather than shown as blank.
- Every user-facing label goes through `localized(_:)`.

- [ ] **Step 5: Write `ViewDetailView`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewDetailView.swift`: a `List` of `Section`s — `Where it is`, `Geometry`, `Appearance`, `Context`, `Behaviour` — using stock `LabeledContent` for every field row.

The `Where it is` section holds the thumbnail beside the position map:

- The thumbnail is a stock `Image` for `.image`, and for the other three cases a `Text` carrying the matching localised sentence.
- The position map is a `Canvas` drawing two rectangles: the outline from `ViewPositionMap.outlineRect(forWindowBounds:in:)` stroked in `.secondary`, and the view's rect from `ViewPositionMap.rect(for:windowBounds:in:)` filled in `.green`. Pass the `Canvas`'s own size as `box`.
- The thumbnail is decorative: `.accessibilityHidden(true)`. The position map takes an `.accessibilityLabel` naming the frame, since a drawing is not readable.
- `.navigationTitle(node.className)`.

- [ ] **Step 6: Run the tests, then the full suite**

Expected: 8 new tests pass; whole suite green.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/ViewHierarchy/ Tests/ScytherTests/Features/ViewDetailViewModelTests.swift Scripts/localization/strings/ViewHierarchy.json Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Add the inspector's detail page

Thumbnail, position map, geometry, appearance and responder context. The
three reasons a view cannot be rendered are reported separately, because an
empty box reads as the view's appearance rather than as its absence."
```

---

### Task 5: The tree page and the menu row

**Files:**
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyViewModel.swift`
- Create: `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyView.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuItem.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuSection.swift:98-101`
- Modify: `Sources/Scyther/Features/Menu/MenuView.swift`
- Modify: `Sources/Scyther/Features/Menu/MenuSearchIndex.swift:124-132`
- Modify: `Tests/ScytherTests/Features/MenuItemTests.swift:126`
- Test: `Tests/ScytherTests/Features/ViewHierarchyViewModelTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `@MainActor final class ViewHierarchyViewModel: ViewModel`, `struct ViewHierarchyView: View`, `MenuItem.viewHierarchy`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/ViewHierarchyViewModelTests.swift`:

```swift
//
//  ViewHierarchyViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewHierarchyViewModelTests: XCTestCase {

    private let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func makeTree() -> UIView {
        let root = UIView(frame: windowBounds)
        let scroll = UIScrollView(frame: windowBounds)
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
        label.text = "GraphQL Demo"
        scroll.addSubview(label)
        root.addSubview(scroll)
        return root
    }

    func testTheRootIsExpandedToTheFirstTwoLevelsOnLoad() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)

        XCTAssertTrue(model.isExpanded(model.snapshotRoot!))
        XCTAssertTrue(model.isExpanded(model.snapshotRoot!.children[0]))
        XCTAssertFalse(model.isExpanded(model.snapshotRoot!.children[0].children[0]),
                       "the third level starts collapsed")
    }

    func testSearchingProducesMatchesWithTheirPaths() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)
        model.searchText = "GraphQL"

        XCTAssertEqual(model.matches.count, 1)
        XCTAssertEqual(model.matches[0].node.className, "UILabel")
        XCTAssertEqual(model.matches[0].path, ["UIView", "UIScrollView"])
    }

    func testClearingTheSearchReturnsToTheTree() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)
        model.searchText = "GraphQL"
        model.searchText = ""

        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    func testRefreshingTakesANewSnapshot() {
        let root = makeTree()
        let model = ViewHierarchyViewModel()
        model.load(from: root, windowBounds: windowBounds)
        let firstCount = model.nodeCount

        root.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        model.load(from: root, windowBounds: windowBounds)

        XCTAssertEqual(model.nodeCount, firstCount + 1)
    }

    func testTogglingExpansionFlipsIt() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)
        let deep = model.snapshotRoot!.children[0].children[0]

        model.toggleExpansion(deep)

        XCTAssertTrue(model.isExpanded(deep))
    }
}
```

Then update `Tests/ScytherTests/Features/MenuItemTests.swift:126`: `XCTAssertEqual(MenuItem.allStaticCases.count, 48)` — it is currently `47`.

- [ ] **Step 2: Run to verify they fail**

Expected: compile failure for the new type, and `MenuItemTests` failing on the count until the case is added.

- [ ] **Step 3: Write `ViewHierarchyViewModel`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyViewModel.swift`, subclassing `ViewModel`:

- `@Published var searchText: String = ""`, with `matches` recomputed from `ViewNodeSearch.matches(for:in:)` whenever it or the snapshot changes. `isSearching` is `!searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
- `private(set) var snapshotRoot: ViewNode?`, `nodeCount: Int`, `takenAt: Date?`.
- `func load(from root: UIView, windowBounds: CGRect)` calls `ViewHierarchyWalker.snapshot(of:windowBounds:)` and resets expansion to depth ≤ 1.
- `func loadFromKeyWindow()` finds the key window and calls `load(from:windowBounds:)`; when there is no key window it sets an error state the page shows, matching the spec's edge case.
- `func isExpanded(_ node: ViewNode) -> Bool` / `func toggleExpansion(_ node: ViewNode)`, backed by a `Set<ObjectIdentifier>`.
- The snapshot is retained so `ViewDetailView` can be handed it.

- [ ] **Step 4: Write `ViewHierarchyView`**

Create `Sources/Scyther/Features/ViewHierarchy/ViewHierarchyView.swift`:

- A `List`. When not searching it shows the tree, each row indented by `ViewNode.indentationLevel(forDepth:)` × a fixed step, with a stock `DisclosureGroup` for nodes with children. When searching it shows one row per `ViewNodeSearch.Match`, the ancestor path above the class name in `.caption`.
- Each row shows the class name, `"\(Int(size.width)) × \(Int(size.height))"`, and badges for hidden / zero-size / off-screen. Each badge's word goes through `localized(_:)` and is included in the row's `.accessibilityLabel`, so a badge is spoken and not only seen.
- `.searchable(text: $viewModel.searchText, prompt: localized("Search classes and text"))`
- `.refreshable { viewModel.loadFromKeyWindow() }`
- `.navigationTitle(localized("View Hierarchy"))`
- A header showing `String(format: localized("%lld views"), viewModel.nodeCount)` and the snapshot's age.
- An empty state when a search matches nothing, naming the query. **`ContentUnavailableView` is iOS 17** — either `#available`-guard it or use a plain `Text`, matching how `CookieBrowserView` handles its own no-results case.
- Selecting a row pushes `ViewDetailView(node:snapshot:windowBounds:)` via `NavigationLink`.
- `.onFirstAppear { await viewModel.onFirstAppear() }`, with `onFirstAppear()` calling `loadFromKeyWindow()`.

- [ ] **Step 5: Wire the menu row**

Five edits, all forced by adding a `MenuItem` case — the compiler finds four of them, and the fifth is the one that silently ships a bug:

1. `MenuItem.swift` — add `viewHierarchy` to the `case` list beside `.layoutRuler`, to `allStaticCases`, `id` (`"viewHierarchy"`), `title` (`localized("View Hierarchy")`), and `icon` (`"list.bullet.indent"` — check it is not already used by another row before committing to it).
2. `MenuSection.swift:98-101` — add `.viewHierarchy` to the `uiux` section's items, after `.layoutRuler`.
3. `MenuView.swift` — add `case .viewHierarchy: ViewHierarchyView()` to `destination(for:)`, and a navigation row in the main row builder.
4. `MenuSearchIndex.swift:124-132` — add `.viewHierarchy: ["views", "tree", "inspector", "subviews", "hierarchy", "frames"]`.
5. **`MenuView.searchResultRow(for:)`** — this switch has no `default` case that navigates correctly for new items: anything without a case falls through to `navigationResult` → `destination(for:)`. Since `.viewHierarchy` **is** a navigation row, falling through is correct here — but verify it by searching for "hierarchy" in the running app and confirming the row pushes the page rather than a blank one. This project has already shipped that defect once.

- [ ] **Step 6: Run the tests, then the full suite**

Expected: 5 new tests pass, `MenuItemTests` passes at 48, whole suite green.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/ViewHierarchy/ Sources/Scyther/Features/Menu/ Tests/ScytherTests/Features/
git commit -m "Add the view hierarchy page and its menu row

Collapsed to two levels with search over class names and carried text,
because most of a 148-node tree is framework scaffolding you did not write."
```

---

### Task 6: Documentation and verification on device

**Files:**
- Modify: `README.md`
- Modify: `Sources/Scyther/Scyther.docc/UIDebuggingTools.md`

- [ ] **Step 1: Update the README**

Add the inspector to the UI/UX feature list: what it shows, that it is a **snapshot** refreshed by pulling, and that it is read-only. State that it skips Scyther's own views, so the tree is the host app's hierarchy and nothing else.

- [ ] **Step 2: Update the DocC article**

Add the inspector to `UIDebuggingTools.md`, and record the two things the next reader will otherwise undo:

- **Why the tree is a snapshot rather than live** — UIKit has no clean change signal, so the alternatives are a timer or swizzling layout, and a full walk on every layout pass is the hot-path mistake the accessibility audit taught in 4.3.0.
- **Why `ViewNode` holds no `UIView`** — a tree that strongly held views would keep an entire screen alive for as long as the page was open; the weak side table exists so the thumbnail can still work.

Verify DocC builds with no new warnings:

```bash
xcodebuild docbuild -scheme Scyther -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' -derivedDataPath ./docbuild
```

- [ ] **Step 3: Build and install the example app**

```bash
cd Example && xcodebuild build -project ScytherExample.xcodeproj -scheme ScytherExample \
  -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-inspector
xcrun simctl install 0EEED0FF-A025-468E-9466-3BDE708B41B0 /tmp/dd-inspector/Build/Products/Debug-iphonesimulator/ScytherExample.app
xcrun simctl launch 0EEED0FF-A025-468E-9466-3BDE708B41B0 com.scyther.example
```

Drive it with `/Applications/RocketSim.app/Contents/Helpers/rocketsim` — the shape is `rocketsim interact tap 200 400`, `rocketsim interact swipe --from x,y --to x,y`, `rocketsim screenshot > file.png`. Coordinates are in points; the portrait canvas is 402 × 874. Avoid `rocketsim elements`, whose output is enormous. Prefer `xcrun simctl io <udid> screenshot <path>` for captures — RocketSim's screenshot has returned a stale frame in this project before.

- [ ] **Step 4: Walk the spec's seven checks**

From the spec's "Verification on device" section, in order, reporting what you saw for each:

1. The tree matches the screen behind it — tab bar, list, and section cards present and nested correctly.
2. Searching for text in a label finds it, shows its ancestor path, and opens the right view.
3. A visible view's thumbnail looks like the view and the position map puts it where it actually is.
4. A hidden view says it is hidden rather than showing an empty box.
5. No Scyther view appears anywhere in the tree.
6. Navigating the host app and reopening the page shows a snapshot of the new screen.
7. Scrolling the tree on a long list stays smooth — no rasterisation happens while scrolling.

**Open and read every screenshot before filing it.** A screenshot is evidence only after someone has looked at it; an earlier plan in this project had a round file a screenshot of a failure as proof of a fix.

- [ ] **Step 5: Commit**

```bash
git add README.md Sources/Scyther/Scyther.docc/UIDebuggingTools.md
git commit -m "Document the view hierarchy inspector"
```

---

## Self-Review

**Spec coverage.** The tree and its badges are Tasks 2 and 5; search with ancestor paths is Tasks 1 and 5; the snapshot-plus-refresh model is Tasks 2 and 5; the detail page's four groups are Task 4; the thumbnail and position map are Tasks 3 and 4; responder context is Task 3; the walk's cost rules and the Scyther skip are Task 2, with an explicit accessibility-spy test; the weak side table is Task 2; localisation is Task 4; menu wiring is Task 5; documentation and the seven device checks are Task 6.

**Edge-case table coverage.** No key window → Task 5's `loadFromKeyWindow()`. Deallocated view → Task 3's `.unavailable` and Task 4's test. Hidden and zero-size → Tasks 2 and 4. Off-screen → Tasks 2 and 3, including the "maps outside the outline" test. Deep hierarchy → Task 1's indentation cap. Search matching nothing → Tasks 1 and 5. Rotation → no code; the snapshot header already states its age, and Task 6 check 6 exercises re-walking.

**Placeholder scan.** No TBDs. The one place this plan describes rather than dictates is the localisation fragment's twelve translations per key: the exact structure, the exact language codes, the complete key list, the collision check and the rebuild command are all given, and translating twenty-six keys inline would be disproportionate rather than more precise.

**Type consistency.** `ViewNode`'s members are used with the same names in Tasks 2, 4 and 5. `ViewHierarchySnapshot.view(for:)` is defined in Task 2 and consumed in Task 4. `ViewThumbnailRenderer.thumbnail(of:isHidden:isZeroSize:)` is defined and consumed with that exact signature. `ViewPositionMap.outlineRect(forWindowBounds:in:)` and `rect(for:windowBounds:in:)` match between Task 3's tests, its implementation, and Task 4's view. `ViewContext`'s three functions match their tests.

**One correction made during self-review.** `ViewContext.swift` is not in the spec's architecture table; the spec folds responder context into the detail page. It is split out here because `owningController(of:)` and `responderChain(from:)` have right answers worth testing directly, and a view model is a poor place to hide them. This is an addition to the spec's file list, not a change to its behaviour.
