//
//  ScytherPresentationTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 6/9/2026.
//

@testable import Scyther
import SwiftUI
import UIKit
import XCTest

/// Covers the one question ``ScytherPresentation`` answers — is Scyther's own UI in front of the
/// app? — against chains of view controllers built by hand.
///
/// Nothing here presents anything. A real presentation needs a window, an animation and a run
/// loop, and none of them would make the answer any more true: the rule is entirely about the
/// shape of the chain, so the chain is what the tests hand it.
@MainActor
final class ScytherPresentationTests: XCTestCase {

    /// A stand-in for one of the app's own screens.
    private func appController() -> UIViewController {
        UIViewController()
    }

    /// A stand-in for one of Scyther's, hosted the way Scyther really hosts what it presents.
    private func scytherController() -> UIViewController {
        ScytherHostingController(rootView: Text(verbatim: "Scyther"))
    }

    /// Nothing presented is the ordinary case: the app is on screen on its own, and every check
    /// including contrast can be measured against it.
    func testAnEmptyChainIsNotCovered() {
        XCTAssertFalse(ScytherPresentation.isScytherPresented(in: []))
    }

    /// The app's own modals are the app. Skipping contrast under one would refuse to measure
    /// exactly the screens a developer most wants measured.
    func testTheAppsOwnModalIsNotScyther() {
        XCTAssertFalse(ScytherPresentation.isScytherPresented(in: [appController(), appController()]))
    }

    /// A screen Scyther presented directly — the audit report opened from the pill, or the
    /// held-request editor — dims everything behind it.
    func testAScytherControllerPresentedDirectlyIsCovering() {
        XCTAssertTrue(ScytherPresentation.isScytherPresented(in: [scytherController()]))
    }

    /// The menu is the case a single `is` check would miss: `Scyther.showMenu(from:)` presents a
    /// `UINavigationController`, which is UIKit's own class, and only its child gives it away.
    func testTheMenuInsideItsNavigationControllerIsCovering() {
        let navigation = UINavigationController(rootViewController: scytherController())
        XCTAssertTrue(ScytherPresentation.isScytherPresented(in: [navigation]))
    }

    /// An app screen presented over Scyther's menu does not undo the dimming Scyther put between
    /// the audit and the app, so every link in the chain is looked at rather than only the last.
    func testAnAppModalOverScythersMenuIsStillCovering() {
        let navigation = UINavigationController(rootViewController: scytherController())
        XCTAssertTrue(ScytherPresentation.isScytherPresented(in: [navigation, appController()]))
    }

    /// The root controller is the app under audit, not something covering it, so it is left out
    /// of the chain entirely.
    func testTheChainExcludesTheRootController() {
        XCTAssertTrue(ScytherPresentation.presentedControllers(over: appController()).isEmpty)
    }

    /// No window, no root, nothing presented — the answer is "not covered" rather than a crash.
    func testTheChainOverNothingIsEmpty() {
        XCTAssertTrue(ScytherPresentation.presentedControllers(over: nil).isEmpty)
    }

    // MARK: - Which transform belongs to the presentation

    /// The measurement correction has to be the presentation's transform and not the app's, and
    /// the presenting view controller's root view is the line between them. A drawer, a zoom
    /// container or any other transform the app applies sits *below* that view, so it is not a
    /// candidate — the previous rule took the outermost transform anywhere in the chain and
    /// therefore deleted exactly those.
    func testATransformBelowThePresentingViewIsNotThePresentations() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let presenting = UIView(frame: window.bounds)
        window.addSubview(presenting)
        let drawer = UIView(frame: window.bounds)
        presenting.addSubview(drawer)
        drawer.transform = CGAffineTransform(scaleX: 0.83, y: 0.83)

        XCTAssertNil(ScytherPresentation.highestTransformedView(atOrAbove: presenting))
    }

    /// And what it does find: UIKit scales the presenting view controller's view, or a container
    /// it wraps it in, so the presenting view itself and everything above it are the candidates.
    func testTheTransformOnAndAboveThePresentingViewIsThePresentations() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let wrapper = UIView(frame: window.bounds)
        window.addSubview(wrapper)
        let presenting = UIView(frame: window.bounds)
        wrapper.addSubview(presenting)
        presenting.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)

        XCTAssertTrue(ScytherPresentation.highestTransformedView(atOrAbove: presenting) === presenting)

        wrapper.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        XCTAssertTrue(ScytherPresentation.highestTransformedView(atOrAbove: presenting) === wrapper)
    }

    /// A window's own transform moves the whole screen rather than the app inside it, so removing
    /// it would not be a correction of anything.
    func testAWindowsOwnTransformIsNeverThePresentations() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let presenting = UIView(frame: window.bounds)
        window.addSubview(presenting)

        XCTAssertNil(ScytherPresentation.highestTransformedView(atOrAbove: presenting))
    }
}
