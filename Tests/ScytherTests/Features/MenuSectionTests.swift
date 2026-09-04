//
//  MenuSectionTests.swift
//  ScytherTests
//

#if !os(macOS)
@testable import Scyther
import SwiftUI
import XCTest

@MainActor
final class MenuSectionTests: XCTestCase {

    func testSectionIDsAreStableAndUnique() {
        let sections = MenuSection.allSections(developerOptions: [])
        let ids = sections.map(\.id)
        XCTAssertEqual(ids, ["device", "application", "networking", "data", "security", "systemTools", "notifications", "uiux"])
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTintIsKeyedOnIDNotTitle() {
        XCTAssertEqual(MenuSection.tint(forID: "uiux"), .teal)
        XCTAssertEqual(MenuSection.tint(forID: "networking"), .blue)
        XCTAssertEqual(MenuSection.tint(forID: "unknown"), .accentColor)
        let uiux = MenuSection(id: "uiux", title: "Interface utilisateur", items: [])
        XCTAssertEqual(uiux.tint, .teal)
    }
}
#endif
