//
//  WaterfallView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Charts
import SwiftUI
import UIKit

/// Every logged request as a bar on one shared, scrollable time axis, oldest at the top.
///
/// Reached from the **See all** button in the Waterfall section of ``TrafficStatsView``. It shows
/// the same session that section previews — the same colours, the same outcome names, the same
/// legend, the same row height, all from ``WaterfallChartStyle`` — over the whole log rather than
/// the most recent seven, and made tappable so a bar leads to the request behind it.
///
/// ## Why it scrolls in both directions
///
/// The page used to fit the session into one screen width and only scroll vertically. That is
/// fine for a log whose requests are all roughly as long as each other and terrible for every
/// other log: against a three hundred second session of requests between thirty-two milliseconds
/// and one and a half seconds, every bar asked for less than a point of ink, every bar was floored
/// to the one point minimum, and the fastest and the slowest request in the log drew the same
/// size. A ruler running to 300 s over 190 points is a statement about the phone, not about the
/// traffic.
///
/// So the axis is drawn at a scale derived from the durations present — see
/// ``WaterfallTimeScale`` — and the reader scrolls it. Four things follow from that, and all four
/// are load-bearing:
///
/// - **The rows are lazy.** A log holding thousands of captures only ever builds the handful of
///   rows on screen, and each row is a rectangle and two labels rather than a `Chart`, because a
///   chart per row at tens of thousands of points wide is a rendering hazard for no gain.
/// - **The ruler is a pinned section header inside the same scroll view as the bars.** Pinned, so
///   the axis never scrolls out of reach vertically; inside the same scroll view, so it moves
///   horizontally with the bars in the same frame rather than a frame later. A tick that does not
///   sit above its bar is worse than no ruler.
/// - **The label column is frozen.** Names hold the leading edge while the timeline slides
///   underneath them, the way Chrome's network panel and Charles both behave. Reading a bar
///   against the request that produced it is the one task the page has.
/// - **The card is a container rather than an assembly.** It used to be built out of its ends —
///   the pinned header rounding the top corners, the last row the bottom — so that a lazily built
///   stack still read as one block. With the scroll view living *inside* the card that is no
///   longer needed: the card is one rounded rectangle and the timeline scrolls within it.
///
/// ## Usage
/// ```swift
/// NavigationLink(localized("See all")) {
///     WaterfallView(logs: logs)
/// }
/// ```
struct WaterfallView: View {
    /// The network log this page is drawing. Its filtered array is the input, so the page follows
    /// the log's search and filter chips the way the rest of the stats screen does.
    @ObservedObject private var logs: NetworkLogsViewModel

    /// The page's own view model.
    @StateObject private var viewModel: WaterfallViewModel

    /// Creates the page.
    ///
    /// - Parameter logs: The network log view model whose filtered requests are drawn.
    init(logs: NetworkLogsViewModel) {
        self.logs = logs
        _viewModel = StateObject(
            wrappedValue: WaterfallViewModel(
                requests: logs.requests,
                totalCount: logs.totalRequestCount
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        // The ground the card sits on, which is what a grouped List paints behind its sections.
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(localized("Waterfall"))
        .navigationBarTitleDisplayMode(.inline)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        // The array itself, not a count derived from it. Watching counts meant a request that
        // *completed* moved nothing the page was looking at, so its bar stayed orange and
        // stretched to a stale "now" until unrelated traffic happened to arrive — on a page whose
        // whole subject is when things started and finished.
        .onReceive(logs.$requests) { requests in
            viewModel.update(requests: requests, totalCount: logs.totalRequestCount)
        }
    }

    /// The card, and the caption underneath it.
    ///
    /// Wrapped in a `GeometryReader` because the page's scale needs to know how much of the
    /// timeline shows at once: that is the lower bound on the scale, so that a session too short
    /// to need scrolling still fills the card rather than huddling at its leading edge.
    private var timeline: some View {
        GeometryReader { geometry in
            let scale = viewModel.scale(
                visibleWidth: WaterfallChartStyle.plotWidth(inPageWidth: geometry.size.width)
            )
            VStack(alignment: .leading, spacing: 0) {
                card(scale: scale)
                Text(viewModel.caption)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    // Aligned with the card's content rather than its edge, the way a grouped
                    // List aligns a section footer.
                    .padding(
                        .horizontal,
                        WaterfallChartStyle.cardInset + WaterfallChartStyle.cardContentPadding
                    )
                    .padding(.vertical, 12)
            }
        }
    }

    /// The legend, and the scrollable timeline under it, in an inset grouped card.
    ///
    /// The legend sits outside the scroll view rather than above the ruler inside it: it explains
    /// four colours and has nothing to do with time, so scrolling it sideways with the axis would
    /// be nonsense. Outside, it also gets the card's full content width, which is what stops
    /// "Stubbed" wrapping onto a second line the way it did when it shared the ruler's row.
    ///
    /// - Parameter scale: The page's time scale.
    /// - Returns: The card.
    private func card(scale: WaterfallTimeScale) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WaterfallLegendView()
                .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
                .padding(.top, 8)
            WaterfallTimelineView(rows: viewModel.rows, scale: scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WaterfallChartStyle.cardCornerRadius,
                                    style: .continuous))
        .padding(.horizontal, WaterfallChartStyle.cardInset)
        .padding(.top, 8)
    }

    /// The placeholder shown for a log with nothing in it.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Traffic Captured"),
                systemImage: "chart.bar.xaxis",
                description: Text(
                    localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Traffic Captured"))
                    .font(.headline)
                Text(localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// The scrollable part of the page: the ruler, pinned, over one lazily built row per request.
///
/// One scroll view carrying both axes, which is the whole trick. The ruler is a pinned section
/// header inside it, so it holds the top of the card vertically while travelling horizontally
/// with the bars — in the same layout pass, not a frame behind, which is what any solution built
/// out of two scroll views and a published offset would give. The frozen label column is the
/// mirror image: it lives inside each row and inside the header, and counter-offsets itself by
/// the row's own position in the scroll view's coordinate space.
private struct WaterfallTimelineView: View {
    /// The rows to draw, oldest first.
    let rows: [WaterfallViewModel.Row]

    /// The page's time scale.
    let scale: WaterfallTimeScale

    /// The coordinate space the frozen column measures itself against.
    ///
    /// Named on the scroll view, so a row's `minX` in this space is zero at rest and negative
    /// once the timeline has been scrolled — which is exactly the figure
    /// ``WaterfallChartStyle/frozenColumnOffset(leadingEdge:)`` takes.
    private static let coordinateSpace = "ScytherWaterfallTimeline"

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        NavigationLink {
                            LogDetailsView(httpRequest: row.request)
                        } label: {
                            WaterfallRowView(
                                row: row,
                                scale: scale,
                                coordinateSpace: Self.coordinateSpace
                            )
                        }
                        // Plain, because the row is a chart: the automatic link style would tint
                        // the bar's label and its duration in the accent colour, and the two
                        // surfaces would no longer look like the same chart.
                        .buttonStyle(.plain)
                    }
                } header: {
                    WaterfallRulerView(scale: scale, coordinateSpace: Self.coordinateSpace)
                }
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        // Outside the scroll view, not inside its content: an inset applied to the content would
        // travel with it, and the frozen column would slide from the card's content margin to its
        // bare edge the moment the reader scrolled.
        .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
    }
}

/// One request's row on the full-log waterfall: its name, frozen at the leading edge, and its bar
/// somewhere along a timeline far wider than the screen.
///
/// The bar is a filled rectangle rather than a `Chart`, and that is a deliberate step away from
/// the preview. A `BarMark` with both axes and the legend hidden *is* a filled rectangle with a
/// caption beside it, and asking Charts to lay one out inside a plot tens of thousands of points
/// wide, once per row, buys nothing for a real cost. Everything a reader could compare against the
/// preview — thickness, colour, the duration label and the four points of air before it — still
/// comes from ``WaterfallChartStyle``.
private struct WaterfallRowView: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The page's time scale, identical for every row and for the ruler above them.
    let scale: WaterfallTimeScale

    /// The scroll view's coordinate space, which the frozen column measures itself against.
    let coordinateSpace: String

    /// The row's height, scaled against the reader's text size.
    ///
    /// Scaled rather than constant because the label beside the bar grows with Dynamic Type; a
    /// constant height would clip it at exactly the sizes where it most needs to be legible.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = WaterfallChartStyle.rowHeight

    var body: some View {
        HStack(spacing: 0) {
            WaterfallFrozenLabel(
                text: row.label,
                height: rowHeight,
                coordinateSpace: coordinateSpace
            )
            track
        }
        .frame(
            width: WaterfallChartStyle.rowWidth(timelineWidth: scale.contentWidth),
            height: rowHeight,
            alignment: .leading
        )
        // The whole row is the target, not just the bar: a request drawn at the minimum width is
        // a point across and would otherwise be unhittable even though it is now visible.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The bar and its duration label, placed along the timeline.
    ///
    /// The clear rectangle underneath is what gives the track its width; the bar is offset into
    /// place rather than laid out with spacers, because an offset costs nothing and a leading
    /// spacer of thirty thousand points is a layout the stack has to solve on every pass.
    private var track: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: scale.contentWidth, height: 1)
            HStack(spacing: 4) {
                Rectangle()
                    .fill(WaterfallChartStyle.colour(for: row.entry))
                    .frame(
                        width: scale.width(of: row.entry),
                        height: WaterfallChartStyle.barThickness
                    )
                Text(WaterfallChartStyle.valueLabel(for: row.entry))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .fixedSize()
            }
            .offset(x: scale.x(atSeconds: row.entry.start))
        }
        .frame(width: scale.contentWidth, alignment: .leading)
    }

    /// What VoiceOver reads for the row.
    ///
    /// The bar itself conveys length by width, which is nothing to a screen reader, so the name,
    /// the outcome and the duration are spoken instead.
    private var accessibilityLabel: String {
        [
            row.label,
            WaterfallChartStyle.outcomeTitle(for: row.entry),
            WaterfallChartStyle.valueLabel(for: row.entry),
        ].joined(separator: ", ") // scyther:unlocalised separator between localised parts
    }
}

/// A block that holds the leading edge of the timeline while the bars scroll underneath it.
///
/// The freeze is one subtraction — see ``WaterfallChartStyle/frozenColumnOffset(leadingEdge:)`` —
/// applied to the block's own content from a `GeometryReader` wrapped around it. Because the
/// geometry and the offset are read and applied in the same layout pass, the column moves in the
/// same frame the bars do; an offset published through `@State` would arrive a frame late and the
/// names would slide and snap back under the reader's thumb.
///
/// The background is opaque and covers the gap to the plot as well, because bars pass beneath it:
/// a bar showing through the gap would read as a request that started at zero.
private struct WaterfallFrozenLabel: View {
    /// The name to draw, or `nil` for the ruler's corner, which is frozen but empty.
    var text: String?

    /// How tall the block is.
    let height: CGFloat

    /// The scroll view's coordinate space.
    let coordinateSpace: String

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(
                    width: WaterfallChartStyle.labelColumnWidth,
                    height: height,
                    alignment: .trailing
                )
                .padding(.trailing, WaterfallChartStyle.labelColumnSpacing)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(alignment: .trailing) {
                    // A hairline saying the column is a column: without it the frozen names read
                    // as bars that failed to move.
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.5)
                }
                .offset(
                    x: WaterfallChartStyle.frozenColumnOffset(
                        leadingEdge: proxy.frame(in: .named(coordinateSpace)).minX
                    )
                )
        }
        .frame(width: WaterfallChartStyle.frozenColumnWidth, height: height)
        // Above the track, so the bars pass behind the column rather than over it.
        .zIndex(1)
    }

    /// The name, or nothing.
    @ViewBuilder
    private var content: some View {
        if let text {
            Text(text)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.secondary)
        } else {
            Color.clear
        }
    }
}

/// The seconds ruler, pinned to the top of the card.
///
/// Drawn by hand rather than by Charts, for the same reason the rows are: a chart whose plot is
/// tens of thousands of points wide would be asked to choose its own tick interval across a span
/// it cannot see, and the ticks would stop lining up with the bars the moment it chose differently
/// from them. Here the interval comes from ``WaterfallTimeScale/tickInterval`` and every tick is
/// placed by the same arithmetic that places a bar, so a tick sits above its bar by construction.
///
/// The ticks are lazy: at the widest scale the page allows there are a few hundred of them, and
/// only the ones on screen are ever built.
private struct WaterfallRulerView: View {
    /// The page's time scale.
    let scale: WaterfallTimeScale

    /// The scroll view's coordinate space, which the frozen corner measures itself against.
    let coordinateSpace: String

    /// The ruler's height, scaled against the reader's text size.
    ///
    /// Fixed rather than measured because the header is pinned: a header that resized as the
    /// reader scrolled would shift every bar under it. Fixed is not the same as constant, though
    /// — a constant height clips the tick labels at the sizes where they most need to be legible.
    @ScaledMetric(relativeTo: .caption) private var rulerHeight: CGFloat = WaterfallChartStyle.rulerHeight

    var body: some View {
        HStack(spacing: 0) {
            WaterfallFrozenLabel(
                text: nil,
                height: rulerHeight,
                coordinateSpace: coordinateSpace
            )
            ticks
        }
        .frame(
            width: WaterfallChartStyle.rowWidth(timelineWidth: scale.contentWidth),
            height: rulerHeight,
            alignment: .leading
        )
        // Opaque and card-coloured, because the rows scroll underneath it and it is the top of
        // the same card they are in.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
    }

    /// One cell per tick, each as wide as the interval it covers.
    ///
    /// A cell rather than an absolute offset so the stack does the arithmetic once and the labels
    /// cannot collide: the interval was chosen to be at least
    /// ``WaterfallTimeScale/minimumTickSpacing`` wide, so a cell is always wide enough for its own
    /// label.
    private var ticks: some View {
        LazyHStack(alignment: .top, spacing: 0) {
            ForEach(0..<scale.tickCount, id: \.self) { index in
                let seconds = scale.seconds(ofTick: index)
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.5, height: 5)
                    Text(Self.label(forSeconds: seconds))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                        .fixedSize()
                }
                .frame(width: CGFloat(scale.tickInterval * scale.pointsPerSecond),
                       alignment: .leading)
            }
        }
        .frame(width: scale.contentWidth, height: rulerHeight, alignment: .topLeading)
        .padding(.top, 6)
    }

    /// What one tick is labelled.
    ///
    /// The same milliseconds-or-seconds form the bars use, so a ruler zoomed in far enough to tick
    /// every twenty milliseconds says `20 ms` rather than `0.02 s`. The origin is written as
    /// seconds whatever the interval, because `0 ms` reads as a measurement rather than as the
    /// start of the axis.
    ///
    /// - Parameter seconds: The moment the tick marks.
    /// - Returns: The label.
    private static func label(forSeconds seconds: TimeInterval) -> String {
        seconds <= 0 ? DurationText.seconds(0) : DurationText.milliseconds(seconds * 1_000)
    }
}

/// What each colour means, at the card's full content width.
///
/// Still a `Chart`, and deliberately: this is the one piece of the page that has to be laid out
/// exactly as the preview's legend is, and the surest way to guarantee that is to let Charts draw
/// both from the same ``WaterfallChartStyle/styleScale``. The zero-width marks exist only to give
/// Charts something to derive a legend from, and the plot they sit in is collapsed to a point.
private struct WaterfallLegendView: View {
    /// The legend's height, scaled against the reader's text size, because a constant height
    /// clips a wrapped legend at the sizes where it would actually wrap.
    @ScaledMetric(relativeTo: .caption) private var legendHeight: CGFloat = WaterfallChartStyle.legendHeight

    var body: some View {
        Chart(WaterfallChartStyle.outcomeTitles, id: \.self) { title in
            BarMark(
                xStart: .value(localized("Start"), 0),
                xEnd: .value(localized("End"), 0),
                y: .value(localized("Request"), title),
                height: .fixed(0)
            )
            .foregroundStyle(by: .value(localized("Outcome"), title))
        }
        .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, spacing: 0)
        .chartPlotStyle { plot in
            plot.frame(height: 1)
        }
        .frame(height: legendHeight)
    }
}
