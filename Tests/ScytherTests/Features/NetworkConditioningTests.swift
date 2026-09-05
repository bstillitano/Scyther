//
//  NetworkConditioningTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkConditioningPresetTests: XCTestCase {

    func testEveryPresetButCustomFillsInAllThreeFields() {
        for preset in NetworkConditioningPreset.allCases where preset != .custom {
            let condition = preset.condition
            XCTAssertNotNil(condition, "\(preset.rawValue) must supply a condition")
            XCTAssertNotNil(condition?.bandwidthKBps, "\(preset.rawValue) must supply a ceiling")
        }
    }

    func testCustomSuppliesNothing() {
        XCTAssertNil(NetworkConditioningPreset.custom.condition)
    }

    func testEveryPresetRecognisesItsOwnCondition() {
        for preset in NetworkConditioningPreset.allCases where preset != .custom {
            let condition = try? XCTUnwrap(preset.condition)
            XCTAssertEqual(NetworkConditioningPreset.matching(condition ?? NetworkCondition()), preset)
        }
    }

    func testAConditionMatchingNoPresetReadsAsCustom() {
        let odd = NetworkCondition(latency: 1.234, bandwidthKBps: 77, failureRate: 0.33)
        XCTAssertEqual(NetworkConditioningPreset.matching(odd), .custom)
    }

    /// No preset sets a failure code, so one carrying a non-default code is still the preset it
    /// otherwise is rather than silently becoming Custom.
    func testAFailureCodeDoesNotStopAConditionMatchingAPreset() throws {
        var condition = try XCTUnwrap(NetworkConditioningPreset.threeG.condition)
        condition.failureCode = URLError.Code.timedOut.rawValue
        XCTAssertEqual(NetworkConditioningPreset.matching(condition), .threeG)
    }

    func testSummaryReadsOffWhileConditioningIsSwitchedOff() throws {
        let condition = try XCTUnwrap(NetworkConditioningPreset.edge.condition)
        XCTAssertEqual(NetworkConditioningPreset.summary(isEnabled: false, condition: condition),
                       localized("Off"))
        XCTAssertEqual(NetworkConditioningPreset.summary(isEnabled: true, condition: condition),
                       "EDGE")
    }
}

@MainActor
final class NetworkConditioningStoreTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NetworkConditioningStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    /// Clears the snapshot's conditioning half, so a test cannot leak a global condition into
    /// every later interceptor test in the run.
    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(globalCondition: nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> NetworkConditioningStore {
        NetworkConditioningStore(defaults: defaults)
    }

    func testConditioningIsOffByDefault() {
        let store = makeStore()
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.condition, NetworkCondition())
        XCTAssertNil(NetworkRuleSnapshot.current.globalCondition,
                     "nothing is published while the switch is off")
    }

    func testTheSwitchAndTheConditionSurviveARelaunch() throws {
        let store = makeStore()
        store.isEnabled = true
        store.condition = try XCTUnwrap(NetworkConditioningPreset.threeG.condition)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.condition, NetworkConditioningPreset.threeG.condition)
    }

    func testEnablingPublishesTheConditionToTheSnapshot() throws {
        let store = makeStore()
        store.condition = try XCTUnwrap(NetworkConditioningPreset.edge.condition)
        XCTAssertNil(NetworkRuleSnapshot.current.globalCondition, "still off")

        store.isEnabled = true
        XCTAssertEqual(NetworkRuleSnapshot.current.globalCondition,
                       NetworkConditioningPreset.edge.condition)

        store.isEnabled = false
        XCTAssertNil(NetworkRuleSnapshot.current.globalCondition)
    }

    func testEditingWhileEnabledRepublishes() {
        let store = makeStore()
        store.isEnabled = true
        store.condition.latency = 4
        XCTAssertEqual(NetworkRuleSnapshot.current.globalCondition?.latency, 4)
    }

    /// The two stores write different halves of one snapshot, and neither may clear the other's.
    func testPublishingOverridesDoesNotClearTheGlobalCondition() {
        let store = makeStore()
        store.isEnabled = true
        store.condition.latency = 2

        NetworkRuleSnapshot.update(isEnabled: true, rules: [])

        XCTAssertEqual(NetworkRuleSnapshot.current.globalCondition?.latency, 2)
    }

    func testPublishingTheGlobalConditionDoesNotClearTheRules() {
        let rule = NetworkRule(name: "cart",
                               match: .path("/api/cart"),
                               actions: NetworkRuleActions(stub: .mock(MockResponse())))
        NetworkRuleSnapshot.update(isEnabled: true, rules: [rule])
        defer { NetworkRuleSnapshot.update(isEnabled: true, rules: []) }

        let store = makeStore()
        store.isEnabled = true

        XCTAssertEqual(NetworkRuleSnapshot.current.rules.map(\.name), ["cart"])
    }

    func testActivateRepublishesWhatIsAlreadyStored() throws {
        let store = makeStore()
        store.isEnabled = true
        store.condition = try XCTUnwrap(NetworkConditioningPreset.wifi.condition)
        NetworkRuleSnapshot.update(globalCondition: nil)

        store.activate()

        XCTAssertEqual(NetworkRuleSnapshot.current.globalCondition,
                       NetworkConditioningPreset.wifi.condition)
    }
}

@MainActor
final class NetworkConditioningViewModelTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NetworkConditioningViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(globalCondition: nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A store over this test's throwaway suite. Built on the main actor, where it belongs, rather
    /// than in the inherited-nonisolated `setUpWithError()`.
    private var store: NetworkConditioningStore {
        NetworkConditioningStore(defaults: defaults)
    }

    func testPickingAPresetFillsInAllThreeFields() {
        let store = self.store
        let viewModel = NetworkConditioningViewModel(store: store)
        viewModel.preset = .veryBad

        XCTAssertEqual(viewModel.latency, 0.5)
        XCTAssertEqual(viewModel.bandwidthKBps, 125)
        XCTAssertEqual(viewModel.failureRate, 0.1)
    }

    /// Custom is the absence of a preset, so picking it must not wipe what is already typed.
    func testPickingCustomLeavesTheFieldsAlone() {
        let store = self.store
        let viewModel = NetworkConditioningViewModel(store: store)
        viewModel.preset = .threeG
        viewModel.preset = .custom

        XCTAssertEqual(viewModel.latency, 0.1)
        XCTAssertEqual(viewModel.bandwidthKBps, 100)
    }

    func testEditingAFieldMakesThePresetReadAsCustom() {
        let store = self.store
        let viewModel = NetworkConditioningViewModel(store: store)
        viewModel.preset = .threeG
        XCTAssertEqual(viewModel.preset, .threeG)

        viewModel.latency = 9
        XCTAssertEqual(viewModel.preset, .custom, "the picker follows the fields, not the reverse")
    }

    func testAZeroCeilingMeansUnthrottled() {
        let store = self.store
        let viewModel = NetworkConditioningViewModel(store: store)
        viewModel.bandwidthKBps = 0
        XCTAssertNil(store.condition.bandwidthKBps)
    }

    func testTheSwitchReadsAndWritesTheStore() {
        let store = self.store
        let viewModel = NetworkConditioningViewModel(store: store)
        viewModel.isEnabled = true
        XCTAssertTrue(store.isEnabled)

        store.isEnabled = false
        XCTAssertFalse(viewModel.isEnabled, "the screen reads through rather than mirroring")
    }
}
