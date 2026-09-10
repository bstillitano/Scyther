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

    /// Searching publishes rows, each carrying the ancestor path that says which `UILabel` a hit
    /// is, and clearing the field goes back to the tree rather than to a list of everything.
    func testSearchingPublishesRowsWithTheirPathsAndClearingEmptiesThem() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)
        model.searchText = "GraphQL"

        XCTAssertEqual(model.matchRows.count, 1)
        XCTAssertEqual(model.matchRows[0].row.className, "UILabel")
        XCTAssertEqual(model.matchRows[0].path, ["UIView", "UIScrollView"])

        model.searchText = ""

        XCTAssertTrue(model.matchRows.isEmpty)
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

    /// The tree the page draws: the expanded part of the hierarchy, flattened, parents first.
    ///
    /// A collapsed node's children are not merely hidden — they are not in the list at all, which
    /// is the whole point of opening on two levels rather than on a screen of scaffolding.
    func testTheVisibleTreeStopsAtCollapsedNodes() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)

        XCTAssertEqual(model.visibleRows.map(\.row.className),
                       ["UIView", "UIScrollView", "UILabel"])

        model.toggleExpansion(model.snapshotRoot!.children[0])

        XCTAssertEqual(model.visibleRows.map(\.row.className), ["UIView", "UIScrollView"],
                       "a closed node keeps its own row and drops its subtree")

        model.toggleExpansion(model.snapshotRoot!)

        XCTAssertEqual(model.visibleRows.map(\.row.className), ["UIView"])
    }

    /// Toggling is the whole state machine the tree's disclosure button drives, so it is worth
    /// asserting it survives being driven both ways rather than only once.
    func testTogglingTwiceReturnsANodeToWhereItStarted() {
        let model = ViewHierarchyViewModel()
        model.load(from: makeTree(), windowBounds: windowBounds)
        let root = model.snapshotRoot!

        XCTAssertTrue(model.isExpanded(root))
        model.toggleExpansion(root)
        XCTAssertFalse(model.isExpanded(root))
        XCTAssertEqual(model.visibleRows.count, 1, "a closed root shows only itself")
        model.toggleExpansion(root)
        XCTAssertTrue(model.isExpanded(root))
        XCTAssertEqual(model.visibleRows.map(\.row.className),
                       ["UIView", "UIScrollView", "UILabel"])
    }

    /// Pull to refresh answers "what is on screen now"; it is not a request to close everything the
    /// developer has opened in a four-hundred-row tree.
    func testARefreshKeepsWhatTheDeveloperOpened() {
        let root = makeTree()
        let model = ViewHierarchyViewModel()
        model.load(from: root, windowBounds: windowBounds)
        model.toggleExpansion(model.snapshotRoot!.children[0])

        model.load(from: root, windowBounds: windowBounds)

        XCTAssertTrue(model.isExpanded(model.snapshotRoot!), "the root was left open")
        XCTAssertFalse(model.isExpanded(model.snapshotRoot!.children[0]),
                       "the node closed before the refresh is still closed after it")
        XCTAssertEqual(model.visibleRows.map(\.row.className), ["UIView", "UIScrollView"])
    }

    /// The rows the page draws, worked out once per change rather than per redraw — and what
    /// VoiceOver reads from one, which is asserted against the literal rather than against the
    /// function that built it. A badge that is only a coloured lozenge tells a sighted developer
    /// a view is hidden and tells everyone else nothing, so the words belong in the spoken label.
    func testARowCarriesWhatItsLineDrawsAndSpeaks() {
        let root = UIView(frame: windowBounds)
        let flagged = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        flagged.isHidden = true
        root.addSubview(flagged)
        hierarchyRoot = root

        let model = ViewHierarchyViewModel()
        model.load(from: root, windowBounds: windowBounds)

        XCTAssertEqual(model.visibleRows.map(\.row.className), ["UIView", "UIView"])
        let rootRow = model.visibleRows[0]
        XCTAssertTrue(rootRow.hasChildren)
        XCTAssertTrue(rootRow.isExpanded)
        XCTAssertEqual(rootRow.indentationLevel, 0)

        let childRow = model.visibleRows[1]
        XCTAssertFalse(childRow.hasChildren)
        XCTAssertEqual(childRow.indentationLevel, 1)
        XCTAssertEqual(childRow.row.size, "0 × 44")
        XCTAssertEqual(childRow.row.badges, [.hidden, .zeroSize])
        XCTAssertEqual(childRow.row.accessibilityLabel, "UIView, 0 × 44, hidden, zero size")
    }

    func testLoadingWithNoKeyWindowReportsItRatherThanShowingAnEmptyTree() {
        let model = ViewHierarchyViewModel(keyWindow: { nil })

        model.loadFromKeyWindow()

        XCTAssertTrue(model.hasNoKeyWindow)
        XCTAssertNil(model.snapshotRoot)
        XCTAssertEqual(model.nodeCount, 0)
        XCTAssertTrue(model.visibleRows.isEmpty)
    }

    /// A refresh that loses the key window must clear the rows the page draws, not only the state
    /// beside them.
    ///
    /// Starting from a *loaded* model is the whole point: a model that never loaded has nothing to
    /// leave behind, so a test that starts there cannot see the previous tree's rows survive.
    func testLosingTheKeyWindowClearsTheRowsThePageDraws() {
        let window = UIWindow(frame: windowBounds)
        window.addSubview(UIView(frame: windowBounds))
        self.window = window
        var available: UIWindow? = window
        let model = ViewHierarchyViewModel(keyWindow: { available })

        model.loadFromKeyWindow()
        model.searchText = "UIWindow"
        XCTAssertFalse(model.visibleRows.isEmpty, "the premise: something was drawn")
        XCTAssertFalse(model.matchRows.isEmpty)

        available = nil
        model.loadFromKeyWindow()

        XCTAssertTrue(model.hasNoKeyWindow)
        XCTAssertTrue(model.visibleRows.isEmpty,
                      "the page draws visibleRows, so a lost window has to clear them")
        XCTAssertTrue(model.matchRows.isEmpty)
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
