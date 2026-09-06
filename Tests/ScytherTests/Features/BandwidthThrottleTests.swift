//
//  BandwidthThrottleTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class BandwidthThrottleTests: XCTestCase {

    func testNoCeilingProducesNoThrottle() {
        XCTAssertNil(BandwidthThrottle(bandwidthKBps: nil, maximumTotalSleep: 30))
        XCTAssertNil(BandwidthThrottle(bandwidthKBps: 0, maximumTotalSleep: 30))
        XCTAssertNil(BandwidthThrottle(bandwidthKBps: -1, maximumTotalSleep: 30))
    }

    /// The defect the throttle exists to fix: `URLSession` hands a body over in chunks smaller
    /// than a second's worth of any realistic ceiling, so a budget measured per delivery never
    /// sleeps. Measured per response it does.
    func testTheBudgetAccumulatesAcrossDeliveries() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 200, maximumTotalSleep: 30))

        // Two megabytes in the 64 KB chunks CFNetwork typically delivers. No single chunk comes
        // close to 200 KB, so a per-delivery budget would sleep for exactly none of them.
        var total: TimeInterval = 0
        var elapsed: TimeInterval = 0
        for _ in 0..<32 {
            let wait = throttle.delay(forwarding: 64 * 1024, elapsed: elapsed)
            total += wait
            elapsed += wait
        }

        // 2 MB at 200 KB/s is 10.24 seconds.
        XCTAssertEqual(total, 10.24, accuracy: 0.01)
    }

    func testATransferAlreadyUnderTheCeilingIsNotDelayed() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 200, maximumTotalSleep: 30))
        // 64 KB after a whole second is well under 200 KB/s.
        XCTAssertEqual(throttle.delay(forwarding: 64 * 1024, elapsed: 1), 0)
    }

    func testTheCumulativeCapBoundsOneResponse() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 1, maximumTotalSleep: 0.25))

        var total: TimeInterval = 0
        for _ in 0..<10 {
            total += throttle.delay(forwarding: 64 * 1024, elapsed: 0)
        }

        XCTAssertEqual(total, 0.25, accuracy: 0.0001, "a 640 KB body at 1 KB/s must not sleep for ten minutes")
    }

    /// Idle time used to accrue credit without limit, so a response that arrived late arrived all
    /// at once: headers early, a slow backend, then a burst, and the ceiling stopped applying.
    ///
    /// The two deliveries are what makes this an assertion about the *bound* rather than about
    /// the arithmetic in general. The first is small enough to be covered by the idle outright;
    /// the second is charged against a clock that has been wound back to one second of credit, so
    /// it owes three seconds rather than the two it would owe if the whole three-second think had
    /// been banked.
    func testIdleTimeAccruesOnlyABoundedBurstCredit() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 100, maximumTotalSleep: 30))

        // Headers arrive and the backend thinks for three seconds, then sends 500 KB in two goes.
        XCTAssertEqual(throttle.delay(forwarding: 100 * 1024, elapsed: 3), 0,
                       "one second of the think covers the first 100 KB outright")
        XCTAssertEqual(throttle.delay(forwarding: 400 * 1024, elapsed: 3), 3, accuracy: 0.001,
                       "the other two seconds of the think are written off rather than banked")
    }

    /// The long-poll and server-sent-events shape: mostly idle, in bursts. Every idle period used
    /// to bank credit, so the ceiling never applied to any of them.
    ///
    /// Each burst is twice the ceiling's worth of the think that preceded it, so the response as a
    /// whole has to be slowed to half speed: 900 KB at 50 KB/s is eighteen seconds, the source
    /// supplies nine of them, and the throttle owes the other nine.
    func testCreditDoesNotAccumulateAcrossSuccessiveIdlePeriods() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 50, maximumTotalSleep: 30))

        var elapsed: TimeInterval = 0
        var total: TimeInterval = 0
        for _ in 0..<3 {
            elapsed += 3 // the backend thinks
            let wait = throttle.delay(forwarding: 300 * 1024, elapsed: elapsed)
            total += wait
            elapsed += wait // and the caller honours the delay
        }

        XCTAssertEqual(total, 9, accuracy: 0.01, "each 300 KB burst is paced, not just the first")
        XCTAssertEqual(elapsed, 18, accuracy: 0.01, "the whole response converges on the ceiling")
    }

    /// The burst bound used to be applied to the credit standing *before* the bytes in hand were
    /// charged, which made the debt `count / rate − burstWindow` after any idle longer than the
    /// window — a constant, with the elapsed time cancelled out of it entirely.
    ///
    /// On the shipped EDGE ceiling that charged 1.13 seconds for every 64 KB chunk of a source
    /// running at a third of that ceiling, which is the case the type's own documentation
    /// promises is free.
    func testASourceDeliveringUnderItsCeilingIsNeverDelayed() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 30, maximumTotalSleep: 30))

        var elapsed: TimeInterval = 0
        for _ in 0..<20 {
            elapsed += 6.5 // 64 KB every 6.5 seconds is about 10 KB/s, a third of the ceiling
            XCTAssertEqual(throttle.delay(forwarding: 64 * 1024, elapsed: elapsed), 0,
                           "a transfer inside its ceiling owes nothing, whatever the chunking")
        }
    }

    /// The consequence of charging debt that was never owed: ``BandwidthThrottle/maximumTotalSleep``
    /// ran out — roughly 1.7 MB into an EDGE response — and pacing then stopped for the rest of it,
    /// so the ceiling silently lifted on exactly the traffic it was meant to shape.
    func testAnUnderCeilingTransferLeavesThePacingBudgetIntact() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 30, maximumTotalSleep: 30))

        var elapsed: TimeInterval = 0
        for _ in 0..<20 {
            elapsed += 6.5
            _ = throttle.delay(forwarding: 64 * 1024, elapsed: elapsed)
        }

        // The source now dumps two megabytes at once, which is far over the ceiling.
        XCTAssertEqual(throttle.delay(forwarding: 2 * 1024 * 1024, elapsed: elapsed), 30,
                       accuracy: 0.001,
                       "the whole budget is still there for the burst that actually needs it")
    }

    /// The other side of the bound: a pause shorter than the burst window is forgiven, so an
    /// ordinary response already under its ceiling is never delayed by it.
    func testAPauseShorterThanTheBurstWindowIsForgiven() throws {
        var throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: 200, maximumTotalSleep: 30))
        XCTAssertEqual(throttle.delay(forwarding: 64 * 1024, elapsed: 0.5), 0)
    }

    /// A host app supplies the ceiling, so `bandwidthKBps * 1024` must not be allowed to overflow.
    func testAnAbsurdCeilingIsClamped() throws {
        let throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: .max, maximumTotalSleep: 30))
        XCTAssertEqual(throttle.bytesPerSecond, Double(BandwidthThrottle.maximumBandwidthKBps * 1024))
    }
}
