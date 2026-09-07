//
//  WaterfallSeries.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// One request's bar on the traffic waterfall.
///
/// Both ``start`` and ``duration`` are seconds on the series' shared axis, so two entries whose
/// ranges intersect were genuinely in flight at the same time.
struct WaterfallEntry: Identifiable, Equatable, Sendable {
    /// The captured request's hash, which identifies the bar.
    let id: String

    /// What the bar is called: the GraphQL operation name, else `"METHOD /path"`.
    let label: String

    /// Seconds from the series origin to this request starting. Never negative.
    let start: TimeInterval

    /// How long the bar runs, in seconds. Zero for a request that has not finished and has no
    /// span to run into.
    var duration: TimeInterval

    /// Whether the request finished and finished badly: a status of 400 or above, or a load that
    /// ended without a response at all.
    ///
    /// Mutually exclusive with ``isPending``. A request that has not come back has not failed
    /// yet, and one that has come back is not in flight, so exactly one of the two can be true.
    let isFailure: Bool

    /// Whether the request is still in flight.
    ///
    /// Derived from the absence of a response *date*, not from
    /// ``HTTPRequest/noResponse``: a load that ended in an error carries a response date and no
    /// response, so `noResponse` means "finished badly" rather than "still running". Deriving
    /// pending from it painted every failure in the log as in flight and stretched its bar to the
    /// end of the chart.
    ///
    /// A pending bar is drawn to the end of the series rather than stopping short, because its
    /// real end is not known yet.
    let isPending: Bool

    /// Whether a rule synthesised the response.
    ///
    /// A stub keeps its place on the timeline — it happened, and it can block or overlap real
    /// work — but its length measures the toolkit rather than the network, so the chart says so.
    let isStubbed: Bool
}

/// The recent captured requests laid out on one shared time axis.
///
/// Answers the question the log's flat list cannot: what was happening at the same time as what.
/// The series takes the most recent `limit` requests, sets its origin to the earliest of their
/// start times, and expresses every bar in seconds from there.
///
/// ## Usage
/// ```swift
/// let series = WaterfallSeries.build(from: requests)
/// series.span                     // seconds covered by the whole chart
/// series.entries.first?.start     // always 0, the origin
/// ```
struct WaterfallSeries: Equatable, Sendable {
    /// The wall-clock time the axis starts at.
    let origin: Date

    /// The seconds from ``origin`` to the far end of the chart. Never negative.
    ///
    /// The later of the last request finishing and, when anything is still in flight, the moment
    /// the series was built — because a request that has not come back is still running now, and
    /// an axis that stopped at the last *finish* would give the newest pending bar no width at
    /// all.
    let span: TimeInterval

    /// The bars, oldest first.
    let entries: [WaterfallEntry]

    /// How many requests a series covers unless a caller says otherwise.
    ///
    /// Seven, because the only caller that takes the default is the preview section on
    /// **Traffic Stats**, and a preview has to read as one. It was forty, which at a readable row
    /// height filled the card and then some: a log of twenty-two requests drew all twenty-two, so
    /// the preview already showed everything and the **See all** page it links to was showing the
    /// same picture. Seven is a glance; the page carries the rest.
    static let defaultLimit = 7

    /// The status code at and above which a response counts as a failure.
    private static let failureStatusFloor = 400

    /// A series with nothing in it, used as a view model's initial value.
    static let empty = WaterfallSeries(origin: Date(), span: 0, entries: [])

    /// Lays the most recent `limit` of `requests` out on a shared axis.
    ///
    /// Requests with no start date are dropped: there is nowhere on the axis to put them. A
    /// negative duration — a clock that moved while the request was in flight — is drawn as zero
    /// rather than as a bar that runs backwards.
    ///
    /// The axis is sized before the pending tails are filled in, and takes `now` into account
    /// when anything is still in flight. Sizing it from the finished bars alone left every entry
    /// that started at or after the last finish — the newest request, the common case — with a
    /// zero-width bar reading `0 ms`.
    ///
    /// - Parameters:
    ///   - requests: The requests to lay out, in any order.
    ///   - limit: How many of the most recent requests to keep. Defaults to ``defaultLimit``.
    ///   - now: The moment the series describes, which is where a still-running bar ends.
    ///     Defaults to the current time; a test passes its own so the arithmetic is deterministic.
    /// - Returns: The series, oldest entry first. Empty when there is nothing to place.
    static func build(from requests: [HTTPRequest],
                      limit: Int = defaultLimit,
                      now: Date = Date()) -> WaterfallSeries {
        guard limit > 0 else { return WaterfallSeries(origin: now, span: 0, entries: []) }

        let dated = requests
            .compactMap { request -> (request: HTTPRequest, date: Date)? in
                guard let date = request.requestDate else { return nil }
                return (request, date)
            }
            .sorted { $0.date < $1.date }
            .suffix(limit)

        guard let origin = dated.first?.date else {
            return WaterfallSeries(origin: now, span: 0, entries: [])
        }

        var entries = dated.map { pair -> WaterfallEntry in
            let request = pair.request
            let didFinish = request.responseDate != nil
            return WaterfallEntry(
                id: request.getRandomHash() as String,
                label: label(for: request),
                start: max(0, pair.date.timeIntervalSince(origin)),
                duration: duration(of: request, startedAt: pair.date),
                isFailure: didFinish
                    && (request.noResponse || (request.responseCode ?? 0) >= failureStatusFloor),
                isPending: !didFinish,
                isStubbed: request.wasStubbed
            )
        }

        let finished = entries.reduce(0) { max($0, $1.start + $1.duration) }
        let stillRunning = entries.contains(where: \.isPending) ? max(0, now.timeIntervalSince(origin)) : 0
        let span = max(finished, stillRunning)
        for index in entries.indices where entries[index].isPending {
            entries[index].duration = max(0, span - entries[index].start)
        }

        return WaterfallSeries(origin: origin, span: span, entries: entries)
    }

    /// How long one request's bar runs, in seconds.
    ///
    /// ``HTTPRequest/requestDuration`` is only filled in when a response arrived, so a request
    /// that failed carries none and used to be drawn with no width at all. The response date is
    /// stamped either way, so the time between the two dates is the honest length of a failed
    /// bar: a request that failed twenty milliseconds in is twenty milliseconds long.
    ///
    /// - Parameters:
    ///   - request: The request to measure.
    ///   - start: The request's own start date, already unwrapped by the caller.
    /// - Returns: The bar's length in seconds. Zero for a request still in flight, which is
    ///   filled in from the series' span afterwards, and zero for any figure that is not finite.
    private static func duration(of request: HTTPRequest, startedAt start: Date) -> TimeInterval {
        if let raw = request.requestDuration, raw.isFinite, raw > 0 {
            return Double(raw) / 1_000
        }
        guard let finish = request.responseDate else { return 0 }
        let measured = finish.timeIntervalSince(start)
        return measured.isFinite ? max(0, measured) : 0
    }

    /// What a request's bar is called.
    ///
    /// A GraphQL operation name identifies the call far better than the single endpoint every
    /// operation is posted to, so it wins where there is one.
    ///
    /// - Parameter request: The request to name.
    /// - Returns: The operation name, else `"METHOD /path"` with the query stripped.
    private static func label(for request: HTTPRequest) -> String {
        if request.isGraphQL, let name = request.graphQLOperationName, !name.isEmpty {
            return name
        }
        let method = (request.requestMethod ?? "GET").uppercased()
        let path = request.requestURL.flatMap { URLComponents(string: $0)?.path } ?? ""
        return "\(method) \(path.isEmpty ? "/" : path)"
    }
}
