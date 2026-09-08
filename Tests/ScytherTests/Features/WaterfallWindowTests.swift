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

    // MARK: - The opening window
    //
    // Third rule pinned here, not the first two. `opening(span:narrowest:medianMeasured:plotWidth:)`
    // used to size the window so the *median* measured request rendered legibly, which is why
    // this section's tests used to pass a `medianMeasured` figure and check the arithmetic that
    // derived from it. That rule opened too tight in ordinary use — a 19-request log opened on
    // `1 of 19` — and was replaced with a flat half-span default that takes no per-request
    // duration as input at all; see `WaterfallWindow.opening(span:narrowest:)`'s own "Two rules
    // before this one" for the full account of both this rule and the one before it. The tests
    // below are the same tests, updated for the new signature and rule rather than deleted:
    // `testOpeningOnAShortLogIsTheWholeSpan` and `testOpeningWithOneMeasurementIsTheWholeSpan`
    // still pin the same whole-span degenerate case, now reached because the narrowest limit
    // itself equals the span rather than because a median-demanded width happened to exceed it.
    // `testOpeningWithNothingMeasuredIsTheWholeSpan` collapsed into
    // `testOpeningWithOneMeasurementIsTheWholeSpan` once both reduced to the identical
    // `narrowest == span` call this rule no longer distinguishes by "what was measured" — this
    // function does not see measurements at all any more, only the `narrowest` its caller already
    // derived from them.

    /// A log whose narrowest limit already sits above half its span opens at that limit, not at
    /// the plain half — the case the owner's own wording named directly: "a log short enough that
    /// half its span is below the narrowest limit simply gets the narrowest."
    func testOpeningBelowTheNarrowestLimitOpensAtTheNarrowestLimit() {
        // Half of a 10s span is 5s, short of the 8s floor, so the floor wins.
        let window = WaterfallWindow.opening(span: 10, narrowest: 8)
        XCTAssertEqual(window.duration, 8, accuracy: 0.0001)
        XCTAssertEqual(window.start, 2, accuracy: 0.0001)
        XCTAssertEqual(window.end, 10, accuracy: 0.0001, "anchored on the newest traffic")
    }

    /// The ordinary case: half the span, anchored on the newest traffic, with room either side of
    /// both limits so neither clamp applies.
    func testOpeningIsHalfTheSpan() {
        let window = WaterfallWindow.opening(span: 60, narrowest: 1)
        XCTAssertEqual(window.duration, 30, accuracy: 0.0001)
        XCTAssertEqual(window.start, 30, accuracy: 0.0001)
        XCTAssertEqual(window.end, 60, accuracy: 0.0001, "anchored on the newest traffic")
    }

    /// The case the owner originally reported, re-pinned against the current rule: a long log —
    /// modelled on the hour-long capture with two bursts of traffic an hour apart — opens anchored
    /// on the newest traffic and as a genuine subset, rather than at the whole span with every bar
    /// floored to the same three points.
    func testOpeningOnALongLogAnchorsOnTheNewestTrafficAtHalfTheSpan() {
        let window = WaterfallWindow.opening(span: 3_522, narrowest: 0.5)
        XCTAssertEqual(window.duration, 1_761, accuracy: 0.0001, "half of 3,522")
        XCTAssertEqual(window.end, 3_522, accuracy: 0.0001, "anchored on the newest traffic")
        XCTAssertEqual(window.start, 1_761, accuracy: 0.0001)
        XCTAssertTrue(window.marksASubset, "so the strip's overlay draws the moment the page opens")
    }

    /// A log short enough that half its own span still sits inside the narrowest limit opens at
    /// the whole span — the same degenerate case a log too short to zoom at all always produces,
    /// whatever rule computes the demanded width.
    func testOpeningOnAShortLogIsTheWholeSpan() {
        // Half of 0.3s is 0.15s, short of the 0.2s floor, so the floor wins and happens to equal
        // the whole span exactly.
        let window = WaterfallWindow.opening(span: 0.2, narrowest: 0.2)
        XCTAssertEqual(window.start, 0, accuracy: 0.0001)
        XCTAssertEqual(window.duration, 0.2, accuracy: 0.0001)
    }

    /// A single measurement makes the narrowest limit equal to the span outright — see
    /// `narrowestDuration(shortestMeasured:span:plotWidth:)`'s own tests for why — so the window
    /// opens at the whole span and `canZoom` is already `false` for the same underlying reason.
    /// This is also what a log with nothing measured at all produces, since
    /// `narrowestDuration(shortestMeasured:span:plotWidth:)` falls back to the same `narrowest ==
    /// span` for both: this function no longer distinguishes the two, because it no longer reads
    /// measurements of any kind, only whatever `narrowest` its caller already derived from them.
    func testOpeningWithOneMeasurementIsTheWholeSpan() {
        let window = WaterfallWindow.opening(span: 0.12, narrowest: 0.12)
        XCTAssertEqual(window.start, 0, accuracy: 0.0001)
        XCTAssertEqual(window.duration, 0.12, accuracy: 0.0001)
        XCTAssertFalse(window.canZoom)
    }

    /// An empty series opens at the same degenerate, non-dividing-by-zero window every other
    /// empty-series case on this type produces.
    func testOpeningAnEmptySeriesIsTheEmptyWindow() {
        let window = WaterfallWindow.opening(span: 0, narrowest: 0)
        XCTAssertEqual(window.start, 0)
        XCTAssertEqual(window.duration, 0)
        XCTAssertFalse(window.canZoom)
    }

    // MARK: - Marking a subset

    /// A window at the whole span — a short log's opening window, or any log once zoomed all the
    /// way back out — is exactly the case an overlay must not be drawn for: edge to edge, it
    /// would tint the entire strip one solid colour rather than mark a subset of it.
    func testTheWidestWindowDoesNotMarkASubset() {
        XCTAssertFalse(WaterfallWindow(span: 60, narrowest: 1).marksASubset)
    }

    /// The moment a zoom or a drag narrows the window at all, it is worth drawing.
    func testANarrowedWindowMarksASubset() {
        let window = WaterfallWindow(start: 20, duration: 20, span: 60, narrowest: 1)
        XCTAssertTrue(window.marksASubset)
    }

    /// The degenerate empty-series window answers the opposite of `durationFraction` here, on
    /// purpose: `durationFraction` defaults to `1` so `WaterfallStripGeometry`'s arithmetic never
    /// divides by a span of zero, but a window with nothing to be a subset of is not a subset,
    /// and must not be drawn as an overlay covering a strip that has nothing on it either.
    func testAnEmptySeriesWindowDoesNotMarkASubset() {
        let window = WaterfallWindow(span: 0, narrowest: 0)
        XCTAssertEqual(window.durationFraction, 1, "what windowRect would be drawn at, if asked")
        XCTAssertFalse(window.marksASubset, "but there is nothing here to be a subset of")
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
