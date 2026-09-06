import UIKit

/// Reads pixels out of a real window for ``ContrastAnalyser`` to compare.
///
/// The window is snapshotted exactly once, in ``init(window:)``, rather than re-drawn on every
/// call to ``samples(in:)``: the audit takes many samples across a single walk of the tree, and
/// the point of one snapshot is that every one of those samples reads the same frame — a repaint
/// mid-walk (an animation tick, a keyboard appearing) would otherwise make findings from the same
/// run disagree with each other for no reason a developer reading them could see.
@MainActor
struct WindowContrastSampler: ContrastSampling {
    /// The window's contents at the moment of ``init(window:)``, in device pixels.
    private let image: CGImage?

    /// How many device pixels map to one point — needed to turn `samples(in:)`'s window-point
    /// frame into the pixel grid `image` is actually addressed in.
    private let scale: CGFloat

    /// Snapshots `window` immediately.
    ///
    /// - Parameter window: The window to read pixels from, usually the key window.
    init(window: UIWindow) {
        scale = window.contentScaleFactor
        image = Self.snapshot(of: window)
    }

    /// Renders `window` to a `CGImage`.
    ///
    /// `drawHierarchy(afterScreenUpdates:)` is the documented way to snapshot a live view, and is
    /// tried first because it composites exactly what's on screen, animations and all. It relies
    /// on the window having actually gone through a screen update, though, and an `XCTestCase`'s
    /// window — created and made key entirely inside the test, with no real screen backing it —
    /// doesn't always get one: `drawHierarchy` then silently produces a fully transparent image
    /// rather than failing, which would otherwise be indistinguishable from a real, empty window.
    /// `CALayer.render(in:)` has no such dependency: it walks the layer tree directly, so it
    /// draws correctly even for a window the system never presented. It is less faithful to some
    /// live-only effects (certain `UIVisualEffectView` blurs, for instance), which is why it is
    /// the fallback rather than the default — used only when `drawHierarchy` comes back empty.
    ///
    /// - Parameter window: The window to render.
    /// - Returns: The rendered image, or `nil` when `window` has no area to draw.
    private static func snapshot(of window: UIWindow) -> CGImage? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.contentScaleFactor
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        let drawn = renderer.image { _ in
            _ = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        if let cgImage = drawn.cgImage, hasAnyOpaquePixel(cgImage) {
            return cgImage
        }

        let rendered = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        return rendered.cgImage
    }

    /// Whether an image has at least one pixel that isn't fully transparent.
    ///
    /// This is how ``snapshot(of:)`` tells "`drawHierarchy` genuinely drew an empty window" apart
    /// from "`drawHierarchy` silently failed" — both look identical as a `CGImage`, so the only
    /// way to notice the failure is to check whether anything was actually painted.
    ///
    /// - Parameter image: The candidate image to inspect.
    /// - Returns: `true` once a non-transparent pixel is found.
    private static func hasAnyOpaquePixel(_ image: CGImage) -> Bool {
        let width = min(image.width, 32)
        let height = min(image.height, 32)
        guard let bytes = rgbaBytes(of: image, width: width, height: height) else { return false }

        var index = 3 // the alpha byte of the first pixel
        while index < bytes.count {
            if bytes[index] != 0 { return true }
            index += 4
        }
        return false
    }

    /// Draws `image` into a bitmap of a format this type chooses itself, so pixel bytes can be
    /// read back without having to know or guess the source image's own colour space, byte order
    /// or premultiplication — `UIGraphicsImageRenderer`'s output format is not documented and has
    /// changed across OS versions, so trusting it would be trusting an implementation detail.
    /// Core Graphics does the colour conversion (and, since `width`/`height` can be smaller than
    /// `image`'s own size, the downsampling) while drawing, using nearest-neighbour sampling so
    /// the result is a genuine stride over the source pixels rather than a blur of them.
    ///
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - width: The target width in pixels; the caller keeps this small and cheap.
    ///   - height: The target height in pixels; the caller keeps this small and cheap.
    /// - Returns: `width * height` RGBA8 premultiplied-alpha bytes, four per pixel, in row-major
    ///   order, or `nil` when the bitmap could not be created.
    private static func rgbaBytes(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(data: &buffer,
                                       width: width,
                                       height: height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// The pixels drawn inside `frame`, downsampled to at most 64 × 64.
    ///
    /// - Parameter frame: The region to read, in window points.
    /// - Returns: The sampled pixels, or `[]` when there was nothing to snapshot, `frame` has no
    ///   area, or `frame` doesn't overlap the image at all.
    func samples(in frame: CGRect) -> [RGB] {
        guard let image, frame.width > 0, frame.height > 0 else { return [] }

        let pixelRect = CGRect(x: frame.origin.x * scale,
                               y: frame.origin.y * scale,
                               width: frame.width * scale,
                               height: frame.height * scale)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = pixelRect.intersection(imageBounds).integral
        guard !cropRect.isEmpty, let cropped = image.cropping(to: cropRect) else { return [] }

        let columns = min(cropped.width, 64)
        let rows = min(cropped.height, 64)
        guard let bytes = Self.rgbaBytes(of: cropped, width: columns, height: rows) else { return [] }

        var pixels: [RGB] = []
        pixels.reserveCapacity(columns * rows)
        var offset = 0
        while offset < bytes.count {
            let alpha = Double(bytes[offset + 3]) / 255
            func unmultiply(_ component: UInt8) -> Double {
                let value = Double(component) / 255
                return alpha > 0.001 ? min(value / alpha, 1) : value
            }
            pixels.append(RGB(red: unmultiply(bytes[offset]),
                              green: unmultiply(bytes[offset + 1]),
                              blue: unmultiply(bytes[offset + 2])))
            offset += 4
        }
        return pixels
    }
}
