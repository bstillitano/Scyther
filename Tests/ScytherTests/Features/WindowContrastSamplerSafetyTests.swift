@testable import Scyther
import UIKit
import XCTest

/// Covers the safety properties of the window snapshot: what it is allowed to rasterise, how big
/// the bitmap is permitted to get, whose pixels are excluded from it, and what an unpainted pixel
/// contributes to a measurement.
///
/// Every test here is deliberately aimed at a *pure* entry point rather than at a real window.
/// `ScytherTests` has no host app, so `UIView.drawHierarchy(in:afterScreenUpdates:)` returns
/// `false` and paints nothing for every window a test can build — a test that went in through
/// ``WindowContrastSampler/samples(in:)`` would assert against an empty snapshot and pass whatever
/// the code underneath it did. That trap has already caught two people on this branch, so the one
/// test here that does use a real window (``testTheSamplerReportsThatItCouldNotCaptureATestsWindow``)
/// asserts precisely the thing that *is* true in this host: that the capture fails and is admitted.
@MainActor
final class WindowContrastSamplerSafetyTests: XCTestCase {

    // MARK: - Capture Scale

    /// The bitmap is the memory problem: a full-window snapshot at a 3× device's native scale is
    /// roughly 14 MB, re-taken every half-second in live mode. The crop is capped at 64 × 64 per
    /// element, so nothing above the cap survives to be measured anyway.
    func testANativeScaleAboveTheCapIsCapped() {
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: 3), 2)
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: 4), 2)
    }

    /// Capping must not *raise* the scale on a device below the cap — that would cost memory to
    /// invent detail the window does not have.
    func testAScaleAtOrBelowTheCapIsLeftAlone() {
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: 2), 2)
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: 1), 1)
    }

    /// A nonsense scale must not produce a zero-pixel or infinite bitmap.
    func testAnUnusableScaleFallsBackToOneToOne() {
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: 0), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: -3), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: .infinity), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forContentScaleFactor: .nan), 1)
    }

    /// The capped scale really is what the snapshot is taken at, not just what the policy says.
    func testTheSamplerAddressesItsSnapshotAtTheCappedScale() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentScaleFactor = 3

        XCTAssertEqual(WindowContrastSampler(window: window).captureScale, 2)
    }

    // MARK: - Scyther's Own Pixels

    /// The audit's own finding boxes, its count pill, the grid overlay and the FPS counter all
    /// live in a single `TopLevelViewsWrapper` inside the key window. Before this, pass *N*'s
    /// boxes were still on screen when pass *N + 1* snapshotted the window, so every element sat
    /// under Scyther's own stroke was measured through it and the drift compounded pass over pass.
    func testScythersOwnOverlayWrapperIsExcludedFromTheSnapshot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let appView = UIView(frame: window.bounds)
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        window.addSubview(appView)
        window.addSubview(wrapper)

        let overlays = WindowContrastSampler.scytherOverlays(in: window)

        XCTAssertEqual(overlays.count, 1)
        XCTAssertTrue(overlays.first === wrapper)
        XCTAssertFalse(overlays.contains { $0 === appView })
    }

    /// An overlay added to a window directly rather than through the wrapper is still Scyther's.
    func testATopLevelViewAddedStraightToTheWindowIsExcludedToo() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let overlay = GridOverlayView(frame: window.bounds)
        window.addSubview(overlay)

        XCTAssertTrue(WindowContrastSampler.scytherOverlays(in: window).contains { $0 === overlay })
    }

    /// The app's own views are the entire point of the audit and must never be hidden for it.
    func testTheAppsOwnViewsAreNotExcluded() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = UIViewController()
        window.layoutIfNeeded()

        XCTAssertTrue(WindowContrastSampler.scytherOverlays(in: window).isEmpty)
    }

    /// Hiding is only honest if it is undone: the overlay the developer switched on has to be
    /// back on screen the instant the snapshot returns, whatever the render did.
    func testAnOverlayIsVisibleAgainAfterTheSnapshot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        wrapper.isHidden = false
        window.addSubview(wrapper)

        _ = WindowContrastSampler(window: window)

        XCTAssertFalse(wrapper.isHidden)
    }

    /// An overlay the developer had already hidden must stay hidden — restoring it would switch
    /// on a feature nobody asked for.
    func testAnAlreadyHiddenOverlayStaysHidden() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        wrapper.isHidden = true
        window.addSubview(wrapper)

        _ = WindowContrastSampler(window: window)

        XCTAssertTrue(wrapper.isHidden)
    }

    // MARK: - Unpainted Pixels

    /// An alpha of zero is a pixel nothing painted, not a black one. Un-premultiplying it recovers
    /// `0, 0, 0`, so an unpainted corner of a crop used to enter the sample as pure black, drag
    /// the darkest luminance to zero and manufacture contrast out of a region the user cannot see.
    func testFullyTransparentPixelsAreDroppedRatherThanReadAsBlack() {
        // One opaque mid-grey pixel, then one entirely unpainted one.
        let bytes: [UInt8] = [128, 128, 128, 255, 0, 0, 0, 0]

        let pixels = WindowContrastSampler.pixels(fromPremultipliedRGBA: bytes)

        XCTAssertEqual(pixels.count, 1)
        XCTAssertEqual(pixels.first?.red ?? -1, 128.0 / 255.0, accuracy: 0.001)
    }

    /// A crop that was never painted at all reports nothing, so `ContrastAnalyser.measure` returns
    /// `nil` and the element is not silently passed on the strength of imaginary black.
    func testACropThatWasNeverPaintedYieldsNoPixels() {
        let bytes = [UInt8](repeating: 0, count: 4 * 16)

        XCTAssertTrue(WindowContrastSampler.pixels(fromPremultipliedRGBA: bytes).isEmpty)
    }

    /// The ordinary case still works: opaque bytes come back as the colours they encode.
    func testOpaquePixelsAreReadBackAsTheirComponents() {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]

        let pixels = WindowContrastSampler.pixels(fromPremultipliedRGBA: bytes)

        XCTAssertEqual(pixels, [RGB(red: 1, green: 0, blue: 0), RGB(red: 0, green: 0, blue: 1)])
    }

    /// Half-transparent white is stored premultiplied as `128, 128, 128, 128`; un-premultiplying
    /// has to recover white rather than the grey the bytes literally hold.
    func testAPartiallyTransparentPixelIsUnpremultiplied() {
        let pixels = WindowContrastSampler.pixels(fromPremultipliedRGBA: [128, 128, 128, 128])

        XCTAssertEqual(pixels.count, 1)
        XCTAssertEqual(pixels.first?.red ?? 0, 1, accuracy: 0.01)
    }

    // MARK: - A Capture That Did Not Happen

    /// The one honest end-to-end assertion this host can make. `ScytherTests` has no host app, so
    /// `drawHierarchy` declines for every window a test can build. Before this change the sampler
    /// answered that by rendering the layer tree instead — which is exactly the path that ignores
    /// iOS's non-capturable-content flags and would put a secure text field's glyphs into the
    /// bitmap. There is now no such path, so the sampler admits it has nothing.
    func testTheSamplerReportsThatItCouldNotCaptureATestsWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.backgroundColor = .black
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.layoutIfNeeded()

        let sampler = WindowContrastSampler(window: window)

        XCTAssertFalse(sampler.didCaptureWindow,
                       "drawHierarchy paints nothing without a host app; anything that did paint came from a layer render")
        XCTAssertTrue(sampler.samples(in: CGRect(x: 10, y: 10, width: 20, height: 20)).isEmpty,
                      "no capture must mean no pixels, not pixels invented by a different API")
    }

    /// A zero-sized window has nothing to capture and must not be reported as captured.
    func testAWindowWithNoAreaIsNotCaptured() {
        XCTAssertFalse(WindowContrastSampler(window: UIWindow(frame: .zero)).didCaptureWindow)
    }
}
