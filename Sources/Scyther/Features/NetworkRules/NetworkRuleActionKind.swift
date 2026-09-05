//
//  NetworkRuleActionKind.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// A ``NetworkRuleAction`` with its associated value discarded.
///
/// ``NetworkRuleAction`` carries the configuration for whichever behaviour a rule performs, which
/// makes it unusable as a `Picker` selection or as a `ForEach` identity. This enum is the same
/// four choices without the payload, so the editor can offer them as a list and the rules list can
/// name a rule's behaviour without switching over four associated values at every call site.
///
/// ## Usage
///
/// ```swift
/// rule.action.kind.title   // "Mock Response"
/// rule.action.kind.icon    // "arrow.uturn.left"
/// ```
enum NetworkRuleActionKind: String, CaseIterable, Identifiable, Sendable {
    /// Answers the request with a canned response — ``NetworkRuleAction/mock(_:)``.
    case mock
    /// Answers the request with the contents of a local file — ``NetworkRuleAction/mapLocal(_:)``.
    case mapLocal
    /// Sets or removes request headers — ``NetworkRuleAction/rewriteHeaders(_:)``.
    case rewriteHeaders
    /// Adds latency, throttles bandwidth or fails the request — ``NetworkRuleAction/condition(_:)``.
    case condition

    /// A stable identity for `ForEach` and `Picker`.
    var id: String { rawValue }

    /// The localised label shown in the editor's action picker and as a rule row's subtitle.
    var title: String {
        switch self {
        case .mock: return localized("Mock Response")
        case .mapLocal: return localized("Map Local File")
        case .rewriteHeaders: return localized("Rewrite Headers")
        case .condition: return localized("Network Condition")
        }
    }

    /// The SF Symbol shown alongside a rule performing this kind of action.
    var icon: String {
        switch self {
        case .mock: return "arrow.uturn.left"
        case .mapLocal: return "doc.text"
        case .rewriteHeaders: return "pencil.line"
        case .condition: return "tortoise"
        }
    }

    /// A freshly configured action of this kind, used when the editor's picker changes to a kind
    /// the developer has not configured yet.
    ///
    /// - Returns: An action carrying this kind's default payload.
    func emptyAction() -> NetworkRuleAction {
        switch self {
        case .mock: return .mock(MockResponse())
        case .mapLocal: return .mapLocal(MapLocalFile(relativePath: ""))
        case .rewriteHeaders: return .rewriteHeaders(NetworkHeaderRewrite())
        case .condition: return .condition(NetworkCondition())
        }
    }
}

internal extension NetworkRuleAction {
    /// This action's kind, with its associated value discarded.
    var kind: NetworkRuleActionKind {
        switch self {
        case .mock: return .mock
        case .mapLocal: return .mapLocal
        case .rewriteHeaders: return .rewriteHeaders
        case .condition: return .condition
        }
    }
}
