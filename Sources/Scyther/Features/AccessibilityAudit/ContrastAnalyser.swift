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

    /// The ink: the dominant colour of the *smaller* of the two tonal groups, which is the group
    /// text falls into — a glyph run never covers as much of its own frame as the surface behind
    /// it does.
    let foreground: RGB

    /// The page: the dominant colour of the larger group, i.e. the surface the ink sits on.
    let background: RGB
}

/// Turns pixels into a contrast ratio.
///
/// The job is to recover *two colours* — the ink and the page — from a crop that also contains
/// every intermediate shade the rasteriser painted along each glyph's edge, and quite often a
/// third thing the crop was never meant to include: an icon beside the text, a gradient, a photo,
/// the corner of a neighbouring view. Four decisions carry that:
///
/// - **Everything is averaged in linear light.** Relative luminance is a linear-light quantity
///   and linearisation is convex, so `L(mean(c)) ≠ mean(L(c))`: averaging the gamma-encoded
///   bytes of a half-black, half-white group reports 3.98:1 against white where the light those
///   pixels actually emit is 1.91:1. Averaging in linear light is not a refinement, it is the
///   only averaging that answers the question the ratio formula asks.
/// - **The two groups are found by clustering, not by a fixed split.** ``twoMeansThreshold(of:)``
///   runs Lloyd's algorithm on the luminances, so the boundary between ink and page lands where
///   the pixels are actually sparse rather than at the midpoint of whatever the extremes happen
///   to be.
/// - **Each group is represented by its *mode*, not by its mean and not by its extreme.** This is
///   the decision the previous two versions of this file both got wrong, in opposite directions.
///   A mean is dragged toward the middle by the antialiased skirt, which reported `#767676` on
///   `#FFFFFF` — WCAG's canonical exactly-passing grey — as 3.5:1. An extreme decile is defined by
///   whatever is darkest or lightest anywhere in the crop, so a `#333333` icon covering three per
///   cent of a label's frame turned `#949494` text at a real 3.03:1 into a reported 12.63:1 and no
///   finding at all. A mode is defined by the pixels there are *most of*, which is what "the colour
///   the text is drawn in" and "the colour behind it" actually mean, and neither the skirt nor a
///   small intruder can move it. See ``dominantColour(of:coveringAtLeast:)``.
/// - **A crop with no two-tone structure is refused rather than estimated.** Text on a gradient,
///   text on a photograph, and a glyph the sampler only ever caught at partial coverage all
///   produce groups with no dominant colour in them, and the honest answer there is `nil` — which
///   the auditor reports as "could not be measured" — rather than a confident ratio taken between
///   two colours nobody drew. Every previous version answered those with a number.
///
/// It remains an estimate, which is why every finding it produces is a warning that says so.
enum ContrastAnalyser {
    /// The fewest pixels a crop can have and still be clustered.
    ///
    /// Below this a "group" is one or two pixels and its mode is noise rather than a colour: the
    /// share tests underneath would be satisfied by any crop at all, because a single pixel is
    /// always 100% of a one-pixel group. Sixteen is a 4 × 4 crop, which is smaller than any real
    /// element the sampler is asked about once the capture scale is applied.
    static let smallestUsefulSample = 16

    /// The smallest ratio worth calling a measurement.
    ///
    /// Set by what the report can honestly *say*. A finding quotes the ratio to one decimal place,
    /// so anything below 1.05 renders as "About 1.0:1" — a sentence that tells a developer
    /// nothing, on a pair of colours the check cannot distinguish from an artefact of its own
    /// capture. Below the gate the element is reported as unmeasurable, which is a different claim
    /// from a pass and is rendered differently.
    ///
    /// What that number rejects, computed rather than asserted: one 8-bit step of dither or
    /// banding is a ratio of 1.0061 near black, 1.0140 at mid grey and 1.0086 near white, so the
    /// gate clears two or three steps of it everywhere on the scale — the previous 1.02 cleared
    /// one step at mid grey and admitted the rest, and reported `#7F7F7F` on `#818181` as a
    /// finding. It also drops `#0A0A0A` on `#040404` (1.0356), which is what a caption scrolled
    /// under a navigation bar measures, and `#000000` on `#050505` (1.0304), which is dark-mode
    /// banding.
    ///
    /// What it keeps is the constraint that sets it: `#000000` on `#0F0F0F` is 1.0954, is genuinely
    /// invisible text, and must be reported. The gate is therefore as tight as the darkest real
    /// defect allows and no tighter.
    static let smallestMeaningfulRatio: Double = 1.05

    /// How far either side of a group's peak code level still counts as the same colour.
    ///
    /// One 8-bit level, i.e. a three-level band. A flat surface in a real snapshot does not land on
    /// a single code: quantisation, the sRGB conversion in `WindowContrastSampler.rgbaBytes` and
    /// the compositor's own dithering spread it over two or three adjacent levels, and a peak read
    /// from a single level would report a fraction of the pixels that are really that colour and
    /// fail the share tests on perfectly ordinary text.
    static let dominantBandRadius = 1

    /// How much of the ink group its dominant colour has to cover.
    ///
    /// Lower than ``smallestPageShare`` because the ink group is the antialiased one: the split
    /// puts every edge pixel darker than the boundary in here, and at ordinary body-text weights
    /// the solid core of a stem is about a third of what lands in the group. A quarter allows for
    /// lighter weights and smaller sizes.
    ///
    /// It is not lower still on purpose. A dark group with no colour in it worth a quarter is not
    /// a glyph — it is a shadow, a photograph, a second gradient, or a glyph the sampler only ever
    /// caught at partial coverage, and that last case is the one that used to report WCAG's
    /// canonical passing grey as 2.20:1. None of them has an ink colour to quote.
    static let smallestInkShare: Double = 0.25

    /// How much of the page group its dominant colour has to cover.
    ///
    /// A half. The surface behind text is a fill: it is one colour over nearly all of the group,
    /// and the only pixels in the group that are not it are the lighter half of the antialiased
    /// skirt. When it is *not* one colour — a gradient, a photograph, a card edge crossing the
    /// crop — there is no "background colour" to quote and no single ratio that describes what the
    /// reader sees, so the measurement is refused. That refusal is the whole answer to a gradient:
    /// the previous version quoted the lightest end of the ramp, a colour the text never sits on,
    /// and passed the element.
    static let smallestPageShare: Double = 0.5

    /// How many refinement passes ``twoMeansThreshold(of:)`` makes before it settles for what it
    /// has.
    ///
    /// Lloyd's algorithm in one dimension converges monotonically and in practice in fewer than
    /// ten passes; the cap only exists so a pathological input cannot spin the main thread, and
    /// stopping early yields a slightly worse boundary rather than a wrong one.
    static let maximumClusteringPasses = 32

    /// How close two successive cluster centres have to be before clustering stops.
    static let clusteringTolerance: Double = 1e-9

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

    /// The 8-bit grey level a luminance corresponds to.
    ///
    /// Binning happens in the *encoded* domain rather than in luminance, because that is the domain
    /// the pixels arrived in: one bin is one 8-bit code, so a flat surface lands in one bin at
    /// every point on the scale. Binning luminance directly would give near-black codes bins
    /// thousands of times narrower than near-white ones, and a dark-mode background would be
    /// scattered across dozens of them.
    ///
    /// Two colours of different hue but equal luminance share a bin. That is correct for a contrast
    /// ratio, which is a function of luminance alone; the consequence is only that the hex a
    /// finding quotes for such a band is the average of them, which ``linearMean(_:)`` makes a
    /// colour of exactly the right luminance.
    ///
    /// - Parameter luminance: The pixel's relative luminance.
    /// - Returns: A bin index from `0` to `255`.
    static func codeLevel(of luminance: Double) -> Int {
        let encoded = encodedComponent(min(max(luminance, 0), 1))
        return min(255, max(0, Int((encoded * 255).rounded())))
    }

    /// The luminance that best separates a crop into two groups.
    ///
    /// Lloyd's algorithm — two-means — seeded at the darkest and lightest luminance present. Each
    /// pass assigns every pixel to the nearer of the two centres (in one dimension that is just
    /// "which side of the midpoint") and moves each centre to the mean of what it was given.
    ///
    /// The fixed midpoint of the extremes that this replaces is a boundary chosen by the two most
    /// unusual pixels in the crop. On white text over a `#1C1C1E` card with one white hairline, the
    /// midpoint sits at 50% luminance and cuts the *page* group in half. Clustering puts the
    /// boundary in the sparse region between the two populations instead, which is where the ink
    /// stops and the page starts.
    ///
    /// - Parameter luminances: Every pixel's luminance, in any order.
    /// - Returns: The threshold; pixels below it are the dark group and the rest the light group.
    static func twoMeansThreshold(of luminances: [Double]) -> Double {
        guard let lowest = luminances.min(), let highest = luminances.max() else { return 0 }
        var darkCentre = lowest
        var lightCentre = highest

        for _ in 0..<maximumClusteringPasses {
            let threshold = (darkCentre + lightCentre) / 2
            var darkSum = 0.0
            var darkCount = 0
            var lightSum = 0.0
            var lightCount = 0
            for value in luminances {
                if value < threshold {
                    darkSum += value
                    darkCount += 1
                } else {
                    lightSum += value
                    lightCount += 1
                }
            }
            // One empty side means every pixel is on one side of the midpoint of the extremes,
            // which only happens when the two centres have already collapsed together; the
            // boundary in hand is the best one available.
            guard darkCount > 0, lightCount > 0 else { break }

            let movedDark = darkSum / Double(darkCount)
            let movedLight = lightSum / Double(lightCount)
            let settled = abs(movedDark - darkCentre) < clusteringTolerance
                && abs(movedLight - lightCentre) < clusteringTolerance
            darkCentre = movedDark
            lightCentre = movedLight
            if settled { break }
        }
        return (darkCentre + lightCentre) / 2
    }

    /// Measures a region's contrast.
    ///
    /// Clusters the pixels into two tonal groups, calls the smaller group the ink and the larger
    /// the page, and represents each by the colour most of its pixels actually are. Answers `nil` —
    /// which the auditor reports as "could not be measured", never as a pass — whenever the crop
    /// cannot support that reading:
    ///
    /// - fewer than ``smallestUsefulSample`` pixels;
    /// - everything within ``smallestMeaningfulRatio`` of one colour, which is a flat surface, a
    ///   dithered material or a bar the element has scrolled underneath, not text;
    /// - the two groups exactly the same size, so neither is the minority and there is no way to
    ///   tell which side is the text. Real text never covers half its own frame — the leading, the
    ///   side bearings and the space above the cap height see to that — so an evenly split crop is
    ///   a boundary between two regions rather than a glyph on a surface, and a confident 21:1 for
    ///   half a black view beside half a white one is a pass nobody earned;
    /// - either group with no dominant colour in it, per ``smallestInkShare`` and
    ///   ``smallestPageShare``.
    ///
    /// - Parameter pixels: The region's pixels.
    /// - Returns: The measurement, or `nil` when the crop cannot be read as text on a surface.
    static func measure(pixels: [RGB]) -> ContrastMeasurement? {
        guard pixels.count >= smallestUsefulSample else { return nil }

        let luminances = pixels.map(luminance)
        guard let darkest = luminances.min(), let lightest = luminances.max(),
              ratio(lightest, darkest) >= smallestMeaningfulRatio else { return nil }

        let threshold = twoMeansThreshold(of: luminances)
        var dark: [(pixel: RGB, luminance: Double)] = []
        var light: [(pixel: RGB, luminance: Double)] = []
        for (pixel, value) in zip(pixels, luminances) {
            if value < threshold {
                dark.append((pixel, value))
            } else {
                light.append((pixel, value))
            }
        }
        guard !dark.isEmpty, !light.isEmpty, dark.count != light.count else { return nil }

        let inkGroup = dark.count < light.count ? dark : light
        let pageGroup = dark.count < light.count ? light : dark
        guard let ink = dominantColour(of: inkGroup, coveringAtLeast: smallestInkShare),
              let page = dominantColour(of: pageGroup, coveringAtLeast: smallestPageShare) else {
            return nil
        }

        // The gate is applied again to the two colours actually recovered. The first application
        // is on the crop's extremes, which is the widest spread it contains and therefore the
        // loosest form of the test; a crop can clear it on an intruder and still turn out to have
        // two near-identical dominant colours.
        let measured = ratio(luminance(ink), luminance(page))
        guard measured >= smallestMeaningfulRatio else { return nil }

        return ContrastMeasurement(ratio: measured, foreground: ink, background: page)
    }

    /// The colour a group mostly is, or `nil` when it is not mostly any colour.
    ///
    /// Histograms the group by 8-bit grey level, takes the tallest bin together with its immediate
    /// neighbours (see ``dominantBandRadius``), and returns that band's linear-light mean — but
    /// only if the band holds at least `share` of the group. That share test is the whole
    /// difference between an estimate and a guess: a gradient, a photograph and a partially covered
    /// glyph all produce a group whose pixels are spread evenly across dozens of levels, where the
    /// tallest bin is an accident of where the ramp happened to land and quoting it would be
    /// inventing a colour.
    ///
    /// Ties are broken toward the darker level so the answer does not depend on dictionary
    /// ordering, which is not stable between runs.
    ///
    /// - Parameters:
    ///   - group: The group's pixels, paired with their luminances so nothing is recomputed.
    ///   - share: The fraction of the group the dominant band has to cover.
    /// - Returns: The dominant colour, or `nil` when the group has no dominant colour.
    static func dominantColour(of group: [(pixel: RGB, luminance: Double)],
                               coveringAtLeast share: Double) -> RGB? {
        guard !group.isEmpty else { return nil }

        var levels: [Int: [RGB]] = [:]
        for entry in group {
            levels[codeLevel(of: entry.luminance), default: []].append(entry.pixel)
        }
        guard let peak = levels.max(by: { first, second in
            first.value.count == second.value.count
                ? first.key > second.key
                : first.value.count < second.value.count
        })?.key else { return nil }

        var band: [RGB] = []
        for level in (peak - dominantBandRadius)...(peak + dominantBandRadius) {
            band.append(contentsOf: levels[level] ?? [])
        }
        guard Double(band.count) / Double(group.count) >= share else { return nil }
        return linearMean(band)
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
