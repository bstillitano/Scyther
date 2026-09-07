#if !os(macOS)
import UIKit

/// Reads pixels out of a real window for ``ContrastAnalyser`` to compare.
///
/// The window is snapshotted exactly once, in ``init(window:)``, rather than re-drawn on every
/// call to ``samples(in:)``: the audit takes many samples across a single walk of the tree, and
/// the point of one snapshot is that every one of those samples reads the same frame — a repaint
/// mid-walk (an animation tick, a keyboard appearing) would otherwise make findings from the same
/// run disagree with each other for no reason a developer reading them could see.
///
/// Three things about that snapshot are deliberate and each has cost a defect:
///
/// - It is taken with `UIView.drawHierarchy(in:afterScreenUpdates:)` and **nothing else**. The
///   obvious fallback, `CALayer.render(in:)`, walks the layer tree directly and so ignores iOS's
///   non-capturable-content flags — the ones that keep secure text entry, DRM layers and Apple Pay
///   sheets out of a screenshot. `drawHierarchy` honours them. A tool that reads the user's screen
///   as pixels does not get to opt out of the platform's privacy protection just because the
///   preferred API returned nothing, so when `drawHierarchy` declines there is simply no snapshot
///   and ``didCaptureWindow`` says so.
/// - It is captured at no more than ``maximumCaptureScale`` pixels per point. See
///   ``captureScale(forContentScaleFactor:)``.
/// - Scyther's own overlays are hidden for the duration of the draw. See
///   ``scytherOverlays(in:)``.
@MainActor
struct WindowContrastSampler: ContrastSampling {
    // MARK: - Capture Policy

    /// The most pixels per point a snapshot is ever taken at.
    ///
    /// A full-window bitmap at a 3× device's native scale is roughly 14 MB, plus a same-sized
    /// backing context inside `UIGraphicsImageRenderer` — re-allocated on every pass, and live
    /// mode runs a pass every half-second for as long as layout keeps settling. That is a real
    /// jetsam risk in exactly the memory-heavy host (a map, a camera, a video player) most likely
    /// to want an audit run over it.
    ///
    /// Two is the number rather than one because ``samples(in:)`` strides over the crop rather
    /// than averaging it: at 1× a body-text stem is roughly one pixel wide and the stride can step
    /// over the ink altogether, which reports an element as a flat colour and therefore as passing.
    /// At 2× the ink is at least two pixels wide in every direction and cannot vanish, while the
    /// bitmap costs well under half of what the native scale would.
    ///
    /// Nothing above 2× buys accuracy in any case: ``samples(in:)`` caps every crop at 64 × 64,
    /// so on all but the largest elements the extra pixels are strided straight past.
    static let maximumCaptureScale: CGFloat = 2

    /// The colour space every pixel this type reports is expressed in.
    ///
    /// Explicitly sRGB, not `CGColorSpaceCreateDeviceRGB()`. The device space has no defined
    /// transfer function or primaries — its bytes are sRGB by platform convention only — whereas
    /// ``ContrastAnalyser/luminance(_:)`` implements WCAG's linearisation, which is *specified*
    /// against sRGB. Naming the space makes Core Graphics' conversion defined rather than
    /// conventional, so the numbers fed to the WCAG maths really are the components it expects.
    private static let colourSpace: CGColorSpace? = CGColorSpace(name: CGColorSpace.sRGB)

    // MARK: - Data

    /// The window's contents at the moment of ``init(window:)``, in device pixels, or `nil` when
    /// nothing could be captured.
    private let image: CGImage?

    /// How many snapshot pixels map to one window point — needed to turn ``samples(in:)``'s
    /// window-point frame into the pixel grid ``image`` is actually addressed in.
    ///
    /// This is the *capture* scale, which is deliberately not the window's own
    /// `contentScaleFactor`; see ``captureScale(forContentScaleFactor:)``. Readable rather than
    /// private so a test can assert that the cap is applied to a real snapshot and not only by
    /// the policy function in isolation.
    let captureScale: CGFloat

    /// Whether the window actually rendered into the snapshot.
    ///
    /// `false` means the check cannot be answered from here at all — not that the window was
    /// blank. `drawHierarchy(in:afterScreenUpdates:)` returns `false` when it declines to render,
    /// which happens for a window the system has never presented (an `XCTestCase`'s fabricated
    /// window, for instance) and for content iOS refuses to let anything capture.
    ///
    /// Callers must treat this as "contrast could not be measured" and say so, rather than running
    /// the check against an empty snapshot: every element would come back as a single flat colour,
    /// ``ContrastAnalyser/measure(pixels:)`` would return `nil` for each one, and a screen full of
    /// unmeasurable elements would be reported as a screen full of passing ones. That is the worst
    /// possible outcome for an accessibility tool — a clean bill of health nobody earned.
    let didCaptureWindow: Bool

    // MARK: - Lifecycle

    /// Snapshots `window` immediately.
    ///
    /// - Parameter window: The window to read pixels from, usually the key window.
    init(window: UIWindow) {
        captureScale = Self.captureScale(forContentScaleFactor: window.contentScaleFactor)
        let capture = Self.snapshot(of: window, scale: captureScale)
        image = capture.image
        didCaptureWindow = capture.didDraw && capture.image != nil
    }

    // MARK: - Capture

    /// The scale a snapshot of a window with this `contentScaleFactor` is taken at.
    ///
    /// Split out as a pure function of one number so the policy in ``maximumCaptureScale`` can be
    /// tested: the test host has no host app, so every `UIWindow` a test can make reports a
    /// `contentScaleFactor` of 1 and a test that went through a real window could never tell a cap
    /// from no cap at all.
    ///
    /// - Parameter contentScaleFactor: The window's own scale.
    /// - Returns: The capture scale, never above ``maximumCaptureScale`` and never below 1.
    static func captureScale(forContentScaleFactor contentScaleFactor: CGFloat) -> CGFloat {
        guard contentScaleFactor.isFinite, contentScaleFactor > 1 else { return 1 }
        return min(contentScaleFactor, maximumCaptureScale)
    }

    /// Scyther's own views sitting directly in `window`, which must not appear in the snapshot.
    ///
    /// `AuditNode.isScytherOwned` keeps Scyther's views out of the *walk*. Nothing kept them out
    /// of the *pixels*, and the consequences compounded: in live mode, pass *N* strokes a red or
    /// orange box at each finding's own frame, and pass *N+1* — half a second later, with those
    /// boxes still on screen — measured the element *through* them. A finding perturbed the
    /// measurement that produced it, and a borderline element could oscillate between flagged and
    /// clean forever. With the grid overlay switched on as well, its lines landed in every single
    /// crop and corrupted every ratio in the report.
    ///
    /// Scyther's *presented* UI is a different problem with a different answer — see
    /// ``AccessibilityAudit/checksNeedingAnUncoveredScreen`` — because a modal dims what is behind
    /// it and no amount of hiding recovers the undimmed pixels. Everything Scyther draws *without*
    /// presenting goes into a single ``TopLevelViewsWrapper`` added straight to the window
    /// (`InterfaceToolkit.addTopLevelViewsWrapperToWindow(window:)`), so hiding that one subview
    /// removes the grid, the FPS counter, the audit's boxes and its count pill together.
    /// ``TopLevelView`` is matched as well, in case a future overlay is ever added to a window
    /// directly rather than through the wrapper.
    ///
    /// - Parameter window: The window about to be snapshotted.
    /// - Returns: The subviews to hide for the duration of the draw, in `window.subviews` order.
    static func scytherOverlays(in window: UIWindow) -> [UIView] {
        window.subviews.filter { $0 is TopLevelViewsWrapper || $0 is TopLevelView }
    }

    /// Renders `window` to a `CGImage`, without Scyther's own overlays in it.
    ///
    /// The overlays are hidden and restored around the draw rather than the app's own subviews
    /// being drawn one by one into a shared context. Both exclude the same pixels; hiding keeps
    /// the window composited as a whole, so a window-level mask, corner radius or transformed
    /// subview still renders the way the user actually sees it, which is the only thing a contrast
    /// measurement is entitled to look at. The cost is that `afterScreenUpdates: true` commits the
    /// hidden state before rendering, so Scyther's own overlay can in principle miss a frame; the
    /// restore is synchronous and unconditional (`defer`), so it cannot outlive this call, and the
    /// worst case is a flicker of Scyther's drawing rather than of the app's.
    ///
    /// - Parameters:
    ///   - window: The window to render.
    ///   - scale: The pixels-per-point to render at, from ``captureScale(forContentScaleFactor:)``.
    /// - Returns: The rendered image, and whether the window actually drew into it. An image with
    ///   `didDraw` of `false` is not usable — see ``didCaptureWindow``.
    private static func snapshot(of window: UIWindow, scale: CGFloat) -> (image: CGImage?, didDraw: Bool) {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return (nil, false) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        // `.automatic` resolves to `.extended` on every wide-gamut device, i.e. every iPhone since
        // the 7, which produces an extended-range sRGB image whose out-of-gamut components are
        // then clamped when drawn into the 8-bit bitmap `rgbaBytes(of:width:height:)` reads. A
        // P3 brand colour would arrive at the WCAG maths as a colour the app never drew. Asking
        // for standard range up front makes Core Graphics do that conversion properly, once.
        format.preferredRange = .standard

        let overlays = scytherOverlays(in: window).filter { !$0.isHidden }
        overlays.forEach { $0.isHidden = true }
        defer { overlays.forEach { $0.isHidden = false } }

        var didDraw = false
        let drawn = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            didDraw = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return (drawn.cgImage, didDraw)
    }

    // MARK: - Reading Pixels

    /// Draws `image` into a bitmap of a format this type chooses itself, so pixel bytes can be
    /// read back without having to know or guess the source image's own colour space, byte order
    /// or premultiplication — `UIGraphicsImageRenderer`'s output format is not documented and has
    /// changed across OS versions, so trusting it would be trusting an implementation detail.
    /// Core Graphics does the colour conversion (and, since `width`/`height` can be smaller than
    /// `image`'s own size, the downsampling) while drawing, using nearest-neighbour sampling so
    /// the result is a genuine stride over the source pixels rather than a blur of them.
    ///
    /// Every use of the bitmap's memory happens inside `withUnsafeMutableBytes`. The obvious
    /// spelling — `CGContext(data: &buffer, …)` followed by `context.draw(…)` — is undefined
    /// behaviour: an inout-to-pointer conversion is guaranteed valid only for the duration of the
    /// call it appears in, and Swift is explicitly permitted to hand over a temporary copy. The
    /// context outlives that call and writes every byte it produces afterwards, through a pointer
    /// the language no longer promises anything about.
    ///
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - width: The target width in pixels; the caller keeps this small and cheap.
    ///   - height: The target height in pixels; the caller keeps this small and cheap.
    /// - Returns: `width * height` RGBA8 premultiplied-alpha bytes, four per pixel, in row-major
    ///   order, or `nil` when the bitmap could not be created.
    private static func rgbaBytes(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, let colourSpace else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colourSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drew ? buffer : nil
    }

    /// Turns premultiplied RGBA8 bytes into sRGB pixels, dropping the ones nothing painted.
    ///
    /// A byte quad with an alpha of zero is not a black pixel — it is a pixel the snapshot never
    /// covered. Un-premultiplying it recovers `0, 0, 0`, so before this it entered the sample as
    /// pure black: an unpainted corner of a crop pulled the darkest luminance down to zero, moved
    /// ``ContrastAnalyser/measure(pixels:)``'s midpoint split with it, and manufactured contrast
    /// out of a region the user cannot see. Those quads are skipped instead, which can legitimately
    /// leave the result empty — and an empty result is reported as "could not measure" rather than
    /// as a pass.
    ///
    /// Split out as a pure function over bytes because it cannot be reached through a real window
    /// in the test host: `ScytherTests` has no host app, so `drawHierarchy` renders nothing and
    /// any test that went in through ``samples(in:)`` would assert against an empty snapshot and
    /// pass no matter what this code did.
    ///
    /// - Parameter bytes: RGBA8 premultiplied bytes, four per pixel, as returned by
    ///   ``rgbaBytes(of:width:height:)``.
    /// - Returns: One `RGB` per painted pixel, in the order the bytes arrived.
    static func pixels(fromPremultipliedRGBA bytes: [UInt8]) -> [RGB] {
        var pixels: [RGB] = []
        pixels.reserveCapacity(bytes.count / 4)

        var offset = 0
        while offset + 3 < bytes.count {
            defer { offset += 4 }

            let alphaByte = bytes[offset + 3]
            guard alphaByte != 0 else { continue }

            let alpha = Double(alphaByte) / 255
            func unmultiply(_ component: UInt8) -> Double {
                min(Double(component) / 255 / alpha, 1)
            }
            pixels.append(RGB(red: unmultiply(bytes[offset]),
                              green: unmultiply(bytes[offset + 1]),
                              blue: unmultiply(bytes[offset + 2])))
        }
        return pixels
    }

    /// The pixels drawn inside `frame`, downsampled to at most 64 × 64.
    ///
    /// - Parameter frame: The region to read, in window points.
    /// - Returns: The sampled pixels, or `[]` when there was nothing to snapshot, `frame` has no
    ///   area, `frame` doesn't overlap the image at all, or nothing in it was painted.
    func samples(in frame: CGRect) -> [RGB] {
        guard let image, didCaptureWindow, frame.width > 0, frame.height > 0 else { return [] }

        let pixelRect = CGRect(x: frame.origin.x * captureScale,
                               y: frame.origin.y * captureScale,
                               width: frame.width * captureScale,
                               height: frame.height * captureScale)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = pixelRect.intersection(imageBounds).integral
        guard !cropRect.isEmpty, let cropped = image.cropping(to: cropRect) else { return [] }

        let columns = min(cropped.width, 64)
        let rows = min(cropped.height, 64)
        guard let bytes = Self.rgbaBytes(of: cropped, width: columns, height: rows) else { return [] }
        return Self.pixels(fromPremultipliedRGBA: bytes)
    }
}
#endif
