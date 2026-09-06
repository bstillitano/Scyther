import CoreGraphics

/// One sampled pixel, in sRGB components from `0` to `1`.
struct RGB: Equatable, Sendable {
    /// The red component, from `0` (none) to `1` (full).
    let red: Double

    /// The green component, from `0` (none) to `1` (full).
    let green: Double

    /// The blue component, from `0` (none) to `1` (full).
    let blue: Double
}

/// Where the contrast check gets its pixels.
///
/// A protocol rather than a concrete snapshot so the maths can be tested against known bitmaps
/// with no window and no rendering.
@MainActor
protocol ContrastSampling {
    /// The pixels drawn inside `frame`, already downsampled.
    ///
    /// - Parameter frame: The region in window coordinates.
    /// - Returns: The pixels, or an empty array when the region cannot be read.
    func samples(in frame: CGRect) -> [RGB]
}
