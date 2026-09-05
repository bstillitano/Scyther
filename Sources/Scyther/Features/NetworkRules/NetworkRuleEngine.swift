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
    public var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition rule.
    public var condition: NetworkCondition?
    /// A response to synthesise instead of performing the request.
    public var stub: RuleStub?
    /// Names of every rule that contributed, in evaluation order.
    public var appliedRuleNames: [String]

    /// An outcome that changes nothing.
    public static let empty = RuleOutcome(headerRewrite: nil, condition: nil, stub: nil, appliedRuleNames: [])

    /// Whether this outcome leaves the request untouched.
    public var isEmpty: Bool { self == .empty }
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
    /// - Parameters:
    ///   - request: The outgoing request.
    ///   - rules: The rules to evaluate, in precedence order.
    public static func outcome(for request: URLRequest, rules: [NetworkRule]) -> RuleOutcome {
        var setHeaders: [String: String] = [:]
        var removeHeaders: [String] = []
        var sawRewrite = false
        var condition: NetworkCondition?
        var stub: RuleStub?
        var names: [String] = []

        for rule in rules where rule.isEnabled {
            guard rule.match.matches(request) else { continue }
            switch rule.action {
            case .rewriteHeaders(let rewrite):
                sawRewrite = true
                rewrite.set.forEach { setHeaders[$0.key] = $0.value }
                removeHeaders.append(contentsOf: rewrite.remove)
                names.append(rule.name)
            case .condition(let value):
                guard condition == nil else { continue }
                condition = value
                names.append(rule.name)
            case .mock(let mock):
                guard stub == nil else { continue }
                stub = .mock(mock)
                names.append(rule.name)
            case .mapLocal(let file):
                guard stub == nil else { continue }
                stub = .mapLocal(file)
                names.append(rule.name)
            }
        }

        return RuleOutcome(
            headerRewrite: sawRewrite ? NetworkHeaderRewrite(set: setHeaders, remove: removeHeaders) : nil,
            condition: condition,
            stub: stub,
            appliedRuleNames: names
        )
    }
}
