//
//  MenuSearchIndexTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 3/8/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class MenuSearchIndexTests: XCTestCase {

    // MARK: - MenuSearchEntry

    func testEntryIdentifierCombinesTargetAndTitle() {
        let entry = MenuSearchEntry(
            title: "Grid Color",
            breadcrumb: ["UI/UX", "Grid Overlay"],
            icon: "rectangle.split.3x3",
            target: .gridOverlay,
            isSubpageEntry: true
        )
        XCTAssertEqual(entry.id, "gridOverlay.Grid Color")
    }

    func testBreadcrumbTextJoinsComponentsWithArrows() {
        let entry = MenuSearchEntry(
            title: "Grid Color",
            breadcrumb: ["UI/UX", "Grid Overlay"],
            icon: nil,
            target: .gridOverlay,
            isSubpageEntry: true
        )
        XCTAssertEqual(entry.breadcrumbText, "UI/UX → Grid Overlay")
    }

    // MARK: - Main-menu derivation

    private var mainPageEntries: [MenuSearchEntry] {
        MenuSearchIndex.entries(developerOptions: []).filter { !$0.isSubpageEntry }
    }

    func testEveryStaticItemHasExactlyOneMainPageEntry() {
        let targets = mainPageEntries.map(\.target)
        XCTAssertEqual(targets.count, MenuItem.allStaticCases.count)
        XCTAssertEqual(Set(targets), Set(MenuItem.allStaticCases))
    }

    func testMainPageEntriesCarryTheirSectionTitleAsBreadcrumb() {
        let sections = MenuSection.allSections(developerOptions: [])
        for entry in mainPageEntries {
            let home = sections.first { $0.items.contains(entry.target) }
            XCTAssertEqual(entry.breadcrumb, [home?.title ?? ""], "\(entry.title) has the wrong breadcrumb")
        }
    }

    func testMainPageEntriesUseTheItemTitleAndIcon() {
        for entry in mainPageEntries {
            XCTAssertEqual(entry.title, entry.target.title)
            XCTAssertEqual(entry.icon, entry.target.icon)
        }
    }

    func testEntryIdentifiersAreUnique() {
        let ids = MenuSearchIndex.entries(developerOptions: []).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Two search entries share an identifier")
    }

    func testDeveloperOptionsAreIndexedWhenSupplied() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let entries = MenuSearchIndex.entries(developerOptions: options)

        let entry = entries.first { $0.target == .developerOption(name: "Reset Onboarding") }
        XCTAssertEqual(entry?.title, "Reset Onboarding")
        XCTAssertEqual(entry?.breadcrumb, ["Development Tools"])
        XCTAssertEqual(entry?.isSubpageEntry, false)
    }

    func testDeveloperOptionsAreAbsentWhenNoneAreSupplied() {
        let entries = MenuSearchIndex.entries(developerOptions: [])
        XCTAssertFalse(entries.contains { $0.breadcrumb.first == "Development Tools" })
    }

    // MARK: - Sub-page entries

    private var subpageEntries: [MenuSearchEntry] {
        MenuSearchIndex.entries(developerOptions: []).filter(\.isSubpageEntry)
    }

    func testSubpageEntriesExist() {
        XCTAssertFalse(subpageEntries.isEmpty)
    }

    func testSubpageEntriesTargetRealMenuItems() {
        for entry in subpageEntries {
            XCTAssertTrue(
                MenuItem.allStaticCases.contains(entry.target),
                "\(entry.title) targets a menu item that does not exist"
            )
        }
    }

    func testSubpageBreadcrumbsAreSectionThenPage() {
        let sections = MenuSection.allSections(developerOptions: [])
        for entry in subpageEntries {
            let home = sections.first { $0.items.contains(entry.target) }
            XCTAssertEqual(
                entry.breadcrumb,
                [home?.title ?? "", entry.target.title],
                "\(entry.title) has the wrong breadcrumb"
            )
        }
    }

    func testSubpageEntriesInheritTheirTargetIcon() {
        for entry in subpageEntries {
            XCTAssertEqual(entry.icon, entry.target.icon, "\(entry.title) has the wrong icon")
        }
    }

    func testGridOverlaySubpageRowsAreIndexed() {
        let titles = subpageEntries.filter { $0.target == .gridOverlay }.map(\.title)
        XCTAssertEqual(titles, ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"])
    }

    func testEverySubpageTargetContributesEntries() {
        XCTAssertEqual(
            Set(subpageEntries.map(\.target)),
            [
                .gridOverlay, .fpsCounter, .touchVisualiser, .appearance,
                .locationSpoofer, .notificationTester, .deepLinkTester
            ],
            "A curated sub-page target is missing from the index — its rows were silently dropped"
        )
    }

    // MARK: - Matching

    private func results(for query: String) -> [MenuSearchEntry] {
        MenuSearchIndex.entries(matching: query, developerOptions: [])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(results(for: "").isEmpty)
    }

    func testWhitespaceQueryReturnsNothing() {
        XCTAssertTrue(results(for: "   \n").isEmpty)
    }

    func testTitleMatchIsCaseInsensitive() {
        XCTAssertTrue(results(for: "GRID COLOR").contains { $0.title == "Grid Color" })
    }

    func testTitleMatchIsDiacriticInsensitive() {
        XCTAssertTrue(results(for: "gríd cölor").contains { $0.title == "Grid Color" })
    }

    func testBreadcrumbComponentsMatch() {
        // "grid overlay" appears only in breadcrumbs of sub-page entries and in the
        // page's own title; all Grid Overlay sub-page rows must surface.
        let matches = results(for: "grid overlay").filter(\.isSubpageEntry)
        XCTAssertEqual(
            Set(matches.map(\.title)),
            ["Enable Grid", "Grid Size", "Grid Opacity", "Grid Color"]
        )
    }

    func testQueryIsTrimmedBeforeMatching() {
        XCTAssertTrue(results(for: "  feature flags  ").contains { $0.target == .featureFlags })
    }

    func testDeveloperOptionsAreSearchable() {
        let options = [DeveloperOption(name: "Reset Onboarding", value: "tap")]
        let matches = MenuSearchIndex.entries(matching: "onboarding", developerOptions: options)
        XCTAssertTrue(matches.contains { $0.target == .developerOption(name: "Reset Onboarding") })
    }

    func testUnmatchedQueryReturnsNothing() {
        XCTAssertTrue(results(for: "zzzzzz-no-such-row").isEmpty)
    }

    // MARK: - Alias keywords

    func testEnvVarAliasFindsEnvironmentVariables() {
        XCTAssertTrue(results(for: "env var").contains { $0.target == .environmentVariables })
    }

    func testRemoteConfigAliasFindsFeatureFlags() {
        XCTAssertTrue(results(for: "remote config").contains { $0.target == .featureFlags })
    }

    func testAliasMatchingIsCaseInsensitive() {
        XCTAssertTrue(results(for: "REMOTE CONFIG").contains { $0.target == .featureFlags })
    }

    func testPartialAliasMatches() {
        // The keyword "remote config" contains the partial query.
        XCTAssertTrue(results(for: "remote confi").contains { $0.target == .featureFlags })
    }

    func testEveryKeywordKeyIsARealMenuItem() {
        for key in MenuSearchIndex.keywords.keys {
            XCTAssertTrue(
                MenuItem.allStaticCases.contains(key),
                "\(key) has keywords but is not a static menu item"
            )
        }
    }

    func testMainPageEntriesCarryTheirKeywords() {
        let entry = mainPageEntries.first { $0.target == .featureFlags }
        XCTAssertEqual(entry?.keywords, MenuSearchIndex.keywords[.featureFlags])
    }
}
#endif
