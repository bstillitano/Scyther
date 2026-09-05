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

    /// A host app supplies the ceiling, so `bandwidthKBps * 1024` must not be allowed to overflow.
    func testAnAbsurdCeilingIsClamped() throws {
        let throttle = try XCTUnwrap(BandwidthThrottle(bandwidthKBps: .max, maximumTotalSleep: 30))
        XCTAssertEqual(throttle.bytesPerSecond, Double(BandwidthThrottle.maximumBandwidthKBps * 1024))
    }
}
