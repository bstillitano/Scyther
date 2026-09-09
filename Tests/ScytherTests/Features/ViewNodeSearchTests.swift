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

        XCTAssertEqual(ViewNode.indentationLevel(forDepth: deep.depth), 8,
                       "the row is drawn at the cap")
        XCTAssertEqual(deep.depth, 40,
                       "and the node still knows how deep it really is, which is what the search "
                       + "path relies on")
    }
}
