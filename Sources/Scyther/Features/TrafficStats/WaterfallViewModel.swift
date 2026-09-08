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
/// The section on **Traffic Stats** draws a small preview of the same idea — see
/// ``WaterfallOverviewStrip`` and `TrafficStatsViewModel.recentLayout` — a strip zoomed to the
/// most recent handful of requests with a few tappable rows beneath it, rather than the whole log
/// this view model lays out. The two share ``layout(of:limit:totalCount:now:)``, called with a
/// different `limit`, not a second implementation: see that function's own documentation. This
/// view model is what turns the full-log strip into something a developer can actually work in:
/// it lays out *every* request the log is currently showing on one axis, and pairs each bar back
/// with the request it was drawn from so tapping the bar can open it.
///
/// It holds the result rather than deriving it. A `List` asks its rows for content constantly
/// while scrolling, so a computed ``Layout/rows`` would rebuild a thousand-entry series on every
/// frame; the layout is computed once per change to the log, on a detached task behind the same
/// debounce ``TrafficStatsViewModel`` uses, and published as a single value. ``visibleRows`` is
/// cached the same way, on top of it, for the window rather than the whole log — see its own
/// documentation.
///
/// ## Usage
/// ```swift
/// let viewModel = WaterfallViewModel(requests: logs.requests, totalCount: logs.totalRequestCount)
/// await viewModel.recompute()
/// viewModel.visibleRows.first?.request   // the capture behind the topmost bar in the window
/// ```
final class WaterfallViewModel: ViewModel {

    /// How long the page waits after the log changes before laying it out again.
    ///
    /// Matches ``TrafficStatsViewModel/recomputeDebounce``, because the page is reached from that
    /// screen and follows the same log: coalescing on a different rhythm would have the two
    /// disagree about how much traffic there is for up to half a second at a time.
    static let recomputeDebounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

    /// How much of the span the window opens with when a caller of ``open(centredOn:)`` lands the
    /// page already centred on a specific moment, rather than at the full span. No caller within
    /// this module currently does this — see ``open(centredOn:)``'s own documentation — but the
    /// figure is kept rather than the function, for whichever caller reaches for it next.
    ///
    /// An eighth is wide enough to carry context around the moment given and narrow enough to be
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

        /// The shortest finished, non-zero duration in the series, or `nil` when nothing
        /// finished.
        ///
        /// Cached with the rows rather than derived on demand: it is an input to the zoom limit,
        /// the view recomputes that whenever its geometry changes, and a `List` asks for geometry
        /// constantly.
        let shortestMeasured: Double?

        /// Whether the rows hold more than one distinct, non-empty host.
        ///
        /// Cached with the rows for the same reason ``shortestMeasured`` is: the detail list reads
        /// this once per row it builds, and counting distinct hosts across every row on every one
        /// of those reads would make an O(rows) check happen O(rows) times.
        ///
        /// `false` — not shown — with one host or none, where the host is pure noise repeated on
        /// every row; `true` the moment a second distinct host appears, where it becomes the one
        /// thing that tells two rows apart. See ``WaterfallDetailRow`` in `WaterfallView.swift`.
        let showsHost: Bool

        /// Nothing laid out.
        static let empty = Layout(series: .empty, rows: [], count: 0, total: 0,
                                  shortestMeasured: nil, showsHost: false)
    }

    /// The laid-out log the page is drawing.
    ///
    /// `didSet` recomputes ``visibleRows``'s cache: see ``refreshVisibleRows()`` for why that has
    /// to happen here rather than being left for the next read.
    @Published private(set) var layout: Layout = .empty {
        didSet { refreshVisibleRows() }
    }

    /// The slice of the log the page is showing.
    ///
    /// Published rather than derived so the strip's overlay and the detail list are always
    /// drawing the same window: two views deriving it separately is two views one layout pass
    /// apart from disagreeing.
    ///
    /// `didSet` recomputes ``visibleRows``'s cache, the same as ``layout``'s does — see
    /// ``refreshVisibleRows()``.
    @Published private(set) var window: WaterfallWindow = WaterfallWindow(span: 0, narrowest: 0) {
        didSet { refreshVisibleRows() }
    }

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
        layout = Self.layout(of: requests, limit: requests.count, totalCount: totalCount)
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
            Self.layout(of: snapshot, limit: snapshot.count, totalCount: snapshotTotal)
        }.value
        guard !Task.isCancelled else { return }
        layout = computed
        configureWindow(plotWidth: plotWidth)
    }

    /// Lays out the most recent `limit` of `requests` on one shared axis.
    ///
    /// Pure and `nonisolated` so it can run on a detached task and be measured by a test without
    /// building a view. The pairing back to captures is done through a hash-keyed dictionary in
    /// the same pass: the obvious alternative — each row searching the log for its own request —
    /// is quadratic, and a log holding thousands of entries is exactly the case this page was
    /// built for.
    ///
    /// `limit` has no default, matching ``WaterfallSeries/build(from:limit:now:)``'s own — see
    /// that function's documentation for why a fixed figure could never stand in for it. This
    /// function has two callers now with two different answers: ``WaterfallView`` still wants
    /// everything, and passes `requests.count`; `TrafficStatsViewModel` wants only
    /// ``TrafficStatsViewModel/recentWaterfallCount``, so it can draw a small preview whose bars
    /// are legible rather than the whole log flattened to specks. Neither caller's choice belongs
    /// to this function, which is exactly why it takes a parameter instead of a policy.
    ///
    /// - Parameters:
    ///   - requests: The captures to lay out, in any order.
    ///   - limit: How many of the most recent (by request date) to keep. See
    ///     ``WaterfallSeries/build(from:limit:now:)``'s own `limit` for the exact rule, including
    ///     what happens when `requests` holds fewer than this many.
    ///   - totalCount: How many requests the log holds unfiltered, carried through for the
    ///     caption.
    ///   - now: The moment the layout describes, which is where a still-running bar ends.
    ///     Defaults to the current time; a test passes its own so the arithmetic is deterministic.
    /// - Returns: The axis, the rows on it, and the counts they describe.
    nonisolated static func layout(
        of requests: [HTTPRequest],
        limit: Int,
        totalCount: Int = 0,
        now: Date = Date()
    ) -> Layout {
        guard !requests.isEmpty else {
            return Layout(series: .empty, rows: [], count: 0, total: totalCount,
                          shortestMeasured: nil, showsHost: false)
        }
        let series = WaterfallSeries.build(from: requests, limit: limit, now: now)
        var byHash = [String: HTTPRequest](minimumCapacity: requests.count)
        for request in requests {
            byHash[request.getRandomHash() as String] = request
        }
        let rows = series.entries.compactMap { entry -> Row? in
            guard let request = byHash[entry.id] else { return nil }
            return Row(id: entry.id, entry: entry, request: request)
        }
        let durations = WaterfallDurations.measuredDurations(of: series)
        let shortestMeasured = durations.filter { $0 > 0 }.min()
        let distinctHosts = Set(series.entries.map(\.shortHost).filter { !$0.isEmpty })
        return Layout(
            series: series,
            rows: rows,
            // `rows.count`, not `requests.count`: the two agreed exactly as long as every caller
            // passed `limit: requests.count` and no capture lacked a start date, which was every
            // caller until `TrafficStatsViewModel` started passing a genuine limit. `count` is
            // documented as "how many requests the rows were laid out from" — once `limit` can
            // truncate the input, `requests.count` stops answering that question and `rows.count`
            // is what actually does, in both the truncated and the untruncated case alike.
            count: rows.count,
            total: totalCount,
            shortestMeasured: shortestMeasured,
            showsHost: distinctHosts.count > 1
        )
    }

    // MARK: - Presentation

    /// The series the published rows were laid out on.
    var series: WaterfallSeries { layout.series }

    /// Whether there is nothing to draw, which is what the page's empty state is for.
    var isEmpty: Bool { layout.rows.isEmpty }

    /// Whether the detail list's rows should draw their host.
    ///
    /// True only past a second distinct host: against one host it is noise repeated on every
    /// row, and worse, it crowds out the path — the one thing that actually tells two rows to
    /// the same host apart, and truncation gives the path what little room the row has left only
    /// when the host is not drawn at all.
    var showsHost: Bool { layout.showsHost }

    // MARK: - The window

    /// The rows the window holds, oldest first, cached rather than filtered on every read.
    ///
    /// Reading this used to run `layout.rows.filter { window.contains(...) } }` fresh each time —
    /// an uncached `O(rows)` pass with its own allocation. `window` is `@Published`, so a pinch or
    /// a drag re-evaluates ``WaterfallView``'s `body` on every frame the gesture reports, and that
    /// body reads this property four times — the strip's window overlay, `isWindowEmpty`, the
    /// `ForEach`, and `windowCaption`'s count — so one frame of a gesture over the 5,000 requests
    /// the design names as the reason the strip is a `Canvas` cost four full passes and four
    /// allocations. See ``refreshVisibleRows()`` for where the cache is kept in step; this is the
    /// same reasoning ``Layout``'s own cached ``Layout/shortestMeasured`` was written from — a
    /// value a `List` or a gesture reads constantly should not be recomputed on every one of those
    /// reads.
    ///
    /// Intersection rather than containment, so a request already in flight when the window opens
    /// is shown clipped rather than missing. See ``WaterfallWindow/contains(start:duration:)``.
    private(set) var visibleRows: [Row] = []

    /// Recomputes ``visibleRows``'s cache against the current ``layout`` and ``window``.
    ///
    /// Called from both properties' `didSet`, which is what makes the cache correct rather than
    /// merely fast: a cache invalidated by hand at each call site is a cache one future call site
    /// forgets to invalidate. Filtering here, eagerly, on the far less frequent event of one of
    /// the two inputs actually changing, is what lets every other read of ``visibleRows`` be a
    /// property access instead of a pass over ``Layout/rows``.
    private func refreshVisibleRows() {
        visibleRows = layout.rows.filter { window.contains(start: $0.entry.start, duration: $0.entry.duration) }
    }

    /// Whether the window is over a stretch of the log with no traffic in it.
    ///
    /// Distinct from an empty log, which the page answers with its `ContentUnavailableView`. This
    /// one earns a row saying so, because a blank list after a drag reads as a bug.
    var isWindowEmpty: Bool { !layout.rows.isEmpty && visibleRows.isEmpty }

    /// Whether the window has been zoomed or scrubbed away from wherever it opened, for
    /// ``WaterfallView``'s own minimap header: the reset-zoom button once this is `true`, and the
    /// pinch-discoverability hint — see `WaterfallView.minimapHeader`'s own documentation — for as
    /// long as it is `false`. The two read the same flag rather than one apiece on purpose: they
    /// are exact inverses of the same fact, "has the developer ever touched this window," and a
    /// second flag could only ever disagree with this one by a bug, never usefully.
    ///
    /// `false` from construction, `true` from the first call to ``zoom(by:)`` or ``scrub(to:)``,
    /// and `false` again only once ``resetWindow()`` is called — the owner's own specification,
    /// verbatim: the button "doesn't need to go away until the users presses it, i.e. if the user
    /// zooms to the default zoom, without pressing the button, it can stay." That is a claim a
    /// computed comparison against the opening window cannot make honestly: a window that has
    /// drifted back to numerically match ``WaterfallWindow/opening(span:narrowest:)`` — entirely
    /// possible after a zoom out, or several zooms that cancel out — is still a window the reader
    /// *chose*, not one they are still looking at by default, and the button's whole job is to
    /// mark that distinction. Only an explicit flag, set once and cleared once, can tell "adjusted,
    /// currently equal to the default" apart from "never adjusted at all" — a stored fact about
    /// history, not a property of the window's current value.
    ///
    /// - Note: `open(centredOn:)` — which lands the page already centred on a specific moment for
    ///   a caller that wants that, currently none within this module — deliberately does *not* set
    ///   this. The owner named `zoom(by:)` and `scrub(to:)` specifically, and `open(centredOn:)` is not the
    ///   developer adjusting a window they are already looking at; it is how the window the page
    ///   opens with was chosen in the first place, for that one entrance. Showing "reset zoom" the
    ///   instant a reader arrives at a page they explicitly navigated to a moment on, before they
    ///   have touched anything, would flag a change they never made.
    ///
    /// Distinct from ``windowFollowsDefault``, which tracks a different question — whether
    /// ``configureWindow(plotWidth:)`` should keep recomputing the window against fresh geometry —
    /// and which does flip back conceptually in the sense that ``resetWindow()`` sets it back to
    /// `true`. The two happen to change together at every call site that touches either, but they
    /// answer different questions for different readers: ``windowFollowsDefault`` is this type's
    /// own internal bookkeeping, `private`; this property is public precisely because a view needs
    /// to read it.
    @Published private(set) var hasAdjustedWindow = false

    /// Whether ``window`` is still following ``WaterfallWindow/opening(span:narrowest:)``
    /// rather than a position or size the developer — or a caller of ``open(centredOn:)`` — chose.
    ///
    /// `true` from construction until the first call to ``zoom(by:)``, ``scrub(to:)`` or
    /// ``open(centredOn:)`` that actually changes something, and `false` for the rest of this
    /// instance's life after that. While it is `true`, ``configureWindow(plotWidth:)`` keeps
    /// recomputing the opening window fresh against whatever geometry it is called with, rather
    /// than preserving the previous one — which is what corrects for `init`'s own first call
    /// having opened the window against ``plotWidth``'s placeholder default
    /// (``WaterfallChartStyle/minimumPlotWidth``, set before ``WaterfallView``'s `GeometryReader`
    /// has measured anything) once its `.onAppear` supplies the real, measured width moments
    /// later. It also means a page left open while more traffic streams in keeps tracking the
    /// tail of the log — the same "anchored on the newest traffic" promise the opening window
    /// makes, just re-applied on every recomputation rather than only the first one — for exactly
    /// as long as nobody has touched it.
    ///
    /// Once it flips to `false` it never flips back: a window the developer has zoomed, dragged,
    /// or that a caller of ``open(centredOn:)`` opened already centred on a moment must not be
    /// silently replaced by "the newest traffic" again just because Dynamic Type changed or the
    /// device rotated — the same guarantee ``configureWindow(plotWidth:)`` always made for a
    /// *zoomed* window, extended here to cover the window's position too, now that opening can
    /// narrow it.
    private var windowFollowsDefault = true

    /// Recomputes the window for a plot of `plotWidth`.
    ///
    /// Called whenever the list's geometry changes, and once from `init` before the real geometry
    /// is known at all — see ``windowFollowsDefault``. What it does with the new limits depends on
    /// whether the window is still following the default:
    ///
    /// - **Still following it** (``windowFollowsDefault`` is `true`): the window is rebuilt from
    ///   scratch via ``WaterfallWindow/opening(span:narrowest:)`` against the current layout and
    ///   geometry. This is what lets the placeholder-width window `init`
    ///   opens with self-correct once the real plot width arrives, and what lets an untouched page
    ///   keep tracking new traffic as it streams in.
    /// - **Already held** (`false`): the centre is kept wherever the new limits leave room to,
    ///   the same behaviour this method always had. Keeping the centre matters because a rotation
    ///   or a Dynamic Type change re-measures the plot, and throwing the developer back to
    ///   wherever they were away from because the row got narrower would be its own bug. Near an
    ///   edge — or when the re-measure raises ``WaterfallWindow/narrowest`` *above* the current
    ///   duration, which a widened plot does — the centre cannot be held exactly: the duration has
    ///   to grow to the new floor, and holding the *old* start while doing that would shift the
    ///   centre by half of whatever the duration was forced to grow. So the duration is clamped to
    ///   the new limits first, and only then is the window moved back to the old centre — the same
    ///   two-step ``WaterfallWindow/movedToCentre(_:)`` already uses internally, applied here
    ///   across a change in limits rather than a change in time.
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
        guard !windowFollowsDefault else {
            window = WaterfallWindow.opening(span: span, narrowest: narrowest)
            return
        }
        let candidate = WaterfallWindow(start: 0, duration: window.duration, span: span,
                                        narrowest: narrowest)
        window = candidate.movedToCentre(window.centre)
    }

    /// Magnifies the window, holding its centre, and marks it as held — see
    /// ``windowFollowsDefault`` — and as adjusted — see ``hasAdjustedWindow``.
    ///
    /// - Parameter factor: The pinch's magnitude. Above 1 zooms in.
    func zoom(by factor: Double) {
        guard window.canZoom else { return }
        window = window.zoomed(by: factor)
        windowFollowsDefault = false
        hasAdjustedWindow = true
    }

    /// Moves the window's centre to `time`, and marks it as held — see ``windowFollowsDefault`` —
    /// and as adjusted — see ``hasAdjustedWindow``.
    ///
    /// - Parameter time: Seconds from the series origin.
    func scrub(to time: TimeInterval) {
        window = window.movedToCentre(time)
        windowFollowsDefault = false
        hasAdjustedWindow = true
    }

    /// Returns the window to the page's own default: anchored on the most recent traffic, at
    /// ``WaterfallWindow/opening(span:narrowest:)`` — the same window the page opens with, and
    /// the same window an untouched page keeps tracking as new traffic streams in.
    ///
    /// Two buttons call this, and it is one definition of "back to normal" for both rather than
    /// two: ``WaterfallView``'s gap empty state, and its reset-zoom section header button. Zooming
    /// or scrubbing into a stretch of the log with nothing in it leaves the developer looking at a
    /// blank list with no bars left to drag by — see ``isWindowEmpty`` — and that is the first
    /// button's way out. The second is the more general case ``hasAdjustedWindow`` exists for: any
    /// zoom or scrub at all, gap or not. Returning to the opening default rather than jumping
    /// straight to the widest possible window (the whole span) is deliberate: the whole span is
    /// still one pinch-out away from there, and "the most recent traffic" answers the more common
    /// reason a developer reaches for either button — a drag or a zoom that overshot what they
    /// actually wanted — without discarding the zoom level they had chosen for a flattened view of
    /// the entire session.
    ///
    /// Reusing ``configureWindow(plotWidth:)`` rather than duplicating its arithmetic here is what
    /// keeps this in step with a future change to the opening rule automatically: there is exactly
    /// one place that computes "the window the page opens with," and both the first frame and both
    /// buttons read it.
    ///
    /// Marks the window as following the default again — see ``windowFollowsDefault`` — rather
    /// than only computing the same window once: without that flip, the very next geometry change
    /// (a rotation, a Dynamic Type change) would hold this position instead of continuing to track
    /// new traffic the way an untouched page does, and the buttons' promise — "back to where an
    /// untouched page would be" — would only hold for one frame. Also the one place
    /// ``hasAdjustedWindow`` is cleared: see that property's own documentation for why nothing
    /// short of this call — not a zoom or a scrub that happens to land back on the same numbers —
    /// is allowed to clear it.
    func resetWindow() {
        windowFollowsDefault = true
        hasAdjustedWindow = false
        configureWindow(plotWidth: plotWidth)
    }

    /// Opens the window at ``openingWindowFraction`` of the span, centred on `time`, and marks it
    /// as held — see ``windowFollowsDefault``. Without this, ``WaterfallView``'s own `.onAppear`
    /// call to ``configureWindow(plotWidth:)`` — which runs after this, once the real plot width
    /// is measured — would discard the tapped position in favour of the newest-traffic default.
    ///
    /// - Parameter time: Seconds from ``series``'s own origin — this instance's, not necessarily
    ///   whichever series `time` was originally measured against. See
    ///   ``WaterfallView/init(logs:openingTime:)`` for the caller that would cross that boundary,
    ///   currently none within this module, and the bound that crossing accepts.
    func open(centredOn time: TimeInterval) {
        let span = layout.series.span
        guard span > 0 else { return }
        window = window.centred(on: time, duration: span * Self.openingWindowFraction)
        windowFollowsDefault = false
    }

    /// What the page says under the list about what is on screen.
    ///
    /// Against ``layout``'s *filtered* count, not its unfiltered `total`: the window is a slice of
    /// the rows the page is actually drawing, which under an active filter is already a slice of
    /// the log. Comparing `visibleRows` to `total` mixed a filtered numerator with an unfiltered
    /// denominator and could read "5 of 340" for a window over a dozen-request filtered list —
    /// the count against the wrong total the page's own caption on ``TrafficStatsViewModel`` is
    /// written to avoid making, and the same mistake this line exists to rule out here.
    var windowCaption: String {
        localized("\(visibleRows.count) of \(layout.count) requests")
    }
}
