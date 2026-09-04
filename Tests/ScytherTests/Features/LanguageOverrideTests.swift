//
//  LanguageOverrideTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class LanguageOverrideTests: XCTestCase {

    private var system: UserDefaults!
    private var scyther: UserDefaults!
    private var systemSuite: String!
    private var scytherSuite: String!

    override func setUpWithError() throws {
        systemSuite = "LanguageOverrideTests.system.\(UUID().uuidString)"
        scytherSuite = "LanguageOverrideTests.scyther.\(UUID().uuidString)"
        system = try XCTUnwrap(UserDefaults(suiteName: systemSuite))
        scyther = try XCTUnwrap(UserDefaults(suiteName: scytherSuite))
    }

    override func tearDownWithError() throws {
        system.removePersistentDomain(forName: systemSuite)
        scyther.removePersistentDomain(forName: scytherSuite)
    }

    private func makeOverride(hostBundle: Bundle = .main) -> LanguageOverride {
        LanguageOverride(
            systemDefaults: system,
            scytherDefaults: scyther,
            hostBundle: hostBundle,
            moduleBundle: ScytherLocalization.moduleBundle
        )
    }

    func testNoOverrideByDefault() {
        let override = makeOverride()
        XCTAssertNil(override.preferredLanguage)
        XCTAssertNil(override.effectiveLocale)
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testSettingLanguageWritesAppleLanguagesAndBookkeeping() {
        let override = makeOverride()
        override.setPreferredLanguage("fr")
        XCTAssertEqual(system.stringArray(forKey: LanguageOverride.appleLanguagesKey), ["fr"])
        XCTAssertEqual(scyther.string(forKey: LanguageOverride.bookkeepingKey), "fr")
        XCTAssertEqual(override.preferredLanguage, "fr")
        XCTAssertEqual(override.effectiveLocale?.identifier, "fr")
        XCTAssertEqual(override.effectiveBundle.bundlePath.hasSuffix("fr.lproj"), true)
    }

    func testResetRemovesBothKeys() {
        let override = makeOverride()
        override.setPreferredLanguage("de")
        override.reset()
        XCTAssertNil(system.persistentDomain(forName: systemSuite)?[LanguageOverride.appleLanguagesKey], "AppleLanguages must be removed from the suite's own domain")
        XCTAssertNil(scyther.object(forKey: LanguageOverride.bookkeepingKey))
        XCTAssertNil(override.preferredLanguage)
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testSettingNilBehavesLikeReset() {
        let override = makeOverride()
        override.setPreferredLanguage("de")
        override.setPreferredLanguage(nil)
        XCTAssertNil(system.persistentDomain(forName: systemSuite)?[LanguageOverride.appleLanguagesKey], "AppleLanguages must be removed from the suite's own domain")
        XCTAssertNil(override.preferredLanguage)
    }

    func testPreferredLanguageIsRestoredFromBookkeepingOnInit() {
        scyther.set("ja", forKey: LanguageOverride.bookkeepingKey)
        let override = makeOverride()
        XCTAssertEqual(override.preferredLanguage, "ja")
    }

    func testLanguageNotInCatalogFallsBackToModuleBundle() {
        let override = makeOverride()
        override.setPreferredLanguage("xx")
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testAvailableLanguagesExcludeBaseAndSortByDisplayName() {
        let override = makeOverride(hostBundle: ScytherLocalization.moduleBundle)
        let languages = override.availableLanguages
        XCTAssertFalse(languages.contains("Base"))
        XCTAssertTrue(languages.contains("fr"))
        let names = languages.map { override.displayName(for: $0, in: Locale(identifier: "en")) }
        XCTAssertEqual(names, names.sorted())
    }

    func testDisplayNames() {
        let override = makeOverride()
        XCTAssertEqual(override.displayName(for: "fr", in: Locale(identifier: "en")), "French")
        XCTAssertEqual(override.nativeDisplayName(for: "fr"), "français")
        let simplified = override.displayName(for: "zh-Hans", in: Locale(identifier: "en"))
        XCTAssertTrue(simplified.contains("Chinese") && simplified.contains("Simplified"), simplified)
    }
}
