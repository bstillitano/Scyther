//
//  WaterfallViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Combine
import Foundation

/// Drives ``WaterfallView``, the full-log waterfall.
///
/// The Traffic Stats section shows the most recent ``WaterfallSeries/defaultLimit`` requests
/// because forty bars is as many as fit legibly in a `List` section. This view model exists to
/// lift that ceiling: it lays out *every* request in the log on one axis, and pairs each bar back
/// with the request it was drawn from so tapping the bar can open it.
///
/// It holds the result rather than deriving it. A `LazyVStack` asks its rows for content
/// constantly while scrolling, so a computed `rows` would rebuild a thousand-entry series on
/// every frame; the layout is computed once per change to the log, on a detached task behind the
/// same debounce ``TrafficStatsViewModel`` uses, and published as a snapshot.
///
/// ## Usage
/// ```swift
/// let viewModel = WaterfallViewModel(requests: logs.requests)
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
        /// form the Traffic Stats chart already labels its axis with.
        let label: String

        /// The bar this row draws.
        let entry: WaterfallEntry

        /// The capture the bar was drawn from, which is what tapping the row opens.
        let request: HTTPRequest
    }

    /// A laid-out log: the shared axis and the rows on it.
    ///
    /// Returned as one value so the axis and the bars can never be published from two different
    /// snapshots — a bar measured against an axis it was not laid out on is drawn at the wrong
    /// length.
    struct Layout: Sendable {
        /// The series the rows were laid out on.
        let series: WaterfallSeries

        /// The rows, oldest first.
        let rows: [Row]

        /// Nothing laid out, used as the initial value and for a cleared log.
        static let empty = Layout(series: .empty, rows: [])
    }

    /// The rows, oldest first, so time reads downward.
    @Published private(set) var rows: [Row] = []

    /// The series the published rows were laid out on.
    @Published private(set) var series: WaterfallSeries = .empty

    /// The requests the page is drawing: the network log's filtered array.
    private(set) var requests: [HTTPRequest]

    /// Coalesces bursts of log updates into one layout pass.
    private let updateSubject = PassthroughSubject<Void, Never>()

    /// Retains the debounce subscription.
    private var cancellables = Set<AnyCancellable>()

    /// The task the current layout pass is running on.
    private var recomputeTask: Task<Void, Never>?

    /// Creates the view model.
    ///
    /// - Parameter requests: The requests to draw, usually the log's filtered array.
    init(requests: [HTTPRequest]) {
        self.requests = requests
        super.init()
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
                guard let self else { return }
                self.recomputeTask?.cancel()
                self.recomputeTask = Task { [weak self] in await self?.recompute() }
            }
            .store(in: &cancellables)
    }

    /// Lays the log out on first appearance.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await recompute()
    }

    /// Replaces the requests the page draws and schedules a debounced layout pass.
    ///
    /// - Parameter requests: The new filtered array.
    func update(requests: [HTTPRequest]) {
        self.requests = requests
        updateSubject.send(())
    }

    /// Lays the current requests out, off the main actor.
    ///
    /// Safe to call at any time; the axis and the rows are assigned back together, so the page is
    /// never drawn from two snapshots at once.
    func recompute() async {
        let snapshot = requests
        let computed = await Task.detached(priority: .userInitiated) {
            Self.layout(of: snapshot)
        }.value
        guard !Task.isCancelled else { return }
        series = computed.series
        rows = computed.rows
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
    ///   - now: The moment the layout describes, which is where a still-running bar ends.
    ///     Defaults to the current time; a test passes its own so the arithmetic is deterministic.
    /// - Returns: The axis and the rows on it, oldest first.
    nonisolated static func layout(of requests: [HTTPRequest], now: Date = Date()) -> Layout {
        guard !requests.isEmpty else { return .empty }
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
        return Layout(series: series, rows: rows)
    }

    // MARK: - Presentation

    /// Whether there is nothing to draw, which is what the page's empty state is for.
    var isEmpty: Bool { rows.isEmpty }

    /// The far end of the shared seconds axis.
    ///
    /// Computed by ``WaterfallChartStyle/upperBound(forSpan:)`` rather than by a rule of its own,
    /// so the same request is the same length on this page and in the Traffic Stats section.
    var upperBound: Double { WaterfallChartStyle.upperBound(forSpan: series.span) }

    /// The sentence under the bars explaining what the page is showing.
    var caption: String {
        localized("Every request in the log on a shared axis, oldest first. Bars that overlap were in flight at the same time.")
    }
}
