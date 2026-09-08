//
//  WaterfallOverviewStrip.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import SwiftUI

/// Where each request is drawn on the overview strip.
///
/// Separated from the view because a `Canvas` cannot be inspected by a test. The `Canvas` fills
/// exactly the rects this returns and does nothing else, so testing this tests the drawing.
enum WaterfallStripGeometry {

    /// The tallest a single request's line is drawn, in points.
    ///
    /// A log of five requests drawn as hairlines looks broken; a log of five hundred drawn at
    /// three points would not fit. The height is the smaller of this and an even share.
    static let maximumBarHeight: CGFloat = 3

    /// The narrowest a request is drawn, in points.
    ///
    /// A 20ms request inside a 60s log is a third of a pixel wide. The strip exists to show that
    /// something happened at that moment, so it stays a visible dot.
    static let minimumBarWidth: CGFloat = 1

    /// The narrowest the window overlay is drawn, in points.
    ///
    /// Wider than ``minimumBarWidth`` because the overlay is a frame with two edge rules rather
    /// than a single fill, and two 2pt rules need daylight between them to read as a frame rather
    /// than a single thick line.
    static let minimumWindowWidth: CGFloat = 2

    /// Where one request is drawn.
    ///
    /// The left edge is pulled back before the width is computed, not after: clamping the width
    /// alone once `x` is already past `size.width - minimumBarWidth` lets the right-edge clamp
    /// win over the minimum-width floor, drawing a sliver a fraction of a point wide for a
    /// request that started in the log's last moments — precisely the request this floor exists
    /// to keep visible. Pulling `x` back first means the two clamps can never fight: whichever
    /// applies, the bar this returns is always at least `minimumBarWidth` wide when the strip
    /// itself is that wide, and never runs past `size.width`.
    ///
    /// - Parameters:
    ///   - index: The request's position in the series, oldest first.
    ///   - count: How many requests the series holds.
    ///   - start: The request's start, in seconds from the origin.
    ///   - duration: The request's length in seconds.
    ///   - span: The series' span in seconds.
    ///   - size: The strip's size in points.
    /// - Returns: The rect to fill, always inside `size`.
    static func barRect(index: Int,
                        count: Int,
                        start: TimeInterval,
                        duration: TimeInterval,
                        span: TimeInterval,
                        size: CGSize) -> CGRect {
        guard count > 0, size.width > 0, size.height > 0 else { return .zero }

        let usableSpan = span > 0 && span.isFinite ? span : 1
        let rawX = CGFloat(min(max(0, start / usableSpan), 1)) * size.width
        let x = min(rawX, max(0, size.width - minimumBarWidth))
        let rawWidth = CGFloat(max(0, duration) / usableSpan) * size.width
        let width = min(max(rawWidth, minimumBarWidth), max(0, size.width - x))

        let height = min(maximumBarHeight, max(1, size.height / CGFloat(count)))
        let lane = (size.height - height) / CGFloat(max(1, count - 1))
        let y = count == 1 ? (size.height - height) / 2 : CGFloat(index) * lane

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Where the current-window overlay is drawn.
    ///
    /// A pure function for the same reason ``barRect(index:count:start:duration:span:size:)`` is
    /// one: the overlay used to be laid out inline in the view with `.frame(width:)` and
    /// `.offset(x:)`, which floored the rendered width but not the offset that positions it — so
    /// a window narrower than ``minimumWindowWidth`` (routine at deep zoom, since a window can be
    /// a tiny fraction of a long session) sitting near the trailing edge drew its rect, and the
    /// edge rule marking its end, past `size.width`, silently cropped by the strip's own
    /// `clipShape`. The same left-edge pull-back that fixes
    /// ``barRect(index:count:start:duration:span:size:)`` fixes this, and doing it here rather
    /// than in the view is what makes it something a test can reach at all.
    ///
    /// - Parameters:
    ///   - startFraction: The window's left edge as a fraction of the strip, from
    ///     ``WaterfallWindow/startFraction``.
    ///   - durationFraction: The window's width as a fraction of the strip, from
    ///     ``WaterfallWindow/durationFraction``.
    ///   - size: The strip's size in points.
    /// - Returns: The rect to fill, always inside `size`.
    static func windowRect(startFraction: Double,
                           durationFraction: Double,
                           size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }

        let rawX = CGFloat(min(max(0, startFraction), 1)) * size.width
        let x = min(rawX, max(0, size.width - minimumWindowWidth))
        let rawWidth = CGFloat(max(0, durationFraction)) * size.width
        let width = min(max(rawWidth, minimumWindowWidth), max(0, size.width - x))

        return CGRect(x: x, y: 0, width: width, height: size.height)
    }
}

/// Whether a drag over the overview strip counts as horizontal, for
/// ``WaterfallOverviewStrip/Interaction/scrub(_:)``.
///
/// Separated from the view for the same reason ``WaterfallStripGeometry`` is: the comparison
/// this makes lives inside a `DragGesture`'s `onChanged` closure in production, which a test
/// cannot invoke — SwiftUI gives no way to synthesise a `DragGesture.Value` and drive a gesture
/// as if a finger produced it. Pulling the actual decision boundary out here is what lets a test
/// pin the boundary itself — the exact ratio at which a drag stops being "horizontal enough" —
/// rather than only the generated documentation's word for where it sits. This is the one part of
/// ``WaterfallOverviewStrip/scrubGesture(width:onScrub:)`` a test can reach at all; the gesture's
/// timing (``WaterfallOverviewStrip``'s own `scrubMinimumDistance`), and whether it actually wins
/// or loses arbitration against a real `List`'s pan on a real touch screen, cannot be exercised
/// this way and were not verified by anything in this file.
enum WaterfallScrubGeometry {

    /// How many times wider than it is tall a drag's translation must be before it counts as
    /// horizontal.
    ///
    /// `2`: the horizontal component must be at least double the vertical one, which admits only
    /// a drag within roughly 27° of dead horizontal (`atan(1/2) ≈ 26.57°`) — not the `1` a naive
    /// "more horizontal than vertical" reading would use. Biased deliberately toward the `List`
    /// this strip's page now sits inside, not toward the strip itself: this rule exists because a
    /// scrub gesture previously captured scrolls it had no business capturing, so anything near
    /// the ambiguous middle around 45°, including a drag that is only barely more horizontal than
    /// vertical, is left for the list to scroll rather than guessed at as a scrub. The cost is a
    /// scrub that occasionally does not start on a drag a reader meant horizontally but began at
    /// a shallow diagonal — recoverable by simply dragging again — set against the alternative
    /// this whole rule was written to remove: a scroll silently eaten by the strip.
    static let horizontalDominance: CGFloat = 2

    /// Whether a drag's cumulative translation reads as horizontal rather than vertical.
    ///
    /// - Parameters:
    ///   - width: The drag's cumulative horizontal translation, in points
    ///     (`DragGesture.Value.translation.width`). Sign does not matter — compared by magnitude,
    ///     since a leftward drag is exactly as horizontal as a rightward one.
    ///   - height: The drag's cumulative vertical translation, in points
    ///     (`DragGesture.Value.translation.height`). Sign does not matter, for the same reason.
    /// - Returns: `true` once `width`'s magnitude is at least ``horizontalDominance`` times
    ///   `height`'s.
    static func isHorizontal(width: CGFloat, height: CGFloat) -> Bool {
        abs(width) > abs(height) * horizontalDominance
    }
}

/// The whole log compressed into one strip: every request as a short horizontal line, placed by
/// when it happened and coloured by how it went.
///
/// One view, two jobs. On ``WaterfallView`` it carries the current window as an overlay and takes
/// a continuous drag that moves it. In ``TrafficStatsView`` it carries no window and a tap opens
/// the page at the moment touched — see ``Interaction`` for why those are two different gestures
/// rather than one.
///
/// Drawn with a `Canvas` rather than a stack of shapes. Both callers now build from the entire
/// log rather than the most recent handful, and a view per request would be thousands of views
/// for a busy session; a `Canvas` is one drawing pass whatever the count.
struct WaterfallOverviewStrip: View {

    /// How the strip responds to touch, which differs by host.
    ///
    /// Both hosts now put the strip inside a `List` — see ``WaterfallView/minimapSection`` and
    /// ``TrafficStatsView/waterfallSection`` — so both interactions that actually do anything have
    /// to let the list's own pan recognise a scroll rather than capture it, and the difference
    /// between them is what kind of gesture each host actually needs: the full page wants a
    /// continuous drag to sweep its window across the log, Traffic Stats wants a single point
    /// touched. A single gesture cannot serve both needs honestly, so the strip is told which one
    /// it wants rather than guessing from its own state.
    enum Interaction {
        /// Draws only. No gesture is attached.
        case none

        /// Reports continuously while a drag reads as horizontal, and does nothing at all while
        /// it reads as vertical — see ``scrubGesture(width:onScrub:)`` for the exact rule and,
        /// most importantly, for why a *zero-distance* drag cannot be used here even though this
        /// is a continuous gesture. Used by the full page, which sits inside a scrolling `List`
        /// and needs a drag that starts anywhere over the strip to still be able to scroll it.
        case scrub((TimeInterval) -> Void)

        /// Reports once, on a touch that did not travel. Used by Traffic Stats, where the gesture
        /// has to let a scroll pass through untouched rather than capture it, and a single touched
        /// moment is all the section needs — it has no window of its own to drag.
        case tap((TimeInterval) -> Void)
    }

    /// The strip's height on the full page, in points.
    static let pageHeight: CGFloat = 96

    /// The strip's height inside the Traffic Stats section, in points. Shorter because it is one
    /// section among several rather than the screen's subject.
    static let sectionHeight: CGFloat = 72

    /// How far a touch may travel and still be read as a tap rather than the start of a scroll,
    /// in points, for ``Interaction/tap(_:)``.
    ///
    /// Not zero: a finger is never perfectly still, and a strict zero would read most genuine
    /// taps as the beginning of a scroll and silently drop them.
    private static let tapTolerance: CGFloat = 10

    /// How far a touch must travel before ``scrubGesture(width:onScrub:)`` reports anything at
    /// all, in points, for ``Interaction/scrub(_:)``.
    ///
    /// The same magnitude as ``tapTolerance``, and the same underlying reason: a finger is never
    /// perfectly still, so the very first few points of any drag — horizontal, vertical or
    /// diagonal — are noise, not signal. Below this distance ``scrubGesture(width:onScrub:)``
    /// has not yet been asked to decide anything; above it, the drag has moved far enough that
    /// its direction actually means something, which is what
    /// ``WaterfallScrubGeometry/isHorizontal(width:height:)`` is then applied to decide. This
    /// alone is not what makes the gesture safe inside a `List` — see
    /// ``scrubGesture(width:onScrub:)``'s own documentation for the rest of that story.
    private static let scrubMinimumDistance: CGFloat = 10

    /// The log to draw.
    let series: WaterfallSeries

    /// The window to mark, or `nil` to draw no overlay.
    let window: WaterfallWindow?

    /// The strip's height.
    let height: CGFloat

    /// How touch on the strip is handled.
    let interaction: Interaction

    var body: some View {
        GeometryReader { proxy in
            accessibleContent(size: proxy.size)
        }
        .frame(height: height)
        .background(WaterfallChartStyle.stripBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// ``content(size:)`` plus the accessibility both interactions need, built together because
    /// ``Interaction/tap(_:)``'s own accessibility action needs the same width the gesture and the
    /// drawing already read from the enclosing `GeometryReader`.
    ///
    /// Traffic Stats' strip used to collapse to one element with a label and nothing else — no
    /// value, no trait, no action — which meant "tap the strip to open the page at that moment"
    /// was unreachable by VoiceOver at all: the `Chart` this strip replaced made every bar its own
    /// navigable element with a spoken value, so that was a regression on what shipped before it,
    /// not a pre-existing gap. `.isButton` plus an `.accessibilityAction` fix the same failure
    /// `.accessibilityAdjustableAction` already fixed for zoom on ``WaterfallView``'s own strip —
    /// see that type's own documentation — by giving VoiceOver and Switch Control a route to the
    /// interaction a sighted reader's tap already has.
    ///
    /// - Parameter size: The strip's size in points, from the enclosing `GeometryReader`.
    @ViewBuilder
    private func accessibleContent(size: CGSize) -> some View {
        let base = content(size: size)
            .accessibilityElement()
            .accessibilityLabel(localized("Traffic overview"))
            .accessibilityValue(accessibilityValue)

        switch interaction {
        case .none, .scrub:
            // `.scrub`'s own page overrides this value with the current window's caption, and
            // reaches zoom through `.accessibilityAdjustableAction` attached from outside — see
            // ``WaterfallView/strip``. Nothing here needs an activation action: the drag that
            // gesture answers to has no single VoiceOver-reachable equivalent the way a tap does.
            base
        case .tap(let onTap):
            // The strip has no destination view of its own for a `NavigationLink` to wrap — see
            // ``TrafficStatsView/waterfallSection`` — so a sighted tap and VoiceOver's activation
            // both have to drive the same callback. The midpoint stands in for "the moment
            // touched" that a sighted tap would otherwise name, which is the best a single
            // activation action can report without asking the reader to drag first.
            base
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard let time = time(at: size.width / 2, width: size.width) else { return }
                    onTap(time)
                }
        }
    }

    /// A description of what the strip shows, read by VoiceOver after
    /// ``localized(_:)`` `"Traffic overview"` names what the element *is*.
    ///
    /// ``WaterfallView/strip`` overrides this with `.accessibilityValue(viewModel.windowCaption)`,
    /// applied from outside and so replacing rather than joining this default — see that
    /// property's own documentation on why the label and the value are split. This default is
    /// therefore only ever heard on the Traffic Stats section, which supplies no override of its
    /// own; without it, that strip named itself and said nothing about what it held.
    private var accessibilityValue: String {
        localized("\(series.entries.count) requests over \(DurationText.milliseconds(series.span * 1_000))")
    }

    /// The strip's drawing and its gesture, built together because the gesture the view attaches
    /// depends on ``interaction`` and the width both need comes from the same `GeometryReader`.
    ///
    /// A `switch` in a `@ViewBuilder` rather than a single call with a `nil` case, because each
    /// branch has a different concrete `some View` type — `drawing` bare for `.none`, and two
    /// differently-built `DragGesture` pipelines wrapped in `.simultaneousGesture(_:)` for
    /// `.scrub` and `.tap` — and a `@ViewBuilder` is what lets the branches differ without
    /// erasing the view.
    ///
    /// Both `.scrub` and `.tap` attach with `.simultaneousGesture(_:)`, not `.gesture(_:)`: a
    /// gesture attached with plain `.gesture(_:)` only recognises once every other gesture in the
    /// responder chain has failed to, and a `List`'s own pan recogniser routinely wins that race
    /// outright rather than failing cleanly — the same failure mode ``WaterfallView/magnification``
    /// documents in full for the pinch. `.simultaneousGesture(_:)` lets this strip's own gesture
    /// and the enclosing `List`'s pan both recognise the same touch independently, which is what
    /// leaves a genuine scroll free to reach the list at all. See
    /// ``scrubGesture(width:onScrub:)`` and ``tapGesture(width:onTap:)`` for how each one then
    /// decides, on its own, whether that same touch is *also* meant for the strip.
    ///
    /// - Parameter size: The strip's size in points, from the enclosing `GeometryReader`.
    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let drawing = ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                for (index, entry) in series.entries.enumerated() {
                    let rect = WaterfallStripGeometry.barRect(
                        index: index,
                        count: series.entries.count,
                        start: entry.start,
                        duration: entry.duration,
                        span: series.span,
                        size: canvasSize
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                                 with: .color(WaterfallChartStyle.colour(for: entry)))
                }
            }
            // `marksASubset` rather than `span > 0`: the page opens with the window at the full
            // span, and a window that wide would draw an overlay edge to edge — a solid tint over
            // the whole strip rather than a mark on part of it. The overlay earns its place the
            // moment the window actually is one.
            if let window, window.marksASubset {
                windowOverlay(window: window, size: size)
            }
        }
        .contentShape(Rectangle())

        switch interaction {
        case .none:
            drawing
        case .scrub(let onScrub):
            drawing.simultaneousGesture(scrubGesture(width: size.width, onScrub: onScrub))
        case .tap(let onTap):
            drawing.simultaneousGesture(tapGesture(width: size.width, onTap: onTap))
        }
    }

    /// The window overlay, laid out by ``WaterfallStripGeometry/windowRect(startFraction:durationFraction:size:)``
    /// so its minimum width and its position are computed together and can never disagree.
    ///
    /// - Parameters:
    ///   - window: The window to mark. Already checked by the caller to mark a genuine subset of
    ///     the strip — see ``WaterfallWindow/marksASubset``.
    ///   - size: The strip's size in points.
    private func windowOverlay(window: WaterfallWindow, size: CGSize) -> some View {
        let rect = WaterfallStripGeometry.windowRect(
            startFraction: window.startFraction,
            durationFraction: window.durationFraction,
            size: size
        )
        return Rectangle()
            .fill(WaterfallChartStyle.windowTint)
            .frame(width: rect.width)
            .overlay(alignment: .leading) { edge }
            .overlay(alignment: .trailing) { edge }
            .offset(x: rect.minX)
            .allowsHitTesting(false)
    }

    /// The window overlay's edge rule, on both sides, so the window reads as a frame rather than
    /// as a tint that might be a highlight.
    private var edge: some View {
        Rectangle()
            .fill(WaterfallChartStyle.windowEdge)
            .frame(width: 2)
    }

    /// Turns a touch position into a time.
    ///
    /// - Parameters:
    ///   - x: The touch's horizontal position, in points from the strip's leading edge.
    ///   - width: The strip's width in points.
    /// - Returns: Seconds from the series origin, or `nil` when there is no width or no span to
    ///   place a time on.
    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval? {
        guard width > 0, series.span > 0 else { return nil }
        let fraction = min(max(0, x / width), 1)
        return Double(fraction) * series.span
    }

    /// The full page's gesture: reports on every change that reads as a horizontal drag, so
    /// dragging left or right tracks the finger continuously, and does nothing at all on a change
    /// that reads as vertical — attached with `.simultaneousGesture(_:)` from ``content(size:)``
    /// so the enclosing `List`'s own pan is never blocked from recognising the same touch.
    ///
    /// ## Why not a zero-distance drag
    ///
    /// This shipped as `DragGesture(minimumDistance: 0)`, safe only for a strip that sits
    /// *outside* any scroll view, which was true of every page that used it until the full page's
    /// minimap moved into its own `List` section. A zero-distance drag satisfies its own
    /// recognition criterion — no movement at all — at the very first touch event, before a
    /// `List`'s own pan recogniser has seen enough movement to decide whether the touch is a
    /// scroll; having recognised first, it claims the touch sequence outright, and no later
    /// direction check inside `onChanged` can hand a touch back once another recogniser has
    /// already lost the race for it. Attaching that same zero-distance gesture with
    /// `.simultaneousGesture(_:)` instead of `.gesture(_:)` does not fix this either: simultaneous
    /// recognition stops the strip from *blocking* the list's pan, but a zero-distance drag still
    /// fires `onScrub` on the very first pixel of *every* touch, scroll included, so the window
    /// would visibly jump the instant a genuine scroll began even though the list itself kept
    /// scrolling underneath it. **Do not restore `minimumDistance: 0` here, and do not drop the
    /// direction check below, to "simplify" this gesture** — both exist to fix exactly the defect
    /// reported against this page once its strip moved inside a `List`, and removing either one
    /// reintroduces it.
    ///
    /// ## The rule
    ///
    /// `DragGesture(minimumDistance: scrubMinimumDistance)` withholds every `onChanged` callback
    /// until the touch has travelled ``scrubMinimumDistance`` points in *any* direction — far
    /// enough that its direction actually means something. From there, every `onChanged` call
    /// asks ``WaterfallScrubGeometry/isHorizontal(width:height:)`` whether the drag's cumulative
    /// `translation`, measured from the drag's own start rather than frame to frame, reads as
    /// horizontal; only then is `onScrub` called at all. A drag that never reads as horizontal —
    /// a vertical scroll, or anything in the ambiguous middle around 45°, see that function's own
    /// documentation for the exact boundary — calls `onScrub` not once for its entire lifetime;
    /// because this is `.simultaneousGesture(_:)`, doing nothing here never blocks anything
    /// either, so the enclosing `List` is free to recognise and act on the same touch as an
    /// ordinary scroll throughout.
    ///
    /// No attempt is made to "lock" the decision the moment a drag first reads as horizontal:
    /// because `translation` is measured from the drag's own start rather than the previous
    /// frame, a genuinely horizontal drag's ratio only grows more lopsided as it continues, so a
    /// drag whose classification wanders back and forth across the boundary does so because the
    /// touch itself is genuinely near-diagonal — there is no more "correct" fixed answer to lock
    /// onto than what the ratio already says at each instant.
    ///
    /// - Parameters:
    ///   - width: The strip's width in points.
    ///   - onScrub: Called with the touched time on every change that reads as horizontal.
    private func scrubGesture(width: CGFloat, onScrub: @escaping (TimeInterval) -> Void) -> some Gesture {
        DragGesture(minimumDistance: Self.scrubMinimumDistance)
            .onChanged { value in
                guard WaterfallScrubGeometry.isHorizontal(width: value.translation.width,
                                                           height: value.translation.height),
                      let time = time(at: value.location.x, width: width) else { return }
                onScrub(time)
            }
    }

    /// Traffic Stats' gesture: reports once, only when the touch ended without travelling more
    /// than ``tapTolerance`` in either axis, and is attached as a simultaneous gesture so a
    /// genuine scroll started on the strip still reaches the enclosing `List` untouched.
    ///
    /// - Parameters:
    ///   - width: The strip's width in points.
    ///   - onTap: Called with the touched time when the touch counts as a tap.
    private func tapGesture(width: CGFloat, onTap: @escaping (TimeInterval) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard abs(value.translation.width) < Self.tapTolerance,
                      abs(value.translation.height) < Self.tapTolerance,
                      let time = time(at: value.location.x, width: width) else { return }
                onTap(time)
            }
    }
}
