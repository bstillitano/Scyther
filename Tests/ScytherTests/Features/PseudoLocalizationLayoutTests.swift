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
/// device. Hence ``testNothingSwiftUIHostsIsEverWrittenTo``, which is the assertion that would
/// have caught it.
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

    /// The assertion the earlier fix would have failed: the walk must not write to a view SwiftUI
    /// hosts, even one the appearance proxy stamped, because forcing a direction on a hosting view
    /// mirrors the text it renders.
    func testNothingSwiftUIHostsIsEverWrittenTo() {
        let hosting = HostingController()
        let views = hierarchy(hosting, setTo: stamped)
        PseudoLocalizationLayout.clearForcedDirection(in: [views.root])
        XCTAssertEqual(views.root.semanticContentAttribute, stamped)
        XCTAssertEqual(views.child.semanticContentAttribute, stamped)
        XCTAssertEqual(views.grandchild.semanticContentAttribute, stamped)
    }

    func testTheWalkStopsAtAHostingViewWhileClearingTheChromeAroundIt() {
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
        XCTAssertEqual(hosting.view.semanticContentAttribute, stamped)
        XCTAssertEqual(hosted.semanticContentAttribute, stamped)
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
