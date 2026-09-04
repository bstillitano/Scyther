//
//  LanguageOverride.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Combine
import Foundation

/// Forces the host app's language and resolves Scyther's own strings in that language.
///
/// iOS reads the `AppleLanguages` array from standard `UserDefaults` at launch, so writing it
/// changes the whole app's language on the **next** launch without any cooperation from the host.
/// Scyther's own menu switches immediately, because ``localized(_:comment:)`` reads from
/// ``effectiveBundle``: the forced language's `.lproj` inside the module bundle.
///
/// The choice is also recorded in `UserDefaults.scyther` under ``bookkeepingKey`` so the Language
/// page can show that an override is active even if the host rewrites `AppleLanguages`.
///
/// ## Usage
///
/// ```swift
/// Scyther.localization.setPreferredLanguage("fr")   // takes effect app-wide on next launch
/// Scyther.localization.reset()                       // back to the device language
/// ```
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Override
/// - ``preferredLanguage``
/// - ``setPreferredLanguage(_:)``
/// - ``reset()``
///
/// ### Resolution
/// - ``effectiveLocale``
/// - ``effectiveBundle``
/// - ``languageBundle(for:in:)``
/// - ``deviceLanguageBundle(systemDefaults:moduleBundle:)``
/// - ``devicePreferredLanguages(systemDefaults:)``
///
/// ### Display
/// - ``availableLanguages``
/// - ``displayName(for:in:)``
/// - ``nativeDisplayName(for:)``
/// - ``currentLanguageDisplayName``
/// - ``currentRegionDisplayName``
public final class LanguageOverride: ObservableObject, @unchecked Sendable {
    /// The shared override, exposed as `Scyther.localization`.
    public static let shared = LanguageOverride()

    /// The standard-defaults key iOS reads at launch.
    static let appleLanguagesKey = "AppleLanguages"

    /// The private-suite key recording Scyther's own override.
    static let bookkeepingKey = "Scyther.Localization.PreferredLanguage"

    /// The BCP 47 identifier forced via `AppleLanguages`, or `nil` for the system default.
    ///
    /// Reads ``_preferredLanguage`` under ``lock``, so it is safe to call from any thread.
    public var preferredLanguage: String? {
        lock.withLock { _preferredLanguage }
    }

    /// Publishes a change notification manually, since ``preferredLanguage`` is no longer `@Published`.
    ///
    /// Declared explicitly (rather than relying on `ObservableObject`'s synthesised publisher) so
    /// it can be sent deterministically from ``setPreferredLanguage(_:)`` and ``reset()``, which may
    /// run off the main actor.
    public let objectWillChange = ObservableObjectPublisher()

    /// Serialises access to ``_preferredLanguage`` and ``resolvedBundle``, the two properties that
    /// change together whenever the override is set or cleared.
    private let lock = NSLock()

    /// Where `AppleLanguages` is written.
    private let systemDefaults: UserDefaults

    /// Where the bookkeeping key is written.
    private let scytherDefaults: UserDefaults

    /// The bundle whose declared localisations populate ``availableLanguages``.
    private let hostBundle: Bundle

    /// The bundle holding Scyther's catalog, used to resolve a forced language's `.lproj` sub-bundle.
    private let moduleBundle: Bundle

    /// The bundle ``effectiveBundle`` currently returns. Guarded by ``lock``.
    private var resolvedBundle: Bundle

    /// Backing storage for ``preferredLanguage``. Guarded by ``lock``.
    private var _preferredLanguage: String?

    /// Creates an override backed by specific stores and bundles. Tests inject throwaway suites.
    ///
    /// - Parameters:
    ///   - systemDefaults: Where `AppleLanguages` is written. Defaults to `.standard`.
    ///   - scytherDefaults: Where the bookkeeping key is written. Defaults to `.scyther`.
    ///   - hostBundle: The bundle whose declared localisations populate ``availableLanguages``.
    ///   - moduleBundle: The bundle holding Scyther's catalog.
    init(
        systemDefaults: UserDefaults = .standard,
        scytherDefaults: UserDefaults = .scyther,
        hostBundle: Bundle = .main,
        moduleBundle: Bundle = ScytherLocalization.moduleBundle
    ) {
        self.systemDefaults = systemDefaults
        self.scytherDefaults = scytherDefaults
        self.hostBundle = hostBundle
        self.moduleBundle = moduleBundle
        let stored = scytherDefaults.string(forKey: Self.bookkeepingKey)
        self._preferredLanguage = stored
        if let stored, let bundle = Self.languageBundle(for: stored, in: moduleBundle) {
            self.resolvedBundle = bundle
        } else {
            self.resolvedBundle = Self.deviceLanguageBundle(systemDefaults: systemDefaults, moduleBundle: moduleBundle)
        }
    }

    // MARK: - Override

    /// Forces a language for the host app (next launch) and Scyther's menu (immediately).
    ///
    /// Writes `[identifier]` to `AppleLanguages` in the system defaults and records the choice in
    /// Scyther's private suite. Passing `nil` is equivalent to ``reset()``.
    ///
    /// - Parameter identifier: A BCP 47 language identifier such as `"fr"` or `"zh-Hans"`.
    public func setPreferredLanguage(_ identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            reset()
            return
        }
        systemDefaults.set([identifier], forKey: Self.appleLanguagesKey)
        scytherDefaults.set(identifier, forKey: Self.bookkeepingKey)
        let bundle = Self.languageBundle(for: identifier, in: moduleBundle) ?? moduleBundle
        lock.withLock {
            _preferredLanguage = identifier
            resolvedBundle = bundle
        }
        notifyObservers()
    }

    /// Removes the override so the host app and Scyther follow the device language again.
    ///
    /// Scyther's own strings switch back immediately, in the same session. That needs an explicit
    /// resolution rather than simply handing back ``moduleBundle``: a bundle's localisation search
    /// list is fixed when the process launches, from the `AppleLanguages` in effect at that moment.
    /// After a relaunch under a forced language, ``moduleBundle`` therefore still resolves to that
    /// language, and clearing the override alone would leave the menu stuck in it until the *next*
    /// launch. ``deviceLanguageBundle(systemDefaults:moduleBundle:)`` reads the device's own
    /// languages from the global domain instead, which the override never writes to.
    public func reset() {
        systemDefaults.removeObject(forKey: Self.appleLanguagesKey)
        scytherDefaults.removeObject(forKey: Self.bookkeepingKey)
        let bundle = Self.deviceLanguageBundle(systemDefaults: systemDefaults, moduleBundle: moduleBundle)
        lock.withLock {
            _preferredLanguage = nil
            resolvedBundle = bundle
        }
        notifyObservers()
    }

    /// Sends ``objectWillChange`` on the main actor, synchronously if already there.
    ///
    /// ``setPreferredLanguage(_:)`` and ``reset()`` may run off the main actor, but SwiftUI
    /// observers expect change notifications on the main actor.
    private func notifyObservers() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            Task { @MainActor [objectWillChange] in
                objectWillChange.send()
            }
        }
    }

    // MARK: - Resolution

    /// The locale matching ``preferredLanguage``, or `nil` when no override is set.
    public var effectiveLocale: Locale? {
        preferredLanguage.map(Locale.init(identifier:))
    }

    /// The bundle Scyther's strings are read from.
    ///
    /// The forced language's `.lproj` sub-bundle when an override is set and the catalog contains
    /// that language; otherwise the module bundle, which follows the device's preferred languages.
    public var effectiveBundle: Bundle {
        lock.withLock { resolvedBundle }
    }

    /// The `.lproj` sub-bundle matching the *device's* languages, ignoring any forced language.
    ///
    /// `Locale.preferredLanguages` and ``moduleBundle``'s own localisation search list both reflect
    /// the `AppleLanguages` that were in effect when the process launched, so neither can tell the
    /// device's language apart from a language Scyther forced before a relaunch. The global domain
    /// can: ``setPreferredLanguage(_:)`` writes `AppleLanguages` into the app's own domain, never
    /// into `NSGlobalDomain`, so the global domain still holds what the user chose in Settings.
    ///
    /// - Parameters:
    ///   - systemDefaults: The defaults object used to read the global domain.
    ///   - moduleBundle: The bundle holding Scyther's catalog.
    /// - Returns: The best-matching `.lproj` sub-bundle, or `moduleBundle` when none matches.
    static func deviceLanguageBundle(systemDefaults: UserDefaults, moduleBundle: Bundle) -> Bundle {
        let preferences = devicePreferredLanguages(systemDefaults: systemDefaults)
        let matches = Bundle.preferredLocalizations(from: moduleBundle.localizations, forPreferences: preferences)
        guard let best = matches.first else { return moduleBundle }
        return languageBundle(for: best, in: moduleBundle) ?? moduleBundle
    }

    /// The device's own preferred languages, ignoring any language Scyther forced.
    ///
    /// `Locale.preferredLanguages` is frozen at launch, so in a session relaunched under an
    /// override it reports the forced language even after the override is cleared. The global
    /// domain is not: ``setPreferredLanguage(_:)`` writes `AppleLanguages` into the app's own
    /// domain only.
    ///
    /// - Parameter systemDefaults: The defaults object used to read the global domain.
    /// - Returns: The device's language identifiers, most preferred first.
    static func devicePreferredLanguages(systemDefaults: UserDefaults) -> [String] {
        let globalDomain = systemDefaults.persistentDomain(forName: UserDefaults.globalDomain)
        guard let languages = globalDomain?[Self.appleLanguagesKey] as? [String], !languages.isEmpty else {
            return Locale.preferredLanguages
        }
        return languages
    }

    /// The `.lproj` sub-bundle for a language inside a bundle, or `nil` if it is not present.
    ///
    /// - Parameters:
    ///   - identifier: A language identifier such as `"fr"` or `"pt-BR"`, or `nil`.
    ///   - bundle: The bundle to search.
    static func languageBundle(for identifier: String?, in bundle: Bundle) -> Bundle? {
        guard let identifier,
              let path = bundle.path(forResource: identifier, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Display

    /// The locale every name on the Language page is rendered in: the forced language when one is
    /// set, otherwise the *device's* language.
    ///
    /// Without this the page's chrome would switch language while every language name and the
    /// Current section stayed behind, which reads as a half-translated screen. The no-override
    /// fallback deliberately reads the device language rather than `Locale.current`, which is
    /// frozen at launch and would still say "français" in a session relaunched under a French
    /// override that the user has since cleared.
    private var namingLocale: Locale {
        if let effectiveLocale { return effectiveLocale }
        guard let device = Self.devicePreferredLanguages(systemDefaults: systemDefaults).first else { return .current }
        return Locale(identifier: device)
    }

    /// The localisations the host app declares, excluding `Base`, sorted by their name in
    /// ``namingLocale`` — so the list re-sorts to match whatever language is in effect.
    public var availableLanguages: [String] {
        let locale = namingLocale
        return hostBundle.localizations
            .filter { $0 != "Base" }
            .sorted { displayName(for: $0, in: locale) < displayName(for: $1, in: locale) }
    }

    /// A language's name in `locale`, e.g. `"French"` for `"fr"` in English.
    ///
    /// - Parameters:
    ///   - identifier: The language identifier.
    ///   - locale: The locale to name it in. Defaults to the current locale.
    public func displayName(for identifier: String, in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// A language's name in itself, e.g. `"français"` for `"fr"`.
    ///
    /// - Parameter identifier: The language identifier.
    public func nativeDisplayName(for identifier: String) -> String {
        Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
    }

    /// The name of the language currently in effect: the override if set, else the device's first
    /// preferred language. Rendered in ``namingLocale``, so under a French override it reads
    /// `"français"` rather than `"French"`.
    public var currentLanguageDisplayName: String {
        let identifier = preferredLanguage
            ?? Self.devicePreferredLanguages(systemDefaults: systemDefaults).first
            ?? Locale.current.identifier
        return displayName(for: identifier, in: namingLocale)
    }

    /// The name of the device's region, e.g. `"Australia"`, rendered in ``namingLocale``.
    public var currentRegionDisplayName: String {
        guard let region = Locale.current.region?.identifier else { return "" }
        return namingLocale.localizedString(forRegionCode: region) ?? region
    }
}
