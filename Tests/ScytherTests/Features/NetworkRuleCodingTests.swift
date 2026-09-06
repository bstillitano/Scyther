//
//  NetworkRuleCodingTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Guards the on-disk format of an override.
///
/// An override that fails to decode is dropped by ``NetworkRuleStore``, so a format change that
/// is not migrated costs the developer every override they had configured. These tests pin both
/// shapes: the composable `actions` object written now, and the single `action` key written
/// before actions could compose.
final class NetworkRuleCodingTests: XCTestCase {

    /// Restores the process-global snapshot this suite published to.
    ///
    /// Constructing a `NetworkRuleStore` publishes its rules and its body directory to
    /// `NetworkRuleSnapshot`, which the interceptor tests read. Leaving a legacy decoding
    /// fixture's rules — and a body directory under `/tmp` that nothing wrote to — standing there
    /// makes those tests depend on what ran before them.
    override func tearDown() {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
    }

    private let identifier = UUID(uuidString: "6F0B0C3E-4C1E-4E3D-9C0B-0F5E7A9D2B41")!

    /// One rule persisted in the shape that preceded composable actions.
    ///
    /// The `_0` is not a typo: the compiler synthesised that positional key for the enum's
    /// associated value, and every override written before this change carries it.
    private func legacyRule(action: String, id: UUID? = nil, name: String = "Empty cart") -> String {
        """
        {
          "id": "\(id ?? identifier)",
          "name": "\(name)",
          "isEnabled": true,
          "match": { "methods": ["GET"], "query": {}, "path": { "kind": "exact", "value": "/api/cart" } },
          "action": \(action)
        }
        """
    }

    private func decode(_ json: String) throws -> NetworkRule {
        try JSONDecoder().decode(NetworkRule.self, from: Data(json.utf8))
    }

    // MARK: - Reading what is already on disk

    func testALegacyMockRuleDecodesIntoAStub() throws {
        let json = legacyRule(action: """
        { "mock": { "_0": { "statusCode": 418, "headers": { "X-Mock": "yes" }, "delay": 1.5 } } }
        """)
        let rule = try decode(json)

        XCTAssertEqual(rule.id, identifier)
        XCTAssertEqual(rule.name, "Empty cart")
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.match.path, NetworkRulePattern(kind: .exact, value: "/api/cart"))
        guard case .mock(let mock) = try XCTUnwrap(rule.actions.stub) else {
            return XCTFail("expected a mock stub")
        }
        XCTAssertEqual(mock.statusCode, 418)
        XCTAssertEqual(mock.headers, ["X-Mock": "yes"])
        XCTAssertEqual(mock.delay, 1.5)
        XCTAssertNil(rule.actions.rewriteHeaders)
        XCTAssertNil(rule.actions.condition)
    }

    func testALegacyMockRuleKeepsItsBodyIdentifier() throws {
        let bodyID = UUID()
        let json = legacyRule(action: """
        { "mock": { "_0": { "statusCode": 200, "headers": {}, "delay": 0, "bodyID": "\(bodyID)" } } }
        """)
        guard case .mock(let mock) = try XCTUnwrap(try decode(json).actions.stub) else {
            return XCTFail("expected a mock stub")
        }
        XCTAssertEqual(mock.bodyID, bodyID, "losing the body identifier would serve an empty mock")
    }

    func testALegacyMapLocalRuleDecodesIntoAStub() throws {
        let json = legacyRule(action: """
        { "mapLocal": { "_0": { "path": "/tmp/users.json", "statusCode": 200,
          "contentType": "application/json", "delay": 0 } } }
        """)
        guard case .mapLocal(let file) = try XCTUnwrap(try decode(json).actions.stub) else {
            return XCTFail("expected a map local stub")
        }
        XCTAssertEqual(file.path, "/tmp/users.json")
        XCTAssertEqual(file.contentType, "application/json")
        XCTAssertNil(file.fileName, "a rule written before the field existed simply has no name")
    }

    /// W33: the field was called `relativePath` and held an absolute path, justified in its own
    /// documentation as compatibility with rules already persisted under it. No released version
    /// ever persisted one, so the only documents carrying the old key came from intermediate
    /// commits of this branch — which are read for the developers who ran them.
    func testAMapLocalFileWrittenUnderTheOldPathKeyStillDecodes() throws {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "stub": {
            "mapLocal": { "relativePath": "/tmp/users.json", "statusCode": 200, "delay": 0 }
          } } }
        """
        guard case .mapLocal(let file) = try XCTUnwrap(try decode(json).actions.stub) else {
            return XCTFail("expected a map local stub")
        }
        XCTAssertEqual(file.path, "/tmp/users.json")
    }

    func testTheOldPathKeyIsNeverWritten() throws {
        let file = MapLocalFile(path: "/tmp/users.json", statusCode: 200, delay: 0)
        let data = try JSONEncoder().encode(file)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["relativePath"], "the old name was never true of the value it held")
        XCTAssertEqual(object["path"] as? String, "/tmp/users.json")
    }

    func testAMapLocalFileCarryingNeitherPathKeyFailsToDecode() {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "stub": { "mapLocal": { "statusCode": 200, "delay": 0 } } } }
        """
        XCTAssertThrowsError(try decode(json), "a map local override with no file serves nothing")
    }

    func testALegacyRewriteRuleDecodesIntoARewrite() throws {
        let json = legacyRule(action: """
        { "rewriteHeaders": { "_0": { "set": { "Authorization": "Bearer test" }, "remove": ["X-Drop"] } } }
        """)
        let rule = try decode(json)
        XCTAssertEqual(rule.actions.rewriteHeaders?.set, ["Authorization": "Bearer test"])
        XCTAssertEqual(rule.actions.rewriteHeaders?.remove, ["X-Drop"])
        XCTAssertNil(rule.actions.stub)
        XCTAssertNil(rule.actions.condition)
    }

    func testALegacyConditionRuleDecodesIntoACondition() throws {
        let json = legacyRule(action: """
        { "condition": { "_0": { "latency": 2, "bandwidthKBps": 64, "failureRate": 0.25,
          "failureCode": -1009 } } }
        """)
        let condition = try XCTUnwrap(try decode(json).actions.condition)
        XCTAssertEqual(condition.latency, 2)
        XCTAssertEqual(condition.bandwidthKBps, 64)
        XCTAssertEqual(condition.failureRate, 0.25)
        XCTAssertEqual(condition.failureCode, -1009)
        XCTAssertNil(try decode(json).actions.stub)
    }

    func testARuleCarryingNeitherShapeFailsToDecode() {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true, "match": { "methods": [], "query": {} } }
        """
        XCTAssertThrowsError(try decode(json), "a rule that does nothing must be dropped, not stored")
    }

    func testALegacyActionWithNoRecognisableCaseFailsToDecode() {
        let json = legacyRule(action: #"{ "somethingNewer": { "_0": { } } }"#)
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: - The current shape

    func testTheCurrentShapeRoundTrips() throws {
        let rule = NetworkRule(
            id: identifier,
            name: "Slow, rewritten mock",
            isEnabled: false,
            match: .host("api.example.com", path: "/v1/*", methods: ["POST"]),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 201, headers: ["A": "1"], bodyID: UUID(), delay: 0.5)),
                rewriteHeaders: NetworkHeaderRewrite(set: ["B": "2"], remove: ["C"]),
                condition: NetworkCondition(latency: 1, bandwidthKBps: 32, failureRate: 0.5)
            )
        )
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(NetworkRule.self, from: data), rule)
    }

    /// The persisted format must not depend on the compiler's positional key for an enum's
    /// associated value, which is what `_0` is.
    func testAStubIsPersistedWithoutAPositionalKey() throws {
        let rule = NetworkRule(id: identifier,
                               name: "cart",
                               match: .path("/api/cart"),
                               actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 204))))
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(rule), encoding: .utf8))
        XCTAssertFalse(json.contains("_0"))
        XCTAssertTrue(json.contains("\"mock\""))
    }

    /// Pins every persisted key name. Each type spells its `CodingKeys` out, so this is what
    /// would catch a rename — or a new property — quietly changing the on-disk format.
    func testEveryPersistedFieldKeepsItsKeyName() throws {
        let rule = NetworkRule(
            id: identifier,
            name: "everything",
            isEnabled: true,
            match: NetworkRuleMatch(methods: ["GET"],
                                    host: NetworkRulePattern(kind: .wildcard, value: "*.example.com"),
                                    path: NetworkRulePattern(kind: .exact, value: "/v1"),
                                    query: ["a": "1"]),
            actions: NetworkRuleActions(
                stub: .mock(MockResponse(statusCode: 200, headers: ["A": "1"], bodyID: UUID(), delay: 1)),
                rewriteHeaders: NetworkHeaderRewrite(set: ["B": "2"], remove: ["C"]),
                condition: NetworkCondition(latency: 1, bandwidthKBps: 8, failureRate: 0.5)
            )
        )
        let data = try JSONEncoder().encode(rule)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["id", "name", "isEnabled", "match", "actions"])

        let match = try XCTUnwrap(object["match"] as? [String: Any])
        XCTAssertEqual(Set(match.keys), ["methods", "host", "path", "query"])
        XCTAssertEqual(Set(try XCTUnwrap(match["host"] as? [String: Any]).keys), ["kind", "value"])

        let actions = try XCTUnwrap(object["actions"] as? [String: Any])
        XCTAssertEqual(Set(actions.keys), ["stub", "rewriteHeaders", "condition"])

        let stub = try XCTUnwrap(actions["stub"] as? [String: Any])
        XCTAssertEqual(Set(stub.keys), ["mock"])
        XCTAssertEqual(Set(try XCTUnwrap(stub["mock"] as? [String: Any]).keys),
                       ["statusCode", "headers", "bodyID", "delay"])

        XCTAssertEqual(Set(try XCTUnwrap(actions["rewriteHeaders"] as? [String: Any]).keys),
                       ["set", "remove"])
        XCTAssertEqual(Set(try XCTUnwrap(actions["condition"] as? [String: Any]).keys),
                       ["latency", "bandwidthKBps", "failureRate", "failureCode"])
    }

    /// A map-local stub's keys, which the mock case above cannot reach.
    func testAMapLocalStubKeepsItsKeyNames() throws {
        let rule = NetworkRule(id: identifier,
                               name: "file",
                               match: .path("/v1"),
                               actions: NetworkRuleActions(stub: .mapLocal(
                                MapLocalFile(path: "/tmp/x.json",
                                             fileName: "x.json",
                                             statusCode: 200,
                                             contentType: "application/json",
                                             delay: 0)
                               )))
        let data = try JSONEncoder().encode(rule)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stub = try XCTUnwrap((object["actions"] as? [String: Any])?["stub"] as? [String: Any])
        XCTAssertEqual(Set(stub.keys), ["mapLocal"])
        XCTAssertEqual(Set(try XCTUnwrap(stub["mapLocal"] as? [String: Any]).keys),
                       ["path", "fileName", "statusCode", "contentType", "delay"])
    }

    func testTheLegacyKeyIsNeverWritten() throws {
        let rule = NetworkRule(id: identifier,
                               name: "cart",
                               match: .path("/api/cart"),
                               actions: NetworkRuleActions(condition: NetworkCondition(latency: 1)))
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(rule), encoding: .utf8))
        XCTAssertTrue(json.contains("\"actions\""))
        XCTAssertFalse(json.contains("\"action\":"))
    }

    func testTheCurrentShapeWinsWhenBothKeysArePresent() throws {
        let json = """
        {
          "id": "\(identifier)", "name": "both", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "condition": { "latency": 9, "failureRate": 0, "failureCode": -1009 } },
          "action": { "mock": { "_0": { "statusCode": 200, "headers": {}, "delay": 0 } } }
        }
        """
        let rule = try decode(json)
        XCTAssertEqual(rule.actions.condition?.latency, 9)
        XCTAssertNil(rule.actions.stub, "the legacy key is a fallback, never a supplement")
    }

    /// The sibling of ``testARuleCarryingNeitherShapeFailsToDecode()``, and it has to agree with
    /// it: an override that does nothing is dropped rather than stored, whichever shape it arrives
    /// in. The synthesised initialiser used to decode this happily, which is how a rule that
    /// matched live traffic and left it alone got onto the list.
    func testAnEmptyActionsObjectFailsToDecode() {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true,
          "match": { "methods": [], "query": {} }, "actions": {} }
        """
        XCTAssertThrowsError(try decode(json), "a rule that does nothing must be dropped, not stored")
    }

    /// The case the defect was actually about: every property went through `decodeIfPresent`, so
    /// an `actions` object naming only a facet a later release added decoded as an empty one — an
    /// override that matches live traffic, does nothing, and cannot be explained.
    func testActionsCarryingOnlyUnrecognisedKeysFailToDecode() {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "throttleProfile": { "shape": "burst" } } }
        """
        XCTAssertThrowsError(try decode(json), "a facet this version has no case for is not nothing")
    }

    /// A newer release writing a fourth facet keeps the legacy key beside it for exactly this
    /// reason. Dropping a valid action because the object above it was unreadable would cost the
    /// override that the compatibility key was written to save.
    func testAnUnreadableActionsObjectFallsBackToTheLegacyKey() throws {
        let json = """
        {
          "id": "\(identifier)", "name": "from the future", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "throttleProfile": { "shape": "burst" } },
          "action": { "mock": { "_0": { "statusCode": 204, "headers": {}, "delay": 0 } } }
        }
        """
        guard case .mock(let mock) = try XCTUnwrap(try decode(json).actions.stub) else {
            return XCTFail("expected the legacy mock to be recovered")
        }
        XCTAssertEqual(mock.statusCode, 204)
    }

    /// JSON has no idea it is looking at an enum, so the exclusivity ``NetworkRuleStub`` claims
    /// structurally has to be enforced on the way in. Keeping whichever key was read first would
    /// mean an override answering from a mock this launch and from a file the next.
    func testAStubCarryingBothAMockAndAMapLocalFailsToDecode() {
        let json = """
        { "id": "\(identifier)", "name": "x", "isEnabled": true,
          "match": { "methods": [], "query": {} },
          "actions": { "stub": {
            "mock": { "statusCode": 200, "headers": {}, "delay": 0 },
            "mapLocal": { "path": "/tmp/x.json", "statusCode": 200, "delay": 0 }
          } } }
        """
        XCTAssertThrowsError(try decode(json), "a stub answers from one place or the other")
    }

    // MARK: - Through the store

    /// The end that actually matters: a `UserDefaults` blob written by the previous version is
    /// loaded whole, rather than costing the developer every override they had.
    @MainActor
    func testTheStoreLoadsALegacyBlobWithoutLosingAnything() throws {
        let suiteName = "NetworkRuleCodingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let blob = """
        [
          \(legacyRule(action: #"{ "mock": { "_0": { "statusCode": 200, "headers": {}, "delay": 0 } } }"#,
                       id: UUID(), name: "mock")),
          \(legacyRule(action: #"{ "rewriteHeaders": { "_0": { "set": {}, "remove": ["X"] } } }"#,
                       id: UUID(), name: "rewrite")),
          \(legacyRule(action: #"{ "condition": { "_0": { "latency": 3, "failureRate": 0, "failureCode": -1009 } } }"#,
                       id: UUID(), name: "condition"))
        ]
        """
        defaults.set(Data(blob.utf8), forKey: "Scyther.NetworkRules.Rules")

        let store = NetworkRuleStore(defaults: defaults,
                                     bodyDirectory: FileManager.default.temporaryDirectory
                                        .appendingPathComponent(UUID().uuidString, isDirectory: true))
        XCTAssertEqual(store.rules.map(\.name), ["mock", "rewrite", "condition"])
        XCTAssertNotNil(store.rules[0].actions.stub)
        XCTAssertEqual(store.rules[1].actions.rewriteHeaders?.remove, ["X"])
        XCTAssertEqual(store.rules[2].actions.condition?.latency, 3)
    }

    /// One unreadable override still costs that override alone.
    @MainActor
    func testAnUnreadableRuleDoesNotTakeItsNeighboursWithIt() throws {
        let suiteName = "NetworkRuleCodingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let blob = """
        [
          \(legacyRule(action: #"{ "mock": { "_0": { "statusCode": 200, "headers": {}, "delay": 0 } } }"#,
                       id: UUID(), name: "before")),
          { "id": "\(UUID())", "name": "broken", "isEnabled": true },
          \(legacyRule(action: #"{ "condition": { "_0": { "latency": 1, "failureRate": 0, "failureCode": -1009 } } }"#,
                       id: UUID(), name: "after"))
        ]
        """
        defaults.set(Data(blob.utf8), forKey: "Scyther.NetworkRules.Rules")

        let store = NetworkRuleStore(defaults: defaults,
                                     bodyDirectory: FileManager.default.temporaryDirectory
                                        .appendingPathComponent(UUID().uuidString, isDirectory: true))
        XCTAssertEqual(store.rules.map(\.name), ["before", "after"])
    }

    /// A store that read a legacy blob writes the new shape back, so the migration happens once.
    @MainActor
    func testSavingAfterALegacyLoadWritesTheCurrentShape() throws {
        let suiteName = "NetworkRuleCodingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let blob = "[\(legacyRule(action: #"{ "mock": { "_0": { "statusCode": 200, "headers": {}, "delay": 0 } } }"#))]"
        defaults.set(Data(blob.utf8), forKey: "Scyther.NetworkRules.Rules")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,
                                                                                     isDirectory: true)
        let store = NetworkRuleStore(defaults: defaults, bodyDirectory: directory)
        var rule = try XCTUnwrap(store.rules.first)
        rule.name = "renamed"
        store.update(rule)

        let written = try XCTUnwrap(defaults.data(forKey: "Scyther.NetworkRules.Rules"))
        let text = try XCTUnwrap(String(data: written, encoding: .utf8))
        XCTAssertTrue(text.contains("\"actions\""))
        XCTAssertFalse(text.contains("_0"))

        let reloaded = NetworkRuleStore(defaults: defaults, bodyDirectory: directory)
        XCTAssertEqual(reloaded.rules.map(\.name), ["renamed"])
        XCTAssertNotNil(reloaded.rules.first?.actions.stub)
    }
}
