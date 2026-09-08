//
//  WaterfallWindow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import CoreGraphics
import Foundation

/// The slice of a ``WaterfallSeries`` the page is currently showing.
///
/// Every rule about what can be seen lives here: how far you may zoom in, how far out, where the
/// window may sit, and which entries fall inside it. None of it lives in the view.
///
/// That split is deliberate and it is the whole reason this type exists. Zoom is driven by a
/// pinch, and a gesture cannot be unit-tested honestly — so the gesture is reduced to handing a
/// magnification factor to ``zoomed(by:)`` and installing whatever comes back. The arithmetic
/// that decides whether that is legal is here, where a test can drive it.
///
/// The window carries its own limits rather than taking them per call, so a window can never be
/// combined with the wrong series' span.
///
/// ## Topics
///
/// ### Creating a Window
/// - ``init(span:narrowest:)``
/// - ``init(start:duration:span:narrowest:)``
/// - ``narrowestDuration(shortestMeasured:span:plotWidth:)``
/// - ``opening(span:narrowest:)``
///
/// ### Moving and Zooming
/// - ``zoomed(by:)``
/// - ``movedToCentre(_:)``
/// - ``centred(on:duration:)``
///
/// ### Reading It
/// - ``contains(start:duration:)``
/// - ``canZoom``
/// - ``marksASubset``
struct WaterfallWindow: Equatable, Sendable {

    /// How wide the shortest measured request should be drawn at maximum zoom, in points.
    ///
    /// Past this there is nothing left to magnify: every bar is already legible and the only
    /// thing that grows is the gap between them.
    static let targetShortestBarWidth: CGFloat = 24

    /// Seconds from the series origin to the window's left edge.
    let start: TimeInterval

    /// How many seconds the window spans.
    let duration: TimeInterval

    /// The series' full span — the widest this window may ever be.
    let span: TimeInterval

    /// The tightest duration this window may be narrowed to.
    let narrowest: TimeInterval

    /// The widest window: the whole series.
    ///
    /// - Parameters:
    ///   - span: The series' span.
    ///   - narrowest: The tightest allowed duration, from
    ///     ``narrowestDuration(shortestMeasured:span:plotWidth:)``.
    init(span: TimeInterval, narrowest: TimeInterval) {
        self.init(start: 0, duration: span, span: span, narrowest: narrowest)
    }

    /// A window clamped into `span`.
    ///
    /// Clamping happens here rather than at each call site, so there is exactly one place that
    /// can be wrong about it. Every other initialiser and every mutating method on this type
    /// routes back through here, which is also why none of them can produce NaN or infinity: a
    /// non-finite `span`, `narrowest` or `duration` is replaced before it can propagate, and the
    /// two `min`/`max` chains below only ever divide nothing — they compare and clamp.
    ///
    /// - Parameters:
    ///   - start: The requested left edge, in seconds from the origin.
    ///   - duration: The requested width, in seconds.
    ///   - span: The series' span.
    ///   - narrowest: The tightest allowed duration.
    init(start: TimeInterval, duration: TimeInterval, span: TimeInterval, narrowest: TimeInterval) {
        let safeSpan = max(0, span.isFinite ? span : 0)
        let safeNarrowest = min(max(0, narrowest.isFinite ? narrowest : safeSpan), safeSpan)
        let width = min(max(duration.isFinite ? duration : safeSpan, safeNarrowest), safeSpan)
        self.span = safeSpan
        self.narrowest = safeNarrowest
        self.duration = width
        self.start = min(max(0, start.isFinite ? start : 0), max(0, safeSpan - width))
    }

    /// Seconds from the origin to the window's right edge.
    var end: TimeInterval { start + duration }

    /// Seconds from the origin to the middle of the window.
    var centre: TimeInterval { start + duration / 2 }

    /// Whether zooming does anything at all.
    ///
    /// `false` for an empty series, a single request, and a series whose shortest request is
    /// already legible at full span. The page disables the gesture rather than letting a pinch
    /// do nothing, because a control that silently ignores you is worse than one that is absent.
    var canZoom: Bool { span > 0 && narrowest < span }

    /// Where the window's left edge sits as a fraction of the span, for drawing the overlay.
    /// `0` when there is no span to be a fraction of.
    var startFraction: Double { span > 0 ? start / span : 0 }

    /// How wide the window is as a fraction of the span, for drawing the overlay. `1` when there
    /// is no span, so an empty strip draws a full-width window rather than an invisible one.
    var durationFraction: Double { span > 0 ? duration / span : 1 }

    /// Whether the window is narrower than the whole span, and therefore worth drawing as an
    /// overlay at all.
    ///
    /// At the widest window — the whole span, still where a short log opens, and where any log
    /// lands once zoomed all the way back out — every request in the log falls inside it, so an
    /// overlay drawn edge to edge would tint the entire strip one solid colour instead of marking
    /// a subset of it: a green box, not a minimap. An overlay that marks *everything* marks
    /// nothing, and is worse than no overlay at all, since it hides the bars underneath it. A log
    /// long enough to need the overlay is also, by construction, long enough that
    /// ``opening(span:narrowest:)`` does not open it at the whole span — see that function's own
    /// documentation — so the overlay this guards is visible from the first frame on exactly the
    /// logs it exists for.
    ///
    /// `false` at the full span, `true` the instant a drag or a zoom narrows the window at all —
    /// and `false`, not `true`, for the degenerate `span == duration == 0` window an empty series
    /// produces, which is the opposite of what ``durationFraction`` returns for the same window.
    /// The two answer different questions: `durationFraction` is what an overlay would be drawn
    /// *at* if one were drawn, and defaults to covering everything so the arithmetic in
    /// ``WaterfallStripGeometry`` never divides by a span of zero; this is whether one should be
    /// drawn *at all*, and a window with nothing to be a subset of is not a subset.
    var marksASubset: Bool { duration < span }

    /// The tightest window that still leaves the shortest request legible.
    ///
    /// A request of length `d` drawn in a window of length `w` across a plot `p` points wide is
    /// `d / w * p` points. Setting that to ``targetShortestBarWidth`` and solving for `w` gives
    /// `d * p / target`.
    ///
    /// - Parameters:
    ///   - shortestMeasured: The shortest finished, non-zero duration in the series, or `nil`
    ///     when nothing finished. Pending and zero-length requests have no measured length to be
    ///     legible at and must be excluded by the caller.
    ///   - span: The series' span, which is also the answer when no zoom is possible.
    ///   - plotWidth: The width the detail list gives a bar, in points.
    /// - Returns: The tightest allowed duration, never above `span` and never below zero.
    static func narrowestDuration(shortestMeasured: TimeInterval?,
                                  span: TimeInterval,
                                  plotWidth: CGFloat) -> TimeInterval {
        guard span > 0,
              let shortest = shortestMeasured,
              shortest > 0, shortest.isFinite,
              plotWidth > 0 else { return max(0, span) }
        let demanded = shortest * Double(plotWidth) / Double(targetShortestBarWidth)
        guard demanded.isFinite else { return span }
        return min(max(0, demanded), span)
    }

    /// The window the page opens with, before any zoom or drag.
    ///
    /// Anchored on the most recent traffic — `end == span` — rather than at the origin, and sized
    /// at half the series' span, clamped into `narrowest...span` exactly as every other window on
    /// this type is: never forced tighter than the zoom floor, and never wider than the log
    /// actually is. A log whose narrowest limit already sits above half its span opens at that
    /// limit instead of at half; a log whose narrowest limit is below half its span, and whose
    /// span is not itself narrower than that limit, opens at the plain half. The whole-span case
    /// still exists, but only where it always has — a log too short to zoom at all, where
    /// `narrowest == span` and every window this type can produce collapses to the one value.
    ///
    /// ## Two rules before this one
    ///
    /// This is the *third* rule this function has computed, and both earlier ones are kept here
    /// rather than deleted, because each was a deliberate, reviewed decision the next one
    /// overturned only once it was driven against real traffic — see
    /// `docs/superpowers/specs/2026-09-07-waterfall-window-design.md`'s own "Default" section and
    /// its "Amendments" for the fuller account of both reversals.
    ///
    /// **First: the whole span, unconditionally.** "Opens honest, zoom is the escape" — the
    /// original design's own phrase for it. Driven against a real, hour-long capture with two
    /// short bursts of traffic an hour apart, every bar in the log floored to the same three
    /// points regardless of whether the request took 43ms or 1.06s, and the strip showed no
    /// window overlay at all, because a window that wide is never `marksASubset`. The owner
    /// reported this as the pinch appearing to do nothing and no window ever appearing — three
    /// symptoms of the one cause.
    ///
    /// **Second: anchored on the newest traffic, sized so the *median* measured request rendered
    /// at ``targetShortestBarWidth`` — the same "24pt is legible" idea
    /// ``narrowestDuration(shortestMeasured:span:plotWidth:)`` already applies to the shortest
    /// reading, reused against the median because the shortest reading was already spoken for as
    /// the zoom floor.** This fixed the hour-long capture — the strip's overlay was visible from
    /// the first frame on any log that needed it — but it also opened *too tight* on an ordinary
    /// log: a 19-request session opened showing `1 of 19`, because a single median-legible request
    /// is a narrow window indeed once nothing else forces it wider. Median-legible and
    /// *comfortable to open on* turned out to be two different targets, and the owner asked for
    /// the second one directly instead: a page that opens on roughly half its traffic, not on
    /// however few requests one happens to be legible.
    ///
    /// **Third, and current: a flat half the span.** No measurement of any single request's
    /// duration enters this rule at all any more — `WaterfallDurations.median(of:)`, the function
    /// the second rule read for its own "typical request" figure, has no remaining caller and was
    /// removed alongside this change; see that type's own documentation. Simpler, and it happens
    /// to keep the one thing
    /// the second rule got right: half of an hour-long span is still comfortably narrower than the
    /// whole thing, so the hour-long capture's own defect — every bar flooring to the same three
    /// points — does not return, without depending on where the log's median duration happens to
    /// fall to say so.
    ///
    /// - Parameters:
    ///   - span: The series' span.
    ///   - narrowest: The zoom floor, from ``narrowestDuration(shortestMeasured:span:plotWidth:)``.
    ///     The window this returns can never be forced narrower than that, regardless of what half
    ///     the span alone would demand.
    /// - Returns: A window anchored at `span`, whose left edge sits at `span - duration`, clamped
    ///   into the series exactly as every other window on this type is.
    static func opening(span: TimeInterval, narrowest: TimeInterval) -> WaterfallWindow {
        let demanded = span / 2
        let duration = min(max(demanded, narrowest), max(0, span))
        return WaterfallWindow(start: span - duration, duration: duration, span: span, narrowest: narrowest)
    }

    /// The window magnified by `factor`, holding its centre still where the span leaves room to.
    ///
    /// Holding the centre is what stops a pinch sliding the developer through time while they are
    /// trying to change resolution. Near an edge there is no room: the result is still clamped
    /// into `[0, span]`, and an edge that would otherwise overhang the log is pulled back instead
    /// — which moves the centre. That is correct, not a bug: the alternative is a window showing
    /// time that does not exist.
    ///
    /// - Parameter factor: Greater than 1 zooms in, between 0 and 1 zooms out. A non-finite or
    ///   non-positive factor returns the window unchanged, because a gesture in an odd state must
    ///   not be able to produce a nonsense window.
    /// - Returns: The zoomed window, clamped at both limits and re-clamped into the span.
    func zoomed(by factor: Double) -> WaterfallWindow {
        guard factor.isFinite, factor > 0, span > 0 else { return self }
        let held = centre
        let width = duration / factor
        return WaterfallWindow(start: held - width / 2,
                               duration: width,
                               span: span,
                               narrowest: narrowest)
    }

    /// The window moved so its centre sits at `time`, clamped into the span.
    ///
    /// - Parameter time: Seconds from the origin.
    func movedToCentre(_ time: TimeInterval) -> WaterfallWindow {
        WaterfallWindow(start: time - duration / 2,
                        duration: duration,
                        span: span,
                        narrowest: narrowest)
    }

    /// A window of `duration` centred on `time`, clamped into the span and the zoom limits.
    ///
    /// This is how the page opens when it is reached by tapping the Traffic Stats strip: the tap
    /// names a moment, and the page arrives looking at it.
    ///
    /// - Parameters:
    ///   - time: Seconds from the origin.
    ///   - duration: The width to open at.
    func centred(on time: TimeInterval, duration: TimeInterval) -> WaterfallWindow {
        WaterfallWindow(start: time - duration / 2,
                        duration: duration,
                        span: span,
                        narrowest: narrowest)
    }

    /// Whether an entry's span intersects the window's.
    ///
    /// Intersection, not containment: a request already in flight when the window opens, or one
    /// that outlives it, is part of what was happening in that window and is drawn clipped. Only
    /// requests entirely before or entirely after it are absent.
    ///
    /// - Parameters:
    ///   - start: The entry's start, in seconds from the origin.
    ///   - duration: The entry's length in seconds. Zero is allowed: a zero-length request on the
    ///     edge still happened there.
    func contains(start entryStart: TimeInterval, duration entryDuration: TimeInterval) -> Bool {
        entryStart <= end && entryStart + max(0, entryDuration) >= start
    }
}
