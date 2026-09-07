//
//  WaterfallDurationsTests.swift
//  ScytherTests
//

@testable import Scyther
import Foundation
import XCTest

/// Covers the statistics ``WaterfallDurations`` still owns once the points-per-second scale it
/// used to compute was retired: which durations in a series are legitimate measurements, and the
/// nearest-rank arithmetic that reads a percentile out of them.
///
/// This file used to be `WaterfallTimeScaleTests` and pinned the whole points-per-second rule —
/// the median-at-24pt target, the tenth-percentile tail floor, the 50,000pt ceiling and the ruler's
/// tick spacing. None of that exists to pin any more: ``WaterfallWindow`` computes its own scale
/// for whatever slice of the log is visible, and ``WaterfallWindowTests`` covers it.
final class WaterfallDurationsTests: XCTestCase {

    /// Builds a bar with the given shape.
    ///
    /// - Parameters:
    ///   - start: Seconds from the series origin to the bar starting.
    ///   - duration: How long the bar runs, in seconds.
    ///   - pending: Whether the request is still in flight.
    /// - Returns: The bar.
    private func entry(start: TimeInterval = 0,
                       duration: TimeInterval,
                       pending: Bool = false) -> WaterfallEntry {
        WaterfallEntry(
            id: UUID().uuidString,
            label: "GET /v1/users",
            start: start,
            duration: duration,
            isFailure: false,
            isPending: pending,
            isStubbed: false
        )
    }

    // MARK: - The sample a statistic is derived from

    /// A pending bar is stretched to the end of the series, so its "duration" describes the
    /// session rather than a round trip. Letting it into the sample would drag the median toward
    /// the span.
    func testPendingBarsAreLeftOutOfTheSample() {
        let series = WaterfallSeries(
            origin: Date(),
            span: 300,
            entries: [entry(duration: 0.1), entry(duration: 0.3), entry(duration: 299, pending: true)]
        )
        XCTAssertEqual(WaterfallDurations.measuredDurations(of: series), [0.1, 0.3])
    }

    /// A zero-length bar is not a measurement, and a caller that divided by it would divide by
    /// zero.
    func testZeroLengthBarsAreLeftOutOfTheSample() {
        let series = WaterfallSeries(
            origin: Date(),
            span: 1,
            entries: [entry(duration: 0), entry(duration: 0.5)]
        )
        XCTAssertEqual(WaterfallDurations.measuredDurations(of: series), [0.5])
    }

    // MARK: - The percentile

    /// The nearest-rank value: the lower of the two middles at an even count, exactly as
    /// ``TrafficStatistics`` reports its own median — see that type's tests for the rule this
    /// mirrors.
    func testPercentileIsTheNearestRankValue() {
        XCTAssertEqual(WaterfallDurations.percentile(0.5, of: [10, 20, 30]), 20,
                       "an odd count lands exactly on the middle value")
        XCTAssertEqual(WaterfallDurations.percentile(0.5, of: [10, 20, 30, 40]), 20,
                       "an even count takes the lower of the two middles")
        XCTAssertEqual(WaterfallDurations.percentile(0.1, of: Array(stride(from: 1.0, through: 10.0, by: 1))),
                       1, "the tenth percentile of ten ranked values is the first")
    }

    /// An empty sample has no rank to name.
    func testPercentileOfAnEmptySampleIsNil() {
        XCTAssertNil(WaterfallDurations.percentile(0.5, of: []))
    }
}
