//
//  PseudoLocalizationHostHook.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import Foundation

/// Extends pseudo-localisation from Scyther's own interface into the host app's strings, by
/// hooking the one string-loading funnel that can be hooked.
///
/// ## Why this method, and what it misses
///
/// `NSLocalizedString(_:tableName:bundle:value:comment:)` is a thin wrapper over
/// `-[NSBundle localizedStringForKey:value:table:]`, an Objective-C method and therefore
/// swizzlable. Scyther already swizzles `UIView.layoutSubviews`, `UIWindow` and
/// `CLLocationManager`, so the technique and the machinery are established here.
///
/// It does not reach everything, and the gap is large enough to state rather than imply. Measured
/// with this method hooked and the results printed:
///
/// | Call site | Reaches the hook |
/// | --- | --- |
/// | `NSLocalizedString(…)` | yes |
/// | `String(localized:)` | no |
/// | SwiftUI `Text("some key")` | no |
/// | `LocalizedStringResource` | no |
///
/// The SwiftUI result was checked non-vacuously — the `Text` was rendered all the way to a bitmap
/// with `ImageRenderer`, which succeeded, and the hook still recorded nothing. Foundation's
/// Swift-native lookup does not descend into `NSBundle` at all; no other selector on the class
/// sees those calls either, `localizedStringForKey:value:table:localizations:` included.
///
/// The practical consequence: a UIKit app, or any app whose copy goes through
/// `NSLocalizedString`, is pseudo-localised broadly. A SwiftUI app whose copy is written as
/// `Text("Some string")` is not, and for it this feature demonstrates the idea against Scyther's
/// own interface rather than testing the developer's.
///
/// ## Scope and safety
///
/// - Only `Bundle.main` is transformed, and within it only the default table (`Localizable`).
///   Framework and system bundles resolve normally, so UIKit's own "Cancel" and "Done" are left
///   alone — and so is a host app's own named table, which teams routinely use for things that are
///   per-locale but are not copy: analytics identifiers, feature-flag names, segment keys. The
///   trade is deliberate and one-directional: copy kept in a named table is missed, which costs
///   coverage, whereas transforming an identifier table would change what the app *does*. A miss
///   is a failure of ambition; the other is a bug Scyther invented.
/// - A string carrying `.stringsdict` plural configuration is returned untouched, as the exact
///   object Foundation produced — see ``PseudoLocalizationTransform/carriesPluralConfiguration(_:)``.
/// - The swizzle is installed only while a text-affecting mode is on and removed the moment the
///   last one is switched off, so an app that never opens this screen never has its string
///   loading touched.
/// - It is never installed on an App Store build or under XCTest. That guard lives in
///   ``setEnabled(_:isTestCase:isAppStore:)`` itself rather than only in its caller, so the
///   guarantee holds for every route to the swizzle rather than for one of them.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Installing
/// - ``setEnabled(_:isTestCase:isAppStore:)``
/// - ``isInstalled``
///
/// ### Scope
/// - ``transforms(table:)``
/// - ``defaultTableName``
internal final class PseudoLocalizationHostHook: @unchecked Sendable {
    /// The shared hook. One instance, because the state it manages — a swizzled method on
    /// `NSBundle` — is itself process-wide and cannot meaningfully be installed twice.
    static let shared = PseudoLocalizationHostHook()

    /// Guards ``installed`` so ``setEnabled(_:)`` can be called from any thread without two
    /// callers racing to exchange the same pair of implementations, which would swizzle the method
    /// back to its original and leave the flag saying otherwise.
    private let lock = NSLock()

    /// Whether the swizzle is currently in place. Guarded by ``lock``.
    private var installed = false

    /// Private init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// The name Foundation gives the table `NSLocalizedString` uses when none is named.
    nonisolated static let defaultTableName = "Localizable"

    /// Whether a lookup in a given table should be transformed.
    ///
    /// `nil` and `"Localizable"` are the same table: `NSLocalizedString(key, comment:)` passes
    /// `nil`, while the four-argument form and some UIKit paths spell it out. Everything else is a
    /// table the app named on purpose, which is a good signal that its contents are not copy.
    ///
    /// - Parameter table: The table name from the lookup, or `nil`.
    /// - Returns: `true` for the default table only.
    nonisolated static func transforms(table: String?) -> Bool {
        table == nil || table == defaultTableName
    }

    /// Whether the swizzle is currently in place.
    internal var isInstalled: Bool {
        lock.withLock { installed }
    }

    /// Installs or removes the swizzle, idempotently.
    ///
    /// Idempotence is not a nicety here. `method_exchangeImplementations` is its own inverse, so
    /// installing twice would silently uninstall, and the developer would be left with a screen
    /// whose toggles say pseudo-localisation is on while the app renders normally.
    ///
    /// The production guard lives here rather than only in ``PseudoLocalization`` because this is
    /// where the promise is made: the type's own header, the README and the DocC article all say
    /// the swizzle is never installed on an App Store build or under XCTest, and a guarantee that
    /// holds only for one caller is not a guarantee. The two booleans are parameters, defaulted
    /// from ``AppEnvironment``, for the same reason
    /// ``PseudoLocalization/canAffectHostApp(isTestCase:isAppStore:)`` is a pure function: neither
    /// can be faked in the test host, so the tests that exercise the swizzle for real have to be
    /// able to say so explicitly.
    ///
    /// *Removal* is never guarded. If the swizzle is somehow in place, taking it back out must
    /// always be possible — refusing to uninstall on the grounds that installing would have been
    /// refused is how a build ends up stuck with it.
    ///
    /// - Parameters:
    ///   - enabled: `true` to install the swizzle, `false` to remove it.
    ///   - isTestCase: Whether the process is running under XCTest, per ``AppEnvironment/isTestCase``.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    internal func setEnabled(
        _ enabled: Bool,
        isTestCase: Bool = AppEnvironment.isTestCase,
        isAppStore: Bool = AppEnvironment.isAppStore
    ) {
        guard !enabled || PseudoLocalization.canAffectHostApp(isTestCase: isTestCase, isAppStore: isAppStore) else {
            return
        }
        lock.withLock {
            guard enabled != installed else { return }
            if enabled {
                swizzle(Bundle.self,
                        #selector(Bundle.localizedString(forKey:value:table:)),
                        #selector(Bundle.scyther_pseudoLocalizedString(forKey:value:table:)))
            } else {
                unswizzle(Bundle.self,
                          #selector(Bundle.localizedString(forKey:value:table:)),
                          #selector(Bundle.scyther_pseudoLocalizedString(forKey:value:table:)))
            }
            installed = enabled
        }
    }
}

internal extension Bundle {
    /// The replacement for `localizedString(forKey:value:table:)` while pseudo-localisation is on.
    ///
    /// The recursive-looking call is the swizzle: after the exchange this selector holds the
    /// original implementation, so calling it here runs Foundation's real lookup.
    ///
    /// Restricted to `Bundle.main` because everything else resolving a string through this method
    /// belongs to somebody else — UIKit's alert buttons, a dependency's internal table — and
    /// mangling those produces a broken app rather than a translated-looking one, which is not the
    /// question the developer is asking.
    ///
    /// It returns `NSString` rather than `String`, and hands back the *original object* whenever
    /// it decides not to transform. That is not a style choice: a `.stringsdict` lookup returns a
    /// format carrying plural configuration that `String.localizedStringWithFormat` later expands,
    /// and bridging through a Swift `String` and back produces a fresh, plain `NSString` with the
    /// configuration gone — so a hook that always rebuilt the string would break every plural in
    /// the host app whatever the modes said, including with all of them off.
    ///
    /// - Parameters:
    ///   - key: The catalog key being looked up.
    ///   - value: The fallback Foundation returns when the key is missing.
    ///   - table: The `.strings` table name, or `nil` for `Localizable`.
    /// - Returns: The pseudo-localised string, or the object Foundation produced, untouched.
    @objc dynamic func scyther_pseudoLocalizedString(forKey key: String, value: String?, table: String?) -> NSString {
        let resolved = scyther_pseudoLocalizedString(forKey: key, value: value, table: table)
        guard self === Bundle.main,
              PseudoLocalizationHostHook.transforms(table: table) else { return resolved }

        let transformed = PseudoLocalizationTransform.apply(
            to: resolved as String,
            key: key,
            modes: PseudoLocalization.instance.activeModes
        )
        guard transformed != resolved as String else { return resolved }
        return transformed as NSString
    }
}
#endif
