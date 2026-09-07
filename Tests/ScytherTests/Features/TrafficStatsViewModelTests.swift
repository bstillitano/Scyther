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

    /// Used to also assert `viewModel.caption == "3 requests"` here — `caption` had a distinct
    /// unfiltered form until `TrafficStatsView.summarySection` stopped showing the header at all
    /// when nothing is filtered (it would otherwise restate the section's own first row). That
    /// branch of `caption` is gone; the property now always produces the "N of M requests" form,
    /// even when, as here, `N == M`, because ``TrafficStatsView`` never calls it in that case any
    /// more. The rewritten assertion below pins that: `caption` no longer special-cases this
    /// scenario, it is simply never read for it in production.
    func testAnUnfilteredListIsNotReportedAsFiltered() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<3).map { _ in request(duration: 100) },
            totalCount: 3
        )
        await viewModel.recompute()
        XCTAssertFalse(viewModel.isFiltered)
        XCTAssertEqual(viewModel.caption, "3 of 3 requests",
                       "caption's only remaining form is 'N of M requests' - the view is what decides "
                       + "whether to show it at all, not this property")
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

    // MARK: Waterfall overview

    /// The section is a minimap now, so it draws everything rather than the most recent handful.
    func testTheWaterfallSectionDrawsTheWholeLogRatherThanAPreviewsWorth() async {
        let origin = Date(timeIntervalSince1970: 1_000)
        let requests: [HTTPRequest] = (0..<40).map { index in
            let request = HTTPRequest()
            request.requestURL = "https://httpbin.org/json"
            request.requestMethod = "GET"
            request.requestDate = origin.addingTimeInterval(Double(index))
            request.responseDate = origin.addingTimeInterval(Double(index) + 0.1)
            return request
        }

        let model = TrafficStatsViewModel(requests: [], totalCount: 0)
        model.update(requests: requests, totalCount: requests.count)
        await model.recompute()

        XCTAssertEqual(model.waterfall.entries.count, 40,
                       "the strip is an overview of everything, not a sample of it")
    }

    /// The count behind the footer's "N hosts": distinct, non-empty hosts only.
    func testHostCountCountsDistinctNonEmptyHosts() async {
        let base = Date(timeIntervalSince1970: 2_000)
        let requests = [
            request(duration: 100, url: "https://api.example.com/v1/users"),
            request(duration: 100, url: "https://api.example.com/v1/orders"),
            request(duration: 100, url: "https://api.example.org/v1/users"),
        ].enumerated().map { index, model -> HTTPRequest in
            model.requestDate = base.addingTimeInterval(Double(index))
            model.responseDate = base.addingTimeInterval(Double(index) + 0.1)
            return model
        }
        let viewModel = TrafficStatsViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.hostCount, 2, "two of the three requests share a host")
    }

    /// Case must not multiply hosts: ``WaterfallSeries/shortHost(for:)`` already lowercases
    /// before picking a label, and ``TrafficStatistics`` lowercases when it buckets hosts for
    /// *By Host* — this count has to agree with both, or the footer would name a different
    /// number of hosts than the section sitting right beneath it, for the very same log.
    func testHostCountIsCaseInsensitive() async {
        let base = Date(timeIntervalSince1970: 2_500)
        let requests = [
            request(duration: 100, url: "https://api.example.com/v1/users"),
            request(duration: 100, url: "https://API.EXAMPLE.COM/v1/orders"),
        ].enumerated().map { index, model -> HTTPRequest in
            model.requestDate = base.addingTimeInterval(Double(index))
            model.responseDate = base.addingTimeInterval(Double(index) + 0.1)
            return model
        }
        let viewModel = TrafficStatsViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.hostCount, 1, "the same host spelled two ways is still one host")
    }

    /// The footer names the count, the span and the host count — not, any more, where the rest of
    /// the log went, because none of it is hidden. The fixture is sized so the three figures never
    /// share a digit: five requests, spanning 500 ms, across three hosts — a caption built from
    /// the wrong number of hosts (say, two, from a `hostCount` that failed to lowercase and split
    /// a shared host into two) could not coincidentally still contain "3", the way it could have
    /// against a fixture where the request count, the span and the host count overlapped.
    func testTheWaterfallCaptionNamesTheRequestCountAndHostCount() async {
        let base = Date(timeIntervalSince1970: 3_000)
        let hosts = ["a.example.com", "a.example.com", "b.example.com", "b.example.com", "c.example.com"]
        let requests = hosts.enumerated().map { index, host -> HTTPRequest in
            let model = request(duration: 100, url: "https://\(host)/v1/users")
            model.requestDate = base.addingTimeInterval(Double(index) * 0.1)
            model.responseDate = base.addingTimeInterval(Double(index) * 0.1 + 0.1)
            return model
        }
        let viewModel = TrafficStatsViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.hostCount, 3, "three distinct hosts, precondition for the assertion below")
        XCTAssertTrue(viewModel.waterfallCaption.contains("5"), "names how many requests it covers")
        XCTAssertTrue(
            viewModel.waterfallCaption.contains("3"),
            "and how many distinct hosts they touched — the request count (5) and the ~500 ms span share no digit with 3, so only the host count can put it in the caption"
        )
    }

    /// The defect: the single flat sentence this caption used to be could only pluralise on one
    /// of its two numbers, and the request count always won — so the common case, a log that has
    /// touched exactly one host, read "across 1 hosts" on the feature's own first screen. Splitting
    /// the host count into its own pluralised key, joined after the request-count half, fixes
    /// precisely this case rather than only the rarer ones a "contains a digit" assertion would
    /// have missed.
    func testTheWaterfallCaptionPluralisesASingleHostCorrectly() async {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 100, url: "https://a.example.com/v1/users")],
            totalCount: 1
        )
        await viewModel.recompute()
        XCTAssertEqual(viewModel.hostCount, 1, "precondition for the assertion below")
        XCTAssertFalse(viewModel.waterfallCaption.contains("1 hosts"),
                       "a single host must not read as plural: \(viewModel.waterfallCaption)")
        XCTAssertTrue(viewModel.waterfallCaption.contains("1 host"))
    }

    // MARK: Bar semantics

    func testABarValueLabelUsesMillisecondsUnderASecond() async throws {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 2)], totalCount: 1)
        await viewModel.recompute()
        let entry = try XCTUnwrap(viewModel.waterfall.entries.first)
        let label = WaterfallChartStyle.valueLabel(for: entry)
        XCTAssertTrue(label.contains("2"), "a two millisecond bar reads as two milliseconds")
        XCTAssertFalse(label.contains("0.002"), "and must not round away to zero seconds")
    }

    func testABarValueLabelUsesSecondsBeyondOne() async throws {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 2_500)], totalCount: 1)
        await viewModel.recompute()
        let entry = try XCTUnwrap(viewModel.waterfall.entries.first)
        XCTAssertTrue(WaterfallChartStyle.valueLabel(for: entry).contains("2.5"))
    }

    /// The defect W19 named, at the surface it reaches the developer through: a failed request
    /// was coloured, named and measured as though it were still running.
    func testAFailedBarIsNamedFailedAndNotPending() async throws {
        let failed = request(duration: 20, status: 0)
        failed.noResponse = true
        failed.responseCode = nil
        let viewModel = TrafficStatsViewModel(requests: [failed], totalCount: 1)
        await viewModel.recompute()
        let entry = try XCTUnwrap(viewModel.waterfall.entries.first)
        XCTAssertEqual(WaterfallChartStyle.outcomeTitle(for: entry), "Failed")
        XCTAssertFalse(entry.isPending)
    }

    func testAStubbedBarIsNamedStubbedWhateverItsStatusSays() async throws {
        let viewModel = TrafficStatsViewModel(
            requests: [request(duration: 2, status: 500, stubbed: true)],
            totalCount: 1
        )
        await viewModel.recompute()
        let entry = try XCTUnwrap(viewModel.waterfall.entries.first)
        XCTAssertEqual(WaterfallChartStyle.outcomeTitle(for: entry), "Stubbed",
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
