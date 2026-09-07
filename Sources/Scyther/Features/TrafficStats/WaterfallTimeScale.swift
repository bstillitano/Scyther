//
//  WaterfallTimeScale.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import CoreGraphics
import Foundation

/// How many points of the full-log page one second of traffic is worth.
///
/// The page used to have no scale at all. It sized its axis to the session and its plot to the
/// screen, so the two together said "the whole log, whatever its length, fits in one screen
/// width" — which is a statement about the device, not about the traffic. Against the log this
/// type was written for that produced a ruler running past three hundred seconds over about a
/// hundred and ninety points, with every request on it between thirty-two milliseconds and one
/// and a half seconds. At 0.47 points per second every one of those bars asked for less than a
/// point of ink, every one was floored to the one point minimum, and a 32 ms request and a 1.4 s
/// request came out the same size. The chart could not show the one thing it exists to show.
///
/// A scale fixes that by refusing to fit. The seconds axis is drawn at whatever width the traffic
/// needs and the reader scrolls it, exactly as every waterfall a developer has used behaves.
///
/// ## The rule
///
/// Two demands, whichever is larger, then two clamps:
///
/// - **The typical request gets ``medianBarWidth``.** The median of the durations actually
///   present is what "an ordinary request in this log" means, so pinning it to a readable width
///   is what makes the page zoom rather than magnify: a log of 20 ms calls scales up until they
///   are legible, and a log of five second calls needs no more room than five second calls.
/// - **The fast tail gets ``tailBarWidth``.** The median alone is not enough. A log whose typical
///   request takes a second and a half but which still contains 32 ms calls would satisfy the
///   first demand at seventeen points per second and crush the fast ones back to a sliver — the
///   original defect, one rule further down. Taking the ``tailPercentile`` of the sample and
///   insisting it stays a few points wide is what keeps the fast end readable. A percentile
///   rather than the minimum, so one anomalously quick cache hit cannot set the scale for
///   everything else.
/// - **Never narrower than the room available.** A scale that fits the log into less than the
///   plot's own width would draw a chart floating in empty space, which is the mirror image of
///   the defect.
/// - **Never wider than ``maximumContentWidth``.** A pathological session — millisecond requests
///   spread across an hour — would otherwise ask for millions of points of scroll view. The
///   ceiling is the one place the page knowingly gives up detail, and it gives it up on the
///   session's length rather than on the individual bar.
///
/// The clamps are applied in that order, so the ceiling wins over both demands and the floor wins
/// over the ceiling; the floor can only bind on a session too short to fill the screen, where
/// there is no detail to lose.
///
/// ## Usage
/// ```swift
/// let scale = WaterfallTimeScale.make(for: series, visibleWidth: plotWidth)
/// scale.contentWidth              // how wide the scrollable timeline is
/// scale.x(atSeconds: entry.start) // where a bar begins
/// scale.width(of: entry)          // how wide it is drawn
/// ```
struct WaterfallTimeScale: Equatable, Sendable {

    // MARK: - The rule's constants

    /// How wide the log's median request is drawn, in points.
    ///
    /// Twenty-four, which is about the height of a line of body text: enough that two bars a
    /// factor of two apart are obviously different lengths rather than two similar smudges, and
    /// small enough that a log of ordinary requests still shows several seconds of context per
    /// screen.
    static let medianBarWidth: CGFloat = 24

    /// The narrowest the ``tailPercentile`` request is allowed to be drawn, in points.
    ///
    /// Three rather than one. One point is the floor at which a bar is *findable*
    /// (``WaterfallChartStyle/minimumBarWidth``); three is the width at which two bars either
    /// side of the tail can be told apart, which is what the reader is actually doing.
    static let tailBarWidth: CGFloat = 3

    /// Which end of the sample the tail demand is measured at.
    ///
    /// The tenth percentile. Lower would let a single outlier — one 2 ms response served from a
    /// cache — set the scale for the entire log; the median already covers the middle, so this
    /// only has to protect the genuinely fast end.
    static let tailPercentile: Double = 0.1

    /// The widest scrollable timeline the page will build, in points.
    ///
    /// Fifty thousand: about a hundred and twenty-five iPhone screens, and roughly eighteen
    /// metres of virtual paper. Generous, because horizontal scrolling is the point and a five
    /// minute session of fast requests legitimately needs tens of thousands of points; bounded,
    /// because without a ceiling a log of millisecond calls across an hour asks for millions and
    /// the scroll view becomes useless in a different way.
    static let maximumContentWidth: CGFloat = 50_000

    /// The closest two ruler ticks may be drawn, in points.
    ///
    /// Wide enough for a label like `120 s` plus air. The interval is chosen as the smallest
    /// round number of seconds that clears it, so the ruler stays legible at every scale rather
    /// than at the one it was designed against.
    static let minimumTickSpacing: CGFloat = 72

    // MARK: - The scale

    /// How many points one second is drawn as. Always finite and greater than zero.
    let pointsPerSecond: Double

    /// The far end of the seconds axis, in seconds.
    ///
    /// Taken from ``WaterfallChartStyle/upperBound(forSpan:)`` so the page and the preview agree
    /// about where the axis stops, and so the trailing duration label of the longest bar still
    /// has somewhere to sit.
    let upperBound: Double

    /// How wide the scrollable timeline is, in points: the axis at this scale, never narrower
    /// than the room the page has to draw it in.
    let contentWidth: CGFloat

    /// The seconds between two ruler ticks: a round number, chosen for this scale.
    let tickInterval: Double

    // MARK: - Building

    /// Builds the scale from the two figures the rule needs.
    ///
    /// Takes the percentiles rather than the series so the view model can compute them once per
    /// layout and the view can rebuild the scale on every geometry change for nothing — a
    /// `LazyVStack` asks its rows for content constantly, and sorting a thousand durations per
    /// frame is exactly the cost this page was built to avoid.
    ///
    /// - Parameters:
    ///   - medianDuration: The median measured duration, in seconds, or `nil` when nothing in the
    ///     log has finished.
    ///   - tailDuration: The ``tailPercentile`` measured duration, in seconds, or `nil` as above.
    ///   - span: The seconds the series covers.
    ///   - visibleWidth: How much room the plot has on screen, in points.
    /// - Returns: The scale.
    static func make(medianDuration: Double?,
                     tailDuration: Double?,
                     span: TimeInterval,
                     visibleWidth: CGFloat) -> WaterfallTimeScale {
        let upperBound = WaterfallChartStyle.upperBound(forSpan: span)
        let visible = max(WaterfallChartStyle.minimumPlotWidth, visibleWidth)
        let fitScale = Double(visible) / upperBound
        let ceilingScale = max(fitScale, Double(maximumContentWidth) / upperBound)

        var demanded = fitScale
        if let medianDuration, medianDuration > 0, medianDuration.isFinite {
            demanded = max(demanded, Double(medianBarWidth) / medianDuration)
        }
        if let tailDuration, tailDuration > 0, tailDuration.isFinite {
            demanded = max(demanded, Double(tailBarWidth) / tailDuration)
        }

        let pointsPerSecond = min(max(demanded, fitScale), ceilingScale)
        return WaterfallTimeScale(
            pointsPerSecond: pointsPerSecond,
            upperBound: upperBound,
            contentWidth: max(visible, CGFloat(upperBound * pointsPerSecond)),
            tickInterval: tickInterval(pointsPerSecond: pointsPerSecond)
        )
    }

    /// Builds the scale straight from a series.
    ///
    /// The convenient form, for callers that are not drawing a thousand rows — a test, or a
    /// one-off measurement. The page goes through ``make(medianDuration:tailDuration:span:visibleWidth:)``
    /// with figures it has already computed.
    ///
    /// - Parameters:
    ///   - series: The laid-out log.
    ///   - visibleWidth: How much room the plot has on screen, in points.
    /// - Returns: The scale.
    static func make(for series: WaterfallSeries, visibleWidth: CGFloat) -> WaterfallTimeScale {
        let durations = measuredDurations(of: series)
        return make(
            medianDuration: percentile(0.5, of: durations),
            tailDuration: percentile(tailPercentile, of: durations),
            span: series.span,
            visibleWidth: visibleWidth
        )
    }

    /// The durations the scale is allowed to be derived from, ascending.
    ///
    /// Pending bars are excluded and that exclusion is load-bearing: a request still in flight is
    /// drawn to the end of the series, so its "duration" measures how long the session has been
    /// running rather than how long a round trip took. Letting one into the sample would drag the
    /// median toward the span and undo the zoom the moment anything was outstanding. Zero-length
    /// bars go too — they are not measurements, and the rule divides by them.
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
    /// including the floating-point nudge, so the duration the scale is built around is one the
    /// summary above it would also name.
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

    /// The seconds between ruler ticks at a given scale.
    ///
    /// The smallest number of the form 1, 2 or 5 times a power of ten that draws its ticks at
    /// least ``minimumTickSpacing`` apart. Round numbers because a ruler reading `13.7 s`,
    /// `27.4 s` is arithmetic the reader has to do; the 1-2-5 sequence because those are the
    /// intervals a reader can subdivide by eye.
    ///
    /// - Parameter pointsPerSecond: The scale.
    /// - Returns: The interval in seconds, always greater than zero.
    static func tickInterval(pointsPerSecond: Double) -> Double {
        let target = Double(minimumTickSpacing) / pointsPerSecond
        guard target.isFinite, target > 0 else { return 1 }
        let magnitude = pow(10, log10(target).rounded(.down))
        for step in [1.0, 2.0, 5.0] where magnitude * step >= target {
            return magnitude * step
        }
        return magnitude * 10
    }

    // MARK: - Placing a bar

    /// Where a moment on the axis is drawn, in points from the start of the timeline.
    ///
    /// - Parameter seconds: Seconds from the series origin.
    /// - Returns: The offset in points.
    func x(atSeconds seconds: TimeInterval) -> CGFloat {
        CGFloat(seconds * pointsPerSecond)
    }

    /// How wide a length of time is drawn, in points.
    ///
    /// Floored at ``WaterfallChartStyle/minimumBarWidth`` so a request too short to draw is still
    /// findable. The floor survives the scale unchanged, and matters far less now: at a scale
    /// derived from the durations present, almost nothing reaches it.
    ///
    /// - Parameter seconds: The length of time.
    /// - Returns: The width in points, never below one point.
    func width(ofSeconds seconds: TimeInterval) -> CGFloat {
        max(WaterfallChartStyle.minimumBarWidth, CGFloat(seconds * pointsPerSecond))
    }

    /// How wide one bar is drawn, in points.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The width in points.
    func width(of entry: WaterfallEntry) -> CGFloat {
        width(ofSeconds: entry.duration)
    }

    // MARK: - The ruler

    /// How many ticks the ruler draws, counting the one at zero.
    var tickCount: Int {
        max(1, Int((upperBound / tickInterval).rounded(.down)) + 1)
    }

    /// The moment one tick marks.
    ///
    /// - Parameter index: The tick's position, counting from zero.
    /// - Returns: Seconds from the series origin.
    func seconds(ofTick index: Int) -> TimeInterval {
        Double(index) * tickInterval
    }
}
