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

    /// How many of the most recent requests the Waterfall section's own strip and row preview are
    /// zoomed to.
    ///
    /// The section used to draw the *whole* log as one strip — every request in the session
    /// compressed onto one shared axis, exactly as the full-log page's own overview does. At
    /// real request counts that read as a scatter of near-invisible specks: 25 requests over 24
    /// seconds is 25 marks a few points wide each, conveying rough shape and nothing else, and
    /// naming *when* something happened is the one thing a preview like this exists to do. The
    /// owner judged it unusable and asked for a small version of the full page instead — a strip
    /// zoomed to a handful of legible bars, with those same requests listed as real, tappable
    /// rows beneath it.
    ///
    /// `5`, the owner's own suggestion, kept rather than replaced with a rounder or larger figure:
    /// it is few enough that every bar earns real width even on a screen a few requests apart, few
    /// enough that five rows plus the section's other chrome still fits comfortably above the
    /// fold on the smallest supported phone, and small enough that "these are the *most recent*
    /// few" reads as obviously true rather than as an arbitrary cut-off partway through what would
    /// otherwise look like a complete list. Larger figures were considered and rejected: even ten
    /// bars, at the kind of a-few-seconds-apart traffic this toolkit is built to inspect, start
    /// crowding back toward the specks this constant exists to avoid, and a section meant as a
    /// glance rather than a workspace does not need to try to be one.
    ///
    /// A log holding fewer than this shows exactly what it has — see
    /// ``WaterfallSeries/build(from:limit:now:)``'s own handling of a `limit` larger than its
    /// input — rather than padding or hiding anything to reach five.
    static let recentWaterfallCount = 5

    /// The figures for ``requests``. ``TrafficStatistics/empty`` until the first computation lands.
    @Published private(set) var statistics: TrafficStatistics = .empty

    /// The whole session's timeline for ``requests``, laid out on one shared axis.
    ///
    /// No longer what the Waterfall section's own strip draws — see ``recentLayout`` for that —
    /// but still built in full, because ``waterfallCaption`` still describes the whole session as
    /// context underneath the section's own small preview of the most recent few. See that
    /// property's own documentation for why the caption kept this rather than following the strip
    /// down to ``TrafficStatsViewModel/recentWaterfallCount`` requests too.
    ///
    /// ``WaterfallSeries/empty`` until the first computation lands.
    @Published private(set) var waterfall: WaterfallSeries = .empty

    /// The strip and the row preview beneath it: the most recent
    /// ``TrafficStatsViewModel/recentWaterfallCount`` requests, laid out on their own shared axis
    /// and paired back to the captures behind them.
    ///
    /// Built by ``WaterfallViewModel/layout(of:limit:totalCount:now:)`` — the exact function the
    /// full-log page uses for itself, called here with a small `limit` instead of the whole log,
    /// rather than a second implementation of the same axis-and-pairing arithmetic. See that
    /// function's own documentation for why it takes `limit` as a parameter rather than assuming
    /// "everything" the way it once did.
    ///
    /// A `WaterfallViewModel.Layout`, not a bare `WaterfallSeries`, because the section now draws
    /// real rows beneath its strip — ``WaterfallDetailRow``, reused directly rather than rebuilt —
    /// and a row needs the capture behind its bar, which only `Layout.rows` carries.
    /// ``WaterfallViewModel/Layout/showsHost`` is read from here too, scoped to just these few
    /// requests rather than to the whole log, matching how the full page's own rows decide
    /// whether to draw a host.
    ///
    /// ``WaterfallViewModel/Layout/empty`` until the first computation lands.
    @Published private(set) var recentLayout: WaterfallViewModel.Layout = .empty

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
        // Read on the main actor and captured into a local, the same reason `snapshot` and
        // `snapshotTotal` are: `recentWaterfallCount` is a `static let` on this `@MainActor` type,
        // so it is itself main-actor-isolated, and the detached task below cannot read it directly.
        let recentLimit = Self.recentWaterfallCount
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
                // The whole log, kept for the caption's own context even though the strip no
                // longer draws it — see `waterfall`'s own documentation.
                waterfall: WaterfallSeries.build(from: snapshot, limit: snapshot.count),
                // The strip and its row preview, zoomed to the most recent few rather than the
                // whole log — reusing the full-log page's own layout function with a small
                // `limit`, not a second implementation. See `recentLayout`'s own documentation.
                recentLayout: WaterfallViewModel.layout(
                    of: snapshot,
                    limit: recentLimit,
                    totalCount: snapshotTotal
                )
            )
        }.value
        guard !Task.isCancelled else { return }
        statistics = computed.statistics
        waterfall = computed.waterfall
        recentLayout = computed.recentLayout
        captionCount = snapshot.count
        captionTotal = snapshotTotal
    }

    // MARK: - Caption

    /// Whether the log's search or filters are narrowing what the figures cover.
    var isFiltered: Bool { captionCount != captionTotal }

    /// Whether there is nothing to describe.
    var isEmpty: Bool { captionCount == 0 }

    /// The line under the title saying what the figures cover.
    ///
    /// Only the "N of M requests" form now — no longer conditional on ``isFiltered`` the way it
    /// used to be. ``TrafficStatsView/summarySection`` is this property's only production reader,
    /// and it now shows the header only when `isFiltered` is true: unfiltered, the header would
    /// have restated the section's own first row, `LabeledContent(localized("Requests"), …)`, so
    /// the view omits it entirely rather than call this at all. With the unfiltered case no
    /// longer reachable from anywhere that reads this, the branch that produced it was dead
    /// weight — see `TrafficStatsView.summarySection`'s header for the reasoning.
    ///
    /// The unfiltered branch's key, `"%lld requests"`, is not orphaned by this: `endpointSubtitle(for:)`
    /// and `hostSubtitle(for:)` below both still build it from `requestCount`, so it stays in
    /// `Scripts/localization/strings/TrafficStats.json` untouched.
    var caption: String {
        localized("\(captionCount) of \(captionTotal) requests")
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

    /// The sentence under the section: the whole session's own count, span and host total, as
    /// context beneath the strip and rows above it now showing only the most recent
    /// ``TrafficStatsViewModel/recentWaterfallCount``.
    ///
    /// ## Kept, not reworded, once the strip stopped drawing the whole log
    ///
    /// This sentence used to describe exactly what the strip above it drew, because the strip
    /// drew everything. It no longer does — see ``recentLayout`` — and the owner's own question
    /// was direct: keep this caption, reword it, or move it. Decided to keep the wording
    /// unchanged, for two reasons. First, it never actually claimed to describe the strip in the
    /// first place: "25 requests over 24 seconds across 3 hosts" is already a plain statement
    /// about the session, not "the strip above shows…", so nothing about it became false once the
    /// strip stopped matching it — it was always the session's own summary, sitting in the
    /// section's footer, which is exactly the slot a summary belongs in. Second, folding in an
    /// explicit "showing 5 of 25" framing was tried and rejected: every phrasing tested either
    /// repeated the request count immediately next to itself ("5 of 25 requests. 25 requests
    /// over…") or left genuine ambiguity about which count a trailing "over X, across Y hosts"
    /// modified. The visual layout already carries that distinction without more words needing to
    /// carry it too — a handful of legible bars and real tappable rows read as *recent* on their
    /// own, next to a **See all** link that already implies there is more, over a footer stating
    /// bigger numbers than what is drawn above it.
    ///
    /// This is a wording judgement, not a settled fact, and the alternative was seriously
    /// considered rather than dismissed — see the fix report for the phrasings that were tried and
    /// why each was set aside; the owner may read the rendered result differently.
    ///
    /// ## Why two joined sentences, not one
    ///
    /// The single sentence this replaced — `"\(count) requests over \(duration) across \(hosts)
    /// hosts"` — carries two numbers that agree with two different nouns, and the String Catalog
    /// this package builds from only inflects a key's *first* number: the request count would
    /// pluralise correctly while the host count stayed flat, so a single-host log read "across 1
    /// hosts" on the feature's own first screen. Splitting each count into its own pluralised key
    /// and joining them the way ``endpointSubtitle(for:)`` and ``hostSubtitle(for:)`` already join
    /// theirs — and the way this very caption did before the whole-log strip briefly replaced its
    /// most-recent-seven predecessor — lets each half inflect on its own number.
    var waterfallCaption: String {
        [
            localized("\(waterfall.entries.count) requests over \(DurationText.milliseconds(waterfall.span * 1_000))"),
            localized("across \(hostCount) hosts"),
        ].joined(separator: " ") // scyther:unlocalised space between localised sentences
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
