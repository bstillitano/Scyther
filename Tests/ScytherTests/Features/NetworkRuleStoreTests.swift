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
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
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
        rule.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0))
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

    // MARK: - Persistence integrity

    /// `JSONEncoder` refuses a non-finite `Double`, and both the public API and the editor can
    /// hand the store one. Losing the write silently means the in-memory rules and the persisted
    /// blob disagree from then on.
    func testARuleCarryingANonFiniteLatencyIsStillPersisted() {
        let store = makeStore()
        store.add(NetworkRule(name: "infinite",
                              match: .path("/a"),
                              actions: NetworkRuleActions(condition: NetworkCondition(latency: .infinity))))

        XCTAssertEqual(makeStore().rules.map(\.name), ["infinite"])
        XCTAssertEqual(store.rules.first?.actions.condition?.latency, 0,
                       "a value JSON cannot express is sanitised on the way in")
    }

    /// The worse half of the same defect: the offending rule stays in the array, so every later
    /// mutation fails to persist too.
    func testANonFiniteValueDoesNotStopEveryLaterRuleBeingPersisted() {
        let store = makeStore()
        store.add(NetworkRule(name: "infinite",
                              match: .path("/a"),
                              actions: NetworkRuleActions(condition: NetworkCondition(latency: .infinity))))
        store.add(makeRule("second"))

        XCTAssertEqual(makeStore().rules.map(\.name), ["infinite", "second"])
    }

    func testANonFiniteMockDelayIsSanitised() {
        let store = makeStore()
        store.add(NetworkRule(name: "nan",
                              match: .path("/a"),
                              actions: NetworkRuleActions(stub: .mock(MockResponse(delay: .nan)))))

        guard case .mock(let mock) = makeStore().rules.first?.actions.stub else {
            return XCTFail("expected the rule to survive the round trip")
        }
        XCTAssertEqual(mock.delay, 0)
    }

    /// A blob that will not decode as an array at all — truncated, or a future version that wraps
    /// it in an object — must not become an empty list that is then written back over the
    /// developer's whole configuration.
    func testAnUnreadableBlobIsSetAsideRatherThanOverwritten() {
        let original = Data(#"{"version": 2, "rules": []}"#.utf8)
        defaults.set(original, forKey: "Scyther.NetworkRules.Rules")

        let store = makeStore()
        XCTAssertTrue(store.rules.isEmpty)

        store.add(makeRule("written after the unreadable load"))

        let survives = defaults.dictionaryRepresentation().values.contains { ($0 as? Data) == original }
        XCTAssertTrue(survives, "the developer's configuration is set aside, not destroyed")
    }

    func testAnUnreadableBlobIsReportedRatherThanShownAsAnEmptyList() {
        defaults.set(Data("not json at all".utf8), forKey: "Scyther.NetworkRules.Rules")

        let store = makeStore()

        XCTAssertEqual(store.lastFailure, .rulesNotLoaded)
        store.acknowledgeFailure()
        XCTAssertNil(store.lastFailure)
    }

    /// The store does not know what the developer had configured, so every body on disk looks
    /// orphaned. Sweeping on that basis would delete the bodies of the very configuration that
    /// was set aside to be recovered.
    func testAnUnreadableBlobStandsTheSweepDown() async throws {
        let store = makeStore()
        let body = store.storeBody(Data("belongs to the unreadable configuration".utf8))
        try age(store.bodyURL(for: body))
        defaults.set(Data("not json at all".utf8), forKey: "Scyther.NetworkRules.Rules")

        let reloaded = makeStore()
        reloaded.sweepOrphanedBodies()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(reloaded.bodyData(for: body),
                       Data("belongs to the unreadable configuration".utf8))
    }

    // MARK: - Map local copies

    /// Writes a throwaway document, standing in for one picked with the system file importer.
    private func pickedFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testStoringAFileCopiesItIntoTheRulesDirectory() throws {
        let store = makeStore()
        let picked = try pickedFile(named: "users.json", contents: "[]")

        let path = try XCTUnwrap(store.storeFile(at: picked))
        let copy = URL(fileURLWithPath: path)
        XCTAssertEqual(copy.deletingLastPathComponent().standardizedFileURL,
                       bodyDirectory.standardizedFileURL)
        XCTAssertNotNil(UUID(uuidString: copy.lastPathComponent),
                        "the copy is named like a body so the sweep can reclaim it")
        XCTAssertEqual(try Data(contentsOf: copy), Data("[]".utf8))
    }

    /// The copy is what makes the override survive the document going away, which is the whole
    /// reason the file is copied rather than referenced.
    func testACopiedFileOutlivesTheDocumentItWasCopiedFrom() throws {
        let store = makeStore()
        let picked = try pickedFile(named: "users.json", contents: "[1]")
        let path = try XCTUnwrap(store.storeFile(at: picked))

        try FileManager.default.removeItem(at: picked)

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("[1]".utf8))
    }

    func testStoringAFileThatCannotBeReadReturnsNil() {
        let store = makeStore()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/nothing.json")
        XCTAssertNil(store.storeFile(at: missing))
    }

    func testRemovingAMapLocalRuleDeletesItsCopy() throws {
        let store = makeStore()
        let path = try XCTUnwrap(store.storeFile(at: try pickedFile(named: "users.json", contents: "[]")))
        var rule = makeRule("map local")
        rule.actions.stub = .mapLocal(MapLocalFile(relativePath: path, fileName: "users.json"))
        store.add(rule)

        store.remove(id: rule.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// A map-local override pointing at a path Scyther did not write — one supplied from code —
    /// must never have that file deleted out from under the host app.
    func testRemovingAMapLocalRuleLeavesAPathItDidNotWriteAlone() throws {
        let store = makeStore()
        let picked = try pickedFile(named: "users.json", contents: "[]")
        var rule = makeRule("map local")
        rule.actions.stub = .mapLocal(MapLocalFile(relativePath: picked.path))
        store.add(rule)

        store.remove(id: rule.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: picked.path))
    }

    // MARK: - Body sweep

    /// Backdates a file past the sweep's grace period, standing in for a body written by an
    /// earlier launch.
    private func age(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-NetworkRuleStore.bodySweepGracePeriod - 60)],
            ofItemAtPath: url.path
        )
    }

    func testTheSweepDeletesOrphanedBodiesAndKeepsReferencedOnes() throws {
        let store = makeStore()
        let referenced = store.storeBody(Data("still in use".utf8))
        let orphan = store.storeBody(Data("nothing points here".utf8))
        try age(store.bodyURL(for: referenced))
        try age(store.bodyURL(for: orphan))

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [referenced],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertEqual(store.bodyData(for: referenced), Data("still in use".utf8))
        XCTAssertNil(store.bodyData(for: orphan), "a body no rule points at is reclaimed")
    }

    /// A body is written before the rule that points at it is stored, so a sweep racing a
    /// `Scyther.start()` that is immediately followed by `rules.add(...)` must not eat it.
    func testTheSweepLeavesAFreshlyWrittenBodyAlone() {
        let store = makeStore()
        let justWritten = store.storeBody(Data("about to be referenced".utf8))

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertEqual(store.bodyData(for: justWritten), Data("about to be referenced".utf8))
    }

    /// The directory sits inside the host app's container. Anything not named after a UUID was
    /// not written by the store, and deleting it would be far worse than leaving it.
    func testTheSweepLeavesFilesItDidNotName() throws {
        let store = makeStore()
        store.storeBody(Data("a real body".utf8))
        let stranger = bodyDirectory.appendingPathComponent("something-else.txt")
        try Data("not ours".utf8).write(to: stranger)
        try age(stranger)

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path))
    }

    func testSweepingTheStoreKeepsAFileAMapLocalRulePointsAt() async throws {
        let store = makeStore()
        let path = try XCTUnwrap(store.storeFile(at: try pickedFile(named: "users.json", contents: "[]")))
        var rule = makeRule("map local")
        rule.actions.stub = .mapLocal(MapLocalFile(relativePath: path, fileName: "users.json"))
        store.add(rule)

        let orphan = store.storeBody(Data("orphan".utf8))
        try age(URL(fileURLWithPath: path))
        try age(store.bodyURL(for: orphan))

        store.sweepOrphanedBodies()

        for _ in 0..<200 where store.bodyData(for: orphan) != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNil(store.bodyData(for: orphan))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "the copy a map local override serves is still in use")
    }

    func testSweepingTheStoreKeepsBodiesBothPersistedAndTransientRulesPointAt() async throws {
        let store = makeStore()

        let persistedBody = store.storeBody(Data("persisted".utf8))
        var persisted = makeRule("persisted")
        persisted.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: persistedBody, delay: 0))
        store.add(persisted)

        let transientBody = store.storeBody(Data("transient".utf8))
        var transient = makeRule("transient")
        transient.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: transientBody, delay: 0))
        store.addTransient(transient)

        let orphan = store.storeBody(Data("orphan".utf8))
        for id in [persistedBody, transientBody, orphan] {
            try age(store.bodyURL(for: id))
        }

        store.sweepOrphanedBodies()

        // The sweep runs off the main actor, so poll rather than assuming it has landed.
        for _ in 0..<200 where store.bodyData(for: orphan) != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNil(store.bodyData(for: orphan))
        XCTAssertEqual(store.bodyData(for: persistedBody), Data("persisted".utf8))
        XCTAssertEqual(store.bodyData(for: transientBody), Data("transient".utf8),
                       "a transient rule's body is still in use, even though the rule is not persisted")
    }

    /// `Application Support` is backed up by default, and a colleague's 40 MB capture has no
    /// business inflating the host app's iCloud backup.
    func testTheBodyDirectoryIsExcludedFromBackup() throws {
        let store = makeStore()
        store.storeBody(Data("body".utf8))

        let values = try bodyDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
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

    /// Whether the process was already started when this test began.
    ///
    /// `Scyther.start()` is the seam under test — asserting against the narrower
    /// `NetworkRuleStore.shared.activate()` instead would prove nothing, because that method was
    /// added by the very fix this test guards and would still pass if the call were deleted from
    /// `start()` again. So the real thing is called, and what it changed is put back.
    private var wasStarted = false

    /// Whether the console was already capturing when this test began.
    private var wasCapturing = false

    override func setUp() async throws {
        wasStarted = Scyther.isStarted
        wasCapturing = ConsoleLogger.instance.isCapturing
    }

    /// Puts back the two pieces of process state `start()` changes that later tests can observe.
    ///
    /// `Scyther._started` is the important one: while it is `false`,
    /// `HTTPInterceptorURLProtocol.canInit(with:)` refuses every request, so restoring it also
    /// undoes the URL interception `start()` registered. The remaining hooks — the crash handler,
    /// the interface toolkit's swizzling and the appearance observers — install once per process
    /// and have no uninstall; they are additive and inert unless something asks for them, so they
    /// are left alone rather than faked away. Location spoofing puts itself back a second later,
    /// which `start()` already arranges.
    override func tearDown() async throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        if !wasCapturing {
            ConsoleLogger.instance.stop()
        }
        Scyther._started = wasStarted
    }

    func testStartPublishesPersistedOverridesWithoutTheMenuBeingOpened() {
        let rule = NetworkRule(
            id: UUID(),
            name: "startup override",
            isEnabled: true,
            match: .host("startup.invalid"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
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
