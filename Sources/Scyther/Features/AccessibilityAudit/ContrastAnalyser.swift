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

    /// The ink: the colour of the extreme end of the smaller group, which is as close as a
    /// pixel sample gets to "the colour the text is drawn in".
    let foreground: RGB

    /// The page: the colour of the extreme end of the larger group.
    let background: RGB
}

/// Turns pixels into a contrast ratio.
///
/// The job is to recover *two colours* — the ink and the page — from a crop that also contains
/// every intermediate shade the rasteriser painted along each glyph's edge. Two decisions carry
/// that:
///
/// - **Everything is averaged in linear light.** Relative luminance is a linear-light quantity
///   and linearisation is convex, so `L(mean(c)) ≠ mean(L(c))`: averaging the gamma-encoded
///   bytes of a half-black, half-white group reports 3.98:1 against white where the light those
///   pixels actually emit is 1.91:1. Averaging in linear light is not a refinement, it is the
///   only averaging that answers the question the ratio formula asks.
/// - **Each group is represented by its extreme decile, not its mean.** Antialiased edge pixels
///   run the whole way between ink and page, so roughly half of them land in the ink group and
///   drag its mean toward the background — enough to report `#767676` on `#FFFFFF`, WCAG's own
///   canonical exactly-passing grey, as 3.5:1. Taking the darkest tenth of the dark group and
///   the lightest tenth of the light group skips the antialiased skirt and lands on the glyph
///   core and the clear page, which reports that pair at 4.54:1 as it should be.
///
/// It remains an estimate — a photograph or a gradient behind the text has no two colours to
/// find — which is why every finding it produces is a warning that says it is an estimate.
enum ContrastAnalyser {
    /// The fraction of each group taken as that group's colour.
    ///
    /// A tenth is enough to average away sampling noise and small enough that, for any glyph
    /// covering more than about one pixel in fifty of its own frame, the whole slice sits inside
    /// the glyph core rather than on its antialiased edge. Too small and the answer is one noisy
    /// pixel; too large and the edge pixels are back in the average.
    static let groupPercentile: Double = 0.1

    /// The smallest ratio worth calling a measurement.
    ///
    /// The gate this replaces was an absolute difference in relative luminance, which is not a
    /// scale-free quantity: luminance is compressed near black, so `#000000` on `#0F0F0F` — a
    /// real 1.10:1, meaning invisible text — differs by 0.0048 and was dropped, while the same
    /// gate never fired anywhere near white. That made the check blind in exactly the place
    /// dark-mode contrast fails. A ratio gate is scale-free: 1.02 rejects a flat surface plus
    /// dithering or one 8-bit step of banding, at either end of the scale, and keeps every pair
    /// that differs by more than that.
    static let smallestMeaningfulRatio: Double = 1.02

    /// One sRGB component in linear light.
    ///
    /// - Parameter component: The gamma-encoded component, from `0` to `1`.
    /// - Returns: Its linear-light value, from `0` to `1`.
    static func linearComponent(_ component: Double) -> Double {
        component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    /// One linear-light component encoded back to sRGB.
    ///
    /// The exact inverse of ``linearComponent(_:)``, including its threshold — which is the
    /// standard's `0.03928` divided by `12.92` rather than the errata's `0.0031308`, so that a
    /// value round-trips through the pair unchanged and a quoted hex colour is the colour whose
    /// luminance was measured.
    ///
    /// - Parameter linear: The linear-light value, from `0` to `1`.
    /// - Returns: Its gamma-encoded sRGB component, from `0` to `1`.
    static func encodedComponent(_ linear: Double) -> Double {
        linear <= 0.03928 / 12.92 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// WCAG's relative luminance.
    ///
    /// - Parameter colour: The colour to measure.
    /// - Returns: Its luminance, `0` for black and `1` for white.
    static func luminance(_ colour: RGB) -> Double {
        0.2126 * linearComponent(colour.red)
            + 0.7152 * linearComponent(colour.green)
            + 0.0722 * linearComponent(colour.blue)
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
    /// Splits the pixels at the midpoint between the darkest and lightest luminance present —
    /// which separates ink from page — and then represents each side by its extreme decile
    /// rather than by its mean, so the antialiased shades between the two colours are not
    /// averaged into either of them. The larger group is the page, on the reasoning that text
    /// covers less of its own frame than its background does.
    ///
    /// - Parameter pixels: The region's pixels.
    /// - Returns: The measurement, or `nil` when there are no pixels, or when everything in the
    ///   region is within ``smallestMeaningfulRatio`` of one colour — in which case there is no
    ///   text to have found and no contrast to report, rather than a contrast of 1.
    static func measure(pixels: [RGB]) -> ContrastMeasurement? {
        guard !pixels.isEmpty else { return nil }

        let luminances = pixels.map(luminance)
        guard let darkest = luminances.min(), let lightest = luminances.max(),
              ratio(lightest, darkest) > smallestMeaningfulRatio else { return nil }

        let midpoint = (darkest + lightest) / 2
        var dark: [(pixel: RGB, luminance: Double)] = []
        var light: [(pixel: RGB, luminance: Double)] = []
        for (pixel, value) in zip(pixels, luminances) {
            if value < midpoint {
                dark.append((pixel, value))
            } else {
                light.append((pixel, value))
            }
        }
        guard !dark.isEmpty, !light.isEmpty else { return nil }

        let ink = extremeColour(of: dark, takingDarkest: true)
        let page = extremeColour(of: light, takingDarkest: false)
        let darkIsTheBackground = dark.count >= light.count

        return ContrastMeasurement(ratio: ratio(luminance(ink), luminance(page)),
                                   foreground: darkIsTheBackground ? page : ink,
                                   background: darkIsTheBackground ? ink : page)
    }

    /// The colour of one end of a group.
    ///
    /// - Parameters:
    ///   - group: The group's pixels, paired with their luminances so nothing is recomputed.
    ///   - takingDarkest: `true` for the darkest slice, `false` for the lightest.
    /// - Returns: The linear-light mean of that slice, which is at least one pixel however small
    ///   the group is.
    private static func extremeColour(of group: [(pixel: RGB, luminance: Double)],
                                      takingDarkest: Bool) -> RGB {
        let sorted = group.sorted { $0.luminance < $1.luminance }
        let count = max(1, Int((Double(sorted.count) * groupPercentile).rounded(.down)))
        let slice = takingDarkest ? sorted.prefix(count) : sorted.suffix(count)
        return linearMean(slice.map(\.pixel))
    }

    /// The mean of a group of pixels, taken in linear light.
    ///
    /// Each component is linearised, averaged, and encoded back to sRGB, so the returned colour
    /// is one a developer can read as a hex value *and* has exactly the luminance the group
    /// emits. Averaging the encoded components instead — which is what "average the bytes"
    /// means — overstates the luminance of any mixed group, by as much as 2.1× in reported ratio
    /// on a half-black, half-white sample.
    ///
    /// - Parameter pixels: The group. An empty group averages to black, which no caller here
    ///   passes: every call site has already guarded on at least one pixel.
    /// - Returns: Their average colour, in sRGB.
    static func linearMean(_ pixels: [RGB]) -> RGB {
        guard !pixels.isEmpty else { return RGB(red: 0, green: 0, blue: 0) }
        let count = Double(pixels.count)
        let red = pixels.reduce(0) { $0 + linearComponent($1.red) } / count
        let green = pixels.reduce(0) { $0 + linearComponent($1.green) } / count
        let blue = pixels.reduce(0) { $0 + linearComponent($1.blue) } / count
        return RGB(red: encodedComponent(red),
                   green: encodedComponent(green),
                   blue: encodedComponent(blue))
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
