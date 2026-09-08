//
//  WaterfallView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Charts
import SwiftUI

/// Every logged request as a bar on one shared time axis, oldest at the top, seen through a
/// window the reader zooms and drags rather than scrolls.
///
/// Reached from the Waterfall section of ``TrafficStatsView`` two ways: the **See all** link opens
/// at the full span, and a tap on the section's own overview strip opens centred on the moment
/// touched — see ``init(logs:openingTime:)``. Either way it shows the same session that section's
/// strip already compresses — literally the same strip, ``WaterfallOverviewStrip``, drawing from
/// the same ``WaterfallChartStyle`` colours, now carrying the current window as well — but with
/// every request its own tappable row in a detail list underneath, leading to the capture behind
/// it, which the section has no equivalent of at all.
///
/// ## Why a window rather than a scroll
///
/// The page used to fit the session into one screen width and only scroll vertically, then — when
/// that made every bar in a long session collapse to the same one-point floor — grew a plot tens
/// of thousands of points wide with a frozen label column and a ruler pinned inside a two-axis
/// `ScrollView`, the way Chrome's network panel and Charles both behave. Both of those are a
/// *scroll* answer to what is really a *zoom* problem: a reader does not want to pan across five
/// minutes of quiet network to find the one burst that mattered, and a plot wide enough to give a
/// twenty-millisecond request room next to a three-second one is wide enough that panning it by
/// hand is its own chore.
///
/// So the page shows two things instead. ``WaterfallOverviewStrip`` compresses the *entire* log
/// into one short band and marks the current window on it — a drag on the strip moves the window
/// anywhere in the log in one gesture, which no amount of panning a wide plot could do. Beneath
/// it, the detail list holds only the requests that window contains: a `List` of `NavigationLink`
/// rows rather than a `LazyVStack` of hand-laid-out rectangles, because this is a menu screen and
/// a bar without a row to sit in cannot happen — see ``WaterfallViewModel/visibleRows``. Zoom
/// narrows the window with a pinch, described below.
///
/// - Important: `.accessibilityAdjustableAction` on the strip is what keeps zoom reachable without
///   a pinch. VoiceOver and Switch Control users get the same range a sighted reader's fingers do;
///   the toolkit does not get to ship an accessibility audit feature one release and a
///   gesture-only control the next.
///
/// ## Usage
/// ```swift
/// NavigationLink(localized("See all")) {
///     WaterfallView(logs: logs)
/// }
/// NavigationLink(isActive: $isActive) {
///     WaterfallView(logs: logs, openingTime: openingTime)
/// } label: { EmptyView() }
/// ```
struct WaterfallView: View {
    /// The network log this page is drawing. Its filtered array is the input, so the page follows
    /// the log's search and filter chips the way the rest of the stats screen does.
    @ObservedObject private var logs: NetworkLogsViewModel

    /// The page's own view model, which owns the laid-out log and the current time window.
    @StateObject private var viewModel: WaterfallViewModel

    /// The detail row's label column, scaled against the reader's text size, before
    /// ``WaterfallDetailRowMetrics`` decides whether the row still has room to draw it at that
    /// width. See ``WaterfallChartStyle/detailLabelWidth``.
    ///
    /// Owned here rather than by `WaterfallDetailRow` itself — which is where it lived before this
    /// fix — because ``rowLayout(in:)`` needs the exact same scaled number `WaterfallDetailRow`
    /// draws its column at. A `@ScaledMetric` in the row and the unscaled `WaterfallChartStyle`
    /// constant the page's old `plotWidth(in:)` function subtracted were free to disagree the
    /// moment either one changed independently, and that disagreement is exactly the defect this
    /// fix exists to close. Hoisting both `@ScaledMetric`s here and
    /// passing the results down to `WaterfallDetailRow` as plain `let` properties makes the two
    /// uses read the same property, so they cannot drift again without deleting this one. Reading
    /// it from the parent rather than the child costs nothing extra: `@ScaledMetric` resolves from
    /// the environment, which a view and its children already share, so the value is identical
    /// either way — only which type declares the property differs.
    @ScaledMetric(relativeTo: .caption) private var scaledLabelWidth: CGFloat = WaterfallChartStyle.detailLabelWidth

    /// The detail row's duration column, scaled against the reader's text size, for the same
    /// reason and in the same way ``scaledLabelWidth`` is. See
    /// ``WaterfallChartStyle/detailDurationWidth``.
    @ScaledMetric(relativeTo: .caption) private var scaledDurationWidth: CGFloat = WaterfallChartStyle.detailDurationWidth

    /// The reader's current Dynamic Type setting, watched only so ``detail`` can recompute the
    /// zoom limit when it changes while the page is already open.
    ///
    /// `@ScaledMetric` itself already keeps ``scaledLabelWidth`` and ``scaledDurationWidth`` — and
    /// therefore what `WaterfallDetailRow` actually draws — correct on every body evaluation,
    /// because SwiftUI re-evaluates a view's body whenever an environment value one of its
    /// property wrappers reads changes. What does *not* happen automatically is
    /// ``WaterfallViewModel/configureWindow(plotWidth:)`` running again: it is called from
    /// `.onAppear` and from `.onChange(of: proxy.size.width)`, neither of which fires just because
    /// the *columns'* width changed while the row's own outer width did not. Without this, opening
    /// the page, then changing text size in Settings and returning to it, would leave the zoom
    /// limit computed against the previous text size until the next rotation or resize happened to
    /// trigger a recompute.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The magnification the pinch gesture last reported, so each change applies only the delta
    /// since the previous callback rather than the whole gesture again.
    ///
    /// `MagnificationGesture` reports magnitude relative to where the pinch *started*, not to the
    /// last callback. Feeding that straight to ``WaterfallViewModel/zoom(by:)`` would reapply the
    /// entire pinch on every frame the gesture reports and slam the window into its zoom limit on
    /// the first frame of motion.
    ///
    /// A plain `@State` now, not `@GestureState`. It used to be `@GestureState`, driven from
    /// `.updating(_:body:)`, specifically to survive a pinch the enclosing `List` claimed
    /// mid-gesture — before this fix, ``detail`` attached the gesture with plain `.gesture(_:)`,
    /// SwiftUI's *lowest* priority, so the `List`'s own pan recogniser routinely won the sequence
    /// outright and the pinch's `onEnded` never ran; a `@State` reset only there would have been
    /// left stranded at whatever magnitude the pinch last reported, corrupting the next pinch's
    /// first delta. `@GestureState` avoided that because SwiftUI resets it whenever the gesture
    /// ends *or is cancelled*, with no `onEnded` required.
    ///
    /// That risk is gone now that ``magnification`` is attached with
    /// `.simultaneousGesture(_:including:)` instead: the pinch no longer has to wait for the
    /// `List`'s own gesture to fail before it can recognise, so it is tracked to completion
    /// independently, and `onEnded` — which resets this back to `1` explicitly, below — is
    /// reliably the last callback SwiftUI sends for any pinch that recognises at all. With that
    /// guarantee back, `.updating(_:body:)` stops being the safer choice and starts being the
    /// worse one: its closure is documented as updating only the transient gesture-state property
    /// it is attached to, because it runs as part of the gesture's own transaction rather than an
    /// ordinary event callback, and can be invoked, retried or coalesced as SwiftUI applies that
    /// transaction. Calling ``WaterfallViewModel/zoom(by:)`` from inside it — a write to a
    /// `@Published` property, which schedules `objectWillChange` and a body re-evaluation — is a
    /// side effect exactly of the kind that closure is supposed to be free of, and is the known
    /// shape of SwiftUI's "publishing changes from within view updates" warning. `.onChanged`
    /// runs as an ordinary callback instead, so the same mutation runs on the same footing every
    /// other change to ``WaterfallViewModel`` in this file does.
    @State private var lastMagnification: CGFloat = 1

    /// Creates the page.
    ///
    /// `openingTime` is forwarded straight into
    /// ``WaterfallViewModel/init(requests:totalCount:openingTime:)`` rather than applied here
    /// afterwards, and that is not a stylistic choice: `_viewModel` is a `@StateObject`, whose
    /// `wrappedValue` is an `@autoclosure` SwiftUI evaluates lazily, exactly once, only when the
    /// view is actually inserted into the tree. Building the instance eagerly in this initialiser
    /// and calling `open(centredOn:)` on it afterwards — which is what an earlier version of this
    /// did — forces that autoclosure to run on *every* construction of a `WaterfallView` value,
    /// which for the hidden link and the **See all** link together is twice per body evaluation of
    /// the section that owns them, whether or not either page is ever pushed. The view model's own
    /// initialiser already lays the whole log out synchronously — see ``WaterfallViewModel``'s own
    /// documentation on why — so paying for that eagerly, twice, on a screen that merely offers the
    /// page rather than shows it, is the cost `@StateObject` exists to defer.
    ///
    /// - Parameters:
    ///   - logs: The network log view model whose filtered requests are drawn.
    ///   - openingTime: Seconds from the log's earliest request, when the page is reached by
    ///     tapping a moment on the Traffic Stats section's overview strip. The window opens
    ///     already centred there instead of at the full span, which is what `nil` — the **See
    ///     all** link's default — leaves it at.
    ///
    ///     Measured against ``TrafficStatsViewModel/waterfall``'s origin — the strip that was
    ///     tapped — and reapplied here against this page's own, separately built
    ///     ``WaterfallViewModel/series``'s origin, on the assumption the two agree. They almost
    ///     always do: both are built from the same log, moments apart, and an origin only moves
    ///     when the log's *oldest* surviving request changes, which navigating to this page does
    ///     not itself cause. What the two builds do *not* share is `now` — each call to
    ///     `WaterfallSeries.build(from:limit:now:)` defaults it independently, at whatever instant
    ///     that particular build ran — so a request still pending when the strip was tapped grows
    ///     this page's own span a little further by the time its `WaterfallViewModel` is built.
    ///     The tapped moment is still centred exactly, in absolute terms; what shifts is *where
    ///     that moment falls* on this page's own, now slightly longer, strip — proportionally
    ///     further toward its leading edge than where the finger actually was on the shorter one
    ///     it tapped. Accepted rather than threaded through as an absolute `Date`: the drift is
    ///     bounded by how long the push takes and is invisible unless a request is still pending
    ///     at the exact moment of the tap, and carrying a `Date` end to end would mean converting
    ///     it back to a `TimeInterval` against *this* page's origin anyway, which is exactly the
    ///     assumption above with an extra type in the way.
    init(logs: NetworkLogsViewModel, openingTime: TimeInterval? = nil) {
        self.logs = logs
        _viewModel = StateObject(
            wrappedValue: WaterfallViewModel(
                requests: logs.requests,
                totalCount: logs.totalRequestCount,
                openingTime: openingTime
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(localized("Waterfall"))
        .navigationBarTitleDisplayMode(.inline)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        // The array itself, not a count derived from it. Watching counts meant a request that
        // *completed* moved nothing the page was looking at, so its bar stayed orange and
        // stretched to a stale "now" until unrelated traffic happened to arrive — on a page whose
        // whole subject is when things started and finished.
        .onReceive(logs.$requests) { requests in
            viewModel.update(requests: requests, totalCount: logs.totalRequestCount)
        }
    }

    /// The page's body once the log holds something: ``minimapCard``, fixed above ``detail``'s
    /// `List` rather than scrolling with it, over one continuous inset-grouped-looking
    /// background.
    ///
    /// A `VStack` rather than a `List` at the top level — again, the reverse of where this went
    /// one fix round ago. That round put the minimap in a `Section` at the top of the `List` on
    /// the owner's own direction; asked to try it, the owner then asked whether it could stay
    /// fixed while the rows scrolled underneath it instead, and a `List` cannot do that: it never
    /// pins section content the way a table view can pin a header, and `.insetGrouped` does not
    /// pin section headers either — only `.plain` does, and this list is `.insetGrouped` by an
    /// explicit, separate instruction that still stands. A section genuinely cannot be sticky
    /// here, so the minimap moved back to being a sibling — the shape it had before either of the
    /// last two fix rounds — but now hand-styled to still read as the inset-grouped card it
    /// briefly, literally was. See ``minimapCard`` for that styling and its own honest limits.
    ///
    /// Unconditional here on purpose, same as ``minimapCard`` and ``detail`` are individually:
    /// this property is only ever reached through ``body``, which shows it only once
    /// ``WaterfallViewModel/isEmpty`` is `false` — "no traffic at all" still shows nothing but
    /// ``emptyState``, not a floating card above an empty list.
    ///
    /// `.background(WaterfallChartStyle.insetGroupedPageBackground)` on the whole `VStack`: the
    /// `List` beneath already paints that colour on itself, so this is redundant there, but it is
    /// what keeps the space around and above ``minimapCard`` — which paints nothing of its own —
    /// from defaulting to whatever colour this view's own container happens to be, breaking the
    /// seam between the card and the list beneath it.
    private var content: some View {
        VStack(spacing: 0) {
            minimapCard
            detail
        }
        .background(WaterfallChartStyle.insetGroupedPageBackground)
    }

    /// The colour legend, unchanged in content since the page's original design: four marks in one
    /// line, still drawn by a `Chart` of its own from ``WaterfallChartStyle/styleScale``, the one
    /// place the outcome colours are declared. The Traffic Stats section has no legend of its own
    /// for this one to match — it draws only the overview strip — so this exists to give the
    /// full-log page's own bars something naming what each colour means. See
    /// ``WaterfallLegendView``.
    ///
    /// No manual padding on this property itself: ``minimapCard`` applies padding to the `VStack`
    /// holding this and ``strip`` together, once, rather than each of them carrying its own — see
    /// that property's own documentation for what that padding is and why.
    private var legend: some View {
        WaterfallLegendView()
    }

    /// The overview strip, carrying the current window and announcing it to VoiceOver.
    ///
    /// Back to `.scrub`'s original, continuous zero-distance drag — see
    /// ``WaterfallOverviewStrip/Interaction/scrub(_:)``'s own documentation for why that is safe
    /// again now that ``minimapCard`` sits outside any scroll view.
    ///
    /// `.accessibilityValue` rather than baking the count into the label: the strip's label
    /// (``localized(_:)`` `"Traffic overview"`, set inside ``WaterfallOverviewStrip`` itself)
    /// names *what* the element is, and the value is what VoiceOver re-announces after every
    /// drag or adjustable-action change — without it, a VoiceOver user swiping to zoom hears
    /// "Traffic overview" again on every step and has no way to tell anything happened.
    ///
    /// Whether ``minimapCard`` also attaches `.accessibilityAdjustableAction` is decided by
    /// ``WaterfallViewModel/window``'s `canZoom`, not by this property: `canZoom`'s own
    /// documentation says the page disables the control rather than letting a pinch silently do
    /// nothing, and an adjustable action offered on an element that cannot act on it breaks that
    /// promise for VoiceOver the same way an un-disabled pinch would for a sighted reader.
    private var strip: some View {
        WaterfallOverviewStrip(series: viewModel.series,
                               window: viewModel.window,
                               height: WaterfallOverviewStrip.pageHeight,
                               interaction: .scrub { viewModel.scrub(to: $0) })
            .accessibilityValue(viewModel.windowCaption)
    }

    /// The minimap, styled to still read as an inset-grouped card even though it is no longer
    /// one: the legend explaining the strip's colours, and the strip itself carrying the current
    /// window, in one row-shaped `VStack` on a rounded, coloured background — fixed above
    /// ``detail``'s `List` as a sibling in ``content``, rather than scrolling with it.
    ///
    /// ## Why this is not a `Section` any more
    ///
    /// The previous fix round put this in a `Section` at the top of ``detail``'s `List`, on the
    /// owner's own direction. Having seen that build, the owner then asked whether it could stay
    /// on screen while the rows scrolled underneath — and a `List` genuinely cannot do that for
    /// section content: `List` never pins a section's own rows the way a table view can pin a
    /// section *header*, and even header-pinning is a `.plain`-list behaviour that
    /// `.insetGrouped` — this page's list style, on its own separate, still-standing instruction
    /// — does not have at all. There is no modifier that makes a `Section` sticky here; the only
    /// way to fix this to the top of the screen is to take it out of the scrolling container
    /// entirely, which is what ``content`` now does.
    ///
    /// ## Matching `.insetGrouped` by hand
    ///
    /// Four things make an inset-grouped section look the way it does, and this reaches for the
    /// most exact version of each it can:
    ///
    /// - **Background material** — `WaterfallChartStyle.insetGroupedCardBackground`, which is
    ///   `UIColor.secondarySystemGroupedBackground`. Not a guess: it is the exact semantic colour
    ///   an `.insetGrouped` `List` fills its own rows with, so the card's *colour* matches the
    ///   list's own sections exactly, not approximately.
    /// - **Corner radius** — `WaterfallChartStyle.insetGroupedCardCornerRadius`, `10`pt. The
    ///   figure most consistently cited for an inset-grouped section's own rounding; not
    ///   published as an API constant, so an estimate.
    /// - **Horizontal insets** — `WaterfallChartStyle.insetGroupedCardMargin`, `20`pt from this
    ///   page's own edges to the card's rounded background. The same figure, and the same
    ///   estimate, `WaterfallChartStyle.detailRowInteriorChrome` already uses for the detail
    ///   list's own section margin — reused rather than picked afresh, since both are estimating
    ///   the same real quantity for two independently hand-built views that need to agree with
    ///   each other, and with the real `List` beneath them, for the page to read as one screen.
    /// - **Internal content padding** — plain `.padding()`, SwiftUI's own system-default spacing,
    ///   rather than a bespoke figure invented to imitate a `List` row's own content insets. This
    ///   is a deliberate simplification: it is one fewer guessed constant, and "the platform's own
    ///   default padding" is a defensible stand-in for "whatever a system list row's padding is"
    ///   in a way a hand-picked number pretending to know that figure exactly would not be.
    ///
    /// What is **not** attempted: the exact vertical gap between the top of the page and the
    /// card, and between the card and the list's own first row. The `16`pt top padding below is a
    /// plain estimate with no particular source, and the gap to the list beneath relies entirely
    /// on whatever top inset `.insetGrouped` already gives a `List`'s first section — this view
    /// adds no bottom padding of its own, on the reasoning that doing so would very likely double
    /// a gap the list is already contributing on its own, but that reasoning was not checked
    /// against a running app either.
    ///
    /// - Important: None of this was seen rendered. The colour is exact by construction; the
    ///   corner radius, the horizontal margin, and both vertical gaps are estimates a device or
    ///   simulator pass is needed to confirm or correct — see the fix report.
    ///
    /// ## What did not change
    ///
    /// Still one row, not two — the strip and the legend are one `VStack`, strip on top, legend
    /// beneath, no divider between them, exactly as the previous fix round settled it. Only the
    /// *container* around that `VStack` changed, from a `Section` back to a plain view with its
    /// own drawn background.
    private var minimapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.window.canZoom {
                strip.accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: viewModel.zoom(by: 2)
                    case .decrement: viewModel.zoom(by: 0.5)
                    @unknown default: break
                    }
                }
            } else {
                strip
            }
            legend
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: WaterfallChartStyle.insetGroupedCardCornerRadius, style: .continuous)
                .fill(WaterfallChartStyle.insetGroupedCardBackground)
        )
        .padding(.horizontal, WaterfallChartStyle.insetGroupedCardMargin)
        .padding(.top, 16)
    }

    /// The detail rows, in their own `List`.
    ///
    /// A `List` rather than a `LazyVStack` in a `ScrollView`: rows are `NavigationLink`s and this
    /// is a menu screen, so it takes the menu's row treatment, separators and press states for
    /// free rather than hand-rolling them. `.insetGrouped` — not `.plain`, which is what this used
    /// to be styled and what ``NetworkLogsView`` still is — because the owner asked for it
    /// explicitly, and because a `List` built from a section with content, the shape this page's
    /// `List` has, is the same shape `TrafficStatsView`'s own `List` is, which gets its
    /// inset-grouped card look by not overriding the style at all. That default is exactly
    /// `.insetGrouped` on iOS, so setting it here explicitly produces the identical appearance
    /// without this page's own correctness depending on an unwritten default resolving the same
    /// way on every iOS version the package supports.
    ///
    /// Holds only ``detailSection(rowLayout:)`` now — the minimap left this `List` entirely, see
    /// ``minimapCard``'s own documentation for why a `Section` could not do what the owner asked
    /// for. `WaterfallChartStyle.detailRowInteriorChrome`'s own row-inset estimate was re-checked
    /// against that move, not just assumed to still hold: see that constant's own `- Note`.
    @ViewBuilder
    private var detail: some View {
        GeometryReader { proxy in
            // Named `metrics`, not `rowLayout` — the latter would shadow the
            // ``WaterfallView/rowLayout(in:)`` method this line calls, which a local `let` of the
            // same name silently breaks: every reference to `rowLayout` below this line would
            // resolve to the constant instead of the method, including the one computing it.
            let metrics = rowLayout(in: proxy.size.width)
            List {
                detailSection(rowLayout: metrics)
            }
            .listStyle(.insetGrouped)
            .onAppear { viewModel.configureWindow(plotWidth: metrics.plotWidth) }
            .onChange(of: proxy.size.width) { _ in
                viewModel.configureWindow(plotWidth: rowLayout(in: proxy.size.width).plotWidth)
            }
            .onChange(of: dynamicTypeSize) { _ in
                viewModel.configureWindow(plotWidth: rowLayout(in: proxy.size.width).plotWidth)
            }
        }
        // Attached to the `GeometryReader` — the container this property returns — rather than
        // chained onto the `List` inside it, and with `.simultaneousGesture` rather than
        // `.gesture`. Both changed together as the fix ``magnification``'s own documentation
        // describes in full, and neither moved for *this* fix: the minimap leaving this `List`
        // changes what the `List` contains, not what wraps the `List` itself, so the gesture's
        // attachment point is untouched. `.subviews` rather than `.all` when zoom is impossible:
        // it disables the pinch this modifier adds while still letting the `List` recognise its
        // own scroll and press gestures, so a request the window cannot narrow any further does
        // not also lose its scroll. See `canZoom`'s own documentation on why the page disables
        // the gesture rather than letting a pinch silently do nothing.
        .simultaneousGesture(magnification, including: viewModel.window.canZoom ? .all : .subviews)
    }

    /// The detail section: the rows the window holds, or ``windowEmptyState`` when it holds none —
    /// captioned, when it holds rows, with how many of the log's requests they are.
    ///
    /// The caption used to sit below the whole `List` as a `Text` of its own, outside every
    /// section. It is this section's own footer instead, on the owner's own direction after
    /// driving the build: a footer is exactly SwiftUI's slot for a line explaining what a
    /// section's rows are, and this caption has always been exactly that — see
    /// ``WaterfallViewModel/windowCaption``.
    ///
    /// The footer is shown only alongside the rows, not alongside ``windowEmptyState``: a footer
    /// naming how many requests are showing is noise underneath an empty state that already says,
    /// in its own words, that none are. `viewModel.isWindowEmpty` is what already chooses between
    /// the two content branches above, so the footer reads the same condition rather than a second
    /// one that could drift from it.
    ///
    /// - Parameter rowLayout: How wide this frame's rows should draw their columns, from
    ///   ``WaterfallView/rowLayout(in:)``.
    @ViewBuilder
    private func detailSection(rowLayout: WaterfallDetailRowMetrics.Layout) -> some View {
        Section {
            if viewModel.isWindowEmpty {
                windowEmptyState
            } else {
                ForEach(viewModel.visibleRows) { row in
                    NavigationLink {
                        LogDetailsView(httpRequest: row.request)
                    } label: {
                        WaterfallDetailRow(row: row, window: viewModel.window,
                                           showsHost: viewModel.showsHost,
                                           labelWidth: rowLayout.labelWidth,
                                           durationWidth: rowLayout.durationWidth)
                    }
                }
            }
        } footer: {
            if !viewModel.isWindowEmpty {
                Text(viewModel.windowCaption)
            }
        }
    }

    /// How one row divides its width between the label column, the plot, and the duration column,
    /// and therefore also the width the plot's zoom limit is computed from.
    ///
    /// A thin wrapper around `WaterfallDetailRowMetrics.layout(rowWidth:scaledLabelWidth:scaledDurationWidth:)`,
    /// which does the actual arithmetic and carries its own documentation of the rule this applies.
    /// This exists only to supply that function with the two values only a view can produce —
    /// ``scaledLabelWidth`` and ``scaledDurationWidth``, each a `@ScaledMetric` — so every caller
    /// in this file reads the columns' width from the same two properties `WaterfallDetailRow` is
    /// handed, rather than each recomputing its own `@ScaledMetric`, which is exactly how the
    /// value ``detail`` fed ``WaterfallViewModel/configureWindow(plotWidth:)`` and the value the
    /// row actually drew its columns at used to disagree: this function and `WaterfallDetailRow`
    /// now both terminate at the same two stored properties, so there is only one number for
    /// either of them to be wrong about.
    ///
    /// - Parameter rowWidth: The full width one row is given, from the list's own geometry.
    /// - Returns: The label, plot and duration widths the row should draw at, none of which put
    ///   together ever exceed `rowWidth`.
    private func rowLayout(in rowWidth: CGFloat) -> WaterfallDetailRowMetrics.Layout {
        WaterfallDetailRowMetrics.layout(rowWidth: rowWidth,
                                         scaledLabelWidth: scaledLabelWidth,
                                         scaledDurationWidth: scaledDurationWidth)
    }

    /// Pinch to zoom, running alongside the list's scrolling rather than instead of it.
    ///
    /// `MagnificationGesture` and not `MagnifyGesture`: the package's floor is iOS 16 and
    /// `MagnifyGesture` is iOS 17.
    ///
    /// ## Why this never recognised, and what changed
    ///
    /// This shipped attached to ``detail``'s `List` with plain `.gesture(_:including:)` — SwiftUI's
    /// *lowest*-priority attachment, which only recognises once every other gesture in the
    /// responder chain has failed to. A `List` owns a pan recogniser of its own for scrolling, and
    /// on device that recogniser claims a touch sequence, pinch included, before deferring to
    /// anything lower priority — so the `MagnificationGesture` sat behind a recogniser that never
    /// failed, and never recognised at all. That is the reported defect: the pinch does nothing,
    /// full stop, on any log long enough to need it.
    ///
    /// The fix is ``detail`` attaching this with `.simultaneousGesture(_:including:)` instead —
    /// and attaching it to the `GeometryReader` that wraps the `List`, not to the `List` itself.
    /// Both changes matter:
    ///
    /// - `.simultaneousGesture` tells SwiftUI the two gestures are allowed to recognise together,
    ///   rather than requiring the `List`'s own recogniser to fail first — which is precisely the
    ///   dependency that made plain `.gesture(_:)` never fire.
    /// - Attaching it one level up, to the `GeometryReader`, rather than chaining it directly onto
    ///   the `List`: `List` bridges to a UIKit `UICollectionView`, which owns and arbitrates its
    ///   *own* gesture-recogniser subsystem beneath whatever SwiftUI modifiers are chained onto
    ///   the `List` value itself. A SwiftUI gesture attached to an ancestor view sits in a
    ///   different part of the hosting hierarchy, closer to the window, rather than nested inside
    ///   that subsystem — which is judgement about where a SwiftUI-recognised gesture is most
    ///   likely to be let through by a UIKit-backed scroll view's own recogniser, not a
    ///   documented Apple guarantee. It is the more conservative of the two reasonable places to
    ///   attach this, so it is where this fix puts it.
    ///
    /// **What this should do to one-finger scrolling: nothing.** `MagnificationGesture` only
    /// recognises a two-finger pinch; a one-finger drag never satisfies it regardless of which
    /// priority it is attached with, so `.simultaneousGesture` allowing the two to run together
    /// has nothing to arbitrate for an ordinary scroll — the `List`'s pan recogniser is the only
    /// one that ever sees a single touch. The behaviour this change actually gambles on is what
    /// happens on a genuine two-finger touch: before, the `List` won it outright and the pinch
    /// never ran; now both are allowed to recognise, so the list may also register some vertical
    /// motion for the duration of a pinch. That is the accepted cost of choosing a gesture over a
    /// dedicated zoom control — recorded in the design spec's own "Zoom" section — not a new one
    /// this fix introduces.
    ///
    /// **On verification:** nobody in this pipeline can drive a two-finger pinch — RocketSim has
    /// no pinch verb, and this repository has no UI test harness. This was not verified against a
    /// running app. What *is* checked automatically: this gesture's closures are ordinary Swift
    /// code with no SwiftUI-only dependency, so `WaterfallViewModelTests` exercises
    /// ``WaterfallViewModel/zoom(by:)`` — exactly what `onChanged` below calls — directly, and
    /// that coverage is unaffected by any of this. What it does not and cannot show is that the
    /// gesture recognises on a real touch sequence at all. Confirming that the pinch now responds
    /// on device, and that one-finger scrolling still works, is on the owner.
    ///
    /// ## `.onChanged`/`.onEnded`, not `.updating(_:body:)`
    ///
    /// This also used to be driven through `.updating($lastMagnification)`, which is the safer
    /// shape only while the gesture can be cancelled by the `List` stealing the sequence — see
    /// ``lastMagnification``'s own documentation, which covers this in full. That risk is gone now
    /// that the gesture recognises independently rather than behind the `List`'s own, and
    /// `.updating(_:body:)`'s own contract — a closure meant to update only the transient gesture
    /// state it is attached to, not to push side effects into other observed state — is what makes
    /// `.onChanged`/`.onEnded` the better fit now, not merely an equivalent one.
    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value.isFinite, value > 0, lastMagnification > 0 else { return }
                viewModel.zoom(by: Double(value / lastMagnification))
                lastMagnification = value
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }

    /// The placeholder shown for a log with nothing in it at all.
    ///
    /// Distinct from ``windowEmptyState``, which answers ``WaterfallViewModel/isWindowEmpty``: this
    /// is the whole log holding nothing to draw a strip or a window over in the first place, so
    /// ``body`` shows this instead of ``content`` entirely — no ``minimapCard`` floating above an
    /// empty list, no detail list either.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Traffic Captured"),
                systemImage: "chart.bar.xaxis",
                description: Text(
                    localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Traffic Captured"))
                    .font(.headline)
                Text(localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    /// The placeholder shown when the window is over a stretch of the log with nothing in it.
    ///
    /// Distinct from ``emptyState``, which answers the whole log holding no traffic at all: this
    /// one answers ``WaterfallViewModel/isWindowEmpty`` — traffic exists elsewhere in the log, the
    /// current window just is not over any of it. Shown as ``detailSection(rowLayout:)``'s own
    /// content rather than in place of the whole page, because ``minimapCard`` above it is still
    /// showing something real and must stay on screen: a developer who dragged into a gap still
    /// needs to see where the window sits to drag it back out of one, which swapping the entire
    /// page for a placeholder — the way ``emptyState`` replaces ``content`` outright — would take
    /// away.
    ///
    /// Replaces a bare `Text` row that used to sit here reading "No requests in this part of the
    /// log." — which looked like a stray list item rather than a state of the page, the defect
    /// report this whole fix was written from. Built in the same idiom as ``emptyState``: a title,
    /// an icon and a description behind `#available(iOS 17.0, *)`, with the same hand-built
    /// fallback below it for the package's iOS 16 floor. What this state carries that ``emptyState``
    /// does not is a way out: a request that lands here got there because it was dragged or zoomed
    /// into a gap, and unlike an empty log — nothing to do about that but wait for traffic — a gap
    /// in a log that has traffic elsewhere is only ever one tap away from somewhere with something
    /// to show. The button calls ``WaterfallViewModel/resetWindow()`` directly; see that method's
    /// own documentation for why it returns to the most recent traffic rather than the whole span.
    ///
    /// `ContentUnavailableView`'s three-slot `label:description:actions:` initialiser is what
    /// supplies that action slot on iOS 17 — the stock SwiftUI shape for exactly this, an
    /// unavailable-content view with something to do about it, rather than a hand-rolled button
    /// bolted onto the two-slot convenience initialiser ``emptyState`` uses. The iOS 16 fallback
    /// hand-builds the same four elements with a stock `Button`.
    ///
    /// - Note: The button carries no `.buttonStyle` on either branch, on the owner's own
    ///   direction after driving the build: `ContentUnavailableView`'s `actions:` slot already
    ///   styles whatever it is given as the plain tinted text link Apple's own empty states use,
    ///   and `.buttonStyle(.borderedProminent)` — this page's usual convention for a screen's one
    ///   primary action elsewhere — fought that here, rendering as a filled capsule that read as
    ///   a call to action heavier than "go back to where you were." The iOS 16 fallback's `Button`
    ///   matches it deliberately, styleless, rather than diverging between the two branches.
    ///
    /// The title is `"Quiet Stretch"`, not the fuller `"No Requests in This Window"` this first
    /// read: that title truncated on a standard iPhone width — `ContentUnavailableView`'s title
    /// is a single line — and the description immediately beneath it already carries the
    /// explanation in full, so the title only ever needed to name the state, not describe it.
    ///
    /// The icon is `"tray"`, not `"timelapse"` this first drew: a dashed, circular glyph read as
    /// an in-progress spinner to the owner driving the build, telling the reader something was
    /// still arriving when nothing was — the opposite of what an empty state should say. `"tray"`
    /// is Apple's own canonical choice for "nothing here" (it is the icon `ContentUnavailableView`
    /// is demonstrated with in Apple's own documentation), has no animated or loading connotation,
    /// and reads the same whether the log is a request short of arriving or has been quiet for an
    /// hour.
    @ViewBuilder
    private var windowEmptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(localized("Quiet Stretch"), systemImage: "tray")
            } description: {
                Text(localized("The window is over a quiet stretch of the log. Move it back to see the most recent traffic."))
            } actions: {
                Button(localized("Show Recent Traffic")) {
                    viewModel.resetWindow()
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("Quiet Stretch"))
                    .font(.headline)
                Text(localized("The window is over a quiet stretch of the log. Move it back to see the most recent traffic."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(localized("Show Recent Traffic")) {
                    viewModel.resetWindow()
                }
            }
            .padding()
        }
    }
}

/// Where one row's bar is drawn inside the detail list's plot.
///
/// Separated from ``WaterfallDetailRow`` for the same reason ``WaterfallStripGeometry`` is
/// separated from ``WaterfallOverviewStrip``: a `GeometryReader`'s content cannot be inspected by
/// a test, so pulling the arithmetic out into a pure function is what makes it something a test
/// can drive directly instead of asserting against rendered pixels.
enum WaterfallDetailGeometry {

    /// Where one row's bar sits inside the window, clipped at both edges.
    ///
    /// The left edge is pulled back before ``WaterfallChartStyle/detailMinimumBarWidth`` is
    /// applied, not after — the same shape
    /// ``WaterfallStripGeometry/barRect(index:count:start:duration:span:size:)`` and
    /// ``WaterfallStripGeometry/windowRect(startFraction:durationFraction:size:)`` already fix,
    /// and the defect this function used to carry as `WaterfallDetailRow.barRect(in:)`: because
    /// ``WaterfallWindow/contains(start:duration:)`` is inclusive of the window's right edge, an
    /// entry starting exactly there is part of `visibleRows` and computed a raw `x` of exactly
    /// `size.width`; the old code applied the width floor *after* clamping `x`, so the floored
    /// rect's far edge ran past `size.width` and drew entirely outside the plot — removed by the
    /// row's own `.clipped()`, leaving a row with a label, a duration, and no bar to show for it.
    /// Pulling `x` back first means the two clamps can never fight: the rect this returns is
    /// always at least ``WaterfallChartStyle/detailMinimumBarWidth`` wide when `size` is that
    /// wide, and always inside `size`.
    ///
    /// Clipping rather than shrinking: a request that outlives the window is drawn flush to the
    /// edge, so the clip reads as "continues" instead of as a shorter request than it was.
    ///
    /// - Parameters:
    ///   - start: The entry's start, in seconds from the series origin.
    ///   - duration: The entry's length in seconds.
    ///   - window: The window the bar is positioned and clipped against.
    ///   - size: The plot's measured size, from the row's own `GeometryReader`.
    /// - Returns: The rect to fill, always inside `size`.
    static func barRect(start: TimeInterval, duration: TimeInterval, window: WaterfallWindow, size: CGSize) -> CGRect {
        guard window.duration > 0, size.width > 0 else { return .zero }
        let scale = size.width / CGFloat(window.duration)
        let rawStart = CGFloat(start - window.start) * scale
        let rawEnd = CGFloat(start + duration - window.start) * scale
        let clippedStart = min(max(0, rawStart), size.width)
        let clippedEnd = min(max(0, rawEnd), size.width)
        let x = min(clippedStart, max(0, size.width - WaterfallChartStyle.detailMinimumBarWidth))
        let rawWidth = clippedEnd - clippedStart
        let width = min(max(rawWidth, WaterfallChartStyle.detailMinimumBarWidth), max(0, size.width - x))
        return CGRect(x: x, y: 0, width: width, height: WaterfallChartStyle.barThickness)
    }
}

/// How the detail row divides its width between the label column, the plot, and the duration
/// column, given the row's own width and how wide Dynamic Type wants the two fixed columns to be.
///
/// Exists because ``WaterfallView/rowLayout(in:)`` — the function feeding
/// ``WaterfallViewModel/configureWindow(plotWidth:)`` the width the zoom limit is computed against
/// — used to subtract ``WaterfallChartStyle/detailLabelWidth`` and
/// ``WaterfallChartStyle/detailDurationWidth``'s *unscaled* base values, while `WaterfallDetailRow`
/// drew its columns at their own, separately computed `@ScaledMetric` widths. The two agreed at
/// the default text size, where a `@ScaledMetric` barely moves off its base value, and diverged
/// the moment Dynamic Type grew past it: the zoom limit kept assuming 132pt and 62pt columns while
/// the row actually drew columns that could be more than three times that wide at the largest
/// accessibility category. That is a single value computed two different ways in two different
/// places, which is the shape every drift in this feature has taken — see ``WaterfallDetailGeometry``
/// and ``WaterfallStripGeometry`` for the same lesson applied to bar position. The fix is the same
/// one those types apply: there is now exactly one function that computes the three widths, and
/// both the plot-width calculation and the row's own columns read its answer instead of each
/// deriving their own.
///
/// ## The rule once the columns no longer fit
///
/// At the largest accessibility category the two `@ScaledMetric` columns alone can demand more
/// width than an ordinary row has — roughly 421pt and 198pt together against a content width near
/// 358pt, measured at AX5 — which a plain `.frame(width:)` does not shrink to accommodate. Left
/// uncorrected, the flexible plot column between them is squeezed to nothing and the row overflows
/// past the screen's edge.
///
/// This caps the two columns' combined width, proportionally, at whatever is left of the row after
/// its fixed chrome (``WaterfallChartStyle/detailRowInteriorChrome``,
/// ``WaterfallChartStyle/detailRowDisclosureReserve``) and ``WaterfallChartStyle/minimumPlotWidth``
/// are both reserved — rather than the alternative of dropping the plot column past some threshold
/// once it would otherwise be squeezed. The plot is what makes this page a *waterfall* rather than
/// a plain list of durations: it is the one place two requests' overlap is visible at a glance,
/// which the label and duration columns do not carry between them however much room they are
/// given. A reader at an accessibility text size has, if anything, more reason to want that
/// picture, not less — losing fine motor control or reading a shrunk screen from a distance are
/// common reasons to raise text size, and neither one makes "did these two requests overlap"
/// stop mattering. So the plot keeps its floor and the two text columns give way instead, split
/// proportionally to how wide `@ScaledMetric` wanted each of them so neither one is starved
/// disproportionately: the label and duration text still truncates or wraps rather than clipping
/// outright — see `WaterfallDetailRow`'s own `.lineLimit`/`.truncationMode` — so a reader loses
/// some characters at the extreme end of Dynamic Type rather than losing the chart entirely.
///
/// - Note: This only guarantees ``WaterfallChartStyle/minimumPlotWidth`` when the row is at least
///   that wide plus its fixed chrome — true of every iPhone and iPad screen width the toolkit
///   supports, including Slide Over's narrowest multitasking width. A row narrower even than the
///   chrome and the floor together — theoretical, not something any supported device produces —
///   still cannot overflow, because ``layout(rowWidth:scaledLabelWidth:scaledDurationWidth:)``
///   never reports a plot wider than what is actually left once the (now possibly zero) columns
///   and the chrome are subtracted; it simply can no longer promise the floor in that case.
enum WaterfallDetailRowMetrics {

    /// The three widths one row should draw its columns at.
    struct Layout: Equatable {
        /// The label column's width, in points.
        let labelWidth: CGFloat

        /// The plot column's width, in points. Never wider than the space actually left after
        /// ``labelWidth``, ``durationWidth`` and the row's fixed chrome are accounted for.
        let plotWidth: CGFloat

        /// The duration column's width, in points.
        let durationWidth: CGFloat
    }

    /// The row's fixed horizontal overhead beyond the label and duration columns: the row's own
    /// `HStack` gaps and `List` insets, plus the `NavigationLink` disclosure chevron's reserve.
    /// See ``WaterfallChartStyle/detailRowInteriorChrome`` and
    /// ``WaterfallChartStyle/detailRowDisclosureReserve`` for what each term covers.
    static var fixedChrome: CGFloat {
        WaterfallChartStyle.detailRowInteriorChrome + WaterfallChartStyle.detailRowDisclosureReserve
    }

    /// Computes the row's three column widths for a row of `rowWidth`.
    ///
    /// - Parameters:
    ///   - rowWidth: The full width one row is given, from the list's own geometry — the same
    ///     value ``WaterfallView/rowLayout(in:)`` passes through unchanged.
    ///   - scaledLabelWidth: ``WaterfallChartStyle/detailLabelWidth`` after `@ScaledMetric` has
    ///     scaled it for the reader's current text size.
    ///   - scaledDurationWidth: ``WaterfallChartStyle/detailDurationWidth``, scaled the same way.
    /// - Returns: The label, plot and duration widths the row should draw at. Their sum plus
    ///   ``fixedChrome`` never exceeds `rowWidth`, so the row this feeds can never overflow it.
    static func layout(rowWidth: CGFloat, scaledLabelWidth: CGFloat, scaledDurationWidth: CGFloat) -> Layout {
        let safeRowWidth = max(0, rowWidth)
        let naiveLabelWidth = max(0, scaledLabelWidth)
        let naiveDurationWidth = max(0, scaledDurationWidth)
        let naiveColumnsWidth = naiveLabelWidth + naiveDurationWidth

        // What the two columns may spend together while still leaving the plot its floor. `0`
        // when the row is too narrow even for the chrome and the floor alone — see this type's
        // own documentation for what happens then.
        let columnsBudget = max(0, safeRowWidth - fixedChrome - WaterfallChartStyle.minimumPlotWidth)

        let labelWidth: CGFloat
        let durationWidth: CGFloat
        if naiveColumnsWidth <= columnsBudget || naiveColumnsWidth <= 0 {
            // The columns already fit alongside a full-floor plot at their natural scaled width —
            // the ordinary case at every text size up to roughly AX2 on a typical iPhone width —
            // so nothing is capped.
            labelWidth = naiveLabelWidth
            durationWidth = naiveDurationWidth
        } else {
            // Scale both columns down by the same factor, so the ratio `@ScaledMetric` chose
            // between them — the label wider than the duration, matching their base 132:62 split
            // — survives the cap instead of one column being starved to save the other.
            let scale = columnsBudget / naiveColumnsWidth
            labelWidth = naiveLabelWidth * scale
            durationWidth = naiveDurationWidth * scale
        }

        // Derived from what is actually left, not re-floored to `minimumPlotWidth`: whenever
        // `columnsBudget` was reachable above, this equals `minimumPlotWidth` exactly (or more, if
        // the columns didn't need the whole budget). In the narrower-than-the-floor-itself case
        // `columnsBudget` already collapsed to `0`, so this reports whatever genuinely remains —
        // which is the promise this type's own documentation makes: the plot is never reported as
        // wider than it actually is.
        let plotWidth = max(0, safeRowWidth - fixedChrome - labelWidth - durationWidth)

        return Layout(labelWidth: labelWidth, plotWidth: plotWidth, durationWidth: durationWidth)
    }
}

/// One request in the waterfall's detail list: who it went to, what it was, when it happened
/// inside the window, and how long it took.
///
/// Its own small view rather than a case inside ``WaterfallView``, since it exists only for this
/// list. The bar is a filled rectangle rather than a `Chart`, for the same reason the old page's
/// rows were: a `BarMark` with both axes and the legend hidden *is* a filled rectangle, and asking
/// Charts to lay one out per row buys nothing a `RoundedRectangle` does not already give for free.
/// The row's thickness, colour, row height and duration label all come from
/// ``WaterfallChartStyle``, which is what keeps a request's colour here the same one the overview
/// strip drew it in before this row existed to be tapped.
///
/// The bar conveys a request's length by width and its outcome by fill colour, neither of which
/// is anything to VoiceOver, so the row collapses itself into one accessibility element with a
/// composed label naming the host, the request, its outcome and its duration — see
/// ``accessibilityLabel``.
///
/// The visible host is conditional in a way the accessibility label is not: see ``showsHost`` and
/// ``label``.
private struct WaterfallDetailRow: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The current window, which is what the bar is placed and clipped against.
    let window: WaterfallWindow

    /// Whether the log holds more than one distinct host, from
    /// ``WaterfallViewModel/showsHost``. `false` hides the host entirely rather than drawing it
    /// dimmed: repeating the same host on every row of a single-host log is noise, and worse, it
    /// crowds out the path even when there is nothing for the host to distinguish.
    let showsHost: Bool

    /// The row's height, scaled against the reader's text size.
    ///
    /// Scaled rather than constant for the same reason the old page's rows were: the label beside
    /// the bar grows with Dynamic Type, and a constant height would clip it at exactly the sizes
    /// where it most needs to be legible.
    ///
    /// Still this row's own `@ScaledMetric`, unlike ``labelWidth`` and ``durationWidth`` below:
    /// height does not compete with siblings the way the row's three *horizontal* columns do, so
    /// there is no budget for ``WaterfallDetailRowMetrics`` to arbitrate and nothing for this to
    /// disagree with anywhere else in the page.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = WaterfallChartStyle.rowHeight

    /// The row's label column width, already scaled and, where the row is too narrow for its full
    /// scaled width, already capped — see ``WaterfallDetailRowMetrics``.
    ///
    /// A plain `let` rather than this row's own `@ScaledMetric`, unlike before this fix: the width
    /// ``WaterfallView`` feeds ``WaterfallViewModel/configureWindow(plotWidth:)`` for the zoom
    /// limit has to be computed from the *same* number this frame is drawn at, and a `@ScaledMetric`
    /// declared here could never be read from outside this type to make that guarantee. See
    /// ``WaterfallDetailRowMetrics`` for the full reasoning and ``WaterfallChartStyle/detailLabelWidth``
    /// for the base value it starts from.
    let labelWidth: CGFloat

    /// The row's duration column width, already scaled and possibly capped, for the same reason
    /// and in the same way ``labelWidth`` is. See ``WaterfallChartStyle/detailDurationWidth`` for
    /// the base value it starts from.
    let durationWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            label

            GeometryReader { proxy in
                let rect = WaterfallDetailGeometry.barRect(start: row.entry.start,
                                                           duration: row.entry.duration,
                                                           window: window,
                                                           size: proxy.size)
                RoundedRectangle(cornerRadius: 3)
                    .fill(WaterfallChartStyle.colour(for: row.entry))
                    .frame(width: rect.width, height: WaterfallChartStyle.barThickness)
                    .offset(x: rect.minX, y: (proxy.size.height - WaterfallChartStyle.barThickness) / 2)
            }
            // `GeometryReader` does not clip its own content, and belt-and-braces is cheap: even
            // though `WaterfallDetailGeometry.barRect(start:duration:window:size:)` now pulls `x`
            // back before the width floor is applied, so the rect it returns is always inside
            // `size`, this still guards against a future change to that arithmetic drawing over
            // the duration column instead of stopping at the plot's edge.
            .clipped()

            Text(row.entry.isPending
                 ? "—" // scyther:unlocalised em dash for an unfinished request
                 : WaterfallChartStyle.valueLabel(for: row.entry))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: durationWidth, alignment: .trailing)
                // `WaterfallDetailRowMetrics` can hand this a `durationWidth` narrower than the
                // text's own natural width once the row is too narrow for the full scaled column
                // — see that type's own documentation. Without a line limit, `Text` would wrap
                // onto a second line rather than truncate, which `rowHeight` has no budget for and
                // which would overflow the row vertically instead of the horizontal overflow this
                // whole fix exists to prevent. Truncated to a leading ellipsis rather than
                // `WaterfallDetailRowLayoutTests`'s middle for the path: a duration like "1.38 s"
                // is read right-to-left for its meaning — the unit at the end matters most — so
                // losing digits off the front is more honest than losing the unit off the back.
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(height: rowHeight)
        // The bar itself conveys length by width, which is nothing to a screen reader, so the
        // name, the outcome and the duration are spoken instead — the same composition the old
        // page's row used, and for the same reason: without it a request's outcome is carried
        // only by the rectangle's fill colour, which VoiceOver cannot read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The row's name column: the path alone, or the host stacked above the path when
    /// ``showsHost`` is true.
    ///
    /// Stacked, not side by side. Side by side was tried first — the host capped at a fixed
    /// width, the path taking what was left — and it read worse than not showing the host at
    /// all: the label column is 132pt, a capped host left roughly 60pt for the path, and a path
    /// like `GET /posts/1` needs more than that, so it was the *path* that ended up giving way
    /// per row. Because how much it gave way depended on how long that row's own host happened to
    /// be, different rows truncated the host to different widths, so the paths no longer started
    /// at a common x and the column stopped being scannable down. Widening the label column
    /// instead would have taken width from the plot, which the zoom limit is computed against.
    ///
    /// Stacking removes the contest rather than refereeing it: each line gets the column's full
    /// width, so nothing about one row's host affects where another row's path starts. It is also
    /// the same subtitle shape the rest of the menu already uses — Network Logs stacks method and
    /// status over the URL — so a two-line row here is a pattern the reader has already seen
    /// rather than a new one.
    @ViewBuilder
    private var label: some View {
        if showsHost {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.entry.shortHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Tail, because hosts differ near their front — `jsonplaceholder…` is still
                    // `jsonplaceholder`.
                    .truncationMode(.tail)
                Text(verbatim: row.entry.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    // Middle, not tail: a path's distinguishing content is usually at its *end* —
                    // a query value in `/comments?postId=1`, a resolution suffix in
                    // `/assets/logo@3x.png` — and tail truncation is exactly what cuts that off.
                    // Middle keeps a fragment of both ends.
                    .truncationMode(.middle)
            }
            .frame(width: labelWidth, alignment: .leading)
        } else {
            Text(verbatim: row.entry.label)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: labelWidth, alignment: .leading)
        }
    }

    /// What VoiceOver reads for the row.
    ///
    /// - Returns: The host and label, the outcome, and the duration (or an em dash for a request
    ///   still in flight), joined the way ``WaterfallEntry``'s own accessibility summaries are —
    ///   one sentence per part rather than reading the visible " · " punctuation aloud.
    private var accessibilityLabel: String {
        let name = row.entry.shortHost.isEmpty ? row.entry.label : "\(row.entry.shortHost) \(row.entry.label)"
        return [
            name,
            WaterfallChartStyle.outcomeTitle(for: row.entry),
            row.entry.isPending ? "—" : WaterfallChartStyle.valueLabel(for: row.entry), // scyther:unlocalised em dash for an unfinished request
        ].joined(separator: ", ") // scyther:unlocalised separator between localised parts
    }
}

/// What each colour means, at the page's full content width.
///
/// Still a `Chart`, and deliberately: letting Charts derive the legend straight from
/// ``WaterfallChartStyle/styleScale`` is what guarantees it can never name a colour the scale
/// itself does not produce, rather than hand-drawing four marks that would need to be kept in step
/// with the scale by hand. The zero-width marks exist only to give Charts something to derive a
/// legend from, and the plot they sit in is collapsed to a point.
private struct WaterfallLegendView: View {
    /// The legend's height, scaled against the reader's text size, because a constant height
    /// clips a wrapped legend at the sizes where it would actually wrap.
    @ScaledMetric(relativeTo: .caption) private var legendHeight: CGFloat = WaterfallChartStyle.legendHeight

    var body: some View {
        Chart(WaterfallChartStyle.outcomeTitles, id: \.self) { title in
            BarMark(
                xStart: .value(localized("Start"), 0),
                xEnd: .value(localized("End"), 0),
                y: .value(localized("Request"), title),
                height: .fixed(0)
            )
            .foregroundStyle(by: .value(localized("Outcome"), title))
        }
        .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, spacing: 0)
        .chartPlotStyle { plot in
            plot.frame(height: 1)
        }
        .frame(height: legendHeight)
    }
}
