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
        let bodyID = store.storeBody(Data(body.utf8))
        let rule = NetworkRule(
            name: "Cart", isEnabled: true, match: .path("/api/cart"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0))
        )
        store.add(rule)
        return (rule, bodyID)
    }

    func testEditingTheBodyDeletesTheOneItSupersedes() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyText, "old")

        viewModel.bodyText = "new"
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).action else {
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

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).action else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path))
    }

    func testSwitchingTheActionAwayFromAMockDeletesTheStrandedBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.actionKind = .condition
        viewModel.save()

        XCTAssertEqual(store.rules.first?.action.kind, .condition)
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

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).action else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    func testSwitchingAwayFromAMockAndBackKeepsTheBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.actionKind = .condition
        viewModel.actionKind = .mock
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).action else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    func testSavingAnExistingRuleUpdatesItInPlace() {
        var rule = NetworkRule(
            id: UUID(), name: "Old", isEnabled: true, match: .path("/api/cart"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        )
        store.add(rule)
        rule.name = "New"
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["New"])
        XCTAssertEqual(store.rules.count, 1)
    }
}
