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

    // Two tests used to live here: `testPercentileIsTheNearestRankValue`, asserting the
    // nearest-rank selection (the lower of the two middles at an even count; the first of ten at
    // the tenth percentile), and `testPercentileOfAnEmptySampleIsNil`, asserting an empty sample
    // names no rank. Both drove `WaterfallDurations.percentile(_:of:)`, which this file's own type
    // doc now explains was dead from the rename onward: `WaterfallViewModel` stopped reading a
    // median or a tail duration once `windowCaption` and the zoom limit turned out not to need
    // either, and nothing else in production ever called it. The nearest-rank rule itself is not
    // an orphaned guarantee — `TrafficStatistics` computes the same arithmetic for its own median
    // and 95th-percentile figures, independently, and `TrafficStatisticsTests` already pins it
    // there — so removing the function removed a second, unused implementation of a rule the
    // codebase still keeps exactly one owner for.
}
