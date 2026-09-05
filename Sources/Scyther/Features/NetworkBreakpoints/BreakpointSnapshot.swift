//
//  BreakpointSnapshot.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// The breakpoints as the interceptor sees them.
///
/// `HTTPInterceptorURLProtocol` runs on threads the URL loading system owns. It cannot hop to the
/// main actor to read ``BreakpointStore`` without risking a deadlock, so the store publishes an
/// immutable copy here after every mutation and the interceptor reads it under a lock — exactly
/// as ``NetworkRuleSnapshot`` does for overrides.
///
/// ## The test-run gate
///
/// ``current`` reports **disabled** inside an XCTest process. A breakpoint holds a request until
/// somebody resolves it, and nobody is watching a CI run, so a breakpoint left enabled on a
/// developer's device could otherwise reach the shared suite and hold a request there for its
/// whole timeout. The gate is on the read rather than on the store, so it covers every path into
/// the interceptor at once.
///
/// A test that is *about* breakpoints opts back in with ``setEnabledDuringTests(_:)`` and turns it
/// off again in `tearDown`. Nothing in production calls it.
///
/// ## Topics
///
/// ### Reading
/// - ``current``
/// - ``State``
///
/// ### Writing
/// - ``update(isEnabled:breakpoints:)``
///
/// ### Testing
/// - ``setEnabledDuringTests(_:)``
enum BreakpointSnapshot {
    /// Everything the interceptor reads before it decides whether to hold an exchange.
    struct State: Sendable {
        /// The breakpoints' master switch.
        var isEnabled: Bool

        /// The configured breakpoints, in the order they were added.
        var breakpoints: [NetworkBreakpoint]

        /// Creates a state.
        ///
        /// - Parameters:
        ///   - isEnabled: The master switch.
        ///   - breakpoints: The configured breakpoints.
        init(isEnabled: Bool, breakpoints: [NetworkBreakpoint]) {
            self.isEnabled = isEnabled
            self.breakpoints = breakpoints
        }

        /// The first enabled breakpoint that holds `request` at `stage`, or `nil`.
        ///
        /// The first rather than every one: two breakpoints holding the same request would stop
        /// it twice for one journey, which is a worse answer than the first one winning — the
        /// same precedence rule overrides already use.
        ///
        /// - Parameters:
        ///   - request: The request to test.
        ///   - stage: The side of the exchange about to happen.
        /// - Returns: The breakpoint that holds it, or `nil` when none does.
        func breakpoint(matching request: URLRequest, stage: NetworkBreakpoint.Stage) -> NetworkBreakpoint? {
            guard isEnabled else { return nil }
            return breakpoints.first { candidate in
                guard candidate.isEnabled else { return false }
                switch stage {
                case .request: guard candidate.stage.holdsRequest else { return false }
                case .response: guard candidate.stage.holdsResponse else { return false }
                case .both: break
                }
                return candidate.match.matches(request)
            }
        }
    }

    /// Guards ``storage`` and ``isEnabledDuringTests`` so that reads from the URL loading
    /// system's threads never observe a half-written value.
    private static let lock = NSLock()

    /// The published copy of the store's state.
    ///
    /// - Note: Declared `nonisolated(unsafe)` because every access goes through ``lock``, which
    ///   provides the synchronisation the compiler cannot prove.
    nonisolated(unsafe) private static var storage = State(isEnabled: false, breakpoints: [])

    /// Whether a test has deliberately opted this process back in. See the type's discussion.
    ///
    /// - Note: Declared `nonisolated(unsafe)` for the same reason as ``storage``.
    nonisolated(unsafe) private static var isEnabledDuringTests = false

    /// The current snapshot. Safe to call from any thread.
    ///
    /// Reports disabled during an XCTest run unless a test has called
    /// ``setEnabledDuringTests(_:)``.
    static var current: State {
        lock.withLock {
            guard !AppEnvironment.isTestCase || isEnabledDuringTests else {
                return State(isEnabled: false, breakpoints: [])
            }
            return storage
        }
    }

    /// Replaces the snapshot. Called by ``BreakpointStore`` after every mutation.
    ///
    /// - Parameters:
    ///   - isEnabled: The master switch.
    ///   - breakpoints: The configured breakpoints.
    static func update(isEnabled: Bool, breakpoints: [NetworkBreakpoint]) {
        lock.withLock {
            storage = State(isEnabled: isEnabled, breakpoints: breakpoints)
        }
    }

    /// Opts this test process into evaluating breakpoints, or back out of it.
    ///
    /// Only a test that drives a breakpoint end to end calls this, and it turns it off again in
    /// `tearDown` so the opt-in cannot leak into the rest of the run. Nothing in production calls
    /// it; it exists because the alternative — weakening the gate itself — would put the CI hang
    /// the gate prevents back on the table.
    ///
    /// - Parameter enabled: Whether breakpoints are evaluated for the rest of this process.
    static func setEnabledDuringTests(_ enabled: Bool) {
        lock.withLock { isEnabledDuringTests = enabled }
    }
}
