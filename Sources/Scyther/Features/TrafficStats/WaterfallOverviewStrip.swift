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
    /// The page keeps the strip outside its scrolling list, so it can afford a continuous drag.
    /// Traffic Stats puts it inside a `List`, where a zero-distance drag would win arbitration
    /// against the list's own pan and steal every scroll that happened to start on the strip. A
    /// single gesture cannot serve both hosts honestly, so the strip is told which one it is in
    /// rather than guessing from its own state.
    enum Interaction {
        /// Draws only. No gesture is attached.
        case none

        /// Reports continuously while dragged, from the first touch. For a strip that is not
        /// inside a scroll view, where nothing else is competing for the drag.
        case scrub((TimeInterval) -> Void)

        /// Reports once, on a touch that did not travel. For a strip inside a scroll view, where
        /// the gesture has to let a scroll pass through untouched rather than capture it.
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
            content(size: proxy.size)
        }
        .frame(height: height)
        .background(WaterfallChartStyle.stripBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(localized("Traffic overview"))
    }

    /// The strip's drawing and its gesture, built together because the gesture the view attaches
    /// depends on ``interaction`` and the width both need comes from the same `GeometryReader`.
    ///
    /// A `switch` in a `@ViewBuilder` rather than a single `.gesture` call with a `nil` case,
    /// because `.tap` has to attach as `.simultaneousGesture` rather than `.gesture` — the two
    /// modifiers are different types, and this is the only way to choose between them per
    /// instance without erasing the view.
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
            if let window, window.span > 0 {
                windowOverlay(window: window, size: size)
            }
        }
        .contentShape(Rectangle())

        switch interaction {
        case .none:
            drawing
        case .scrub(let onScrub):
            drawing.gesture(scrubGesture(width: size.width, onScrub: onScrub))
        case .tap(let onTap):
            drawing.simultaneousGesture(tapGesture(width: size.width, onTap: onTap))
        }
    }

    /// The window overlay, laid out by ``WaterfallStripGeometry/windowRect(startFraction:durationFraction:size:)``
    /// so its minimum width and its position are computed together and can never disagree.
    ///
    /// - Parameters:
    ///   - window: The window to mark. Already checked non-empty by the caller.
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
