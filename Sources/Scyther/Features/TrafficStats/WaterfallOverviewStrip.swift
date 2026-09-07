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

    /// Where one request is drawn.
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
        let x = CGFloat(min(max(0, start / usableSpan), 1)) * size.width
        let rawWidth = CGFloat(max(0, duration) / usableSpan) * size.width
        let width = min(max(rawWidth, minimumBarWidth), max(0, size.width - x))

        let height = min(maximumBarHeight, max(1, size.height / CGFloat(count)))
        let lane = (size.height - height) / CGFloat(max(1, count - 1))
        let y = count == 1 ? (size.height - height) / 2 : CGFloat(index) * lane

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The whole log compressed into one strip: every request as a short horizontal line, placed by
/// when it happened and coloured by how it went.
///
/// One view, two jobs. On ``WaterfallView`` it carries the current window as an overlay and takes
/// a drag that moves it. In ``TrafficStatsView`` it carries no window and a tap opens the page at
/// the moment touched.
///
/// Drawn with a `Canvas` rather than a stack of shapes. Both callers now build from the entire
/// log rather than the most recent handful, and a view per request would be thousands of views
/// for a busy session; a `Canvas` is one drawing pass whatever the count.
struct WaterfallOverviewStrip: View {

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

    /// What to do when the strip is touched, given a time in seconds from the series origin.
    let onScrub: ((TimeInterval) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (index, entry) in series.entries.enumerated() {
                        let rect = WaterfallStripGeometry.barRect(
                            index: index,
                            count: series.entries.count,
                            start: entry.start,
                            duration: entry.duration,
                            span: series.span,
                            size: size
                        )
                        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                                     with: .color(WaterfallChartStyle.colour(for: entry)))
                    }
                }
                if let window, window.span > 0 {
                    Rectangle()
                        .fill(WaterfallChartStyle.windowTint)
                        .frame(width: max(2, proxy.size.width * window.durationFraction))
                        .overlay(alignment: .leading) { edge }
                        .overlay(alignment: .trailing) { edge }
                        .offset(x: proxy.size.width * window.startFraction)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrub(width: proxy.size.width))
        }
        .frame(height: height)
        .background(WaterfallChartStyle.stripBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(localized("Traffic overview"))
    }

    /// The window overlay's edge rule, on both sides, so the window reads as a frame rather than
    /// as a tint that might be a highlight.
    private var edge: some View {
        Rectangle()
            .fill(WaterfallChartStyle.windowEdge)
            .frame(width: 2)
    }

    /// Turns a touch anywhere on the strip into a time.
    ///
    /// `minimumDistance` is zero so a tap counts, which is what Traffic Stats needs; the page
    /// gets dragging from the same gesture for free.
    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onScrub, width > 0, series.span > 0 else { return }
                let fraction = min(max(0, value.location.x / width), 1)
                onScrub(Double(fraction) * series.span)
            }
    }
}
