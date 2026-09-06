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
