//
//  LocalizableCatalogTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Parses the shipped catalog source and checks it is complete and consistent.
final class LocalizableCatalogTests: XCTestCase {

    private struct Catalog: Decodable {
        struct Localization: Decodable {
            struct Unit: Decodable { let state: String; let value: String }
            struct Variations: Decodable { let plural: [String: Wrapped]? }
            struct Wrapped: Decodable { let stringUnit: Unit }
            let stringUnit: Unit?
            let variations: Variations?
        }
        struct Entry: Decodable { let localizations: [String: Localization]; let comment: String? }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private static let placeholder = try! NSRegularExpression(pattern: #"%(\d+\$)?[@dlfsu]|%lld|%\.\d+f"#)

    private func placeholders(in text: String) -> [String] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return Self.placeholder.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    private func loadCatalog() throws -> Catalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Scyther/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    func testSourceLanguageIsEnglish() throws {
        XCTAssertEqual(try loadCatalog().sourceLanguage, "en")
    }

    func testEveryKeyHasEverySupportedLanguage() throws {
        let catalog = try loadCatalog()
        XCTAssertFalse(catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            for language in ScytherLocalization.supportedLanguages {
                guard let localization = entry.localizations[language] else {
                    XCTFail("\(key): missing \(language)"); continue
                }
                if let unit = localization.stringUnit {
                    XCTAssertFalse(unit.value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key): empty \(language)")
                } else if let plural = localization.variations?.plural {
                    XCTAssertFalse(plural.isEmpty, "\(key): empty plural for \(language)")
                } else {
                    XCTFail("\(key): \(language) has neither a stringUnit nor plural variations")
                }
            }
        }
    }

    func testPlaceholdersMatchEnglishInEveryLanguage() throws {
        let catalog = try loadCatalog()
        for (key, entry) in catalog.strings {
            let source: String = entry.localizations["en"]?.variations?.plural?["other"]?.stringUnit.value ?? key
            let expected = placeholders(in: source)
            for (language, localization) in entry.localizations {
                if let unit = localization.stringUnit {
                    XCTAssertEqual(placeholders(in: unit.value), expected, "\(key) [\(language)]")
                } else if let other = localization.variations?.plural?["other"] {
                    XCTAssertEqual(placeholders(in: other.stringUnit.value), expected, "\(key) [\(language).other]")
                }
            }
        }
    }

    func testNoNearDuplicateKeys() throws {
        let keys = try loadCatalog().strings.keys
        var seen: [String: String] = [:]
        for key in keys {
            let normalised = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".…:!? "))
            if let existing = seen[normalised], existing != key {
                XCTFail("near-duplicate keys: \(existing) / \(key)")
            }
            seen[normalised] = key
        }
    }

    func testCompiledTablesMatchSource() throws {
        let catalog = try loadCatalog()
        let key = try XCTUnwrap(catalog.strings.keys.first { catalog.strings[$0]?.localizations["fr"]?.stringUnit != nil })
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(french.localizedString(forKey: key, value: nil, table: nil), catalog.strings[key]?.localizations["fr"]?.stringUnit?.value)
    }
}
