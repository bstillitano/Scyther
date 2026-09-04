//
//  MenuItemTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
import SwiftUI
import XCTest

final class MenuItemTests: XCTestCase {

    // MARK: - Identity

    func testAllStaticCaseIdentifiersAreUnique() {
        let ids = MenuItem.allStaticCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Two menu items share an identifier")
    }

    func testAllStaticCaseIdentifiersAreNonEmpty() {
        for item in MenuItem.allStaticCases {
            XCTAssertFalse(item.id.isEmpty, "\(item) has an empty identifier")
        }
    }

    func testEveryStaticCaseRoundTripsThroughItsIdentifier() {
        for item in MenuItem.allStaticCases {
            XCTAssertEqual(MenuItem(id: item.id), item, "\(item) did not round-trip")
        }
    }

    func testDeveloperOptionRoundTrips() {
        let item = MenuItem.developerOption(name: "Reset Onboarding")
        XCTAssertEqual(MenuItem(id: item.id), item)
    }

    func testDeveloperOptionRoundTripsWithAwkwardNames() {
        let names = ["A.B.C", "has spaces", "emoji 🚀", "developerOption.nested"]
        for name in names {
            let item = MenuItem.developerOption(name: name)
            XCTAssertEqual(MenuItem(id: item.id), item, "\(name) did not round-trip")
        }
    }

    func testDeveloperOptionIdentifierIsNamespaced() {
        XCTAssertEqual(MenuItem.developerOption(name: "Panel").id, "developerOption.Panel")
    }

    func testUnknownIdentifierReturnsNil() {
        XCTAssertNil(MenuItem(id: "somethingThatWasRemovedInV2"))
    }

    func testEmptyDeveloperOptionNameReturnsNil() {
        XCTAssertNil(MenuItem(id: "developerOption."))
    }

    func testPinnedRowIdentifierIsDistinctFromTheIdentifier() {
        let item = MenuItem.featureFlags
        XCTAssertNotEqual(item.pinnedRowID, item.id)
        XCTAssertTrue(item.pinnedRowID.hasSuffix(item.id))
    }

    // MARK: - Presentation

    func testEveryStaticCaseHasANonEmptyTitle() {
        for item in MenuItem.allStaticCases {
            XCTAssertFalse(item.title.isEmpty, "\(item) has no title")
        }
    }

    func testDeveloperOptionTitleIsItsName() {
        XCTAssertEqual(MenuItem.developerOption(name: "Reset Onboarding").title, "Reset Onboarding")
    }

    func testNavigationItemsCarryAnIcon() {
        let navigationItems: [MenuItem] = [
            .networkLogs, .serverConfiguration, .environmentVariables, .featureFlags,
            .userDefaults, .cookies, .fileBrowser, .databaseBrowser, .keychainBrowser,
            .locationSpoofer, .consoleLogs, .deepLinkTester, .crashLogs,
            .notificationLogger, .notificationTester, .fonts, .interfaceComponents,
            .gridOverlay, .fpsCounter, .touchVisualiser, .appearance, .language
        ]
        for item in navigationItems {
            XCTAssertNotNil(item.icon, "\(item) should have an icon")
        }
    }

    func testEveryStaticItemCarriesAnIcon() {
        for item in MenuItem.allStaticCases {
            XCTAssertNotNil(item.icon, "\(item) should have an icon for its section-tinted tile")
            XCTAssertFalse(item.icon?.isEmpty ?? true, "\(item) has an empty icon name")
        }
    }

    func testDeveloperOptionHasNoBuiltInIcon() {
        // Its icon comes from the host-supplied DeveloperOption instead.
        XCTAssertNil(MenuItem.developerOption(name: "Panel").icon)
    }

    func testEveryStaticItemTintMatchesItsHomeSection() {
        for section in MenuSection.allSections(developerOptions: []) {
            for item in section.items {
                XCTAssertEqual(item.tint, section.tint, "\(item) should wear \(section.title)'s tint")
            }
        }
    }

    func testDeveloperOptionTintIsTheDevelopmentToolsTint() {
        XCTAssertEqual(
            MenuItem.developerOption(name: "Panel").tint,
            MenuSection.tint(forID: MenuSectionID.developmentTools)
        )
    }

    func testStaticCaseCountIsStable() {
        XCTAssertEqual(MenuItem.allStaticCases.count, 40)
    }
}
#endif
