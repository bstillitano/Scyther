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

    /// Every literal key `localized(_:)` is called with in the source has an entry in the catalog.
    ///
    /// The unlocalised-literal lint catches a string that never reached `localized(_:)`. Nothing
    /// caught the other direction — a key that *is* localised in source but has no translation
    /// behind it — which fails soundlessly at runtime, because `String(localized:)` falls back to
    /// the key and the English reader sees the right words in every language.
    ///
    /// Keys built with string interpolation are skipped. Their catalog key is the format the
    /// compiler derives — `%lld bytes` for `localized("\(count) bytes")` — and reconstructing that
    /// from source text would mean inferring each interpolation's type, which this cannot do
    /// honestly. Those keys are covered by the suite's other checks once they are in the catalog.
    func testEveryLocalisedKeyInSourceIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        var missing: [String] = []
        var checked = 0

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                for key in Self.localisedKeys(in: line) {
                    checked += 1
                    guard catalog.strings[key] == nil else { continue }
                    missing.append("\(file.lastPathComponent):\(index + 1): \(key)")
                }
            }
        }

        XCTAssertGreaterThan(checked, 100, "the scanner found almost nothing, so it is not scanning")
        XCTAssertTrue(missing.isEmpty, "localized() keys with no catalog entry:\n" + missing.joined(separator: "\n"))
    }

    /// The literal keys a line passes to `localized(_:)`, with interpolated ones left out.
    ///
    /// - Parameter line: One line of Swift source.
    /// - Returns: The keys, unescaped.
    static func localisedKeys(in line: String) -> [String] {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return localisedCall.matches(in: line, range: range).compactMap { match in
            let key = (line as NSString).substring(with: match.range(at: 1))
            guard !key.contains("\\(") else { return nil }
            return key.replacingOccurrences(of: "\\\"", with: "\"")
        }
    }

    /// Matches `localized("…")`, capturing the literal between the quotes.
    private static let localisedCall = try! NSRegularExpression(pattern: #"localized\(\s*"((?:[^"\\]|\\.)*)""#)

    /// The directory the source scan walks.
    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Scyther")
    }

    func testTheKeyScannerReadsLiteralsAndSkipsInterpolations() {
        XCTAssertEqual(Self.localisedKeys(in: #"Text(localized("Network logs"))"#), ["Network logs"])
        XCTAssertEqual(Self.localisedKeys(in: #"localized("A"), localized("B")"#), ["A", "B"])
        XCTAssertEqual(Self.localisedKeys(in: ###"localized("\(count) bytes")"###), [])
        XCTAssertEqual(Self.localisedKeys(in: #"Text("not localised")"#), [])
    }

    func testCompiledTablesMatchSource() throws {
        let catalog = try loadCatalog()
        let key = try XCTUnwrap(catalog.strings.keys.first { catalog.strings[$0]?.localizations["fr"]?.stringUnit != nil })
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(french.localizedString(forKey: key, value: nil, table: nil), catalog.strings[key]?.localizations["fr"]?.stringUnit?.value)
    }
}
