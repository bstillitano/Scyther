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
/// Reached from the Waterfall section of ``TrafficStatsView`` two ways: the **See all** link opens
/// at the full span, and a tap on the section's own overview strip opens centred on the moment
/// touched — see ``init(logs:openingTime:)``. Either way it shows the same session that section's
/// strip already compresses — the same colours, the same outcome names, the same legend, the same
/// row height, all from ``WaterfallChartStyle`` — but with every request its own tappable row
/// leading to the capture behind it.
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
/// NavigationLink(isActive: $isActive) {
///     WaterfallView(logs: logs, openingTime: openingTime)
/// } label: { EmptyView() }
/// ```
struct WaterfallView: View {
    /// The network log this page is drawing. Its filtered array is the input, so the page follows
    /// the log's search and filter chips the way the rest of the stats screen does.
    @ObservedObject private var logs: NetworkLogsViewModel

    /// The page's own view model, which owns the laid-out log and the current time window.
    @StateObject private var viewModel: WaterfallViewModel

    /// The magnification the pinch gesture last reported, so each change applies only the delta
    /// since the previous callback rather than the whole gesture again.
    ///
    /// `MagnificationGesture` reports magnitude relative to where the pinch *started*, not to the
    /// last callback. Feeding that straight to ``WaterfallViewModel/zoom(by:)`` would reapply the
    /// entire pinch on every frame the gesture reports and slam the window into its zoom limit on
    /// the first frame of motion.
    ///
    /// `@GestureState` rather than `@State`: SwiftUI resets a gesture state back to its initial
    /// value whenever the gesture ends *or is cancelled*, which a plain `@State` variable reset
    /// only from `onEnded` does not get. A pinch the enclosing `List` claims mid-gesture never
    /// calls `onEnded`, and a `@State` left stranded at, say, `3` would make the *next* pinch's
    /// first callback compute `factor = 1/3` and snap the window before the user had moved a
    /// finger.
    @GestureState private var lastMagnification: CGFloat = 1

    /// Creates the page.
    ///
    /// `openingTime` is forwarded straight into
    /// ``WaterfallViewModel/init(requests:totalCount:openingTime:)`` rather than applied here
    /// afterwards, and that is not a stylistic choice: `_viewModel` is a `@StateObject`, whose
    /// `wrappedValue` is an `@autoclosure` SwiftUI evaluates lazily, exactly once, only when the
    /// view is actually inserted into the tree. Building the instance eagerly in this initialiser
    /// and calling `open(centredOn:)` on it afterwards — which is what an earlier version of this
    /// did — forces that autoclosure to run on *every* construction of a `WaterfallView` value,
    /// which for the hidden link and the **See all** link together is twice per body evaluation of
    /// the section that owns them, whether or not either page is ever pushed. The view model's own
    /// initialiser already lays the whole log out synchronously — see ``WaterfallViewModel``'s own
    /// documentation on why — so paying for that eagerly, twice, on a screen that merely offers the
    /// page rather than shows it, is the cost `@StateObject` exists to defer.
    ///
    /// - Parameters:
    ///   - logs: The network log view model whose filtered requests are drawn.
    ///   - openingTime: Seconds from the log's earliest request, when the page is reached by
    ///     tapping a moment on the Traffic Stats section's overview strip. The window opens
    ///     already centred there instead of at the full span, which is what `nil` — the **See
    ///     all** link's default — leaves it at.
    init(logs: NetworkLogsViewModel, openingTime: TimeInterval? = nil) {
        self.logs = logs
        _viewModel = StateObject(
            wrappedValue: WaterfallViewModel(
                requests: logs.requests,
                totalCount: logs.totalRequestCount,
                openingTime: openingTime
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
            if viewModel.window.canZoom {
                strip.accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: viewModel.zoom(by: 2)
                    case .decrement: viewModel.zoom(by: 0.5)
                    @unknown default: break
                    }
                }
            } else {
                strip
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

    /// The overview strip, carrying the current window and announcing it to VoiceOver.
    ///
    /// `.accessibilityValue` rather than baking the count into the label: the strip's label
    /// (``localized(_:)`` `"Traffic overview"`, set inside ``WaterfallOverviewStrip`` itself)
    /// names *what* the element is, and the value is what VoiceOver re-announces after every
    /// drag or adjustable-action change — without it, a VoiceOver user swiping to zoom hears
    /// "Traffic overview" again on every step and has no way to tell anything happened.
    ///
    /// Whether ``content`` also attaches `.accessibilityAdjustableAction` is decided by
    /// ``WaterfallViewModel/window``'s `canZoom`, not by this property: `canZoom`'s own
    /// documentation says the page disables the control rather than letting a pinch silently do
    /// nothing, and an adjustable action offered on an element that cannot act on it breaks that
    /// promise for VoiceOver the same way an un-disabled pinch would for a sighted reader.
    private var strip: some View {
        WaterfallOverviewStrip(series: viewModel.series,
                               window: viewModel.window,
                               height: WaterfallOverviewStrip.pageHeight,
                               interaction: .scrub { viewModel.scrub(to: $0) })
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .accessibilityValue(viewModel.windowCaption)
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
                            WaterfallDetailRow(row: row, window: viewModel.window,
                                               showsHost: viewModel.showsHost)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear { viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width)) }
            .onChange(of: proxy.size.width) { _ in
                viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width))
            }
            // `.subviews` rather than `.all` when zoom is impossible: it disables the pinch this
            // modifier adds while still letting the `List` recognise its own scroll and press
            // gestures, so a request the window cannot narrow any further does not also lose its
            // scroll. See `canZoom`'s own documentation on why the page disables the gesture
            // rather than letting a pinch silently do nothing.
            .gesture(magnification, including: viewModel.window.canZoom ? .all : .subviews)
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
    /// `MagnifyGesture` is iOS 17. Attached by ``detail`` with `including: .all` so the list keeps
    /// recognising its own scroll and press gestures simultaneously — a pinch and a scroll do not
    /// compete for the same fingers — and with `including: .subviews` once the window cannot
    /// narrow any further, which disables the pinch itself without disabling the list underneath
    /// it.
    ///
    /// Driven through `.updating($lastMagnification)` rather than `.onChanged`/`.onEnded`: see
    /// ``lastMagnification`` for why a plain `@State` reset only in `onEnded` is not safe here.
    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($lastMagnification) { value, state, _ in
                guard value.isFinite, value > 0, state > 0 else { return }
                viewModel.zoom(by: Double(value / state))
                state = value
            }
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
/// Everything a reader could compare against the preview — the thickness, the colour, the row
/// height and the duration label — still comes from ``WaterfallChartStyle``.
///
/// The bar conveys a request's length by width and its outcome by fill colour, neither of which
/// is anything to VoiceOver, so the row collapses itself into one accessibility element with a
/// composed label naming the host, the request, its outcome and its duration — see
/// ``accessibilityLabel``.
///
/// The visible host is conditional in a way the accessibility label is not: see ``showsHost`` and
/// ``label``.
private struct WaterfallDetailRow: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The current window, which is what the bar is placed and clipped against.
    let window: WaterfallWindow

    /// Whether the log holds more than one distinct host, from
    /// ``WaterfallViewModel/showsHost``. `false` hides the host entirely rather than drawing it
    /// dimmed: repeating the same host on every row of a single-host log is noise, and worse, it
    /// crowds out the path even when there is nothing for the host to distinguish.
    let showsHost: Bool

    /// The row's height, scaled against the reader's text size.
    ///
    /// Scaled rather than constant for the same reason the old page's rows were: the label beside
    /// the bar grows with Dynamic Type, and a constant height would clip it at exactly the sizes
    /// where it most needs to be legible.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = WaterfallChartStyle.rowHeight

    var body: some View {
        HStack(spacing: 8) {
            label

            GeometryReader { proxy in
                let rect = barRect(in: proxy.size)
                RoundedRectangle(cornerRadius: 3)
                    .fill(WaterfallChartStyle.colour(for: row.entry))
                    .frame(width: rect.width, height: WaterfallChartStyle.barThickness)
                    .offset(x: rect.minX, y: (proxy.size.height - WaterfallChartStyle.barThickness) / 2)
            }
            // `GeometryReader` does not clip its own content: a request in the window's last few
            // points still computes a rect flush to the trailing edge, and the minimum-width floor
            // below can push that rect's far edge past `size.width`. Without this the bar draws
            // over the duration column instead of stopping at the plot's edge.
            .clipped()

            Text(row.entry.isPending
                 ? "—" // scyther:unlocalised em dash for an unfinished request
                 : WaterfallChartStyle.valueLabel(for: row.entry))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: WaterfallChartStyle.detailDurationWidth, alignment: .trailing)
        }
        .frame(height: rowHeight)
        // The bar itself conveys length by width, which is nothing to a screen reader, so the
        // name, the outcome and the duration are spoken instead — the same composition the old
        // page's row used, and for the same reason: without it a request's outcome is carried
        // only by the rectangle's fill colour, which VoiceOver cannot read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The row's name column: the path alone, or the host stacked above the path when
    /// ``showsHost`` is true.
    ///
    /// Stacked, not side by side. Side by side was tried first — the host capped at a fixed
    /// width, the path taking what was left — and it read worse than not showing the host at
    /// all: the label column is 132pt, a capped host left roughly 60pt for the path, and a path
    /// like `GET /posts/1` needs more than that, so it was the *path* that ended up giving way
    /// per row. Because how much it gave way depended on how long that row's own host happened to
    /// be, different rows truncated the host to different widths, so the paths no longer started
    /// at a common x and the column stopped being scannable down. Widening the label column
    /// instead would have taken width from the plot, which the zoom limit is computed against.
    ///
    /// Stacking removes the contest rather than refereeing it: each line gets the column's full
    /// width, so nothing about one row's host affects where another row's path starts. It is also
    /// the same subtitle shape the rest of the menu already uses — Network Logs stacks method and
    /// status over the URL — so a two-line row here is a pattern the reader has already seen
    /// rather than a new one.
    @ViewBuilder
    private var label: some View {
        if showsHost {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.entry.shortHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Tail, because hosts differ near their front — `jsonplaceholder…` is still
                    // `jsonplaceholder`.
                    .truncationMode(.tail)
                Text(verbatim: row.entry.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    // Middle, not tail: a path's distinguishing content is usually at its *end* —
                    // a query value in `/comments?postId=1`, a resolution suffix in
                    // `/assets/logo@3x.png` — and tail truncation is exactly what cuts that off.
                    // Middle keeps a fragment of both ends.
                    .truncationMode(.middle)
            }
            .frame(width: WaterfallChartStyle.detailLabelWidth, alignment: .leading)
        } else {
            Text(verbatim: row.entry.label)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WaterfallChartStyle.detailLabelWidth, alignment: .leading)
        }
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
                      width: max(WaterfallChartStyle.minimumBarWidth, clippedEnd - clippedStart),
                      height: WaterfallChartStyle.barThickness)
    }

    /// What VoiceOver reads for the row.
    ///
    /// - Returns: The host and label, the outcome, and the duration (or an em dash for a request
    ///   still in flight), joined the way ``WaterfallEntry``'s own accessibility summaries are —
    ///   one sentence per part rather than reading the visible " · " punctuation aloud.
    private var accessibilityLabel: String {
        let name = row.entry.shortHost.isEmpty ? row.entry.label : "\(row.entry.shortHost) \(row.entry.label)"
        return [
            name,
            WaterfallChartStyle.outcomeTitle(for: row.entry),
            row.entry.isPending ? "—" : WaterfallChartStyle.valueLabel(for: row.entry), // scyther:unlocalised em dash for an unfinished request
        ].joined(separator: ", ") // scyther:unlocalised separator between localised parts
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
