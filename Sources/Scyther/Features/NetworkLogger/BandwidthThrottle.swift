//
//  BandwidthThrottle.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Paces the bytes of one response to a bandwidth ceiling.
///
/// The budget is per **response**, not per delivery. `URLSession` hands a body to its delegate in
/// chunks of its own choosing — 64 KB at a time is typical — so a throttle that only weighs the
/// chunk in hand never sleeps for any ceiling above one chunk per second, which is every ceiling
/// a developer is likely to type. This instead remembers how many bytes of the response have been
/// forwarded and compares the time the ceiling implies for them against the time the transfer has
/// actually taken, sleeping the difference.
///
/// The type is pure: it measures nothing and sleeps for nobody. The caller supplies the elapsed
/// time and performs the wait, which is what makes the pacing testable without waiting on a clock.
///
/// ## Usage
///
/// ```swift
/// var throttle = BandwidthThrottle(bandwidthKBps: 200, maximumTotalSleep: 30)
/// let wait = throttle?.delay(forwarding: chunk.count, elapsed: Date().timeIntervalSince(start))
/// ```
///
/// ## Topics
///
/// ### Creating a Throttle
/// - ``init(bandwidthKBps:maximumTotalSleep:)``
/// - ``maximumBandwidthKBps``
///
/// ### Pacing
/// - ``delay(forwarding:elapsed:)``
struct BandwidthThrottle {
    /// The largest ceiling that is honoured, in kilobytes per second.
    ///
    /// A ceiling is host-supplied, and `bandwidthKBps * 1024` would trap on overflow for an
    /// absurd one. Anything at or above this is effectively unthrottled anyway.
    static let maximumBandwidthKBps: Int = 1_000_000

    /// The ceiling, in bytes per second.
    let bytesPerSecond: Double

    /// The most time this throttle may ask for across the whole response.
    ///
    /// Without a ceiling on the ceiling, a 10 MB body at 1 KB/s would hold the session's delegate
    /// queue for nearly three hours, which is not a simulation anyone asked for.
    let maximumTotalSleep: TimeInterval

    /// Bytes of this response handed to ``delay(forwarding:elapsed:)`` so far.
    private var bytesForwarded: Int = 0

    /// Seconds this throttle has already asked the caller to wait.
    private var sleepUsed: TimeInterval = 0

    /// Creates a throttle for a ceiling, or `nil` when there is nothing to throttle.
    ///
    /// - Parameters:
    ///   - bandwidthKBps: The ceiling in kilobytes per second. `nil` or a non-positive value
    ///     means unthrottled, and produces `nil`.
    ///   - maximumTotalSleep: The most time the throttle may ask for across the whole response.
    init?(bandwidthKBps: Int?, maximumTotalSleep: TimeInterval) {
        guard let bandwidthKBps, bandwidthKBps > 0 else { return nil }
        self.bytesPerSecond = Double(min(bandwidthKBps, Self.maximumBandwidthKBps) * 1024)
        self.maximumTotalSleep = maximumTotalSleep
    }

    /// How long to wait before forwarding the next bytes of the response.
    ///
    /// Because `elapsed` is measured from the start of the response, time already spent asleep is
    /// counted automatically: a caller that honours every returned delay converges on the ceiling
    /// rather than overshooting it.
    ///
    /// - Parameters:
    ///   - count: The number of bytes about to be forwarded.
    ///   - elapsed: Seconds since the response began arriving.
    /// - Returns: Seconds to wait, `0` when the transfer is already at or under the ceiling or
    ///   when ``maximumTotalSleep`` is exhausted.
    mutating func delay(forwarding count: Int, elapsed: TimeInterval) -> TimeInterval {
        bytesForwarded += count
        let owed = Double(bytesForwarded) / bytesPerSecond - elapsed
        guard owed > 0 else { return 0 }
        let remaining = maximumTotalSleep - sleepUsed
        guard remaining > 0 else { return 0 }
        let wait = min(owed, remaining)
        sleepUsed += wait
        return wait
    }
}
