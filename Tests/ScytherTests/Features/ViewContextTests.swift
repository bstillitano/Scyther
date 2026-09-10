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
