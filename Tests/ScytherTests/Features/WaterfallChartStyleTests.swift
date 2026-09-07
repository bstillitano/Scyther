//
//  WaterfallChartStyleTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers the rules both waterfall surfaces draw by.
///
/// These used to live inside ``TrafficStatsViewModel``, where only the Traffic Stats section
/// could reach them. The full-log page draws the same chart, so the moment the rules were shared
/// they became worth pinning on their own: a change here changes both surfaces at once, and the
/// owner's requirement is that the two never diverge.
@MainActor
final class WaterfallChartStyleTests: XCTestCase {

    /// Builds a bar with the given shape.
    ///
    /// - Parameters:
    ///   - start: Seconds from the series origin to the bar starting.
    ///   - duration: How long the bar runs, in seconds.
    ///   - failure: Whether the request finished badly.
    ///   - pending: Whether the request is still in flight.
    ///   - stubbed: Whether a rule synthesised the response.
    /// - Returns: The bar.
    private func entry(
        start: TimeInterval = 0,
        duration: TimeInterval = 1,
        failure: Bool = false,
        pending: Bool = false,
        stubbed: Bool = false
    ) -> WaterfallEntry {
        WaterfallEntry(
            id: UUID().uuidString,
            label: "GET /v1/users",
            start: start,
            duration: duration,
            isFailure: failure,
            isPending: pending,
            isStubbed: stubbed
        )
    }

    // MARK: - The axis

    /// The value label sits past the end of its bar, so the axis needs headroom or the longest
    /// bar's label falls outside the plot.
    func testTheAxisLeavesRoomForTheLongestBarsLabel() {
        XCTAssertEqual(WaterfallChartStyle.upperBound(forSpan: 2), 2.7, accuracy: 0.0001)
    }

    /// A session where nothing has been measured yet still has to have somewhere to draw.
    func testTheAxisIsNeverZeroWide() {
        XCTAssertGreaterThan(WaterfallChartStyle.upperBound(forSpan: 0), 0,
                             "a zero-wide axis has nothing to draw on")
    }

    // MARK: - Minimum bar width

    /// The full-log page can run its axis over minutes, where a sub-millisecond request is a bar
    /// a fraction of a point wide: present in the data and invisible on screen. The floor is the
    /// only reason such a request can be seen, and therefore tapped.
    func testASubMillisecondBarIsWidenedEnoughToStaySeen() {
        let bar = entry(start: 4, duration: 0.0002)
        let width = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 60) - bar.start
        XCTAssertGreaterThan(width, 0.0002, "a bar this short is invisible at its true length")
        XCTAssertGreaterThanOrEqual(width / 60, WaterfallChartStyle.minimumBarFraction)
    }

    /// The floor only ever grows a bar that could not be seen. A bar with real length is drawn at
    /// exactly the length it ran, or the chart stops being a measurement.
    func testABarWithRealLengthIsDrawnAtItsTrueLength() {
        let bar = entry(start: 1, duration: 5)
        XCTAssertEqual(WaterfallChartStyle.drawnEnd(of: bar, upperBound: 10), 6, accuracy: 0.0001)
    }

    /// Widening the bar must not touch what it says. The label is the honest figure; the width is
    /// the legible one.
    func testAWidenedBarStillReportsItsRealDuration() {
        let bar = entry(start: 0, duration: 0.0002)
        XCTAssertTrue(WaterfallChartStyle.valueLabel(for: bar).contains("0"),
                      "the label reports the measurement, not the drawn width")
        XCTAssertFalse(WaterfallChartStyle.valueLabel(for: bar).contains("480"))
    }

    // MARK: - Outcome

    /// A stub's status code was authored rather than returned, so it is named as a stub whatever
    /// that code says.
    func testAStubIsNamedAStubEvenWhenItsAuthoredCodeFailed() {
        XCTAssertEqual(WaterfallChartStyle.outcomeTitle(for: entry(failure: true, stubbed: true)),
                       "Stubbed")
    }

    /// Failure is tested before pending. When this ran the other way round every failure in the
    /// log was drawn as still in flight.
    func testAFailureIsNamedAFailureRatherThanPending() {
        XCTAssertEqual(WaterfallChartStyle.outcomeTitle(for: entry(failure: true)), "Failed")
    }

    /// A request that has not come back is in flight, not a success.
    func testARequestStillInFlightIsNamedPending() {
        XCTAssertEqual(WaterfallChartStyle.outcomeTitle(for: entry(pending: true)), "Pending")
    }

    /// Every name the chart can produce needs a colour, or Charts drops the bar's fill and the
    /// legend loses an entry.
    func testEveryOutcomeTheChartCanProduceHasAColour() {
        let scaled = WaterfallChartStyle.styleScale.map(\.key)
        XCTAssertEqual(scaled, WaterfallChartStyle.outcomeTitles)
    }
}
