//
//  TrafficStatsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
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

    /// The figures for ``requests``. ``TrafficStatistics/empty`` until the first computation lands.
    @Published private(set) var statistics: TrafficStatistics = .empty

    /// The timeline for ``requests``. ``WaterfallSeries/empty`` until the first computation lands.
    @Published private(set) var waterfall: WaterfallSeries = .empty

    /// The requests the screen is describing: the network log's filtered array.
    private(set) var requests: [HTTPRequest]

    /// How many requests the log holds before its search and filters narrow it.
    private(set) var totalCount: Int

    /// How many requests the published figures were computed from.
    ///
    /// Not ``requests``: that array is replaced the moment the log changes, while the figures
    /// below it lag by the debounce. Reading the caption from one and the rows from the other
    /// left the header saying "41 requests" above a table describing forty, for up to half a
    /// second at a time, whenever traffic was flowing.
    @Published private(set) var captionCount: Int

    /// How many requests the log held, unfiltered, when the published figures were computed.
    ///
    /// Snapshotted with ``captionCount`` for the same reason.
    @Published private(set) var captionTotal: Int

    /// Coalesces bursts of log updates into one recomputation.
    private let updateSubject = PassthroughSubject<Void, Never>()

    /// Retains the debounce subscription.
    private var cancellables = Set<AnyCancellable>()

    /// The task the current recomputation is running on.
    private var recomputeTask: Task<Void, Never>?

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - requests: The requests to describe, usually the log's filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    init(requests: [HTTPRequest], totalCount: Int) {
        self.requests = requests
        self.totalCount = totalCount
        self.captionCount = requests.count
        self.captionTotal = totalCount
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
    /// Safe to call at any time; the results are assigned back on the main actor together — the
    /// caption's counts among them — so no two parts of the screen are ever drawn from different
    /// snapshots.
    func recompute() async {
        let snapshot = requests
        let snapshotTotal = totalCount
        // Force each capture's lazily assigned hash while still on the main actor. `HTTPRequest`
        // is `@unchecked Sendable` and `getRandomHash()` writes on first call, so leaving it to
        // the detached pass would have two threads racing to assign it — and the waterfall bakes
        // that id into the bar it draws.
        for request in snapshot {
            _ = request.getRandomHash()
        }
        let computed = await Task.detached(priority: .userInitiated) {
            (
                statistics: TrafficStatistics.compute(from: snapshot),
                // The whole log, not a preview of it: the section now draws the same overview
                // strip the full-log page does, over everything, the way the page's own build
                // call already does.
                waterfall: WaterfallSeries.build(from: snapshot, limit: snapshot.count)
            )
        }.value
        guard !Task.isCancelled else { return }
        statistics = computed.statistics
        waterfall = computed.waterfall
        captionCount = snapshot.count
        captionTotal = snapshotTotal
    }

    // MARK: - Caption

    /// Whether the log's search or filters are narrowing what the figures cover.
    var isFiltered: Bool { captionCount != captionTotal }

    /// Whether there is nothing to describe.
    var isEmpty: Bool { captionCount == 0 }

    /// The line under the title saying what the figures cover.
    var caption: String {
        isFiltered
            ? localized("\(captionCount) of \(captionTotal) requests")
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

    /// How many distinct hosts the log touched, for the section's footer.
    ///
    /// The count rather than the names: the names are on the rows, and a section footer listing
    /// twelve hosts is a paragraph. Empty hosts — an unparseable request URL, see
    /// ``WaterfallEntry/host`` — name nothing and are left out, or a log with a single real host
    /// and one malformed request would count as touching two.
    ///
    /// Lowercased before counting, matching ``WaterfallSeries/shortHost(for:)`` and
    /// ``TrafficStatistics/HostBreakdown``'s own identity: without it, two requests to the same
    /// host that merely differ in case — `API.example.com` and `api.example.com` — would count as
    /// two distinct hosts here while *By Host* below groups them as one, and the footer would
    /// disagree with the section it sits under.
    var hostCount: Int { Set(waterfall.entries.map { $0.host.lowercased() }).filter { !$0.isEmpty }.count }

    /// The sentence under the strip explaining what it is showing.
    ///
    /// The strip draws the whole log now, not a preview of it — see ``WaterfallOverviewStrip`` —
    /// so the caption states what a minimap states: how much is on it, how long it ran, and how
    /// much of it there is to lose track of. It used to say how many requests were hidden and
    /// point at **See all** to find them; nothing is hidden any more, so nothing here does either.
    var waterfallCaption: String {
        localized("\(waterfall.entries.count) requests over \(DurationText.milliseconds(waterfall.span * 1_000)) across \(hostCount) hosts")
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
    /// Delegated to ``DurationText/milliseconds(_:)``, which the waterfall's bar labels also use,
    /// so the same round trip reads the same wherever the screen reports it.
    ///
    /// - Parameter milliseconds: The duration, or `nil` when there is nothing to show.
    /// - Returns: The formatted duration, or an em dash.
    func durationText(_ milliseconds: Double?) -> String {
        DurationText.milliseconds(milliseconds)
    }

    /// A duration in seconds as text, to two decimal places.
    ///
    /// - Parameter seconds: The duration.
    /// - Returns: The formatted duration.
    private func secondsText(_ seconds: TimeInterval) -> String {
        DurationText.seconds(seconds)
    }
}
