//
//  NetworkRuleActions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Everything a matching ``NetworkRule`` does to a request.
///
/// An override used to carry exactly one action, which made "mock this endpoint and make it slow"
/// impossible to express: choosing a condition replaced the mock rather than sitting beside it.
/// Each facet is now independent and optional, so an override can stub, rewrite and condition the
/// same request at once.
///
/// The one combination that has no meaning — a mock *and* a local file answering the same
/// request — is ruled out structurally rather than by validation, because ``stub`` holds either
/// one or the other and cannot hold both.
///
/// ## What composes with what
///
/// - A ``condition`` applies to a ``stub``: its latency delays the synthesised response, its
///   failure rate can fail it, and its bandwidth ceiling paces the synthetic body.
/// - A ``rewriteHeaders`` is **recorded on the logged request but has no wire effect** when the
///   request is stubbed, because nothing is sent. It still shapes the log, so the log shows what
///   would have gone out.
///
/// ## Usage
///
/// ```swift
/// NetworkRuleActions(
///     stub: .mock(MockResponse(statusCode: 200)),
///     condition: NetworkCondition(latency: 2)
/// )
/// ```
public struct NetworkRuleActions: Codable, Sendable, Equatable {
    /// The response to serve instead of performing the request, if any.
    public var stub: NetworkRuleStub?

    /// Headers to set or remove on the outgoing request.
    ///
    /// - Important: Recorded on the logged request but never sent when ``stub`` is set, because a
    ///   stubbed request never leaves the device.
    public var rewriteHeaders: NetworkHeaderRewrite?

    /// Latency, bandwidth ceiling and failure rate applied to this request, stubbed or not.
    public var condition: NetworkCondition?

    /// The keys a set of actions is persisted under.
    ///
    /// Spelled out rather than synthesised so the on-disk format cannot change under a rename.
    private enum CodingKeys: String, CodingKey {
        /// ``stub``.
        case stub
        /// ``rewriteHeaders``.
        case rewriteHeaders
        /// ``condition``.
        case condition
    }

    /// Creates a set of actions. Every facet is optional; an omitted one does nothing.
    ///
    /// - Parameters:
    ///   - stub: The response to serve instead of performing the request. Defaults to none.
    ///   - rewriteHeaders: Headers to set or remove. Defaults to none.
    ///   - condition: Latency, bandwidth ceiling and failure rate. Defaults to none.
    public init(stub: NetworkRuleStub? = nil,
                rewriteHeaders: NetworkHeaderRewrite? = nil,
                condition: NetworkCondition? = nil) {
        self.stub = stub
        self.rewriteHeaders = rewriteHeaders
        self.condition = condition
    }

    /// Whether this override would do nothing at all to a request it matched.
    ///
    /// The editor refuses to save one, because an override that matches traffic and then leaves it
    /// alone is indistinguishable from a broken one.
    public var isEmpty: Bool {
        stub == nil && rewriteHeaders == nil && condition == nil
    }
}

/// A response served in place of performing the request.
///
/// Mock and map local are mutually exclusive by construction — an override holds one or the
/// other — because a canned response and a local file cannot both answer the same request.
public enum NetworkRuleStub: Codable, Sendable, Equatable {
    /// A canned response synthesised in place of a real network call.
    case mock(MockResponse)

    /// The contents of a local file served in place of a real network call.
    case mapLocal(MapLocalFile)

    /// The keys a stub is persisted under.
    ///
    /// Written by hand rather than synthesised so the stored JSON is `{"mock": { … }}` rather than
    /// the compiler's `{"mock": {"_0": { … }}}`. The positional `_0` is an implementation detail
    /// of the synthesised conformance, and persisting it makes the on-disk format hostage to it.
    private enum CodingKeys: String, CodingKey {
        /// A ``mock(_:)`` stub's ``MockResponse``.
        case mock
        /// A ``mapLocal(_:)`` stub's ``MapLocalFile``.
        case mapLocal
    }

    /// Decodes a stub written under either of ``CodingKeys``.
    ///
    /// - Parameter decoder: The decoder positioned at a stub.
    /// - Throws: `DecodingError.dataCorrupted` when neither key is present.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let mock = try container.decodeIfPresent(MockResponse.self, forKey: .mock) {
            self = .mock(mock)
        } else if let file = try container.decodeIfPresent(MapLocalFile.self, forKey: .mapLocal) {
            self = .mapLocal(file)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "A stub must carry either a mock or a map local file.")
            )
        }
    }

    /// Encodes this stub under its own key, with the payload directly beneath it.
    ///
    /// - Parameter encoder: The encoder to write to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mock(let mock): try container.encode(mock, forKey: .mock)
        case .mapLocal(let file): try container.encode(file, forKey: .mapLocal)
        }
    }
}

public extension NetworkRuleStub {
    /// The seconds this stub waits before it is served.
    ///
    /// Both kinds carry their own delay, and a caller that has to switch over the stub every time
    /// it wants one ends up with the two spellings drifting apart.
    var delay: TimeInterval {
        switch self {
        case .mock(let mock): return mock.delay
        case .mapLocal(let file): return file.delay
        }
    }
}
