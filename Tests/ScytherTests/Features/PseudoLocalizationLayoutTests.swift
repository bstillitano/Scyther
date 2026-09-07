//
//  PseudoLocalizationLayoutTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import SwiftUI
import UIKit
import XCTest

/// Covers the half of ``PseudoLocalizationLayout`` that resets the views Scyther owns.
///
/// The appearance proxy cannot be tested here — it is process-wide state with no reliable way to
/// read the applied value back — but the walk that undoes its work can be, because it takes the
/// views it should visit rather than going looking for windows. Every hierarchy below is real
/// `UIView`s under a real `UIViewController`, so the responder chain the ownership rule climbs is
/// the one UIKit builds rather than a stand-in for it.
@MainActor
final class PseudoLocalizationLayoutTests: XCTestCase {

    /// Stands in for a ``ScytherHostingController``: the marker is what ownership is decided by,
    /// and a plain controller carrying it exercises the same rule without needing SwiftUI to build
    /// a hosting view first.
    private final class OwnedController: UIViewController, ScytherPresentedUI { }

    /// The attribute a view stamped by the appearance proxy while the mode was on would be left
    /// holding once the mode is switched off — the state the fix exists to clear.
    private let stale: UISemanticContentAttribute = .forceRightToLeft

    /// A value neither switch position ever produces, so a view that still holds it was genuinely
    /// left alone rather than coincidentally reset to the value "off" happens to use.
    private let untouched: UISemanticContentAttribute = .forceLeftToRight

    // MARK: - Helpers

    /// A controller whose root view holds two nested subviews, all three stamped with `attribute`.
    private func hierarchy(
        _ controller: UIViewController,
        stampedWith attribute: UISemanticContentAttribute
    ) -> (root: UIView, child: UIView, grandchild: UIView) {
        let child = UIView()
        let grandchild = UIView()
        child.addSubview(grandchild)
        controller.view.addSubview(child)
        for view in [controller.view!, child, grandchild] {
            view.semanticContentAttribute = attribute
        }
        return (controller.view, child, grandchild)
    }

    // MARK: - Ownership

    func testAViewOwnedByAScytherControllerIsScythers() {
        let controller = OwnedController()
        let views = hierarchy(controller, stampedWith: .unspecified)
        XCTAssertTrue(PseudoLocalizationLayout.isScytherOwned(views.root))
        XCTAssertTrue(PseudoLocalizationLayout.isScytherOwned(views.grandchild))
    }

    func testAViewOwnedByTheAppIsNotScythers() {
        let controller = UIViewController()
        let views = hierarchy(controller, stampedWith: .unspecified)
        XCTAssertFalse(PseudoLocalizationLayout.isScytherOwned(views.root))
        XCTAssertFalse(PseudoLocalizationLayout.isScytherOwned(views.grandchild))
    }

    func testAContainerHostingAScytherControllerIsScythers() {
        let container = UIViewController()
        let scyther = OwnedController()
        container.addChild(scyther)
        container.view.addSubview(scyther.view)
        XCTAssertTrue(PseudoLocalizationLayout.isScytherOwned(container.view))
    }

    func testScythersOwnOverlayViewsAreScythers() {
        XCTAssertTrue(PseudoLocalizationLayout.isScytherOwned(TopLevelViewsWrapper()))
        XCTAssertTrue(PseudoLocalizationLayout.isScytherOwned(TopLevelView()))
    }

    // MARK: - Switching on

    func testSwitchingOnForcesRightToLeftOnEveryViewScytherOwns() {
        let controller = OwnedController()
        let views = hierarchy(controller, stampedWith: .unspecified)
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: true, in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, .forceRightToLeft)
        XCTAssertEqual(views.child.semanticContentAttribute, .forceRightToLeft)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, .forceRightToLeft)
    }

    // MARK: - Switching off

    func testSwitchingOffClearsEveryViewScytherOwns() {
        let controller = OwnedController()
        let views = hierarchy(controller, stampedWith: stale)
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: false, in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, .unspecified)
        XCTAssertEqual(views.child.semanticContentAttribute, .unspecified)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, .unspecified)
    }

    /// The defect as reported: on, then off, and the menu is still mirrored.
    func testSwitchingOnThenOffLeavesNothingOfScythersMirrored() {
        let controller = OwnedController()
        let views = hierarchy(controller, stampedWith: .unspecified)
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: true, in: [views.root])
        for view in [views.root, views.child, views.grandchild] {
            XCTAssertEqual(view.semanticContentAttribute, .forceRightToLeft)
            XCTAssertEqual(view.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        }
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: false, in: [views.root])
        for view in [views.root, views.child, views.grandchild] {
            XCTAssertEqual(view.semanticContentAttribute, .unspecified)
            XCTAssertEqual(view.effectiveUserInterfaceLayoutDirection, .leftToRight)
        }
    }

    // MARK: - Descending from a window

    func testTheWalkFindsScythersViewsBelowViewsThatAreNot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let app = UIViewController()
        let appViews = hierarchy(app, stampedWith: untouched)
        window.rootViewController = app
        let scyther = OwnedController()
        let scytherViews = hierarchy(scyther, stampedWith: stale)
        window.addSubview(scyther.view)

        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: false, in: [window])

        XCTAssertEqual(scytherViews.root.semanticContentAttribute, .unspecified)
        XCTAssertEqual(scytherViews.child.semanticContentAttribute, .unspecified)
        XCTAssertEqual(scytherViews.grandchild.semanticContentAttribute, .unspecified)
        XCTAssertEqual(appViews.root.semanticContentAttribute, untouched)
        XCTAssertEqual(appViews.child.semanticContentAttribute, untouched)
        XCTAssertEqual(appViews.grandchild.semanticContentAttribute, untouched)
    }

    func testTheWalkReachesAContainersOwnViewsAndNotTheAppsAroundIt() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let app = UIViewController()
        let appViews = hierarchy(app, stampedWith: untouched)
        window.rootViewController = app

        let container = UIViewController()
        let bar = UIView()
        container.view.addSubview(bar)
        let scyther = OwnedController()
        container.addChild(scyther)
        container.view.addSubview(scyther.view)
        for view in [container.view!, bar, scyther.view!] {
            view.semanticContentAttribute = stale
        }
        window.addSubview(container.view)

        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: false, in: [window])

        XCTAssertEqual(bar.semanticContentAttribute, .unspecified)
        XCTAssertEqual(container.view.semanticContentAttribute, .unspecified)
        XCTAssertEqual(scyther.view.semanticContentAttribute, .unspecified)
        XCTAssertEqual(appViews.root.semanticContentAttribute, untouched)
    }

    // MARK: - The host app

    func testTheWalkLeavesTheHostAppsViewsAloneInBothDirections() {
        let controller = UIViewController()
        let views = hierarchy(controller, stampedWith: untouched)
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: true, in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, untouched)
        XCTAssertEqual(views.child.semanticContentAttribute, untouched)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, untouched)
        PseudoLocalizationLayout.applyToOwnedViews(rightToLeft: false, in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, untouched)
        XCTAssertEqual(views.child.semanticContentAttribute, untouched)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, untouched)
    }
}
#endif
