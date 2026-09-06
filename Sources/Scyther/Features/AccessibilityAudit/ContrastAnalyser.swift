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

/// What one measurement found.
struct ContrastMeasurement: Equatable, Sendable {
    /// The WCAG contrast ratio, from 1 to 21.
    let ratio: Double
    /// The mean colour of the smaller group — the ink.
    let foreground: RGB
    /// The mean colour of the larger group — the page.
    let background: RGB
}

/// Turns pixels into a contrast ratio.
///
/// Deliberately naive about what it is looking at: it splits the pixels into a light group and a
/// dark group and compares their means. That is right for text on a flat background, which is
/// what it is pointed at, and approximate for anything else — which is why every finding it
/// produces is a warning that says it is an estimate.
enum ContrastAnalyser {
    /// WCAG's relative luminance.
    ///
    /// - Parameter colour: The colour to measure.
    /// - Returns: Its luminance, `0` for black and `1` for white.
    static func luminance(_ colour: RGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red)
            + 0.7152 * linear(colour.green)
            + 0.0722 * linear(colour.blue)
    }

    /// The ratio between two luminances, lighter over darker.
    ///
    /// - Parameters:
    ///   - first: One luminance.
    ///   - second: The other.
    /// - Returns: The ratio, from 1 to 21.
    static func ratio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Measures a region's contrast.
    ///
    /// Splits the pixels at the midpoint between the darkest and lightest luminance present, calls
    /// the larger group the background and the smaller the foreground, and compares their mean
    /// colours.
    ///
    /// - Parameter pixels: The region's pixels.
    /// - Returns: The measurement, or `nil` when there are no pixels or they are all one colour —
    ///   in which case there is no contrast to report rather than a contrast of 1.
    static func measure(pixels: [RGB]) -> ContrastMeasurement? {
        guard !pixels.isEmpty else { return nil }

        let luminances = pixels.map(luminance)
        guard let darkest = luminances.min(), let lightest = luminances.max(),
              lightest - darkest > 0.005 else { return nil }

        let midpoint = (darkest + lightest) / 2
        var dark: [RGB] = []
        var light: [RGB] = []
        for (pixel, value) in zip(pixels, luminances) {
            if value < midpoint { dark.append(pixel) } else { light.append(pixel) }
        }
        guard !dark.isEmpty, !light.isEmpty else { return nil }

        let background = dark.count >= light.count ? mean(dark) : mean(light)
        let foreground = dark.count >= light.count ? mean(light) : mean(dark)

        return ContrastMeasurement(ratio: ratio(luminance(foreground), luminance(background)),
                                   foreground: foreground,
                                   background: background)
    }

    /// The mean of a group of pixels.
    ///
    /// - Parameter pixels: The group. Must not be empty.
    /// - Returns: Their average colour.
    private static func mean(_ pixels: [RGB]) -> RGB {
        let count = Double(pixels.count)
        return RGB(red: pixels.reduce(0) { $0 + $1.red } / count,
                   green: pixels.reduce(0) { $0 + $1.green } / count,
                   blue: pixels.reduce(0) { $0 + $1.blue } / count)
    }
}

extension RGB {
    /// The colour as `#RRGGBB`, for a finding to quote.
    var hexDescription: String {
        String(format: "#%02X%02X%02X", // scyther:unlocalised a hex colour
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }
}
