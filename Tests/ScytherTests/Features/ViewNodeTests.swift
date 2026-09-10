//
//  ViewNodeTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// The node itself: the indentation cap the tree draws with, and the real depth that survives it.
final class ViewNodeTests: XCTestCase {

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
