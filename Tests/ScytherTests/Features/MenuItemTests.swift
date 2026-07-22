//
//  MenuItemTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/7/2026.
//

#if !os(macOS)
@testable import Scyther
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
            .gridOverlay, .fpsCounter, .touchVisualiser, .appearance
        ]
        for item in navigationItems {
            XCTAssertNotNil(item.icon, "\(item) should have an icon")
        }
    }

    func testDeviceAndApplicationInfoItemsHaveNoIcon() {
        let infoItems: [MenuItem] = [
            .osVersion, .hardware, .releaseYear, .uuid,
            .appIdPrefix, .displayName, .bundleId, .processId,
            .version, .buildNumber, .buildDate, .releaseType
        ]
        for item in infoItems {
            XCTAssertNil(item.icon, "\(item) should not have an icon")
        }
    }

    func testStaticCaseCountIsStable() {
        XCTAssertEqual(MenuItem.allStaticCases.count, 39)
    }
}
#endif
