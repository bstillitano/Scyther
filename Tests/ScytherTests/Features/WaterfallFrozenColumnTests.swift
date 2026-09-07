//
//  WaterfallFrozenColumnTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// Covers the arithmetic that keeps the request names in place while the bars scroll sideways.
///
/// Every waterfall a developer has used freezes its name column — Chrome's network panel and
/// Charles both do — because the one task the page exists for is reading a bar against the
/// request that produced it. Names that scroll out of view while the reader inspects a bar leave
/// the page showing coloured rectangles belonging to nothing.
///
/// The freeze is one subtraction, done inside the row's own layout pass rather than through a
/// published scroll offset, so the column moves in the same frame the bars do. These tests pin
/// the subtraction; a lagging column would show up on a device as names sliding and snapping
/// back, which no unit test can see.
@MainActor
final class WaterfallFrozenColumnTests: XCTestCase {

    // MARK: - Staying put

    /// The column holds the leading edge of the plot however far the bars have scrolled.
    ///
    /// `leadingEdge` is where the row's own start sits in the scroll view's visible coordinate
    /// space, so a row scrolled five hundred points to the left reports `-500` and the column has
    /// to travel five hundred points to the right to stay where it was.
    func testTheColumnHoldsTheLeadingEdgeAsTheBarsScroll() {
        for scrolled in [0.0, 1.0, 500.0, 38_000.0] as [CGFloat] {
            let offset = WaterfallChartStyle.frozenColumnOffset(leadingEdge: -scrolled)
            XCTAssertEqual(-scrolled + offset, 0, accuracy: 0.0001,
                           "the column has to land at the leading edge, not near it")
        }
    }

    /// A scroll view that is rubber-banding reports a *positive* leading edge, because the
    /// content has been dragged past its own start. Following it would push the column off the
    /// leading edge and into the plot, which reads as the names sliding away — the opposite of
    /// what the freeze is for. The column simply stops.
    func testTheColumnDoesNotDriftWhenTheScrollRubberBands() {
        XCTAssertEqual(WaterfallChartStyle.frozenColumnOffset(leadingEdge: 60), 0)
    }

    // MARK: - Room for the column

    /// The column is opaque and the bars pass underneath it, so it has to own the gap between
    /// itself and the plot as well. A column only as wide as its text would let a bar show
    /// through the gap and read as a bar starting at zero.
    func testTheColumnOwnsTheGapBetweenItselfAndThePlot() {
        XCTAssertEqual(
            WaterfallChartStyle.frozenColumnWidth,
            WaterfallChartStyle.labelColumnWidth + WaterfallChartStyle.labelColumnSpacing
        )
    }

    /// A row is the frozen column plus the whole scrollable timeline, which is what the scroll
    /// view sizes its content from. Sizing rows to the timeline alone would leave the last
    /// column-width of the log unreachable.
    func testARowIsTheColumnPlusTheWholeTimeline() {
        XCTAssertEqual(
            WaterfallChartStyle.rowWidth(timelineWidth: 38_880),
            WaterfallChartStyle.frozenColumnWidth + 38_880
        )
    }

    /// Everything on the timeline is placed past the column, by the one function the ruler and
    /// the bars both call. A tick that forgot the column would sit a column-width to the left of
    /// the bar it describes — the exact misalignment the shared call exists to make impossible.
    func testEverythingOnTheTimelineIsPlacedPastTheColumn() {
        let scale = WaterfallTimeScale.make(medianDuration: 0.25, tailDuration: 0.04,
                                            span: 300, visibleWidth: 190)
        XCTAssertEqual(WaterfallChartStyle.plotX(forSeconds: 0, on: scale),
                       WaterfallChartStyle.frozenColumnWidth,
                       "the axis starts where the frozen column ends")
        for seconds in [0.5, 12.0, 299.0] {
            XCTAssertEqual(WaterfallChartStyle.plotX(forSeconds: seconds, on: scale),
                           WaterfallChartStyle.frozenColumnWidth + scale.x(atSeconds: seconds),
                           accuracy: 0.0001)
        }
    }

    // MARK: - Colour

    /// The page draws its bars itself rather than through Charts, so the colour it fills them
    /// with has to be the colour the legend claims. The legend is still a `Chart`, seeded from
    /// ``WaterfallChartStyle/styleScale``, and nothing but this test would notice the two
    /// drifting apart.
    func testEveryBarIsFilledWithTheColourItsLegendEntryShows() {
        for (title, colour) in WaterfallChartStyle.styleScale {
            XCTAssertEqual(WaterfallChartStyle.colour(forOutcome: title), colour,
                           "\(title) is drawn in a colour its legend entry does not show")
        }
    }

    /// Every outcome a bar can have is one the legend lists, so no bar is drawn in a colour with
    /// nothing explaining it.
    func testEveryOutcomeAppearsInTheLegend() {
        let legend = WaterfallChartStyle.styleScale.map(\.key)
        for title in WaterfallChartStyle.outcomeTitles {
            XCTAssertTrue(legend.contains(title), "\(title) has no legend entry")
        }
    }
}
