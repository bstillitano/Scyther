//
//  HostedSwiftUIWindowTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import UIKit
import XCTest

/// Covers ``HostedSwiftUIWindow`` itself, because two of the accessibility audit's load-bearing
/// tests now depend on it and a helper that skips when it should wait — or waits when it should
/// skip — would quietly take those tests out of service.
@MainActor
final class HostedSwiftUIWindowTests: XCTestCase {

    /// The happy path: a hosted `Text` publishes accessibility elements, so the helper returns a
    /// window rather than skipping.
    ///
    /// This is also the canary for the helper's readiness probe. If SwiftUI ever stops setting
    /// `accessibilityElements` on the views it hosts, this test starts skipping — and a suite full
    /// of skips is the signal that the audit's central assumption needs revisiting.
    func testAHostedViewWithTextIsReadyAndReturnsAWindow() throws {
        let window = try HostedSwiftUIWindow.make(hosting: Text(verbatim: "Hello world"))

        XCTAssertNotNil(window.rootViewController)
        XCTAssertFalse(window.isHidden)
    }

    /// The skip path: when the readiness probe never succeeds, the helper throws `XCTSkip` rather
    /// than letting the caller assert against an empty hierarchy.
    ///
    /// Driven through the injected probe rather than through a view that happens to publish
    /// nothing, so it is deterministic on every platform — the failure this guards against is
    /// precisely a platform behaving differently from the one the test was written on.
    func testAProbeThatNeverSucceedsSkipsInsteadOfFailing() {
        do {
            _ = try HostedSwiftUIWindow.make(hosting: Text(verbatim: "Hello world"),
                                             timeout: 0.2,
                                             isReady: { _ in false })
            XCTFail("the helper must not return a window it could not make ready")
        } catch is XCTSkip {
            // Expected.
        } catch {
            XCTFail("expected XCTSkip, got \(error)")
        }
    }

    /// The probe is polled rather than sampled once, so a platform that needs a few run-loop turns
    /// is waited for instead of being declared unsupported on the first look.
    func testTheProbeIsPolledUntilItSucceeds() throws {
        var looks = 0
        _ = try HostedSwiftUIWindow.make(hosting: Text(verbatim: "Hello world"),
                                         timeout: 5,
                                         isReady: { _ in
                                             looks += 1
                                             return looks >= 3
                                         })

        XCTAssertEqual(looks, 3, "the helper must keep looking, not give up after the first turn")
    }

    /// The probe asks the real question: has SwiftUI *set* `accessibilityElements` anywhere in the
    /// hosted hierarchy? A view that has is ready; a bare `UIView` tree is not.
    func testTheDefaultProbeLooksForSetAccessibilityElements() {
        let bare = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        bare.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50)))
        XCTAssertFalse(HostedSwiftUIWindow.publishesAccessibilityElements(bare))

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let nested = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        container.addSubview(nested)
        let element = UIAccessibilityElement(accessibilityContainer: nested)
        element.accessibilityLabel = "synthetic" // scyther:unlocalised test fixture
        nested.accessibilityElements = [element]
        XCTAssertTrue(HostedSwiftUIWindow.publishesAccessibilityElements(container),
                      "the probe has to find elements set anywhere in the subtree, not just at the root")
    }

    /// The count probe adds up every element set across the subtree, so a caller that knows how
    /// many its fixture produces can wait for all of them rather than for the first.
    func testTheCountProbeSumsElementsAcrossTheSubtree() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(HostedSwiftUIWindow.publishedAccessibilityElementCount(root), 0)

        let branch = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        root.addSubview(branch)
        root.accessibilityElements = [UIAccessibilityElement(accessibilityContainer: root)]
        branch.accessibilityElements = [
            UIAccessibilityElement(accessibilityContainer: branch),
            UIAccessibilityElement(accessibilityContainer: branch),
        ]

        XCTAssertEqual(HostedSwiftUIWindow.publishedAccessibilityElementCount(root), 3)
    }

    /// An empty `accessibilityElements` array is not readiness. SwiftUI assigns the array before it
    /// has anything to put in it, and treating that as ready is exactly how the audit's tests came
    /// to assert against an empty walk.
    func testAnEmptyElementsArrayIsNotReady() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.accessibilityElements = []
        XCTAssertFalse(HostedSwiftUIWindow.publishesAccessibilityElements(view))
    }
}
