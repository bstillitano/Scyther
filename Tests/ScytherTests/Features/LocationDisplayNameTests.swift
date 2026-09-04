//
//  LocationDisplayNameTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers the `displayName` computed properties that resolve Scyther's own location and route
/// preset names through the String Catalog at display time.
///
/// `Location.name` and `Route.name` keep their English wording so that persisted data, GPX output
/// and the public API stay stable; the views read `displayName` instead. These tests check both
/// halves of that split:
///
/// - the `switch` in each property covers every built-in preset, and each `case` matches the stored
///   English name exactly (otherwise the preset would silently fall through to the raw name);
/// - the stored English names really are catalog keys, so a non-English table resolves them; and
/// - a `Location` or `Route` created by the host app falls through to its own name unchanged.
///
/// Translations are read through an explicit `.lproj` bundle from
/// ``ScytherLocalization/moduleBundle`` rather than the process language, so the results do not
/// depend on the simulator's locale.
final class LocationDisplayNameTests: XCTestCase {

    // MARK: - Helpers

    /// Every built-in city preset's `Location`.
    private var cityPresets: [Location] {
        LocationSpooferPresets.allCases.compactMap { $0.location }
    }

    /// Every built-in route preset's `Route`.
    private var routePresets: [Route] {
        LocationSpooferPresets.allCases.compactMap { $0.route }
    }

    /// Resolves `key` in `language`'s table inside the module bundle.
    ///
    /// - Parameters:
    ///   - key: The English source string, which is also the catalog key.
    ///   - language: A shipped language code such as `"fr"`.
    /// - Returns: The translation for that language.
    private func translation(of key: String, in language: String) throws -> String {
        let bundle = try XCTUnwrap(
            LanguageOverride.languageBundle(for: language, in: ScytherLocalization.moduleBundle),
            "missing \(language).lproj"
        )
        return String(localized: String.LocalizationValue(stringLiteral: key), bundle: bundle)
    }

    // MARK: - Coverage of the switch

    func testEveryCityPresetDisplayNameMatchesItsEnglishName() {
        XCTAssertFalse(cityPresets.isEmpty)
        for location in cityPresets {
            XCTAssertEqual(location.displayName, location.name, "\(location.id) is missing from the displayName switch")
        }
    }

    func testEveryRoutePresetDisplayNameMatchesItsEnglishName() {
        XCTAssertFalse(routePresets.isEmpty)
        for route in routePresets {
            XCTAssertEqual(route.displayName, route.name, "\(route.id ?? "?") is missing from the displayName switch")
        }
    }

    // MARK: - The stored names are catalog keys

    func testEveryCityPresetNameResolvesInFrench() throws {
        for location in cityPresets {
            let french = try translation(of: location.name, in: "fr")
            XCTAssertFalse(french.trimmingCharacters(in: .whitespaces).isEmpty, "\(location.name): empty fr")
        }
    }

    func testEveryRoutePresetNameResolvesInFrench() throws {
        for route in routePresets {
            let french = try translation(of: route.name, in: "fr")
            XCTAssertFalse(french.trimmingCharacters(in: .whitespaces).isEmpty, "\(route.name): empty fr")
            XCTAssertNotEqual(french, route.name, "\(route.name) was not translated into French")
        }
    }

    // MARK: - Exonyms

    func testCityExonymsResolveInTheirLanguage() throws {
        // A city whose name changes in the target language.
        XCTAssertEqual(try translation(of: Location.lisbon.name, in: "fr"), "Lisbonne, Portugal")
        XCTAssertEqual(try translation(of: Location.moscow.name, in: "ru"), "Москва, Россия")
        XCTAssertEqual(try translation(of: Location.tokyo.name, in: "ja"), "東京、日本")
        // A city whose name is unchanged in the target language still has an entry, with the
        // country translated around it.
        XCTAssertEqual(try translation(of: Location.tokyo.name, in: "fr"), "Tokyo, Japon")
    }

    func testRouteNameIsTranslated() throws {
        XCTAssertEqual(try translation(of: Route.driveCityToSuburb.name, in: "fr"), "Trajet en voiture de la ville à la banlieue")
    }

    // MARK: - Fallback for host-supplied models

    func testCustomLocationDisplayNameFallsBackToItsName() {
        let location = Location(id: "hq", name: "Custom HQ", latitude: 37.7749, longitude: -122.4194)
        XCTAssertEqual(location.displayName, "Custom HQ")
    }

    func testCustomRouteDisplayNameFallsBackToItsName() {
        let route = Route(id: "commute", name: "Morning Commute", fileName: "MorningCommute", updateInterval: 3)
        XCTAssertEqual(route.displayName, "Morning Commute")
    }
}
