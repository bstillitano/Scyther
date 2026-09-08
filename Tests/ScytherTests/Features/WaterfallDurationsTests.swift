//
//  WaterfallDurationsTests.swift
//  ScytherTests
//

@testable import Scyther
import Foundation
import XCTest

/// Covers the statistics ``WaterfallDurations`` still owns once the points-per-second scale it
/// used to compute was retired: which durations in a series are legitimate measurements.
///
/// This file used to be `WaterfallTimeScaleTests` and pinned the whole points-per-second rule —
/// the median-at-24pt target, the tenth-percentile tail floor, the 50,000pt ceiling and the ruler's
/// tick spacing. None of that exists to pin any more: ``WaterfallWindow`` computes its own scale
/// for whatever slice of the log is visible, and ``WaterfallWindowTests`` covers it. A nearest-rank
/// median lived here too for a while, `median(of:)`, and is gone the same way — see the removal
/// comment in this file's own "The median" section for why.
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

    // A test used to live here, `testPercentileIsTheNearestRankValue`, asserting the nearest-rank
    // selection (the lower of the two middles at an even count; the first of ten at the tenth
    // percentile) that `WaterfallDurations.percentile(_:of:)` computed, and
    // `testPercentileOfAnEmptySampleIsNil` alongside it. Both drove a function this file's own
    // type doc now explains was dead from the rename onward, and removed. `median(of:)` was its
    // replacement — narrower on purpose, since nothing in this file needed an arbitrary
    // percentile any more, only the one reading `WaterfallWindow.opening(...)` read.

    // MARK: - The median
    //
    // `median(of:)` and its four tests — `testMedianOfAnOddCountIsTheMiddleValue`,
    // `testMedianOfAnEvenCountIsTheLowerOfTheTwoMiddleValues`, `testMedianOfOneValueIsThatValue`,
    // `testMedianOfAnEmptySampleIsNil` — used to live here, pinning the nearest-rank rule
    // `WaterfallWindow.opening(span:narrowest:medianMeasured:plotWidth:)` read to size the page's
    // opening window against a "typical" request. That rule was replaced by a flat half-span
    // default with no per-request duration in it at all — see `WaterfallWindow.opening(span:narrowest:)`'s
    // own "Two rules before this one" — which left `median(of:)` with no caller anywhere in
    // production. Removed alongside it rather than kept as tested, uncalled code; see
    // `WaterfallDurations`' own type documentation, "The median came back, then left again," for
    // the full account.
}
