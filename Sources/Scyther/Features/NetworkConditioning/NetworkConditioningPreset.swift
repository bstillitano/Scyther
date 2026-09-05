//
//  NetworkConditioningPreset.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The named links a developer picks from instead of typing three numbers.
///
/// The names and the shape of the list follow Network Link Conditioner, because that is the tool
/// every iOS developer already knows: "make it behave like 3G" is a thing people say, and having
/// to convert it into a latency and a kilobyte ceiling is friction with no purpose.
///
/// The values are approximations of Network Link Conditioner's own profiles, converted from its
/// kilobits per second into the kilobytes per second ``NetworkCondition`` uses and from its
/// milliseconds into seconds. They are not a simulation of a radio; they are numbers that feel
/// like the link they are named after.
///
/// ## Usage
///
/// ```swift
/// viewModel.preset = .threeG        // fills in latency, bandwidth and failure rate
/// viewModel.preset                  // .custom once any of the three is edited
/// ```
enum NetworkConditioningPreset: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the three fields currently say. Never fills anything in.
    case custom
    /// A good Wi-Fi link: no meaningful latency, no meaningful ceiling.
    case wifi
    /// A good LTE link.
    case fourG
    /// A 3G link: a tenth of a second of latency and about 100 KB/s.
    case threeG
    /// An EDGE link: nearly half a second of latency and about 30 KB/s.
    case edge
    /// A link that is both slow and unreliable — one request in ten fails outright.
    case veryBad

    /// A stable identity for `ForEach` and `Picker`.
    var id: String { rawValue }

    /// The label shown in the preset picker.
    ///
    /// Wi-Fi, 4G, 3G and EDGE are the names of the technologies themselves and are left as they
    /// are in every language, exactly as Network Link Conditioner leaves them; only the two that
    /// are words rather than names are localised.
    var title: String {
        switch self {
        case .custom: return localized("Custom")
        case .wifi: return "Wi-Fi"
        case .fourG: return "4G"
        case .threeG: return "3G"
        case .edge: return "EDGE"
        case .veryBad: return localized("Very bad network")
        }
    }

    /// The conditioning this preset fills in, or `nil` for ``custom``, which fills in nothing.
    var condition: NetworkCondition? {
        switch self {
        case .custom: return nil
        case .wifi: return NetworkCondition(latency: 0.01, bandwidthKBps: 5_000, failureRate: 0)
        case .fourG: return NetworkCondition(latency: 0.05, bandwidthKBps: 1_500, failureRate: 0)
        case .threeG: return NetworkCondition(latency: 0.1, bandwidthKBps: 100, failureRate: 0)
        case .edge: return NetworkCondition(latency: 0.4, bandwidthKBps: 30, failureRate: 0)
        case .veryBad: return NetworkCondition(latency: 0.5, bandwidthKBps: 125, failureRate: 0.1)
        }
    }

    /// The preset a condition corresponds to, or ``custom`` when it matches none of them.
    ///
    /// Compares the three fields a preset actually sets rather than the whole value, so a
    /// condition carrying a non-default failure code — which no preset touches — still reads as
    /// the preset it otherwise is.
    ///
    /// - Parameter condition: The conditioning currently configured.
    /// - Returns: The matching preset, or ``custom``.
    static func matching(_ condition: NetworkCondition) -> NetworkConditioningPreset {
        allCases.first { preset in
            guard let candidate = preset.condition else { return false }
            return candidate.latency == condition.latency
                && candidate.bandwidthKBps == condition.bandwidthKBps
                && candidate.failureRate == condition.failureRate
        } ?? .custom
    }

    /// What a row describing the global conditioning reads: the named link, `Custom`, or `Off`.
    ///
    /// Lives here rather than on either view model because two screens show it — the menu's
    /// Network Conditioning row and any test asserting what that row says — and two spellings of
    /// "what is conditioning set to" would drift.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether conditioning is applied at all.
    ///   - condition: The conditioning configured, applied or not.
    /// - Returns: The localised summary.
    static func summary(isEnabled: Bool, condition: NetworkCondition) -> String {
        isEnabled ? matching(condition).title : localized("Off")
    }
}
