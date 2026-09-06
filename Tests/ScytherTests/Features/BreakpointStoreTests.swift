//
//  BreakpointStoreTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class BreakpointStoreTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "BreakpointStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: [])
        BreakpointSnapshot.setEnabledDuringTests(false)
    }

    private func makeBreakpoint(_ name: String, stage: NetworkBreakpoint.Stage = .request) -> NetworkBreakpoint {
        NetworkBreakpoint(id: UUID(),
                          name: name,
                          isEnabled: true,
                          match: .path("/v1/*"),
                          stage: stage,
                          timeout: 60)
    }

    func testTheMasterSwitchDefaultsToOff() {
        XCTAssertFalse(BreakpointStore(defaults: defaults).isEnabled,
                       "a feature that holds the app up must be switched on deliberately")
    }

    func testBreakpointsRoundTrip() {
        let store = BreakpointStore(defaults: defaults)
        store.add(makeBreakpoint("cart", stage: .both))
        let reloaded = BreakpointStore(defaults: defaults)
        XCTAssertEqual(reloaded.breakpoints.map(\.name), ["cart"])
        XCTAssertEqual(reloaded.breakpoints.first?.stage, .both)
        XCTAssertEqual(reloaded.breakpoints.first?.match.path?.value, "/v1/*")
    }

    func testTimeoutIsClampedToTheAllowedRange() {
        let store = BreakpointStore(defaults: defaults)
        var tooShort = makeBreakpoint("short")
        tooShort.timeout = 1
        var tooLong = makeBreakpoint("long")
        tooLong.timeout = 9_000
        store.add(tooShort)
        store.add(tooLong)
        XCTAssertEqual(store.breakpoints.map(\.timeout), [5, 300])
    }

    /// A timeout hand-edited into the persisted blob is clamped on the way back in, so the
    /// invariant holds for state this process did not write.
    func testAnOutOfRangeTimeoutIsClampedOnDecode() throws {
        let breakpoint = NetworkBreakpoint(id: UUID(),
                                           name: "cart",
                                           isEnabled: true,
                                           match: .path("/v1/*"),
                                           stage: .request,
                                           timeout: 60)
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode([breakpoint])) as? [[String: Any]]
        json?[0]["timeout"] = 100_000
        defaults.set(try JSONSerialization.data(withJSONObject: try XCTUnwrap(json)), forKey: "Scyther.NetworkBreakpoints.Breakpoints")

        XCTAssertEqual(BreakpointStore(defaults: defaults).breakpoints.first?.timeout, 300)
    }

    func testUpdatingReplacesTheBreakpointInPlace() {
        let store = BreakpointStore(defaults: defaults)
        var breakpoint = makeBreakpoint("cart")
        store.add(breakpoint)
        store.add(makeBreakpoint("checkout"))
        breakpoint.name = "renamed"
        store.update(breakpoint)
        XCTAssertEqual(store.breakpoints.map(\.name), ["renamed", "checkout"])
    }

    func testRemovingDropsOnlyThatBreakpoint() {
        let store = BreakpointStore(defaults: defaults)
        let breakpoint = makeBreakpoint("cart")
        store.add(breakpoint)
        store.add(makeBreakpoint("checkout"))
        store.remove(id: breakpoint.id)
        XCTAssertEqual(store.breakpoints.map(\.name), ["checkout"])
    }

    func testAddingUpsertsByIdentifier() {
        let store = BreakpointStore(defaults: defaults)
        var breakpoint = makeBreakpoint("cart")
        store.add(breakpoint)
        breakpoint.name = "cart again"
        store.add(breakpoint)
        XCTAssertEqual(store.breakpoints.map(\.name), ["cart again"],
                       "one identifier is one row, however many times it is registered")
    }

    func testTheSnapshotFollowsTheStore() {
        BreakpointSnapshot.setEnabledDuringTests(true)
        let store = BreakpointStore(defaults: defaults)
        store.isEnabled = true
        store.add(makeBreakpoint("cart"))

        XCTAssertTrue(BreakpointSnapshot.current.isEnabled)
        XCTAssertEqual(BreakpointSnapshot.current.breakpoints.map(\.name), ["cart"])
    }

    /// The rail the whole feature rests on: a breakpoint left enabled can never hold up CI.
    func testTheSnapshotReportsDisabledInATestCase() {
        let store = BreakpointStore(defaults: defaults)
        store.isEnabled = true
        store.add(makeBreakpoint("cart"))
        XCTAssertTrue(AppEnvironment.isTestCase, "this suite only means anything inside a test run")
        XCTAssertFalse(
            BreakpointSnapshot.current.isEnabled,
            "AppEnvironment.isTestCase is true in this process, so breakpoints must report as off"
        )
        XCTAssertTrue(BreakpointSnapshot.current.breakpoints.isEmpty)
    }

    func testTheTestOverrideIsOffAgainWhenItIsSwitchedBack() {
        BreakpointSnapshot.setEnabledDuringTests(true)
        let store = BreakpointStore(defaults: defaults)
        store.isEnabled = true
        store.add(makeBreakpoint("cart"))
        XCTAssertTrue(BreakpointSnapshot.current.isEnabled)

        BreakpointSnapshot.setEnabledDuringTests(false)
        XCTAssertFalse(BreakpointSnapshot.current.isEnabled)
    }

    func testMatchingBreakpointsForARequestSkipDisabledOnesAndTheWrongStage() {
        let store = BreakpointStore(defaults: defaults)
        var disabled = makeBreakpoint("disabled")
        disabled.isEnabled = false
        store.add(disabled)
        store.add(makeBreakpoint("response only", stage: .response))
        store.add(makeBreakpoint("request", stage: .request))
        store.add(makeBreakpoint("both", stage: .both))
        store.isEnabled = true

        let state = BreakpointSnapshot.State(isEnabled: true, breakpoints: store.breakpoints)
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        XCTAssertEqual(state.breakpoint(matching: request, stage: .request)?.name, "request")
        XCTAssertEqual(state.breakpoint(matching: request, stage: .response)?.name, "response only")
    }

    func testNothingMatchesWhileTheMasterSwitchIsOff() {
        let state = BreakpointSnapshot.State(isEnabled: false, breakpoints: [makeBreakpoint("cart")])
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        XCTAssertNil(state.breakpoint(matching: request, stage: .request))
    }
}
