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
}
#endif
