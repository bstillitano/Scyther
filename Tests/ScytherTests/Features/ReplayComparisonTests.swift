//
//  ReplayComparisonTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ReplayComparisonTests: XCTestCase {

    private func model(status: Int?, duration: Float?, size: Int?) -> HTTPRequest {
        let request = HTTPRequest()
        request.responseCode = status
        request.requestDuration = duration
        request.responseBodyLength = size
        request.noResponse = status == nil
        return request
    }

    func testIdenticalResponsesReportNoChange() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: 200, duration: 100, size: 500)
        )
        XCTAssertFalse(comparison.statusChanged)
        XCTAssertEqual(comparison.durationDeltaMilliseconds, 0)
        XCTAssertEqual(comparison.sizeDeltaBytes, 0)
    }

    func testAChangedStatusIsReported() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: 401, duration: 90, size: 40)
        )
        XCTAssertTrue(comparison.statusChanged)
        XCTAssertEqual(comparison.durationDeltaMilliseconds, -10)
        XCTAssertEqual(comparison.sizeDeltaBytes, -460)
    }

    func testASlowerLargerReplayReportsPositiveDeltas() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 90, size: 40),
            replay: model(status: 200, duration: 100, size: 500)
        )
        XCTAssertFalse(comparison.statusChanged)
        XCTAssertEqual(comparison.durationDeltaMilliseconds, 10)
        XCTAssertEqual(comparison.sizeDeltaBytes, 460)
    }

    func testAPendingReplayHasNoDeltas() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: nil, duration: nil, size: nil)
        )
        XCTAssertNil(comparison.durationDeltaMilliseconds)
        XCTAssertNil(comparison.sizeDeltaBytes)
        XCTAssertTrue(comparison.statusChanged, "no response is a change from a 200")
    }

    func testAnOriginalWithNoRecordedFiguresHasNoDeltas() {
        let comparison = ReplayComparison(
            original: model(status: nil, duration: nil, size: nil),
            replay: model(status: 200, duration: 100, size: 500)
        )
        XCTAssertNil(comparison.durationDeltaMilliseconds, "there is nothing to subtract from")
        XCTAssertNil(comparison.sizeDeltaBytes)
        XCTAssertTrue(comparison.statusChanged)
    }

    func testTwoRequestsThatBothFailedReportNoStatusChange() {
        let comparison = ReplayComparison(
            original: model(status: nil, duration: nil, size: nil),
            replay: model(status: nil, duration: nil, size: nil)
        )
        XCTAssertFalse(comparison.statusChanged, "two failures are the same outcome")
        XCTAssertNil(comparison.durationDeltaMilliseconds)
        XCTAssertNil(comparison.sizeDeltaBytes)
    }

    func testFractionalDurationsSubtractWithoutFloatDrift() throws {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 12.5, size: 0),
            replay: model(status: 200, duration: 37.25, size: 0)
        )
        XCTAssertEqual(try XCTUnwrap(comparison.durationDeltaMilliseconds), 24.75, accuracy: 0.0001)
    }
}
