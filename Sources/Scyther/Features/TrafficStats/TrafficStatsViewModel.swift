//
//  TrafficStatsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
import CoreGraphics
import Foundation

/// Drives ``TrafficStatsView``.
///
/// Holds the requests the screen is describing — the filtered array the network log is showing —
/// and recomputes ``TrafficStatistics`` and ``WaterfallSeries`` from them on a detached task, the
/// way `NetworkLogsViewModel` already filters off the main actor.
///
/// No figure is calculated here. Everything this type does to a number is turn it into text: the
/// arithmetic lives in the two pure types so it can be pinned by a test that never builds a view.
///
/// ## Usage
/// ```swift
/// let viewModel = TrafficStatsViewModel(requests: logs.requests, totalCount: logs.totalRequestCount)
/// await viewModel.recompute()
/// ```
final class TrafficStatsViewModel: ViewModel {

    /// How many completed measurements the summary needs before it reports percentiles.
    ///
    /// A median of three samples is noise, so below this the summary shows the fastest and
    /// slowest round trips instead — figures that are true of any sample size.
    static let percentileThreshold = 5

    /// How long the screen waits after the log changes before recomputing.
    ///
    /// Matches the log's own search debounce. With a live app the request list changes constantly
    /// and every change would otherwise walk the whole array twice.
    static let recomputeDebounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

    /// How much wider than the longest bar the waterfall's axis runs.
    ///
    /// The value label sits past the end of its bar, so the axis needs headroom or the longest
    /// bar's label falls outside the plot.
    private static let chartHeadroom = 1.35

    /// The narrowest axis the chart will draw, in seconds, so a session with no measured duration
    /// still has somewhere to put its bars.
    private static let minimumChartSpan = 0.05

    /// The vertical space one bar takes, in points.
    private static let barHeight: CGFloat = 22

    /// How thick each bar is drawn, in points, leaving a gap between neighbouring rows.
    static let barThickness: CGFloat = 10

    /// The vertical space the chart's axis and labels take, in points.
    private static let chartChrome: CGFloat = 60

    /// The shortest the chart is ever drawn, in points.
    private static let minimumChartHeight: CGFloat = 140

    /// The figures for ``requests``. ``TrafficStatistics/empty`` until the first computation lands.
    @Published private(set) var statistics: TrafficStatistics = .empty

    /// The timeline for ``requests``. ``WaterfallSeries/empty`` until the first computation lands.
    @Published private(set) var waterfall: WaterfallSeries = .empty

    /// The requests the screen is describing: the network log's filtered array.
    private(set) var requests: [HTTPRequest]

    /// How many requests the log holds before its search and filters narrow it.
    private(set) var totalCount: Int

    /// Coalesces bursts of log updates into one recomputation.
    private let updateSubject = PassthroughSubject<Void, Never>()

    /// Retains the debounce subscription.
    private var cancellables = Set<AnyCancellable>()

    /// The task the current recomputation is running on.
    private var recomputeTask: Task<Void, Never>?

    /// The chart's rows, in the order they are drawn.
    @Published private(set) var chartRows: [ChartRow] = []

    /// One row of the waterfall chart: a bar and the name the axis gives it.
    ///
    /// The name carries the row's position because a chart's categorical axis collapses two rows
    /// that share a value, and two calls to the same endpoint have the same label. Numbering them
    /// keeps each request its own bar, and matches the order they were sent in.
    struct ChartRow: Identifiable, Equatable {
        /// The axis label, which is also the row's identity on the chart's y scale.
        let id: String

        /// The bar this row draws.
        let entry: WaterfallEntry
    }

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - requests: The requests to describe, usually the log's filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    init(requests: [HTTPRequest], totalCount: Int) {
        self.requests = requests
        self.totalCount = totalCount
        super.init()
    }

    /// Cancels any recomputation in flight.
    deinit {
        recomputeTask?.cancel()
    }

    /// Wires the debounce that coalesces log updates.
    override func setup() {
        super.setup()
        updateSubject
            .debounce(for: Self.recomputeDebounce, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.recomputeTask?.cancel()
                self.recomputeTask = Task { [weak self] in await self?.recompute() }
            }
            .store(in: &cancellables)
    }

    /// Computes the statistics and the waterfall on first appearance.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await recompute()
    }

    /// Replaces the requests the screen describes and schedules a debounced recomputation.
    ///
    /// - Parameters:
    ///   - requests: The new filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    func update(requests: [HTTPRequest], totalCount: Int) {
        self.requests = requests
        self.totalCount = totalCount
        updateSubject.send(())
    }

    /// Recomputes both value types from the current requests, off the main actor.
    ///
    /// Safe to call at any time; the results are assigned back on the main actor together, so the
    /// summary and the chart are never drawn from different snapshots.
    func recompute() async {
        let snapshot = requests
        let computed = await Task.detached(priority: .userInitiated) {
            (statistics: TrafficStatistics.compute(from: snapshot), waterfall: WaterfallSeries.build(from: snapshot))
        }.value
        guard !Task.isCancelled else { return }
        statistics = computed.statistics
        waterfall = computed.waterfall
        chartRows = computed.waterfall.entries.enumerated().map { index, entry in
            ChartRow(id: "\(index + 1). \(entry.label)", entry: entry)
        }
    }

    // MARK: - Caption

    /// How many requests the figures cover.
    var captionCount: Int { requests.count }

    /// Whether the log's search or filters are narrowing what the figures cover.
    var isFiltered: Bool { requests.count != totalCount }

    /// Whether there is nothing to describe.
    var isEmpty: Bool { requests.isEmpty }

    /// The line under the title saying what the figures cover.
    var caption: String {
        isFiltered
            ? localized("\(captionCount) of \(totalCount) requests")
            : localized("\(captionCount) requests")
    }

    // MARK: - Summary

    /// Whether the sample is big enough for the percentiles to mean anything.
    ///
    /// Below ``percentileThreshold`` completed measurements the screen shows the fastest and
    /// slowest round trips instead.
    var showsPercentiles: Bool { statistics.summary.completedCount >= Self.percentileThreshold }

    /// The request count as text.
    var requestCountText: String { statistics.summary.requestCount.formatted() }

    /// The failure count as text.
    var failureCountText: String { statistics.summary.failureCount.formatted() }

    /// The pending count as text.
    var pendingCountText: String { statistics.summary.pendingCount.formatted() }

    /// The stubbed count as text.
    var stubbedCountText: String { statistics.summary.stubbedCount.formatted() }

    /// The failure rate as a whole-number percentage, or `nil` when nothing was measured.
    var failureRateText: String? {
        statistics.summary.failureRate?.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The bytes received, formatted for reading.
    var bytesText: String { statistics.summary.bytesReceived.formatted(.byteCount(style: .file)) }

    /// The wall-clock span of the captured session, or `nil` when no request carries a date.
    var elapsedText: String? {
        statistics.summary.wallClockSpan.map { secondsText($0) }
    }

    // MARK: - Waterfall

    /// How tall the chart is drawn, so every bar keeps its own row.
    var chartHeight: CGFloat {
        max(Self.minimumChartHeight, CGFloat(waterfall.entries.count) * Self.barHeight + Self.chartChrome)
    }

    /// The far end of the chart's seconds axis.
    ///
    /// Wider than the longest bar so the value label past its end stays inside the plot, and
    /// never zero, which would leave the axis with no extent to draw on.
    var chartUpperBound: Double {
        max(waterfall.span * Self.chartHeadroom, Self.minimumChartSpan)
    }

    /// The axis labels of the waterfall's bars, oldest first, which is the chart's y-axis domain.
    var chartDomain: [String] { chartRows.map(\.id) }

    /// What one bar's outcome is called, which is also its key in the chart's colour scale.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The localised outcome name.
    func outcomeTitle(for entry: WaterfallEntry) -> String {
        if entry.isPending { return localized("Pending") }
        if entry.isStubbed { return localized("Stubbed") }
        return entry.isFailure ? localized("Failed") : localized("Succeeded")
    }

    /// The value label drawn at the end of one bar.
    ///
    /// In the same milliseconds-or-seconds form the summary uses, so a two millisecond bar reads
    /// as `2 ms` rather than rounding away to `0 s`.
    ///
    /// - Parameter entry: The bar.
    /// - Returns: The bar's length as text.
    func valueLabel(for entry: WaterfallEntry) -> String { durationText(entry.duration * 1_000) }

    /// The sentence under the chart explaining what it is showing.
    var waterfallCaption: String {
        localized("The most recent \(waterfall.entries.count) requests on a shared axis. Bars that overlap were in flight at the same time.")
    }

    // MARK: - Breakdowns

    /// The subtitle under an endpoint: how many requests it took and their median.
    ///
    /// - Parameter endpoint: The endpoint row.
    /// - Returns: The subtitle.
    func endpointSubtitle(for endpoint: TrafficStatistics.EndpointBreakdown) -> String {
        [
            localized("\(endpoint.requestCount) requests"),
            localized("Median \(durationText(endpoint.medianDuration))"),
        ].joined(separator: " · ")
    }

    /// The subtitle under a host: how many requests it took, and how many failed when any did.
    ///
    /// - Parameter host: The host row.
    /// - Returns: The subtitle.
    func hostSubtitle(for host: TrafficStatistics.HostBreakdown) -> String {
        var parts = [localized("\(host.requestCount) requests")]
        if host.failureCount > 0 {
            parts.append(localized("\(host.failureCount) failed"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Formatting

    /// A duration in milliseconds as text.
    ///
    /// Milliseconds up to a second and seconds beyond it, because "1,842 ms" is a number a reader
    /// has to divide before it means anything.
    ///
    /// - Parameter milliseconds: The duration, or `nil` when there is nothing to show.
    /// - Returns: The formatted duration, or an em dash.
    func durationText(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite else { return "—" } // scyther:unlocalised em dash placeholder
        guard milliseconds >= 1_000 else {
            return Measurement(value: milliseconds.rounded(), unit: UnitDuration.milliseconds)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        return secondsText(milliseconds / 1_000)
    }

    /// A duration in seconds as text, to two decimal places.
    ///
    /// - Parameter seconds: The duration.
    /// - Returns: The formatted duration.
    private func secondsText(_ seconds: TimeInterval) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0...2))
                )
            )
    }
}
