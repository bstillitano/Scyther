//
//  WaterfallViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Combine
import CoreGraphics
import Foundation

/// Drives ``WaterfallView``, the full-log waterfall.
///
/// The preview section on **Traffic Stats** shows the most recent ``WaterfallSeries/defaultLimit``
/// requests because a preview has to read as one. This view model exists to lift that ceiling: it
/// lays out *every* request the log is currently showing on one axis, and pairs each bar back with
/// the request it was drawn from so tapping the bar can open it.
///
/// It holds the result rather than deriving it. A `LazyVStack` asks its rows for content
/// constantly while scrolling, so a computed `rows` would rebuild a thousand-entry series on
/// every frame; the layout is computed once per change to the log, on a detached task behind the
/// same debounce ``TrafficStatsViewModel`` uses, and published as a single value.
///
/// ## Usage
/// ```swift
/// let viewModel = WaterfallViewModel(requests: logs.requests, totalCount: logs.totalRequestCount)
/// await viewModel.recompute()
/// viewModel.rows.first?.request   // the capture behind the topmost bar
/// ```
final class WaterfallViewModel: ViewModel {

    /// How long the page waits after the log changes before laying it out again.
    ///
    /// Matches ``TrafficStatsViewModel/recomputeDebounce``, because the page is reached from that
    /// screen and follows the same log: coalescing on a different rhythm would have the two
    /// disagree about how much traffic there is for up to half a second at a time.
    static let recomputeDebounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

    /// One row of the page: a bar, the name beside it, and the capture behind it.
    ///
    /// The request is carried rather than looked up when the row is tapped. Matching a bar back
    /// to a capture by its label would land the reader on the wrong one of two calls to the same
    /// endpoint, and re-scanning the log per row would make drawing the page quadratic in the
    /// size of the log.
    struct Row: Identifiable, Sendable {
        /// The capture's own hash, so a row keeps its identity as newer traffic arrives above it.
        let id: String

        /// The name drawn beside the bar: the position in the log and the bar's label, in the
        /// form the preview chart already labels its axis with.
        let label: String

        /// The bar this row draws.
        let entry: WaterfallEntry

        /// The capture the bar was drawn from, which is what tapping the row opens.
        let request: HTTPRequest

    }

    /// A laid-out log: the shared axis, the rows on it, and what the two describe.
    ///
    /// Published as one value, not unpacked into several. The axis, the bars and the caption's
    /// counts are one snapshot of one moment: assigning them separately puts the page one
    /// `objectWillChange` away from drawing new bars against an old axis, or captioning new bars
    /// with an old count.
    struct Layout: Sendable {
        /// The series the rows were laid out on.
        let series: WaterfallSeries

        /// The rows, oldest first.
        let rows: [Row]

        /// How many requests the rows were laid out from.
        let count: Int

        /// How many requests the log held, unfiltered, when they were laid out.
        let total: Int

        /// The median measured duration in the series, in seconds, or `nil` when nothing in it
        /// finished.
        ///
        /// Cached with the rows rather than derived on demand. The page rebuilds its
        /// ``WaterfallTimeScale`` whenever its geometry changes, and a `LazyVStack` asks for
        /// geometry constantly; sorting a thousand durations on every one of those passes is the
        /// cost this whole view model exists to avoid.
        let medianDuration: Double?

        /// The ``WaterfallTimeScale/tailPercentile`` measured duration, in seconds, or `nil` as
        /// above. Cached for the same reason.
        let tailDuration: Double?

        /// Nothing laid out.
        static let empty = Layout(series: .empty, rows: [], count: 0, total: 0,
                                  medianDuration: nil, tailDuration: nil)
    }

    /// The laid-out log the page is drawing.
    @Published private(set) var layout: Layout = .empty

    /// The requests the page is drawing: the network log's filtered array.
    private(set) var requests: [HTTPRequest]

    /// How many requests the log holds before its search and filters narrow it.
    private(set) var totalCount: Int

    /// Coalesces bursts of log updates into one layout pass.
    private let updateSubject = PassthroughSubject<Void, Never>()

    /// Retains the debounce subscription.
    private var cancellables = Set<AnyCancellable>()

    /// The task the current layout pass is running on.
    private var recomputeTask: Task<Void, Never>?

    /// Creates the view model, laying the log out before the page is first drawn.
    ///
    /// The first pass is synchronous, unlike every one after it. It costs about two milliseconds
    /// for a thousand requests, and it buys the page never flashing its "no traffic" placeholder
    /// over a log that is full — which is what an empty initial value plus an asynchronous first
    /// pass produced.
    ///
    /// - Parameters:
    ///   - requests: The requests to draw, usually the log's filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    init(requests: [HTTPRequest], totalCount: Int) {
        self.requests = requests
        self.totalCount = totalCount
        super.init()
        layout = Self.layout(of: requests, totalCount: totalCount)
    }

    /// Cancels any layout pass in flight.
    deinit {
        recomputeTask?.cancel()
    }

    /// Wires the debounce that coalesces log updates.
    override func setup() {
        super.setup()
        updateSubject
            .debounce(for: Self.recomputeDebounce, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.startRecomputing()
            }
            .store(in: &cancellables)
    }

    /// Lays the log out on first appearance.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await startRecomputing()?.value
    }

    /// Replaces the requests the page draws and schedules a debounced layout pass.
    ///
    /// - Parameters:
    ///   - requests: The new filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    func update(requests: [HTTPRequest], totalCount: Int) {
        self.requests = requests
        self.totalCount = totalCount
        updateSubject.send(())
    }

    /// Starts a layout pass, cancelling whichever one was already running.
    ///
    /// Every pass goes through here, the first appearance included. That one used to be an
    /// untracked `Task`, so a debounced pass could not cancel it and it could land afterwards and
    /// overwrite fresh rows with stale ones.
    ///
    /// - Returns: The task, so a caller that has to wait for it can.
    @discardableResult
    private func startRecomputing() -> Task<Void, Never>? {
        recomputeTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.recompute()
        }
        recomputeTask = task
        return task
    }

    /// Lays the current requests out, off the main actor.
    ///
    /// Safe to call at any time; the whole snapshot is assigned in one write, so the page is
    /// never drawn from two snapshots at once.
    func recompute() async {
        let snapshot = requests
        let snapshotTotal = totalCount
        // Force each capture's lazily assigned hash while still on the main actor. `HTTPRequest`
        // is `@unchecked Sendable` and `getRandomHash()` writes on first call, so leaving it to
        // the layout pass would have two threads racing to assign it — and a capture whose id
        // came out one way in the series and another in the lookup is a bar that silently
        // vanishes.
        for request in snapshot {
            _ = request.getRandomHash()
        }
        let computed = await Task.detached(priority: .userInitiated) {
            Self.layout(of: snapshot, totalCount: snapshotTotal)
        }.value
        guard !Task.isCancelled else { return }
        layout = computed
    }

    /// Lays a whole log out on one shared axis.
    ///
    /// Pure and `nonisolated` so it can run on a detached task and be measured by a test without
    /// building a view. The pairing back to captures is done through a hash-keyed dictionary in
    /// the same pass: the obvious alternative — each row searching the log for its own request —
    /// is quadratic, and a log holding thousands of entries is exactly the case this page was
    /// built for.
    ///
    /// - Parameters:
    ///   - requests: The captures to lay out, in any order.
    ///   - totalCount: How many requests the log holds unfiltered, carried through for the
    ///     caption.
    ///   - now: The moment the layout describes, which is where a still-running bar ends.
    ///     Defaults to the current time; a test passes its own so the arithmetic is deterministic.
    /// - Returns: The axis, the rows on it, and the counts they describe.
    nonisolated static func layout(
        of requests: [HTTPRequest],
        totalCount: Int = 0,
        now: Date = Date()
    ) -> Layout {
        guard !requests.isEmpty else {
            return Layout(series: .empty, rows: [], count: 0, total: totalCount,
                          medianDuration: nil, tailDuration: nil)
        }
        let series = WaterfallSeries.build(from: requests, limit: requests.count, now: now)
        var byHash = [String: HTTPRequest](minimumCapacity: requests.count)
        for request in requests {
            byHash[request.getRandomHash() as String] = request
        }
        let rows = series.entries.enumerated().compactMap { index, entry -> Row? in
            guard let request = byHash[entry.id] else { return nil }
            return Row(
                id: entry.id,
                label: "\(index + 1). \(entry.label)",
                entry: entry,
                request: request
            )
        }
        let durations = WaterfallTimeScale.measuredDurations(of: series)
        return Layout(
            series: series,
            rows: rows,
            count: requests.count,
            total: totalCount,
            medianDuration: WaterfallTimeScale.percentile(0.5, of: durations),
            tailDuration: WaterfallTimeScale.percentile(WaterfallTimeScale.tailPercentile, of: durations)
        )
    }

    // MARK: - Presentation

    /// The rows, oldest first, so time reads downward.
    var rows: [Row] { layout.rows }

    /// The series the published rows were laid out on.
    var series: WaterfallSeries { layout.series }

    /// Whether there is nothing to draw, which is what the page's empty state is for.
    var isEmpty: Bool { layout.rows.isEmpty }

    /// Whether the log's search or filters are narrowing what the page draws.
    var isFiltered: Bool { layout.count != layout.total }

    /// The far end of the shared seconds axis.
    ///
    /// Computed by ``WaterfallChartStyle/upperBound(forSpan:)`` rather than by a rule of its own,
    /// so both surfaces stop their axis in the same place.
    var upperBound: Double { WaterfallChartStyle.upperBound(forSpan: layout.series.span) }

    /// How many points a second is worth, for a page with the given room to draw in.
    ///
    /// The page asks for this on every geometry pass, so it has to be cheap: the two percentiles
    /// the rule needs were computed once, with the rows, and this is arithmetic on them.
    ///
    /// - Parameter visibleWidth: How much of the timeline shows at once, in points.
    /// - Returns: The scale the page draws at.
    func scale(visibleWidth: CGFloat) -> WaterfallTimeScale {
        WaterfallTimeScale.make(
            medianDuration: layout.medianDuration,
            tailDuration: layout.tailDuration,
            span: layout.series.span,
            visibleWidth: visibleWidth
        )
    }

    /// The sentence under the bars saying what the page is showing.
    ///
    /// It says "every request" only when that is true. The page is handed the log's *filtered*
    /// array, so under an active filter the unqualified sentence claimed to be the whole log while
    /// drawing one host's slice of it — the caption has to name the same "N of M" the screen it
    /// was opened from names.
    var caption: String {
        isFiltered
            ? localized("\(layout.count) of \(layout.total) requests on a shared axis, oldest first. Bars that overlap were in flight at the same time.")
            : localized("Every request in the log on a shared axis, oldest first. Bars that overlap were in flight at the same time.")
    }
}
