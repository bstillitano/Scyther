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

    /// What to do to a matching request. Every facet composes; see ``NetworkRuleActions``.
    public var actions: NetworkRuleActions

    /// Creates a rule.
    ///
    /// Most callers use the ergonomic constructors — ``mock(id:name:matching:returning:)`` and its
    /// siblings — rather than this initialiser.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one.
    ///   - name: The label shown in the rule list.
    ///   - isEnabled: Whether the rule is evaluated. Defaults to `true`.
    ///   - match: The requests this rule applies to.
    ///   - actions: What to do to a matching request. Defaults to nothing at all, which the
    ///     editor refuses to save but which is a legal value for a rule built in code and filled
    ///     in afterwards.
    public init(id: UUID = UUID(),
                name: String,
                isEnabled: Bool = true,
                match: NetworkRuleMatch,
                actions: NetworkRuleActions = NetworkRuleActions()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.actions = actions
    }

    /// The keys a rule is persisted under.
    ///
    /// Spelled out rather than synthesised so that renaming a property in Swift cannot silently
    /// orphan every override a developer has saved.
    private enum CodingKeys: String, CodingKey {
        /// ``id``.
        case id
        /// ``name``.
        case name
        /// ``isEnabled``.
        case isEnabled
        /// ``match``.
        case match
        /// ``actions``.
        case actions
        /// The single action a rule carried before actions became composable.
        case action
    }

    /// Decodes a rule written in either the current shape or the one that preceded it.
    ///
    /// A rule used to hold one `action`; it now holds an `actions` object. A decode failure costs
    /// the developer **every** override they have configured — ``NetworkRuleStore`` drops what it
    /// cannot read — so the old key is still understood and lifted into the equivalent
    /// ``NetworkRuleActions``:
    ///
    /// | Persisted `action` | Becomes |
    /// |---|---|
    /// | `mock` | ``NetworkRuleActions/stub`` = ``NetworkRuleStub/mock(_:)`` |
    /// | `mapLocal` | ``NetworkRuleActions/stub`` = ``NetworkRuleStub/mapLocal(_:)`` |
    /// | `rewriteHeaders` | ``NetworkRuleActions/rewriteHeaders`` |
    /// | `condition` | ``NetworkRuleActions/condition`` |
    ///
    /// - Parameter decoder: The decoder positioned at one rule.
    /// - Throws: A decoding error when the rule carries neither shape, or when a facet either
    ///   shape names cannot be read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        match = try container.decode(NetworkRuleMatch.self, forKey: .match)

        if let actions = try container.decodeIfPresent(NetworkRuleActions.self, forKey: .actions) {
            self.actions = actions
        } else {
            self.actions = try Self.legacyActions(from: container)
        }
    }

    /// Writes a rule in the current shape. The legacy `action` key is never written.
    ///
    /// - Parameter encoder: The encoder to write to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(match, forKey: .match)
        try container.encode(actions, forKey: .actions)
    }

    /// The four cases the retired `NetworkRuleAction` enum was persisted under.
    private enum LegacyActionKey: String, CodingKey {
        /// A canned response.
        case mock
        /// A local file.
        case mapLocal
        /// Headers to set or remove.
        case rewriteHeaders
        /// Latency, bandwidth and failure rate.
        case condition
    }

    /// The single positional key the compiler synthesises for an enum's associated value.
    private enum LegacyPayloadKey: String, CodingKey {
        /// The action's payload, e.g. the `MockResponse` inside `.mock(_:)`.
        case _0
    }

    /// Lifts a rule persisted with one `action` into the composable shape.
    ///
    /// - Parameter container: The rule's own keyed container, positioned at a rule with no
    ///   `actions` key.
    /// - Returns: The equivalent actions.
    /// - Throws: `DecodingError.keyNotFound` when the rule carries no recognisable action at all,
    ///   which is what tells ``NetworkRuleStore`` to drop it rather than store a rule that does
    ///   nothing.
    private static func legacyActions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NetworkRuleActions {
        let action = try container.nestedContainer(keyedBy: LegacyActionKey.self, forKey: .action)

        if action.contains(.mock) {
            return NetworkRuleActions(stub: .mock(try legacyPayload(MockResponse.self, from: action, forKey: .mock)))
        }
        if action.contains(.mapLocal) {
            return NetworkRuleActions(stub: .mapLocal(try legacyPayload(MapLocalFile.self, from: action, forKey: .mapLocal)))
        }
        if action.contains(.rewriteHeaders) {
            return NetworkRuleActions(
                rewriteHeaders: try legacyPayload(NetworkHeaderRewrite.self, from: action, forKey: .rewriteHeaders)
            )
        }
        if action.contains(.condition) {
            return NetworkRuleActions(
                condition: try legacyPayload(NetworkCondition.self, from: action, forKey: .condition)
            )
        }

        throw DecodingError.keyNotFound(
            CodingKeys.actions,
            DecodingError.Context(codingPath: container.codingPath,
                                  debugDescription: "A rule must carry either actions or a legacy action.")
        )
    }

    /// Reads one legacy action's payload out from under its positional key.
    ///
    /// - Parameters:
    ///   - type: The payload type to decode.
    ///   - container: The legacy action's container.
    ///   - key: Which of the four cases is present.
    /// - Returns: The decoded payload.
    /// - Throws: Whatever decoding the payload throws.
    private static func legacyPayload<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<LegacyActionKey>,
        forKey key: LegacyActionKey
    ) throws -> T {
        let payload = try container.nestedContainer(keyedBy: LegacyPayloadKey.self, forKey: key)
        return try payload.decode(T.self, forKey: ._0)
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

    /// The keys a match is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``methods``.
        case methods
        /// ``host``.
        case host
        /// ``path``.
        case path
        /// ``query``.
        case query
    }

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

    /// The keys a pattern is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``kind``.
        case kind
        /// ``value``.
        case value
    }

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

/// A canned response synthesised in place of a real network call.
public struct MockResponse: Codable, Sendable, Equatable {
    /// The HTTP status code to return.
    public var statusCode: Int

    /// Response headers to return.
    ///
    /// - Important: A dictionary, so a mocked response cannot carry two headers of the same name.
    ///   Where a real response may repeat one — `Set-Cookie` above all — only one value survives,
    ///   and a HAR import silently keeps the last of the repeats. Mock a response that depends on
    ///   repeated headers and the app will see fewer of them than the server sent.
    public var headers: [String: String]

    /// Body id; the bytes live on disk under the rules directory. Nil means an empty body.
    public var bodyID: UUID?

    /// Seconds to wait before responding, simulating network latency.
    ///
    /// - Note: Capped at 30 seconds when the response is served.
    public var delay: TimeInterval

    /// Body bytes waiting to be written, carried until the rule holding them is stored.
    ///
    /// ``json(_:status:delay:)`` used to write its bytes at value-construction time, through the
    /// shared store: a value built in a test wrote into the real Application Support container,
    /// and a value built on an App Store launch wrote a file for a feature that never runs. The
    /// bytes now travel with the value, and ``NetworkRuleStore`` writes them — into *its* body
    /// directory — when the rule is added or updated, filling in ``bodyID``. A value that is
    /// simply discarded leaves nothing on disk to reclaim.
    ///
    /// Never persisted: by the time a rule reaches `UserDefaults` its bytes are on disk and
    /// ``bodyID`` points at them.
    internal var pendingBody: Data?

    /// The keys a canned response is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename,
    /// and so a property that must never be persisted cannot be added to one by accident.
    /// - Important: ``pendingBody`` is deliberately absent. It is bytes on their way to disk, not
    ///   part of the stored shape.
    private enum CodingKeys: String, CodingKey {
        /// ``statusCode``.
        case statusCode
        /// ``headers``.
        case headers
        /// ``bodyID``.
        case bodyID
        /// ``delay``.
        case delay
    }

    /// Creates a canned response.
    ///
    /// ``json(_:status:delay:)`` is the easier way to return a JSON body, because it carries the
    /// bytes until the rule holding it is stored, and the store fills in ``bodyID``.
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
    /// The absolute path of the file to serve.
    ///
    /// - Important: Absolute, despite the name — it is read with `URL(fileURLWithPath:)` and is
    ///   not resolved against the Documents directory or any other root. A file picked in the
    ///   editor is **copied** into the rules directory and this holds the path of the copy, so the
    ///   override keeps working after the document the developer picked has moved or gone away,
    ///   and no security-scoped bookmark is needed to read it. A path supplied from code is used
    ///   as given. A path that cannot be read fails safely: the responder returns nothing and the
    ///   request goes to the real network.
    public var relativePath: String

    /// The name of the document the copy was made from, for display in the editor.
    ///
    /// The copy itself is named after an identifier so it can be swept like a mock body, which
    /// tells a developer nothing about what they picked. `nil` for a file supplied from code, and
    /// for one persisted before this field existed.
    public var fileName: String?

    /// The HTTP status code to return alongside the file's contents.
    public var statusCode: Int

    /// The `Content-Type` header to return, or `nil` to omit it.
    public var contentType: String?

    /// Seconds to wait before responding, simulating network latency.
    public var delay: TimeInterval

    /// The keys a map-local action is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``relativePath``.
        case relativePath
        /// ``fileName``.
        case fileName
        /// ``statusCode``.
        case statusCode
        /// ``contentType``.
        case contentType
        /// ``delay``.
        case delay
    }

    /// Creates a map-local action.
    ///
    /// - Parameters:
    ///   - relativePath: The absolute path of the file to serve.
    ///   - fileName: The name of the document the file was copied from, for display. Defaults to
    ///     none, which is right for a path supplied from code.
    ///   - statusCode: The HTTP status code to return. Defaults to `200`.
    ///   - contentType: The `Content-Type` header to return, or `nil` to omit it.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    public init(relativePath: String,
                fileName: String? = nil,
                statusCode: Int = 200,
                contentType: String? = nil,
                delay: TimeInterval = 0) {
        self.relativePath = relativePath
        self.fileName = fileName
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

    /// The keys a header rewrite is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``set``.
        case set
        /// ``remove``.
        case remove
    }

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
    ///
    /// - Note: Capped at 30 seconds when the condition is applied.
    public var latency: TimeInterval

    /// A bandwidth ceiling in kilobytes per second, or `nil` for unthrottled.
    ///
    /// - Important: The ceiling is honoured for at most 30 seconds of added delay across one
    ///   response, so that a debug tool can never appear to have hung. A body larger than
    ///   `30 × bandwidthKBps` kilobytes therefore stops being paced part-way through and the
    ///   remainder is forwarded as fast as it arrives — 1 MB at 10 KB/s takes about 30 seconds
    ///   rather than the 100 the ceiling implies. Pick a ceiling with the body size in mind, or
    ///   read the effective rate off the log rather than off the rule.
    public var bandwidthKBps: Int?

    /// The fraction of matching requests, from `0` to `1`, that fail instead of proceeding.
    public var failureRate: Double

    /// The `URLError.Code` raw value used when a request fails, default `.notConnectedToInternet`.
    public var failureCode: Int

    /// The keys a condition is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``latency``.
        case latency
        /// ``bandwidthKBps``.
        case bandwidthKBps
        /// ``failureRate``.
        case failureRate
        /// ``failureCode``.
        case failureCode
    }

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

internal extension NetworkRule {
    /// A copy of this rule with every number JSON cannot express replaced by the one that does
    /// nothing.
    ///
    /// `JSONEncoder` throws on a non-finite `Double`, and `.infinity` is reachable from both the
    /// public API and the editor — pasting `1e400` into a latency field parses to `inf`. An
    /// encode that throws would leave the in-memory rules and the persisted blob disagreeing from
    /// then on, and, because the offending rule stays in the array, every later mutation would
    /// fail to persist too. ``NetworkRuleStore`` sanitises on the way in so the encoder can never
    /// be handed one.
    ///
    /// A non-finite delay, latency or failure rate becomes `0` — the value that does nothing —
    /// rather than a guess at what the developer meant by infinity.
    var sanitised: NetworkRule {
        var copy = self
        switch copy.actions.stub {
        case .mock(var mock):
            mock.delay = mock.delay.finiteOrZero
            copy.actions.stub = .mock(mock)
        case .mapLocal(var file):
            file.delay = file.delay.finiteOrZero
            copy.actions.stub = .mapLocal(file)
        case nil:
            break
        }
        if var condition = copy.actions.condition {
            condition.latency = condition.latency.finiteOrZero
            condition.failureRate = condition.failureRate.finiteOrZero
            copy.actions.condition = condition
        }
        return copy
    }
}

private extension Double {
    /// This value when JSON can express it, and `0` when it cannot.
    ///
    /// Infinity and NaN are the two values `JSONEncoder` refuses outright.
    var finiteOrZero: Double { isFinite ? self : 0 }
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
