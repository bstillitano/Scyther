//
//  WaterfallViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers the full-log waterfall page.
///
/// The point of the page is the two things the Traffic Stats section cannot do: show *every*
/// request rather than the most recent forty, and hand each bar back the request it was drawn
/// from so tapping it can open that request. Both are pinned here.
@MainActor
final class WaterfallViewModelTests: XCTestCase {

    /// Builds a captured request with the given shape.
    ///
    /// - Parameters:
    ///   - startedAt: When the request was sent.
    ///   - duration: The round trip in milliseconds, or `nil` for one still in flight.
    ///   - path: The request path, which becomes the bar's label.
    /// - Returns: The request.
    private func request(
        startedAt: Date,
        duration: Float? = 100,
        path: String = "/v1/users"
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com\(path)")!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = startedAt
        model.noResponse = false
        if let duration {
            model.requestDuration = duration
            model.responseCode = 200
            model.responseDate = startedAt.addingTimeInterval(TimeInterval(duration) / 1_000)
        }
        return model
    }

    /// A fixed origin, so every arithmetic assertion below is deterministic.
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Every request, not the most recent few

    /// The whole reason the page exists. The section on Traffic Stats stops at forty bars; a
    /// developer chasing a burst needs the other nine hundred and sixty.
    func testEveryRequestInTheLogGetsARow() async {
        let requests = (0..<50).map { request(startedAt: origin.addingTimeInterval(Double($0))) }
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.count, 50,
                       "the page is not subject to WaterfallSeries.defaultLimit")
        XCTAssertGreaterThan(50, WaterfallSeries.defaultLimit)
    }

    /// Time reads downward, so the oldest request is the first row.
    func testRowsRunOldestFirst() async {
        let old = request(startedAt: origin, path: "/old")
        let new = request(startedAt: origin.addingTimeInterval(5), path: "/new")
        let viewModel = WaterfallViewModel(requests: [new, old], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.map(\.entry.label), ["GET /old", "GET /new"])
    }

    /// The row labels match the Traffic Stats chart's axis labels exactly, because the owner's
    /// requirement is that the page looks like the section it was opened from.
    func testRowsAreNumberedTheWayTheStatsChartNumbersThem() async {
        let viewModel = WaterfallViewModel(requests: [
            request(startedAt: origin),
            request(startedAt: origin.addingTimeInterval(1)),
        ], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.map(\.label), ["1. GET /v1/users", "2. GET /v1/users"])
    }

    // MARK: - Tapping a bar

    /// A bar is only tappable because its row carries the request it was drawn from. Matching by
    /// label would land the reader on the wrong one of two calls to the same endpoint.
    func testEachRowCarriesTheExactRequestItWasDrawnFrom() async {
        let first = request(startedAt: origin, path: "/v1/users")
        let second = request(startedAt: origin.addingTimeInterval(1), path: "/v1/users")
        let viewModel = WaterfallViewModel(requests: [first, second], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertTrue(viewModel.rows.first?.request === first)
        XCTAssertTrue(viewModel.rows.last?.request === second)
    }

    /// The row's identity is the request's own hash, so a redraw after new traffic arrives does
    /// not reshuffle which row is which.
    func testARowIsIdentifiedByItsRequest() async {
        let only = request(startedAt: origin)
        let viewModel = WaterfallViewModel(requests: [only], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.first?.id, only.getRandomHash() as String)
    }

    // MARK: - The shared axis

    /// One axis across the whole log, so overlap still means "in flight together" on a page that
    /// may be scrolled far past the bars it is being compared with.
    func testOneAxisSpansTheWholeLog() async {
        let viewModel = WaterfallViewModel(requests: [
            request(startedAt: origin),
            request(startedAt: origin.addingTimeInterval(10)),
        ], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.first?.entry.start ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.rows.last?.entry.start ?? -1, 10, accuracy: 0.0001)
    }

    /// The page's axis is computed by the same rule as the section's, or the same request would
    /// be a different length on the two screens.
    func testTheAxisMatchesTheStatsChart() async {
        let requests = [request(startedAt: origin), request(startedAt: origin.addingTimeInterval(2))]
        let page = WaterfallViewModel(requests: requests, totalCount: requests.count)
        let stats = TrafficStatsViewModel(requests: requests, totalCount: requests.count)
        await page.recompute()
        await stats.recompute()
        XCTAssertEqual(page.upperBound, stats.chartUpperBound, accuracy: 0.0001)
    }

    // MARK: - Following the log

    /// A request with no start date has nowhere to go on the axis, so it is dropped rather than
    /// stacked at the origin.
    func testARequestWithNoStartDateIsLeftOut() async {
        let undated = HTTPRequest()
        undated.saveRequest(URLRequest(url: URL(string: "https://api.example.com/v1/x")!))
        undated.requestDate = nil
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin), undated], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.count, 1)
    }

    /// A cleared log empties the page, which is what its empty state is for.
    func testAClearedLogLeavesNothingToDraw() async {
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.isEmpty)
        viewModel.update(requests: [], totalCount: 0)
        await viewModel.recompute()
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    /// The page follows the log the way the rest of the stats screen does.
    func testNewTrafficAppearsOnTheNextRecomputation() async {
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin)], totalCount: 1)
        await viewModel.recompute()
        viewModel.update(
            requests: [request(startedAt: origin), request(startedAt: origin.addingTimeInterval(1))],
            totalCount: 2
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.count, 2)
    }

    // MARK: - Saying what it is showing

    /// The defect: the page is handed the log's *filtered* array, and said "Every request in the
    /// log" over one host's slice of it. Text that claims more than the code did.
    func testTheCaptionNamesBothCountsWhenTheLogIsFiltered() async {
        let viewModel = WaterfallViewModel(
            requests: [request(startedAt: origin), request(startedAt: origin.addingTimeInterval(1))],
            totalCount: 10
        )
        await viewModel.recompute()
        XCTAssertTrue(viewModel.isFiltered)
        XCTAssertTrue(viewModel.caption.contains("2"))
        XCTAssertTrue(viewModel.caption.contains("10"))
        XCTAssertFalse(viewModel.caption.contains("Every request"),
                       "it is not every request when a filter is on")
    }

    /// And says the unqualified thing only when it is true.
    func testTheCaptionSaysEveryRequestOnlyWhenItIsEveryRequest() async {
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.isFiltered)
        XCTAssertTrue(viewModel.caption.contains("Every request"))
    }

    // MARK: - The card

    /// Exactly one row closes the card, and it is the last one.
    func testOnlyTheLastRowClosesTheCard() async {
        let viewModel = WaterfallViewModel(
            requests: (0..<4).map { request(startedAt: origin.addingTimeInterval(Double($0))) },
            totalCount: 4
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.filter(\.isLast).count, 1)
        XCTAssertTrue(viewModel.rows.last?.isLast == true)
    }

    /// The card's bottom edge is decided by position, not by identity. Comparing against the last
    /// row's id rounded a row in the middle of the card whenever one capture was in the log twice.
    func testTheCardsBottomEdgeSurvivesOneCaptureAppearingTwice() async {
        // The duplicate has to be the newest capture, which is where the id comparison broke:
        // the second-to-last row then shares the last row's id and rounds its corners too.
        let twice = request(startedAt: origin.addingTimeInterval(1))
        let viewModel = WaterfallViewModel(
            requests: [request(startedAt: origin), twice, twice],
            totalCount: 3
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.rows.filter(\.isLast).count, 1,
                       "a duplicated capture must not round a row in the middle of the card")
    }

    // MARK: - Snapshots

    /// The axis, the bars and the caption's counts are one snapshot of one moment. Published
    /// separately, the page is one change away from drawing new bars against an old axis.
    func testTheAxisTheRowsAndTheCountsArePublishedTogether() async {
        let viewModel = WaterfallViewModel(
            requests: (0..<3).map { request(startedAt: origin.addingTimeInterval(Double($0))) },
            totalCount: 9
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.count, viewModel.layout.series.entries.count)
        XCTAssertEqual(viewModel.layout.count, 3)
        XCTAssertEqual(viewModel.layout.total, 9)
    }

    /// A page pushed over a full log must not flash "No Traffic Captured" while its first pass
    /// runs. The first layout happens in `init`, before anything is drawn.
    func testAPageOpenedOverAFullLogIsNeverEmptyToBeginWith() {
        let viewModel = WaterfallViewModel(
            requests: (0..<3).map { request(startedAt: origin.addingTimeInterval(Double($0))) },
            totalCount: 3
        )
        XCTAssertFalse(viewModel.isEmpty, "no placeholder over a log that is full")
        XCTAssertEqual(viewModel.rows.count, 3)
    }
}
