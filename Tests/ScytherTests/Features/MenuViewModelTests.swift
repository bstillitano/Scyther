//
//  MenuViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class MenuViewModelTests: XCTestCase {

    // MARK: - Sections

    func testEveryStaticItemAppearsInExactlyOneSection() {
        let items = MenuSection.allSections(developerOptions: []).flatMap(\.items)

        XCTAssertEqual(Set(items).count, items.count, "An item appears in more than one section")
        XCTAssertEqual(Set(items), Set(MenuItem.allStaticCases), "Sections do not cover every item")
    }

    func testDeviceSectionIsFirst() {
        XCTAssertEqual(MenuSection.allSections(developerOptions: []).first?.title, "Device")
    }

    func testDevelopmentToolsSectionIsOmittedWhenThereAreNoDeveloperOptions() {
        let titles = MenuSection.allSections(developerOptions: []).map(\.title)
        XCTAssertFalse(titles.contains("Development Tools"))
    }

    func testDevelopmentToolsSectionIsIncludedWhenDeveloperOptionsExist() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let sections = MenuSection.allSections(developerOptions: options)

        let developmentTools = sections.first { $0.title == "Development Tools" }
        XCTAssertEqual(developmentTools?.items, [.developerOption(name: "Reset Onboarding")])
    }

    func testSectionTitlesAreInTheExpectedOrder() {
        let options = [DeveloperOption(name: "Panel", value: "x")]
        let titles = MenuSection.allSections(developerOptions: options).map(\.title)

        XCTAssertEqual(titles, [
            "Device",
            "Application",
            "Development Tools",
            "Networking",
            "Data",
            "Security",
            "System Tools",
            "Notifications",
            "UI/UX"
        ])
    }

    func testSectionIdentifiersAreUnique() {
        let ids = MenuSection.allSections(developerOptions: []).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Pinning

    private var suiteName: String { "com.scyther.tests.menu" }

    private func makeDefaults() -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    private func wipeDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testNothingIsPinnedByDefault() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        XCTAssertTrue(viewModel.pinnedItemIDs.isEmpty)
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
    }

    func testPinningAppendsTheItem() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .featureFlags)

        XCTAssertTrue(viewModel.isPinned(.featureFlags))
        XCTAssertEqual(viewModel.pinnedItems, [.featureFlags])
    }

    func testUnpinningRemovesTheItem() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .featureFlags)

        XCTAssertFalse(viewModel.isPinned(.featureFlags))
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
    }

    func testPinnedItemsAreOrderedOldestFirst() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .fonts)

        XCTAssertEqual(viewModel.pinnedItems, [.crashLogs, .featureFlags, .fonts])
    }

    func testUnpinningDoesNotDisturbTheOrderOfOtherItems() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .featureFlags)
        viewModel.togglePin(for: .fonts)
        viewModel.togglePin(for: .featureFlags)

        XCTAssertEqual(viewModel.pinnedItems, [.crashLogs, .fonts])
    }

    func testRepinningMovesTheItemToTheEnd() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .fonts)
        viewModel.togglePin(for: .crashLogs)
        viewModel.togglePin(for: .crashLogs)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts, .crashLogs])
    }

    func testPinStateSurvivesANewViewModel() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let first = MenuViewModel(defaults: defaults)
        first.togglePin(for: .keychainBrowser)
        first.togglePin(for: .cookies)

        let second = MenuViewModel(defaults: defaults)
        XCTAssertEqual(second.pinnedItems, [.keychainBrowser, .cookies])
    }

    func testPinsAreWrittenToTheInjectedStoreOnly() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let viewModel = MenuViewModel(defaults: defaults)
        viewModel.togglePin(for: .fonts)

        XCTAssertEqual(defaults.stringArray(forKey: MenuViewModel.pinnedItemsKey), ["fonts"])
    }

    func testStoredIdentifiersThatNoLongerResolveAreDropped() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()
        defaults.set(["fonts", "removedInV2", "cookies"], forKey: MenuViewModel.pinnedItemsKey)

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts, .cookies])
    }

    func testPinnedDeveloperOptionThatNoLongerExistsIsDropped() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        let defaults = makeDefaults()
        defaults.set(["developerOption.Gone", "fonts"], forKey: MenuViewModel.pinnedItemsKey)
        Scyther.developerOptions = []

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.fonts])
    }

    func testPinnedDeveloperOptionThatStillExistsIsKept() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        let defaults = makeDefaults()
        defaults.set(["developerOption.Panel"], forKey: MenuViewModel.pinnedItemsKey)
        Scyther.developerOptions = [DeveloperOption(name: "Panel", value: "x")]

        let viewModel = MenuViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.pinnedItems, [.developerOption(name: "Panel")])
    }

    func testIsPinnedAgreesWithPinnedItemIdentifiers() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .gridOverlay)

        XCTAssertTrue(viewModel.isPinned(.gridOverlay))
        XCTAssertFalse(viewModel.isPinned(.fpsCounter))
        XCTAssertEqual(viewModel.pinnedItemIDs, [MenuItem.gridOverlay.id])
    }
}
#endif
