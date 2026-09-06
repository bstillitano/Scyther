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
/// request Scyther intercepts: the first matching stub short-circuits the network, the first
/// matching condition applies its latency, bandwidth ceiling and failure rate, and every matching
/// header rewrite is applied.
///
/// A rule carries as many of those as it likes — see ``NetworkRuleActions`` — so an endpoint can
/// be mocked *and* made slow. The ergonomic constructors below each build one action; build a
/// ``NetworkRule`` directly to combine them:
///
/// ```swift
/// Scyther.network.rules.add(
///     NetworkRule(name: "Slow cart",
///                 match: .path("/api/cart"),
///                 actions: NetworkRuleActions(stub: .mock(.json("{}")),
///                                             condition: NetworkCondition(latency: 3)))
/// )
/// ```
///
/// ## Usage
///
/// ```swift
/// // Persisted: survives relaunch and appears in the debug menu. The identifier is a
/// // constant, so a relaunch updates this rule instead of storing a second copy of it.
/// Scyther.network.rules.add(
///     .mock(id: UUID(uuidString: "6F0B0C3E-4C1E-4E3D-9C0B-0F5E7A9D2B41")!,
///           name: "Empty cart",
///           matching: .path("/api/cart"),
///           returning: .json("{}"))
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
/// ## Production safety
///
/// Every member here is inert until ``Scyther/start(allowProductionBuilds:)`` has run, which it does not do on an App
/// Store build unless the host app explicitly asks for it. A reader hands back nothing and a
/// mutator writes nothing — not to `UserDefaults`, not to disk. The usage above is exactly what
/// the documentation suggests putting in `didFinishLaunching`, and a debugging tool has no
/// business creating directories in a user's container for a feature that will never run.
///
/// - Note: Isolated to the main actor, like every other Scyther singleton, so the compiler
///   enforces safe access to the store rather than leaving it to a runtime check.
@MainActor
public final class NetworkRules: Sendable {
    /// The shared rules instance.
    public static let shared = NetworkRules()
    private init() {}

    /// Every rule that survives relaunch, in precedence order.
    ///
    /// Empty until ``Scyther/start(allowProductionBuilds:)`` has run, because until then no rule is being applied.
    public var all: [NetworkRule] {
        guard Scyther.isStarted else { return [] }
        return NetworkRuleStore.shared.rules
    }

    /// Every rule registered for this launch only, evaluated after ``all``.
    ///
    /// Empty until ``Scyther/start(allowProductionBuilds:)`` has run, because until then no rule is being applied.
    public var transient: [NetworkRule] {
        guard Scyther.isStarted else { return [] }
        return NetworkRuleStore.shared.transientRules
    }

    /// The master switch. When `false` no rule is applied, but none is deleted either.
    ///
    /// Reads as `false` and ignores writes until ``Scyther/start(allowProductionBuilds:)`` has run: the interceptor is
    /// not installed, so nothing is being applied whatever this said.
    public var isEnabled: Bool {
        get { Scyther.isStarted && NetworkRuleStore.shared.isEnabled }
        set {
            guard Scyther.isStarted else { return }
            NetworkRuleStore.shared.isEnabled = newValue
        }
    }

    /// Adds a rule that survives relaunch, at the lowest precedence.
    ///
    /// Adding is an **upsert**: a rule whose ``NetworkRule/id`` is already stored replaces that
    /// rule in place. Give a rule a stable identifier when the same call runs on every launch —
    /// from `didFinishLaunching`, say — or each launch stores another copy of it:
    ///
    /// ```swift
    /// // The identifier is a constant, so relaunching updates this override rather than
    /// // adding a second one beside it.
    /// let emptyCart = UUID(uuidString: "6F0B0C3E-4C1E-4E3D-9C0B-0F5E7A9D2B41")!
    /// Scyther.network.rules.add(
    ///     .mock(id: emptyCart,
    ///           name: "Empty cart",
    ///           matching: .path("/api/cart"),
    ///           returning: .json("{}"))
    /// )
    /// ```
    ///
    /// A rule built without an identifier gets a fresh one, which is right for a rule created
    /// once — from the menu, or behind a launch argument — and wrong for one registered on every
    /// launch.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a rule already stored under the
    ///   same identifier.
    /// - Returns: `false` when nothing was stored — because ``Scyther/start(allowProductionBuilds:)`` has not run, or
    ///   because a mock body the rule carried could not be written to disk. `true` otherwise.
    @discardableResult
    public func add(_ rule: NetworkRule) -> Bool {
        guard Scyther.isStarted else { return false }
        return NetworkRuleStore.shared.add(rule)
    }

    /// Adds a rule for this launch only. Nothing is written to disk.
    ///
    /// Use this for rules the app installs for itself — a UI test's stubbed endpoints, say — so
    /// that they cannot outlive the run that created them.
    ///
    /// Upserts by ``NetworkRule/id`` exactly as ``add(_:)`` does, so registering the same rule
    /// twice within one launch leaves one rule rather than two.
    ///
    /// An identifier lives in exactly one of the two lists, so registering a transient rule under
    /// an identifier ``add(_:)`` stored moves it across rather than leaving two copies.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a rule already registered under
    ///   the same identifier.
    /// - Returns: `false` when nothing was stored — because ``Scyther/start(allowProductionBuilds:)`` has not run, or
    ///   because a mock body the rule carried could not be written to disk. `true` otherwise.
    @discardableResult
    public func addTransient(_ rule: NetworkRule) -> Bool {
        guard Scyther.isStarted else { return false }
        return NetworkRuleStore.shared.addTransient(rule)
    }

    /// Replaces the rule carrying the same identifier, leaving its position alone.
    ///
    /// - Parameter rule: The edited rule.
    /// - Returns: `false` when the edit was not applied — because ``Scyther/start(allowProductionBuilds:)`` has not run,
    ///   or because a mock body the rule carried could not be written to disk. `true` otherwise,
    ///   including when no rule carries this identifier and there is nothing to update.
    @discardableResult
    public func update(_ rule: NetworkRule) -> Bool {
        guard Scyther.isStarted else { return false }
        return NetworkRuleStore.shared.update(rule)
    }

    /// Deletes a rule, along with any mock body it owns.
    ///
    /// - Parameter id: The identifier of the rule to delete.
    public func remove(id: UUID) {
        guard Scyther.isStarted else { return }
        NetworkRuleStore.shared.remove(id: id)
    }

    /// Deletes every rule, persisted and transient, and every mock body they own.
    ///
    /// Also discards any configuration a launch could not read and set aside, which is the only
    /// way to discard one. Until it is discarded the orphan sweep stands down, because the store
    /// cannot tell which files on disk belong to overrides it could not decode.
    public func removeAll() {
        guard Scyther.isStarted else { return }
        NetworkRuleStore.shared.removeAll()
    }
}

public extension NetworkRule {
    /// A rule that answers matching requests with a canned response instead of hitting the network.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one; pass a constant when the same call
    ///     runs on every launch, so ``NetworkRules/add(_:)`` updates the rule rather than adding
    ///     another copy of it.
    ///   - name: The label shown in the rule list and in the log's applied-rules badge.
    ///   - matching: The requests this rule applies to.
    ///   - returning: The response to synthesise.
    /// - Returns: An enabled rule.
    static func mock(id: UUID = UUID(),
                     name: String,
                     matching: NetworkRuleMatch,
                     returning: MockResponse) -> NetworkRule {
        NetworkRule(id: id,
                    name: name,
                    isEnabled: true,
                    match: matching,
                    actions: NetworkRuleActions(stub: .mock(returning)))
    }

    /// A rule that slows, throttles or randomly fails matching requests.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one; pass a constant when the same call
    ///     runs on every launch.
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - condition: The latency, bandwidth ceiling and failure rate to apply.
    /// - Returns: An enabled rule.
    static func condition(id: UUID = UUID(),
                          name: String,
                          matching: NetworkRuleMatch,
                          _ condition: NetworkCondition) -> NetworkRule {
        NetworkRule(id: id,
                    name: name,
                    isEnabled: true,
                    match: matching,
                    actions: NetworkRuleActions(condition: condition))
    }

    /// A rule that sets or removes headers on matching requests before they are sent.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one; pass a constant when the same call
    ///     runs on every launch.
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - set: Headers to set, replacing any existing value.
    ///   - remove: Header names to remove. A name in both is removed.
    /// - Returns: An enabled rule.
    static func headers(id: UUID = UUID(),
                        name: String,
                        matching: NetworkRuleMatch,
                        set: [String: String] = [:],
                        remove: [String] = []) -> NetworkRule {
        NetworkRule(id: id,
                    name: name,
                    isEnabled: true,
                    match: matching,
                    actions: NetworkRuleActions(
                        rewriteHeaders: NetworkHeaderRewrite(set: set, remove: remove)
                    ))
    }

    /// A rule that answers matching requests with the contents of a local file.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one; pass a constant when the same call
    ///     runs on every launch.
    ///   - name: The label shown in the rule list.
    ///   - matching: The requests this rule applies to.
    ///   - serving: The file to serve, described by its absolute path. It must be an **absolute**
    ///     path; a file picked in the editor is copied into the rules directory and the copy's
    ///     path is what the override stores.
    /// - Returns: An enabled rule.
    static func mapLocal(id: UUID = UUID(),
                         name: String,
                         matching: NetworkRuleMatch,
                         serving: MapLocalFile) -> NetworkRule {
        NetworkRule(id: id,
                    name: name,
                    isEnabled: true,
                    match: matching,
                    actions: NetworkRuleActions(stub: .mapLocal(serving)))
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
    /// - Note: Building the value touches no disk at all. The bytes travel with it and are written
    ///   when the rule holding it is added or updated, so a response that is never stored leaves
    ///   nothing behind, and one stored through a store of your own is written where *that* store
    ///   keeps its bodies.
    static func json(_ body: String,
                     status: Int = 200,
                     delay: TimeInterval = 0) -> MockResponse {
        var response = MockResponse(statusCode: status,
                                    headers: ["Content-Type": "application/json"],
                                    bodyID: nil,
                                    delay: delay)
        response.pendingBody = Data(body.utf8)
        return response
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
