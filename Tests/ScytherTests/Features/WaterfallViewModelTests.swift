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
    ///   - host: The request's host. `""` produces a URL with an empty host component, which is
    ///     what ``WaterfallSeries/shortHost(for:)`` also reduces an unparseable host to —
    ///     `showsHost` tests use it to check those are left out of the distinct-host count.
    /// - Returns: The request.
    private func request(
        startedAt: Date,
        duration: Float? = 100,
        path: String = "/v1/users",
        host: String = "api.example.com"
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: "https://\(host)\(path)")!)
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

    /// The whole reason the page exists next to a strip that already draws the whole log too: a
    /// thousand-request burst is one compressed strip either way, but only this page gives each
    /// of those thousand requests its own tappable row.
    func testEveryRequestInTheLogGetsARow() async {
        let requests = (0..<50).map { request(startedAt: origin.addingTimeInterval(Double($0))) }
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.count, 50, "every request gets a row, not a sample of them")
    }

    /// Time reads downward, so the oldest request is the first row.
    func testRowsRunOldestFirst() async {
        let old = request(startedAt: origin, path: "/old")
        let new = request(startedAt: origin.addingTimeInterval(5), path: "/new")
        let viewModel = WaterfallViewModel(requests: [new, old], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.map(\.entry.label), ["GET /old", "GET /new"])
    }

    // `testRowsAreNumberedByTheirPositionInTheLog` used to live here, asserting
    // `Row.label`'s numbered form — `"1. GET /v1/users"`. `WaterfallDetailRow` never drew it: it
    // reads `Row.entry.label` unnumbered instead, stacked under the host, and nothing else in
    // production read the numbered form either. `Row.label` was removed with the test — see the
    // fix report.

    // MARK: - Tapping a bar

    /// A bar is only tappable because its row carries the request it was drawn from. Matching by
    /// label would land the reader on the wrong one of two calls to the same endpoint.
    func testEachRowCarriesTheExactRequestItWasDrawnFrom() async {
        let first = request(startedAt: origin, path: "/v1/users")
        let second = request(startedAt: origin.addingTimeInterval(1), path: "/v1/users")
        let viewModel = WaterfallViewModel(requests: [first, second], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.count, 2)
        XCTAssertTrue(viewModel.layout.rows.first?.request === first)
        XCTAssertTrue(viewModel.layout.rows.last?.request === second)
    }

    /// The row's identity is the request's own hash, so a redraw after new traffic arrives does
    /// not reshuffle which row is which.
    func testARowIsIdentifiedByItsRequest() async {
        let only = request(startedAt: origin)
        let viewModel = WaterfallViewModel(requests: [only], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.first?.id, only.getRandomHash() as String)
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
        XCTAssertEqual(viewModel.layout.rows.first?.entry.start ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.layout.rows.last?.entry.start ?? -1, 10, accuracy: 0.0001)
    }

    /// The section on Traffic Stats and this page now feed the *same* `WaterfallOverviewStrip`
    /// from series built by the same `WaterfallSeries.build` call over the same log — replacing
    /// ``testTheAxisMatchesTheStatsChart``, which compared an axis neither surface still computes
    /// now that the section's `Chart` is gone. That guarantee is stronger than the one it
    /// replaces, not weaker, and it had nothing asserting it: a future change to either `build`
    /// call site — the section's inside ``TrafficStatsViewModel/recompute()``, this page's inside
    /// ``layout(of:totalCount:now:)`` — would silently draw the two screens' strips differently
    /// with every other test still green. `WaterfallSeries` is `Equatable`, so the whole guarantee
    /// is one assertion.
    func testBothSurfacesBuildTheIdenticalSeriesFromTheSameLog() async {
        let requests = [
            request(startedAt: origin),
            request(startedAt: origin.addingTimeInterval(2), path: "/v1/orders"),
        ]
        let page = WaterfallViewModel(requests: requests, totalCount: requests.count)
        let stats = TrafficStatsViewModel(requests: requests, totalCount: requests.count)
        await page.recompute()
        await stats.recompute()
        XCTAssertEqual(page.series, stats.waterfall,
                       "the section's strip and the page's strip must draw the identical series")
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
        XCTAssertEqual(viewModel.layout.rows.count, 1)
    }

    /// A cleared log empties the page, which is what its empty state is for.
    func testAClearedLogLeavesNothingToDraw() async {
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.isEmpty)
        viewModel.update(requests: [], totalCount: 0)
        await viewModel.recompute()
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.layout.rows.isEmpty)
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
        XCTAssertEqual(viewModel.layout.rows.count, 2)
    }

    // MARK: - Saying what it is showing

    // `testTheCaptionNamesBothCountsWhenTheLogIsFiltered` and
    // `testTheCaptionSaysEveryRequestOnlyWhenItIsEveryRequest` used to live here, asserting
    // `WaterfallViewModel.caption` and `.isFiltered`: the sentence under the bars naming "Every
    // request in the log…" or "N of M requests on a shared axis…". `WaterfallView` never read
    // either — it reads `windowCaption` instead, which is built from `visibleRows` and `layout`'s
    // counts alone and already has its own coverage below in
    // `testWindowCaptionCountsAgainstTheFilteredTotalNotTheUnfilteredOne`. Both members, and the
    // two localised sentences they were the only production readers of, were removed together —
    // see the fix report.

    /// `windowCaption` counts against the *filtered* rows the page is drawing, not the log's
    /// unfiltered total. Comparing the window to `total` mixed a filtered numerator with an
    /// unfiltered denominator and could read "5 of 340" for a window over a dozen-request
    /// filtered list.
    ///
    /// Also confirms the caption reads correctly when the window opens as a genuine subset — not
    /// only when it happens to be the whole span: twelve requests one second apart, all the same
    /// duration, opens anchored on the newest two rather than all twelve, so the numerator here is
    /// smaller than `layout.count` for the same reason it must never equal `layout.total`.
    func testWindowCaptionCountsAgainstTheFilteredTotalNotTheUnfilteredOne() async {
        let requests = (0..<12).map { request(startedAt: origin.addingTimeInterval(Double($0))) }
        let viewModel = WaterfallViewModel(requests: requests, totalCount: 340)
        await viewModel.recompute()
        viewModel.configureWindow(plotWidth: 240)

        XCTAssertNotEqual(viewModel.layout.count, viewModel.layout.total, "the log is filtered")
        XCTAssertLessThan(viewModel.visibleRows.count, viewModel.layout.count,
                          "the window opens as a genuine subset, not the whole span")
        XCTAssertTrue(viewModel.windowCaption.contains("\(viewModel.visibleRows.count)"))
        XCTAssertFalse(viewModel.windowCaption.contains("340"),
                       "the denominator is the filtered row count, not the log's unfiltered total")
    }

    // MARK: - Showing the host

    /// A single host repeated on every row is noise, not information — the row should not draw
    /// it.
    func testASingleHostIsNotShown() async {
        let requests = (0..<3).map {
            request(startedAt: origin.addingTimeInterval(Double($0)), host: "example.com")
        }
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.showsHost)
    }

    /// The moment a second distinct host appears, it becomes the one thing that tells two rows
    /// apart, so it earns its place on the row.
    func testSeveralDistinctHostsAreShown() async {
        let requests = [
            request(startedAt: origin, host: "example.com"),
            request(startedAt: origin.addingTimeInterval(1), host: "another.com"),
        ]
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertTrue(viewModel.showsHost)
    }

    /// A request whose URL did not parse a host at all must not count as a second "host" on its
    /// own — that would show a host label with nothing in it beside the one host that is real.
    func testAnEmptyHostIsNotCountedAsADistinctHost() async {
        let requests = [
            request(startedAt: origin, host: "example.com"),
            request(startedAt: origin.addingTimeInterval(1), host: ""),
        ]
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.showsHost, "one real host and one empty one is still one host")
    }

    /// Two entries at the *same* host, even spelled with a leading `www.` on one of them, must
    /// not be counted as two distinct hosts — `shortHost` is what the row actually draws, and
    /// `www.example.com` and `example.com` draw identically.
    func testHostsThatShortenToTheSameLabelAreNotCountedTwice() async {
        let requests = [
            request(startedAt: origin, host: "example.com"),
            request(startedAt: origin.addingTimeInterval(1), host: "www.example.com"),
        ]
        let viewModel = WaterfallViewModel(requests: requests, totalCount: requests.count)
        await viewModel.recompute()
        XCTAssertFalse(viewModel.showsHost)
    }

    // `testTheCachedPercentilesDescribeTheSeriesTheRowsWereLaidOutOn` used to live here, pinning
    // `Layout.medianDuration` and `.tailDuration` to `WaterfallDurations.percentile(_:of:)` over
    // the series' measured durations. Both fields, and the function, were removed — see
    // `WaterfallDurations`' own type documentation for why nothing in production read them any
    // more. `Layout.shortestMeasured`, the cached figure that *is* still read — by the zoom limit,
    // through `configureWindow(plotWidth:)` — keeps its own coverage: every test below that zooms
    // to the limit and checks where the window lands is exercising it end to end.

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
        XCTAssertEqual(viewModel.layout.rows.count, 3)
    }

    // MARK: - The window

    /// Builds a view model over requests at known offsets, each lasting `duration` seconds.
    ///
    /// The brief this suite was written from called for a bare `WaterfallViewModel()` followed by
    /// `update(requests:totalCount:)`, but the type has no such initialiser — every call site,
    /// production included, builds it with `init(requests:totalCount:)`. That designated
    /// initialiser is used here instead; see the task report for the discrepancy.
    private func makeModel(starts: [TimeInterval], duration: TimeInterval = 0.05,
                          openingTime: TimeInterval? = nil) -> WaterfallViewModel {
        let origin = Date(timeIntervalSince1970: 1_000)
        let requests: [HTTPRequest] = starts.map { offset in
            let request = HTTPRequest()
            request.requestURL = "https://api.ipify.org/?format=json"
            request.requestMethod = "GET"
            request.requestDate = origin.addingTimeInterval(offset)
            request.responseDate = origin.addingTimeInterval(offset + duration)
            return request
        }
        return WaterfallViewModel(requests: requests, totalCount: requests.count, openingTime: openingTime)
    }

    /// The page's first body render happens before `onFirstAppear`'s asynchronous first
    /// `recompute()` can run, so if `init` did not also configure the window, that first frame
    /// would read `window` at its zero-valued default — an empty `visibleRows` and
    /// `isWindowEmpty` `true` — over a `layout` that is already full. Deliberately does not
    /// `await recompute()`, which is the case every other test in this file has already moved
    /// past by the time it makes an assertion.
    ///
    /// Not asserting the full row count any more: the window this first configuration opens —
    /// see `WaterfallWindow.opening(...)` and ``WaterfallViewModel/windowFollowsDefault`` — anchors
    /// on the newest traffic rather than the whole span, so legitimately showing only the tail of
    /// the log on the very first frame is not a bug. What still has to be true from that first
    /// frame is that it is not the *empty* placeholder.
    func testTheWindowIsAlreadyConfiguredBeforeTheFirstRecompute() {
        let model = makeModel(starts: [0, 10, 20, 30])

        XCTAssertFalse(model.visibleRows.isEmpty, "no flash of empty before recompute() runs")
        XCTAssertFalse(model.isWindowEmpty)
    }

    /// A log short enough that the zoom floor already equals the whole span opens at the whole
    /// span — see `WaterfallWindow.opening(...)`'s own tests for the rule in isolation; this pins
    /// the same behaviour end to end through `configureWindow(plotWidth:)`. All four requests here
    /// share the same 50ms duration and are clustered within a tenth of a second of each other, so
    /// the zoom floor (0.5s, at 24pt/240pt against that shared duration) exceeds the 0.11s span
    /// outright, `narrowestDuration` clamps it down to the span, and half of *that* span still
    /// clamps back up to it — the whole-span branch, not the anchored one; see
    /// `testALongLogOpensAnchoredOnTheNewestTraffic` for that one.
    func testAShortLogOpensShowingTheWholeSpan() async {
        let model = makeModel(starts: [0, 0.02, 0.04, 0.06])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertEqual(model.window.start, 0, accuracy: 0.0001)
        XCTAssertEqual(model.window.duration, model.series.span, accuracy: 0.0001,
                       "short enough that the demanded width already reaches the whole span")
        XCTAssertEqual(model.visibleRows.count, 4)
    }

    /// The defect the owner reported: a long log — modelled here on the hour-long capture with
    /// two bursts of traffic an hour apart — must not open with every bar floored to the same
    /// width. It opens anchored on the newest traffic instead, as a genuine subset, with the
    /// older burst left outside the window and the strip's overlay therefore already visible.
    func testALongLogOpensAnchoredOnTheNewestTraffic() async {
        let model = makeModel(starts: [0, 0.02, 0.04, 3_500, 3_500.02, 3_500.04])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertEqual(model.window.end, model.series.span, accuracy: 0.0001,
                       "anchored on the newest traffic")
        XCTAssertLessThan(model.window.duration, model.series.span,
                          "a genuine subset, not the whole span")
        XCTAssertTrue(model.window.marksASubset, "the overlay must be visible the moment it opens")
        // Compared with `accuracy:` element by element rather than a single array equality: the
        // starts recovered through `Date.addingTimeInterval`/`timeIntervalSince` at a ~3,500
        // second offset carry a few hundred nanoseconds of floating-point drift from the literal
        // seconds requested, which an exact `XCTAssertEqual` on the array does not tolerate.
        let starts = model.visibleRows.map(\.entry.start)
        XCTAssertEqual(starts.count, 3, "the older burst an hour earlier is outside the window")
        for (start, expected) in zip(starts, [3_500, 3_500.02, 3_500.04]) {
            XCTAssertEqual(start, expected, accuracy: 0.0001)
        }
    }

    /// One request: its own duration is the only measurement there is, so the zoom floor
    /// `narrowestDuration` computes from it already equals the whole span, and half of that span
    /// clamps straight back up to it — the window opens at the whole span and cannot zoom,
    /// matching `testASingleRequestCannotZoom` below.
    func testASingleRequestOpensShowingTheWholeSpan() async {
        let model = makeModel(starts: [0])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertEqual(model.window.start, 0, accuracy: 0.0001)
        XCTAssertEqual(model.window.duration, model.series.span, accuracy: 0.0001)
        XCTAssertEqual(model.visibleRows.count, 1)
    }

    /// Nothing logged at all: the window opens at the same degenerate span-zero state it always
    /// has, without dividing by zero or crashing.
    func testAnEmptyLogOpensWithTheEmptyWindow() {
        let model = WaterfallViewModel(requests: [], totalCount: 0)
        model.configureWindow(plotWidth: 240)

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.window.duration, 0)
        XCTAssertFalse(model.window.canZoom)
    }

    /// The tapped moment on the Traffic Stats strip is threaded through `init`'s own
    /// `openingTime` parameter rather than applied by the view afterwards — see
    /// ``WaterfallView/init(logs:openingTime:)`` — precisely so `@StateObject` can keep deferring
    /// this initialiser's whole-log layout until the page is actually inserted into the tree.
    /// Nothing was asserting that the parameter is actually applied; this does, before either
    /// `recompute()` or `configureWindow(plotWidth:)` has run, the same synchronous guarantee
    /// ``testTheWindowIsAlreadyConfiguredBeforeTheFirstRecompute`` pins for the ordinary open.
    func testOpeningTimePassedToInitCentresTheWindowBeforeAnyRecompute() {
        let model = makeModel(starts: [0, 10, 20, 30], openingTime: 20)

        XCTAssertLessThan(model.window.duration, model.series.span,
                          "span / 8 is narrower than the whole span")
        XCTAssertEqual(model.window.centre, 20, accuracy: 0.5)
    }

    /// Five requests, three of them clustered at the middle of the log (14s, 15s, 16s) and two
    /// at the far ends (0s, 30s). Zooming in 8x from the whole 30.05s span narrows it to ~3.756s,
    /// still centred at 15.025s, which brackets exactly the three middle requests and excludes
    /// both end ones. Checking the exact survivors — not just that `visibleRows` agrees with
    /// `window.contains`, which holds by definition of `visibleRows` however wrong the zoom
    /// arithmetic is — is what makes this catch a mis-centred or mis-scaled zoom.
    ///
    /// `zoom(by: 0.001)` first forces the window back out to the whole span, establishing a known
    /// baseline before narrowing it back in: the page no longer necessarily opens there by
    /// default — see `WaterfallWindow.opening(...)` — so this test can no longer assume it without
    /// asserting that separately, and this is exactly what it exists to avoid depending on.
    func testZoomingDropsTheRowsThatLeaveTheWindow() async {
        let model = makeModel(starts: [0, 14, 15, 16, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 0.001)
        model.zoom(by: 8)

        XCTAssertEqual(model.visibleRows.map(\.entry.start), [14, 15, 16])
    }

    func testScrubbingMovesTheWindowToTheTimeTouched() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 8)
        model.scrub(to: 20)

        XCTAssertEqual(model.window.centre, 20, accuracy: 0.5)
    }

    /// Dragging into a stretch with no traffic must say so rather than showing a blank list.
    func testAWindowOverAGapReportsItselfEmpty() async {
        let model = makeModel(starts: [0, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 20)
        model.scrub(to: 15)

        XCTAssertTrue(model.visibleRows.isEmpty)
        XCTAssertTrue(model.isWindowEmpty)
    }

    // MARK: - The escape from a gap

    /// The button `WaterfallView`'s gap empty state offers has to land somewhere with traffic in
    /// it, not merely somewhere different: dragging into another empty stretch would be no escape
    /// at all.
    func testResetWindowReturnsToTheMostRecentTraffic() async {
        let model = makeModel(starts: [0, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 20)
        model.scrub(to: 15)
        XCTAssertTrue(model.isWindowEmpty, "starting from the same gap the reported defect describes")

        model.resetWindow()

        XCTAssertFalse(model.visibleRows.isEmpty, "the escape must land somewhere with traffic")
        XCTAssertFalse(model.isWindowEmpty)
        XCTAssertEqual(model.window.end, model.series.span, accuracy: 0.0001,
                       "anchored on the most recent traffic, the same as the page's own opening default")
    }

    /// `resetWindow()` has to do more than move the window once: a developer who taps the button
    /// and then leaves the page open while more traffic streams in should see it keep tracking the
    /// tail of the log, the same as a page nobody has touched at all — not freeze wherever the
    /// button happened to leave it.
    func testResetWindowResumesTrackingNewTraffic() async {
        let model = makeModel(starts: [0, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 20)
        model.scrub(to: 15)
        model.resetWindow()
        XCTAssertEqual(model.window.end, model.series.span, accuracy: 0.0001)

        // New traffic arrives well past the old span; an untouched page's window would move to
        // keep tracking it, via `configureWindow(plotWidth:)`'s own `windowFollowsDefault` branch
        // running again on the next `recompute()`.
        let origin = Date(timeIntervalSince1970: 1_000)
        let newer = HTTPRequest()
        newer.requestURL = "https://api.ipify.org/?format=json"
        newer.requestMethod = "GET"
        newer.requestDate = origin.addingTimeInterval(60)
        newer.responseDate = origin.addingTimeInterval(60.05)
        model.update(requests: model.requests + [newer], totalCount: model.requests.count + 1)
        await model.recompute()

        XCTAssertEqual(model.window.end, model.series.span, accuracy: 0.0001,
                       "still tracking the tail of the log after the button was used")
        XCTAssertGreaterThan(model.series.span, 30, "the new request really did extend the span")
    }

    func testASingleRequestCannotZoom() async {
        let model = makeModel(starts: [0])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertFalse(model.window.canZoom)
    }

    func testOpeningCentredOnATimeUsesAnEighthOfTheSpan() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.open(centredOn: 20)

        XCTAssertEqual(model.window.duration,
                       model.series.span * WaterfallViewModel.openingWindowFraction,
                       accuracy: 0.01)
        XCTAssertEqual(model.window.centre, 20, accuracy: 0.5)
    }

    /// Re-measuring the plot must not throw away where the developer had scrolled to.
    func testReconfiguringForANewWidthKeepsTheCentre() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 4)
        model.scrub(to: 20)
        let centre = model.window.centre

        model.configureWindow(plotWidth: 180)

        XCTAssertEqual(model.window.centre, centre, accuracy: 0.5)
    }

    /// The test above only ever narrows the plot, which lowers the narrowest allowed duration and
    /// never forces the window wider than it already is. A rotation or a Dynamic Type change that
    /// *widens* the plot raises the floor instead, and can raise it above the window's current
    /// duration — the case that exposed the centre drifting by half of whatever the duration was
    /// forced to grow.
    func testReconfiguringForAWiderPlotThatForcesTheDurationUpKeepsTheCentre() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 20)
        model.scrub(to: 12)
        let centre = model.window.centre
        let durationBefore = model.window.duration
        XCTAssertLessThan(durationBefore, 6,
                          "the window must start out narrower than the new floor below")

        // 0.05s (the shortest measured duration here) drawn at 24pt across a 2,880pt plot demands
        // a 6s window — well above durationBefore, so the duration is forced to grow.
        model.configureWindow(plotWidth: 2_880)

        XCTAssertGreaterThan(model.window.duration, durationBefore, "the floor really was raised")
        XCTAssertEqual(model.window.centre, centre, accuracy: 0.0001)
    }

    // MARK: - The visible-rows cache

    /// `visibleRows` is a cache, not a computed property re-filtered on every read — see
    /// ``WaterfallViewModel/visibleRows``'s own documentation. This proves it invalidates on a
    /// change to `window`, at a fixed `layout`: zooming past a request without touching the log
    /// has to drop it from the cached array, not just from what a fresh filter would produce.
    ///
    /// `zoom(by: 0.001)` establishes a known whole-span baseline first: the page no longer
    /// necessarily opens there by default — see `WaterfallWindow.opening(...)` — so this can no
    /// longer be assumed the way it once was.
    func testVisibleRowsCacheInvalidatesWhenTheWindowChanges() async {
        let model = makeModel(starts: [0, 14, 15, 16, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 0.001)
        XCTAssertEqual(model.visibleRows.count, 5, "the whole span holds every row")

        model.zoom(by: 8)
        model.scrub(to: 15)

        XCTAssertEqual(model.visibleRows.map(\.entry.start), [14, 15, 16],
                       "the cache must reflect the narrowed, re-centred window")
    }

    /// The other half of the same guarantee: invalidation on a change to `layout`, at a fixed
    /// `window`. New traffic arriving inside an already-open window has to appear without the
    /// developer touching the window at all — a cache invalidated only by `window` would miss
    /// exactly this.
    ///
    /// `scrub(to:)` to the window's own centre is a deliberate no-op move, made only to mark the
    /// window as held — see ``WaterfallViewModel/windowFollowsDefault``. Without it, the traffic
    /// added below would itself re-anchor the still-following-default window to the new newest
    /// request when `update(requests:totalCount:)`'s `recompute()` calls `configureWindow(plotWidth:)`
    /// again, which would conflate "the window moved because it is still tracking the tail of the
    /// log" with the cache-invalidation property this test exists to isolate.
    ///
    /// The second request lands 0.2s after the first rather than a full second: both share the
    /// same 100ms duration, so the zoom floor `narrowestDuration` computes from the shortest
    /// reading demands 1s at this plot width — comfortably wider than the resulting 0.3s span —
    /// and the held window is forced open to that whole span with margin either side of both
    /// entries, rather than depending on an exact floating-point edge for the second one to fall
    /// inside it.
    func testVisibleRowsCacheInvalidatesWhenNewTrafficArrives() async {
        let viewModel = WaterfallViewModel(requests: [request(startedAt: origin)], totalCount: 1)
        await viewModel.recompute()
        viewModel.configureWindow(plotWidth: 240)
        viewModel.scrub(to: viewModel.window.centre)
        XCTAssertEqual(viewModel.visibleRows.count, 1)

        viewModel.update(
            requests: [request(startedAt: origin), request(startedAt: origin.addingTimeInterval(0.2))],
            totalCount: 2
        )
        await viewModel.recompute()

        XCTAssertEqual(viewModel.visibleRows.count, 2, "new traffic must appear without touching the window")
    }
}
