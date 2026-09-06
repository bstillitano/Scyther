//
//  TrafficStatistics.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The figures a set of captured requests adds up to: what is slow, what is failing, and how much
/// came down the wire.
///
/// Everything here is derived, in one pass, from requests ``NetworkLogger`` already holds. No
/// capture, no storage, and nothing that touches the request path. The type is a pure value with a
/// single static entry point so every number can be pinned by a test without a network or a view.
///
/// ## What counts as a measurement
///
/// A response synthesised by a request override never left the device, so its duration measures
/// the toolkit rather than the server and its status code was authored rather than returned.
/// Counting it would make the slowest-endpoint list and the error rate lie. Stubbed requests are
/// therefore counted in ``Summary/requestCount`` and ``Summary/stubbedCount`` and excluded from
/// every other figure, including the host and endpoint breakdowns.
///
/// Percentiles use the nearest-rank method, so every duration reported is one a request actually
/// took rather than a number interpolated between two of them.
///
/// ## Usage
/// ```swift
/// let statistics = TrafficStatistics.compute(from: requests)
/// statistics.summary.medianDuration    // milliseconds, or nil when nothing completed
/// statistics.endpoints.first?.id       // the slowest endpoint
/// ```
struct TrafficStatistics: Equatable, Sendable {

    /// The session-wide figures.
    struct Summary: Equatable, Sendable {
        /// Every request in the input, stubbed or not.
        var requestCount: Int = 0

        /// The requests whose response a rule synthesised.
        ///
        /// Excluded from every other figure in this summary — see the type's discussion.
        var stubbedCount: Int = 0

        /// The requests that actually went to the network, that is ``requestCount`` less
        /// ``stubbedCount``. The denominator for the failure rate.
        var measuredCount: Int = 0

        /// The measured requests that came back with a usable duration.
        ///
        /// The sample size behind ``medianDuration`` and ``p95Duration``.
        var completedCount: Int = 0

        /// The measured requests that failed: a status of 400 or above, or no response at all.
        var failureCount: Int = 0

        /// The measured requests that never came back.
        ///
        /// Counted separately rather than treated as zero-duration completions, which would
        /// flatter every latency figure.
        var pendingCount: Int = 0

        /// The total response body length of the measured requests, in bytes.
        var bytesReceived: Int = 0

        /// The nearest-rank median duration in milliseconds, or `nil` when nothing completed.
        var medianDuration: Double?

        /// The nearest-rank 95th percentile duration in milliseconds, or `nil` when nothing completed.
        var p95Duration: Double?

        /// The quickest completed duration in milliseconds, or `nil` when nothing completed.
        ///
        /// Shown in place of the percentiles when the sample is too small for them to mean
        /// anything.
        var fastestDuration: Double?

        /// The slowest completed duration in milliseconds, or `nil` when nothing completed.
        var slowestDuration: Double?

        /// The elapsed time from the first measured request starting to the last one finishing,
        /// or `nil` when no measured request carries a date.
        ///
        /// Stubbed requests are left out, like every other duration here: a stub that answered an
        /// hour after the last real request would otherwise report an hour of network activity
        /// that never happened.
        var wallClockSpan: TimeInterval?

        /// ``failureCount`` over ``measuredCount``, or `nil` when nothing was measured.
        ///
        /// Computed rather than stored so the denominator can never be zero: a session made
        /// entirely of stubs has no failure rate at all, which is a different statement from a
        /// rate of zero.
        var failureRate: Double? {
            guard measuredCount > 0 else { return nil }
            return Double(failureCount) / Double(measuredCount)
        }

        /// Creates a summary. Every figure defaults to nothing captured.
        init() { }
    }

    /// The figures for one host.
    struct HostBreakdown: Identifiable, Equatable, Sendable {
        /// The lowercased host, which is also the row's identity.
        let id: String

        /// The measured requests sent to this host.
        var requestCount: Int = 0

        /// How many of them failed.
        var failureCount: Int = 0

        /// The nearest-rank median duration in milliseconds, or `nil` when nothing completed.
        var medianDuration: Double?

        /// The total response body length received from this host, in bytes.
        var bytesReceived: Int = 0

        /// ``failureCount`` over ``requestCount``, or `nil` when this host has no requests.
        var failureRate: Double? {
            guard requestCount > 0 else { return nil }
            return Double(failureCount) / Double(requestCount)
        }

        /// Creates a breakdown for `id`.
        ///
        /// - Parameter id: The lowercased host.
        init(id: String) {
            self.id = id
        }
    }

    /// The figures for one endpoint, in the sense of ``TrafficStatistics/endpointIdentity(for:)``.
    struct EndpointBreakdown: Identifiable, Equatable, Sendable {
        /// The endpoint identity, which is also the row's identity.
        let id: String

        /// The measured requests made to this endpoint.
        var requestCount: Int = 0

        /// How many of them failed.
        var failureCount: Int = 0

        /// The nearest-rank median duration in milliseconds, or `nil` when nothing completed.
        var medianDuration: Double?

        /// The slowest duration in milliseconds, or `nil` when nothing completed.
        var slowestDuration: Double?

        /// Creates a breakdown for `id`.
        ///
        /// - Parameter id: The endpoint identity.
        init(id: String) {
            self.id = id
        }
    }

    /// The session-wide figures.
    var summary: Summary

    /// One entry per host, worst first: most failures, then slowest median, then name.
    var hosts: [HostBreakdown]

    /// One entry per endpoint, slowest first, then by identity.
    var endpoints: [EndpointBreakdown]

    /// The figures for a session with nothing captured.
    ///
    /// Used as a view model's initial value so the screen has something to render before the
    /// first computation lands.
    static let empty = TrafficStatistics(summary: Summary(), hosts: [], endpoints: [])

    /// The status code at and above which a response counts as a failure.
    private static let failureStatusFloor = 400

    /// Reduces `requests` to the figures the traffic stats screen shows.
    ///
    /// Walks the array once, bucketing by host and by endpoint identity, then sorts each
    /// breakdown so the worst offender is first. Stubbed requests are counted and then set aside;
    /// see the type's discussion for why.
    ///
    /// - Parameter requests: The requests to summarise, in any order.
    /// - Returns: The figures. Never throws and never fails; an empty input gives ``empty``.
    static func compute(from requests: [HTTPRequest]) -> TrafficStatistics {
        var summary = Summary()
        var durations: [Double] = []
        var hostDurations: [String: [Double]] = [:]
        var endpointDurations: [String: [Double]] = [:]
        var hosts: [String: HostBreakdown] = [:]
        var endpoints: [String: EndpointBreakdown] = [:]
        var earliestStart: Date?
        var latestFinish: Date?

        summary.requestCount = requests.count

        for request in requests {
            guard !request.wasStubbed else {
                summary.stubbedCount += 1
                continue
            }
            summary.measuredCount += 1

            // Dated after the stubbed guard, not before it. The screen's own footer says a
            // stubbed response is "left out of every duration", and the elapsed figure is a
            // duration: a session of one real request and a stub answered an hour later reported
            // an hour of network activity that never happened.
            if let start = request.requestDate {
                if earliestStart == nil || start < earliestStart! {
                    earliestStart = start
                }
                let finish = request.responseDate ?? start
                if latestFinish == nil || finish > latestFinish! {
                    latestFinish = finish
                }
            }

            // A load that ended carries a response date whether or not a response arrived, so it
            // is the only signal that separates "failed" from "still in flight". Without it a
            // failed request counted as both, and seven requests could report seven failures and
            // seven pending at the same time.
            let didFinish = request.responseDate != nil
            let isPending = !didFinish
            let isFailure = didFinish
                && (request.noResponse || (request.responseCode ?? 0) >= failureStatusFloor)
            let duration = measuredDuration(of: request)
            let bytes = request.responseBodyLength ?? 0

            if isPending { summary.pendingCount += 1 }
            if isFailure { summary.failureCount += 1 }
            summary.bytesReceived += bytes
            if let duration {
                summary.completedCount += 1
                durations.append(duration)
            }

            if let host = request.host {
                var breakdown = hosts[host] ?? HostBreakdown(id: host)
                breakdown.requestCount += 1
                if isFailure { breakdown.failureCount += 1 }
                breakdown.bytesReceived += bytes
                hosts[host] = breakdown
                if let duration { hostDurations[host, default: []].append(duration) }
            }

            let identity = endpointIdentity(for: request)
            var endpoint = endpoints[identity] ?? EndpointBreakdown(id: identity)
            endpoint.requestCount += 1
            if isFailure { endpoint.failureCount += 1 }
            endpoints[identity] = endpoint
            if let duration { endpointDurations[identity, default: []].append(duration) }
        }

        let sorted = durations.sorted()
        summary.medianDuration = percentile(0.5, of: sorted)
        summary.p95Duration = percentile(0.95, of: sorted)
        summary.fastestDuration = sorted.first
        summary.slowestDuration = sorted.last
        if let earliestStart, let latestFinish {
            summary.wallClockSpan = max(0, latestFinish.timeIntervalSince(earliestStart))
        }

        for (host, samples) in hostDurations {
            hosts[host]?.medianDuration = percentile(0.5, of: samples.sorted())
        }
        for (identity, samples) in endpointDurations {
            let sortedSamples = samples.sorted()
            endpoints[identity]?.medianDuration = percentile(0.5, of: sortedSamples)
            endpoints[identity]?.slowestDuration = sortedSamples.last
        }

        return TrafficStatistics(
            summary: summary,
            hosts: hosts.values.sorted(by: hostIsBefore),
            endpoints: endpoints.values.sorted(by: endpointIsBefore)
        )
    }

    /// A stable identity for grouping requests by endpoint.
    ///
    /// The query string is dropped and any path segment that is purely numeric, or a UUID, is
    /// replaced with `:id`. Without that collapse a REST API produces one endpoint per record and
    /// the breakdown is useless. A request with no parseable URL is identified by its method
    /// alone, which keeps it visible rather than silently dropping it.
    ///
    /// A GraphQL operation carries its name, in parentheses. Every operation in a GraphQL API is
    /// posted to the same path, so without the name the breakdown collapsed a whole API into one
    /// row called `POST api.example.com/graphql` — while the waterfall, ten lines away on the
    /// same screen, named each operation individually. The name is what identifies the call.
    ///
    /// - Parameter request: The request to identify.
    /// - Returns: `"METHOD host/path"`, for example `"GET api.example.com/v1/users/:id"`, or
    ///   `"POST api.example.com/graphql (GetUser)"` for a named GraphQL operation.
    static func endpointIdentity(for request: HTTPRequest) -> String {
        let method = (request.requestMethod ?? "GET").uppercased()
        guard let url = request.requestURL,
              let components = URLComponents(string: url),
              let host = components.host, !host.isEmpty else {
            return operationSuffixed(method, for: request)
        }
        let segments = components.path.split(separator: "/").map { segment -> String in
            let text = String(segment)
            if !text.isEmpty, text.allSatisfy(\.isNumber) { return ":id" }
            if UUID(uuidString: text) != nil { return ":id" }
            return text
        }
        let path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return operationSuffixed("\(method) \(host.lowercased())\(path)", for: request)
    }

    /// Appends a GraphQL operation name to an endpoint identity, when there is one.
    ///
    /// An unnamed operation — an anonymous query, or a batch — is left as the bare endpoint,
    /// because there is no name to tell it apart by.
    ///
    /// - Parameters:
    ///   - identity: The identity built from the method and URL.
    ///   - request: The request being identified.
    /// - Returns: The identity, with `" (name)"` appended for a named GraphQL operation.
    private static func operationSuffixed(_ identity: String, for request: HTTPRequest) -> String {
        guard request.isGraphQL, let name = request.graphQLOperationName, !name.isEmpty else {
            return identity
        }
        return "\(identity) (\(name))"
    }

    /// The duration of `request` in milliseconds, or `nil` when it is not a measurement.
    ///
    /// A request that never came back has no duration, and a duration that is negative or
    /// non-finite is a clock artefact rather than a round trip. Either would drag a percentile
    /// somewhere no request ever went.
    ///
    /// - Parameter request: The request to measure.
    /// - Returns: The duration in milliseconds, or `nil`.
    private static func measuredDuration(of request: HTTPRequest) -> Double? {
        guard !request.noResponse, let raw = request.requestDuration else { return nil }
        let duration = Double(raw)
        guard duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    /// The nearest-rank value at `percentile` of an ascending sample.
    ///
    /// Nearest rank rather than interpolation, so every reported figure is a duration that a
    /// request actually took. The rank is nudged off a floating-point hair before it is rounded
    /// up: `0.95 * 20` can land a fraction above 19 in binary, which would silently report the
    /// twentieth sample as the 95th percentile of twenty.
    ///
    /// - Parameters:
    ///   - percentile: The percentile as a fraction from 0 to 1.
    ///   - sorted: The sample, sorted ascending.
    /// - Returns: The value at that rank, or `nil` when the sample is empty.
    private static func percentile(_ percentile: Double, of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let position = (percentile * Double(sorted.count) * 1e9).rounded() / 1e9
        let rank = min(sorted.count, max(1, Int(position.rounded(.up))))
        return sorted[rank - 1]
    }

    /// Orders hosts worst first: most failures, then slowest median, then name.
    ///
    /// A host with nothing completed sorts after one with a median, and the name breaks every
    /// remaining tie so the list does not reshuffle between computations.
    ///
    /// - Parameters:
    ///   - lhs: The left host.
    ///   - rhs: The right host.
    /// - Returns: Whether `lhs` sorts before `rhs`.
    private static func hostIsBefore(_ lhs: HostBreakdown, _ rhs: HostBreakdown) -> Bool {
        if lhs.failureCount != rhs.failureCount { return lhs.failureCount > rhs.failureCount }
        if lhs.medianDuration != rhs.medianDuration {
            return isSlower(lhs.medianDuration, than: rhs.medianDuration)
        }
        return lhs.id < rhs.id
    }

    /// Orders endpoints slowest first, then by identity.
    ///
    /// - Parameters:
    ///   - lhs: The left endpoint.
    ///   - rhs: The right endpoint.
    /// - Returns: Whether `lhs` sorts before `rhs`.
    private static func endpointIsBefore(_ lhs: EndpointBreakdown, _ rhs: EndpointBreakdown) -> Bool {
        if lhs.slowestDuration != rhs.slowestDuration {
            return isSlower(lhs.slowestDuration, than: rhs.slowestDuration)
        }
        return lhs.id < rhs.id
    }

    /// Whether `lhs` represents a slower duration than `rhs`, with `nil` sorting last.
    ///
    /// - Parameters:
    ///   - lhs: The left duration, or `nil` when nothing completed.
    ///   - rhs: The right duration, or `nil` when nothing completed.
    /// - Returns: Whether `lhs` sorts before `rhs` in a slowest-first order.
    private static func isSlower(_ lhs: Double?, than rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return false
        }
    }
}
