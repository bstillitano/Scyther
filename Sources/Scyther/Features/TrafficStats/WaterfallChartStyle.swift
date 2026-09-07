//
//  WaterfallChartStyle.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Charts
import CoreGraphics
import Foundation
import SwiftUI

/// The one place the waterfall is drawn from.
///
/// The chart has two surfaces — the section on ``TrafficStatsView`` and the full-log page behind
/// its **See all** button — and the requirement they were built under is that they are the *same
/// chart*, not two charts that resemble each other. Anything a reader could compare across the
/// two lives here: the bar itself, the colours, what an outcome is called, and how wide the axis
/// runs. A second implementation would drift the first time either screen was touched, and the
/// drift would be invisible until someone compared a bar's length on one against its length on
/// the other.
///
/// The type holds no state and draws no chrome. It is the mark and the arithmetic behind it; each
/// surface still decides its own layout, because that is the only thing the two legitimately
/// disagree about — the section stacks every bar in one `Chart`, the page gives each bar a row of
/// its own so it can be tapped.
///
/// ## Usage
/// ```swift
/// Chart(rows) { row in
///     WaterfallChartStyle.bar(id: row.id, entry: row.entry, upperBound: bound)
/// }
/// .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
/// .chartXScale(domain: 0...bound)
/// ```
enum WaterfallChartStyle {

    // MARK: - Geometry

    /// How thick each bar is drawn, in points, leaving a gap between neighbouring rows.
    static let barThickness: CGFloat = 10

    /// The vertical space one bar takes, in points.
    ///
    /// The page reuses the section's figure rather than picking its own, so a burst of requests
    /// has the same visual density on both screens and a staircase reads at the same slope.
    static let barHeight: CGFloat = 22

    /// How much wider than the longest bar the axis runs.
    ///
    /// The value label sits past the end of its bar, so the axis needs headroom or the longest
    /// bar's label falls outside the plot.
    private static let chartHeadroom = 1.35

    /// The narrowest axis the chart will draw, in seconds, so a session with no measured duration
    /// still has somewhere to put its bars.
    private static let minimumChartSpan = 0.05

    /// The narrowest a bar is ever drawn, as a fraction of the axis.
    ///
    /// A fraction rather than a duration because the floor exists for a reason that is about
    /// pixels, not about time: on the full-log page the axis can run over minutes, and there a
    /// sub-millisecond request is a bar far less than a point wide — in the data, invisible on
    /// screen, and impossible to tap. Roughly two points of a typical plot, which is enough to
    /// see and hit without misreading as a measurable duration.
    static let minimumBarFraction: Double = 0.008

    /// How wide the full-log page's leading label column is, in points.
    ///
    /// The page draws each bar in its own chart, so it cannot let Charts size a shared y axis for
    /// it: every row's axis would be sized to that row's own label and no two bars would start at
    /// the same x. A fixed column is what keeps the axis genuinely shared, which is the whole
    /// claim the chart makes — that bars which overlap were in flight together.
    static let labelColumnWidth: CGFloat = 132

    /// The gap between the label column and the plot, in points.
    static let labelColumnSpacing: CGFloat = 8

    /// How tall the page's pinned ruler is, in points.
    ///
    /// Enough for the legend, the collapsed plot, the tick labels and the axis title. Fixed
    /// rather than measured because the header is pinned: a header that resized as the reader
    /// scrolled would shift every bar under it.
    static let rulerHeight: CGFloat = 84

    // MARK: - Colour

    /// The colour each outcome is drawn in, and the order the legend lists them in.
    ///
    /// Given as an explicit scale rather than left to Charts so that the legend shows all four
    /// outcomes whether or not the current log contains one of each — otherwise the legend
    /// changes shape as traffic arrives, and the two surfaces show different legends for the same
    /// session.
    static var styleScale: KeyValuePairs<String, Color> {
        [
            localized("Succeeded"): Color.green,
            localized("Failed"): Color.red,
            localized("Pending"): Color.orange,
            localized("Stubbed"): Color.purple,
        ]
    }

    /// Every outcome name the chart can produce, in legend order.
    ///
    /// Used to seed the page's ruler with one mark per outcome, so Charts draws the same legend
    /// there that it draws for the section's chart.
    static var outcomeTitles: [String] {
        [localized("Succeeded"), localized("Failed"), localized("Pending"), localized("Stubbed")]
    }

    // MARK: - Semantics

    /// What one bar's outcome is called, which is also its key in ``styleScale``.
    ///
    /// A stub is named as one whatever its authored status code says, because the code was
    /// written rather than returned. Beyond that, ``WaterfallEntry/isPending`` and
    /// ``WaterfallEntry/isFailure`` are mutually exclusive, so the remaining order decides
    /// nothing — it reads failure first regardless, because when the two could both be set this
    /// test ran second and every failure in the log was drawn as pending.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The localised outcome name.
    static func outcomeTitle(for entry: WaterfallEntry) -> String {
        if entry.isStubbed { return localized("Stubbed") }
        if entry.isFailure { return localized("Failed") }
        return entry.isPending ? localized("Pending") : localized("Succeeded")
    }

    /// The far end of the chart's seconds axis for a series of the given span.
    ///
    /// Wider than the longest bar so the value label past its end stays inside the plot, and
    /// never zero, which would leave the axis with no extent to draw on.
    ///
    /// - Parameter span: The seconds the series covers.
    /// - Returns: The axis' upper bound in seconds.
    static func upperBound(forSpan span: TimeInterval) -> Double {
        max(span * chartHeadroom, minimumChartSpan)
    }

    /// Where one bar is *drawn* to, which is not always where it ended.
    ///
    /// Only ever longer than the measurement, and only when the measurement would otherwise be
    /// too narrow to see — see ``minimumBarFraction``. The bar's label still reports the real
    /// figure, so nothing the reader can read is inflated; what changes is only whether they can
    /// find the bar at all.
    ///
    /// - Parameters:
    ///   - entry: The bar.
    ///   - upperBound: The axis' far end, which is what the floor is a fraction of.
    /// - Returns: The x value the bar is drawn to, in seconds.
    static func drawnEnd(of entry: WaterfallEntry, upperBound: Double) -> Double {
        entry.start + max(entry.duration, upperBound * minimumBarFraction)
    }

    /// The value label drawn at the end of one bar.
    ///
    /// In the same milliseconds-or-seconds form the summary uses, so a two millisecond bar reads
    /// as `2 ms` rather than rounding away to `0 s`.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The bar's real length as text.
    static func valueLabel(for entry: WaterfallEntry) -> String {
        DurationText.milliseconds(entry.duration * 1_000)
    }

    // MARK: - The mark

    /// One request's bar, with its colour and its trailing duration label.
    ///
    /// Both surfaces build their marks from here, so a change to the bar — its thickness, where
    /// its label sits, how a widened bar behaves — lands on both at once.
    ///
    /// - Parameters:
    ///   - id: The bar's value on the chart's categorical y scale. The section numbers its rows
    ///     to keep two calls to the same endpoint apart; the page gives each row its own chart,
    ///     where the value only has to exist.
    ///   - entry: The bar to draw.
    ///   - upperBound: The axis' far end, used to floor the drawn width.
    /// - Returns: The mark.
    @ChartContentBuilder
    static func bar(id: String, entry: WaterfallEntry, upperBound: Double) -> some ChartContent {
        BarMark(
            xStart: .value(localized("Start"), entry.start),
            xEnd: .value(localized("End"), drawnEnd(of: entry, upperBound: upperBound)),
            y: .value(localized("Request"), id),
            height: .fixed(barThickness)
        )
        .foregroundStyle(by: .value(localized("Outcome"), outcomeTitle(for: entry)))
        .annotation(position: .trailing, alignment: .leading, spacing: 4) {
            Text(valueLabel(for: entry))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
    }
}
