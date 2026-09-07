//
//  PseudoLocalizationKeyTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class PseudoLocalizationKeyTests: XCTestCase {

    func testALiteralKeyIsRecoveredVerbatim() {
        let value: String.LocalizationValue = "Grid Overlay"
        XCTAssertEqual(PseudoLocalizationKey.extract(from: value), "Grid Overlay")
    }

    func testAnInterpolatedKeyIsRecoveredAsItsCatalogFormRatherThanItsFormattedForm() {
        let count = 5
        let value: String.LocalizationValue = "Selected \(count) items"
        XCTAssertEqual(PseudoLocalizationKey.extract(from: value), "Selected %lld items")
    }

    func testAStringInterpolationIsRecoveredAsAnObjectSpecifier() {
        let name = "Brandon"
        let value: String.LocalizationValue = "Hello \(name)"
        XCTAssertEqual(PseudoLocalizationKey.extract(from: value), "Hello %@")
    }

    func testAnEmptyKeyIsStillRecovered() {
        let value: String.LocalizationValue = ""
        XCTAssertEqual(PseudoLocalizationKey.extract(from: value), "")
    }
}
#endif
