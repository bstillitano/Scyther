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
/// - ``burstWindow``
///
/// ### Pacing
/// - ``delay(forwarding:elapsed:)``
struct BandwidthThrottle {
    /// The largest ceiling that is honoured, in kilobytes per second.
    ///
    /// A ceiling is host-supplied, and `bandwidthKBps * 1024` would trap on overflow for an
    /// absurd one. Anything at or above this is effectively unthrottled anyway.
    static let maximumBandwidthKBps: Int = 1_000_000

    /// The most idle time a response may bank as credit against a later burst, in seconds.
    ///
    /// The pacing compares the time a transfer *should* have taken against the time it actually
    /// has taken, and forwards for free whenever it is running behind. Left unbounded that credit
    /// accrues while nothing is arriving at all, so a response whose headers came early and whose
    /// body came late is forwarded in one unpaced burst, however far over the ceiling that burst
    /// is. Long-poll and server-sent events are mostly idle by design, so they were effectively
    /// unthrottled.
    ///
    /// The bound is applied to the credit a call *leaves behind*, never to the credit it spends:
    /// the clock may end a call at most this far ahead of where the ceiling says the transfer
    /// should have got to, and the bytes in hand are charged against the credit that was standing
    /// when they arrived. Bounding the credit before the charge instead made the debt
    /// `count / rate − burstWindow` after any idle longer than the window — a constant,
    /// independent of how long the source had actually taken — so a source delivering at a third
    /// of its ceiling in 64 KB chunks was still delayed, and spent the whole of
    /// ``maximumTotalSleep`` on debt it never owed.
    ///
    /// One second is large enough that a response already comfortably under its ceiling is never
    /// delayed by it, and small enough that a burst after a think is still paced.
    static let burstWindow: TimeInterval = 1

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

    /// Elapsed time written off because it left the clock more than ``burstWindow`` ahead of
    /// schedule.
    ///
    /// `elapsed` is measured from the start of the response and only ever grows, so idle time
    /// cannot simply be ignored at the call that sees it — the same idle seconds would still be
    /// there at the next call. Subtracting them once, here, holds the credit carried into the
    /// next call at ``burstWindow`` for the rest of the response.
    private var discardedIdle: TimeInterval = 0

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
    /// Because `elapsed` is measured from the start of the response, time already spent waiting is
    /// counted automatically: a caller that honours every returned delay converges on the ceiling
    /// rather than overshooting it. Time in which *nothing arrived* counts too, but the clock is
    /// never left more than ``burstWindow`` ahead of schedule — see that property for why.
    ///
    /// The bytes in hand are charged **before** the credit is bounded, so a response whose bytes
    /// have averaged out at or under the ceiling is never delayed, however the source chose to
    /// chunk them. Bounding first charged the whole of a chunk's transmit time against a clock
    /// that had just been wound back to the burst window, which delayed transfers that were
    /// comfortably inside their ceiling and burned ``maximumTotalSleep`` doing it.
    ///
    /// - Parameters:
    ///   - count: The number of bytes about to be forwarded.
    ///   - elapsed: Seconds since the response began arriving, measured on a monotonic clock so
    ///     that a system clock change cannot make the pacing jump.
    /// - Returns: Seconds to wait, `0` when the transfer is already at or under the ceiling or
    ///   when ``maximumTotalSleep`` is exhausted.
    mutating func delay(forwarding count: Int, elapsed: TimeInterval) -> TimeInterval {
        /// Where the ceiling says the transfer should have got to once these bytes are counted,
        /// and where the clock stands against it. Charging the bytes first is what makes a
        /// transfer already under its ceiling free rather than merely cheaper.
        bytesForwarded += count
        let scheduled = Double(bytesForwarded) / bytesPerSecond
        var effectiveElapsed = elapsed - discardedIdle

        /// Whatever credit is left over once the bytes are paid for is bounded, so the next call
        /// starts at most ``burstWindow`` ahead of schedule rather than banking an idle stretch
        /// in full.
        let credit = effectiveElapsed - scheduled
        if credit > Self.burstWindow {
            discardedIdle += credit - Self.burstWindow
            effectiveElapsed = scheduled + Self.burstWindow
        }

        let owed = scheduled - effectiveElapsed
        guard owed > 0 else { return 0 }
        let remaining = maximumTotalSleep - sleepUsed
        guard remaining > 0 else { return 0 }
        let wait = min(owed, remaining)
        sleepUsed += wait
        return wait
    }
}
