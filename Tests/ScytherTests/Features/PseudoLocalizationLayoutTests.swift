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

/// Covers the half of ``PseudoLocalizationLayout`` that takes the appearance proxy's stamp back
/// off Scyther's own UIKit chrome.
///
/// The appearance proxy cannot be tested here — it is process-wide state with no reliable way to
/// read the applied value back — but the walk that undoes its work can be, because it takes the
/// views it should visit rather than going looking for windows. Every hierarchy below is real
/// `UIView`s under a real `UIViewController`, so the responder chain the classifier climbs is the
/// one UIKit builds rather than a stand-in for it.
///
/// What these tests can and cannot say is worth stating, because a previous version of this file
/// said more than it could. They can say which attribute a view carries afterwards. They cannot
/// say what the screen looks like: an earlier fix forced `.forceRightToLeft` onto Scyther's own
/// views, passed every assertion here, and rendered the menu's text reversed glyph by glyph on a
/// device.
///
/// The property that actually matters is therefore pinned directly rather than approximated. It is
/// not "hosted views are never written to" — that restriction was tried, and it left the reversed
/// text in place, since the stamps doing the damage were inside the hosting view. It is
/// ``testNothingIsEverForcedRightToLeft``: whatever this walk touches, it only ever *removes* a
/// forced direction.
@MainActor
final class PseudoLocalizationLayoutTests: XCTestCase {

    /// Stands in for a ``ScytherHostingController``: the marker is what the classifier decides on,
    /// and a plain controller carrying it exercises the same rule without needing SwiftUI to build
    /// a hosting view first.
    private final class HostingController: UIViewController, ScytherPresentedUI { }

    /// The attribute the appearance proxy leaves on a view built while the mode was on, and the
    /// only value the walk is allowed to overwrite.
    private let stamped: UISemanticContentAttribute = .forceRightToLeft

    /// A value the walk must never produce or overwrite, so a view still holding it was genuinely
    /// left alone rather than coincidentally reset to the value a clear happens to write.
    private let foreignValue: UISemanticContentAttribute = .forceLeftToRight

    // MARK: - Helpers

    /// A controller whose root view holds two nested subviews, all three set to `attribute`.
    @discardableResult
    private func hierarchy(
        _ controller: UIViewController,
        setTo attribute: UISemanticContentAttribute
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

    // MARK: - Roles

    func testAViewSwiftUIHostsForScytherIsRecognisedAsSuch() {
        let controller = HostingController()
        let views = hierarchy(controller, setTo: .unspecified)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: views.root), .swiftUIHosted)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: views.grandchild), .swiftUIHosted)
    }

    func testTheChromeAroundAPresentedScytherScreenIsRecognisedAsScythers() {
        let container = UIViewController()
        let bar = UIView()
        container.view.addSubview(bar)
        let hosting = HostingController()
        container.addChild(hosting)
        container.view.addSubview(hosting.view)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: container.view), .scytherChrome)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: bar), .scytherChrome)
    }

    func testScythersOwnOverlayViewsAreRecognisedAsScythers() {
        XCTAssertEqual(PseudoLocalizationLayout.role(of: TopLevelViewsWrapper()), .scytherChrome)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: TopLevelView()), .scytherChrome)
    }

    func testAViewOwnedByTheAppIsForeign() {
        let controller = UIViewController()
        let views = hierarchy(controller, setTo: .unspecified)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: views.root), .foreign)
        XCTAssertEqual(PseudoLocalizationLayout.role(of: views.grandchild), .foreign)
    }

    // MARK: - Clearing

    func testClearingTakesTheStampOffScythersChrome() {
        let container = UIViewController()
        let views = hierarchy(container, setTo: stamped)
        let hosting = HostingController()
        container.addChild(hosting)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, .unspecified)
        XCTAssertEqual(views.child.semanticContentAttribute, .unspecified)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, .unspecified)
    }

    /// `.unspecified` rather than `.forceLeftToRight`, so a genuinely Arabic device is handed back
    /// to its own language rather than pinned the other way.
    func testClearingWritesUnspecifiedRatherThanForcingTheOtherDirection() {
        let container = UIViewController()
        let views = hierarchy(container, setTo: stamped)
        let hosting = HostingController()
        container.addChild(hosting)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertNotEqual(views.root.semanticContentAttribute, .forceLeftToRight)
        XCTAssertEqual(views.root.effectiveUserInterfaceLayoutDirection, .leftToRight)
    }

    /// The walk exists to undo one specific stamp, so a view holding anything else was never this
    /// feature's to touch.
    func testClearingLeavesAViewHoldingAnyOtherValueAlone() {
        let container = UIViewController()
        let views = hierarchy(container, setTo: foreignValue)
        let hosting = HostingController()
        container.addChild(hosting)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, foreignValue)
        XCTAssertEqual(views.child.semanticContentAttribute, foreignValue)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, foreignValue)
    }

    /// The property that matters, and the one an attribute-by-attribute assertion kept missing:
    /// this walk only ever *removes* a forced direction. Forcing one is what made a hosting view
    /// mirror the text it renders, and nothing here may do it — to Scyther's views, to the app's,
    /// or to a view SwiftUI hosts.
    func testNothingIsEverForcedRightToLeft() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let app = UIViewController()
        let appViews = hierarchy(app, setTo: .unspecified)
        window.rootViewController = app

        let container = UIViewController()
        let chrome = hierarchy(container, setTo: foreignValue)
        let hosting = HostingController()
        container.addChild(hosting)
        container.view.addSubview(hosting.view)
        let hosted = hierarchy(hosting, setTo: .unspecified)
        window.addSubview(container.view)

        PseudoLocalizationLayout.clearForcedDirection(in: [window])
        PseudoLocalizationLayout.clearForcedDirection(in: [window])

        let everything = [window, appViews.root, appViews.child, appViews.grandchild,
                          chrome.root, chrome.child, chrome.grandchild,
                          hosted.root, hosted.child, hosted.grandchild]
        for view in everything {
            XCTAssertNotEqual(view.semanticContentAttribute, .forceRightToLeft)
        }
    }

    /// The check this round of the bug needed: a view stamped while the mode was on has to come
    /// back to `.unspecified` when it is switched off, and it makes no difference that the view
    /// sits inside a hosting view. That is where the reversed rows were.
    func testAStampedViewInsideAHostingViewIsCleared() {
        let hosting = HostingController()
        let collection = UIView()
        let cell = UIView()
        let label = UIView()
        cell.addSubview(label)
        collection.addSubview(cell)
        hosting.view.addSubview(collection)
        for view in [hosting.view!, collection, cell, label] {
            view.semanticContentAttribute = stamped
        }

        PseudoLocalizationLayout.clearForcedDirection(in: [hosting.view])

        XCTAssertEqual(hosting.view.semanticContentAttribute, .unspecified)
        XCTAssertEqual(collection.semanticContentAttribute, .unspecified)
        XCTAssertEqual(cell.semanticContentAttribute, .unspecified)
        XCTAssertEqual(label.semanticContentAttribute, .unspecified)
    }

    /// SwiftUI puts container view controllers of its own inside a hosting controller, so a cell's
    /// *nearest* controller is a private SwiftUI type that neither is nor contains anything of
    /// Scyther's. A classifier that stopped at the first controller called every row of the menu
    /// the app's and left the stamps in place.
    func testAViewUnderASwiftUIContainerControllerIsStillScythers() {
        let hosting = HostingController()
        let inner = UIViewController()
        hosting.addChild(inner)
        hosting.view.addSubview(inner.view)
        let cell = UIView()
        inner.view.addSubview(cell)
        cell.semanticContentAttribute = stamped

        XCTAssertEqual(PseudoLocalizationLayout.role(of: cell), .swiftUIHosted)
        PseudoLocalizationLayout.clearForcedDirection(in: [hosting.view])
        XCTAssertEqual(cell.semanticContentAttribute, .unspecified)
    }

    func testTheWalkClearsTheChromeAroundAHostingViewAndTheHostingViewItself() {
        let container = UIViewController()
        let bar = UIView()
        container.view.addSubview(bar)
        let hosting = HostingController()
        container.addChild(hosting)
        container.view.addSubview(hosting.view)
        let hosted = UIView()
        hosting.view.addSubview(hosted)
        for view in [container.view!, bar, hosting.view!, hosted] {
            view.semanticContentAttribute = stamped
        }

        PseudoLocalizationLayout.clearForcedDirection(in: [container.view])

        XCTAssertEqual(container.view.semanticContentAttribute, .unspecified)
        XCTAssertEqual(bar.semanticContentAttribute, .unspecified)
        XCTAssertEqual(hosting.view.semanticContentAttribute, .unspecified)
        XCTAssertEqual(hosted.semanticContentAttribute, .unspecified)
    }

    // MARK: - Descending from a window

    func testTheWalkFindsScythersChromeBelowViewsThatAreNot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let app = UIViewController()
        let appViews = hierarchy(app, setTo: stamped)
        window.rootViewController = app

        let container = UIViewController()
        let scytherViews = hierarchy(container, setTo: stamped)
        let hosting = HostingController()
        container.addChild(hosting)
        window.addSubview(container.view)

        PseudoLocalizationLayout.clearForcedDirection(in: [window])

        XCTAssertEqual(scytherViews.root.semanticContentAttribute, .unspecified)
        XCTAssertEqual(scytherViews.child.semanticContentAttribute, .unspecified)
        XCTAssertEqual(scytherViews.grandchild.semanticContentAttribute, .unspecified)
        XCTAssertEqual(appViews.root.semanticContentAttribute, stamped)
        XCTAssertEqual(appViews.child.semanticContentAttribute, stamped)
        XCTAssertEqual(appViews.grandchild.semanticContentAttribute, stamped)
    }

    /// The host app's UIKit views un-mirror on their next launch through the appearance proxy, the
    /// same way they mirror on one. Nothing here may bring that forward.
    func testTheWalkNeverWritesToTheHostAppsViews() {
        let controller = UIViewController()
        let views = hierarchy(controller, setTo: stamped)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, stamped)
        XCTAssertEqual(views.child.semanticContentAttribute, stamped)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, stamped)
    }

    func testClearingAnAlreadyClearHierarchyChangesNothing() {
        let container = UIViewController()
        let views = hierarchy(container, setTo: .unspecified)
        let hosting = HostingController()
        container.addChild(hosting)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, .unspecified)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, .unspecified)
    }
}
#endif
