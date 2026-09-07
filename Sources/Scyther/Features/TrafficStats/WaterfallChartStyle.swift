//
//  WaterfallChartStyle.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import CoreGraphics
import Foundation
import SwiftUI

/// The one place the waterfall is drawn from.
///
/// The chart has two surfaces: the compressed overview strip — `WaterfallOverviewStrip`, one
/// implementation used unchanged on both ``TrafficStatsView`` and the full-log page behind **See
/// all**, so there is nothing there for two copies to drift apart on — and the full-log page's own
/// detail list, which the strip has no equivalent of at all. What the two surfaces genuinely have
/// to agree on is which colour an outcome is drawn in, since colour is the one thing both of them
/// render; that lives here, in ``colour(forOutcome:)`` and ``colour(for:)``, so a failed request
/// cannot end up red on one and a slightly different red on the other.
///
/// The type holds no state and draws no chrome. Beyond that shared colour, everything else it
/// holds belongs to the full-log page's own detail list and legend — the row height, the bar
/// thickness, the label and duration column widths, and the outcome names its rows'
/// accessibility labels and its own legend speak. None of it has anything on the Traffic Stats
/// section to agree with, because that section draws the strip and nothing else.
///
/// The detail list draws its own bars rather than asking Charts for one: a log can hold thousands
/// of requests and a `Chart` per row was a rendering hazard for no gain, and the section's own
/// most-recent-seven `Chart` — the "preview" this file's documentation used to compare against —
/// is gone along with it; the section draws the overview strip and nothing else now. The strip
/// draws its own bars too, from a single `Canvas` pass, using the geometry in
/// ``WaterfallStripGeometry`` rather than anything declared here. The full-log page's legend is
/// still drawn by Charts, from ``styleScale``, so its marks can never name a colour its own bars
/// are not using — there is no second legend anywhere in the feature for it to stay in step with.
///
/// ## Usage
/// ```swift
/// RoundedRectangle(cornerRadius: 3)
///     .fill(WaterfallChartStyle.colour(for: entry))
///     .frame(width: rect.width, height: WaterfallChartStyle.barThickness)
/// Text(WaterfallChartStyle.valueLabel(for: entry))
/// ```
enum WaterfallChartStyle {

    // MARK: - Geometry

    /// How thick each bar is drawn, in points.
    static let barThickness: CGFloat = 10

    /// The vertical space one row takes, in points, before Dynamic Type scales it.
    ///
    /// Fixed, and deliberately not "whatever divides the available height". Rows that shrink to
    /// fit turn a scrollable waterfall into a static one: twenty-two requests were squeezed onto a
    /// single screen, which made the full-log page indistinguishable from the seven-row preview it
    /// was opened from — back when the Traffic Stats section drew a preview of its own rows rather
    /// than the overview strip it draws now — and a thousand requests would have been a thousand
    /// hairlines. With a constant row height the detail list's content height is rows × this, and
    /// the `List` scrolls the moment that exceeds the screen — which is the entire point of the
    /// page.
    ///
    /// Forty-four points because the page's rows are tappable and that is the smallest comfortable
    /// hit target. Nothing on the Traffic Stats section needs to match it any more: that section
    /// draws the overview strip, not rows.
    static let rowHeight: CGFloat = 44

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
    ///
    /// It matters far less than it did. The floor was load-bearing while the page squeezed the
    /// whole session into one screen and almost every bar reached it; against a scale derived from
    /// whatever slice of the log the current ``WaterfallWindow`` shows, almost nothing does.
    static let minimumBarWidth: CGFloat = 1

    /// The narrowest plot the page will draw, in points.
    ///
    /// A floor rather than a negative width in a split view or a very small window.
    static let minimumPlotWidth: CGFloat = 40

    /// How tall the page's legend is, in points, before Dynamic Type scales it.
    ///
    /// The legend is drawn by a chart of its own, at the page's full content width, so it gets
    /// its own line rather than sharing a row with anything else — which is what stopped
    /// "Stubbed" wrapping onto a second line the way it did when an earlier layout squeezed it
    /// beside the axis.
    static let legendHeight: CGFloat = 24

    // MARK: - The detail row

    /// The detail list row's label column, in points.
    ///
    /// Fixed for the same reason the page's rows used to freeze a label column: a column sized to
    /// each row's own text would start every bar at a different x and undercut the one claim the
    /// chart makes, that bars sharing a moment on the window were genuinely in flight together.
    static let detailLabelWidth: CGFloat = 132

    /// The detail list row's duration column, in points. Sized for "1.25 s" plus a little, which
    /// is what the row's fixed-width label column left for the figure beside it.
    static let detailDurationWidth: CGFloat = 62

    /// The padding between the page's edge and its content, in points.
    ///
    /// Matches UIKit's inset-grouped content margin, which is what the legend above the detail
    /// list is measured against so it reads as part of the same screen rather than a component
    /// dropped onto it.
    static let cardContentPadding: CGFloat = 16

    // MARK: - Colour

    /// The colour each outcome is drawn in, and the order the legend lists them in.
    ///
    /// Given as an explicit scale rather than left to Charts so that the legend shows all four
    /// outcomes whether or not the current log contains one of each — otherwise the legend
    /// changes shape as traffic arrives, growing and shrinking a mark at a time instead of
    /// standing still while the requests underneath it come and go.
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
    /// Used to seed the full-log page's own legend with one mark per outcome. The Traffic Stats
    /// section keeps no legend of its own to stay in step with it — it draws only the overview
    /// strip, which speaks an outcome through colour alone.
    static var outcomeTitles: [String] {
        [localized("Succeeded"), localized("Failed"), localized("Pending"), localized("Stubbed")]
    }

    /// The colour one outcome is drawn in.
    ///
    /// A second statement of ``styleScale``, which is unavoidable rather than careless:
    /// `KeyValuePairs` can only be written as a literal, so the scale cannot be looked up by key
    /// or built from an array without ceasing to be the thing Charts wants. The two are kept
    /// honest by a test that walks the scale and asks this for every entry — the full-log page
    /// fills its bars from here while the legend above them is still drawn by Charts from the
    /// scale, so a drift between them would show as a bar whose colour the legend does not
    /// explain.
    ///
    /// - Parameter title: An outcome name from ``outcomeTitle(for:)``.
    /// - Returns: The colour, defaulting to the success colour for anything unrecognised.
    static func colour(forOutcome title: String) -> Color {
        switch title {
        case localized("Failed"): return .red
        case localized("Pending"): return .orange
        case localized("Stubbed"): return .purple
        default: return .green
        }
    }

    /// The colour one bar is drawn in.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The colour its outcome is shown in.
    static func colour(for entry: WaterfallEntry) -> Color {
        colour(forOutcome: outcomeTitle(for: entry))
    }

    /// The tint filling the overview strip's current window.
    ///
    /// Low alpha on the success colour: the window is a frame around what you are reading, not a
    /// status, so it must not read as one of the four states the bars use.
    static let windowTint = Color.green.opacity(0.14)

    /// The rules on the window's left and right edges.
    static let windowEdge = Color.green.opacity(0.9)

    /// The strip's own ground, so the compressed bars have something to sit on.
    static let stripBackground = Color.primary.opacity(0.06)

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

    /// The value label drawn at the end of one bar.
    ///
    /// In the same milliseconds-or-seconds form the summary uses, so a two millisecond bar reads
    /// as `2 ms` rather than rounding away to `0 s`. Built from ``WaterfallEntry/duration``, never
    /// from whatever width a surface draws the bar at: the width is the legible figure, the label
    /// is the honest one.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The bar's real length as text.
    static func valueLabel(for entry: WaterfallEntry) -> String {
        DurationText.milliseconds(entry.duration * 1_000)
    }
}
