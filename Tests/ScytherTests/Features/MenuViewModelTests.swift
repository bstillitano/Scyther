//
//  MenuViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import SwiftUI
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

    // MARK: - Section tints

    func testEverySectionHasADedicatedTint() {
        let options = [DeveloperOption(name: "Panel", value: "x")]
        for section in MenuSection.allSections(developerOptions: options) {
            XCTAssertNotEqual(
                section.tint, .accentColor,
                "\"\(section.title)\" falls back to the accent colour — add it to MenuSection.tint(forTitle:)"
            )
        }
    }

    func testSectionTintsAreDistinct() {
        let options = [DeveloperOption(name: "Panel", value: "x")]
        let tints = MenuSection.allSections(developerOptions: options).map(\.tint)
        XCTAssertEqual(Set(tints).count, tints.count, "Two sections share a tile colour")
    }

    func testUnknownSectionTitleFallsBackToAccent() {
        XCTAssertEqual(MenuSection.tint(forTitle: "Removed In V2"), .accentColor)
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

    // MARK: - Consistency under a concurrent mutation

    func testDeveloperOptionRowsListedBySectionsStayResolvableAfterHostMutatesDeveloperOptions() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        Scyther.developerOptions = [DeveloperOption(name: "Panel", value: "x")]
        let viewModel = MenuViewModel(defaults: makeDefaults())

        // This is the same item list `MenuView` uses to decide which rows to render (and to
        // wrap in a live swipe action via `pinnableRow`).
        let items = viewModel.sections.flatMap(\.items)
        XCTAssertTrue(items.contains(.developerOption(name: "Panel")))

        // A host app mutates `Scyther.developerOptions` while the menu is already on screen
        // -- e.g. between the section list being computed and a lazily-materialised row
        // actually being rendered.
        Scyther.developerOptions = []

        // Every developer-option row already committed to the item list above must still be
        // resolvable by name. If it isn't, `rowContent` renders nothing for that row while
        // `pinnableRow` has already wrapped it in a live swipe action -- a blank but
        // swipeable row.
        for item in items {
            guard case .developerOption(let name) = item else { continue }
            XCTAssertNotNil(
                viewModel.developerOption(named: name),
                "\"\(name)\" was listed by sections but can no longer be resolved for rendering"
            )
        }
    }

    // MARK: - Reloading pin state on reappearance

    func testPinnedItemIDsReloadOnSubsequentAppear() async {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let viewModel = MenuViewModel(defaults: defaults)
        viewModel.togglePin(for: .fonts)
        XCTAssertEqual(viewModel.pinnedItemIDs, ["fonts"])

        // Simulate the pin state changing underneath this view model while the menu is off
        // screen -- e.g. "Reset all Scyther settings" in the UserDefaults browser, or a
        // hand-edit of `Scyther.Menu.PinnedItems`. The view model's `@StateObject` survives
        // this because `MenuView` sits at the root of a `UINavigationController`.
        defaults.removeObject(forKey: MenuViewModel.pinnedItemsKey)

        await viewModel.onSubsequentAppear()

        XCTAssertTrue(
            viewModel.pinnedItemIDs.isEmpty,
            "Reappearing after the underlying store changed should reload pin state from disk"
        )
    }

    func testPinnedItemIDsDoNotChangeBeforeTheFirstSubsequentAppear() {
        defer { wipeDefaults() }
        let defaults = makeDefaults()

        let viewModel = MenuViewModel(defaults: defaults)
        viewModel.togglePin(for: .fonts)

        // A change made to the backing store between init and the first reappearance should
        // not retroactively alter in-memory state until `onSubsequentAppear()` actually runs.
        defaults.removeObject(forKey: MenuViewModel.pinnedItemsKey)

        XCTAssertEqual(viewModel.pinnedItemIDs, ["fonts"])
    }

    func testIsPinnedAgreesWithPinnedItemIdentifiers() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.togglePin(for: .gridOverlay)

        XCTAssertTrue(viewModel.isPinned(.gridOverlay))
        XCTAssertFalse(viewModel.isPinned(.fpsCounter))
        XCTAssertEqual(viewModel.pinnedItemIDs, [MenuItem.gridOverlay.id])
    }

    // MARK: - Search

    func testSearchResultsAreEmptyByDefault() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearchResultsReflectTheSearchText() {
        defer { wipeDefaults() }
        let viewModel = MenuViewModel(defaults: makeDefaults())

        viewModel.searchText = "feature flags"

        XCTAssertTrue(viewModel.searchResults.contains { $0.target == .featureFlags })
    }

    func testSearchResultsUseTheDeveloperOptionsSnapshot() {
        defer {
            wipeDefaults()
            Scyther.developerOptions = []
        }
        Scyther.developerOptions = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let viewModel = MenuViewModel(defaults: makeDefaults())

        // Mutating the global after init must not change what search sees — the view
        // model searches the same snapshot `sections` renders from.
        Scyther.developerOptions = []
        viewModel.searchText = "onboarding"

        XCTAssertTrue(viewModel.searchResults.contains {
            $0.target == .developerOption(name: "Reset Onboarding")
        })
    }
}
#endif
