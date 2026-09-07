//
//  WaterfallSeriesTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Pins the timeline arithmetic in ``WaterfallSeries``.
///
/// Offsets, spans and the pending tail are all subtraction between dates, which is exactly the
/// kind of arithmetic that looks right on screen while being a second out.
final class WaterfallSeriesTests: XCTestCase {

    /// The origin every fixture is measured from.
    private let base = Date(timeIntervalSince1970: 1_000_000)

    /// Builds a captured request that started `offset` seconds after ``base``.
    ///
    /// A finished load is stamped with a response date whether or not a response arrived, exactly
    /// as `HTTPRequest` does: `saveResponse(_:data:)` sets one and so does `saveErrorResponse()`.
    /// That date, not `noResponse`, is what separates a request still in flight from one that
    /// finished badly.
    ///
    /// - Parameters:
    ///   - offset: Seconds after ``base`` that the request started.
    ///   - duration: The round trip in milliseconds, or `nil` for a load that recorded none.
    ///   - status: The response status code, or `nil` for a load that came back with no response.
    ///   - url: The request URL.
    ///   - graphQL: The GraphQL operation name, if this is a GraphQL request.
    ///   - stubbed: Whether a rule synthesised the response.
    ///   - finished: Whether the load ended. `false` is a request still in flight.
    /// - Returns: The request.
    private func request(
        offset: TimeInterval,
        duration: Float? = 100,
        status: Int? = 200,
        url: String = "https://api.example.com/v1/users",
        graphQL: String? = nil,
        stubbed: Bool = false,
        finished: Bool = true
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = base.addingTimeInterval(offset)
        model.requestDuration = duration
        model.responseCode = status
        model.noResponse = status == nil
        if finished {
            model.responseDate = base.addingTimeInterval(offset + Double(duration ?? 0) / 1_000)
        }
        model.wasStubbed = stubbed
        if let graphQL {
            model.isGraphQL = true
            model.graphQLOperationName = graphQL
        }
        return model
    }

    func testOriginIsTheEarliestStart() {
        let series = WaterfallSeries.build(from: [request(offset: 5), request(offset: 0), request(offset: 2)])
        XCTAssertEqual(series.origin, base)
        XCTAssertEqual(series.entries.map(\.start).min(), 0)
    }

    func testOffsetsAreSecondsFromTheOrigin() {
        let series = WaterfallSeries.build(from: [request(offset: 0), request(offset: 3)])
        XCTAssertEqual(series.entries.map(\.start).sorted(), [0, 3])
    }

    func testEntriesAreOrderedOldestFirst() {
        let series = WaterfallSeries.build(from: [request(offset: 4), request(offset: 1), request(offset: 9)])
        XCTAssertEqual(series.entries.map(\.start), [0, 3, 8], "offsets are measured from the earliest start")
    }

    func testDurationIsConvertedFromMillisecondsToSeconds() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: 250)])
        XCTAssertEqual(series.entries.first?.duration ?? 0, 0.25, accuracy: 0.0001)
    }

    func testSpanCoversTheLastRequestsEnd() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: 500), request(offset: 2, duration: 1_000)])
        XCTAssertEqual(series.span, 3, accuracy: 0.0001)
    }

    func testSpanCoversAnEarlyRequestThatOutlastsALaterOne() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: 10_000), request(offset: 1, duration: 100)])
        XCTAssertEqual(series.span, 10, accuracy: 0.0001, "the span is the latest finish, not the last start")
    }

    func testANegativeDurationIsDrawnAsZero() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: -500)])
        XCTAssertEqual(series.entries.first?.duration ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(series.span, 0, accuracy: 0.0001)
    }

    func testAPendingRequestRunsToTheEndOfTheSpan() {
        let series = WaterfallSeries.build(
            from: [
                request(offset: 0, duration: 2_000),
                request(offset: 1, duration: nil, status: nil, finished: false),
            ],
            now: base.addingTimeInterval(2)
        )
        let pending = series.entries.first { $0.isPending }
        XCTAssertEqual(pending?.start ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual((pending?.start ?? 0) + (pending?.duration ?? 0), series.span, accuracy: 0.0001)
    }

    /// The defect W20 named: a request still in flight that started after everything else had
    /// finished used to be given a zero-width bar, because the axis was sized from the finished
    /// bars alone. That is the request a developer opens the screen to look at.
    func testTheNewestPendingRequestStillHasABar() {
        let series = WaterfallSeries.build(
            from: [
                request(offset: 0, duration: 1_000),
                request(offset: 4, duration: nil, status: nil, finished: false),
            ],
            now: base.addingTimeInterval(9)
        )
        let pending = try? XCTUnwrap(series.entries.first { $0.isPending })
        XCTAssertEqual(pending?.duration ?? -1, 5, accuracy: 0.0001,
                       "it started five seconds ago and has not come back, so its bar is five seconds long")
        XCTAssertEqual(series.span, 9, accuracy: 0.0001, "the axis runs to now, not to the last finish")
    }

    func testAPendingRequestAloneRunsFromItsStartToNow() {
        let series = WaterfallSeries.build(
            from: [request(offset: 0, duration: nil, status: nil, finished: false)],
            now: base.addingTimeInterval(3)
        )
        XCTAssertEqual(series.entries.count, 1)
        XCTAssertEqual(series.entries.first?.duration ?? -1, 3, accuracy: 0.0001)
        XCTAssertEqual(series.span, 3, accuracy: 0.0001)
    }

    func testNothingInFlightLeavesTheAxisAtTheLastFinish() {
        let series = WaterfallSeries.build(
            from: [request(offset: 0, duration: 1_000)],
            now: base.addingTimeInterval(600)
        )
        XCTAssertEqual(series.span, 1, accuracy: 0.0001,
                       "a series with nothing running does not stretch to the present")
    }

    /// The defect W19 named: a load that ended in an error carries a response date and no
    /// response, so deriving pending from `noResponse` drew every failure in the log as still
    /// running and stretched its bar to the end of the chart.
    func testARequestThatFailedIsDrawnForAsLongAsItRan() {
        let failed = request(offset: 0, duration: nil, status: nil)
        failed.responseDate = base.addingTimeInterval(0.02)
        let series = WaterfallSeries.build(
            from: [failed, request(offset: 1, duration: 5_000)],
            now: base.addingTimeInterval(60)
        )
        let entry = try? XCTUnwrap(series.entries.first)
        XCTAssertFalse(entry?.isPending ?? true, "it finished; it just finished badly")
        XCTAssertTrue(entry?.isFailure ?? false)
        XCTAssertEqual(entry?.duration ?? -1, 0.02, accuracy: 0.0001,
                       "twenty milliseconds, not the whole timeline")
    }

    func testTwoOverlappingRequestsShareTheAxis() {
        let series = WaterfallSeries.build(from: [
            request(offset: 0, duration: 3_000),
            request(offset: 1, duration: 1_000),
        ])
        let first = series.entries[0]
        let second = series.entries[1]
        XCTAssertLessThan(second.start, first.start + first.duration, "the second starts before the first finishes")
        XCTAssertEqual(series.span, 3, accuracy: 0.0001)
    }

    func testTheLimitKeepsTheMostRecentEntries() {
        let requests = (0..<10).map { request(offset: TimeInterval($0)) }
        let series = WaterfallSeries.build(from: requests, limit: 3)
        XCTAssertEqual(series.entries.count, 3)
        XCTAssertEqual(series.origin, base.addingTimeInterval(7))
    }

    /// The default is what the preview section on **Traffic Stats** takes, and a preview that
    /// draws everything is not one: at forty it filled the card with a twenty-two request log and
    /// left the **See all** page it links to showing the same picture.
    func testTheDefaultLimitIsAGlanceRatherThanTheWholeLog() {
        let series = WaterfallSeries.build(from: (0..<50).map { request(offset: TimeInterval($0)) })
        XCTAssertEqual(series.entries.count, WaterfallSeries.defaultLimit)
        XCTAssertLessThanOrEqual(WaterfallSeries.defaultLimit, 10, "a preview has to read as one")
        XCTAssertEqual(series.origin,
                       base.addingTimeInterval(TimeInterval(50 - WaterfallSeries.defaultLimit)),
                       "and it keeps the most recent, not the oldest")
    }

    func testALimitOfZeroProducesAnEmptySeries() {
        let series = WaterfallSeries.build(from: [request(offset: 0)], limit: 0)
        XCTAssertTrue(series.entries.isEmpty)
        XCTAssertEqual(series.span, 0)
    }

    func testARequestWithNoStartDateCannotBePlaced() {
        let undated = request(offset: 0)
        undated.requestDate = nil
        let series = WaterfallSeries.build(from: [undated, request(offset: 1)])
        XCTAssertEqual(series.entries.count, 1)
        XCTAssertEqual(series.origin, base.addingTimeInterval(1))
    }

    func testLabelPrefersTheGraphQLOperationName() {
        let series = WaterfallSeries.build(from: [request(offset: 0, graphQL: "GetUser")])
        XCTAssertEqual(series.entries.first?.label, "GetUser")
    }

    func testLabelFallsBackToMethodAndPath() {
        let series = WaterfallSeries.build(from: [request(offset: 0, url: "https://api.example.com/v1/users?page=2")])
        XCTAssertEqual(series.entries.first?.label, "GET /v1/users")
    }

    func testLabelOfARootPath() {
        let series = WaterfallSeries.build(from: [request(offset: 0, url: "https://api.example.com")])
        XCTAssertEqual(series.entries.first?.label, "GET /")
    }

    func testFailuresAreFlagged() {
        let series = WaterfallSeries.build(from: [request(offset: 0, status: 500)])
        XCTAssertTrue(series.entries.first?.isFailure ?? false)
        XCTAssertFalse(series.entries.first?.isPending ?? true)
    }

    func testASuccessIsNotFlagged() {
        let series = WaterfallSeries.build(from: [request(offset: 0, status: 204)])
        XCTAssertFalse(series.entries.first?.isFailure ?? true)
    }

    func testAPendingRequestHasNotFailedYet() {
        let series = WaterfallSeries.build(
            from: [request(offset: 0, duration: nil, status: nil, finished: false)],
            now: base.addingTimeInterval(1)
        )
        XCTAssertTrue(series.entries.first?.isPending ?? false)
        XCTAssertFalse(series.entries.first?.isFailure ?? true, "nothing has gone wrong yet")
    }

    func testALoadThatEndedWithNoResponseIsAFailureAndNotPending() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: nil, status: nil)])
        XCTAssertTrue(series.entries.first?.isFailure ?? false)
        XCTAssertFalse(series.entries.first?.isPending ?? true)
    }

    func testAStubbedRequestKeepsItsPlaceOnTheTimelineAndIsFlagged() {
        let series = WaterfallSeries.build(from: [
            request(offset: 0, duration: 1_000),
            request(offset: 0.5, duration: 2, stubbed: true),
        ])
        XCTAssertEqual(series.entries.count, 2, "a stub still happened, so it still occupies the timeline")
        XCTAssertEqual(series.entries.filter(\.isStubbed).count, 1)
    }

    func testEntryIdentifiersAreUnique() {
        let series = WaterfallSeries.build(from: (0..<5).map { request(offset: TimeInterval($0)) })
        XCTAssertEqual(Set(series.entries.map(\.id)).count, 5)
    }

    func testAnEmptyInputProducesAnEmptySeries() {
        let series = WaterfallSeries.build(from: [])
        XCTAssertTrue(series.entries.isEmpty)
        XCTAssertEqual(series.span, 0)
    }

    func testTheEmptyValueHasNothingInIt() {
        XCTAssertTrue(WaterfallSeries.empty.entries.isEmpty)
        XCTAssertEqual(WaterfallSeries.empty.span, 0)
    }
}
