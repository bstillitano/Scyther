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
/// that "the caption and the zoom limit still need them." Neither did.
/// `WaterfallViewModel.windowCaption` is built from counts alone, and the zoom limit is built from
/// ``measuredDurations(of:)``'s shortest reading, not its median or its tail — so both fields, and
/// the nearest-rank `percentile(_:of:)` function they were the only production callers of, were
/// dead weight from the rename onward: every layout pass sorted the sample and ran the nearest-rank
/// arithmetic twice for figures nothing read. Both were removed. What survives is only the raw
/// measurement the window and the view model still need: the sorted, finished durations in a
/// series.
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
}
