//
//  LanguageViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class LanguageViewModelTests: XCTestCase {

    // `nonisolated(unsafe)` because `setUpWithError()`/`tearDownWithError()` are nonisolated
    // overrides on a `@MainActor` test case. `UserDefaults` is thread-safe, and XCTest runs
    // setup, the test body, and teardown strictly in sequence on one test.
    private nonisolated(unsafe) var system: UserDefaults!
    private nonisolated(unsafe) var scyther: UserDefaults!
    private nonisolated(unsafe) var suites: [String] = []

    override func setUpWithError() throws {
        let a = "LanguageViewModelTests.a.\(UUID().uuidString)", b = "LanguageViewModelTests.b.\(UUID().uuidString)"
        suites = [a, b]
        system = try XCTUnwrap(UserDefaults(suiteName: a))
        scyther = try XCTUnwrap(UserDefaults(suiteName: b))
    }

    override func tearDownWithError() throws {
        system.removePersistentDomain(forName: suites[0])
        scyther.removePersistentDomain(forName: suites[1])
    }

    private func makeViewModel() -> LanguageViewModel {
        let override = LanguageOverride(
            systemDefaults: system, scytherDefaults: scyther,
            hostBundle: ScytherLocalization.moduleBundle, moduleBundle: ScytherLocalization.moduleBundle
        )
        return LanguageViewModel(override: override)
    }

    func testRowsStartWithSystemDefaultThenHostLanguages() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.rows.first?.id, LanguageViewModel.systemDefaultID)
        XCTAssertTrue(viewModel.rows.dropFirst().map(\.id).contains("fr"))
        XCTAssertTrue(viewModel.isSelected(viewModel.rows[0]))
        XCTAssertFalse(viewModel.canReset)
    }

    func testSelectingLanguageSetsOverrideAndRequestsRelaunch() {
        let viewModel = makeViewModel()
        let french = viewModel.rows.first { $0.id == "fr" }!
        viewModel.select(french)
        XCTAssertEqual(system.stringArray(forKey: LanguageOverride.appleLanguagesKey), ["fr"])
        XCTAssertTrue(viewModel.isSelected(french))
        XCTAssertTrue(viewModel.showingRelaunchAlert)
        XCTAssertTrue(viewModel.canReset)
    }

    func testSelectingSystemDefaultResets() {
        let viewModel = makeViewModel()
        viewModel.select(viewModel.rows.first { $0.id == "de" }!)
        viewModel.select(viewModel.rows[0])
        // `object(forKey:)` would still see `AppleLanguages` inherited from NSGlobalDomain, so
        // assert against the suite's own persistent domain — the only place the override writes.
        XCTAssertNil(system.persistentDomain(forName: suites[0])?[LanguageOverride.appleLanguagesKey])
        XCTAssertFalse(viewModel.canReset)
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    func testResetClearsOverride() {
        let viewModel = makeViewModel()
        viewModel.select(viewModel.rows.first { $0.id == "ja" }!)
        viewModel.reset()
        XCTAssertNil(system.persistentDomain(forName: suites[0])?[LanguageOverride.appleLanguagesKey])
        XCTAssertFalse(viewModel.canReset)
    }

    func testSelectedRowIDTracksTheOverride() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.selectedRowID, LanguageViewModel.systemDefaultID)
        viewModel.select(viewModel.rows.first { $0.id == "fr" }!)
        XCTAssertEqual(viewModel.selectedRowID, "fr")
    }

    func testSelectingByIDAppliesTheOverrideAndRaisesTheAlert() {
        let viewModel = makeViewModel()
        viewModel.select(id: "de")
        XCTAssertEqual(system.stringArray(forKey: LanguageOverride.appleLanguagesKey), ["de"])
        XCTAssertEqual(viewModel.selectedRowID, "de")
        XCTAssertTrue(viewModel.showingRelaunchAlert)

        viewModel.showingRelaunchAlert = false
        viewModel.select(id: LanguageViewModel.systemDefaultID)
        XCTAssertNil(system.persistentDomain(forName: suites[0])?[LanguageOverride.appleLanguagesKey])
        XCTAssertEqual(viewModel.selectedRowID, LanguageViewModel.systemDefaultID)
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    /// SwiftUI re-asserts a `Picker`'s selection through its binding on every re-render, including
    /// the one caused by dismissing the alert. A no-op write must not raise it again.
    func testReselectingTheActiveRowDoesNotRaiseTheAlert() {
        let viewModel = makeViewModel()
        viewModel.select(id: "fr")
        XCTAssertTrue(viewModel.showingRelaunchAlert)

        viewModel.showingRelaunchAlert = false
        viewModel.select(id: "fr")
        XCTAssertFalse(viewModel.showingRelaunchAlert)
        XCTAssertEqual(viewModel.selectedRowID, "fr")
    }

    func testRowNamesFollowTheForcedLanguage() {
        let viewModel = makeViewModel()
        viewModel.select(viewModel.rows.first { $0.id == "fr" }!)
        let german = viewModel.rows.first { $0.id == "de" }!
        XCTAssertEqual(german.nativeName, "Deutsch")
        XCTAssertEqual(german.localizedName, "allemand", "row names must be rendered in the forced language")
    }

    /// A session that launched under a French override and then cleared it must name its rows in the
    /// *device's* language, not the language the process started in.
    func testRowNamesFollowTheDeviceAfterResetInARelaunchedSession() {
        system.set(["fr"], forKey: LanguageOverride.appleLanguagesKey)
        scyther.set("fr", forKey: LanguageOverride.bookkeepingKey)
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.rows.first { $0.id == "de" }?.localizedName, "allemand")

        viewModel.reset()

        let device = LanguageOverride.devicePreferredLanguages(systemDefaults: system).first ?? Locale.current.identifier
        let expected = Locale(identifier: device).localizedString(forIdentifier: "de") ?? "de"
        XCTAssertEqual(viewModel.rows.first { $0.id == "de" }?.localizedName, expected)
    }

    func testRowsCarryNativeAndLocalisedNames() {
        let viewModel = makeViewModel()
        let french = viewModel.rows.first { $0.id == "fr" }!
        XCTAssertEqual(french.nativeName, "français")
        XCTAssertFalse(french.localizedName.isEmpty)
    }
}
