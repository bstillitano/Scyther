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
}
#endif
