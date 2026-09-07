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
/// - Only `Bundle.main` is transformed. Framework and system bundles resolve normally, so UIKit's
///   own "Cancel" and "Done" — and any string a dependency uses as an identifier rather than as
///   copy — are left exactly as they were.
/// - The swizzle is installed only while a text-affecting mode is on and removed the moment the
///   last one is switched off, so an app that never opens this screen never has its string
///   loading touched.
/// - It is never installed on an App Store build or under XCTest; see
///   ``PseudoLocalization/canAffectHostApp(isTestCase:isAppStore:)``.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Installing
/// - ``setEnabled(_:)``
/// - ``isInstalled``
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
    /// - Parameter enabled: `true` to install the swizzle, `false` to remove it.
    internal func setEnabled(_ enabled: Bool) {
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
    /// - Parameters:
    ///   - key: The catalog key being looked up.
    ///   - value: The fallback Foundation returns when the key is missing.
    ///   - table: The `.strings` table name, or `nil` for `Localizable`.
    /// - Returns: The pseudo-localised string for the main bundle, the untouched string otherwise.
    @objc dynamic func scyther_pseudoLocalizedString(forKey key: String, value: String?, table: String?) -> String {
        let resolved = scyther_pseudoLocalizedString(forKey: key, value: value, table: table)
        guard self === Bundle.main else { return resolved }
        return PseudoLocalizationTransform.apply(
            to: resolved,
            key: key,
            modes: PseudoLocalization.instance.activeModes
        )
    }
}
#endif
