@testable import Scyther
import XCTest

final class ContrastAnalyserTests: XCTestCase {

    private let black = RGB(red: 0, green: 0, blue: 0)
    private let white = RGB(red: 1, green: 1, blue: 1)

    /// The two anchors of the WCAG scale.
    func testBlackOnWhiteIsTwentyOneToOne() {
        let pixels = Array(repeating: white, count: 90) + Array(repeating: black, count: 10)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertEqual(measured?.ratio ?? 0, 21, accuracy: 0.05)
    }

    func testOneColourHasNoRatioToReport() {
        XCTAssertNil(ContrastAnalyser.measure(pixels: Array(repeating: white, count: 100)))
    }

    func testNoPixelsHaveNoRatioToReport() {
        XCTAssertNil(ContrastAnalyser.measure(pixels: []))
    }

    /// The larger group is the background, whichever way round the colours are.
    func testTheMajorityColourIsTheBackground() {
        let pixels = Array(repeating: black, count: 95) + Array(repeating: white, count: 5)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertEqual(measured?.background.red ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(measured?.foreground.red ?? 0, 1, accuracy: 0.01)
    }

    /// Mid grey on white fails AA; the check has to be able to say so.
    func testGreyOnWhiteFallsBelowTheAAThreshold() {
        let grey = RGB(red: 0.6, green: 0.6, blue: 0.6)
        let pixels = Array(repeating: white, count: 80) + Array(repeating: grey, count: 20)
        let measured = ContrastAnalyser.measure(pixels: pixels)
        XCTAssertLessThan(measured?.ratio ?? 99, 4.5)
    }

    /// The WCAG relative-luminance formula, at both ends.
    func testLuminanceMatchesTheWCAGFormula() {
        XCTAssertEqual(ContrastAnalyser.luminance(black), 0, accuracy: 0.0001)
        XCTAssertEqual(ContrastAnalyser.luminance(white), 1, accuracy: 0.0001)
    }
}

// MARK: - Sampling realism

extension ContrastAnalyserTests {

    /// A colour built from an 8-bit grey, the way a designer writes one.
    private func grey(_ value: Int) -> RGB {
        RGB(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
    }

    /// A crop of antialiased text, the way a rasteriser actually produces one.
    ///
    /// Twenty per cent glyph core, sixty per cent page, and twenty per cent edge pixels blended
    /// between the two at evenly spaced coverages — which is what the sampler hands the analyser
    /// for any real label, and the distribution on which a means-based split is wrong.
    ///
    /// - Parameters:
    ///   - ink: The text colour.
    ///   - page: The background colour.
    /// - Returns: One thousand pixels.
    private func antialiasedText(ink: RGB, page: RGB) -> [RGB] {
        var pixels = Array(repeating: ink, count: 200) + Array(repeating: page, count: 600)
        for step in 0..<200 {
            let coverage = (Double(step) + 0.5) / 200
            pixels.append(RGB(red: page.red + (ink.red - page.red) * coverage,
                              green: page.green + (ink.green - page.green) * coverage,
                              blue: page.blue + (ink.blue - page.blue) * coverage))
        }
        return pixels
    }

    /// `#767676` on white is WCAG's own canonical exactly-passing grey: 4.54:1.
    ///
    /// A tool that reports it as a failure is a tool a designer switches off, so this pins the
    /// number rather than merely asserting it clears the threshold.
    func testTheCanonicalPassingGreyMeasuresAsPassing() {
        let measured = ContrastAnalyser.measure(pixels: antialiasedText(ink: grey(0x76), page: white))

        XCTAssertEqual(measured?.ratio ?? 0, 4.54, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(measured?.ratio ?? 0, 4.5, "the canonical AA grey must not be failed")
    }

    /// The other anchor, measured through the same antialiasing.
    func testBlackTextOnWhiteStillMeasuresTwentyOneToOne() {
        let measured = ContrastAnalyser.measure(pixels: antialiasedText(ink: black, page: white))
        XCTAssertEqual(measured?.ratio ?? 0, 21, accuracy: 0.3)
    }

    /// Near-black pairs are the worst dark-mode failures and the ones an absolute luminance gate
    /// drops: `#000000` on `#0F0F0F` is 1.10:1 — invisible text — and must be reported.
    func testNearBlackTextIsMeasuredRatherThanDropped() {
        let pixels = Array(repeating: grey(0x0F), count: 80) + Array(repeating: black, count: 20)
        let measured = ContrastAnalyser.measure(pixels: pixels)

        XCTAssertNotNil(measured, "a near-black pair is the worst failure there is, not a non-answer")
        XCTAssertEqual(measured?.ratio ?? 0, 1.10, accuracy: 0.02)
    }

    /// The mirror case, so the gate is not simply removed and left to report noise: one 8-bit step
    /// apart at the light end is a flat surface, not text.
    func testAnAlmostFlatRegionHasNoRatioToReport() {
        let pixels = Array(repeating: white, count: 80) + Array(repeating: grey(0xFE), count: 20)
        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels))
    }
}

// MARK: - Linear light

extension ContrastAnalyserTests {

    /// Relative luminance is a linear-light quantity, so a group's colour has to be averaged in
    /// linear light. Averaging the gamma-encoded bytes of a half-black, half-white group reports
    /// 3.98:1 against white; the light those pixels actually emit is 1.91:1 — a 2.1× error from
    /// the averaging step alone.
    func testAMixedGroupIsAveragedInLinearLight() {
        let mean = ContrastAnalyser.linearMean([black, white])

        XCTAssertEqual(ContrastAnalyser.luminance(mean), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ContrastAnalyser.ratio(ContrastAnalyser.luminance(mean),
                                              ContrastAnalyser.luminance(white)), 1.91, accuracy: 0.01)
        XCTAssertEqual(mean.red, 0.7354, accuracy: 0.001, "and it comes back as a colour, not a luminance")
    }

    /// The encoding is the exact inverse of the linearisation, so a quoted hex colour is the
    /// colour whose luminance was measured rather than one a rounding error away from it.
    func testEncodingRoundTripsTheLinearisation() {
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(ContrastAnalyser.encodedComponent(ContrastAnalyser.linearComponent(step)),
                           step, accuracy: 0.0001)
        }
    }
}

// MARK: - What the estimator must not be fooled by

extension ContrastAnalyserTests {

    /// A colour built from an 8-bit grey, the way a designer writes one.
    private func level(_ value: Int) -> RGB {
        RGB(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
    }

    /// A crop of antialiased text with a chosen coverage profile.
    ///
    /// - Parameters:
    ///   - ink: The text colour.
    ///   - page: The background colour.
    ///   - core: How many fully covered pixels.
    ///   - surface: How many untouched background pixels.
    ///   - edge: How many partially covered pixels, at evenly spaced coverages.
    ///   - maximumCoverage: The highest coverage an edge pixel reaches. Below `1` this models a
    ///     glyph the sampler's stride never lands squarely on, which has no solid core at all.
    /// - Returns: The crop.
    private func crop(ink: RGB,
                      page: RGB,
                      core: Int,
                      surface: Int,
                      edge: Int,
                      maximumCoverage: Double = 1) -> [RGB] {
        var pixels = Array(repeating: ink, count: core) + Array(repeating: page, count: surface)
        for step in 0..<edge {
            let coverage = maximumCoverage * (Double(step) + 0.5) / Double(edge)
            pixels.append(RGB(red: page.red + (ink.red - page.red) * coverage,
                              green: page.green + (ink.green - page.green) * coverage,
                              blue: page.blue + (ink.blue - page.blue) * coverage))
        }
        return pixels
    }

    /// The regression the decile rewrite introduced, and the reason this file was rewritten again.
    ///
    /// A label's frame routinely contains a small dark thing that is not its text — an icon, a
    /// chevron, the corner of a neighbouring view. Representing the dark group by its darkest
    /// tenth let a `#333333` icon covering three per cent of the crop define "the ink", which
    /// turned `#949494` text at a genuine 3.03:1 into a reported 12.63:1 and therefore into no
    /// finding at all. The mean-based version this replaced reported 3.80:1 and *did* flag it: a
    /// silent regression on an input the older, cruder code got right.
    func testASmallDarkIntruderDoesNotDefineTheInk() {
        let pixels = Array(repeating: level(0x94), count: 150)
            + Array(repeating: level(0x33), count: 30)
            + Array(repeating: white, count: 820)

        let measured = ContrastAnalyser.measure(pixels: pixels)

        XCTAssertEqual(measured?.ratio ?? 0, 3.03, accuracy: 0.05, "the text is the ink, not the icon")
        XCTAssertLessThan(measured?.ratio ?? 99, 4.5, "a real AA failure must still be reported as one")
        XCTAssertEqual(measured?.foreground.hexDescription, "#949494")
        XCTAssertEqual(measured?.background.hexDescription, "#FFFFFF")
    }

    /// A gradient behind text has no background colour to quote, and quoting one is how the decile
    /// version passed `#666666` on a `#B0B0B0`→`#FFFFFF` ramp at 5.62:1 "estimated from #666666 on
    /// #FDFDFD" — the top of the ramp, a colour the text never sits on. The worst pairing a reader
    /// actually sees there is 2.65:1, which fails even the relaxed threshold.
    ///
    /// The honest answer is that this crop cannot be read as text on a surface, and the auditor
    /// reports that as "could not be measured" rather than as a pass.
    func testTextOnAGradientIsRefusedRatherThanPassed() {
        var pixels = Array(repeating: level(0x66), count: 200)
        for step in 0..<800 {
            let value = 0xB0 + (0xFF - 0xB0) * Double(step) / 799
            pixels.append(RGB(red: value / 255, green: value / 255, blue: value / 255))
        }

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels),
                     "a ramp is not a background colour; a number here would be invented")
    }

    /// Text over a photograph is the same defect in a different disguise.
    func testTextOnAPhotographIsRefused() {
        // A fixed linear congruential sequence rather than a random one: a test of a statistical
        // rule must not be able to fail on a Tuesday.
        var state: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40) / Double(1 << 24)
        }
        var pixels = Array(repeating: level(0x33), count: 200)
        for _ in 0..<800 {
            pixels.append(RGB(red: next(), green: next(), blue: next()))
        }

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels))
    }

    /// A glyph the sampler only ever catches at partial coverage has no ink colour in the crop at
    /// all. The decile read the darkest partial pixel as the ink and reported WCAG's canonical
    /// passing grey as 2.20:1 — a false failure on conformant text. There is no correct number to
    /// give here, so none is given.
    func testAGlyphWithNoSolidCoreIsRefusedRatherThanUnderstated() {
        let pixels = crop(ink: level(0x76), page: white,
                          core: 0, surface: 700, edge: 300, maximumCoverage: 0.6)

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels))
    }

    /// Half a black view beside half a white one is a boundary, not a glyph on a surface: there is
    /// no minority group, so nothing says which side is the text. 21:1 there is a pass nobody
    /// earned, and the linear mean's 1.91:1 is a failure nobody earned either.
    func testAnEvenlySplitCropHasNoInkToIdentify() {
        let pixels = Array(repeating: black, count: 500) + Array(repeating: white, count: 500)

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels),
                     "neither 21:1 nor 3.98:1 is a defensible answer for a crop with no minority tone")
    }

    /// The reported ratio has to be one the finding can state. Below 1.05 it renders as
    /// "About 1.0:1", which is a sentence with no content, on a pair the check cannot tell from an
    /// artefact of its own capture. `#7F7F7F` on `#818181` — two 8-bit steps of dither — cleared
    /// the old 1.02 gate and was reported as a finding.
    func testTwoStepsOfDitherAreNotAFinding() {
        let pixels = Array(repeating: level(0x7F), count: 600) + Array(repeating: level(0x81), count: 400)

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels))
    }

    /// The measured false positive from a real device: a caption scrolled underneath a navigation
    /// bar is sampled through the bar's near-black scroll-edge material and used to report
    /// "About 1.0:1 … #0A0A0A on #040404" against the 4.5:1 text threshold. The occlusion itself is
    /// `AuditNode`'s to fix; the analyser's part is never to emit a confident number from a crop
    /// like this one.
    func testNearBlackBarMaterialIsNotAFinding() {
        let pixels = Array(repeating: level(0x04), count: 800) + Array(repeating: level(0x0A), count: 200)

        XCTAssertNil(ContrastAnalyser.measure(pixels: pixels))
    }

    /// The constraint that sets the gate: `#000000` on `#0F0F0F` is 1.10:1, is genuinely invisible
    /// text, and must survive. Pinned here as well as above so a future tightening of the gate
    /// cannot pass silently.
    func testTheDarkestRealDefectSurvivesTheGate() {
        let pixels = Array(repeating: level(0x0F), count: 800) + Array(repeating: black, count: 200)
        let measured = ContrastAnalyser.measure(pixels: pixels)

        XCTAssertEqual(measured?.ratio ?? 0, 1.0954, accuracy: 0.005)
    }

    /// Ordinary antialiasing is unchanged by all of the above: the canonical grey still measures
    /// 4.54:1 with a lighter glyph weight than the suite's default helper produces.
    func testALighterGlyphWeightStillRecoversTheCanonicalGrey() {
        let pixels = crop(ink: level(0x76), page: white, core: 100, surface: 600, edge: 300)
        let measured = ContrastAnalyser.measure(pixels: pixels)

        XCTAssertEqual(measured?.ratio ?? 0, 4.54, accuracy: 0.05)
    }

    /// A crop too small to cluster is refused: in a four-pixel group every pixel is 100% of its own
    /// group, so the share tests would wave anything through.
    func testACropTooSmallToClusterIsRefused() {
        XCTAssertNil(ContrastAnalyser.measure(pixels: [black, white, black, white]))
    }

    /// Light text on a dark surface is the same problem the other way up, and the minority rule has
    /// to identify the ink by size rather than by darkness.
    func testLightTextOnADarkSurfaceIsMeasured() {
        let measured = ContrastAnalyser.measure(pixels: crop(ink: white, page: level(0x1C),
                                                             core: 200, surface: 600, edge: 200))

        XCTAssertEqual(measured?.foreground.hexDescription, "#FFFFFF")
        XCTAssertEqual(measured?.background.hexDescription, "#1C1C1C")
        XCTAssertGreaterThan(measured?.ratio ?? 0, 15)
    }
}
