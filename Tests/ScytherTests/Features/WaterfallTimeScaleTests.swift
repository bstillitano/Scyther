//
//  WaterfallTimeScaleTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import Foundation
import XCTest

/// Covers the arithmetic that decides how many points of the full-log page one second is worth.
///
/// The page used to divide the whole session across one screen width, which is the defect these
/// tests exist to prevent coming back: against the owner's own log — about three hundred seconds
/// of traffic, individual requests between thirty-two milliseconds and one and a half seconds —
/// every bar collapsed to the one point minimum and a 32 ms request and a 1.4 s request drew
/// identically. The numbers below are that log's numbers, not a synthetic case.
@MainActor
final class WaterfallTimeScaleTests: XCTestCase {

    /// The plot window on an iPhone-sized page, in points.
    ///
    /// `402` is the iPhone 17 Pro's width; the chrome the card, its padding and the frozen label
    /// column take is subtracted by the same function the view uses, so the figure the tests
    /// reason about is the one the device draws.
    private let visibleWidth = WaterfallChartStyle.plotWidth(inPageWidth: 402)

    /// The owner's session length, in seconds.
    private let ownersSpan: TimeInterval = 300

    /// Builds a bar with the given shape.
    ///
    /// - Parameters:
    ///   - start: Seconds from the series origin to the bar starting.
    ///   - duration: How long the bar runs, in seconds.
    ///   - pending: Whether the request is still in flight.
    /// - Returns: The bar.
    private func entry(start: TimeInterval = 0,
                       duration: TimeInterval,
                       pending: Bool = false) -> WaterfallEntry {
        WaterfallEntry(
            id: UUID().uuidString,
            label: "GET /v1/users",
            start: start,
            duration: duration,
            isFailure: false,
            isPending: pending,
            isStubbed: false
        )
    }

    /// The scale for the owner's log: a 300 second span whose typical request takes 250 ms and
    /// whose fastest tenth take about 40 ms.
    private var ownersScale: WaterfallTimeScale {
        WaterfallTimeScale.make(
            medianDuration: 0.25,
            tailDuration: 0.04,
            span: ownersSpan,
            visibleWidth: visibleWidth
        )
    }

    // MARK: - The rule

    /// The point of the scale: the request in the middle of the log is drawn at a width a reader
    /// can actually compare against its neighbours, rather than at whatever fraction of one
    /// screen its duration happens to be.
    func testTheTypicalRequestIsDrawnAtTheTargetWidth() {
        XCTAssertEqual(ownersScale.width(ofSeconds: 0.25), WaterfallTimeScale.medianBarWidth,
                       accuracy: 0.01,
                       "the median request is what \"ordinary\" means for this log")
    }

    /// The owner's complaint, stated as an assertion. A 32 ms request has to be visible as
    /// something other than the one point floor, or the chart is not showing what it exists for.
    func testTheFastestRequestInTheOwnersLogIsWiderThanACoupleOfPoints() {
        XCTAssertGreaterThan(ownersScale.width(ofSeconds: 0.032), 2,
                             "a 32 ms bar under two points is the defect this replaced")
    }

    /// The two ends of the owner's log have to be told apart at a glance. They differ by a factor
    /// of nearly forty-four in duration, so they have to differ by about that in ink.
    func testTheOwnersFastestAndSlowestRequestsAreNotDrawnTheSame() {
        let fast = ownersScale.width(ofSeconds: 0.032)
        let slow = ownersScale.width(ofSeconds: 1.4)
        XCTAssertEqual(Double(slow / fast), 1.4 / 0.032, accuracy: 0.5,
                       "the ratio in ink has to be the ratio in time")
    }

    /// A log of slow requests must not be blown up to the same width a log of fast ones needs.
    /// Deriving the scale from the durations present is what makes the page zoom rather than
    /// magnify.
    func testALogOfSlowRequestsDoesNotExplode() {
        let scale = WaterfallTimeScale.make(
            medianDuration: 5,
            tailDuration: 4,
            span: ownersSpan,
            visibleWidth: visibleWidth
        )
        XCTAssertLessThan(scale.contentWidth, 4_000,
                          "five second requests need no more room than five second requests")
        XCTAssertGreaterThanOrEqual(scale.width(ofSeconds: 5), WaterfallTimeScale.medianBarWidth)
    }

    /// A log of fast requests zooms in far enough to separate them.
    func testALogOfFastRequestsZoomsIn() {
        let fast = WaterfallTimeScale.make(medianDuration: 0.02, tailDuration: 0.005,
                                           span: 10, visibleWidth: visibleWidth)
        let slow = WaterfallTimeScale.make(medianDuration: 2, tailDuration: 0.5,
                                           span: 10, visibleWidth: visibleWidth)
        XCTAssertGreaterThan(fast.pointsPerSecond, slow.pointsPerSecond,
                             "the same span reads at a finer scale when its requests are finer")
    }

    /// The tail rule, which the median alone cannot provide: a log whose typical request is slow
    /// but which still contains fast ones has to keep the fast ones visible.
    func testAFastRequestStaysVisibleInALogOfSlowOnes() {
        let scale = WaterfallTimeScale.make(
            medianDuration: 1.4,
            tailDuration: 0.032,
            span: ownersSpan,
            visibleWidth: visibleWidth
        )
        XCTAssertEqual(scale.width(ofSeconds: 0.032), WaterfallTimeScale.tailBarWidth,
                       accuracy: 0.01,
                       "the tenth percentile is what stops the fast tail collapsing")
    }

    // MARK: - The clamps

    /// A pathological log — millisecond requests across an hour — must not ask for a scroll view
    /// kilometres wide.
    func testAPathologicalSpanCannotProduceAnUnboundedScrollView() {
        let scale = WaterfallTimeScale.make(medianDuration: 0.001, tailDuration: 0.0002,
                                            span: 3_600, visibleWidth: visibleWidth)
        XCTAssertLessThanOrEqual(scale.contentWidth, WaterfallTimeScale.maximumContentWidth)
    }

    /// The other end of the clamp: the chart never draws narrower than the room it has, or the
    /// page would show a chart floating in an empty plot.
    func testTheChartNeverDrawsNarrowerThanTheRoomItHas() {
        let scale = WaterfallTimeScale.make(medianDuration: 8, tailDuration: 8,
                                            span: 20, visibleWidth: visibleWidth)
        XCTAssertGreaterThanOrEqual(scale.contentWidth, visibleWidth)
    }

    /// A session with nothing measured still has somewhere to draw.
    func testASeriesWithNothingMeasuredStillHasAScale() {
        let scale = WaterfallTimeScale.make(medianDuration: nil, tailDuration: nil,
                                            span: 0, visibleWidth: visibleWidth)
        XCTAssertGreaterThan(scale.pointsPerSecond, 0)
        XCTAssertGreaterThanOrEqual(scale.contentWidth, visibleWidth)
    }

    // MARK: - Placing a bar

    /// A bar starts where it started. This is the claim the whole chart rests on, and it is now
    /// arithmetic the view no longer does for itself.
    func testABarIsPlacedAtItsStartTime() {
        XCTAssertEqual(Double(ownersScale.x(atSeconds: 12)),
                       12 * ownersScale.pointsPerSecond, accuracy: 0.0001)
    }

    /// The one point floor survives the change: a bar too short to draw is still findable, and
    /// still adds at most one point of ink.
    func testABarTooShortToDrawIsStillGivenOnePoint() {
        let scale = WaterfallTimeScale.make(medianDuration: 5, tailDuration: 5,
                                            span: 600, visibleWidth: visibleWidth)
        XCTAssertEqual(scale.width(of: entry(duration: 0.000_001)),
                       WaterfallChartStyle.minimumBarWidth, accuracy: 0.0001)
    }

    // MARK: - The sample the scale is derived from

    /// A pending bar is stretched to the end of the series, so its "duration" describes the
    /// session rather than a round trip. Letting it into the sample would drag the median toward
    /// the span and undo the zoom.
    func testPendingBarsAreLeftOutOfTheSample() {
        let series = WaterfallSeries(
            origin: Date(),
            span: 300,
            entries: [entry(duration: 0.1), entry(duration: 0.3), entry(duration: 299, pending: true)]
        )
        XCTAssertEqual(WaterfallTimeScale.measuredDurations(of: series), [0.1, 0.3])
    }

    /// A zero-length bar is not a measurement, and dividing by it would be an infinite scale.
    func testZeroLengthBarsAreLeftOutOfTheSample() {
        let series = WaterfallSeries(
            origin: Date(),
            span: 1,
            entries: [entry(duration: 0), entry(duration: 0.5)]
        )
        XCTAssertEqual(WaterfallTimeScale.measuredDurations(of: series), [0.5])
    }

    /// Building the scale straight from a series agrees with building it from the two figures,
    /// so the view model's cached percentiles and a test's literals describe the same chart.
    func testBuildingFromASeriesAgreesWithBuildingFromTheFigures() {
        let series = WaterfallSeries(
            origin: Date(),
            span: 4,
            entries: (1...10).map { entry(duration: Double($0) / 10) }
        )
        let fromSeries = WaterfallTimeScale.make(for: series, visibleWidth: visibleWidth)
        let durations = WaterfallTimeScale.measuredDurations(of: series)
        let fromFigures = WaterfallTimeScale.make(
            medianDuration: WaterfallTimeScale.percentile(0.5, of: durations),
            tailDuration: WaterfallTimeScale.percentile(WaterfallTimeScale.tailPercentile, of: durations),
            span: series.span,
            visibleWidth: visibleWidth
        )
        XCTAssertEqual(fromSeries, fromFigures)
    }

    // MARK: - The ruler

    /// Ticks that overlap are worse than fewer ticks, so the interval is the smallest round
    /// number of seconds that keeps its labels apart at the current scale.
    func testTicksAreFarEnoughApartToRead() {
        for scale in [ownersScale,
                      WaterfallTimeScale.make(medianDuration: 5, tailDuration: 4,
                                              span: 600, visibleWidth: visibleWidth),
                      WaterfallTimeScale.make(medianDuration: 0.004, tailDuration: 0.001,
                                              span: 2, visibleWidth: visibleWidth)] {
            XCTAssertGreaterThanOrEqual(
                CGFloat(scale.tickInterval * scale.pointsPerSecond),
                WaterfallTimeScale.minimumTickSpacing,
                "ticks \(scale.tickInterval)s apart collide at \(scale.pointsPerSecond) pt/s"
            )
        }
    }

    /// A round interval, so the ruler reads `10 s`, `20 s` rather than `13.7 s`, `27.4 s`.
    func testTicksLandOnRoundNumbers() {
        for span in [1.0, 5.0, 60.0, 300.0, 3_600.0] {
            let scale = WaterfallTimeScale.make(medianDuration: 0.25, tailDuration: 0.04,
                                                span: span, visibleWidth: visibleWidth)
            let mantissa = scale.tickInterval / pow(10, floor(log10(scale.tickInterval)))
            XCTAssertTrue([1.0, 2.0, 5.0].contains { abs($0 - mantissa) < 0.0001 },
                          "\(scale.tickInterval)s is not a round interval")
        }
    }

    /// The ruler covers the axis it sits above — the last tick is inside the content, and the
    /// content ends no more than one interval past it.
    func testTheRulerCoversTheWholeAxis() {
        let scale = ownersScale
        XCTAssertGreaterThan(scale.tickCount, 1)
        let last = scale.seconds(ofTick: scale.tickCount - 1)
        XCTAssertLessThanOrEqual(scale.x(atSeconds: last), scale.contentWidth)
        XCTAssertGreaterThan(last + scale.tickInterval, scale.upperBound)
    }
}
