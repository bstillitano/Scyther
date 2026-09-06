//
//  NetworkBreakpoint.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// A rule for holding a request or a response mid-flight so it can be inspected and edited.
///
/// A breakpoint is matching plus a stage and nothing else. What to *do* with the held exchange is
/// decided by the developer while it is held, not by the breakpoint, which is what separates this
/// from ``NetworkRule`` — a rule decides in advance, a breakpoint asks at the time.
///
/// Matching is ``NetworkRuleMatch``, shared verbatim with request overrides. A second matcher
/// would mean two sets of semantics for percent-encoding, trailing slashes and repeated query
/// keys, and a path that matched an override but not a breakpoint written the same way.
///
/// ## Topics
///
/// ### Creating a Breakpoint
/// - ``init(id:name:isEnabled:match:stage:timeout:)``
///
/// ### The Timeout
/// - ``timeout``
/// - ``defaultTimeout``
/// - ``timeoutRange``
/// - ``clampedTimeout(_:)``
struct NetworkBreakpoint: Identifiable, Codable, Sendable, Equatable {
    /// Which side of the exchange a breakpoint holds.
    enum Stage: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Hold the request before it is sent.
        case request
        /// Hold the response before the app sees any of it.
        case response
        /// Hold both, one after the other.
        case both

        /// The raw value, so a `Picker` can tag its rows.
        var id: String { rawValue }

        /// Whether this stage holds requests.
        var holdsRequest: Bool { self != .response }

        /// Whether this stage holds responses.
        var holdsResponse: Bool { self != .request }
    }

    /// A stable identifier, used for lookup, editing and deletion.
    var id: UUID

    /// A short, user-supplied label. Shown on the held-request editor and in the network log.
    var name: String

    /// Whether this breakpoint is evaluated at all. A disabled breakpoint holds nothing.
    var isEnabled: Bool

    /// The requests this breakpoint applies to.
    var match: NetworkRuleMatch

    /// Which side of the exchange to hold. ``Stage/both`` holds twice, once each way.
    var stage: Stage

    /// Seconds to hold before continuing unmodified, clamped to ``timeoutRange``.
    ///
    /// The timeout cannot be switched off. It is the only thing standing between a breakpoint the
    /// developer has forgotten and an app that looks broken, so it is a property of the model
    /// rather than of the UI, and it is clamped on construction, on decode and on save.
    var timeout: TimeInterval

    /// The timeout a new breakpoint starts with.
    static let defaultTimeout: TimeInterval = 60

    /// The range a timeout is clamped into.
    ///
    /// Five seconds is about the least time anyone can read a body in; five minutes is well past
    /// the point at which a held request stops looking like a pause and starts looking like a bug.
    static let timeoutRange: ClosedRange<TimeInterval> = 5...300

    /// `interval` brought inside ``timeoutRange``.
    ///
    /// A non-finite interval — which JSON cannot express and arithmetic can produce — is treated
    /// as the default rather than propagated into a deadline.
    ///
    /// - Parameter interval: The interval to clamp.
    /// - Returns: The clamped interval.
    static func clampedTimeout(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultTimeout }
        return min(max(interval, timeoutRange.lowerBound), timeoutRange.upperBound)
    }

    /// The keys a breakpoint is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``id``.
        case id
        /// ``name``.
        case name
        /// ``isEnabled``.
        case isEnabled
        /// ``match``.
        case match
        /// ``stage``.
        case stage
        /// ``timeout``.
        case timeout
    }

    /// Creates a breakpoint.
    ///
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a fresh one.
    ///   - name: The label shown while the request is held.
    ///   - isEnabled: Whether the breakpoint is evaluated. Defaults to `true`.
    ///   - match: The requests this breakpoint applies to.
    ///   - stage: Which side of the exchange to hold. Defaults to ``Stage/request``.
    ///   - timeout: Seconds to hold before continuing unmodified. Clamped to ``timeoutRange``.
    init(id: UUID = UUID(),
         name: String,
         isEnabled: Bool = true,
         match: NetworkRuleMatch,
         stage: Stage = .request,
         timeout: TimeInterval = NetworkBreakpoint.defaultTimeout) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.stage = stage
        self.timeout = Self.clampedTimeout(timeout)
    }

    /// Reads a persisted breakpoint, clamping its timeout.
    ///
    /// A blob written by another version — or edited by hand — cannot smuggle in a timeout of an
    /// hour, because the value is clamped here rather than only where the editor writes it.
    ///
    /// - Parameter decoder: The decoder to read from.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        match = try container.decode(NetworkRuleMatch.self, forKey: .match)
        stage = try container.decodeIfPresent(Stage.self, forKey: .stage) ?? .request
        timeout = Self.clampedTimeout(
            try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? Self.defaultTimeout
        )
    }
}
