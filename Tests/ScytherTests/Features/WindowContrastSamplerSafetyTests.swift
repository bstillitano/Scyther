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
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: 3), 2)
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: 4), 2)
    }

    /// Capping must not *raise* the scale on a device below the cap — that would cost memory to
    /// invent detail the window does not have.
    func testAScaleAtOrBelowTheCapIsLeftAlone() {
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: 2), 2)
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: 1), 1)
    }

    /// A nonsense scale must not produce a zero-pixel or infinite bitmap.
    func testAnUnusableScaleFallsBackToOneToOne() {
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: 0), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: -3), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: .infinity), 1)
        XCTAssertEqual(WindowContrastSampler.captureScale(forDisplayScale: .nan), 1)
    }

    /// The capped scale really is what the snapshot is taken at, not just what the policy says.
    func testTheSamplerAddressesItsSnapshotAtTheCappedScale() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(WindowContrastSampler(window: window).captureScale,
                       min(window.traitCollection.displayScale, WindowContrastSampler.maximumCaptureScale))
    }

    /// The scale is read from the *display*, not from the window.
    ///
    /// A `UIWindow`'s own `contentScaleFactor` is 1 — its layer draws nothing, so `contentsScale`
    /// is never raised — while the screen behind it is 2× or 3×. Reading the window's value meant
    /// `captureScale(forDisplayScale:)` took its "below the cap" branch on every real device, the
    /// documented two-pixels-per-point cap never once applied, and every snapshot the audit has
    /// ever taken was a downscale of the screen. This asserts the two numbers really are different
    /// on this host and that the sampler follows the display.
    func testTheCaptureScaleFollowsTheDisplayRatherThanTheWindowsOwnScaleFactor() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let display = window.traitCollection.displayScale

        XCTAssertGreaterThan(display, 1, "this host must be a retina display for the test to mean anything")
        XCTAssertEqual(window.contentScaleFactor, 1, "a window's own scale factor is the trap being tested")
        XCTAssertGreaterThan(WindowContrastSampler(window: window).captureScale, 1,
                             "a 1x capture is the downscale that degraded every small-text measurement")
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
    ///
    /// Asked as a function of the rectangle rather than of a window. Through a real window this
    /// assertion is a statement about the *host*: `didCaptureWindow` is `false` for every window
    /// this process can build, zero-sized or not, so deleting the guard it names left it green
    /// because `drawHierarchy` would have declined anyway.
    func testAWindowWithNoAreaIsNotCaptured() {
        XCTAssertNil(WindowContrastSampler.snapshotSize(for: .zero, scale: 2))
        XCTAssertNil(WindowContrastSampler.snapshotSize(for: CGRect(x: 0, y: 0, width: 100, height: 0), scale: 2))
        XCTAssertNil(WindowContrastSampler.snapshotSize(for: CGRect(x: 0, y: 0, width: 0, height: 100), scale: 2))
        XCTAssertFalse(WindowContrastSampler(window: UIWindow(frame: .zero)).didCaptureWindow)
    }

    /// A window with area is snapshotted at the capture scale, in pixels.
    func testAWindowWithAreaIsSnapshottedAtTheCaptureScale() {
        let size = WindowContrastSampler.snapshotSize(for: CGRect(x: 0, y: 0, width: 390, height: 844), scale: 2)
        XCTAssertEqual(size, CGSize(width: 780, height: 1_688))
    }

    // MARK: - Crop Geometry

    /// An element's frame is in window *points*; the snapshot is addressed in *pixels*.
    ///
    /// Everything past ``WindowContrastSampler/samples(in:)``'s first guard is unreachable from a
    /// test in this host, so this conversion — the one place a whole device class's measurements
    /// can go wrong at once — was covered by nothing. Dropping the multiply reads the top-left
    /// quarter of every element on a 2× device: mostly page, no glyph, and a flat crop is reported
    /// as unmeasurable or, worse, as a pass.
    func testACropIsAddressedInPixelsRatherThanPoints() {
        let crop = WindowContrastSampler.cropRect(for: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                  scale: 2,
                                                  imageSize: CGSize(width: 780, height: 1_688))
        XCTAssertEqual(crop, CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    /// An element hanging over the edge of the window is measured on the part of it that is in the
    /// bitmap. Without the clamp, `CGImage.cropping(to:)` is handed a rectangle outside the image,
    /// returns `nil`, and every finding for that element silently disappears.
    func testACropIsClampedToTheImageRatherThanRunningOffIt() {
        let crop = WindowContrastSampler.cropRect(for: CGRect(x: 90, y: 0, width: 40, height: 10),
                                                  scale: 1,
                                                  imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(crop, CGRect(x: 90, y: 0, width: 10, height: 10))
    }

    /// A frame with no overlap at all is empty rather than negative or null, so the caller's
    /// `isEmpty` guard catches it instead of Core Graphics.
    func testACropThatDoesNotTouchTheImageIsEmpty() {
        let crop = WindowContrastSampler.cropRect(for: CGRect(x: 500, y: 500, width: 10, height: 10),
                                                  scale: 1,
                                                  imageSize: CGSize(width: 100, height: 100))
        XCTAssertTrue(crop.isEmpty)
    }

    /// The crop is whole pixels. A fractional origin leaves Core Graphics to round for itself, and
    /// it rounds outward — pulling a row of the neighbouring view's colour into a text crop, which
    /// is exactly the kind of intruder the analyser's own mode rule exists to survive.
    func testACropIsRoundedOutToWholePixels() {
        let crop = WindowContrastSampler.cropRect(for: CGRect(x: 10.4, y: 20.6, width: 30.3, height: 40.2),
                                                  scale: 1,
                                                  imageSize: CGSize(width: 1_000, height: 1_000))
        XCTAssertEqual(crop, crop.integral)
        XCTAssertTrue(crop.contains(CGRect(x: 10.4, y: 20.6, width: 30.3, height: 40.2)))
    }

    // MARK: - Downsample Grid

    /// A crop is read at at most 64 × 64. Removing the cap turns a full-width label on a 2× device
    /// into hundreds of thousands of `RGB` values — allocated, un-premultiplied and linearised on
    /// the main thread, once per element, inside a quarter-second budget.
    func testALargeCropIsReadAtTheCappedGrid() {
        let grid = WindowContrastSampler.sampleGrid(width: 780, height: 400)
        XCTAssertEqual(grid.columns, WindowContrastSampler.maximumSampleGridSide)
        XCTAssertEqual(grid.rows, WindowContrastSampler.maximumSampleGridSide)
        XCTAssertEqual(WindowContrastSampler.maximumSampleGridSide, 64)
    }

    /// A crop smaller than the cap is read at its own size: upsampling would invent pixels, and
    /// duplicated pixels move the analyser's mode.
    func testASmallCropIsReadAtItsOwnSize() {
        let grid = WindowContrastSampler.sampleGrid(width: 12, height: 40)
        XCTAssertEqual(grid.columns, 12)
        XCTAssertEqual(grid.rows, 40)
    }
}

/// A window that records what was hidden at the moment it was asked to draw.
///
/// The one thing this host can observe about the snapshot itself. `drawHierarchy` paints nothing
/// here, but it *is* called, and the state of the view tree when it is called is the whole of wave
/// A's headline fix.
@MainActor
private final class DrawRecordingWindow: UIWindow {
    /// Whether each of ``watched`` was hidden when the draw was asked for.
    private(set) var hiddenAtDrawTime: [Bool] = []

    /// The views whose visibility to record.
    var watched: [UIView] = []

    /// Records ``watched``'s visibility and declines to draw, exactly as this host would anyway.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to draw into. Unused.
    ///   - afterScreenUpdates: Whether to commit pending changes first. Unused.
    /// - Returns: `false`, the same answer a window with no host app gives.
    override func drawHierarchy(in rect: CGRect, afterScreenUpdates: Bool) -> Bool {
        hiddenAtDrawTime = watched.map(\.isHidden)
        return false
    }
}

extension WindowContrastSamplerSafetyTests {

    /// Scyther's own drawing is hidden **at the moment of the draw**, not merely selected for
    /// hiding and restored afterwards.
    ///
    /// The selection (``WindowContrastSampler/scytherOverlays(in:)``) and the restore were both
    /// covered; the step between them was not. Deleting `overlays.forEach { $0.isHidden = true }`
    /// left every existing test green — the restore test passes trivially when the overlay was
    /// never hidden, and the already-hidden test passes because it starts hidden — so the defect
    /// the whole fix exists for, pass *N*'s red boxes being measured by pass *N + 1*, was protected
    /// by nothing at all.
    func testScythersOwnDrawingIsHiddenWhileTheSnapshotIsTaken() {
        let window = DrawRecordingWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let wrapper = TopLevelViewsWrapper(frame: window.bounds)
        wrapper.isHidden = false
        let appView = UIView(frame: window.bounds)
        window.addSubview(appView)
        window.addSubview(wrapper)
        window.watched = [wrapper, appView]

        _ = WindowContrastSampler(window: window)

        XCTAssertEqual(window.hiddenAtDrawTime, [true, false],
                       "Scyther's wrapper must be hidden for the draw, and the app's own view must not")
        XCTAssertFalse(wrapper.isHidden, "and restored the instant the draw returns")
    }
}
