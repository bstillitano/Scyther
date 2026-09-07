//
//  WaterfallView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Charts
import SwiftUI

/// Every logged request as a bar on one shared time axis, oldest at the top, seen through a
/// window the reader zooms and drags rather than scrolls.
///
/// Reached from the **See all** button in the Waterfall section of ``TrafficStatsView``. It shows
/// the same session that section previews — the same colours, the same outcome names, the same
/// legend, the same row height, all from ``WaterfallChartStyle`` — over the whole log rather than
/// the most recent seven, and made tappable so a bar leads to the request behind it.
///
/// ## Why a window rather than a scroll
///
/// The page used to fit the session into one screen width and only scroll vertically, then — when
/// that made every bar in a long session collapse to the same one-point floor — grew a plot tens
/// of thousands of points wide with a frozen label column and a ruler pinned inside a two-axis
/// `ScrollView`, the way Chrome's network panel and Charles both behave. Both of those are a
/// *scroll* answer to what is really a *zoom* problem: a reader does not want to pan across five
/// minutes of quiet network to find the one burst that mattered, and a plot wide enough to give a
/// twenty-millisecond request room next to a three-second one is wide enough that panning it by
/// hand is its own chore.
///
/// So the page shows two things instead. ``WaterfallOverviewStrip`` compresses the *entire* log
/// into one short band and marks the current window on it — a drag on the strip moves the window
/// anywhere in the log in one gesture, which no amount of panning a wide plot could do. Beneath
/// it, the detail list holds only the requests that window contains: a `List` of `NavigationLink`
/// rows rather than a `LazyVStack` of hand-laid-out rectangles, because this is a menu screen and
/// a bar without a row to sit in cannot happen — see ``WaterfallViewModel/visibleRows``. Zoom
/// narrows the window with a pinch, described below.
///
/// - Important: `.accessibilityAdjustableAction` on the strip is what keeps zoom reachable without
///   a pinch. VoiceOver and Switch Control users get the same range a sighted reader's fingers do;
///   the toolkit does not get to ship an accessibility audit feature one release and a
///   gesture-only control the next.
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

    /// The page's own view model, which owns the laid-out log and the current time window.
    @StateObject private var viewModel: WaterfallViewModel

    /// The last magnification the pinch gesture reported, so each change applies only the delta
    /// since the previous callback rather than the whole gesture again.
    ///
    /// `MagnificationGesture` reports magnitude relative to where the pinch *started*, not to the
    /// last callback. Feeding that straight to ``WaterfallViewModel/zoom(by:)`` would reapply the
    /// entire pinch on every frame the gesture reports and slam the window into its zoom limit on
    /// the first frame of motion.
    @State private var lastMagnification: CGFloat = 1

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
                content
            }
        }
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

    /// The page's body once the log holds something: the legend, the overview strip carrying the
    /// current window, the detail list the window holds, and the caption under it.
    ///
    /// A plain `VStack` rather than a `List` at the top level, because the strip needs a
    /// continuous drag — see ``WaterfallOverviewStrip/Interaction/scrub(_:)`` — which only works
    /// honestly outside a scroll view. The detail list underneath is its own `List`, so it still
    /// gets a menu screen's row treatment without the strip losing its gesture to one.
    private var content: some View {
        VStack(spacing: 0) {
            legend
            WaterfallOverviewStrip(series: viewModel.series,
                                   window: viewModel.window,
                                   height: WaterfallOverviewStrip.pageHeight,
                                   interaction: .scrub { viewModel.scrub(to: $0) })
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: viewModel.zoom(by: 2)
                    case .decrement: viewModel.zoom(by: 0.5)
                    @unknown default: break
                    }
                }
            detail
            Text(viewModel.windowCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    /// The colour legend, unchanged from the page's original design: four marks in one line,
    /// still drawn by a `Chart` of its own so it stays pixel-for-pixel the legend the preview
    /// section already draws. See ``WaterfallLegendView``.
    private var legend: some View {
        WaterfallLegendView()
            .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
            .padding(.top, 8)
    }

    /// The rows the window holds.
    ///
    /// A `List` rather than a `LazyVStack` in a `ScrollView`: rows are `NavigationLink`s and this
    /// is a menu screen, so it takes the menu's row treatment, separators and press states for
    /// free rather than hand-rolling them.
    @ViewBuilder
    private var detail: some View {
        GeometryReader { proxy in
            List {
                if viewModel.isWindowEmpty {
                    Text(localized("No requests in this part of the log."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleRows) { row in
                        NavigationLink {
                            LogDetailsView(httpRequest: row.request)
                        } label: {
                            WaterfallDetailRow(row: row, window: viewModel.window)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear { viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width)) }
            .onChange(of: proxy.size.width) { _ in
                viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width))
            }
            .gesture(magnification, including: .all)
        }
    }

    /// The width a bar actually gets, which is the row less the label and duration columns.
    ///
    /// The zoom limit is computed from this rather than from the screen's width, so the shortest
    /// request really is 24pt at maximum zoom instead of 24pt-minus-the-chrome. The trailing `48`
    /// is the row's own overhead that ``WaterfallChartStyle/detailLabelWidth`` and
    /// ``WaterfallChartStyle/detailDurationWidth`` do not already account for: the two 8pt gaps
    /// ``WaterfallDetailRow``'s `HStack` puts between its three columns, plus the 16pt leading and
    /// trailing insets a plain `List` gives every row.
    ///
    /// - Parameter rowWidth: The full width one row is given, from the list's own geometry.
    /// - Returns: The width left for the bar, never below ``WaterfallChartStyle/minimumPlotWidth``.
    private func plotWidth(in rowWidth: CGFloat) -> CGFloat {
        max(WaterfallChartStyle.minimumPlotWidth,
            rowWidth - WaterfallChartStyle.detailLabelWidth - WaterfallChartStyle.detailDurationWidth - 48)
    }

    /// Pinch to zoom, running alongside the list's scrolling rather than instead of it.
    ///
    /// `MagnificationGesture` and not `MagnifyGesture`: the package's floor is iOS 16 and
    /// `MagnifyGesture` is iOS 17. Attached with `including: .all` so the list keeps recognising
    /// its own scroll and press gestures simultaneously — a pinch and a scroll do not compete for
    /// the same fingers.
    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value.isFinite, value > 0, lastMagnification > 0 else { return }
                viewModel.zoom(by: Double(value / lastMagnification))
                lastMagnification = value
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    /// The placeholder shown for a log with nothing in it at all.
    ///
    /// Distinct from ``WaterfallViewModel/isWindowEmpty``, which the detail list answers with its
    /// own row: this is the whole log holding nothing to draw a strip or a window over in the
    /// first place.
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

/// One request in the waterfall's detail list: who it went to, what it was, when it happened
/// inside the window, and how long it took.
///
/// Its own small view rather than a case inside ``WaterfallView``, since it exists only for this
/// list. The bar is a filled rectangle rather than a `Chart`, for the same reason the old page's
/// rows were: a `BarMark` with both axes and the legend hidden *is* a filled rectangle, and asking
/// Charts to lay one out per row buys nothing a `RoundedRectangle` does not already give for free.
/// Everything a reader could compare against the preview — the colour and the row height — still
/// comes from ``WaterfallChartStyle``.
private struct WaterfallDetailRow: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The current window, which is what the bar is placed and clipped against.
    let window: WaterfallWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(row.entry.shortHost) · \(row.entry.label)")
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WaterfallChartStyle.detailLabelWidth, alignment: .leading)

            GeometryReader { proxy in
                let rect = barRect(in: proxy.size)
                RoundedRectangle(cornerRadius: 3)
                    .fill(WaterfallChartStyle.colour(for: row.entry))
                    .frame(width: rect.width, height: 10)
                    .offset(x: rect.minX, y: (proxy.size.height - 10) / 2)
            }

            Text(row.entry.isPending
                 ? "—" // scyther:unlocalised em dash for an unfinished request
                 : DurationText.seconds(row.entry.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: WaterfallChartStyle.detailDurationWidth, alignment: .trailing)
        }
        .frame(height: 44)
    }

    /// The bar's position inside the window, clipped at both edges.
    ///
    /// Clipping rather than shrinking: a request that outlives the window is drawn flush to the
    /// edge, so the clip reads as "continues" instead of as a shorter request than it was.
    ///
    /// - Parameter size: The plot's measured size, from the row's own `GeometryReader`.
    /// - Returns: The rect to fill, always inside `size`.
    private func barRect(in size: CGSize) -> CGRect {
        guard window.duration > 0, size.width > 0 else { return .zero }
        let scale = size.width / CGFloat(window.duration)
        let rawStart = CGFloat(row.entry.start - window.start) * scale
        let rawEnd = CGFloat(row.entry.start + row.entry.duration - window.start) * scale
        let clippedStart = min(max(0, rawStart), size.width)
        let clippedEnd = min(max(0, rawEnd), size.width)
        return CGRect(x: clippedStart,
                      y: 0,
                      width: max(3, clippedEnd - clippedStart),
                      height: 10)
    }
}

/// What each colour means, at the page's full content width.
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
