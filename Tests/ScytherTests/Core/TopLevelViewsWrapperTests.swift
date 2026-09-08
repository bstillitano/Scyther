//
//  TopLevelViewsWrapperTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class TopLevelViewsWrapperTests: XCTestCase {

    /// Records how many times `updateFrame()` was called, so a test can tell whether the
    /// wrapper actually propagated a resize rather than merely appearing to.
    ///
    /// Does not call `super.updateFrame()`: `TopLevelView`'s own implementation asserts, since
    /// every real subclass is required to override it.
    private final class SpyTopLevelView: TopLevelView {
        private(set) var updateFrameCallCount = 0

        override func updateFrame() {
            updateFrameCallCount += 1
        }
    }

    // MARK: - Sizing to the window

    /// The wrapper sizes itself from the window it is installed in — not from
    /// `UIScreen.main.bounds`, which is not safe to read from an orientation-change
    /// notification. See `TopLevelViewsWrapper`'s own doc comment for the measured reason.
    func testTheWrapperSizesItselfToItsWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let wrapper = TopLevelViewsWrapper(frame: .zero)

        window.addSubview(wrapper)

        XCTAssertEqual(wrapper.frame, window.bounds)
    }

    /// Before there is a window — `init` — `UIScreen.main.bounds` is at least a usable guess,
    /// matching `LayoutGuidesView.updateFrame()`'s own fallback.
    func testTheWrapperFallsBackToTheScreenWithNoWindowYet() {
        let wrapper = TopLevelViewsWrapper(frame: .zero)
        XCTAssertEqual(wrapper.frame, UIScreen.main.bounds)
    }

    // MARK: - Propagating a resize

    /// A real resize of the wrapper — the structural event `autoresizingMask` reacts to —
    /// propagates to every `TopLevelView` it holds via `layoutSubviews()`, independent of
    /// `deviceDidChangeOrientation`'s notification.
    func testAResizeOfTheWrapperPropagatesToItsChildren() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let wrapper = TopLevelViewsWrapper(frame: .zero)
        window.addSubview(wrapper)

        let child = SpyTopLevelView()
        wrapper.addTopLevelView(topLevelView: child)
        wrapper.layoutIfNeeded()
        let callsAfterFirstLayout = child.updateFrameCallCount

        wrapper.frame = CGRect(x: 0, y: 0, width: 300, height: 500)
        wrapper.layoutIfNeeded()

        XCTAssertGreaterThan(child.updateFrameCallCount, callsAfterFirstLayout)
    }

    /// A layout pass that leaves the wrapper's own size unchanged does not re-propagate —
    /// matching `LayoutGuidesView.layoutSubviews()`'s own guard, so a superview's unrelated
    /// layout pass costs nothing beyond the comparison.
    func testALayoutPassThatDoesNotChangeSizeDoesNotRepropagate() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let wrapper = TopLevelViewsWrapper(frame: .zero)
        window.addSubview(wrapper)

        let child = SpyTopLevelView()
        wrapper.addTopLevelView(topLevelView: child)
        wrapper.layoutIfNeeded()
        let calls = child.updateFrameCallCount

        wrapper.setNeedsLayout()
        wrapper.layoutIfNeeded()

        XCTAssertEqual(child.updateFrameCallCount, calls)
    }
}
