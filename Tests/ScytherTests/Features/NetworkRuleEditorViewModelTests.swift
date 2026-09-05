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

    func testANewRuleIsInvalidUntilItIsNamed() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertFalse(viewModel.isValid)
        viewModel.draft.name = "Empty cart"
        XCTAssertTrue(viewModel.isValid)
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
