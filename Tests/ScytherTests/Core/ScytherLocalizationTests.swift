//
//  ScytherLocalizationTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ScytherLocalizationTests: XCTestCase {

    func testModuleBundleContainsCompiledCatalog() throws {
        let bundle = ScytherLocalization.moduleBundle
        for language in ScytherLocalization.supportedLanguages {
            XCTAssertNotNil(bundle.path(forResource: language, ofType: "lproj"), "missing \(language).lproj")
        }
    }

    func testLanguageBundleResolvesKnownKey() throws {
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(String(localized: "Language", bundle: french), "Langue")
        let japanese = try XCTUnwrap(LanguageOverride.languageBundle(for: "ja", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(String(localized: "Language", bundle: japanese), "言語")
    }

    func testLanguageBundleIsNilForUnknownLanguage() {
        XCTAssertNil(LanguageOverride.languageBundle(for: "xx", in: ScytherLocalization.moduleBundle))
    }

    func testLocalizedFallsBackToEnglishSourceForUnknownKey() {
        XCTAssertEqual(localized("This key does not exist in the catalog"), "This key does not exist in the catalog")
    }

    func testLocalizedInterpolatesArguments() throws {
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        let count = 3
        XCTAssertEqual(String(localized: "\(count) selected", bundle: french), "3 sélectionnés")
    }
}
