//
//  TrafficStatsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers the recomputation, the caption, and every number the screen turns into text.
@MainActor
final class TrafficStatsViewModelTests: XCTestCase {

    /// Builds a captured request with the given shape.
    ///
    /// - Parameters:
    ///   - duration: The round trip in milliseconds.
    ///   - status: The response status code.
    ///   - url: The request URL.
    ///   - stubbed: Whether a rule synthesised the response.
    /// - Returns: The request.
    private func request(
        duration: Float,
        status: Int = 200,
        url: String = "https://api.example.com/v1/users",
        stubbed: Bool = false
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = Date()
        model.requestDuration = duration
        model.responseCode = status
        model.responseBodyLength = 10
        model.noResponse = false
        // A finished load carries a response date; without one the statistics correctly read the
        // request as still in flight rather than as a result.
        model.responseDate = Date()
        model.wasStubbed = stubbed
        return model
    }

    // MARK: Recomputation

    func testStatisticsAreComputedOnInit() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 1)
        XCTAssertEqual(viewModel.waterfall.entries.count, 1)
    }

    func testUpdatingTheRequestsRecomputes() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()
        viewModel.update(requests: [request(duration: 100), request(duration: 200)], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 2)
        XCTAssertEqual(viewModel.captionCount, 2)
    }

    func testBeforeTheFirstComputationEverythingIsEmpty() {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        XCTAssertEqual(viewModel.statistics, .empty)
        XCTAssertTrue(viewModel.waterfall.entries.isEmpty)
    }

    func testNoRequestsIsReportedAsEmpty() async {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        await viewModel.recompute()
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertFalse(viewModel.isFiltered)
    }

    // MARK: Caption

    func testTheCaptionReportsFilteredAndTotalCounts() {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 340)
        XCTAssertTrue(viewModel.isFiltered)
        XCTAssertEqual(viewModel.captionCount, 1)
        XCTAssertEqual(viewModel.totalCount, 340)
        XCTAssertTrue(viewModel.caption.contains("340"), "the caption names the unfiltered total")
    }

    func testAnUnfilteredListIsNotReportedAsFiltered() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<3).map { _ in request(duration: 100) },
            totalCount: 3
        )
        await viewModel.recompute()
        XCTAssertFalse(viewModel.isFiltered)
        XCTAssertEqual(viewModel.caption, "3 requests",
                       "with nothing filtered out the caption names one number, not two")
    }

    /// The defect W27 named: the caption read the live array while the figures beneath it lagged
    /// by the debounce, so the header said "41 requests" over a table describing forty.
    func testTheCaptionDescribesTheSnapshotTheFiguresWereComputedFrom() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()

        viewModel.update(requests: (0..<5).map { _ in request(duration: 100) }, totalCount: 5)

        XCTAssertEqual(viewModel.captionCount, 1, "the caption still describes the published figures")
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 1)

        await viewModel.recompute()

        XCTAssertEqual(viewModel.captionCount, 5, "and moves with them when they are recomputed")
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 5)
    }

    func testTheUnfilteredTotalIsSnapshottedWithTheFiguresToo() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()

        viewModel.update(requests: [request(duration: 100)], totalCount: 400)
        XCTAssertFalse(viewModel.isFiltered, "the published figures still cover the whole log")

        await viewModel.recompute()
        XCTAssertTrue(viewModel.isFiltered)
        XCTAssertTrue(viewModel.caption.contains("400"))
    }

    // MARK: Percentile threshold

    func testFewCompletedRequestsSuppressesPercentiles() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<4).map { request(duration: Float(($0 + 1) * 10)) },
            totalCount: 4
        )
        await viewModel.recompute()
        XCTAssertFalse(
            viewModel.showsPercentiles,
            "a median of four samples is noise; the summary shows raw durations instead"
        )
    }

    func testFiveOrMoreCompletedRequestsShowsPercentiles() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<5).map { request(duration: Float(($0 + 1) * 10)) },
            totalCount: 5
        )
        await viewModel.recompute()
        XCTAssertTrue(viewModel.showsPercentiles)
    }

    func testStubbedRequestsDoNotCountTowardsThePercentileThreshold() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<3).map { request(duration: Float(($0 + 1) * 10)) }
                + (0..<4).map { _ in request(duration: 1, stubbed: true) },
            totalCount: 7
        )
        await viewModel.recompute()
        XCTAssertFalse(viewModel.showsPercentiles, "seven requests, but only three were measured")
    }

    // MARK: Formatting

    func testADurationUnderASecondIsShownInMilliseconds() {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        XCTAssertTrue(viewModel.durationText(250).contains("250"))
        XCTAssertFalse(viewModel.durationText(250).contains("0.25"))
    }

    func testADurationOfASecondOrMoreIsShownInSeconds() {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        XCTAssertTrue(viewModel.durationText(1_500).contains("1.5"))
    }

    func testAMissingDurationIsShownAsADash() {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        XCTAssertEqual(viewModel.durationText(nil), "—")
    }

    func testTheFailureRateIsHiddenWhenNothingWasMeasured() async {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 5, stubbed: true)],
            totalCount: 1
        )
        await viewModel.recompute()
        XCTAssertNil(viewModel.failureRateText, "one over zero is not a rate")
    }

    func testTheFailureRateIsAPercentageOfTheMeasuredRequests() async {
        let viewModel = TrafficStatsViewModel(
            requests: [
                request(duration: 5, status: 500), request(duration: 5),
                request(duration: 5), request(duration: 5),
            ],
            totalCount: 4
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.failureRate ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertTrue(viewModel.failureRateText?.contains("25") ?? false)
    }

    func testTheElapsedTextIsHiddenWithoutASpan() async {
        let undated = request(duration: 100)
        undated.requestDate = nil
        undated.responseDate = nil
        let viewModel = TrafficStatsViewModel(requests: [undated], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 1, "there is traffic here")
        XCTAssertNil(viewModel.elapsedText, "but nothing to measure an elapsed time between")
    }

    func testTheElapsedTextIsShownForDatedTraffic() async throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let first = request(duration: 100)
        first.requestDate = base
        first.responseDate = base.addingTimeInterval(0.1)
        let second = request(duration: 100)
        second.requestDate = base.addingTimeInterval(2)
        second.responseDate = base.addingTimeInterval(2.1)
        let viewModel = TrafficStatsViewModel(requests: [first, second], totalCount: 2)
        await viewModel.recompute()
        XCTAssertTrue(try XCTUnwrap(viewModel.elapsedText).contains("2.1"))
    }

    // MARK: Chart geometry

    func testTheChartUpperBoundLeavesRoomForTheValueLabels() async {
        let first = request(duration: 2_000)
        first.requestDate = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = TrafficStatsViewModel(requests: [first], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.chartUpperBound, 2.7, accuracy: 0.0001)
    }

    func testTheChartUpperBoundIsNeverZero() async {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        await viewModel.recompute()
        XCTAssertGreaterThan(viewModel.chartUpperBound, 0, "a zero-wide axis has nothing to draw on")
    }

    func testTheChartGrowsWithTheNumberOfBars() async {
        let requests = (0..<20).map { index -> HTTPRequest in
            let model = request(duration: 100)
            model.requestDate = Date(timeIntervalSince1970: 1_000_000 + Double(index))
            return model
        }
        let viewModel = TrafficStatsViewModel(requests: requests, totalCount: 20)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.chartHeight, 500)
    }

    func testTheChartHasAFloorHeight() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.chartHeight, 140)
    }

    // MARK: Row text

    func testAChartRowIsNumberedSoTwoCallsToOneEndpointKeepTheirOwnBars() async {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 100), request(duration: 200)],
            totalCount: 2
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.chartRows.map(\.id), ["1. GET /v1/users", "2. GET /v1/users"])
        XCTAssertEqual(viewModel.chartDomain.count, 2, "a shared axis value would collapse the two bars into one")
    }

    func testTheChartRowsAreEmptyWithoutTraffic() async {
        let viewModel = TrafficStatsViewModel(requests: [], totalCount: 0)
        await viewModel.recompute()
        XCTAssertTrue(viewModel.chartRows.isEmpty)
        XCTAssertTrue(viewModel.chartDomain.isEmpty)
    }

    func testABarValueLabelUsesMillisecondsUnderASecond() async throws {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 2)], totalCount: 1)
        await viewModel.recompute()
        let row = try XCTUnwrap(viewModel.chartRows.first)
        let label = viewModel.valueLabel(for: row.entry)
        XCTAssertTrue(label.contains("2"), "a two millisecond bar reads as two milliseconds")
        XCTAssertFalse(label.contains("0.002"), "and must not round away to zero seconds")
    }

    func testABarValueLabelUsesSecondsBeyondOne() async throws {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 2_500)], totalCount: 1)
        await viewModel.recompute()
        let row = try XCTUnwrap(viewModel.chartRows.first)
        XCTAssertTrue(viewModel.valueLabel(for: row.entry).contains("2.5"))
    }

    /// The defect W19 named, at the surface it reaches the developer through: a failed request
    /// was coloured, named and measured as though it were still running.
    func testAFailedBarIsNamedFailedAndNotPending() async throws {
        let failed = request(duration: 20, status: 0)
        failed.noResponse = true
        failed.responseCode = nil
        let viewModel = TrafficStatsViewModel(requests: [failed], totalCount: 1)
        await viewModel.recompute()
        let row = try XCTUnwrap(viewModel.chartRows.first)
        XCTAssertEqual(viewModel.outcomeTitle(for: row.entry), "Failed")
        XCTAssertFalse(row.entry.isPending)
    }

    func testAStubbedBarIsNamedStubbedWhateverItsStatusSays() async throws {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 2, status: 500, stubbed: true)],
            totalCount: 1
        )
        await viewModel.recompute()
        let row = try XCTUnwrap(viewModel.chartRows.first)
        XCTAssertEqual(viewModel.outcomeTitle(for: row.entry), "Stubbed",
                       "an authored 500 says nothing about the server")
    }

    func testAnEndpointSubtitleNamesTheCountAndMedian() async {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 100), request(duration: 300)],
            totalCount: 2
        )
        await viewModel.recompute()
        let endpoint = try? XCTUnwrap(viewModel.statistics.endpoints.first)
        let subtitle = viewModel.endpointSubtitle(for: endpoint!)
        XCTAssertTrue(subtitle.contains("2"))
        XCTAssertTrue(subtitle.contains("100"))
    }

    func testAHostSubtitleOnlyMentionsFailuresWhenThereAreSome() async {
        let clean = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await clean.recompute()
        XCTAssertFalse(clean.hostSubtitle(for: clean.statistics.hosts[0]).contains("1 failed"))

        let broken = TrafficStatsViewModel(requests: [request(duration: 100, status: 503)], totalCount: 1)
        await broken.recompute()
        XCTAssertTrue(broken.hostSubtitle(for: broken.statistics.hosts[0]).contains("1 failed"))
    }
}
