//
//  NetworkRuleEngine.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The result of evaluating every enabled rule against one request.
public struct RuleOutcome: Sendable, Equatable {
    /// Headers to apply to the outgoing request, merged from every matching rewrite rule.
    ///
    /// A consumer must apply every entry in `set` first, then remove every name in `remove`,
    /// so that a key present in both ends up removed. Applying them in the opposite order would
    /// silently keep a header a rule asked to remove.
    public var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition rule.
    public var condition: NetworkCondition?
    /// A response to synthesise instead of performing the request.
    public var stub: RuleStub?
    /// The name of the rule that supplied ``stub``, or `nil` when nothing is stubbed.
    ///
    /// Separate from ``networkRuleNames`` because a stub short-circuits the request: the header
    /// rewrite is never applied and the condition is never honoured, so crediting them in the
    /// log would name overrides that did nothing.
    public var stubRuleName: String?
    /// Names of the rules that shape a request which actually reaches the network, in evaluation
    /// order: every matching header rewrite, then the first matching condition.
    ///
    /// Empty when nothing else matched. Only meaningful when ``stub`` is `nil`, or when a stub
    /// could not be produced — a map-local file that no longer exists, say — and the request
    /// therefore falls through to the network.
    public var networkRuleNames: [String]
    /// The identifier of the rule that supplied ``stub``, or `nil` when nothing is stubbed.
    ///
    /// Carried alongside ``stubRuleName`` so the log can link a mocked response back to the
    /// override that produced it. A name is what a developer reads; an identifier is what
    /// survives two overrides sharing one.
    public var stubRuleID: UUID?
    /// Identifiers of the rules named by ``networkRuleNames``, in the same order.
    public var networkRuleIDs: [UUID]

    /// An outcome that changes nothing.
    public static let empty = RuleOutcome(headerRewrite: nil,
                                          condition: nil,
                                          stub: nil,
                                          stubRuleName: nil,
                                          networkRuleNames: [],
                                          stubRuleID: nil,
                                          networkRuleIDs: [])
}

/// What to serve instead of performing the request.
public enum RuleStub: Sendable, Equatable {
    /// A canned response synthesised in place of a real network call.
    case mock(MockResponse)
    /// The contents of a local file served in place of a real network call.
    case mapLocal(MapLocalFile)
}

/// Evaluates rules against a request. Pure: it reads no global state and performs no I/O.
public enum NetworkRuleEngine {
    /// Resolves every enabled rule that matches `request` into one outcome.
    ///
    /// Header rewrites all apply in order, a later `set` winning a key collision. The first
    /// matching condition wins; stacking latency from several rules would be surprising. The
    /// first matching mock or map-local wins and short-circuits the network.
    ///
    /// The names of the matching rules are reported in two groups rather than one, because a
    /// request takes one path or the other: the caller credits ``RuleOutcome/stubRuleName`` when
    /// it serves the stub and ``RuleOutcome/networkRuleNames`` when the request goes out. A
    /// single list would have the log naming a rewrite that a mock had already short-circuited.
    ///
    /// - Parameters:
    ///   - request: The outgoing request.
    ///   - rules: The rules to evaluate, in precedence order.
    public static func outcome(for request: URLRequest, rules: [NetworkRule]) -> RuleOutcome {
        var setHeaders: [String: String] = [:]
        var removeHeaders: [String] = []
        var sawRewrite = false
        var condition: NetworkCondition?
        var stub: RuleStub?
        var stubName: String?
        var networkNames: [String] = []
        var networkIDs: [UUID] = []
        var stubID: UUID?

        for rule in rules where rule.isEnabled {
            guard rule.match.matches(request) else { continue }
            switch rule.action {
            case .rewriteHeaders(let rewrite):
                sawRewrite = true
                rewrite.set.forEach { setHeaders[$0.key] = $0.value }
                removeHeaders.append(contentsOf: rewrite.remove)
                networkNames.append(rule.name)
                networkIDs.append(rule.id)
            case .condition(let value):
                guard condition == nil else { continue }
                condition = value
                networkNames.append(rule.name)
                networkIDs.append(rule.id)
            case .mock(let mock):
                guard stub == nil else { continue }
                stub = .mock(mock)
                stubName = rule.name
                stubID = rule.id
            case .mapLocal(let file):
                guard stub == nil else { continue }
                stub = .mapLocal(file)
                stubName = rule.name
                stubID = rule.id
            }
        }

        return RuleOutcome(
            headerRewrite: sawRewrite ? NetworkHeaderRewrite(set: setHeaders, remove: removeHeaders) : nil,
            condition: condition,
            stub: stub,
            stubRuleName: stubName,
            networkRuleNames: networkNames,
            stubRuleID: stubID,
            networkRuleIDs: networkIDs
        )
    }
}
