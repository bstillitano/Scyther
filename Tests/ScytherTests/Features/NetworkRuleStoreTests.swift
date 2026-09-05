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

    func testEveryRuleKindCanBeBuiltThroughThePublicAPI() {
        let store = makeStore()
        store.add(.mock(name: "m", matching: .path("/a"), returning: .json("{}")))
        store.add(.headers(name: "h", matching: .path("/b"), set: ["X": "1"], remove: []))
        store.add(.condition(name: "c", matching: .path("/c"), NetworkCondition(latency: 1)))
        store.add(.mapLocal(name: "l", matching: .path("/d"), serving: MapLocalFile(relativePath: "/tmp/x.json")))
        XCTAssertEqual(store.rules.count, 4)
    }
}
