//
//  TrafficStatisticsTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Pins the arithmetic in ``TrafficStatistics`` on fixtures built by hand.
///
/// Every figure the screen shows is checked here rather than through the view model, because a
/// median that is quietly one rank out looks entirely plausible on screen.
final class TrafficStatisticsTests: XCTestCase {

    /// Builds a captured request with the given shape.
    ///
    /// - Parameters:
    ///   - url: The request URL.
    ///   - method: The HTTP method.
    ///   - status: The response status code, or `nil` for a request that never came back.
    ///   - duration: The round trip in milliseconds, or `nil` when there was no response.
    ///   - size: The response body length in bytes.
    ///   - stubbed: Whether a rule synthesised the response.
    /// - Returns: The request.
    private func request(
        url: String = "https://api.example.com/v1/users",
        method: String = "GET",
        status: Int? = 200,
        duration: Float? = 100,
        size: Int? = 500,
        stubbed: Bool = false
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = method
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.responseCode = status
        model.requestDuration = duration
        model.responseBodyLength = size
        model.noResponse = status == nil
        model.wasStubbed = stubbed
        return model
    }

    // MARK: Percentiles

    func testMedianOfAnOddCount() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 10), request(duration: 30), request(duration: 20),
            request(duration: 40), request(duration: 50),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 30)
    }

    func testMedianOfAnEvenCountUsesNearestRank() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 10), request(duration: 20), request(duration: 30),
            request(duration: 40), request(duration: 50), request(duration: 60),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 30, "nearest rank takes the lower of the two middles")
    }

    func testMedianOfASingleRequestIsThatRequest() {
        let stats = TrafficStatistics.compute(from: [request(duration: 77)])
        XCTAssertEqual(stats.summary.medianDuration, 77)
        XCTAssertEqual(stats.summary.p95Duration, 77)
        XCTAssertEqual(stats.summary.fastestDuration, 77)
        XCTAssertEqual(stats.summary.slowestDuration, 77)
    }

    func testP95OfTwentyRequests() {
        let stats = TrafficStatistics.compute(from: (1...20).map { request(duration: Float($0 * 10)) })
        XCTAssertEqual(stats.summary.p95Duration, 190)
    }

    func testP95OfFortyRequests() {
        let stats = TrafficStatistics.compute(from: (1...40).map { request(duration: Float($0)) })
        XCTAssertEqual(stats.summary.p95Duration, 38, "ceil(0.95 * 40) is rank 38, not 39")
    }

    func testP95OfOneHundredRequests() {
        let stats = TrafficStatistics.compute(from: (1...100).map { request(duration: Float($0)) })
        XCTAssertEqual(stats.summary.p95Duration, 95, "ceil(0.95 * 100) is rank 95, not 96")
    }

    func testP95OfThreeRequestsIsTheSlowest() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 10), request(duration: 20), request(duration: 30),
        ])
        XCTAssertEqual(stats.summary.p95Duration, 30, "the rank never runs past the end of the sample")
    }

    func testNoCompletedRequestsHasNoPercentiles() {
        let stats = TrafficStatistics.compute(from: [request(status: nil, duration: nil, size: nil)])
        XCTAssertNil(stats.summary.medianDuration)
        XCTAssertNil(stats.summary.p95Duration)
        XCTAssertNil(stats.summary.fastestDuration)
        XCTAssertNil(stats.summary.slowestDuration)
        XCTAssertEqual(stats.summary.pendingCount, 1)
        XCTAssertEqual(stats.summary.completedCount, 0)
    }

    func testPendingRequestsAreExcludedFromPercentiles() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 100), request(duration: 200),
            request(status: nil, duration: nil, size: nil),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 100)
        XCTAssertEqual(stats.summary.requestCount, 3)
        XCTAssertEqual(stats.summary.pendingCount, 1)
        XCTAssertEqual(stats.summary.completedCount, 2)
    }

    func testANegativeDurationIsNotTreatedAsASample() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: -50), request(duration: 100), request(duration: 300),
        ])
        XCTAssertEqual(stats.summary.completedCount, 2, "a clock that went backwards is not a measurement")
        XCTAssertEqual(stats.summary.medianDuration, 100)
        XCTAssertEqual(stats.summary.fastestDuration, 100)
    }

    // MARK: Failures

    func testFailuresCountClientServerErrorsAndNoResponse() {
        let stats = TrafficStatistics.compute(from: [
            request(status: 200), request(status: 404), request(status: 500),
            request(status: nil, duration: nil, size: nil), request(status: 301),
        ])
        XCTAssertEqual(stats.summary.failureCount, 3, "404, 500 and the pending entry")
    }

    func testAFourHundredIsAFailureAndAThreeNinetyNineIsNot() {
        let stats = TrafficStatistics.compute(from: [request(status: 399), request(status: 400)])
        XCTAssertEqual(stats.summary.failureCount, 1, "the boundary is at 400 inclusive")
    }

    // MARK: Stubs

    func testAStubbedResponseIsCountedButNeverMeasured() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 100, size: 500),
            request(duration: 1, size: 900, stubbed: true),
        ])
        XCTAssertEqual(stats.summary.requestCount, 2)
        XCTAssertEqual(stats.summary.stubbedCount, 1)
        XCTAssertEqual(stats.summary.measuredCount, 1)
        XCTAssertEqual(stats.summary.completedCount, 1)
        XCTAssertEqual(stats.summary.medianDuration, 100, "a synthesised duration is not a latency")
        XCTAssertEqual(stats.summary.bytesReceived, 500, "stubbed bytes never crossed the network")
    }

    func testAStubbedErrorIsNotCountedAsAFailure() {
        let stats = TrafficStatistics.compute(from: [
            request(status: 200), request(status: 500, stubbed: true),
        ])
        XCTAssertEqual(stats.summary.failureCount, 0, "an authored 500 says nothing about the server")
        XCTAssertEqual(stats.summary.stubbedCount, 1)
    }

    func testAStubbedRequestIsLeftOutOfTheBreakdowns() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://real.example.com/a", duration: 100),
            request(url: "https://mock.example.com/a", duration: 1, stubbed: true),
        ])
        XCTAssertEqual(stats.hosts.map(\.id), ["real.example.com"])
        XCTAssertEqual(stats.endpoints.count, 1)
    }

    func testAWhollyStubbedSessionHasNoMeasurements() {
        let stats = TrafficStatistics.compute(from: (0..<3).map { _ in request(stubbed: true) })
        XCTAssertEqual(stats.summary.requestCount, 3)
        XCTAssertEqual(stats.summary.stubbedCount, 3)
        XCTAssertEqual(stats.summary.measuredCount, 0)
        XCTAssertNil(stats.summary.medianDuration)
        XCTAssertEqual(stats.summary.bytesReceived, 0)
        XCTAssertTrue(stats.hosts.isEmpty)
    }

    // MARK: Failure rate

    func testFailureRateDividesFailuresByTheMeasuredRequests() {
        let stats = TrafficStatistics.compute(from: [
            request(status: 500), request(status: 200), request(status: 200), request(status: 200),
        ])
        XCTAssertEqual(stats.summary.failureRate ?? -1, 0.25, accuracy: 0.0001)
    }

    func testFailureRateIsNilWhenNothingWasMeasured() {
        XCTAssertNil(TrafficStatistics.compute(from: []).summary.failureRate)
        XCTAssertNil(TrafficStatistics.compute(from: [request(stubbed: true)]).summary.failureRate,
                     "a stub is not a measurement, so there is nothing to divide by")
    }

    func testFailureRateIsOneWhenEverythingFailed() {
        let stats = TrafficStatistics.compute(from: [request(status: 500), request(status: 404)])
        XCTAssertEqual(stats.summary.failureRate ?? -1, 1, accuracy: 0.0001)
    }

    func testHostFailureRateIsPerHost() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://a.example.com/x", status: 500),
            request(url: "https://a.example.com/y", status: 200),
            request(url: "https://b.example.com/x", status: 200),
        ])
        XCTAssertEqual(stats.hosts.first { $0.id == "a.example.com" }?.failureRate ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(stats.hosts.first { $0.id == "b.example.com" }?.failureRate ?? -1, 0, accuracy: 0.0001)
    }

    // MARK: Bytes

    func testBytesReceivedSumsResponseSizes() {
        let stats = TrafficStatistics.compute(from: [request(size: 100), request(size: 250), request(size: nil)])
        XCTAssertEqual(stats.summary.bytesReceived, 350)
    }

    // MARK: Wall clock

    func testWallClockSpanCoversTheFirstStartToTheLastFinish() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let first = request()
        first.requestDate = base
        first.responseDate = base.addingTimeInterval(1)
        let second = request()
        second.requestDate = base.addingTimeInterval(2)
        second.responseDate = base.addingTimeInterval(5)
        let stats = TrafficStatistics.compute(from: [second, first])
        XCTAssertEqual(stats.summary.wallClockSpan ?? -1, 5, accuracy: 0.0001)
    }

    func testWallClockSpanFallsBackToTheStartWhenNothingCameBack() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let pending = request(status: nil, duration: nil, size: nil)
        pending.requestDate = base.addingTimeInterval(4)
        pending.responseDate = nil
        let done = request()
        done.requestDate = base
        done.responseDate = base.addingTimeInterval(1)
        let stats = TrafficStatistics.compute(from: [done, pending])
        XCTAssertEqual(stats.summary.wallClockSpan ?? -1, 4, accuracy: 0.0001)
    }

    func testWallClockSpanIsNilWithoutDates() {
        let model = HTTPRequest()
        model.requestDate = nil
        XCTAssertNil(TrafficStatistics.compute(from: [model]).summary.wallClockSpan)
    }

    // MARK: Endpoint identity

    func testEndpointIdentityStripsTheQuery() {
        let identity = TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/users?page=2"))
        XCTAssertEqual(identity, "GET api.example.com/v1/users")
    }

    func testEndpointIdentityCollapsesNumericSegments() {
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/users/42/posts/7")),
            "GET api.example.com/v1/users/:id/posts/:id"
        )
    }

    func testEndpointIdentityCollapsesUUIDSegments() {
        let uuid = "8B1E2C5A-3F4D-4E5A-9C6B-7D8E9F0A1B2C"
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/orders/\(uuid)")),
            "GET api.example.com/v1/orders/:id"
        )
    }

    func testEndpointIdentityKeepsAVersionSegment() {
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/users")),
            "GET api.example.com/v1/users",
            "v1 is not a numeric segment"
        )
    }

    func testEndpointIdentityUppercasesTheMethod() {
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/a", method: "post")),
            "POST api.example.com/a"
        )
    }

    func testEndpointIdentityOfARootPath() {
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/")),
            "GET api.example.com"
        )
    }

    func testEndpointsAggregateAcrossIdentifiers() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://api.example.com/v1/users/1", duration: 100),
            request(url: "https://api.example.com/v1/users/2", duration: 300),
        ])
        XCTAssertEqual(stats.endpoints.count, 1)
        XCTAssertEqual(stats.endpoints.first?.requestCount, 2)
        XCTAssertEqual(stats.endpoints.first?.slowestDuration, 300)
        XCTAssertEqual(stats.endpoints.first?.medianDuration, 100, "nearest rank of two samples is the lower")
    }

    func testTheSameMethodOnDifferentHostsDoesNotAggregate() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://a.example.com/x"), request(url: "https://b.example.com/x"),
        ])
        XCTAssertEqual(stats.endpoints.count, 2)
    }

    // MARK: Hosts

    func testHostBreakdownCountsFailuresAndBytesPerHost() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://a.example.com/x", status: 500, duration: 20, size: 10),
            request(url: "https://a.example.com/y", status: 200, duration: 40, size: 30),
            request(url: "https://b.example.com/x", status: 200, duration: 60, size: 70),
        ])
        let first = stats.hosts.first { $0.id == "a.example.com" }
        XCTAssertEqual(first?.requestCount, 2)
        XCTAssertEqual(first?.failureCount, 1)
        XCTAssertEqual(first?.bytesReceived, 40)
        XCTAssertEqual(first?.medianDuration, 20, "nearest rank of two samples is the lower")
    }

    // MARK: Ordering

    func testEndpointsAreSortedBySlowestFirst() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://api.example.com/fast", duration: 10),
            request(url: "https://api.example.com/slow", duration: 900),
        ])
        XCTAssertEqual(stats.endpoints.map(\.slowestDuration), [900, 10])
    }

    func testEndpointsWithNoDurationSortLast() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://api.example.com/pending", status: nil, duration: nil, size: nil),
            request(url: "https://api.example.com/done", duration: 10),
        ])
        XCTAssertEqual(stats.endpoints.map(\.id).last, "GET api.example.com/pending")
    }

    func testEndpointsTieBreakOnIdentitySoTheOrderIsStable() {
        let requests = ["c", "a", "b"].map { request(url: "https://api.example.com/\($0)", duration: 100) }
        let stats = TrafficStatistics.compute(from: requests)
        XCTAssertEqual(
            stats.endpoints.map(\.id),
            ["GET api.example.com/a", "GET api.example.com/b", "GET api.example.com/c"]
        )
    }

    func testHostsAreSortedByFailuresThenMedianDuration() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://clean.example.com/a", status: 200, duration: 500),
            request(url: "https://broken.example.com/a", status: 500, duration: 10),
        ])
        XCTAssertEqual(stats.hosts.map(\.id), ["broken.example.com", "clean.example.com"])
    }

    func testHostsWithEqualFailuresSortBySlowestMedian() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://quick.example.com/a", duration: 10),
            request(url: "https://slow.example.com/a", duration: 900),
        ])
        XCTAssertEqual(stats.hosts.map(\.id), ["slow.example.com", "quick.example.com"])
    }

    func testHostsTieBreakOnNameSoTheOrderIsStable() {
        let requests = ["c", "a", "b"].map { request(url: "https://\($0).example.com/x", duration: 100) }
        let stats = TrafficStatistics.compute(from: requests)
        XCTAssertEqual(stats.hosts.map(\.id), ["a.example.com", "b.example.com", "c.example.com"])
    }

    func testARequestWithNoHostIsLeftOutOfTheHostBreakdown() {
        let model = HTTPRequest()
        model.requestURL = "not a url"
        model.requestMethod = "GET"
        model.noResponse = false
        model.responseCode = 200
        model.requestDuration = 10
        let stats = TrafficStatistics.compute(from: [model])
        XCTAssertTrue(stats.hosts.isEmpty)
        XCTAssertEqual(stats.summary.requestCount, 1)
    }

    // MARK: Empty

    func testAnEmptyInputProducesAnEmptySummary() {
        let stats = TrafficStatistics.compute(from: [])
        XCTAssertEqual(stats.summary.requestCount, 0)
        XCTAssertTrue(stats.hosts.isEmpty)
        XCTAssertTrue(stats.endpoints.isEmpty)
        XCTAssertNil(stats.summary.medianDuration)
        XCTAssertEqual(stats.summary.bytesReceived, 0)
        XCTAssertNil(stats.summary.wallClockSpan)
    }

    func testTheEmptyValueMatchesComputingFromNothing() {
        XCTAssertEqual(TrafficStatistics.empty, TrafficStatistics.compute(from: []))
    }
}
