@testable import Scyther
import UIKit
import XCTest

/// Verifies the adapters that connect the pure `AuditNode` model to real UIKit: a `UIView`'s
/// conformance, `AccessibilityElementNode`'s wrapping of synthetic accessibility elements, and
/// `WindowContrastSampler`'s reading of pixels from an actual window.
@MainActor
final class AuditNodeAdapterTests: XCTestCase {

    func testAViewReportsItsAccessibilityPropertiesThroughTheProtocol() {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        button.accessibilityLabel = "Close"
        button.isAccessibilityElement = true
        // A plain, unattached `UIButton` never resolves its own implicit `.button` trait outside
        // a live accessibility runtime (no window scene, no VoiceOver session in a unit test
        // host) — every system control's `accessibilityTraits` reads back `[]` here regardless
        // of type, title, or configuration. Setting the trait directly is what an app does when
        // it wants a guaranteed trait anyway, and it keeps this test about the adapter's
        // pass-through rather than about a UIKit runtime dependency this test host doesn't have.
        button.accessibilityTraits = .button

        let node: AuditNode = button

        XCTAssertTrue(node.isAccessibilityElementNode)
        XCTAssertEqual(node.accessibilityLabelText, "Close")
        XCTAssertTrue(node.traits.contains(.button))
        XCTAssertEqual(node.typeName, "UIButton")
    }

    func testAHiddenViewIsNotVisible() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.isHidden = true
        XCTAssertFalse((view as AuditNode).isVisible)
    }

    func testAFullyTransparentViewIsNotVisible() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.alpha = 0
        XCTAssertFalse((view as AuditNode).isVisible)
    }

    /// Scyther's own overlays are marked so the audit can leave them alone.
    func testScytherOwnedViewsAreRecognised() {
        let wrapper = TopLevelViewsWrapper(frame: .zero)
        XCTAssertTrue((wrapper as AuditNode).isScytherOwned)
        XCTAssertFalse((UIView() as AuditNode).isScytherOwned)
    }

    /// A container that exposes accessibility children is walked through them, not its subviews.
    func testAccessibilityChildrenWinOverSubviews() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "synthetic"
        element.accessibilityFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        container.accessibilityElements = [element]

        let children = (container as AuditNode).children

        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.accessibilityLabelText, "synthetic")
    }

    /// A window not at the screen origin (Split View, Slide Over, Stage Manager, ...) must not
    /// leak `accessibilityFrame`'s screen coordinates into `frameInWindow` unconverted — the
    /// overlay box and the contrast sampler's crop both assume window-local coordinates.
    func testSyntheticElementFrameIsConvertedFromScreenToWindowCoordinates() {
        let window = UIWindow(frame: CGRect(x: 100, y: 50, width: 200, height: 200))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.addSubview(container)
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityFrame = CGRect(x: 120, y: 70, width: 40, height: 40)

        let node = AccessibilityElementNode(element: element)

        XCTAssertEqual(node.frameInWindow, CGRect(x: 20, y: 20, width: 40, height: 40))
    }

    /// The sampler reads back what was drawn.
    func testTheSamplerReadsTheColourOfWhatWasDrawn() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.backgroundColor = .black
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.layoutIfNeeded()

        let sampler = WindowContrastSampler(window: window)
        let pixels = sampler.samples(in: CGRect(x: 10, y: 10, width: 20, height: 20))

        XCTAssertFalse(pixels.isEmpty)
        XCTAssertEqual(pixels.first?.red ?? 1, 0, accuracy: 0.05)
    }

    func testTheSamplerReturnsNothingForARegionOutsideTheWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let sampler = WindowContrastSampler(window: window)
        XCTAssertTrue(sampler.samples(in: CGRect(x: 500, y: 500, width: 10, height: 10)).isEmpty)
    }
}
