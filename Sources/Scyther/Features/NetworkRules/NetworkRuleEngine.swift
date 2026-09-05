//
//  NetworkRuleEngine.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The result of evaluating every enabled rule against one request.
struct NetworkRuleOutcome: Sendable, Equatable {
    /// Headers to apply to the outgoing request, merged from every matching rewrite.
    ///
    /// One header name never appears in both `set` and `remove`: the engine has already settled
    /// which of the two the last override to name it asked for, so the consumer applies the two
    /// collections in either order and gets the same request. `nil` when nothing matched, or when
    /// everything that matched asked for no change at all.
    var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition.
    var condition: NetworkCondition?
    /// A response to synthesise instead of performing the request.
    var stub: NetworkRuleStub?
    /// The name of the rule that supplied ``stub``, or `nil` when nothing is stubbed.
    ///
    /// Reported separately from ``networkRuleNames`` because it is the one credit that depends on
    /// the stub actually being producible: a map-local file that has since been deleted falls
    /// through to the network, and crediting the override that named it would say a response was
    /// served that never was.
    var stubRuleName: String?
    /// Names of the rules that shape the request itself, in rule order — one entry per matching
    /// override that supplied a header rewrite, the condition, or both.
    ///
    /// Empty when nothing but a stub matched. These are credited whether or not the request is
    /// stubbed, because both still apply to a stubbed one — the condition delays, paces or fails
    /// the synthesised response, and the rewrite shapes the request the log describes even though
    /// nothing goes on the wire.
    var networkRuleNames: [String]
    /// The identifier of the rule that supplied ``stub``, or `nil` when nothing is stubbed.
    ///
    /// Carried alongside ``stubRuleName`` so the log can link a mocked response back to the
    /// override that produced it. A name is what a developer reads; an identifier is what
    /// survives two overrides sharing one.
    var stubRuleID: UUID?
    /// Identifiers of the rules named by ``networkRuleNames``, in the same order.
    var networkRuleIDs: [UUID]

    /// An outcome that changes nothing.
    static let empty = NetworkRuleOutcome(headerRewrite: nil,
                                          condition: nil,
                                          stub: nil,
                                          stubRuleName: nil,
                                          networkRuleNames: [],
                                          stubRuleID: nil,
                                          networkRuleIDs: [])
}

extension NetworkRuleOutcome {
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
enum NetworkRuleEngine {
    /// Resolves every enabled rule that matches `request` into one outcome.
    ///
    /// Evaluation is first-match-wins **per facet**, not per rule:
    ///
    /// | Facet | Rule |
    /// |---|---|
    /// | Stub | The first matching stub wins and short-circuits the network. |
    /// | Header rewrite | Every matching rewrite merges; the **last** override to name a header wins. |
    /// | Condition | The first matching condition wins. |
    ///
    /// A merged rewrite settles each header once, so precedence for a header is the same rule
    /// order the list shows: a later override that sets a header an earlier one removed wins, and
    /// a later override that removes one an earlier one set wins too. Within a *single* rewrite
    /// there is no order to appeal to, so `set` is applied before `remove` and a header named in
    /// both ends up removed.
    ///
    /// Header names are compared case-insensitively, because that is how `URLRequest` treats
    /// them: `Authorization` and `authorization` are one header, and the winner is carried under
    /// the spelling the winning override used.
    ///
    /// A rewrite that sets and removes nothing is not a rewrite. It is neither reported nor
    /// credited, so an override that has been emptied out cannot make the log record a second,
    /// identical copy of an untouched request.
    ///
    /// A stub deliberately does **not** suppress the other two. Stacking latency from several
    /// rules would be surprising, which is why the condition is first-match-wins; suppressing a
    /// condition because something else stubbed the request is a different thing entirely, and
    /// meant "mock this endpoint and make it slow" quietly did nothing.
    ///
    /// The names of the matching rules are still reported in two groups, because the stub credit
    /// is conditional on the stub being producible — see ``NetworkRuleOutcome/stubRuleName``. A
    /// caller serving the stub credits ``NetworkRuleOutcome/stubbedCredits``; one that falls
    /// through to the network credits ``NetworkRuleOutcome/networkRuleNames``.
    ///
    /// - Parameters:
    ///   - request: The outgoing request.
    ///   - rules: The rules to evaluate, in precedence order.
    static func outcome(for request: URLRequest, rules: [NetworkRule]) -> NetworkRuleOutcome {
        var headers = HeaderMerge()
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

            if let rewrite = rule.actions.rewriteHeaders, headers.merge(rewrite) {
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

        return NetworkRuleOutcome(
            headerRewrite: headers.resolved,
            condition: condition,
            stub: stub,
            stubRuleName: stubName,
            networkRuleNames: networkNames,
            stubRuleID: stubID,
            networkRuleIDs: networkIDs
        )
    }
}

/// Folds every matching override's header rewrite into one, settling each header name once.
///
/// A rewrite used to be flattened into a `set` dictionary and a `remove` array that a consumer
/// applied in that order, which meant removal won globally: a later override could not restore a
/// header an earlier one had removed, whatever the list's order said. Names were also keyed
/// case-sensitively, so `Authorization` and `authorization` both survived into the merged rewrite
/// and which of them reached the request depended on the order a Swift dictionary iterated in.
///
/// Both fall out of recording one operation per canonical header name, in the order the names are
/// first seen, and letting the last one recorded win.
private struct HeaderMerge {
    /// What the last override to name a header asked for.
    private enum Operation {
        /// Set the header, under the spelling that override used.
        case set(name: String, value: String)
        /// Remove the header, under the spelling that override used.
        case remove(name: String)
    }

    /// The operation standing for each header name, lowercased.
    private var operations: [String: Operation] = [:]

    /// Canonical names in the order they were first seen, so the merged rewrite is stable.
    private var order: [String] = []

    /// The merged rewrite, or `nil` when nothing asked for a change.
    ///
    /// `set` and `remove` are disjoint: each header name is in whichever one the last override to
    /// name it asked for.
    var resolved: NetworkHeaderRewrite? {
        guard !order.isEmpty else { return nil }
        var set: [String: String] = [:]
        var remove: [String] = []
        for canonical in order {
            guard let operation = operations[canonical] else { continue }
            switch operation {
            case .set(let name, let value): set[name] = value
            case .remove(let name): remove.append(name)
            }
        }
        return NetworkHeaderRewrite(set: set, remove: remove)
    }

    /// Folds one override's rewrite in.
    ///
    /// `set` is applied before `remove`, so a header this one rewrite names in both ends up
    /// removed; inside a single rewrite there is no rule order to appeal to. Its `set` entries are
    /// taken in a sorted order rather than the dictionary's own, so that a rewrite carrying two
    /// spellings of one name resolves the same way on every launch.
    ///
    /// - Parameter rewrite: The rewrite to fold in.
    /// - Returns: `false` when the rewrite asks for no change at all, so that its override is not
    ///   credited with a rewrite it did not perform.
    mutating func merge(_ rewrite: NetworkHeaderRewrite) -> Bool {
        guard !rewrite.set.isEmpty || !rewrite.remove.isEmpty else { return false }
        for (name, value) in rewrite.set.sorted(by: { $0.key < $1.key }) {
            record(.set(name: name, value: value), for: name)
        }
        for name in rewrite.remove {
            record(.remove(name: name), for: name)
        }
        return true
    }

    /// Records the operation now standing for one header name.
    ///
    /// - Parameters:
    ///   - operation: What the override asked for.
    ///   - name: The header name as that override spelled it.
    private mutating func record(_ operation: Operation, for name: String) {
        let canonical = name.lowercased()
        if operations[canonical] == nil { order.append(canonical) }
        operations[canonical] = operation
    }
}
