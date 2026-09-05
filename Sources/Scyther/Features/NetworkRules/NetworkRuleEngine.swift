//
//  NetworkRuleEngine.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The result of evaluating every enabled rule against one request.
public struct RuleOutcome: Sendable, Equatable {
    /// Headers to apply to the outgoing request, merged from every matching rewrite.
    ///
    /// A consumer must apply every entry in `set` first, then remove every name in `remove`,
    /// so that a key present in both ends up removed. Applying them in the opposite order would
    /// silently keep a header a rule asked to remove.
    public var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition.
    public var condition: NetworkCondition?
    /// A response to synthesise instead of performing the request.
    public var stub: NetworkRuleStub?
    /// The name of the rule that supplied ``stub``, or `nil` when nothing is stubbed.
    ///
    /// Reported separately from ``networkRuleNames`` because it is the one credit that depends on
    /// the stub actually being producible: a map-local file that has since been deleted falls
    /// through to the network, and crediting the override that named it would say a response was
    /// served that never was.
    public var stubRuleName: String?
    /// Names of the rules that shape the request itself, in evaluation order: every matching
    /// header rewrite, then the first matching condition.
    ///
    /// Empty when nothing but a stub matched. These are credited whether or not the request is
    /// stubbed, because both still apply to a stubbed one — the condition delays, paces or fails
    /// the synthesised response, and the rewrite shapes the request the log describes even though
    /// nothing goes on the wire.
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

public extension RuleOutcome {
    /// Every override to credit on the log when the stub is served: the stub first, then whatever
    /// else applied, with no override named twice.
    ///
    /// One override can now both stub a request and condition it, in which case it appears in
    /// ``stubRuleName`` and in ``networkRuleNames`` alike; naming it twice on the log would read
    /// as two overrides having fired. The names and identifiers are built together and stay
    /// parallel — same length, same order — because the log looks an override up by identifier
    /// and shows its name.
    var stubbedCredits: (names: [String], ids: [UUID]) {
        var names = stubRuleName.map { [$0] } ?? []
        var ids = stubRuleID.map { [$0] } ?? []
        for (index, id) in networkRuleIDs.enumerated() where !ids.contains(id) {
            names.append(networkRuleNames[index])
            ids.append(id)
        }
        return (names, ids)
    }
}

/// Evaluates rules against a request. Pure: it reads no global state and performs no I/O.
public enum NetworkRuleEngine {
    /// Resolves every enabled rule that matches `request` into one outcome.
    ///
    /// Evaluation is first-match-wins **per facet**, not per rule:
    ///
    /// | Facet | Rule |
    /// |---|---|
    /// | Stub | The first matching stub wins and short-circuits the network. |
    /// | Header rewrite | Every matching rewrite merges, a later `set` winning a key collision. |
    /// | Condition | The first matching condition wins. |
    ///
    /// A stub deliberately does **not** suppress the other two. Stacking latency from several
    /// rules would be surprising, which is why the condition is first-match-wins; suppressing a
    /// condition because something else stubbed the request is a different thing entirely, and
    /// meant "mock this endpoint and make it slow" quietly did nothing.
    ///
    /// The names of the matching rules are still reported in two groups, because the stub credit
    /// is conditional on the stub being producible — see ``RuleOutcome/stubRuleName``. A caller
    /// serving the stub credits ``RuleOutcome/stubbedCredits``; one that falls through to the
    /// network credits ``RuleOutcome/networkRuleNames``.
    ///
    /// - Parameters:
    ///   - request: The outgoing request.
    ///   - rules: The rules to evaluate, in precedence order.
    public static func outcome(for request: URLRequest, rules: [NetworkRule]) -> RuleOutcome {
        var setHeaders: [String: String] = [:]
        var removeHeaders: [String] = []
        var sawRewrite = false
        var condition: NetworkCondition?
        var stub: NetworkRuleStub?
        var stubName: String?
        var networkNames: [String] = []
        var networkIDs: [UUID] = []
        var stubID: UUID?

        for rule in rules where rule.isEnabled {
            guard rule.match.matches(request) else { continue }

            /// One rule can now carry several actions, so it is credited once for the request it
            /// shapes rather than once per facet it happens to fill in.
            var shapesTheRequest = false

            if let rewrite = rule.actions.rewriteHeaders {
                sawRewrite = true
                rewrite.set.forEach { setHeaders[$0.key] = $0.value }
                removeHeaders.append(contentsOf: rewrite.remove)
                shapesTheRequest = true
            }
            if let value = rule.actions.condition, condition == nil {
                condition = value
                shapesTheRequest = true
            }
            if let value = rule.actions.stub, stub == nil {
                stub = value
                stubName = rule.name
                stubID = rule.id
            }

            if shapesTheRequest {
                networkNames.append(rule.name)
                networkIDs.append(rule.id)
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
