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
