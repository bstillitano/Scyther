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
/// The section on **Traffic Stats** now draws the same whole-log overview this view model does —
/// see ``WaterfallOverviewStrip`` — but as one compressed strip with no per-request detail behind
/// it. This view model is what turns that strip into something a developer can actually work in:
/// it lays out *every* request the log is currently showing on one axis, and pairs each bar back
/// with the request it was drawn from so tapping the bar can open it.
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

    /// How much of the span the page opens with when it is reached by tapping the Traffic Stats
    /// strip.
    ///
    /// An eighth is wide enough to carry context around the moment tapped and narrow enough to be
    /// worth the navigation. Opening at the narrowest allowed window would be well defined and
    /// could land the developer inside a tenth of a second.
    static let openingWindowFraction: Double = 1.0 / 8.0

    /// One row of the page: a bar, the name beside it, and the capture behind it.
    ///
    /// The request is carried rather than looked up when the row is tapped. Matching a bar back
    /// to a capture by its label would land the reader on the wrong one of two calls to the same
    /// endpoint, and re-scanning the log per row would make drawing the page quadratic in the
    /// size of the log.
    struct Row: Identifiable, Sendable {
        /// The capture's own hash, so a row keeps its identity as newer traffic arrives above it.
        let id: String

        /// The row's position in the log and the bar's own label, `"1. GET /v1/users"`-shaped.
        ///
        /// Not what ``WaterfallDetailRow`` puts on screen — it reads ``entry``'s own `label`
        /// unnumbered instead, stacked under the host when the log holds more than one. This
        /// numbered form predates that row and nothing currently draws it.
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
        /// Cached with the rows rather than derived on demand, the same as ``shortestMeasured``: a
        /// `LazyVStack` asks this view model for its layout constantly, and resorting a thousand
        /// durations on every one of those asks would be wasted work for a value that only changes
        /// when the rows themselves do.
        let medianDuration: Double?

        /// The ``WaterfallDurations/tailPercentile`` measured duration, in seconds, or `nil` as
        /// above. Cached for the same reason.
        let tailDuration: Double?

        /// The shortest finished, non-zero duration in the series, or `nil` when nothing
        /// finished.
        ///
        /// Cached beside the median and the tail, and for the same reason: it is an input to the
        /// zoom limit, the view recomputes that whenever its geometry changes, and a `List` asks
        /// for geometry constantly.
        let shortestMeasured: Double?

        /// Whether the rows hold more than one distinct, non-empty host.
        ///
        /// Cached with the rows for the same reason as the durations above: the detail list reads
        /// this once per row it builds, and counting distinct hosts across every row on every one
        /// of those reads would make an O(rows) check happen O(rows) times.
        ///
        /// `false` — not shown — with one host or none, where the host is pure noise repeated on
        /// every row; `true` the moment a second distinct host appears, where it becomes the one
        /// thing that tells two rows apart. See ``WaterfallDetailRow`` in `WaterfallView.swift`.
        let showsHost: Bool

        /// Nothing laid out.
        static let empty = Layout(series: .empty, rows: [], count: 0, total: 0,
                                  medianDuration: nil, tailDuration: nil, shortestMeasured: nil,
                                  showsHost: false)
    }

    /// The laid-out log the page is drawing.
    @Published private(set) var layout: Layout = .empty

    /// The slice of the log the page is showing.
    ///
    /// Published rather than derived so the strip's overlay and the detail list are always
    /// drawing the same window: two views deriving it separately is two views one layout pass
    /// apart from disagreeing.
    @Published private(set) var window: WaterfallWindow = WaterfallWindow(span: 0, narrowest: 0)

    /// The width the detail list gives a bar, from the last ``configureWindow(plotWidth:)``.
    private var plotWidth: CGFloat = WaterfallChartStyle.minimumPlotWidth

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
    /// The window is configured here too, for the same reason: ``onFirstAppear()`` runs its
    /// asynchronous first ``recompute()`` *after* the page's first body render, so without this
    /// the first frame would read ``window`` at its zero-valued default — an empty
    /// ``visibleRows`` and ``isWindowEmpty`` `true` — over a `layout` that is already full. That
    /// is the same flash the synchronous layout pass above exists to prevent, just one property
    /// later.
    ///
    /// `openingTime` is applied here, after both, rather than by the view in an `.onAppear` — see
    /// ``WaterfallView/init(logs:openingTime:)``. Taking it as an initialiser parameter rather
    /// than a method the view calls afterwards matters beyond the ruling that asks for it: this
    /// type is built inside `@StateObject`'s `wrappedValue` autoclosure, which SwiftUI evaluates
    /// lazily, exactly once, only once the view is actually inserted into the tree. A caller that
    /// built the instance eagerly and called `open(centredOn:)` on it afterwards — the way this
    /// view model used to be constructed by the view that owns it — would have forced that
    /// autoclosure to run early, paying for this initialiser's synchronous whole-log layout on
    /// every body evaluation of a view that merely *might* push this page, not only the one that
    /// does.
    ///
    /// - Parameters:
    ///   - requests: The requests to draw, usually the log's filtered array.
    ///   - totalCount: How many requests the log holds unfiltered.
    ///   - openingTime: Seconds from the log's earliest request to open the window centred on, or
    ///     `nil` to open at the full span. See ``open(centredOn:)``.
    init(requests: [HTTPRequest], totalCount: Int, openingTime: TimeInterval? = nil) {
        self.requests = requests
        self.totalCount = totalCount
        super.init()
        layout = Self.layout(of: requests, totalCount: totalCount)
        configureWindow(plotWidth: plotWidth)
        if let openingTime {
            open(centredOn: openingTime)
        }
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
    /// never drawn from two snapshots at once. The window is re-derived against the new series
    /// afterwards, so a log that grew or shrank never leaves the published window describing a
    /// span that no longer exists.
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
        configureWindow(plotWidth: plotWidth)
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
                          medianDuration: nil, tailDuration: nil, shortestMeasured: nil,
                          showsHost: false)
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
        let durations = WaterfallDurations.measuredDurations(of: series)
        let shortestMeasured = durations.filter { $0 > 0 }.min()
        let distinctHosts = Set(series.entries.map(\.shortHost).filter { !$0.isEmpty })
        return Layout(
            series: series,
            rows: rows,
            count: requests.count,
            total: totalCount,
            medianDuration: WaterfallDurations.percentile(0.5, of: durations),
            tailDuration: WaterfallDurations.percentile(WaterfallDurations.tailPercentile, of: durations),
            shortestMeasured: shortestMeasured,
            showsHost: distinctHosts.count > 1
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

    /// Whether the detail list's rows should draw their host.
    ///
    /// True only past a second distinct host: against one host it is noise repeated on every
    /// row, and worse, it crowds out the path — the one thing that actually tells two rows to
    /// the same host apart, and truncation gives the path what little room the row has left only
    /// when the host is not drawn at all.
    var showsHost: Bool { layout.showsHost }

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

    // MARK: - The window

    /// The rows the window holds, oldest first.
    ///
    /// Intersection rather than containment, so a request already in flight when the window opens
    /// is shown clipped rather than missing. See ``WaterfallWindow/contains(start:duration:)``.
    var visibleRows: [Row] {
        layout.rows.filter { window.contains(start: $0.entry.start, duration: $0.entry.duration) }
    }

    /// Whether the window is over a stretch of the log with no traffic in it.
    ///
    /// Distinct from an empty log, which the page answers with its `ContentUnavailableView`. This
    /// one earns a row saying so, because a blank list after a drag reads as a bug.
    var isWindowEmpty: Bool { !layout.rows.isEmpty && visibleRows.isEmpty }

    /// Recomputes the zoom limits for a plot of `plotWidth`, keeping the current centre wherever
    /// the new limits leave room to.
    ///
    /// Called whenever the list's geometry changes. Keeping the centre matters because a rotation
    /// or a Dynamic Type change re-measures the plot, and throwing the developer back to the
    /// start of the log because the row got narrower would be its own bug.
    ///
    /// Near an edge — or when the re-measure raises ``WaterfallWindow/narrowest`` *above* the
    /// current duration, which a widened plot does — it cannot be held exactly: the duration has
    /// to grow to the new floor, and holding the *old* start while doing that would shift the
    /// centre by half of whatever the duration was forced to grow. So the duration is clamped to
    /// the new limits first, and only then is the window moved back to the old centre — the same
    /// two-step ``WaterfallWindow/movedToCentre(_:)`` already uses internally, applied here across
    /// a change in limits rather than a change in time.
    ///
    /// - Parameter plotWidth: The width a bar is drawn across, in points.
    func configureWindow(plotWidth: CGFloat) {
        self.plotWidth = max(WaterfallChartStyle.minimumPlotWidth, plotWidth)
        let span = layout.series.span
        let narrowest = WaterfallWindow.narrowestDuration(
            shortestMeasured: layout.shortestMeasured,
            span: span,
            plotWidth: self.plotWidth
        )
        let previousCentre = window.span > 0 ? window.centre : span / 2
        let previousDuration = window.span > 0 ? window.duration : span
        let candidate = WaterfallWindow(start: 0, duration: previousDuration, span: span,
                                        narrowest: narrowest)
        window = candidate.movedToCentre(previousCentre)
    }

    /// Magnifies the window, holding its centre.
    ///
    /// - Parameter factor: The pinch's magnitude. Above 1 zooms in.
    func zoom(by factor: Double) {
        guard window.canZoom else { return }
        window = window.zoomed(by: factor)
    }

    /// Moves the window's centre to `time`.
    ///
    /// - Parameter time: Seconds from the series origin.
    func scrub(to time: TimeInterval) {
        window = window.movedToCentre(time)
    }

    /// Opens the window at ``openingWindowFraction`` of the span, centred on `time`.
    ///
    /// - Parameter time: Seconds from the series origin.
    func open(centredOn time: TimeInterval) {
        let span = layout.series.span
        guard span > 0 else { return }
        window = window.centred(on: time, duration: span * Self.openingWindowFraction)
    }

    /// What the page says under the list about what is on screen.
    ///
    /// Against ``layout``'s *filtered* count, not its unfiltered `total`: the window is a slice of
    /// the rows the page is actually drawing, which under an active filter is already a slice of
    /// the log. Comparing `visibleRows` to `total` mixed a filtered numerator with an unfiltered
    /// denominator and could read "5 of 340" for a window over a dozen-request filtered list — the
    /// same "count against the wrong total" mistake ``caption`` was written to avoid.
    var windowCaption: String {
        localized("\(visibleRows.count) of \(layout.count) requests")
    }
}
