//
//  WaterfallWindowTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers every rule about what slice of the log is visible. These are the rules the pinch
/// gesture cannot be trusted to enforce, which is why they live in a value type rather than in
/// the view: a gesture is not unit-testable and this is.
final class WaterfallWindowTests: XCTestCase {

    func testTheWidestWindowIsTheWholeSpan() {
        let window = WaterfallWindow(span: 60, narrowest: 0.5)
        XCTAssertEqual(window.start, 0)
        XCTAssertEqual(window.duration, 60)
    }

    func testZoomingInHoldsTheCentreStill() {
        let window = WaterfallWindow(start: 20, duration: 20, span: 60, narrowest: 0.5)
        let zoomed = window.zoomed(by: 2)

        XCTAssertEqual(zoomed.duration, 10, accuracy: 0.0001)
        XCTAssertEqual(zoomed.centre, 30, accuracy: 0.0001,
                       "pinching changes resolution, not position")
    }

    func testZoomingCannotGoNarrowerThanTheLimit() {
        let window = WaterfallWindow(start: 0, duration: 60, span: 60, narrowest: 2)
        XCTAssertEqual(window.zoomed(by: 1_000).duration, 2, accuracy: 0.0001)
    }

    func testZoomingCannotGoWiderThanTheSpan() {
        let window = WaterfallWindow(start: 20, duration: 10, span: 60, narrowest: 2)
        let zoomed = window.zoomed(by: 0.001)

        XCTAssertEqual(zoomed.duration, 60, accuracy: 0.0001)
        XCTAssertEqual(zoomed.start, 0, accuracy: 0.0001)
    }

    /// Zooming out at the right-hand end has to pull the window back rather than let it hang off
    /// the end of the log, which would show time that does not exist.
    func testZoomingOutAtTheEndPullsTheWindowBackInsteadOfOverhanging() {
        let window = WaterfallWindow(start: 55, duration: 5, span: 60, narrowest: 1)
        let zoomed = window.zoomed(by: 0.25)

        XCTAssertEqual(zoomed.duration, 20, accuracy: 0.0001)
        XCTAssertEqual(zoomed.start, 40, accuracy: 0.0001)
        XCTAssertEqual(zoomed.end, 60, accuracy: 0.0001)
    }

    func testMovingClampsToTheSpanAtBothEnds() {
        let window = WaterfallWindow(start: 20, duration: 10, span: 60, narrowest: 1)

        XCTAssertEqual(window.movedToCentre(-100).start, 0, accuracy: 0.0001)
        XCTAssertEqual(window.movedToCentre(1_000).start, 50, accuracy: 0.0001)
        XCTAssertEqual(window.movedToCentre(30).start, 25, accuracy: 0.0001)
    }

    func testAnEntryStartingBeforeTheWindowAndEndingInsideItIsContained() {
        let window = WaterfallWindow(start: 10, duration: 10, span: 60, narrowest: 1)
        XCTAssertTrue(window.contains(start: 5, duration: 8),
                      "a request already in flight when the window opens is in the window")
        XCTAssertTrue(window.contains(start: 18, duration: 30),
                      "a request that outlives the window is in the window")
        XCTAssertFalse(window.contains(start: 0, duration: 3))
        XCTAssertFalse(window.contains(start: 40, duration: 3))
    }

    /// A zero-length request at the window's edge is still something that happened there.
    func testAZeroLengthEntryOnTheEdgeIsContained() {
        let window = WaterfallWindow(start: 10, duration: 10, span: 60, narrowest: 1)
        XCTAssertTrue(window.contains(start: 10, duration: 0))
        XCTAssertTrue(window.contains(start: 20, duration: 0))
    }

    // MARK: - The narrowest duration

    func testTheNarrowestWindowMakesTheShortestRequestLegible() {
        // 20ms drawn at 24pt across a 240pt plot => a 0.2s window.
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: 0.02,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 0.2, accuracy: 0.0001)
    }

    func testASeriesWhoseShortestRequestIsAlreadyLegibleCannotZoom() {
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: 30,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 60, "there is nothing left to magnify")
        XCTAssertFalse(WaterfallWindow(span: 60, narrowest: narrowest).canZoom)
    }

    func testASeriesWithNothingMeasuredCannotZoom() {
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: nil,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 60)
    }

    func testAnEmptySeriesProducesAWindowThatDoesNotDivideByZero() {
        let window = WaterfallWindow(span: 0, narrowest: 0)
        XCTAssertEqual(window.duration, 0)
        XCTAssertFalse(window.canZoom)
        XCTAssertEqual(window.startFraction, 0)
        XCTAssertEqual(window.durationFraction, 1)
        XCTAssertEqual(window.zoomed(by: 4), window)
    }

    // MARK: - Opening centred

    func testOpeningCentredOnATimeClampsIntoTheSpan() {
        let widest = WaterfallWindow(span: 80, narrowest: 1)
        let opened = widest.centred(on: 2, duration: 10)

        XCTAssertEqual(opened.duration, 10, accuracy: 0.0001)
        XCTAssertEqual(opened.start, 0, accuracy: 0.0001,
                       "a tap near the start opens at the start, not before it")
    }

    // MARK: - Non-finite input

    /// The non-finite values every case below is driven with: not-a-number, positive infinity and
    /// negative infinity.
    private static let nonFiniteValues: [Double] = [.nan, .infinity, -.infinity]

    /// Every property of `window` is finite.
    ///
    /// `init(start:duration:span:narrowest:)` is documented as clamping every one of its inputs
    /// before the two `min`/`max` chains run, which is what is supposed to make NaN and infinity
    /// unable to propagate. That claim previously rested on a reviewer's hand-trace rather than a
    /// test, for the one type the rest of the feature leans on — so it is pinned here.
    private func assertAllFinite(_ window: WaterfallWindow, file: StaticString = #filePath,
                                 line: UInt = #line) {
        XCTAssertTrue(window.start.isFinite, "start", file: file, line: line)
        XCTAssertTrue(window.duration.isFinite, "duration", file: file, line: line)
        XCTAssertTrue(window.span.isFinite, "span", file: file, line: line)
        XCTAssertTrue(window.narrowest.isFinite, "narrowest", file: file, line: line)
        XCTAssertTrue(window.end.isFinite, "end", file: file, line: line)
        XCTAssertTrue(window.centre.isFinite, "centre", file: file, line: line)
        XCTAssertTrue(window.startFraction.isFinite, "startFraction", file: file, line: line)
        XCTAssertTrue(window.durationFraction.isFinite, "durationFraction", file: file, line: line)
    }

    func testInitIsFiniteAgainstNonFiniteStart() {
        for value in Self.nonFiniteValues {
            assertAllFinite(WaterfallWindow(start: value, duration: 10, span: 60, narrowest: 1))
        }
    }

    func testInitIsFiniteAgainstNonFiniteDuration() {
        for value in Self.nonFiniteValues {
            assertAllFinite(WaterfallWindow(start: 0, duration: value, span: 60, narrowest: 1))
        }
    }

    func testInitIsFiniteAgainstNonFiniteSpan() {
        for value in Self.nonFiniteValues {
            assertAllFinite(WaterfallWindow(start: 0, duration: 10, span: value, narrowest: 1))
        }
    }

    func testInitIsFiniteAgainstNonFiniteNarrowest() {
        for value in Self.nonFiniteValues {
            assertAllFinite(WaterfallWindow(start: 0, duration: 10, span: 60, narrowest: value))
        }
    }

    func testZoomedIsFiniteAgainstANonFiniteFactor() {
        let window = WaterfallWindow(start: 20, duration: 20, span: 60, narrowest: 0.5)
        for value in Self.nonFiniteValues {
            assertAllFinite(window.zoomed(by: value))
        }
    }

    /// A window that is itself built from non-finite input must still zoom to something finite.
    func testZoomedIsFiniteWhenTheWindowItselfCameFromNonFiniteInput() {
        for value in Self.nonFiniteValues {
            let window = WaterfallWindow(start: value, duration: value, span: value, narrowest: value)
            assertAllFinite(window.zoomed(by: 2))
        }
    }

    func testMovedToCentreIsFiniteAgainstANonFiniteTime() {
        let window = WaterfallWindow(start: 20, duration: 20, span: 60, narrowest: 0.5)
        for value in Self.nonFiniteValues {
            assertAllFinite(window.movedToCentre(value))
        }
    }

    /// A window that is itself built from non-finite input must still move to something finite.
    func testMovedToCentreIsFiniteWhenTheWindowItselfCameFromNonFiniteInput() {
        for value in Self.nonFiniteValues {
            let window = WaterfallWindow(start: value, duration: value, span: value, narrowest: value)
            assertAllFinite(window.movedToCentre(10))
        }
    }
}
