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
}
