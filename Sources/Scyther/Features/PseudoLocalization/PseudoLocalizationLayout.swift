//
//  PseudoLocalizationLayout.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import Foundation

/// Forces the host app's layout direction, without switching it to an RTL language.
///
/// Separated from ``PseudoLocalization`` because right-to-left is not a string transformation at
/// all: no character changes, and none of the string plumbing in this feature is involved. What it
/// is instead is a *launch* setting — two keys in the host app's standard `UserDefaults`, read by
/// iOS while the process starts, reaching UIKit and SwiftUI alike.
///
/// ## Why nothing happens until a relaunch
///
/// This mode has been rebuilt four times, and every version that changed something mid-session
/// corrupted the screen in the same way. The record is short and worth keeping:
///
/// 1. `UIView.appearance().semanticContentAttribute` stamps a view once, as the view joins a
///    window, and never revisits it — so switching the mode off could not undo the views already
///    stamped, and it never reached a SwiftUI view at all.
/// 2. Three attempts to clear those stamps afterwards each left Scyther's menu rendering its
///    labels backwards — `Fonts` as `stnoF` — while every unit test passed, because an attribute
///    holding the value a test asked for says nothing about whether the screen is legible.
/// 3. Writing these two defaults keys fixed the reach but not the timing. They apply to UIKit's
///    text rendering *live*, so switching on agreed with the SwiftUI environment value Scyther
///    installed in its own views and looked right — while removing them does **not** un-apply
///    live, so switching off left UIKit right-to-left under an environment that had flipped back,
///    and the labels reversed again.
///
/// One thing is common to all three: a *disagreement*, inside one session, between something that
/// changed immediately and something that did not. UIKit answers that disagreement by mirroring
/// content that has already been laid out the other way, which is text drawn backwards.
///
/// So nothing changes mid-session. The keys are written or removed when the switch moves, and no
/// surface — the host app's, or Scyther's own menu and page — is asked to move with them. At the
/// next launch every surface reads the same keys and agrees by construction, which was measured on
/// a device in both directions: relaunched with the keys present the app is mirrored and readable,
/// relaunched with them absent it is left-to-right and readable.
///
/// That is also exactly how Xcode's own **Edit Scheme → Run → Options → App Language → Right to
/// Left Pseudolanguage** behaves, which is where these keys come from. A developer who already
/// knows that option will find nothing surprising here.
///
/// The cost is the immediate feedback, and it is worth paying. An unreadable debug menu is a worse
/// failure than a relaunch, and every attempt to avoid the relaunch produced the same corruption
/// by a different route.
///
/// The one thing Scyther's interface still does immediately is follow a *language* override's
/// direction, which is a different input with no launch-time half to disagree with — see
/// ``LanguageOverride/layoutDirection(forLanguage:)``.
///
/// ## Topics
///
/// ### Reaching the host app
/// - ``applyToHostApp(rightToLeft:isTestCase:isAppStore:systemDefaults:)``
/// - ``textDirectionDefaultsKey``
/// - ``forceRightToLeftDefaultsKey``
internal enum PseudoLocalizationLayout {
    /// The standard-defaults key iOS reads at launch to decide the app's text direction.
    ///
    /// Undocumented as a defaults key — Xcode passes it as the launch argument
    /// `-AppleTextDirection YES` — but it is read from the standard domain the same way
    /// `AppleLanguages` is, which is what makes it reachable from inside the process rather than
    /// only from a scheme.
    internal static let textDirectionDefaultsKey = "AppleTextDirection"

    /// The standard-defaults key iOS reads at launch to force right-to-left writing.
    ///
    /// Written alongside ``textDirectionDefaultsKey`` because Xcode's scheme option sets both, and
    /// setting one without the other is a state the system is never asked for in practice.
    internal static let forceRightToLeftDefaultsKey = "NSForceRightToLeftWritingDirection"

    /// Mirrors the *host app* — UIKit and SwiftUI alike — from its next launch, or stops doing so.
    ///
    /// This is the half that makes the mode worth having. Pseudo-localisation exists to test the
    /// developer's app, and a right-to-left mode that mirrored only Scyther's own menu would test
    /// nothing anybody ships. What it costs is immediacy: the two keys are read once, while the
    /// process is starting, so nothing about the running app moves when the switch does.
    ///
    /// ## Reversibility
    ///
    /// Switching off **removes** the keys rather than writing `false`, and that is deliberate
    /// rather than tidy. A developer who tries this once must be able to get their app back, and a
    /// key left behind holding `false` is a Scyther-shaped value sitting in their app's defaults
    /// for good — the sort of thing that is found months later while debugging something else.
    /// Removal restores the state the app was in before Scyther was ever asked, and it takes
    /// effect on the next launch in exactly the way switching on does.
    ///
    /// ``LanguageOverride/reset()`` removes `AppleLanguages` for the same reason.
    ///
    /// ## The guard, and the one place it lets a write through
    ///
    /// Carried here rather than trusted to the caller, matching
    /// ``PseudoLocalizationHostHook/setEnabled(_:isTestCase:isAppStore:)``: the promise that
    /// Scyther never leaves a shipping app mirrored is made about this function, so this function
    /// keeps it. Under XCTest there is no host app to mirror and writing to the standard domain
    /// would leak into unrelated tests in the same process, so nothing happens at all.
    ///
    /// An App Store build refuses to *set* the keys and still *removes* them, which is not an
    /// oversight. ``PseudoLocalization/resolvedModes(stored:isAppStore:)`` reports no modes on such
    /// a build, so the only call that can arrive is the off case — and a switch left on in a
    /// TestFlight build, carried into a store build through the same preferences file, is exactly
    /// the situation where the keys need clearing rather than preserving. Refusing to remove them
    /// would leave a real user's app mirrored with no way to reach the switch that did it.
    ///
    /// - Parameters:
    ///   - rightToLeft: Whether right-to-left is being forced.
    ///   - isTestCase: Whether the process is running under XCTest, per ``AppEnvironment/isTestCase``.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    ///   - systemDefaults: Where the keys are written. Defaults to `.standard`, which is the host
    ///     app's own domain; injected so a test can assert on a throwaway suite instead.
    internal static func applyToHostApp(
        rightToLeft: Bool,
        isTestCase: Bool = AppEnvironment.isTestCase,
        isAppStore: Bool = AppEnvironment.isAppStore,
        systemDefaults: UserDefaults = .standard
    ) {
        guard !isTestCase else { return }
        guard rightToLeft else {
            systemDefaults.removeObject(forKey: textDirectionDefaultsKey)
            systemDefaults.removeObject(forKey: forceRightToLeftDefaultsKey)
            return
        }
        guard PseudoLocalization.canAffectHostApp(
            isTestCase: isTestCase,
            isAppStore: isAppStore
        ) else { return }
        systemDefaults.set(true, forKey: textDirectionDefaultsKey)
        systemDefaults.set(true, forKey: forceRightToLeftDefaultsKey)
    }
}
#endif
