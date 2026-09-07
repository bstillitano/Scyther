//
//  WaterfallDurations.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// The statistics the full-log page reads its median, tail and zoom-limit figures from.
///
/// This used to be `WaterfallTimeScale`, a type that turned those statistics into a single
/// points-per-second scale for the whole session — the seconds axis was drawn at whatever width
/// the traffic needed, and the reader scrolled it. That scale is gone. ``WaterfallWindow`` now
/// computes its own scale for whatever slice of the log is currently visible, so nothing chooses
/// one scale for an entire series any more; a type still named for a scale it no longer computes
/// would be a trap for the next reader, so it was renamed with it.
///
/// What survives is only the raw measurement the window and the view model still need: the
/// sorted, finished durations in a series, and the nearest-rank arithmetic the view model reads
/// its median and fastest-tenth figures from before handing the shortest of them to
/// ``WaterfallWindow`` as the zoom limit's input.
///
/// A case-less enum rather than the struct this used to be: with no scale left to hold, there is
/// nothing to construct an instance of. Every member here is a pure function of the series or the
/// sample handed to it.
enum WaterfallDurations {

    /// Which end of the sample the view model's tail figure is measured at.
    ///
    /// The tenth percentile. Lower would let a single outlier — one 2 ms response served from a
    /// cache — stand in for the whole fast end of the log; the median already covers the middle,
    /// so this only has to protect the genuinely fast tail.
    static let tailPercentile: Double = 0.1

    /// The durations a caller is allowed to derive a statistic from, ascending.
    ///
    /// Pending bars are excluded and that exclusion is load-bearing: a request still in flight is
    /// drawn to the end of the series, so its "duration" measures how long the session has been
    /// running rather than how long a round trip took. Letting one into the sample would drag the
    /// median toward the span. Zero-length bars go too — they are not measurements, and a caller
    /// that divided by one would divide by zero.
    ///
    /// - Parameter series: The laid-out log.
    /// - Returns: The measured durations in seconds, ascending.
    static func measuredDurations(of series: WaterfallSeries) -> [Double] {
        series.entries
            .filter { !$0.isPending }
            .map(\.duration)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
    }

    /// The nearest-rank value at `percentile` of an ascending sample.
    ///
    /// The same nearest-rank arithmetic ``TrafficStatistics`` reports its median and 95th with,
    /// including the floating-point nudge, so a duration named here is one the summary above it
    /// would also name.
    ///
    /// - Parameters:
    ///   - percentile: The percentile as a fraction from 0 to 1.
    ///   - sorted: The sample, sorted ascending.
    /// - Returns: The value at that rank, or `nil` when the sample is empty.
    static func percentile(_ percentile: Double, of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let position = (percentile * Double(sorted.count) * 1e9).rounded() / 1e9
        let rank = min(sorted.count, max(1, Int(position.rounded(.up))))
        return sorted[rank - 1]
    }
}
