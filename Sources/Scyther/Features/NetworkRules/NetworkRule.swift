//
//  NetworkRule.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
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

    /// Creates a rule.
    ///
    /// Most callers use the ergonomic constructors — ``mock(name:matching:returning:)`` and its
    /// siblings — rather than this initialiser.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one.
    ///   - name: The label shown in the rule list.
    ///   - isEnabled: Whether the rule is evaluated. Defaults to `true`.
    ///   - match: The requests this rule applies to.
    ///   - action: What to do to a matching request.
    public init(id: UUID = UUID(),
                name: String,
                isEnabled: Bool = true,
                match: NetworkRuleMatch,
                action: NetworkRuleAction) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.action = action
    }
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

    /// Creates a match. Every facet is optional; an omitted one places no constraint.
    ///
    /// ``host(_:path:methods:)`` and ``path(_:methods:)`` cover the common cases without needing
    /// to build patterns by hand.
    ///
    /// - Parameters:
    ///   - methods: Uppercased HTTP methods. Defaults to any method.
    ///   - host: Host pattern. Defaults to any host.
    ///   - path: Path pattern. Defaults to any path.
    ///   - query: Query items that must all be present. Defaults to any query.
    public init(methods: Set<String> = [],
                host: NetworkRulePattern? = nil,
                path: NetworkRulePattern? = nil,
                query: [String: String] = [:]) {
        self.methods = methods
        self.host = host
        self.path = path
        self.query = query
    }
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

    /// Creates a pattern.
    ///
    /// - Parameters:
    ///   - kind: The comparison to use.
    ///   - value: The pattern text.
    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
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

    /// Creates a canned response.
    ///
    /// ``json(_:status:delay:)`` is the easier way to return a JSON body, because it writes the
    /// bytes to disk and fills in ``bodyID`` for you.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code. Defaults to `200`.
    ///   - headers: Response headers. Defaults to none.
    ///   - bodyID: The identifier of a body stored on disk, or `nil` for an empty body.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    public init(statusCode: Int = 200,
                headers: [String: String] = [:],
                bodyID: UUID? = nil,
                delay: TimeInterval = 0) {
        self.statusCode = statusCode
        self.headers = headers
        self.bodyID = bodyID
        self.delay = delay
    }
}

/// Serves the contents of a local file in place of a real network call.
///
/// - Important: ``relativePath`` holds an **absolute** file path despite its name. The name is
///   retained for compatibility with rules already persisted under it.
public struct MapLocalFile: Codable, Sendable, Equatable {
    /// The absolute path of the file to serve, as chosen with the file browser.
    ///
    /// - Important: Absolute, despite the name — it is read with `URL(fileURLWithPath:)` and is
    ///   not resolved against the Documents directory or any other root.
    public var relativePath: String

    /// The HTTP status code to return alongside the file's contents.
    public var statusCode: Int

    /// The `Content-Type` header to return, or `nil` to omit it.
    public var contentType: String?

    /// Seconds to wait before responding, simulating network latency.
    public var delay: TimeInterval

    /// Creates a map-local action.
    ///
    /// - Parameters:
    ///   - relativePath: The absolute path of the file to serve.
    ///   - statusCode: The HTTP status code to return. Defaults to `200`.
    ///   - contentType: The `Content-Type` header to return, or `nil` to omit it.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    public init(relativePath: String,
                statusCode: Int = 200,
                contentType: String? = nil,
                delay: TimeInterval = 0) {
        self.relativePath = relativePath
        self.statusCode = statusCode
        self.contentType = contentType
        self.delay = delay
    }
}

/// Headers to set or remove on a matching request before it is sent.
public struct NetworkHeaderRewrite: Codable, Sendable, Equatable {
    /// Headers to set, replacing any existing value.
    public var set: [String: String]

    /// Header names to remove.
    public var remove: [String]

    /// Creates a header rewrite.
    ///
    /// - Parameters:
    ///   - set: Headers to set, replacing any existing value. Defaults to none.
    ///   - remove: Header names to remove. Defaults to none.
    public init(set: [String: String] = [:], remove: [String] = []) {
        self.set = set
        self.remove = remove
    }
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

    /// Creates a set of network conditions.
    ///
    /// ```swift
    /// NetworkCondition(latency: 2, failureRate: 0.1)
    /// ```
    ///
    /// - Parameters:
    ///   - latency: Seconds added before the request is sent. Defaults to none.
    ///   - bandwidthKBps: A bandwidth ceiling in kilobytes per second. Defaults to unthrottled.
    ///   - failureRate: The fraction of matching requests, from `0` to `1`, that fail instead of
    ///     proceeding. Defaults to none.
    ///   - failureCode: The `URLError.Code` raw value used when a request fails. Defaults to
    ///     `.notConnectedToInternet`.
    public init(latency: TimeInterval = 0,
                bandwidthKBps: Int? = nil,
                failureRate: Double = 0,
                failureCode: Int = URLError.Code.notConnectedToInternet.rawValue) {
        self.latency = latency
        self.bandwidthKBps = bandwidthKBps
        self.failureRate = failureRate
        self.failureCode = failureCode
    }
}

public extension NetworkHeaderRewrite {
    /// Applies this rewrite to an outgoing request, in place.
    ///
    /// Every entry in ``set`` is applied first and every name in ``remove`` second, so a header
    /// named in both ends up removed. Applying them the other way round would silently keep a
    /// header a rule asked to remove, which is why the order lives in one tested place rather
    /// than at each call site.
    ///
    /// - Parameter request: The request to rewrite. Mutated in place.
    func apply(to request: NSMutableURLRequest) {
        set.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        remove.forEach { request.setValue(nil, forHTTPHeaderField: $0) }
    }
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
            return host == nil && path == nil && query.isEmpty
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
