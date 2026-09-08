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

// `WaterfallScrubGeometry` used to live here — `isHorizontal(width:height:)` and its
// `horizontalDominance` constant, deciding whether a drag's cumulative translation read as
// horizontal rather than vertical. It existed for exactly one reason: `Interaction.scrub(_:)`
// briefly had to live inside `WaterfallView`'s scrolling `List`, where a zero-distance drag would
// have captured every scroll that happened to start on the strip, and the axis check was what let
// a vertical drag pass through to the list instead. That reason stopped applying once the minimap
// — strip and legend together — moved back out of the `List` to become a fixed sibling above it
// instead of a `Section` inside it; see `WaterfallView.minimapCard`'s own documentation for why.
// Outside a scroll view there is nothing for a vertical drag to be mistaken for and nothing to
// pass through to, so `scrubGesture(width:onScrub:)` reverted to the original zero-distance
// `DragGesture` it had before any of this, and this type had no remaining caller.
//
// Removed with its seven tests, `WaterfallScrubGeometryTests.swift`, deleted rather than left as
// untested, uncalled code. What each of those seven asserted, so the claim is not lost along with
// the file: `testAPureHorizontalDragIsHorizontal` and `testAPureVerticalDragIsNotHorizontal` pinned
// the two trivial ends of the rule — no vertical component at all always counted as horizontal, no
// horizontal component at all never did. `testTheDominanceRatioIsTheExactBoundary` pinned the `2×`
// threshold itself, on both sides of the tie: exactly double did not count, a hair past double did.
// `testADiagonalDragAtFortyFiveDegreesIsNotHorizontal` and
// `testAMostlyHorizontalDragUnderTheMarginIsNotHorizontal` pinned that the ambiguous middle around
// 45°, and a drag only barely past a naive 1:1 tie-break, both stayed on the "leave it to the list"
// side of the `2×` margin rather than the naive one. `testTheSignOfEitherComponentIsIgnored` pinned
// that a leftward drag was exactly as horizontal as a rightward one, and a drag that had looped
// back upward exactly as vertical as one that only ever moved down. `testNoMovementAtAllIsNotHorizontal`
// pinned that zero translation in both axes — the very first sample a real gesture could report
// before its own minimum distance was satisfied — did not read as horizontal by some accident of
// the comparison. None of those seven claims has anything left to own them: the function they
// describe is gone, and the zero-distance `DragGesture` that replaced it makes no distinction
// between axes at all — it fires on the first pixel of any drag, in any direction, exactly as it
// did before any of this.
//
// `Interaction.tap(_:)`, the other gesture this file used to have, was considered for the same
// axis check and did not get it: `.tap` already guarded itself with `tapTolerance`, a symmetric
// "did the touch travel at all" radius rather than a "which axis dominates" comparison, checked
// once at `.onEnded` rather than continuously. `.tap` never reported anything to `onScrub`
// continuously the way `.scrub` does, so there was no equivalent of a drag "becoming" a scrub
// partway through for an axis check to arbitrate — either the touch stayed within `tapTolerance`
// of where it started, in which case it was never going to be mistaken for a scroll in the first
// place, or it did not, in which case `.tap` already did nothing. Adding a second, differently-
// shaped check to a gesture that already answered the only question it needed to would have been
// complexity with no defect behind it.
//
// `.tap` itself — and `tapGesture(width:onTap:)`, `tapTolerance` and the accessibility action
// built around it — were removed for an unrelated reason, in a later round: Traffic Stats, `.tap`'s
// one and only caller, stopped opening the full page centred on the tapped point once its strip
// stopped drawing the whole log. Zoomed to the most recent handful of requests instead (see
// `TrafficStatsViewModel.recentWaterfallCount`), the strip's own series origin became the earliest
// of just those few, not the log's true earliest request — so the mapping
// `WaterfallView.init(logs:openingTime:)` relied on, which assumed the two origins agreed, would
// have silently opened the full page centred on the wrong moment by however far those origins had
// drifted apart. Fixing that mapping would have meant changing `WaterfallView`'s own already-
// shipped, owner-approved contract for the sake of a caller that no longer had the problem it
// solved, so the section's strip draws with `interaction: .none` instead — and the rows beneath
// it, one `NavigationLink` per request, already give more precise navigation than "centred near
// where you tapped" ever did. That left `.tap` with no caller anywhere in the module, and it was
// deleted along with `tapGesture(width:onTap:)` and `tapTolerance` rather than kept as untested,
// uncalled capability — the same choice this file already made once for `WaterfallScrubGeometry`,
// above. Nothing in `WaterfallOverviewStripTests.swift` exercised either directly — both were only
// ever reached through the view, never as pure functions the way `WaterfallStripGeometry` is — so
// no test needed rewriting or deleting alongside them.

/// A log compressed into one strip: every request in ``series`` as a short horizontal line,
/// placed by when it happened and coloured by how it went.
///
/// One view, two callers, drawing two different slices of the log. ``WaterfallView`` builds
/// ``series`` from the whole log and carries the current window as an overlay with a continuous
/// drag that moves it — see ``Interaction/scrub(_:)``. ``TrafficStatsView`` builds ``series`` from
/// only the most recent handful of requests instead (`TrafficStatsViewModel.recentLayout`), so it
/// carries no window to mark and draws only — see ``Interaction/none``. The strip does not know
/// which slice it was given; it draws whatever ``series`` holds edge to edge, which is what makes
/// "zoom to the last few requests" as simple as building a smaller series rather than a second
/// windowing concept.
///
/// Drawn with a `Canvas` rather than a stack of shapes. ``WaterfallView``'s strip still builds from
/// the entire log, and a view per request would be thousands of views for a busy session; a
/// `Canvas` is one drawing pass whatever the count.
struct WaterfallOverviewStrip: View {

    /// How the strip responds to touch, which differs by host.
    ///
    /// The full page keeps the strip outside its scrolling `List` — a fixed sibling above it, see
    /// `WaterfallView.minimapCard` — so it can afford a continuous drag: see ``scrub(_:)``.
    /// Traffic Stats' strip sits inside a `List` too, but does not need a gesture of its own at
    /// all any more — see ``none`` — because the handful of rows drawn beneath it already give a
    /// more precise route to any one request than touching the strip ever did. A gesture that had
    /// to coexist with the list's own pan, the way this type once needed for that section, no
    /// longer has a caller; the removal comment at the top of this file records why and what it
    /// was.
    ///
    /// - Note: `.scrub` briefly needed to tolerate living inside a `List` too, when the full
    ///   page's minimap spent one fix round as a `Section` at the top of its own `List` instead of
    ///   a sibling above it. That gave `.scrub` a direction-aware, non-zero-distance drag — see the
    ///   removal comment just above this type, at the top of this file — reverted once the minimap
    ///   moved back to being a sibling and the reason for it stopped applying.
    enum Interaction {
        /// Draws only. No gesture is attached.
        case none

        /// Reports continuously while dragged, from the first touch. For a strip that is not
        /// inside a scroll view, where nothing else is competing for the drag.
        case scrub((TimeInterval) -> Void)
    }

    /// The strip's height on the full page, in points.
    static let pageHeight: CGFloat = 96

    /// The strip's height inside the Traffic Stats section, in points. Shorter because it is one
    /// section among several rather than the screen's subject.
    static let sectionHeight: CGFloat = 72

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

    /// ``content(size:)`` plus the accessibility every interaction needs: one element speaking a
    /// fixed label and a value describing what the strip currently holds.
    ///
    /// This used to branch on ``interaction``: `.tap`, since removed — see the removal comment at
    /// the top of this file — added `.isButton` and an `.accessibilityAction` reporting the
    /// strip's midpoint, because it had no destination view of its own for a `NavigationLink` to
    /// wrap and a sighted tap and VoiceOver's activation both had to drive the same callback. With
    /// `.tap` gone, both remaining cases — ``Interaction/none`` and ``Interaction/scrub(_:)`` —
    /// want exactly this and nothing more, so there is nothing left to switch on. `.scrub`'s own
    /// page overrides ``accessibilityValue`` with the current window's caption and reaches zoom
    /// through `.accessibilityAdjustableAction` attached from outside — see
    /// ``WaterfallView/strip`` — and needs no activation action here: the drag that gesture
    /// answers to has no single VoiceOver-reachable equivalent the way a tap did.
    ///
    /// - Parameter size: The strip's size in points, from the enclosing `GeometryReader`.
    private func accessibleContent(size: CGSize) -> some View {
        content(size: size)
            .accessibilityElement()
            .accessibilityLabel(localized("Traffic overview"))
            .accessibilityValue(accessibilityValue)
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
    /// `.scrub` attaches with plain `.gesture(_:)`: the full page keeps the strip outside its own
    /// scrolling `List` — see ``Interaction``'s own documentation — so there is no competing
    /// recogniser to avoid blocking. `.none` attaches nothing at all. This file used to have a
    /// third case, `.tap`, that had to reach for `.simultaneousGesture(_:)` instead — Traffic
    /// Stats' `List` owned a pan recogniser of its own, and a gesture attached with plain
    /// `.gesture(_:)` only recognises once every other gesture in the responder chain has failed
    /// to, the same failure mode ``WaterfallView/magnification`` documents in full for the pinch —
    /// but `.tap` had no remaining caller once that section stopped drawing the whole log; see the
    /// removal comment at the top of this file. The `switch` stays rather than collapsing to a
    /// single `if`, in case a third case returns: `.gesture(_:)` and `.simultaneousGesture(_:)`
    /// are different modifier types, so a plain optional gesture could not have expressed the
    /// choice this made when there were three cases to choose from, and the two remaining are
    /// cheap enough to keep as a `switch` rather than special-cased back down to an `if`.
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
            drawing.gesture(scrubGesture(width: size.width, onScrub: onScrub))
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

    /// The full page's gesture: reports on every change, so dragging tracks the finger
    /// continuously. Safe because the page keeps the strip out of any scroll view.
    ///
    /// A zero-distance `DragGesture`, back to what this was before a fix round briefly gave it a
    /// non-zero `minimumDistance` and a direction check, gated on
    /// `WaterfallScrubGeometry.isHorizontal(width:height:)`, so a vertical drag could pass through
    /// to a `List` the strip was, for that one fix round, hosted inside of. Both existed for
    /// exactly as long as that hosting did — see this file's own removal comment, just above
    /// ``Interaction``, for why they were needed there and why they are not needed here, and
    /// `WaterfallView.minimapCard`'s documentation for where the strip lives now. Outside a scroll
    /// view there is nothing for a vertical drag to be mistaken for and nothing to pass through
    /// to, so the extra latency and the direction gate were pure cost with no defect left to earn
    /// their place, and reverting them is what makes this gesture responsive again: `onScrub` now
    /// fires from a drag's very first pixel, in any direction, rather than waiting for 10 points
    /// of travel that then had to read as more horizontal than vertical.
    ///
    /// - Parameters:
    ///   - width: The strip's width in points.
    ///   - onScrub: Called with the touched time on every change.
    private func scrubGesture(width: CGFloat, onScrub: @escaping (TimeInterval) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let time = time(at: value.location.x, width: width) else { return }
                onScrub(time)
            }
    }
}
