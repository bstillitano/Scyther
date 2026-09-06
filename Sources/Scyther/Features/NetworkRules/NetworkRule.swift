//
//  NetworkRule.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// A single interception rule: what to match and what to do when it matches.
///
/// A rule is a plain value type with no behaviour of its own beyond matching; the engine composes
/// enabled rules into an outcome, and the store owns their persistence and ordering. Both are
/// internal: a rule is what the host app hands over, and the machinery around it is Scyther's.
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
        ///
        /// - Note: Only intermediate commits of the branch that added request overrides ever
        ///   wrote this key. The feature does not exist in 4.0.0, so no *released* version can
        ///   have persisted one.
        case action
    }

    /// Decodes a rule written in either the current shape or the one that preceded it.
    ///
    /// A rule used to hold one `action`; it now holds an `actions` object. A decode failure costs
    /// the developer **every** override they have configured — `NetworkRuleStore` drops what it
    /// cannot read — so the old key is still understood and lifted into the equivalent
    /// ``NetworkRuleActions``.
    ///
    /// - Important: To be plain about who this is for. Request overrides ship for the first time
    ///   in 4.1.0, so no released version of Scyther ever wrote an `action` key. The documents
    ///   that carry one were written by intermediate commits of the branch that added the
    ///   feature, by a developer running it before it shipped. That is a small audience, and the
    ///   fallback exists for them rather than for any upgrade path from a public release.
    ///
    /// The mapping:
    ///
    /// | Persisted `action` | Becomes |
    /// |---|---|
    /// | `mock` | ``NetworkRuleActions/stub`` = ``NetworkRuleStub/mock(_:)`` |
    /// | `mapLocal` | ``NetworkRuleActions/stub`` = ``NetworkRuleStub/mapLocal(_:)`` |
    /// | `rewriteHeaders` | ``NetworkRuleActions/rewriteHeaders`` |
    /// | `condition` | ``NetworkRuleActions/condition`` |
    ///
    /// An `actions` object this version cannot read is not the end of the attempt. A rule written
    /// by a newer Scyther can carry a facet this build has no case for *and* the legacy `action`
    /// key beside it, and taking the legacy action in that case recovers an override the developer
    /// can still see and still edit. The legacy key remains a fallback rather than a supplement:
    /// an `actions` object that reads cleanly wins outright.
    ///
    /// - Parameter decoder: The decoder positioned at one rule.
    /// - Throws: A decoding error when the rule carries neither shape, or when neither shape it
    ///   carries can be read. The error reported is the one raised by `actions`, since that is the
    ///   shape a rule written now is in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        match = try container.decode(NetworkRuleMatch.self, forKey: .match)
        actions = try Self.decodeActions(from: container)
    }

    /// Reads a rule's actions out of whichever shape it was written in.
    ///
    /// - Parameter container: The rule's own keyed container.
    /// - Returns: The actions to apply.
    /// - Throws: The `actions` object's own error when there is no legacy action to fall back to,
    ///   and `DecodingError.keyNotFound` when the rule carries no readable shape at all.
    private static func decodeActions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NetworkRuleActions {
        guard container.contains(.actions) else {
            return try legacyActions(from: container)
        }
        do {
            return try container.decode(NetworkRuleActions.self, forKey: .actions)
        } catch {
            guard container.contains(.action) else { throw error }
            return try legacyActions(from: container)
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
    /// See ``init(from:)`` for who wrote such a rule: only intermediate commits of this feature's
    /// own branch, never a released version.
    ///
    /// - Parameter container: The rule's own keyed container, positioned at a rule with no
    ///   `actions` key or with one this version cannot read.
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
/// constraint on that part of the request. A pattern whose ``NetworkRulePattern/value`` is the
/// empty string counts as empty, and so constrains nothing either.
///
/// ``matches(_:)`` documents the comparison each facet performs, down to percent-encoding,
/// trailing slashes and repeated query keys.
public struct NetworkRuleMatch: Codable, Sendable, Equatable {
    /// Uppercased HTTP methods. Empty matches any method.
    ///
    /// Compared case-insensitively even so, and a request with no method of its own is treated
    /// as a `GET`, which is what `URLSession` sends for one.
    public var methods: Set<String>

    /// Host pattern, e.g. `api.example.com` or `*.example.com`. Nil matches any host.
    ///
    /// Compared case-insensitively against the host alone: the scheme and the port are not part
    /// of it, so `localhost` matches `http://localhost:8080/health` and `localhost:8080` matches
    /// nothing. A pattern with an empty value places no constraint.
    public var host: NetworkRulePattern?

    /// Path pattern, e.g. `/v1/users` or `/v1/*`. Nil matches any path.
    ///
    /// Compared case-insensitively against the **percent-encoded** path, so `%2F` is not a
    /// separator and a path pasted out of the log matches the request it was copied from. A
    /// trailing slash is significant, a URL with no path is compared as `"/"`, and a pattern with
    /// an empty value places no constraint. See ``matches(_:)``.
    public var path: NetworkRulePattern?

    /// Query items that must all be present with these values. Empty matches any query.
    ///
    /// Names are compared case-sensitively, values after percent-decoding. A key that repeats is
    /// satisfied by any of its occurrences, and a key present with no value reads as `""`.
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
public struct MapLocalFile: Codable, Sendable, Equatable {
    /// The absolute path of the file to serve.
    ///
    /// It is read with `URL(fileURLWithPath:)` and is not resolved against the Documents directory
    /// or any other root. A file picked in the editor is **copied** into the rules directory and
    /// this holds the path of the copy, so the override keeps working after the document the
    /// developer picked has moved or gone away, and no security-scoped bookmark is needed to read
    /// it. A path supplied from code is used as given. A path that cannot be read fails safely:
    /// the responder returns nothing and the request goes to the real network.
    ///
    /// This was called `relativePath` until 4.1.0, which was never true of any value it held, and
    /// was justified in its own documentation as compatibility with rules already persisted under
    /// that name. No released version ever persisted one — the whole request-overrides feature is
    /// absent from 4.0.0 — so the only data written under the old key came from intermediate
    /// commits of the branch that added it. ``init(from:)`` still reads that key, for the handful
    /// of developers who ran one.
    public var path: String

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
    ///
    /// - Note: Capped at 30 seconds when the response is served, exactly as
    ///   ``MockResponse/delay`` is — both stubs are delayed on the same path.
    public var delay: TimeInterval

    /// The keys a map-local action is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``path``.
        case path
        /// ``fileName``.
        case fileName
        /// ``statusCode``.
        case statusCode
        /// ``contentType``.
        case contentType
        /// ``delay``.
        case delay
    }

    /// The key ``path`` was written under before 4.1.0.
    ///
    /// - Note: Nothing any *released* version wrote uses it. The request-overrides feature does
    ///   not exist in 4.0.0, so the only documents carrying this key were written by intermediate
    ///   commits of the branch that added it — a developer who ran one of those builds. It is read
    ///   for their sake and is never written.
    private enum LegacyCodingKeys: String, CodingKey {
        /// The old, and always inaccurate, spelling of ``path``.
        case relativePath
    }

    /// Creates a map-local action.
    ///
    /// - Parameters:
    ///   - path: The absolute path of the file to serve.
    ///   - fileName: The name of the document the file was copied from, for display. Defaults to
    ///     none, which is right for a path supplied from code.
    ///   - statusCode: The HTTP status code to return. Defaults to `200`.
    ///   - contentType: The `Content-Type` header to return, or `nil` to omit it.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    public init(path: String,
                fileName: String? = nil,
                statusCode: Int = 200,
                contentType: String? = nil,
                delay: TimeInterval = 0) {
        self.path = path
        self.fileName = fileName
        self.statusCode = statusCode
        self.contentType = contentType
        self.delay = delay
    }

    /// Reads a map-local action, accepting the pre-4.1.0 spelling of ``path``.
    ///
    /// - Parameter decoder: The decoder positioned at one map-local action.
    /// - Throws: A decoding error when the document carries neither spelling of the path, or when
    ///   any other field cannot be read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .path) {
            self.path = path
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            self.path = try legacy.decode(String.self, forKey: .relativePath)
        }
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.statusCode = try container.decode(Int.self, forKey: .statusCode)
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        self.delay = try container.decode(TimeInterval.self, forKey: .delay)
    }

    /// Writes a map-local action in the current shape. The legacy key is never written.
    ///
    /// - Parameter encoder: The encoder to write to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(statusCode, forKey: .statusCode)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encode(delay, forKey: .delay)
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

internal extension NetworkCondition {
    /// Whether this condition would do anything at all to a request it was applied to.
    ///
    /// A condition with no latency, no ceiling and no failure rate changes nothing: the delay
    /// guard skips a wait of zero, ``BandwidthThrottle/init(bandwidthKBps:maximumTotalSleep:)``
    /// declines to build a throttle for a ceiling that is absent or non-positive, and a failure
    /// rate of zero never fires. ``failureCode`` alone does nothing, because nothing fails.
    ///
    /// ``NetworkRuleEngine`` needs this for the same reason its header merge reports whether a
    /// rewrite asked for a change. The condition facet is first-match-wins, so a do-nothing
    /// condition that was allowed to win would be credited on the log for shaping a request it
    /// left alone *and* would shadow the real condition below it — and it is one tap away, since
    /// switching conditioning on in the editor with nothing remembered assigns exactly this value.
    var shapesTheRequest: Bool {
        latency > 0 || (bandwidthKBps ?? 0) > 0 || failureRate > 0
    }

    /// A copy of this condition with every number JSON cannot express replaced by the one that
    /// does nothing.
    ///
    /// `.infinity` and `.nan` are both reachable from the public API and from a text field —
    /// pasting `1e400` into a latency parses to `inf` — and both are poison twice over.
    /// `JSONEncoder` throws on them, so a condition carrying one cannot be persisted; and `NaN`
    /// compares false against everything, so `min(.nan, cap)` is `NaN` and the interceptor's
    /// `delay > 0` guard then fails, silently erasing a mock's own delay along with the latency.
    ///
    /// A non-finite latency or failure rate becomes `0` — the value that does nothing — rather
    /// than a guess at what the developer meant by infinity.
    var sanitised: NetworkCondition {
        var copy = self
        copy.latency = copy.latency.finiteOrZero
        copy.failureRate = copy.failureRate.finiteOrZero
        return copy
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
        copy.actions.condition = copy.actions.condition?.sanitised
        return copy
    }
}

internal extension Double {
    /// This value when JSON can express it, and `0` when it cannot.
    ///
    /// Infinity and NaN are the two values `JSONEncoder` refuses outright.
    var finiteOrZero: Double { isFinite ? self : 0 }
}

internal extension NetworkHeaderRewrite {
    /// Applies this rewrite to an outgoing request, in place.
    ///
    /// Every entry in ``set`` is applied first and every name in ``remove`` second, so a header
    /// named in both ends up removed. Applying them the other way round would silently keep a
    /// header a rule asked to remove, which is why the order lives in one tested place rather
    /// than at each call site.
    ///
    /// A rewrite merged by ``NetworkRuleEngine`` never names one header in both, so for that one
    /// the order is immaterial; it matters for a rewrite built by hand.
    ///
    /// - Note: Internal, not public. It takes an `NSMutableURLRequest` because the interceptor
    ///   holds one, and putting a Foundation mutable-reference type in the public surface for a
    ///   single internal call site is not worth the API it commits to.
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
    /// Whether `request` satisfies every constraining facet of this match.
    ///
    /// An empty facet is a wildcard: no methods means any method, a nil host means any host, and
    /// a pattern whose ``NetworkRulePattern/value`` is empty means the same as no pattern at all.
    ///
    /// ## The exact semantics
    ///
    /// | Facet | How it is compared |
    /// |---|---|
    /// | Method | Case-insensitively. A request with no method reads as `GET`. |
    /// | Host | Case-insensitively, against the host alone — never the scheme, the port or the userinfo. |
    /// | Path | Case-insensitively, against the **percent-encoded** path, with an empty path read as `"/"`. |
    /// | Query | Every pair listed must be present. Names case-sensitive, values decoded. |
    ///
    /// - Note: The path is compared before percent-decoding, so `%2F` is not a separator:
    ///   `/v1/a%2Fb` is one segment and does not satisfy a rule written for `/v1/a/b`. The
    ///   trade-off is deliberate — a path copied out of the log, out of a HAR or off an address
    ///   bar is percent-encoded, and pasting it into a rule has to match the request it came
    ///   from. A path typed with a literal space or a literal `%` will not.
    ///
    /// - Note: A trailing slash is part of the path. `/v1/users` and `/v1/users/` are different
    ///   paths, and an exact pattern for one does not match the other; use `/v1/users*` to match
    ///   both. A URL with no path at all — `https://api.example.com` — is read as `"/"`, which is
    ///   what a rule built from a log entry or a HAR entry carries for it.
    ///
    /// - Note: A query key that repeats is satisfied by **any** of its occurrences, so a rule
    ///   asking for `page=2` matches `?page=1&page=2`. A key present with no value at all reads
    ///   as an empty value, so `?flag` and `?flag=` both satisfy `flag` = `""`.
    ///
    /// - Parameter request: The outgoing request to test.
    func matches(_ request: URLRequest) -> Bool {
        if !methods.isEmpty {
            let method = (request.httpMethod ?? "GET").uppercased()
            guard methods.contains(where: { $0.uppercased() == method }) else { return false }
        }
        let host = Self.constraining(self.host)
        let path = Self.constraining(self.path)
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return host == nil && path == nil && query.isEmpty
        }
        if let host {
            guard let candidate = components.host, host.matches(candidate) else { return false }
        }
        if let path {
            guard path.matches(Self.candidatePath(of: components)) else { return false }
        }
        if !query.isEmpty {
            let items = components.queryItems ?? []
            for (name, value) in query {
                guard items.contains(where: { $0.name == name && ($0.value ?? "") == value }) else {
                    return false
                }
            }
        }
        return true
    }
}

private extension NetworkRuleMatch {
    /// The pattern to compare against, or `nil` when it constrains nothing.
    ///
    /// A pattern with an empty value is not a comparison against the empty string: this type's
    /// contract is that an empty facet places no constraint, and a half-filled pattern reaching
    /// the matcher from the public API used to constrain the request away entirely.
    ///
    /// - Parameter pattern: The facet as configured.
    /// - Returns: `pattern` when it has something to compare, otherwise `nil`.
    static func constraining(_ pattern: NetworkRulePattern?) -> NetworkRulePattern? {
        guard let pattern, !pattern.value.isEmpty else { return nil }
        return pattern
    }

    /// The path a pattern is compared against: percent-encoded, and never empty.
    ///
    /// - Parameter components: The request URL's components.
    /// - Returns: The percent-encoded path, or `"/"` when the URL carries no path.
    static func candidatePath(of components: URLComponents) -> String {
        components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    }
}
