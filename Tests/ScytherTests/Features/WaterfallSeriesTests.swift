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
    /// - Parameters:
    ///   - offset: Seconds after ``base`` that the request started.
    ///   - duration: The round trip in milliseconds, or `nil` for a request still in flight.
    ///   - status: The response status code, or `nil` for a request still in flight.
    ///   - url: The request URL.
    ///   - graphQL: The GraphQL operation name, if this is a GraphQL request.
    ///   - stubbed: Whether a rule synthesised the response.
    /// - Returns: The request.
    private func request(
        offset: TimeInterval,
        duration: Float? = 100,
        status: Int? = 200,
        url: String = "https://api.example.com/v1/users",
        graphQL: String? = nil,
        stubbed: Bool = false
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = base.addingTimeInterval(offset)
        model.requestDuration = duration
        model.responseCode = status
        model.noResponse = status == nil
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
        let series = WaterfallSeries.build(from: [
            request(offset: 0, duration: 2_000),
            request(offset: 1, duration: nil, status: nil),
        ])
        let pending = series.entries.first { $0.isPending }
        XCTAssertEqual(pending?.start ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual((pending?.start ?? 0) + (pending?.duration ?? 0), series.span, accuracy: 0.0001)
    }

    func testAPendingRequestAloneHasNoSpanToRunInto() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: nil, status: nil)])
        XCTAssertEqual(series.entries.count, 1)
        XCTAssertEqual(series.entries.first?.duration ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(series.span, 0, accuracy: 0.0001)
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

    func testTheDefaultLimitIsForty() {
        let series = WaterfallSeries.build(from: (0..<50).map { request(offset: TimeInterval($0)) })
        XCTAssertEqual(series.entries.count, 40)
        XCTAssertEqual(series.origin, base.addingTimeInterval(10))
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

    func testAPendingRequestIsAFailureAndPending() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: nil, status: nil)])
        XCTAssertTrue(series.entries.first?.isFailure ?? false)
        XCTAssertTrue(series.entries.first?.isPending ?? false)
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
