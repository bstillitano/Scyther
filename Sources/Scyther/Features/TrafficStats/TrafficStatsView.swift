//
//  TrafficStatsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Charts
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
    private var statistics: some View {
        List {
            summarySection
            if !viewModel.waterfall.entries.isEmpty {
                waterfallSection
            }
            if !viewModel.statistics.endpoints.isEmpty {
                endpointSection
            }
            if !viewModel.statistics.hosts.isEmpty {
                hostSection
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
            Text(viewModel.caption)
        } footer: {
            if summary.stubbedCount > 0 {
                Text(localized("A stubbed response never left the device, so it is counted here but left out of every duration, failure and byte total."))
            } else if !viewModel.showsPercentiles {
                Text(localized("Percentiles need at least five completed requests to mean anything, so the raw durations are shown instead."))
            }
        }
    }

    /// The timeline, one bar per request on a shared seconds axis.
    ///
    /// The bars, the colour scale and the outcome names come from ``WaterfallChartStyle`` rather
    /// than from here, because the **See all** page draws the same chart over the whole log and
    /// the two are meant to be indistinguishable. Only the layout is this section's own: it
    /// stacks every bar into one chart, where the page gives each bar a row it can be tapped in.
    private var waterfallSection: some View {
        Section {
            Chart(viewModel.chartRows) { row in
                WaterfallChartStyle.bar(
                    id: row.id,
                    entry: row.entry,
                    upperBound: viewModel.chartUpperBound
                )
            }
            .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
            .chartXScale(domain: 0...viewModel.chartUpperBound)
            .chartXAxisLabel(localized("Seconds"))
            // The x axis is left entirely to Charts. It was hand-coloured to secondary grid
            // lines, ticks and labels, which is what Charts already draws — restating it only
            // meant the chart stopped following the theme the rest of the screen follows.
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) {
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: viewModel.chartHeight)
        } header: {
            HStack {
                Text(localized("Waterfall"))
                Spacer()
                // A trailing header link, the way iOS opens the full version of a summarised
                // list everywhere else. It pushes onto the stack this screen was pushed onto,
                // so Back returns here rather than to the log.
                NavigationLink(localized("See all")) {
                    WaterfallView(logs: logs)
                }
                .textCase(nil)
            }
        } footer: {
            Text(viewModel.waterfallCaption)
        }
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
