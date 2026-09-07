//
//  WaterfallDurations.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// The statistic the full-log page reads its zoom-limit figure from.
///
/// This used to be `WaterfallTimeScale`, a type that turned a series' median and tail durations
/// into a single points-per-second scale for the whole session — the seconds axis was drawn at
/// whatever width the traffic needed, and the reader scrolled it. That scale is gone.
/// ``WaterfallWindow`` now computes its own scale for whatever slice of the log is currently
/// visible, so nothing chooses one scale for an entire series any more; a type still named for a
/// scale it no longer computes would be a trap for the next reader, so it was renamed with it.
///
/// A median and a tenth-percentile figure did not survive the rename, despite one round claiming
/// they had to: `WaterfallViewModel.Layout` cached a `medianDuration` and a `tailDuration`
/// alongside ``measuredDurations(of:)``'s shortest reading, and a commit kept them on the grounds
/// that "the caption and the zoom limit still need them." Neither did at the time —
/// `WaterfallViewModel.windowCaption` was built from counts alone, and the zoom limit was built
/// from ``measuredDurations(of:)``'s shortest reading, not the median or the tail — so both
/// fields, and the nearest-rank `percentile(_:of:)` function they were the only production
/// callers of, were dead weight from the rename onward and were removed.
///
/// The median came back once something needed it again. The page used to open at the whole span
/// unconditionally; on a real, hour-long log with traffic clustered into two short bursts, that
/// read as two hairlines either side of an hour of nothing, with every bar floored to the same
/// three points whether the request took 43ms or 1.06s. ``WaterfallWindow/opening(span:narrowest:medianMeasured:plotWidth:)``
/// is the fix the owner asked for: the page now opens anchored on the newest traffic, sized so a
/// *typical* request renders legibly. "Typical" is the median, not the shortest — the shortest
/// reading already drives the zoom *floor*, and reusing it for the opening width too would size
/// the window for the fastest call in the log rather than the one a reader is actually likely to
/// be looking at. ``median(of:)`` supplies that second reading. What survives from before either
/// figure existed is still the one sample both are taken from: the sorted, finished durations in
/// a series.
///
/// A case-less enum rather than the struct this used to be: with no scale left to hold, there is
/// nothing to construct an instance of. Every member here is a pure function of the series or the
/// sample handed to it.
enum WaterfallDurations {

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

    /// The nearest-rank median of an ascending sample, or `nil` when it is empty.
    ///
    /// `WaterfallWindow.opening(span:narrowest:medianMeasured:plotWidth:)` reads this to size the
    /// window the page opens with. `TrafficStatistics` computes a nearest-rank median too,
    /// independently, for its own session-summary figures — that duplication was accepted rather
    /// than resolved by sharing one function: `TrafficStatistics`'s `percentile(_:of:)` is
    /// `private` to a type answering a different question (aggregate statistics for a whole
    /// session, not one window's geometry), and extracting a third, shared type for this single
    /// caller was not worth the coupling. What this function must not do is drift from the rule
    /// itself while the two stay separate: both pick the sample at
    /// `⌈0.5 × count⌉` of an ascending sample — the same nudge-before-rounding-up shape
    /// `TrafficStatistics.percentile(_:of:)` uses and documents, for the same reason: `0.5 * 19`
    /// can land a fraction below or above `9.5` in binary depending on `count`, and a naive round
    /// could silently pick the wrong one of the two middle values.
    ///
    /// - Parameter durations: An ascending sample, such as ``measuredDurations(of:)``'s result.
    /// - Returns: The nearest-rank median, or `nil` for an empty sample.
    static func median(of durations: [Double]) -> Double? {
        guard !durations.isEmpty else { return nil }
        let position = (0.5 * Double(durations.count) * 1e9).rounded() / 1e9
        let rank = min(durations.count, max(1, Int(position.rounded(.up))))
        return durations[rank - 1]
    }
}
