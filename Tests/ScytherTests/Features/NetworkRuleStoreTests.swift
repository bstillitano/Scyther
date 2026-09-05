//
//  NetworkRuleStoreTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRuleStoreTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var bodyDirectory: URL!

    override func setUpWithError() throws {
        suiteName = "NetworkRuleStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRuleBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    private func makeStore() -> NetworkRuleStore {
        NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
    }

    private func makeRule(_ name: String) -> NetworkRule {
        NetworkRule(
            id: UUID(),
            name: name,
            isEnabled: true,
            match: .path("/v1/*"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        )
    }

    func testRulesRoundTripThroughDefaults() {
        let store = makeStore()
        store.add(makeRule("first"))
        store.add(makeRule("second"))

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.rules.map(\.name), ["first", "second"])
    }

    func testTransientRulesAreNotPersisted() {
        let store = makeStore()
        store.add(makeRule("persisted"))
        store.addTransient(makeRule("transient"))

        XCTAssertEqual(store.rules.map(\.name), ["persisted"])
        XCTAssertEqual(store.transientRules.map(\.name), ["transient"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["persisted"])
    }

    func testSnapshotPutsPersistedRulesBeforeTransientOnes() {
        let store = makeStore()
        store.addTransient(makeRule("transient"))
        store.add(makeRule("persisted"))
        XCTAssertEqual(NetworkRuleSnapshot.current.rules.map(\.name), ["persisted", "transient"])
    }

    func testMasterSwitchDefaultsToOnAndPersists() {
        let store = makeStore()
        XCTAssertTrue(store.isEnabled)
        store.isEnabled = false
        XCTAssertFalse(makeStore().isEnabled)
        XCTAssertFalse(NetworkRuleSnapshot.current.isEnabled)
    }

    func testMoveChangesPrecedence() {
        let store = makeStore()
        store.add(makeRule("first"))
        store.add(makeRule("second"))
        store.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(store.rules.map(\.name), ["second", "first"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["second", "first"])
    }

    func testRemovingARuleDeletesItsBody() throws {
        let store = makeStore()
        let bodyID = store.storeBody(Data("{\"ok\":true}".utf8))
        var rule = makeRule("with body")
        rule.action = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0))
        store.add(rule)

        XCTAssertEqual(store.bodyData(for: bodyID), Data("{\"ok\":true}".utf8))
        store.remove(id: rule.id)
        XCTAssertNil(store.bodyData(for: bodyID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.bodyURL(for: bodyID).path))
    }

    func testUnknownActionInStoredJSONSkipsOnlyThatRule() throws {
        let valid = String(decoding: try JSONEncoder().encode(makeRule("valid")), as: UTF8.self)
        let json = """
        [{"id":"\(UUID().uuidString)","name":"future","isEnabled":true,
          "match":{"methods":[],"query":{}},"action":{"unknownCase":{}}},
         \(valid)]
        """
        defaults.set(Data(json.utf8), forKey: "Scyther.NetworkRules.Rules")

        let store = makeStore()
        XCTAssertEqual(store.rules.count, 1, "a rule Scyther cannot decode is skipped, not fatal")
        XCTAssertEqual(store.rules.map(\.name), ["valid"], "the rules either side of it still load")
    }

    // MARK: - Upsert

    func testAddingARuleWithAStoredIdentifierReplacesItInPlace() {
        let store = makeStore()
        let id = UUID()
        var first = makeRule("registered at launch")
        first.id = id
        store.add(first)
        store.add(makeRule("some other rule"))

        var second = makeRule("registered at launch")
        second.id = id
        second.isEnabled = false
        store.add(second)

        XCTAssertEqual(store.rules.count, 2, "relaunching must not stack another copy of the same rule")
        XCTAssertEqual(store.rules.map(\.name), ["registered at launch", "some other rule"],
                       "the replacement keeps the original's position, and so its precedence")
        XCTAssertEqual(store.rules.first?.isEnabled, false, "the replacement's contents win")
        XCTAssertEqual(makeStore().rules.count, 2, "and the upsert is what gets persisted")
    }

    func testAddingATransientRuleWithARegisteredIdentifierReplacesItInPlace() {
        let store = makeStore()
        let id = UUID()
        var first = makeRule("stub")
        first.id = id
        store.addTransient(first)

        var second = makeRule("stub")
        second.id = id
        second.isEnabled = false
        store.addTransient(second)

        XCTAssertEqual(store.transientRules.count, 1)
        XCTAssertEqual(store.transientRules.first?.isEnabled, false)
    }

    func testEveryRuleKindCanBeBuiltThroughThePublicAPI() {
        let store = makeStore()
        store.add(.mock(name: "m", matching: .path("/a"), returning: .json("{}")))
        store.add(.headers(name: "h", matching: .path("/b"), set: ["X": "1"], remove: []))
        store.add(.condition(name: "c", matching: .path("/c"), NetworkCondition(latency: 1)))
        store.add(.mapLocal(name: "l", matching: .path("/d"), serving: MapLocalFile(relativePath: "/tmp/x.json")))
        XCTAssertEqual(store.rules.count, 4)
    }
}


/// `Scyther.start()` is the only thing that constructs the shared store, and constructing it is
/// what publishes the persisted overrides to the interceptor. Every other test builds a store of
/// its own, which publishes as a side effect — which is exactly why the suite could not see that
/// a relaunched app applied nothing until its debug menu was opened.
@MainActor
final class NetworkRuleStartupTests: XCTestCase {

    override func tearDown() async throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
    }

    func testStartPublishesPersistedOverridesWithoutTheMenuBeingOpened() {
        let rule = NetworkRule(
            id: UUID(),
            name: "startup override",
            isEnabled: true,
            match: .host("startup.invalid"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        )
        NetworkRuleStore.shared.add(rule)
        defer { NetworkRuleStore.shared.remove(id: rule.id) }

        // Stand in for a relaunch: the rule is persisted, but the snapshot the interceptor reads
        // is back at the empty value it holds before any store has published to it.
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        XCTAssertFalse(NetworkRuleSnapshot.current.rules.contains { $0.id == rule.id })

        Scyther.start()

        XCTAssertTrue(
            NetworkRuleSnapshot.current.rules.contains { $0.id == rule.id },
            "a persisted override must apply from the launch's first request, not from whenever the menu is opened"
        )
    }
}
