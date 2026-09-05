//
//  NetworkRules.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Mocks, conditions and rewrites matching HTTP requests.
///
/// Reached through ``Scyther/Network/rules``. Rules added here are evaluated in order for every
/// request Scyther intercepts: the first matching mock or map-local short-circuits the network,
/// the first matching condition applies its latency and failure rate, and every matching header
/// rewrite is applied.
///
/// ## Usage
///
/// ```swift
/// // Persisted: survives relaunch and appears in the debug menu.
/// Scyther.network.rules.add(
///     .mock(name: "Empty cart", matching: .path("/api/cart"), returning: .json("{}"))
/// )
///
/// // This launch only: never written to disk.
/// Scyther.network.rules.addTransient(
///     .headers(name: "Staging auth",
///              matching: .host("*.staging.example.com"),
///              set: ["Authorization": "Bearer test"])
/// )
///
/// // Turn every rule off without deleting any of them.
/// Scyther.network.rules.isEnabled = false
/// ```
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Reading Rules
/// - ``all``
/// - ``transient``
/// - ``isEnabled``
///
/// ### Managing Rules
/// - ``add(_:)``
/// - ``addTransient(_:)``
/// - ``update(_:)``
/// - ``remove(id:)``
/// - ``removeAll()``
///
/// - Note: Isolated to the main actor, like every other Scyther singleton, so the compiler
///   enforces safe access to the store rather than leaving it to a runtime check.
@MainActor
public final class NetworkRules: Sendable {
    /// The shared rules instance.
    public static let shared = NetworkRules()
    private init() {}

    /// Every rule that survives relaunch, in precedence order.
    public var all: [NetworkRule] {
        NetworkRuleStore.shared.rules
    }

    /// Every rule registered for this launch only, evaluated after ``all``.
    public var transient: [NetworkRule] {
        NetworkRuleStore.shared.transientRules
    }

    /// The master switch. When `false` no rule is applied, but none is deleted either.
    public var isEnabled: Bool {
        get { NetworkRuleStore.shared.isEnabled }
        set { NetworkRuleStore.shared.isEnabled = newValue }
    }

    /// Adds a rule that survives relaunch, at the lowest precedence.
    ///
    /// - Parameter rule: The rule to add.
    public func add(_ rule: NetworkRule) {
        NetworkRuleStore.shared.add(rule)
    }

    /// Adds a rule for this launch only. Nothing is written to disk.
    ///
    /// Use this for rules the app installs for itself — a UI test's stubbed endpoints, say — so
    /// that they cannot outlive the run that created them.
    ///
    /// - Parameter rule: The rule to add.
    public func addTransient(_ rule: NetworkRule) {
        NetworkRuleStore.shared.addTransient(rule)
    }

    /// Replaces the rule carrying the same identifier, leaving its position alone.
    ///
    /// - Parameter rule: The edited rule.
    public func update(_ rule: NetworkRule) {
        NetworkRuleStore.shared.update(rule)
    }

    /// Deletes a rule, along with any mock body it owns.
    ///
    /// - Parameter id: The identifier of the rule to delete.
    public func remove(id: UUID) {
        NetworkRuleStore.shared.remove(id: id)
    }

    /// Deletes every rule, persisted and transient, and every mock body they own.
    public func removeAll() {
        NetworkRuleStore.shared.removeAll()
    }
}

public extension NetworkRule {
    /// A rule that answers matching requests with a canned response instead of hitting the network.
    ///
    /// - Parameters:
    ///   - name: The label shown in the rule list and in the log's applied-rules badge.
    ///   - matching: The requests this rule applies to.
    ///   - returning: The response to synthesise.
    /// - Returns: An enabled rule.
    static func mock(name: String,
                     matching: NetworkRuleMatch,
                     returning: MockResponse) -> NetworkRule {
        NetworkRule(id: UUID(), name: name, isEnabled: true, match: matching, action: .mock(returning))
    }

    /// A rule that slows, throttles or randomly fails matching requests.
    ///
    /// - Parameters:
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - condition: The latency, bandwidth ceiling and failure rate to apply.
    /// - Returns: An enabled rule.
    static func condition(name: String,
                          matching: NetworkRuleMatch,
                          _ condition: NetworkCondition) -> NetworkRule {
        NetworkRule(id: UUID(), name: name, isEnabled: true, match: matching, action: .condition(condition))
    }

    /// A rule that sets or removes headers on matching requests before they are sent.
    ///
    /// - Parameters:
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - set: Headers to set, replacing any existing value.
    ///   - remove: Header names to remove. A name in both is removed.
    /// - Returns: An enabled rule.
    static func headers(name: String,
                        matching: NetworkRuleMatch,
                        set: [String: String] = [:],
                        remove: [String] = []) -> NetworkRule {
        NetworkRule(id: UUID(),
                    name: name,
                    isEnabled: true,
                    match: matching,
                    action: .rewriteHeaders(NetworkHeaderRewrite(set: set, remove: remove)))
    }

    /// A rule that answers matching requests with the contents of a local file.
    ///
    /// - Parameters:
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - serving: The file to serve, described by its absolute path.
    /// - Returns: An enabled rule.
    static func mapLocal(name: String,
                         matching: NetworkRuleMatch,
                         serving: MapLocalFile) -> NetworkRule {
        NetworkRule(id: UUID(), name: name, isEnabled: true, match: matching, action: .mapLocal(serving))
    }
}

public extension NetworkRuleMatch {
    /// Matches requests to a host, optionally narrowed to a path and a set of methods.
    ///
    /// Both `host` and `path` may contain `*`, meaning any run of characters; a value without one
    /// must match exactly. Comparison is case-insensitive.
    ///
    /// ```swift
    /// .host("api.example.com", path: "/v1/*", methods: ["POST"])
    /// ```
    ///
    /// - Parameters:
    ///   - host: The host to match, e.g. `api.example.com` or `*.example.com`.
    ///   - path: The path to match, or `nil` for any path.
    ///   - methods: The HTTP methods to match, or empty for any method.
    /// - Returns: A match describing those requests.
    static func host(_ host: String,
                     path: String? = nil,
                     methods: Set<String> = []) -> NetworkRuleMatch {
        NetworkRuleMatch(methods: methods,
                         host: .pattern(host),
                         path: path.map(NetworkRulePattern.pattern),
                         query: [:])
    }

    /// Matches requests to a path on any host, optionally narrowed to a set of methods.
    ///
    /// - Parameters:
    ///   - path: The path to match, e.g. `/v1/users` or `/v1/*`.
    ///   - methods: The HTTP methods to match, or empty for any method.
    /// - Returns: A match describing those requests.
    static func path(_ path: String, methods: Set<String> = []) -> NetworkRuleMatch {
        NetworkRuleMatch(methods: methods, host: nil, path: .pattern(path), query: [:])
    }
}

internal extension NetworkRulePattern {
    /// Reads a pattern the way a developer writes one: `*` means wildcard, anything else is exact.
    ///
    /// - Parameter value: The pattern text.
    /// - Returns: A wildcard pattern when `value` contains `*`, otherwise an exact one.
    static func pattern(_ value: String) -> NetworkRulePattern {
        NetworkRulePattern(kind: value.contains("*") ? .wildcard : .exact, value: value)
    }
}

public extension MockResponse {
    /// A JSON response. The body is written to disk and the rule stores only its identifier.
    ///
    /// - Parameters:
    ///   - body: The JSON text to return.
    ///   - status: The HTTP status code. Defaults to `200`.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    /// - Returns: A response carrying `Content-Type: application/json`.
    ///
    /// - Note: Isolated to the main actor because it writes the body through the rule store.
    @MainActor
    static func json(_ body: String,
                     status: Int = 200,
                     delay: TimeInterval = 0) -> MockResponse {
        let bodyID = NetworkRuleStore.shared.storeBody(Data(body.utf8))
        return MockResponse(statusCode: status,
                            headers: ["Content-Type": "application/json"],
                            bodyID: bodyID,
                            delay: delay)
    }

    /// A response with no body, for endpoints whose status code is the whole answer.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code. Defaults to `204`.
    ///   - delay: Seconds to wait before responding. Defaults to none.
    /// - Returns: A response with no headers and no body.
    static func empty(status: Int = 204, delay: TimeInterval = 0) -> MockResponse {
        MockResponse(statusCode: status, headers: [:], bodyID: nil, delay: delay)
    }
}
