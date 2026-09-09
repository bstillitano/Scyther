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

    /// Keeps the walked hierarchy alive for the length of the test.
    ///
    /// The snapshot's side table is weak on purpose, so a tree left to go out of scope at the end
    /// of the statement that walked it would be gone before the assertions ran, and every test
    /// here would quietly be exercising the deallocated case instead of the one it names.
    private var hierarchyRoot: UIView?

    /// Holds the window the key-window tests hand to the view model, for the same reason.
    private var window: UIWindow?

    private func makeTree() -> UIView {
        let root = UIView(frame: windowBounds)
        let scroll = UIScrollView(frame: windowBounds)
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
        label.text = "GraphQL Demo"
        scroll.addSubview(label)
        root.addSubview(scroll)
        hierarchyRoot = root
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

    /// The tree the page draws: the expanded part of the hierarchy, flattened, parents first.
    ///
    /// A collapsed node's children are not merely hidden — they are not in the list at all, which
    /// is the whole point of opening on two levels rather than on a screen of scaffolding.
    func testTheVisibleTreeStopsAtCollapsedNodes() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)

        XCTAssertEqual(model.visibleNodes.map(\.className), ["UIView", "UIScrollView", "UILabel"])

        model.toggleExpansion(model.snapshotRoot!.children[0])

        XCTAssertEqual(model.visibleNodes.map(\.className), ["UIView", "UIScrollView"],
                       "a closed node keeps its own row and drops its subtree")

        model.toggleExpansion(model.snapshotRoot!)

        XCTAssertEqual(model.visibleNodes.map(\.className), ["UIView"])
    }

    /// A badge that is only a coloured lozenge tells a sighted developer a view is hidden and
    /// tells everyone else nothing, so the words belong in the row's spoken label too.
    func testARowsAccessibilityLabelSpeaksItsBadges() {
        let root = UIView(frame: windowBounds)
        let flagged = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        flagged.isHidden = true
        root.addSubview(flagged)
        hierarchyRoot = root

        let model = ViewHierarchyViewModel()
        model.load(from: root, windowBounds: windowBounds)
        let label = model.accessibilityLabel(for: model.snapshotRoot!.children[0])

        XCTAssertTrue(label.contains("UIView"), label)
        XCTAssertTrue(label.contains("0 × 44"), label)
        XCTAssertTrue(label.contains("hidden"), label)
        XCTAssertTrue(label.contains("zero size"), label)
    }

    func testLoadingWithNoKeyWindowReportsItRatherThanShowingAnEmptyTree() {
        let model = ViewHierarchyViewModel(keyWindow: { nil })

        model.loadFromKeyWindow()

        XCTAssertTrue(model.hasNoKeyWindow)
        XCTAssertNil(model.snapshotRoot)
        XCTAssertEqual(model.nodeCount, 0)
    }

    func testLoadingFromTheKeyWindowWalksIt() {
        let window = UIWindow(frame: windowBounds)
        window.addSubview(UIView(frame: windowBounds))
        self.window = window
        let model = ViewHierarchyViewModel(keyWindow: { window })

        model.loadFromKeyWindow()

        XCTAssertFalse(model.hasNoKeyWindow)
        XCTAssertEqual(model.snapshotRoot?.className, "UIWindow")
        XCTAssertEqual(model.windowBounds, windowBounds)
    }
}
