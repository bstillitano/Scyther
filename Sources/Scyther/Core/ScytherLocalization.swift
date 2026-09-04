//
//  ScytherLocalization.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// Resolves a piece of Scyther's own UI copy from the package's String Catalog.
///
/// Every user-facing string in Scyther goes through this function so that SwiftUI and UIKit
/// call sites behave identically and follow the ``LanguageOverride``: when a language has been
/// forced from the Language page, strings are read from that language's `.lproj` table inside
/// the module bundle, so Scyther's menu switches language without a relaunch.
///
/// The parameter is a `String.LocalizationValue`, so a literal at the call site is recognised by
/// Xcode's catalog extraction and interpolations become format placeholders (`Int` → `%lld`,
/// `String` → `%@`). Add every new key, with all supported languages, to the fragment for its
/// module under `Scripts/localization/strings/` and run `Scripts/localization/build_catalog.py`.
///
/// ## Usage
///
/// ```swift
/// Text(localized("Network logs"))
/// LabeledContent(localized("Requests"), value: "\(count)")
/// Text(localized("Preparing archive of \(count) requests…"))
/// ```
///
/// - Parameters:
///   - key: The English source text, which is also the catalog key.
///   - comment: Context for translators. Not used at runtime.
/// - Returns: The string in the effective language, or the English source if the key is missing.
func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    String(localized: key, bundle: LanguageOverride.shared.effectiveBundle, comment: comment)
}

/// Package-level localisation constants.
enum ScytherLocalization {
    /// The bundle holding Scyther's compiled String Catalog.
    static let moduleBundle: Bundle = .module

    /// The languages shipped in the catalog, in addition to the English source.
    static let supportedLanguages: [String] = [
        "fr", "de", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "zh-Hant", "ko", "ru", "ar",
    ]
}
