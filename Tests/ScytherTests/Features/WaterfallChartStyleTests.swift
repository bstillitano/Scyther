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

    // MARK: - Minimum rendered width

    /// A request too short to draw is given exactly one point of ink — not a fraction of the
    /// axis, which is what it was. That version's floor grew with the session: over five minutes
    /// it inflated every bar to more than three seconds, so a 5 ms request and a 3 s request drew
    /// identically and a floored bar could reach across a request it never ran alongside.
    func testABarTooNarrowToSeeIsDrawnExactlyOnePointWide() {
        let bar = entry(start: 4, duration: 0.0002)
        let secondsPerPoint = 60.0 / 180.0
        let width = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 60, plotWidth: 180) - bar.start
        XCTAssertEqual(width / secondsPerPoint, Double(WaterfallChartStyle.minimumBarWidth),
                       accuracy: 0.0001)
    }

    /// The guard the axis-fraction version could not offer: however long the session runs, the
    /// floor adds at most one point of ink, so it cannot invent an overlap a reader could
    /// otherwise have ruled out.
    func testTheFloorNeverAddsMoreThanOnePointOfInk() {
        let secondsPerPoint = 405.0 / 178.0
        for duration in [0.0, 0.0005, 0.005, 0.5, 5.0, 50.0] {
            let bar = entry(start: 10, duration: duration)
            let drawn = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 405, plotWidth: 178)
            let addedPoints = (drawn - (bar.start + duration)) / secondsPerPoint
            XCTAssertLessThanOrEqual(addedPoints, Double(WaterfallChartStyle.minimumBarWidth) + 0.0001,
                                     "a \(duration)s bar was inflated by \(addedPoints) points")
        }
    }

    /// The teeth against sliding back to a fraction of the axis: a floor expressed in points
    /// shrinks in seconds as the plot gets wider, and a floor expressed as a fraction does not.
    func testAWiderPlotMakesTheFloorWorthLessTime() {
        let bar = entry(start: 0, duration: 0)
        let narrow = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 100, plotWidth: 100)
        let wide = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 100, plotWidth: 400)
        XCTAssertEqual(narrow / wide, 4, accuracy: 0.0001,
                       "four times the plot, a quarter of the seconds")
    }

    /// The floor only ever grows a bar that could not be seen. A bar with real length is drawn at
    /// exactly the length it ran, or the chart stops being a measurement.
    func testABarWithRealLengthIsDrawnAtItsTrueLength() {
        let bar = entry(start: 1, duration: 5)
        XCTAssertEqual(WaterfallChartStyle.drawnEnd(of: bar, upperBound: 10, plotWidth: 200), 6,
                       accuracy: 0.0001)
    }

    /// The preview's contract. Charts sizes its leading axis to its own labels, so that surface
    /// cannot state a plot width; it passes zero and gets the true lengths it shipped with.
    func testASurfaceThatDoesNotKnowItsPlotWidthDrawsTrueLengths() {
        let bar = entry(start: 2, duration: 0.0001)
        XCTAssertEqual(WaterfallChartStyle.drawnEnd(of: bar, upperBound: 405, plotWidth: 0),
                       2.0001, accuracy: 0.000001)
    }

    /// Widening the bar must not touch what it says. Under a floor worth three seconds, a two
    /// millisecond request still reports two milliseconds.
    func testAFlooredBarStillReportsItsRealDuration() {
        let bar = entry(start: 0, duration: 0.002)
        let drawn = WaterfallChartStyle.drawnEnd(of: bar, upperBound: 300, plotWidth: 100)
        XCTAssertEqual(drawn, 3, accuracy: 0.0001, "the floor here is worth three seconds")
        XCTAssertEqual(WaterfallChartStyle.valueLabel(for: bar), DurationText.milliseconds(2))
        XCTAssertFalse(WaterfallChartStyle.valueLabel(for: bar).contains("3"),
                       "the label reports the measurement, never the drawn width")
    }

    // MARK: - Page geometry

    /// The ruler and every row are framed to this one figure, which is what makes a tick and the
    /// bar beneath it line up by construction rather than by two hand-matched stacks of insets.
    func testThePlotIsWhatIsLeftOfThePageAfterTheCardAndTheLabelColumn() {
        let chrome = 2 * WaterfallChartStyle.cardInset
            + 2 * WaterfallChartStyle.cardContentPadding
            + WaterfallChartStyle.labelColumnWidth
            + WaterfallChartStyle.labelColumnSpacing
        XCTAssertEqual(WaterfallChartStyle.plotWidth(inPageWidth: 390), 390 - chrome)
    }

    /// A split view or a very small window must not produce a negative plot.
    func testAVeryNarrowPageStillLeavesAPlotToDrawIn() {
        XCTAssertEqual(WaterfallChartStyle.plotWidth(inPageWidth: 100),
                       WaterfallChartStyle.minimumPlotWidth)
    }

    /// The defect the owner found: rows that shrank to share the screen turned a scrollable
    /// waterfall into a static one — twenty-two requests on a single screen, and the full-log page
    /// showing the same picture as the preview it was opened from. A row has to be tall enough to
    /// read and to tap, whatever the log holds.
    func testARowIsTallEnoughToReadAndToTap() {
        XCTAssertGreaterThanOrEqual(WaterfallChartStyle.rowHeight, 44,
                                    "the page's rows are tappable, so 44pt is the floor")
        XCTAssertGreaterThan(WaterfallChartStyle.rowHeight, WaterfallChartStyle.barThickness * 2)
    }

    /// Twenty-two requests must not fit on one screen, or the page is the preview again.
    func testATypicalLogIsTallerThanAScreen() {
        let screenHeight: CGFloat = 852
        XCTAssertGreaterThan(22 * WaterfallChartStyle.rowHeight, screenHeight,
                             "twenty-two rows have to scroll, which is what the page is for")
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
