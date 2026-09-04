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

    /// The `.lproj` bundle Scyther must resolve to when no override is set, computed from the same
    /// global-domain languages the implementation reads. Keeps the assertions below deterministic
    /// whatever language the running simulator is set to.
    private var deviceLanguageBundle: Bundle {
        let preferences = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[LanguageOverride.appleLanguagesKey] as? [String])
            ?? Locale.preferredLanguages
        let matches = Bundle.preferredLocalizations(from: ScytherLocalization.moduleBundle.localizations, forPreferences: preferences)
        guard let best = matches.first,
              let bundle = LanguageOverride.languageBundle(for: best, in: ScytherLocalization.moduleBundle) else {
            return ScytherLocalization.moduleBundle
        }
        return bundle
    }

    private func language(in bundle: Bundle) -> String {
        bundle.localizedString(forKey: "Language", value: nil, table: nil)
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
        XCTAssertEqual(override.effectiveBundle.bundlePath, deviceLanguageBundle.bundlePath)
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
        XCTAssertEqual(override.effectiveBundle.bundlePath, deviceLanguageBundle.bundlePath)
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

    /// The host app still switches to a language Scyther has no `.lproj` for; Scyther's own strings
    /// fall back to the device's language rather than to whatever the process launched in.
    func testLanguageNotInCatalogFallsBackToTheDeviceLanguage() {
        let override = makeOverride()
        override.setPreferredLanguage("xx")
        XCTAssertEqual(override.preferredLanguage, "xx")
        XCTAssertEqual(override.effectiveBundle.bundlePath, deviceLanguageBundle.bundlePath)
    }

    func testAvailableLanguagesExcludeBaseAndSortByDisplayName() {
        let override = makeOverride(hostBundle: ScytherLocalization.moduleBundle)
        let languages = override.availableLanguages
        XCTAssertFalse(languages.contains("Base"))
        XCTAssertTrue(languages.contains("fr"))
        let names = languages.map { override.displayName(for: $0, in: Locale(identifier: "en")) }
        XCTAssertEqual(names, names.sorted())
    }

    /// A session relaunched under a forced language must switch back the moment the override is
    /// cleared. `Bundle.module`'s search list is frozen at launch, so clearing alone is not enough.
    func testResetResolvesTheDeviceLanguageNotTheLaunchLanguage() {
        system.set(["fr"], forKey: LanguageOverride.appleLanguagesKey)
        scyther.set("fr", forKey: LanguageOverride.bookkeepingKey)
        let override = makeOverride()
        XCTAssertEqual(language(in: override.effectiveBundle), "Langue", "the stored override should resolve French")

        override.reset()

        let expected = language(in: deviceLanguageBundle)
        XCTAssertEqual(language(in: override.effectiveBundle), expected)
        if expected != "Langue" {
            XCTAssertNotEqual(language(in: override.effectiveBundle), "Langue", "reset left Scyther stuck in the launch language")
        }
    }

    func testCurrentLanguageNameIsRenderedInTheForcedLanguage() {
        let override = makeOverride()
        override.setPreferredLanguage("fr")
        XCTAssertEqual(override.currentLanguageDisplayName, override.displayName(for: "fr", in: Locale(identifier: "fr")))
        XCTAssertEqual(override.currentLanguageDisplayName, "français")
    }

    /// After clearing an override in a session that launched under it, the Current section must
    /// name the *device's* language, not the launch language `Locale.current` is stuck on.
    func testCurrentLanguageNameFollowsTheDeviceAfterReset() {
        system.set(["fr"], forKey: LanguageOverride.appleLanguagesKey)
        scyther.set("fr", forKey: LanguageOverride.bookkeepingKey)
        let override = makeOverride()
        XCTAssertEqual(override.currentLanguageDisplayName, "français")

        override.reset()

        let identifier = LanguageOverride.devicePreferredLanguages(systemDefaults: system).first ?? Locale.current.identifier
        XCTAssertEqual(
            override.currentLanguageDisplayName,
            override.displayName(for: identifier, in: Locale(identifier: identifier))
        )
    }

    func testDisplayNames() {
        let override = makeOverride()
        XCTAssertEqual(override.displayName(for: "fr", in: Locale(identifier: "en")), "French")
        XCTAssertEqual(override.nativeDisplayName(for: "fr"), "français")
        let simplified = override.displayName(for: "zh-Hans", in: Locale(identifier: "en"))
        XCTAssertTrue(simplified.contains("Chinese") && simplified.contains("Simplified"), simplified)
    }
}
