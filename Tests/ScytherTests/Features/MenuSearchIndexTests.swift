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
}
#endif
