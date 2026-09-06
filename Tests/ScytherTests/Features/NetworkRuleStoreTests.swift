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
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
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
        let bodyID = try store.storeBody(Data("{\"ok\":true}".utf8))
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

    /// The key an unreadable configuration is set aside under.
    private let quarantineKey = "Scyther.NetworkRules.Rules.Unreadable"

    /// What is currently in quarantine, oldest first.
    private var quarantined: [Data] {
        defaults.array(forKey: quarantineKey) as? [Data] ?? []
    }

    /// A blob that will not decode as an array at all — truncated, or a future version that wraps
    /// it in an object — must not become an empty list that is then written back over the
    /// developer's whole configuration.
    ///
    /// Asserting the quarantine key by name, rather than that the bytes are somewhere in the
    /// suite, is the point: the previous spelling of this test passed just as well when the store
    /// had not written anything at all and the blob was simply still sitting under the rules key.
    func testAnUnreadableBlobIsSetAsideRatherThanOverwritten() {
        let original = Data(#"{"version": 2, "rules": []}"#.utf8)
        defaults.set(original, forKey: "Scyther.NetworkRules.Rules")

        let store = makeStore()
        XCTAssertTrue(store.rules.isEmpty)

        store.add(makeRule("written after the unreadable load"))

        XCTAssertEqual(quarantined, [original], "the developer's configuration is set aside, not destroyed")
        XCTAssertNotEqual(defaults.data(forKey: "Scyther.NetworkRules.Rules"), original,
                          "and the rules key has moved on rather than never having been written")
    }

    /// A second unreadable configuration used to overwrite the first, with nothing recording that
    /// it had. Both promises were then broken at once: one configuration destroyed, and the
    /// developer told twice that theirs had been kept.
    func testASecondUnreadableBlobDoesNotOverwriteTheFirst() {
        let first = Data(#"{"version": 2, "rules": []}"#.utf8)
        defaults.set(first, forKey: "Scyther.NetworkRules.Rules")
        makeStore().add(makeRule("after the first failure"))

        let second = Data(#"{"version": 3, "rules": []}"#.utf8)
        defaults.set(second, forKey: "Scyther.NetworkRules.Rules")
        makeStore().add(makeRule("after the second failure"))

        XCTAssertEqual(quarantined, [first, second])
    }

    /// Preferences are not an archive: a build that cannot read what it wrote would otherwise set
    /// a configuration aside on every launch forever.
    func testTheQuarantineKeepsTheMostRecentBlobsAndNoMore() {
        var written: [Data] = []
        for version in 0..<(NetworkRuleStore.maximumQuarantinedBlobs + 2) {
            let blob = Data(#"{"version": \#(version), "rules": []}"#.utf8)
            written.append(blob)
            defaults.set(blob, forKey: "Scyther.NetworkRules.Rules")
            makeStore().add(makeRule("after failure \(version)"))
        }

        XCTAssertEqual(quarantined, Array(written.suffix(NetworkRuleStore.maximumQuarantinedBlobs)))
    }

    /// Throwing every override away is the only thing that discards a set-aside configuration —
    /// and the only way back to a sweeping store, since the sweep stands down while one exists.
    func testRemovingEverythingDiscardsTheQuarantine() {
        defaults.set(Data("not json at all".utf8), forKey: "Scyther.NetworkRules.Rules")
        let store = makeStore()
        store.add(makeRule("something"))
        XCTAssertFalse(quarantined.isEmpty)

        store.removeAll()

        XCTAssertTrue(quarantined.isEmpty)
        XCTAssertFalse(store.isSweepSuspended, "the sweep can start reclaiming again")
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
    ///
    /// The stand-down is asserted directly rather than inferred from a file that is still there
    /// after a fixed sleep, because a sweep that had simply not got round to the file yet would
    /// have satisfied that just as well.
    func testAnUnreadableBlobStandsTheSweepDown() throws {
        let store = makeStore()
        let body = try store.storeBody(Data("belongs to the unreadable configuration".utf8))
        try age(store.bodyURL(for: body))
        defaults.set(Data("not json at all".utf8), forKey: "Scyther.NetworkRules.Rules")

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.isSweepSuspended)
        reloaded.sweepOrphanedBodies()

        XCTAssertEqual(reloaded.bodyData(for: body),
                       Data("belongs to the unreadable configuration".utf8))
    }

    /// The positive control for the test above: the same orphan, the same call, and no quarantine.
    /// Without this, the stand-down could be spelled "never sweep anything" and still pass.
    func testAStoreWithNoQuarantineSweepsThatSameOrphan() async throws {
        let store = makeStore()
        let body = try store.storeBody(Data("nothing points here".utf8))
        try age(store.bodyURL(for: body))

        XCTAssertFalse(store.isSweepSuspended)
        store.sweepOrphanedBodies()

        for _ in 0..<200 where store.bodyData(for: body) != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(store.bodyData(for: body))
    }

    /// The half of the promise that was not kept. The first mutation after the failed load cleared
    /// the in-memory blob, so the *next* launch — which reads a blob it can read, and therefore has
    /// no in-memory quarantine — swept every body the set-aside rules pointed at.
    func testASetAsideConfigurationKeepsItsBodiesAcrossRelaunches() throws {
        let first = makeStore()
        let body = try first.storeBody(Data("belongs to the unreadable configuration".utf8))
        try age(first.bodyURL(for: body))
        defaults.set(Data("not json at all".utf8), forKey: "Scyther.NetworkRules.Rules")

        // The launch that fails to read it, and then writes something of its own.
        makeStore().add(makeRule("written after the unreadable load"))

        // The launch after that, which reads a perfectly good blob.
        let later = makeStore()
        XCTAssertTrue(later.isSweepSuspended, "the quarantine outlives the launch that filled it")
        later.sweepOrphanedBodies()

        XCTAssertEqual(later.bodyData(for: body),
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

    /// `copyItem` preserves the source's modification date, so the grace period protected nothing:
    /// a copy of any document left alone for a minute — which is nearly every document anyone
    /// picks — was an orphan candidate the instant it was written, in the window before the
    /// override naming it is stored.
    func testACopyOfAnOldDocumentIsNotImmediatelyASweepCandidate() throws {
        let store = makeStore()
        let picked = try pickedFile(named: "users.json", contents: "[]")
        try age(picked)

        let path = try XCTUnwrap(store.storeFile(at: picked))

        let candidates = NetworkRuleStore.orphanCandidates(
            in: bodyDirectory,
            ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod
        )
        XCTAssertFalse(candidates.contains { $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent },
                       "the copy is as new as the copying, whatever the document's own date said")
    }

    /// The mirror case, which leaked rather than over-deleted: a document dated in the future
    /// produced a copy dated in the future, and `modified < cutoff` is never true of one — so that
    /// copy would never be reclaimed, however long it went unreferenced.
    ///
    /// Asserted on the date rather than on a sweep, because the defect is that no sweep at any
    /// future time would ever reach it, which no single sweep can demonstrate.
    func testACopyIsDatedWhenItWasCopiedAndNotWhenTheDocumentWas() throws {
        let store = makeStore()
        let picked = try pickedFile(named: "users.json", contents: "[]")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60 * 60 * 24)],
                                              ofItemAtPath: picked.path)

        let path = try XCTUnwrap(store.storeFile(at: picked))

        let copied = try XCTUnwrap(
            try URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        XCTAssertLessThanOrEqual(copied, Date().addingTimeInterval(1),
                                 "a copy dated in the future is one no sweep can ever reclaim")
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

    // MARK: - Bodies on disk

    private func mockRule(_ name: String, bodyID: UUID?) -> NetworkRule {
        var rule = makeRule(name)
        rule.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0))
        return rule
    }

    /// A body directory that cannot be created, because a file sits where its parent should be.
    private func unwritableStore() throws -> NetworkRuleStore {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("in the way".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        return NetworkRuleStore(defaults: defaults,
                                bodyDirectory: blocker.appendingPathComponent("bodies", isDirectory: true))
    }

    func testStoringABodyThatCannotBeWrittenThrows() throws {
        let store = try unwritableStore()
        XCTAssertThrowsError(try store.storeBody(Data("nowhere to put this".utf8)),
                             "returning an identifier for a write that failed strands every caller")
    }

    /// A stub pointing at bytes that are not on disk answers with the right status and an empty
    /// body, which surfaces in the host app as a decode error with nothing pointing back here.
    func testAnOverrideWhoseBodyCannotBeWrittenIsNotStored() throws {
        let store = try unwritableStore()

        let stored = store.add(.mock(name: "mock", matching: .path("/a"), returning: .json("{}")))

        XCTAssertFalse(stored)
        XCTAssertTrue(store.rules.isEmpty)
        XCTAssertEqual(store.lastFailure, .bodyNotWritten)
    }

    /// Building the value used to write a file through the *shared* store, so a test with an
    /// injected directory wrote into the real Application Support container.
    func testAJSONMockWritesNothingUntilTheRuleHoldingItIsStored() throws {
        let response = MockResponse.json(#"{"a":1}"#)
        XCTAssertNil(response.bodyID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bodyDirectory.path),
                       "building the value touches no disk at all")

        let store = makeStore()
        XCTAssertTrue(store.add(.mock(name: "mock", matching: .path("/a"), returning: response)))

        guard case .mock(let mock) = store.rules.first?.actions.stub, let bodyID = mock.bodyID else {
            return XCTFail("the store fills the body identifier in")
        }
        XCTAssertNil(mock.pendingBody, "and clears the bytes it has written")
        XCTAssertEqual(store.bodyData(for: bodyID), Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(store.bodyURL(for: bodyID).deletingLastPathComponent().standardizedFileURL,
                       bodyDirectory.standardizedFileURL,
                       "into the injected directory, not the shared one")
    }

    /// The documented API encourages building one `MockResponse` and reusing it, which shares one
    /// body identifier between overrides.
    func testDeletingOneOverrideLeavesABodyAnotherOnePointsAt() throws {
        let store = makeStore()
        let bodyID = try store.storeBody(Data("shared".utf8))
        let first = mockRule("first", bodyID: bodyID)
        let second = mockRule("second", bodyID: bodyID)
        store.add(first)
        store.add(second)

        store.remove(id: first.id)
        XCTAssertEqual(store.bodyData(for: bodyID), Data("shared".utf8),
                       "the surviving override would otherwise serve an empty body forever")

        store.remove(id: second.id)
        XCTAssertNil(store.bodyData(for: bodyID), "and the last reference going takes it with it")
    }

    func testRemovingEverythingReclaimsASharedBody() throws {
        let store = makeStore()
        let bodyID = try store.storeBody(Data("shared".utf8))
        store.add(mockRule("first", bodyID: bodyID))
        store.addTransient(mockRule("second", bodyID: bodyID))

        store.removeAll()

        XCTAssertNil(store.bodyData(for: bodyID))
    }

    /// Re-adding a stable-identifier override in a long-lived process wrote a fresh body every
    /// time and orphaned the previous one, with nothing reclaiming them until the next launch.
    func testReplacingAnOverrideReclaimsTheBodyItNoLongerPointsAt() throws {
        let store = makeStore()
        let first = try store.storeBody(Data("first".utf8))
        var rule = mockRule("stable", bodyID: first)
        store.add(rule)

        let second = try store.storeBody(Data("second".utf8))
        rule.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: second, delay: 0))
        store.add(rule)

        XCTAssertNil(store.bodyData(for: first))
        XCTAssertEqual(store.bodyData(for: second), Data("second".utf8))
        XCTAssertEqual(store.rules.count, 1)
    }

    func testUpdatingAnOverrideReclaimsTheBodyItNoLongerPointsAt() throws {
        let store = makeStore()
        let first = try store.storeBody(Data("first".utf8))
        var rule = mockRule("edited", bodyID: first)
        store.add(rule)

        let second = try store.storeBody(Data("second".utf8))
        rule.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: second, delay: 0))
        store.update(rule)

        XCTAssertNil(store.bodyData(for: first))
        XCTAssertEqual(store.bodyData(for: second), Data("second".utf8))
    }

    func testReplacingAnOverrideKeepsABodyAnotherOneAlsoPointsAt() throws {
        let store = makeStore()
        let shared = try store.storeBody(Data("shared".utf8))
        var rule = mockRule("stable", bodyID: shared)
        store.add(rule)
        store.add(mockRule("other", bodyID: shared))

        rule.actions.stub = .mock(MockResponse(statusCode: 204, headers: [:], bodyID: nil, delay: 0))
        store.add(rule)

        XCTAssertEqual(store.bodyData(for: shared), Data("shared".utf8))
    }

    /// A directory that already exists — which is every launch after the first — was never marked,
    /// and `Application Support` is backed up by default.
    func testAnExistingBodyDirectoryIsStillExcludedFromBackup() throws {
        try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        let store = makeStore()

        try store.storeBody(Data("body".utf8))

        let values = try bodyDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - One identifier, one list

    /// The same identifier in both lists made `remove(id:)` delete the persisted copy and its body
    /// while the transient copy carried on matching and serving an empty one.
    func testRegisteringATransientRuleMovesAPersistedIdentifierAcross() throws {
        let store = makeStore()
        let bodyID = try store.storeBody(Data("persisted".utf8))
        var persisted = mockRule("persisted", bodyID: bodyID)
        let id = persisted.id
        store.add(persisted)

        persisted.name = "transient"
        persisted.actions.stub = .mock(MockResponse(statusCode: 204, headers: [:], bodyID: nil, delay: 0))
        store.addTransient(persisted)

        XCTAssertTrue(store.rules.isEmpty, "an identifier lives in exactly one list")
        XCTAssertEqual(store.transientRules.map(\.name), ["transient"])
        XCTAssertTrue(makeStore().rules.isEmpty, "and the move is persisted")
        XCTAssertNil(store.bodyData(for: bodyID), "the replaced copy's body goes with it")

        store.remove(id: id)
        XCTAssertTrue(store.transientRules.isEmpty)
    }

    func testAddingAPersistedRuleMovesATransientIdentifierAcross() {
        let store = makeStore()
        var rule = makeRule("registered in code")
        store.addTransient(rule)

        rule.name = "promoted"
        store.add(rule)

        XCTAssertTrue(store.transientRules.isEmpty)
        XCTAssertEqual(store.rules.map(\.name), ["promoted"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["promoted"])
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
        let referenced = try store.storeBody(Data("still in use".utf8))
        let orphan = try store.storeBody(Data("nothing points here".utf8))
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
    func testTheSweepLeavesAFreshlyWrittenBodyAlone() throws {
        let store = makeStore()
        let justWritten = try store.storeBody(Data("about to be referenced".utf8))

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertEqual(store.bodyData(for: justWritten), Data("about to be referenced".utf8))
    }

    /// The directory sits inside the host app's container. Anything not named after a UUID was
    /// not written by the store, and deleting it would be far worse than leaving it.
    func testTheSweepLeavesFilesItDidNotName() throws {
        let store = makeStore()
        try store.storeBody(Data("a real body".utf8))
        let stranger = bodyDirectory.appendingPathComponent("something-else.txt")
        try Data("not ours".utf8).write(to: stranger)
        try age(stranger)

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path))
    }

    /// `.atomic` stages through a file Foundation names, which an interrupted write leaves behind
    /// under a name the sweep cannot match. Scyther names its own staging file so it can.
    func testTheSweepReclaimsTheDebrisOfAnInterruptedWrite() throws {
        let store = makeStore()
        let live = try store.storeBody(Data("live".utf8))
        let debris = NetworkRuleStore.stagingURL(for: live, in: bodyDirectory)
        try Data("half written".utf8).write(to: debris)
        try age(debris)

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [live],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertFalse(FileManager.default.fileExists(atPath: debris.path),
                       "a body that finished writing is not named that way, so this is debris")
        XCTAssertEqual(store.bodyData(for: live), Data("live".utf8))
    }

    /// A write in flight stages under exactly that name, so the grace period covers it.
    func testTheSweepLeavesFreshStagingDebrisAlone() throws {
        let debris = NetworkRuleStore.stagingURL(for: UUID(), in: bodyDirectory)
        try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        try Data("being written right now".utf8).write(to: debris)

        NetworkRuleStore.sweepBodies(in: bodyDirectory,
                                     keeping: [],
                                     ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod)

        XCTAssertTrue(FileManager.default.fileExists(atPath: debris.path))
    }

    /// The enumeration runs off the main actor and can take a while; deciding against a reference
    /// set captured before it began made the sweep a race an override registered seconds after
    /// `Scyther.start()` could lose.
    /// The second body is what makes the assertion about the file that survives mean anything: it
    /// is deleted by the very same call, so waiting for it to go proves the deletion pass ran and
    /// spared the other one, rather than proving only that a fixed sleep was long enough to
    /// observe nothing having happened yet.
    func testACandidateReferencedBetweenTheWalkAndTheDeleteSurvives() async throws {
        let store = makeStore()
        let body = try store.storeBody(Data("about to be referenced".utf8))
        let orphan = try store.storeBody(Data("nothing will point here".utf8))
        try age(store.bodyURL(for: body))
        try age(store.bodyURL(for: orphan))

        // What the detached walk sees: nothing references either of them yet.
        let candidates = NetworkRuleStore.orphanCandidates(
            in: bodyDirectory,
            ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod
        )
        XCTAssertTrue(candidates.contains { $0.bodyID == body })
        XCTAssertTrue(candidates.contains { $0.bodyID == orphan })

        // The override arrives while the sweep is still walking.
        store.add(mockRule("registered mid-sweep", bodyID: body))
        store.deleteOrphans(candidates)

        for _ in 0..<200 where store.bodyData(for: orphan) != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(store.bodyData(for: orphan), "the deletion pass has run")
        XCTAssertEqual(store.bodyData(for: body), Data("about to be referenced".utf8))
    }

    func testDeletingOrphansStillReclaimsWhatNothingReferences() async throws {
        let store = makeStore()
        let orphan = try store.storeBody(Data("orphan".utf8))
        try age(store.bodyURL(for: orphan))

        let candidates = NetworkRuleStore.orphanCandidates(
            in: bodyDirectory,
            ignoringFilesNewerThan: NetworkRuleStore.bodySweepGracePeriod
        )
        store.deleteOrphans(candidates)

        for _ in 0..<200 where store.bodyData(for: orphan) != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(store.bodyData(for: orphan))
    }

    func testSweepingTheStoreKeepsAFileAMapLocalRulePointsAt() async throws {
        let store = makeStore()
        let path = try XCTUnwrap(store.storeFile(at: try pickedFile(named: "users.json", contents: "[]")))
        var rule = makeRule("map local")
        rule.actions.stub = .mapLocal(MapLocalFile(relativePath: path, fileName: "users.json"))
        store.add(rule)

        let orphan = try store.storeBody(Data("orphan".utf8))
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

        let persistedBody = try store.storeBody(Data("persisted".utf8))
        var persisted = makeRule("persisted")
        persisted.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: persistedBody, delay: 0))
        store.add(persisted)

        let transientBody = try store.storeBody(Data("transient".utf8))
        var transient = makeRule("transient")
        transient.actions.stub = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: transientBody, delay: 0))
        store.addTransient(transient)

        let orphan = try store.storeBody(Data("orphan".utf8))
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
        try store.storeBody(Data("body".utf8))

        let values = try bodyDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - Snapshot publication

    /// The snapshot is the only thing the interceptor can read, so a mutation that changes the
    /// rules without republishing leaves live traffic being matched against the previous set. Each
    /// of these fails if `publish()` is deleted from the mutation it covers.
    private var snapshotNames: [String] {
        NetworkRuleSnapshot.current.rules.map(\.name)
    }

    func testAddingSeveralRulesAtOncePublishesThem() {
        let store = makeStore()
        store.add(contentsOf: [makeRule("first"), makeRule("second")])
        XCTAssertEqual(store.rules.map(\.name), ["first", "second"])
        XCTAssertEqual(snapshotNames, ["first", "second"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["first", "second"])
    }

    func testAddingNoRulesAtAllChangesNothing() {
        let store = makeStore()
        store.add(makeRule("already here"))
        XCTAssertEqual(store.add(contentsOf: []), 0)
        XCTAssertEqual(snapshotNames, ["already here"])
    }

    func testMovingARulePublishesTheNewPrecedence() {
        let store = makeStore()
        store.add(makeRule("first"))
        store.add(makeRule("second"))
        store.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(snapshotNames, ["second", "first"])
    }

    func testUpdatingARulePublishesTheEdit() {
        let store = makeStore()
        var rule = makeRule("before")
        store.add(rule)
        rule.name = "after"
        store.update(rule)
        XCTAssertEqual(snapshotNames, ["after"])
    }

    func testUpdatingATransientRulePublishesTheEdit() {
        let store = makeStore()
        var rule = makeRule("before")
        store.addTransient(rule)
        rule.name = "after"
        store.update(rule)
        XCTAssertEqual(snapshotNames, ["after"])
    }

    func testRemovingARulePublishesItsAbsence() {
        let store = makeStore()
        let rule = makeRule("doomed")
        store.add(rule)
        store.addTransient(makeRule("kept"))
        store.remove(id: rule.id)
        XCTAssertEqual(snapshotNames, ["kept"])
    }

    func testRemovingATransientRulePublishesItsAbsence() {
        let store = makeStore()
        let rule = makeRule("doomed")
        store.addTransient(rule)
        store.remove(id: rule.id)
        XCTAssertTrue(snapshotNames.isEmpty)
    }

    func testRemovingEverythingPublishesAnEmptyRuleSet() {
        let store = makeStore()
        store.add(makeRule("persisted"))
        store.addTransient(makeRule("transient"))
        store.removeAll()
        XCTAssertTrue(store.rules.isEmpty)
        XCTAssertTrue(store.transientRules.isEmpty)
        XCTAssertTrue(snapshotNames.isEmpty)
        XCTAssertTrue(makeStore().rules.isEmpty)
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

    /// Asserting the count alone would pass if every constructor returned the same kind, which is
    /// the mistake worth catching: the four are one-line wrappers that differ only in the action
    /// they fill in.
    func testEveryRuleKindCanBeBuiltThroughThePublicAPI() {
        let store = makeStore()
        store.add(.mock(name: "m", matching: .path("/a"), returning: .json("{}")))
        store.add(.headers(name: "h", matching: .path("/b"), set: ["X": "1"], remove: []))
        store.add(.condition(name: "c", matching: .path("/c"), NetworkCondition(latency: 1)))
        store.add(.mapLocal(name: "l", matching: .path("/d"), serving: MapLocalFile(relativePath: "/tmp/x.json")))

        XCTAssertEqual(store.rules.map(\.name), ["m", "h", "c", "l"])

        guard case .mock = store.rules[0].actions.stub else { return XCTFail("mock built the wrong action") }
        XCTAssertNil(store.rules[0].actions.rewriteHeaders)
        XCTAssertNil(store.rules[0].actions.condition)

        XCTAssertEqual(store.rules[1].actions.rewriteHeaders?.set, ["X": "1"])
        XCTAssertNil(store.rules[1].actions.stub)

        XCTAssertEqual(store.rules[2].actions.condition?.latency, 1)
        XCTAssertNil(store.rules[2].actions.stub)

        guard case .mapLocal(let file) = store.rules[3].actions.stub else {
            return XCTFail("mapLocal built the wrong action")
        }
        XCTAssertEqual(file.relativePath, "/tmp/x.json")
        XCTAssertNil(store.rules[3].actions.condition)
    }
}


/// The public facade writes nothing while Scyther is not running.
///
/// `Scyther.network.rules` is what the documentation tells a host app to call from
/// `didFinishLaunching`, and `start()` refuses to run on an App Store build. Every mutator used to
/// forward to the store regardless, so following our own guide created a directory and wrote to
/// preferences in a user's container for a feature that never runs — and nothing reclaimed it,
/// because the sweep is only reachable from `start()`.
@MainActor
final class NetworkRulesFacadeTests: XCTestCase {

    /// Whether the process was already started when this test began.
    private var wasStarted = false

    override func setUp() async throws {
        wasStarted = Scyther.isStarted
        Scyther._started = false
    }

    override func tearDown() async throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        Scyther._started = wasStarted
    }

    private func rule(_ name: String) -> NetworkRule {
        NetworkRule(name: name,
                    match: .host("facade.invalid"),
                    actions: NetworkRuleActions(stub: .mock(.json("{}"))))
    }

    func testMutatorsWriteNothingWhileScytherIsNotRunning() {
        let before = NetworkRuleStore.shared.rules

        XCTAssertFalse(Scyther.network.rules.add(rule("persisted")))
        XCTAssertFalse(Scyther.network.rules.addTransient(rule("transient")))
        XCTAssertFalse(Scyther.network.rules.update(rule("edited")))
        Scyther.network.rules.isEnabled = false

        XCTAssertEqual(NetworkRuleStore.shared.rules, before)
        XCTAssertTrue(NetworkRuleStore.shared.transientRules.isEmpty)
        XCTAssertTrue(NetworkRuleStore.shared.isEnabled, "the master switch is untouched too")
    }

    func testReadersHandBackNothingWhileScytherIsNotRunning() {
        XCTAssertTrue(Scyther.network.rules.all.isEmpty)
        XCTAssertTrue(Scyther.network.rules.transient.isEmpty)
        XCTAssertFalse(Scyther.network.rules.isEnabled,
                       "nothing is being applied, whatever the persisted switch says")
    }

    func testTheFacadeWorksNormallyOnceScytherIsRunning() {
        Scyther._started = true
        let added = rule("registered in code")
        defer { Scyther.network.rules.remove(id: added.id) }

        XCTAssertTrue(Scyther.network.rules.add(added))
        XCTAssertTrue(Scyther.network.rules.all.contains { $0.id == added.id })
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
