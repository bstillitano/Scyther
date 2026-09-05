//
//  NetworkRulesViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRulesViewModelTests: XCTestCase {

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
        suiteName = "NetworkRulesViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRulesViewModelBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    /// A named rule matching one path, with whatever action is asked for.
    private func rule(
        named name: String,
        isEnabled: Bool = true,
        action: NetworkRuleAction = .mock(MockResponse())
    ) -> NetworkRule {
        NetworkRule(name: name, isEnabled: isEnabled, match: .path("/api/\(name)"), action: action)
    }

    // MARK: - Row presentation

    func testSubtitleNamesTheActionAndTheEnabledState() {
        let viewModel = NetworkRulesViewModel(store: store)
        let enabled = rule(named: "cart", isEnabled: true)
        XCTAssertEqual(
            viewModel.subtitle(for: enabled),
            localized("Mock Response") + " \u{00B7} " + localized("On")
        )
    }

    func testSubtitleReadsAsOffForADisabledOverride() {
        let viewModel = NetworkRulesViewModel(store: store)
        let disabled = rule(named: "cart", isEnabled: false, action: .condition(NetworkCondition()))
        XCTAssertEqual(
            viewModel.subtitle(for: disabled),
            localized("Network Condition") + " \u{00B7} " + localized("Off"),
            "a disabled override must read as disabled from the text alone, without a recoloured row"
        )
    }
}
