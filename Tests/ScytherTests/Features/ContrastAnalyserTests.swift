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
