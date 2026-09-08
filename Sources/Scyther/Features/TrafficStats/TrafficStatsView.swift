//
//  TrafficStatsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// What the captured traffic adds up to: what is slow, what is failing, and what overlapped.
///
/// Reached from the chart button on **Network Logs** rather than from its own menu row, because
/// the figures describe the list you are looking at. The log's search and filter chips narrow the
/// requests, and this screen follows them, so filtering to one host turns the summary into that
/// host's summary.
///
/// A response a request override synthesised never left the device. It is counted, and named as
/// stubbed, but it is left out of every latency and failure figure — see ``TrafficStatistics``.
///
/// ## Usage
/// ```swift
/// NavigationLink {
///     TrafficStatsView(logs: viewModel)
/// } label: {
///     Image(systemName: "chart.bar.xaxis")
/// }
/// ```
struct TrafficStatsView: View {
    /// The network log this screen is describing. Its filtered array is the input.
    @ObservedObject private var logs: NetworkLogsViewModel

    /// The screen's own view model.
    @StateObject private var viewModel: TrafficStatsViewModel

    /// The Waterfall section's own row label column, scaled against the reader's text size,
    /// before ``WaterfallDetailRowMetrics`` decides whether the row still has room to draw it at
    /// that width.
    ///
    /// The same `@ScaledMetric` ``WaterfallView`` declares for its own, much longer, detail list —
    /// see that type's own documentation for why the value is hoisted to the parent rather than
    /// left inside ``WaterfallDetailRow`` itself, and why that reasoning applies here identically:
    /// ``rowLayout(in:)`` needs the exact width ``WaterfallDetailRow`` draws its column at, and a
    /// `@ScaledMetric` resolves from the environment, so declaring it again here reads the same
    /// value ``WaterfallView``'s own property would, not a second, independently-drifting one.
    @ScaledMetric(relativeTo: .caption) private var scaledLabelWidth: CGFloat = WaterfallChartStyle.detailLabelWidth

    /// The Waterfall section's own row duration column, scaled the same way and for the same
    /// reason ``scaledLabelWidth`` is. See ``WaterfallChartStyle/detailDurationWidth``.
    @ScaledMetric(relativeTo: .caption) private var scaledDurationWidth: CGFloat = WaterfallChartStyle.detailDurationWidth

    /// Creates the screen.
    ///
    /// - Parameter logs: The network log view model whose filtered requests the figures cover.
    init(logs: NetworkLogsViewModel) {
        self.logs = logs
        _viewModel = StateObject(
            wrappedValue: TrafficStatsViewModel(requests: logs.requests, totalCount: logs.totalRequestCount)
        )
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                statistics
            }
        }
        .navigationTitle(localized("Traffic Stats"))
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onChange(of: logRevision) { _ in
            viewModel.update(requests: logs.requests, totalCount: logs.totalRequestCount)
        }
    }

    /// What the screen watches the log for: the filtered count and the unfiltered count together.
    ///
    /// Watching the filtered count alone meant that with a filter active — the case the screen's
    /// own empty state advertises — new traffic that the filter excludes moved nothing the screen
    /// was looking at, so the figures and the caption's "N of M" denominator never updated.
    private var logRevision: [Int] { [logs.requests.count, logs.totalRequestCount] }

    /// The figures, once there is traffic to describe.
    ///
    /// Wrapped in a `GeometryReader` now, unlike every other section on this screen, purely so
    /// ``waterfallSection(rowLayout:)`` can hand ``WaterfallDetailRow`` the same pre-computed
    /// column widths ``WaterfallView`` does — see ``rowLayout(in:)``. No pinch, no scrub, nothing
    /// else on this screen needs the measured width, so nothing else changes shape for it.
    private var statistics: some View {
        GeometryReader { proxy in
            let rowLayout = rowLayout(in: proxy.size.width)
            List {
                summarySection
                if !viewModel.recentLayout.rows.isEmpty {
                    waterfallSection(rowLayout: rowLayout)
                }
                if !viewModel.statistics.endpoints.isEmpty {
                    endpointSection
                }
                if !viewModel.statistics.hosts.isEmpty {
                    hostSection
                }
            }
        }
    }

    /// The session-wide figures, captioned with what they cover.
    @ViewBuilder
    private var summarySection: some View {
        let summary = viewModel.statistics.summary
        Section {
            LabeledContent(localized("Requests"), value: viewModel.requestCountText)
                .monospacedDigit()
            if summary.stubbedCount > 0 {
                LabeledContent(localized("Stubbed"), value: viewModel.stubbedCountText)
                    .monospacedDigit()
            }
            // Red once anything has failed. The count and the rate are the same fact, so they
            // carry the same colour; colouring one and not the other reads as an oversight.
            LabeledContent(localized("Failures")) {
                Text(viewModel.failureCountText)
                    .foregroundStyle(summary.failureCount > 0 ? Color.red : Color.secondary)
            }
            .monospacedDigit()
            if let failureRate = viewModel.failureRateText {
                LabeledContent(localized("Failure rate")) {
                    Text(failureRate)
                        .foregroundStyle(summary.failureCount > 0 ? Color.red : Color.secondary)
                }
                .monospacedDigit()
            }
            if summary.pendingCount > 0 {
                LabeledContent(localized("Pending"), value: viewModel.pendingCountText)
                    .monospacedDigit()
            }
            if viewModel.showsPercentiles {
                LabeledContent(localized("Median"), value: viewModel.durationText(summary.medianDuration))
                    .monospacedDigit()
                LabeledContent(localized("95th Percentile"), value: viewModel.durationText(summary.p95Duration))
                    .monospacedDigit()
            } else {
                LabeledContent(localized("Fastest"), value: viewModel.durationText(summary.fastestDuration))
                    .monospacedDigit()
                LabeledContent(localized("Slowest"), value: viewModel.durationText(summary.slowestDuration))
                    .monospacedDigit()
            }
            LabeledContent(localized("Bytes Received"), value: viewModel.bytesText)
                .monospacedDigit()
            if let elapsed = viewModel.elapsedText {
                LabeledContent(localized("Elapsed"), value: elapsed)
                    .monospacedDigit()
            }
        } header: {
            // Shown only when a filter is narrowing what the figures cover. Unfiltered, the
            // caption would read "N requests" directly above the first row of this very section,
            // `LabeledContent(localized("Requests"), value: ...)`, which already says the same
            // number — a header restating its own section's first row rather than naming
            // anything the rows do not. Filtered, "N of M requests" earns its place: it says
            // something the rows genuinely cannot, that a filter is active and how much of the
            // log it is excluding. A header that appears only sometimes reads as a bug unless the
            // reason is written down, so it is written down here — this also buys back a line at
            // accessibility text sizes, where a header's own vertical cost is not free.
            if viewModel.isFiltered {
                Text(viewModel.caption)
            }
        } footer: {
            if summary.stubbedCount > 0 {
                Text(localized("A stubbed response never left the device, so it is counted here but left out of every duration, failure and byte total."))
            } else if !viewModel.showsPercentiles {
                Text(localized("Percentiles need at least five completed requests to mean anything, so the raw durations are shown instead."))
            }
        }
    }

    /// The most recent ``TrafficStatsViewModel/recentWaterfallCount`` requests: a strip zoomed to
    /// just them, then the same requests again as real, tappable rows.
    ///
    /// ## What this used to be
    ///
    /// The section first stacked its own most-recent-seven bars into a `Chart` of its own; that
    /// chart went, replaced by ``WaterfallOverviewStrip`` drawing the *whole* log — the same
    /// overview the full-log page marks its current window on, drawn here with no window at all.
    /// That read fine at the traffic volumes it shipped against and unusable at ordinary ones: 25
    /// requests over 24 seconds compresses to 25 marks a few points wide apiece, which conveys
    /// rough shape and nothing else — precisely the failure this section exists to avoid, back
    /// under a different cause. The owner judged it unusable and asked for a small version of the
    /// full page instead. See the design spec's own "Traffic Stats" section and its Amendments for
    /// the fuller account of both reversals.
    ///
    /// ## What it is now
    ///
    /// `WaterfallOverviewStrip(series: viewModel.recentLayout.series, window: nil, …)` — the same
    /// view, still with no window, but now built from ``TrafficStatsViewModel/recentLayout``,
    /// whose own series is limited to the most recent few requests rather than every one of them.
    /// Read literally: the drawn *range* is those few, not the whole log with a subset merely
    /// marked on it. A marked-window reading was considered and rejected — it would still compress
    /// the entire log onto the strip's width first, which is the exact defect being fixed, and
    /// would only additionally highlight a sliver of it.
    ///
    /// Beneath the strip, ``ForEach(viewModel.recentLayout.rows)`` draws the same requests again as
    /// ``WaterfallDetailRow``, reused directly rather than rebuilt — see that type's own
    /// documentation for why its existing shape already fit this second caller with no changes of
    /// its own required. Each wraps a `NavigationLink` to `LogDetailsView`, exactly as the full
    /// page's own rows do — tappable through to the log entry, per the owner's own instruction.
    ///
    /// `window` for those rows is `WaterfallWindow(span: viewModel.recentLayout.series.span,
    /// narrowest: 0)` — the widest window that series can have, i.e. no zoom applied at all — built
    /// fresh here rather than reused from anywhere, because there is no `WaterfallViewModel` behind
    /// this screen to own one. `WaterfallDetailRow` only ever reads a `WaterfallWindow` to place and
    /// clip its bar against a span; it has no opinion about whether that value came from a
    /// zoomable page or, as here, a plain span with nothing to zoom.
    ///
    /// ## The strip's own gesture: judged, not kept
    ///
    /// `.none`, not `.tap`. Tapping the old, whole-log strip opened the full page centred on the
    /// moment touched, mapping a time relative to *this* section's own strip onto the full page's
    /// own, separately built series — see `WaterfallView.init(logs:openingTime:)`'s own
    /// documentation on that mapping, which explicitly assumed the two series shared the same
    /// origin. They no longer do: this strip's series now starts at the earliest of only the most
    /// recent few requests, not the log's true earliest one, so reusing that mapping unchanged
    /// would centre the full page on the *wrong* moment, silently, by however much time separates
    /// the two origins. Fixing the mapping itself — carrying an absolute `Date` end to end instead
    /// of a relative offset — would mean changing `WaterfallView`'s own, already-shipped and
    /// owner-approved contract for a page this fix has no other reason to touch. Simpler, and
    /// arguably more honest about what changed here: the five rows directly beneath the strip
    /// already give exact, correct navigation to precisely the request tapped, which is strictly
    /// *more* precise than "centred near where you tapped" ever was. A tap on the strip itself
    /// would now be redundant with the row right underneath it, not a second way to reach
    /// something the rows cannot. **See all**, unchanged, is still how this screen reaches the
    /// full, unzoomed page.
    private func waterfallSection(rowLayout: WaterfallDetailRowMetrics.Layout) -> some View {
        let window = WaterfallWindow(span: viewModel.recentLayout.series.span, narrowest: 0)
        return Section {
            WaterfallOverviewStrip(
                series: viewModel.recentLayout.series,
                window: nil,
                height: WaterfallOverviewStrip.sectionHeight,
                interaction: .none
            )
            ForEach(viewModel.recentLayout.rows) { row in
                NavigationLink {
                    LogDetailsView(httpRequest: row.request)
                } label: {
                    WaterfallDetailRow(row: row, window: window,
                                       showsHost: viewModel.recentLayout.showsHost,
                                       labelWidth: rowLayout.labelWidth,
                                       durationWidth: rowLayout.durationWidth)
                }
            }
        } header: {
            HStack {
                Text(localized("Waterfall"))
                Spacer()
                // A trailing header link, the way iOS opens the full version of a summarised
                // list everywhere else. It pushes onto the stack this screen was pushed onto,
                // so Back returns here rather than to the log. No opening time: the link is the
                // page's ordinary entrance and opens at the full span, same as it always has.
                NavigationLink(localized("See all")) {
                    WaterfallView(logs: logs)
                }
                // A section header styles its content as chrome — small, secondary, uppercased.
                // These three put the link back to being a control the way iOS's own "See All" is.
                .textCase(nil)
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        } footer: {
            Text(viewModel.waterfallCaption)
        }
    }

    /// How one of this section's own rows divides its width between the label column, the plot,
    /// and the duration column — a thin wrapper around
    /// `WaterfallDetailRowMetrics.layout(rowWidth:scaledLabelWidth:scaledDurationWidth:)` for the
    /// same reason ``WaterfallView/rowLayout(in:)`` is: supplying it with the two values only a
    /// view can produce, ``scaledLabelWidth`` and ``scaledDurationWidth``, so this screen's own
    /// rows read their column widths from the same two properties ``WaterfallDetailRow`` is
    /// actually handed, rather than each recomputing its own `@ScaledMetric`.
    ///
    /// - Parameter rowWidth: The full width one row is given, from ``statistics``'s own
    ///   `GeometryReader`.
    /// - Returns: The label, plot and duration widths the row should draw at.
    private func rowLayout(in rowWidth: CGFloat) -> WaterfallDetailRowMetrics.Layout {
        WaterfallDetailRowMetrics.layout(rowWidth: rowWidth,
                                         scaledLabelWidth: scaledLabelWidth,
                                         scaledDurationWidth: scaledDurationWidth)
    }

    /// The endpoint breakdown, slowest first.
    private var endpointSection: some View {
        Section {
            ForEach(viewModel.statistics.endpoints) { endpoint in
                LabeledContent {
                    Text(viewModel.durationText(endpoint.slowestDuration))
                        .monospacedDigit()
                } label: {
                    Text(endpoint.id)
                    Text(viewModel.endpointSubtitle(for: endpoint))
                }
            }
        } header: {
            Text(localized("Slowest Endpoints"))
        } footer: {
            Text(localized("The figure shown beside each endpoint is its slowest recorded round trip."))
        }
    }

    /// The host breakdown, most failures first.
    private var hostSection: some View {
        Section {
            ForEach(viewModel.statistics.hosts) { host in
                LabeledContent {
                    Text(viewModel.durationText(host.medianDuration))
                        .monospacedDigit()
                } label: {
                    Text(host.id)
                    Text(viewModel.hostSubtitle(for: host))
                }
            }
        } header: {
            Text(localized("By Host"))
        } footer: {
            Text(localized("The figure shown beside each host is its median round trip."))
        }
    }

    /// The placeholder shown while nothing has been captured.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Traffic Captured"),
                systemImage: "chart.bar.xaxis",
                description: Text(
                    localized("Figures appear once requests are logged. They follow the log's search and filters, so they describe whatever the list is showing.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Traffic Captured"))
                    .font(.headline)
                Text(localized("Figures appear once requests are logged. They follow the log's search and filters, so they describe whatever the list is showing."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
