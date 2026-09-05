//
//  NetworkRuleEditorViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRuleEditorViewModelTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var bodyDirectory: URL!
    nonisolated(unsafe) private var createdStore: NetworkRuleStore?

    /// A store isolated to this test's own suite and body directory.
    ///
    /// Built on first use rather than in `setUpWithError()`, which is nonisolated and so cannot
    /// construct a main-actor type.
    private var store: NetworkRuleStore {
        if let createdStore { return createdStore }
        let store = NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
        createdStore = store
        return store
    }

    override func setUpWithError() throws {
        suiteName = "NetworkRuleEditorTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRuleEditorBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    func testANewRuleIsInvalidUntilItIsNamedAndPointedAtAnEndpoint() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertFalse(viewModel.isValid)
        viewModel.draft.name = "Empty cart"
        XCTAssertFalse(viewModel.isValid, "a name alone does not say which requests the override is for")
        viewModel.draft.match.path = .pattern("/api/cart")
        XCTAssertTrue(viewModel.isValid)
    }

    /// Two taps — name it, save it — used to produce an enabled override mocking every `GET` the
    /// app makes, because the draft was seeded with a method and a method counted as a facet.
    func testAMethodsOnlyDraftIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Every GET"
        viewModel.draft.match = NetworkRuleMatch(methods: ["GET"], host: nil, path: nil, query: [:])
        XCTAssertFalse(
            viewModel.isValid,
            "an override matching every GET in the app is the same hazard as one matching everything"
        )

        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    func testANewRuleStartsWithoutAMethodSeeded() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertTrue(viewModel.draft.match.methods.isEmpty, "a new override matches any method")
    }

    func testARuleMatchingNothingIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.draft.match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: [:])
        XCTAssertFalse(
            viewModel.isValid,
            "a rule with no facets would match every request in the app and is almost certainly a mistake"
        )
    }

    func testSavingANewRuleAddsItToTheStore() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Empty cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["Empty cart"])
    }

    // MARK: - Methods

    func testMethodsSummaryReadsAsAnyMethodWhenNothingIsSelected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = []
        XCTAssertEqual(viewModel.methodsSummary, localized("Any method"))
    }

    func testMethodsSummaryListsSelectionInTheOrderTheChecklistShowsIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = ["DELETE", "GET", "POST"]
        XCTAssertEqual(
            viewModel.methodsSummary,
            "GET, POST, DELETE",
            "the summary should follow availableMethods, not the set's own hashing order"
        )
    }

    func testMethodsSummaryKeepsAMethodTheChecklistDoesNotOffer() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = ["GET", "TRACE"]
        XCTAssertEqual(
            viewModel.methodsSummary,
            "GET, TRACE",
            "a method a HAR import produced must not disappear from the summary"
        )
    }

    func testTogglingAMethodAddsAndRemovesIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = []
        viewModel.toggle(method: "POST")
        XCTAssertTrue(viewModel.isSelected(method: "POST"))
        viewModel.toggle(method: "POST")
        XCTAssertFalse(viewModel.isSelected(method: "POST"))
        XCTAssertEqual(viewModel.methodsSummary, localized("Any method"))
    }

    // MARK: - Saving

    func testAnInvalidDraftIsNotWrittenEvenIfSaveIsCalled() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "   "
        viewModel.save()
        XCTAssertTrue(
            store.rules.isEmpty,
            "the view disables Save, but the validity rule belongs to the view model, not the button"
        )
    }

    func testADraftMatchingNothingIsNotWrittenEvenIfSaveIsCalled() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.draft.match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: [:])
        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    // MARK: - Mock bodies

    /// A saved mock rule whose body is already on disk, and the identifier it points at.
    private func savedMockRule(body: String) throws -> (rule: NetworkRule, bodyID: UUID) {
        let bodyID = try store.storeBody(Data(body.utf8))
        let rule = NetworkRule(
            name: "Cart", isEnabled: true, match: .path("/api/cart"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)))
        )
        store.add(rule)
        return (rule, bodyID)
    }

    /// A body whose file has gone missing loads as `""`, which is what the editor opened with too,
    /// so the unchanged-body guard used to skip the rewrite however many times the developer
    /// re-saved. The override stayed broken and the editor gave no clue why.
    func testAnOverrideWhoseBodyWentMissingCanBeRepairedInTheEditor() throws {
        let saved = try savedMockRule(body: "gone")
        try FileManager.default.removeItem(at: store.bodyURL(for: saved.bodyID))

        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyText, "")

        XCTAssertTrue(viewModel.save())

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID, "an override that serves nothing should say so rather than point at nothing")
    }

    /// The sheet must not dismiss over an override that was never stored: the developer would find
    /// out from the empty list behind it.
    func testAnOverrideWhoseBodyCannotBeWrittenKeepsTheEditorOpen() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("in the way".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        let unwritable = NetworkRuleStore(defaults: defaults,
                                          bodyDirectory: blocker.appendingPathComponent("bodies",
                                                                                        isDirectory: true))

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: unwritable)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.bodyText = "{}"

        XCTAssertFalse(viewModel.save())
        XCTAssertTrue(viewModel.didFailToSave)
        XCTAssertTrue(unwritable.rules.isEmpty)
    }

    func testEditingTheBodyDeletesTheOneItSupersedes() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyText, "old")

        viewModel.bodyText = "new"
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        let newBodyID = try XCTUnwrap(mock.bodyID)
        XCTAssertNotEqual(newBodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: newBodyID), Data("new".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path),
            "the superseded body is unreachable, so leaving it behind just grows the directory"
        )
    }

    func testEmptyingTheBodyDeletesTheFileAndClearsTheIdentifier() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.bodyText = ""
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path))
    }

    func testRemovingTheStubDeletesTheStrandedBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.isConditioning = true
        viewModel.stubKind = .none
        viewModel.save()

        XCTAssertNil(store.rules.first?.actions.stub)
        XCTAssertNotNil(store.rules.first?.actions.condition)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path),
            "no rule can reach that body any more"
        )
    }

    func testResavingAnUnchangedBodyKeepsTheFileItAlreadyHad() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.draft.name = "Cart (renamed)"
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    func testSwitchingAwayFromAMockAndBackKeepsTheBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.stubKind = .none
        viewModel.stubKind = .mock
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    // MARK: - Map local

    func testImportingAFileCopiesItAndNamesIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let picked = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: picked)

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Users"
        viewModel.draft.match = .path("/v1/users")
        viewModel.stubKind = .mapLocal
        viewModel.importMapLocalFile(from: picked)

        XCTAssertEqual(viewModel.mapLocalSummary, "users.json")
        XCTAssertEqual(viewModel.contentType, "application/json",
                       "the content type is filled in from the document's extension")
        XCTAssertFalse(viewModel.didFailToImportFile)

        guard case .mapLocal(let file) = try XCTUnwrap(viewModel.draft.actions.stub) else {
            return XCTFail("expected a map local stub")
        }
        XCTAssertNotEqual(file.relativePath, picked.path, "the override points at the copy")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file.relativePath)), Data("[]".utf8))
    }

    func testImportingAFileLeavesATypedContentTypeAlone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let picked = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: picked)

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.contentType = "text/plain"
        viewModel.importMapLocalFile(from: picked)

        XCTAssertEqual(viewModel.contentType, "text/plain")
    }

    func testImportingAFileThatCannotBeReadIsReported() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.importMapLocalFile(from: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/nothing.json"))

        XCTAssertTrue(viewModel.didFailToImportFile)
        XCTAssertEqual(viewModel.mapLocalSummary, localized("Not set"))
    }

    // MARK: - Composing actions

    func testANewOverrideStartsAsAMockWithNothingElseSwitchedOn() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertEqual(viewModel.stubKind, .mock)
        XCTAssertFalse(viewModel.isRewritingHeaders)
        XCTAssertFalse(viewModel.isConditioning)
    }

    func testAnOverrideCanStubAndConditionAtOnce() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Slow cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.isConditioning = true
        viewModel.latency = 3
        viewModel.save()

        let saved = store.rules.first
        XCTAssertNotNil(saved?.actions.stub)
        XCTAssertEqual(saved?.actions.condition?.latency, 3)
    }

    func testTurningAnActionOffAndBackOnKeepsWhatWasTypedIntoIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.isConditioning = true
        viewModel.latency = 7
        viewModel.isConditioning = false
        XCTAssertNil(viewModel.draft.actions.condition)
        viewModel.isConditioning = true
        XCTAssertEqual(viewModel.latency, 7)
    }

    func testTurningTheRewriteOffAndBackOnKeepsItsHeaders() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.isRewritingHeaders = true
        viewModel.setHeaders = [NetworkRuleHeaderField(name: "Authorization", value: "Bearer test")]
        viewModel.isRewritingHeaders = false
        viewModel.isRewritingHeaders = true

        XCTAssertEqual(viewModel.draft.actions.rewriteHeaders?.set, ["Authorization": "Bearer test"])
        XCTAssertEqual(viewModel.setHeaders.map(\.name), ["Authorization"])
    }

    func testEditingHeadersWhileTheRewriteIsOffChangesNothing() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.setHeaders = [NetworkRuleHeaderField(name: "Authorization", value: "Bearer test")]
        XCTAssertNil(viewModel.draft.actions.rewriteHeaders)
    }

    func testAnOverrideWithNoActionsIsInvalid() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Inert"
        viewModel.draft.match = .path("/api/cart")
        XCTAssertTrue(viewModel.isValid)

        viewModel.stubKind = .none
        XCTAssertFalse(viewModel.isValid, "an override that matches traffic and does nothing to it")

        viewModel.isRewritingHeaders = true
        XCTAssertTrue(viewModel.isValid)
    }

    func testSavingAnInvalidOverrideWritesNothing() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Inert"
        viewModel.draft.match = .path("/api/cart")
        viewModel.stubKind = .none
        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    func testSavingAnExistingRuleUpdatesItInPlace() {
        var rule = NetworkRule(
            id: UUID(), name: "Old", isEnabled: true, match: .path("/api/cart"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
        )
        store.add(rule)
        rule.name = "New"
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["New"])
        XCTAssertEqual(store.rules.count, 1)
    }
}
