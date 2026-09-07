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
/// The chart has two surfaces — the preview section on ``TrafficStatsView`` and the full-log page
/// behind its **See all** button — and the requirement they were built under is that they are the
/// *same chart*, not two charts that resemble each other. Anything a reader could compare across
/// the two lives here: the bar itself, the colours, what an outcome is called, how tall a row is
/// and how wide the axis runs. A second implementation would drift the first time either screen
/// was touched, and the drift would be invisible until someone compared a bar's length on one
/// against its length on the other.
///
/// The type holds no state and draws no chrome. It is the mark and the arithmetic behind it; each
/// surface still decides its own layout, because that is the only thing the two legitimately
/// disagree about — the section stacks a handful of bars in one `Chart`, the page gives each bar a
/// row of its own so it can be tapped.
///
/// ## Usage
/// ```swift
/// Chart(rows) { row in
///     WaterfallChartStyle.bar(id: row.id, entry: row.entry, upperBound: bound, plotWidth: width)
/// }
/// .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
/// .chartXScale(domain: 0...bound)
/// ```
enum WaterfallChartStyle {

    // MARK: - Geometry

    /// How thick each bar is drawn, in points.
    static let barThickness: CGFloat = 10

    /// The vertical space one row takes, in points, before Dynamic Type scales it.
    ///
    /// Fixed, and deliberately not "whatever divides the available height". Rows that shrink to
    /// fit turn a scrollable waterfall into a static one: twenty-two requests were squeezed onto a
    /// single screen, which made the full-log page indistinguishable from the preview it was
    /// opened from, and a thousand requests would have been a thousand hairlines. With a constant
    /// row height the stack's height is rows × this, and the `ScrollView` scrolls the moment that
    /// exceeds the screen — which is the entire point of the page.
    ///
    /// Forty-four points because the page's rows are tappable and that is the smallest comfortable
    /// hit target; the preview uses the same figure so a burst has the same visual density on both
    /// surfaces and a staircase reads at the same slope.
    static let rowHeight: CGFloat = 44

    /// How much wider than the longest bar the axis runs.
    ///
    /// The value label sits past the end of its bar, so the axis needs headroom or the longest
    /// bar's label falls outside the plot.
    private static let chartHeadroom = 1.35

    /// The narrowest axis the chart will draw, in seconds, so a session with no measured duration
    /// still has somewhere to put its bars.
    private static let minimumChartSpan = 0.05

    /// The narrowest a bar is ever *rendered*, in points.
    ///
    /// A width, not a duration, and that distinction is the whole point. Expressing this as a
    /// fraction of the axis — which is what it was — made the floor grow with the session: over a
    /// five minute span it inflated every bar to three and a quarter seconds, so a 5 ms request
    /// and a 3 s request drew identically and a floored bar could reach across a request it never
    /// ran alongside. That contradicts the one claim the chart makes.
    ///
    /// One point is the smallest mark that is still drawn, and it is below the resolution at which
    /// the chart could have shown a gap anyway: two bars whose real separation is under a point
    /// cannot be told apart whether or not the floor is applied, so the floor cannot invent an
    /// overlap a reader could otherwise have ruled out.
    static let minimumBarWidth: CGFloat = 1

    /// How wide the full-log page's leading label column is, in points.
    ///
    /// The page draws each bar in its own chart, so it cannot let Charts size a shared y axis for
    /// it: every row's axis would be sized to that row's own label and no two bars would start at
    /// the same x. A fixed column is what keeps the axis genuinely shared, which is the whole
    /// claim the chart makes — that bars which overlap were in flight together.
    static let labelColumnWidth: CGFloat = 132

    /// The gap between the label column and the plot, in points.
    static let labelColumnSpacing: CGFloat = 8

    /// The narrowest plot the page will draw, in points.
    ///
    /// A floor rather than a negative width in a split view or a very small window.
    static let minimumPlotWidth: CGFloat = 40

    /// How tall the page's legend is, in points, before Dynamic Type scales it.
    ///
    /// The legend is drawn by a chart of its own, at the card's full content width, rather than
    /// beside the ruler. Sharing the ruler's chart put it inside the label column's offset, where
    /// it had roughly a third less room than the preview gives it and wrapped "Stubbed" onto a
    /// second line.
    static let legendHeight: CGFloat = 24

    /// How tall the page's pinned ruler is, in points, before Dynamic Type scales it.
    ///
    /// Enough for the collapsed plot, the tick labels and the axis title. Fixed rather than
    /// measured because the header is pinned: a header that resized as the reader scrolled would
    /// shift every bar under it. Fixed is not the same as constant, though — both this and
    /// ``legendHeight`` are scaled by the view against the reader's text size, or the tick labels
    /// clip at the sizes where they most need to be legible.
    static let rulerHeight: CGFloat = 48

    // MARK: - The grouped card

    /// How far the card is inset from the edge of the page, in points.
    ///
    /// This and the two figures below are UIKit's inset-grouped metrics rather than invented
    /// ones. The full-log page is a `ScrollView` rather than a `List`, so nothing draws the card
    /// for it, and bars sitting on the plain page background read as a different component rather
    /// than as the same chart with more room.
    static let cardInset: CGFloat = 20

    /// The padding between the card's edge and its content, in points.
    static let cardContentPadding: CGFloat = 16

    /// The radius the card's outer corners are rounded to, in points.
    static let cardCornerRadius: CGFloat = 10

    /// How wide the plot is on the full-log page, for a page of the given width.
    ///
    /// The single source of the page's horizontal geometry. The pinned ruler and every row are
    /// framed to whatever this returns, so their plots are the same width *by construction*
    /// rather than by two matching stacks of hand-written insets — which is what the alignment
    /// between a tick and the bar beneath it rests on, and which nothing would have caught if the
    /// two had drifted.
    ///
    /// - Parameter pageWidth: The full width available to the page.
    /// - Returns: The plot width in points, never below ``minimumPlotWidth``.
    static func plotWidth(inPageWidth pageWidth: CGFloat) -> CGFloat {
        let chrome = 2 * cardInset + 2 * cardContentPadding + labelColumnWidth + labelColumnSpacing
        return max(minimumPlotWidth, pageWidth - chrome)
    }

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
    /// Used to seed the page's legend with one mark per outcome, so Charts draws the same legend
    /// there that it draws for the preview's chart.
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
    /// Only ever longer than the measurement, only when the measurement would render narrower
    /// than ``minimumBarWidth``, and only by enough to reach that width — so the inflation is
    /// bounded in points however long the session runs.
    ///
    /// A surface that does not know how wide its plot is passes zero and gets true lengths. That
    /// is the preview's actual contract rather than a fallback: Charts sizes the preview's leading
    /// axis to its own labels, so the section cannot state its plot width without measuring the
    /// chart it is about to build, and a floor computed from a guess would be a floor of unknown
    /// size — which is the exact defect this replaced.
    ///
    /// - Parameters:
    ///   - entry: The bar.
    ///   - upperBound: The axis' far end, in seconds.
    ///   - plotWidth: How wide the plot is, in points, or zero when the surface does not know.
    /// - Returns: The x value the bar is drawn to, in seconds.
    static func drawnEnd(of entry: WaterfallEntry, upperBound: Double, plotWidth: CGFloat) -> Double {
        guard plotWidth > 0, upperBound > 0 else { return entry.start + entry.duration }
        let secondsPerPoint = upperBound / Double(plotWidth)
        return entry.start + max(entry.duration, Double(minimumBarWidth) * secondsPerPoint)
    }

    /// The value label drawn at the end of one bar.
    ///
    /// In the same milliseconds-or-seconds form the summary uses, so a two millisecond bar reads
    /// as `2 ms` rather than rounding away to `0 s`. Built from ``WaterfallEntry/duration``, never
    /// from ``drawnEnd(of:upperBound:plotWidth:)``: the width is the legible figure, the label is
    /// the honest one.
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
    /// its label sits, how a floored bar behaves — lands on both at once.
    ///
    /// - Parameters:
    ///   - id: The bar's value on the chart's categorical y scale. The preview numbers its rows
    ///     to keep two calls to the same endpoint apart; the page gives each row its own chart,
    ///     where the value only has to exist.
    ///   - entry: The bar to draw.
    ///   - upperBound: The axis' far end, in seconds.
    ///   - plotWidth: How wide the plot is, in points, or zero for true lengths only.
    /// - Returns: The mark.
    @ChartContentBuilder
    static func bar(
        id: String,
        entry: WaterfallEntry,
        upperBound: Double,
        plotWidth: CGFloat
    ) -> some ChartContent {
        BarMark(
            xStart: .value(localized("Start"), entry.start),
            xEnd: .value(
                localized("End"),
                drawnEnd(of: entry, upperBound: upperBound, plotWidth: plotWidth)
            ),
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
