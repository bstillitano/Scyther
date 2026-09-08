//
//  WaterfallChartStyleTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers the rules ``WaterfallChartStyle`` still owns.
///
/// These used to live inside ``TrafficStatsViewModel``, where only the Traffic Stats section
/// could reach them, and for a while afterward they really were shared between both waterfall
/// surfaces. That is no longer the shape: the overview strip — the one view both
/// ``TrafficStatsView`` and the full-log page draw — gets its geometry from
/// ``WaterfallStripGeometry`` instead, covered by its own `WaterfallOverviewStripTests`. What
/// stays here is what genuinely is still shared, or belongs to the full-log page's detail list
/// and legend alone — see ``WaterfallChartStyle``'s own type documentation for exactly which is
/// which.
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

    // MARK: - Page geometry

    /// The defect the owner found: rows that shrank to share the screen turned a scrollable
    /// waterfall into a static one — twenty-two requests on a single screen, and the full-log page
    /// showing the same picture as the preview it was opened from. A row has to be tall enough to
    /// read and to tap, whatever the log holds.
    func testARowIsTallEnoughToReadAndToTap() {
        XCTAssertGreaterThanOrEqual(WaterfallChartStyle.rowHeight, 44,
                                    "the page's rows are tappable, so 44pt is the floor")
        XCTAssertGreaterThan(WaterfallChartStyle.rowHeight, WaterfallChartStyle.barThickness * 2)
    }

    /// Twenty-two requests must not fit on one screen, or the page is the cramped,
    /// everything-squeezed-in picture the owner's defect report was written from again — see
    /// ``testARowIsTallEnoughToReadAndToTap`` above. The section it was once compared against, a
    /// `Chart` of its own most recent seven bars, is gone; the comparison that survives is against
    /// this row height, not against that section any more.
    func testATypicalLogIsTallerThanAScreen() {
        let screenHeight: CGFloat = 852
        XCTAssertGreaterThan(22 * WaterfallChartStyle.rowHeight, screenHeight,
                             "twenty-two rows have to scroll, which is what the page is for")
    }

    // MARK: - Colour

    /// The full-log page's detail row fills its bars from ``WaterfallChartStyle/colour(forOutcome:)``
    /// while the legend above it is still drawn by Charts from ``WaterfallChartStyle/styleScale``.
    /// Nothing else keeps those two in step, so a test that walks the scale and asks this for
    /// every entry is what keeps a drifted colour from shipping silently.
    func testEveryBarIsFilledWithTheColourItsLegendEntryShows() {
        for (title, colour) in WaterfallChartStyle.styleScale {
            XCTAssertEqual(WaterfallChartStyle.colour(forOutcome: title), colour,
                           "\(title) is drawn in a colour its legend entry does not show")
        }
    }

    /// `colour(for:)` is a thin wrapper over `colour(forOutcome:)`, but the wrapping — going
    /// through `outcomeTitle(for:)` — is exactly the part a typo in either function's `switch`
    /// would not be caught by testing `colour(forOutcome:)` alone. One entry per outcome, so
    /// every case of `outcomeTitle(for:)` is exercised on the way through.
    func testColourForAnEntryMatchesColourForItsOutcome() {
        let entries: [WaterfallEntry] = [
            entry(),
            entry(failure: true),
            entry(pending: true),
            entry(stubbed: true),
        ]
        for candidate in entries {
            XCTAssertEqual(WaterfallChartStyle.colour(for: candidate),
                           WaterfallChartStyle.colour(forOutcome: WaterfallChartStyle.outcomeTitle(for: candidate)),
                           "colour(for:) drifted from colour(forOutcome:) for \(WaterfallChartStyle.outcomeTitle(for: candidate))")
        }
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
