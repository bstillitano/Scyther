//
//  ReplayComparison.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// The difference between an original request and one of its replays.
///
/// Pure arithmetic over two captures, so the figures the detail page shows can be checked without
/// a network. Body contents are deliberately not compared — structural diffing is a feature in its
/// own right, and the two bodies are already openable side by side in the existing viewer.
struct ReplayComparison: Equatable, Sendable {

    /// What Scyther did to one side of the comparison, if anything.
    ///
    /// The tests are the same ones the log's own badges use, so a row here and a row in the list
    /// can never disagree about whether a request was mocked or held.
    struct Shaping: OptionSet, Equatable, Sendable {
        /// The raw bitmask.
        let rawValue: Int

        /// An override answered the request instead of the network. The log's pink `MOCKED`.
        static let stubbed = Shaping(rawValue: 1 << 0)

        /// An override shaped the request without answering it — a header rewrite, or a network
        /// condition, global or its own. The log's brown `OVERRIDDEN`.
        static let overridden = Shaping(rawValue: 1 << 1)

        /// A breakpoint held the exchange on its way through. The log's indigo `HELD`.
        static let held = Shaping(rawValue: 1 << 2)

        /// The developer changed the exchange while it was held.
        static let edited = Shaping(rawValue: 1 << 3)

        /// Creates a shaping from its bitmask.
        ///
        /// - Parameter rawValue: The bitmask.
        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Reads what Scyther did to a captured request.
        ///
        /// - Parameter request: The capture to describe.
        init(describing request: HTTPRequest) {
            var shaping: Shaping = []
            if request.wasStubbed {
                shaping.insert(.stubbed)
            } else if !request.appliedRuleNames.isEmpty {
                shaping.insert(.overridden)
            }
            if !request.breakpointNames.isEmpty { shaping.insert(.held) }
            if request.wasEdited { shaping.insert(.edited) }
            self = shaping
        }
    }

    /// What Scyther did to the request the app made.
    let originalShaping: Shaping

    /// What Scyther did to the replay.
    let replayShaping: Shaping

    /// Whether nothing Scyther does stands between these two figures and the server.
    ///
    /// A mocked response never left the device, a conditioned one was slowed on purpose, and a
    /// held one waited for a developer to press a button — so a delta across any of those
    /// measures the toolkit rather than the server. The Replays section is the one place on the
    /// page built for comparison, and it used to report those deltas with nothing said.
    var isLikeForLike: Bool { originalShaping.isEmpty && replayShaping.isEmpty }

    /// Whether the status code differs, treating "no response" as a status of its own.
    ///
    /// A replay that failed outright therefore reads as a change from an original that answered,
    /// and two requests that both failed read as no change.
    let statusChanged: Bool

    /// Replay duration minus original, in milliseconds.
    ///
    /// `nil` when either request has no recorded duration — one of them failed before a response
    /// arrived, or is still in flight — because there is nothing honest to subtract.
    let durationDeltaMilliseconds: Double?

    /// Replay body size minus original, in bytes.
    ///
    /// `nil` when either request has no recorded body length, for the same reason
    /// ``durationDeltaMilliseconds`` is.
    let sizeDeltaBytes: Int?

    /// Compares two captured requests.
    ///
    /// - Parameters:
    ///   - original: The request that was captured from the app.
    ///   - replay: The request sent from the editor.
    init(original: HTTPRequest, replay: HTTPRequest) {
        originalShaping = Shaping(describing: original)
        replayShaping = Shaping(describing: replay)
        statusChanged = original.responseCode != replay.responseCode
        if let originalDuration = original.requestDuration, let replayDuration = replay.requestDuration {
            durationDeltaMilliseconds = Double(replayDuration) - Double(originalDuration)
        } else {
            durationDeltaMilliseconds = nil
        }
        if let originalSize = original.responseBodyLength, let replaySize = replay.responseBodyLength {
            sizeDeltaBytes = replaySize - originalSize
        } else {
            sizeDeltaBytes = nil
        }
    }

    /// The duration delta as a signed figure, e.g. `+24 ms`, or `nil` when there is none.
    ///
    /// Always signed, including the zero case, because an unsigned `0 ms` beside a signed
    /// `-460 B` reads as two different kinds of number rather than the same comparison.
    ///
    /// The unit is a symbol rather than a translated word, matching the `%.0fms` the request
    /// details page has always shown its durations in.
    var durationDeltaText: String? {
        guard let durationDeltaMilliseconds else { return nil }
        return String(format: "%+.0f ms", durationDeltaMilliseconds) // scyther:unlocalised unit symbol
    }

    /// The size delta as a signed figure, e.g. `-460 B`, or `nil` when there is none.
    var sizeDeltaText: String? {
        guard let sizeDeltaBytes else { return nil }
        return String(format: "%+lld B", Int64(sizeDeltaBytes)) // scyther:unlocalised unit symbol
    }
}
