//
//  NetworkRule.swift
//  Scyther
//

import Foundation

/// A single interception rule: what to match and what to do when it matches.
///
/// A rule is a plain value type with no behaviour of its own beyond matching; ``NetworkRuleEngine``
/// composes enabled rules into an outcome, and ``NetworkRuleStore`` owns their persistence and
/// ordering.
public struct NetworkRule: Identifiable, Codable, Sendable, Equatable {
    /// A stable identifier, used for lookup, editing and deletion.
    public var id: UUID

    /// A short, user-supplied label shown in the rule list and in the log's applied-rules badge.
    public var name: String

    /// Whether this rule is evaluated at all. A disabled rule is skipped entirely by the engine.
    public var isEnabled: Bool

    /// The conditions a request must satisfy for this rule to apply.
    public var match: NetworkRuleMatch

    /// What to do to a matching request.
    public var action: NetworkRuleAction
}

/// The conditions a request must satisfy for a ``NetworkRule`` to apply.
///
/// A rule matches when every non-empty facet matches; an empty or `nil` facet places no
/// constraint on that part of the request.
public struct NetworkRuleMatch: Codable, Sendable, Equatable {
    /// Uppercased HTTP methods. Empty matches any method.
    public var methods: Set<String>

    /// Host pattern, e.g. `api.example.com` or `*.example.com`. Nil matches any host.
    public var host: NetworkRulePattern?

    /// Path pattern, e.g. `/v1/users` or `/v1/*`. Nil matches any path.
    public var path: NetworkRulePattern?

    /// Query items that must all be present with these values. Empty matches any query.
    public var query: [String: String]
}

/// A single string comparison used by ``NetworkRuleMatch`` to test a host or path.
public struct NetworkRulePattern: Codable, Sendable, Equatable {
    /// How ``value`` is compared against a candidate string.
    public enum Kind: String, Codable, Sendable {
        /// The candidate must equal ``value`` exactly, case-insensitively.
        case exact
        /// The candidate must contain ``value`` anywhere, case-insensitively.
        case contains
        /// ``value`` may contain `*` as "any run of characters, including none"; every other
        /// character is matched literally.
        case wildcard
    }

    /// The comparison to use.
    public var kind: Kind

    /// The pattern text, interpreted according to ``kind``.
    public var value: String
}

/// What a matching ``NetworkRule`` does to a request.
public enum NetworkRuleAction: Codable, Sendable, Equatable {
    /// Short-circuits the network and returns a canned response.
    case mock(MockResponse)
    /// Short-circuits the network and returns the contents of a local file.
    case mapLocal(MapLocalFile)
    /// Sets or removes headers on the outgoing request.
    case rewriteHeaders(NetworkHeaderRewrite)
    /// Adds latency, throttles bandwidth, or randomly fails the request.
    case condition(NetworkCondition)
}

/// A canned response synthesised in place of a real network call.
public struct MockResponse: Codable, Sendable, Equatable {
    /// The HTTP status code to return.
    public var statusCode: Int

    /// Response headers to return.
    public var headers: [String: String]

    /// Body id; the bytes live on disk under the rules directory. Nil means an empty body.
    public var bodyID: UUID?

    /// Seconds to wait before responding, simulating network latency.
    public var delay: TimeInterval
}

/// Serves the contents of a local file in place of a real network call.
public struct MapLocalFile: Codable, Sendable, Equatable {
    /// Path relative to the app's Documents directory, chosen with the file browser.
    public var relativePath: String

    /// The HTTP status code to return alongside the file's contents.
    public var statusCode: Int

    /// The `Content-Type` header to return, or `nil` to omit it.
    public var contentType: String?

    /// Seconds to wait before responding, simulating network latency.
    public var delay: TimeInterval
}

/// Headers to set or remove on a matching request before it is sent.
public struct NetworkHeaderRewrite: Codable, Sendable, Equatable {
    /// Headers to set, replacing any existing value.
    public var set: [String: String]

    /// Header names to remove.
    public var remove: [String]
}

/// Latency, bandwidth and failure conditioning applied to a matching request.
public struct NetworkCondition: Codable, Sendable, Equatable {
    /// Seconds added before the request is sent.
    public var latency: TimeInterval

    /// A bandwidth ceiling in kilobytes per second, or `nil` for unthrottled.
    public var bandwidthKBps: Int?

    /// The fraction of matching requests, from `0` to `1`, that fail instead of proceeding.
    public var failureRate: Double

    /// The `URLError.Code` raw value used when a request fails, default `.notConnectedToInternet`.
    public var failureCode: Int
}

public extension NetworkRulePattern {
    /// Whether `candidate` satisfies this pattern. Comparison is case-insensitive.
    ///
    /// - Parameter candidate: The host or path to test.
    func matches(_ candidate: String) -> Bool {
        let subject = candidate.lowercased()
        let pattern = value.lowercased()
        switch kind {
        case .exact:
            return subject == pattern
        case .contains:
            return subject.contains(pattern)
        case .wildcard:
            return Self.wildcardMatches(pattern: pattern, subject: subject)
        }
    }

    /// Matches `*` as "any run of characters, including none". Every other character is literal,
    /// so a pattern containing regex syntax cannot silently mean something else.
    private static func wildcardMatches(pattern: String, subject: String) -> Bool {
        let segments = pattern.components(separatedBy: "*")
        guard segments.count > 1 else { return pattern == subject }

        var index = subject.startIndex
        for (offset, segment) in segments.enumerated() {
            if segment.isEmpty { continue }
            guard let found = subject.range(of: segment, range: index..<subject.endIndex) else {
                return false
            }
            if offset == 0, found.lowerBound != subject.startIndex { return false }
            index = found.upperBound
        }
        if let last = segments.last, !last.isEmpty {
            return subject.hasSuffix(last)
        }
        return true
    }
}

public extension NetworkRuleMatch {
    /// Whether `request` satisfies every non-empty facet of this match.
    ///
    /// An empty facet is a wildcard: no methods means any method, a nil host means any host.
    ///
    /// - Parameter request: The outgoing request to test.
    func matches(_ request: URLRequest) -> Bool {
        if !methods.isEmpty {
            let method = (request.httpMethod ?? "GET").uppercased()
            guard methods.contains(where: { $0.uppercased() == method }) else { return false }
        }
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return methods.isEmpty && host == nil && path == nil && query.isEmpty
        }
        if let host {
            guard let candidate = components.host, host.matches(candidate) else { return false }
        }
        if let path {
            guard path.matches(components.path) else { return false }
        }
        if !query.isEmpty {
            let items = Dictionary(
                (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                uniquingKeysWith: { first, _ in first }
            )
            for (name, value) in query where items[name] != value { return false }
        }
        return true
    }
}
