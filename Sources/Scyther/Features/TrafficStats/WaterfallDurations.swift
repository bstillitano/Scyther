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
/// ## The median came back, then left again
///
/// The page used to open at the whole span unconditionally; on a real, hour-long log with traffic
/// clustered into two short bursts, that read as two hairlines either side of an hour of nothing,
/// with every bar floored to the same three points whether the request took 43ms or 1.06s. A
/// `median(of:)` function briefly lived here to fix that: `WaterfallWindow.opening(span:narrowest:medianMeasured:plotWidth:)`
/// opened the page anchored on the newest traffic, sized so a *typical* request rendered legibly,
/// where "typical" meant the median rather than the shortest reading — the shortest was already
/// spoken for as the zoom floor, and reusing it for the opening width too would have sized the
/// window for the fastest call in the log rather than the one a reader was actually likely to be
/// looking at.
///
/// That fixed the hour-long capture, but it also opened *too tight* on an ordinary log — a
/// 19-request session opened on `1 of 19`, because a window sized to make one median request
/// legible is a narrow window by construction, whatever else happens to fall inside it. The owner
/// asked for a page that opens on roughly half its traffic instead, and
/// ``WaterfallWindow/opening(span:narrowest:)`` now computes exactly that: half the span, with no
/// single request's duration entering the arithmetic at all. `median(of:)` has no remaining
/// caller under that rule and was removed a second time — see that function's own prior
/// documentation, and `WaterfallWindow.opening(span:narrowest:)`'s own "Two rules before this one"
/// for the fuller account of both the rule this replaced and the one before that. What survives
/// from every version of this file is still the one sample every rule has been taken from: the
/// sorted, finished durations in a series.
///
/// A case-less enum rather than the struct this used to be: with no scale left to hold, there is
/// nothing to construct an instance of. Every member here is a pure function of the series or the
/// sample handed to it.
enum WaterfallDurations {

    /// The durations a caller is allowed to derive a statistic from, ascending.
    ///
    /// Pending bars are excluded and that exclusion is load-bearing: a request still in flight is
    /// drawn to the end of the series, so its "duration" measures how long the session has been
    /// running rather than how long a round trip took. Letting one into the sample would drag any
    /// statistic taken from it toward the span. Zero-length bars go too — they are not
    /// measurements, and a caller that divided by one would divide by zero.
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

    // `median(of:)` used to live here, computing the nearest-rank median of an ascending sample
    // for `WaterfallWindow.opening(span:narrowest:medianMeasured:plotWidth:)` to size the page's
    // opening window against. That rule was replaced by a flat half-span default with no
    // per-request duration in it at all, which left this function with no caller — see this
    // type's own documentation, "The median came back, then left again," and
    // `WaterfallWindow.opening(span:narrowest:)`'s own history for the full account. Removed with
    // its four tests in `WaterfallDurationsTests` rather than left as untested, uncalled code.
}
