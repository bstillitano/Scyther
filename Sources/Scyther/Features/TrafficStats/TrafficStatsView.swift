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

    /// The moment the Waterfall section's overview strip was tapped, which the full-log page opens
    /// centred on.
    ///
    /// Not read back by anything here: it is only ever written just before
    /// ``isWaterfallNavigationActive`` is set, and handed straight to ``WaterfallView``'s own
    /// initialiser, which applies it to the page's own view model — see
    /// ``WaterfallView/init(logs:openingTime:)``. This screen never reaches into that view model
    /// itself, the way its own ``viewModel`` is never reached into by anything that presents it.
    @State private var waterfallOpeningTime: TimeInterval?

    /// Whether the hidden link to the full-log page, opened at ``waterfallOpeningTime``, is active.
    ///
    /// A tap on the strip has no destination view to carry a `NavigationLink`'s own label, unlike
    /// the **See all** link beside it, so navigation is driven by activating this flag instead.
    @State private var isWaterfallNavigationActive = false

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

    /// The whole session compressed into one strip, exactly as ``WaterfallView`` draws it.
    ///
    /// The section used to stack its own most-recent-seven bars into a `Chart` of its own; that
    /// chart is gone. ``WaterfallOverviewStrip`` is the *same* overview the full-log page marks
    /// its current window on, drawn here with no window — the section names no span of the log as
    /// "current", the page does — which is what ``WaterfallOverviewStrip/window`` being `nil`
    /// buys.
    ///
    /// The gesture is `.tap`, not `.scrub`, and that is not a stylistic choice: this section sits
    /// inside the screen's `List`, and `.scrub`'s zero-distance drag would win arbitration against
    /// the list's own pan and steal every scroll that happened to start on the strip. `.tap` lets
    /// a genuine scroll pass through untouched and only reports the moment touched when the touch
    /// did not travel — see ``WaterfallOverviewStrip/Interaction``.
    private var waterfallSection: some View {
        Section {
            WaterfallOverviewStrip(
                series: viewModel.waterfall,
                window: nil,
                height: WaterfallOverviewStrip.sectionHeight,
                interaction: .tap { time in
                    waterfallOpeningTime = time
                    isWaterfallNavigationActive = true
                }
            )
            // A hidden link rather than one wrapping the strip: the strip's own gesture already
            // decides whether a touch counts as a tap, and a `NavigationLink` wrapping it would
            // fire on release regardless, pushing the page on the drag that was meant to keep
            // scrolling. Driving navigation from `isActive` instead lets the strip's own gesture
            // stay the only thing deciding whether this section was tapped or scrolled past.
            //
            // `.accessibilityHidden(true)`: the strip already carries the row's whole
            // accessibility element — see ``WaterfallOverviewStrip`` — so without this VoiceOver
            // would also land on an empty, unlabelled control sitting behind it.
            .background {
                NavigationLink(isActive: $isWaterfallNavigationActive) {
                    WaterfallView(logs: logs, openingTime: waterfallOpeningTime)
                } label: {
                    EmptyView()
                }
                .opacity(0)
                .accessibilityHidden(true)
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
