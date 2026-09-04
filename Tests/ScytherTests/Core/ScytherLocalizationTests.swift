//
//  ScytherLocalizationTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ScytherLocalizationTests: XCTestCase {

    private var system: UserDefaults!
    private var scyther: UserDefaults!
    private var systemSuite: String!
    private var scytherSuite: String!

    override func setUpWithError() throws {
        systemSuite = "ScytherLocalizationTests.system.\(UUID().uuidString)"
        scytherSuite = "ScytherLocalizationTests.scyther.\(UUID().uuidString)"
        system = try XCTUnwrap(UserDefaults(suiteName: systemSuite))
        scyther = try XCTUnwrap(UserDefaults(suiteName: scytherSuite))
    }

    override func tearDownWithError() throws {
        system.removePersistentDomain(forName: systemSuite)
        scyther.removePersistentDomain(forName: scytherSuite)
    }

    /// A throwaway override backed by this test's own suites, so nothing here touches the shared one.
    private func makeOverride() -> LanguageOverride {
        LanguageOverride(
            systemDefaults: system,
            scytherDefaults: scyther,
            hostBundle: ScytherLocalization.moduleBundle,
            moduleBundle: ScytherLocalization.moduleBundle
        )
    }

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

    // MARK: - Override-driven resolution

    func testLocalizedReadsTheForcedLanguagesTable() {
        let override = makeOverride()
        override.setPreferredLanguage("fr")
        XCTAssertEqual(localized("Language", override: override), "Langue")
    }

    /// Russian has `one`/`few`/`many` categories English does not. Selecting them needs the
    /// override's locale, not `Locale.current`, which is frozen at launch.
    func testPluralCategoriesFollowTheForcedLanguage() {
        let override = makeOverride()
        override.setPreferredLanguage("ru")
        XCTAssertEqual(localized("\(5) selected", override: override), "Выбрано 5", "5 must take the Russian many form")
        XCTAssertEqual(localized("\(21) selected", override: override), "Выбран 21", "21 must take the Russian one form")
        XCTAssertEqual(localized("\(3) selected", override: override), "Выбрано 3", "3 must take the Russian few form")
    }

    /// Arabic adds a `two` category, which no other supported language uses.
    func testArabicUsesItsTwoForm() {
        let override = makeOverride()
        override.setPreferredLanguage("ar")
        XCTAssertEqual(localized("\(2) selected", override: override), "تم تحديد عنصرين")
    }

    /// Clearing the override must put both the table and the plural rules back on the device's
    /// language, computed the same way the implementation computes them.
    func testResetResolvesTheDeviceLanguagesForm() {
        let override = makeOverride()
        override.setPreferredLanguage("ru")
        override.reset()

        let resolution = LanguageOverride.resolution(
            forcing: nil,
            systemDefaults: system,
            moduleBundle: ScytherLocalization.moduleBundle
        )
        let expected = String(localized: "\(5) selected", bundle: resolution.bundle, locale: resolution.locale)
        XCTAssertEqual(localized("\(5) selected", override: override), expected)
        XCTAssertNotEqual(localized("Language", override: override), "Язык", "reset left Scyther stuck in Russian")
    }

    /// ``LanguageOverride/resolutionLocale`` is never `nil`, unlike ``LanguageOverride/effectiveLocale``.
    func testResolutionLocaleTracksTheOverrideWhileEffectiveLocaleStaysOptional() {
        let override = makeOverride()
        XCTAssertNil(override.effectiveLocale)
        XCTAssertEqual(override.resolutionLocale.identifier, LanguageOverride.deviceLocale(systemDefaults: system).identifier)

        override.setPreferredLanguage("ru")
        XCTAssertEqual(override.effectiveLocale?.identifier, "ru")
        XCTAssertEqual(override.resolutionLocale.identifier, "ru")
        XCTAssertEqual(override.namingLocale.identifier, "ru", "naming must follow the resolution locale")
    }

    /// A language the catalog has no table for falls back to the device for *both* halves, so the
    /// table and the plural rules can never disagree.
    func testUnknownLanguageResolvesBundleAndLocaleTogether() {
        let override = makeOverride()
        override.setPreferredLanguage("xx")
        let device = LanguageOverride.resolution(
            forcing: nil,
            systemDefaults: system,
            moduleBundle: ScytherLocalization.moduleBundle
        )
        XCTAssertEqual(override.effectiveBundle.bundlePath, device.bundle.bundlePath)
        XCTAssertEqual(override.resolutionLocale.identifier, device.locale.identifier)
    }
}
