//
//  PseudoLocalizationLayout.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import Foundation
import SwiftUI

/// Decides the layout direction Scyther's own interface is laid out in, without switching it to an
/// RTL language.
///
/// Separated from ``PseudoLocalization`` because right-to-left is not a string transformation at
/// all: no character changes, and none of the string plumbing in this feature is involved.
///
/// Two halves, with two different timescales, and the split is the honest shape of the problem.
/// ``layoutDirection(forcingRightToLeft:languageIdentifier:)`` decides the value ``MenuView`` and
/// ``PseudoLocalizationView`` install as `\.layoutDirection`, which mirrors *Scyther's own
/// interface* the instant the switch moves and un-mirrors it the instant it moves back.
/// ``applyToHostApp(rightToLeft:isTestCase:isAppStore:systemDefaults:)`` writes the two defaults
/// keys iOS reads at launch, which mirrors *the host app* — all of it, UIKit and SwiftUI alike —
/// on its next launch.
///
/// ## What used to be here, and why it is gone
///
/// A third mechanism used to set `UIView.appearance().semanticContentAttribute`. It is deleted,
/// and the reasoning is worth keeping so it is not reintroduced.
///
/// The appearance proxy does not govern a view, it *stamps* one: the value is copied onto each
/// view as the view joins a window and is never revisited, so setting the proxy back cannot undo a
/// view that already exists. Everything built while the mode was on kept forcing right-to-left
/// after the mode was switched off — including the views inside Scyther's own menu — and a
/// leftover stamp does not merely mirror a layout. It *disagrees* with the SwiftUI environment
/// around it, and UIKit answers a disagreement by mirroring content SwiftUI has already laid out
/// the other way, which is text drawn backwards: `Fonts` rendered as `stnoF`.
///
/// Three attempts were made to clean up after the stamp — reset the windows, reset the views
/// Scyther owns, reset the views inside its hosting views — and every one left the menu unreadable
/// on a device while every unit test passed, because an attribute holding the value a test asked
/// for is not evidence that the screen is legible. The residue cannot be chased to zero either: a
/// recycled cell that is off-screen when the switch moves carries its stamp back on with it.
///
/// It also never reached a SwiftUI host app at all, so what it cost in corruption it did not even
/// buy in coverage. Nothing is stamped any more, nothing needs unstamping, and the mismatch that
/// reversed the glyphs cannot occur in either direction.
///
/// ## Why the defaults keys instead
///
/// Because they do the thing the proxy could not: they are resolved at launch, before any view
/// exists, and they reach **both** frameworks. `AppleTextDirection` and
/// `NSForceRightToLeftWritingDirection` are what Xcode's own **Edit Scheme → Run → Options → App
/// Language → Right to Left Pseudolanguage** passes on the command line, and writing them into the
/// host's standard `UserDefaults` is the same move ``LanguageOverride`` already makes with
/// `AppleLanguages` — an established pattern in this package rather than a new liberty.
///
/// The trade is timing, and it is stated on the toggle rather than buried here: Scyther's own UI
/// changes now, the developer's app changes on its next launch. An asymmetry nobody explains is a
/// bug report.
///
/// ## Topics
///
/// ### Deciding
/// - ``layoutDirection(forcingRightToLeft:languageIdentifier:)``
///
/// ### Reaching the host app
/// - ``applyToHostApp(rightToLeft:isTestCase:isAppStore:systemDefaults:)``
/// - ``textDirectionDefaultsKey``
/// - ``forceRightToLeftDefaultsKey``
internal enum PseudoLocalizationLayout {
    /// The layout direction Scyther's own SwiftUI interface should be laid out in.
    ///
    /// SwiftUI takes its direction from the environment, so the value has to be *decided* where
    /// the environment is installed rather than *forced onto* a view that has already been built.
    /// That is why this is the half that has been correct since the first version, while the one
    /// that tried to force an attribute onto existing views never was.
    ///
    /// The forced mode wins over the language. That ordering is the point — a developer switching
    /// the mode on is asking to see the layout mirrored *without* changing language, and a
    /// language-derived direction that quietly overruled them is exactly the bug this replaced.
    /// With the mode off the language decides, as it did before, so an Arabic override still lays
    /// the menu out right to left on its own.
    ///
    /// - Parameters:
    ///   - forcingRightToLeft: Whether ``PseudoLocalizationMode/rightToLeft`` is switched on.
    ///   - languageIdentifier: The identifier of the language Scyther is rendering in, from
    ///     ``LanguageOverride/namingLocale``.
    /// - Returns: The direction to install as `\.layoutDirection`.
    internal static func layoutDirection(
        forcingRightToLeft: Bool,
        languageIdentifier: String
    ) -> LayoutDirection {
        if forcingRightToLeft { return .rightToLeft }
        return Locale.Language(identifier: languageIdentifier).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

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
