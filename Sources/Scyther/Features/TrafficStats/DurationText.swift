//
//  DurationText.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// Turns a measured duration into the text the traffic screens show it as.
///
/// Extracted from ``TrafficStatsViewModel`` because the waterfall now has two surfaces — the
/// section on **Traffic Stats** and the full-log page behind its **See all** button — and a bar
/// that reads `2 ms` on one and `0 s` on the other would be the same request described two ways.
/// One formatter is the only way to keep that promise.
///
/// ## Usage
/// ```swift
/// DurationText.milliseconds(1_842)  // "1.84 s"
/// DurationText.milliseconds(2)      // "2 ms"
/// ```
enum DurationText {
    /// The point at which a figure reads better in seconds than in milliseconds.
    ///
    /// "1,842 ms" is a number a reader has to divide before it means anything.
    private static let secondsFloor: Double = 1_000

    /// A duration in milliseconds as text.
    ///
    /// Milliseconds up to a second and seconds beyond it, so a two millisecond round trip reads
    /// as `2 ms` rather than rounding away to `0 s`.
    ///
    /// - Parameter milliseconds: The duration, or `nil` when there is nothing to show.
    /// - Returns: The formatted duration, or an em dash when there is no finite figure.
    static func milliseconds(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite else { return "—" } // scyther:unlocalised em dash placeholder
        guard milliseconds >= secondsFloor else {
            return Measurement(value: milliseconds.rounded(), unit: UnitDuration.milliseconds)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        return seconds(milliseconds / secondsFloor)
    }

    /// A duration in seconds as text, to two decimal places.
    ///
    /// Two places because the figure is read against a seconds axis, where a third would be
    /// noise the chart cannot resolve anyway.
    ///
    /// - Parameter seconds: The duration.
    /// - Returns: The formatted duration.
    static func seconds(_ seconds: TimeInterval) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0...2))
                )
            )
    }
}
