//
//  PseudoLocalizationLayout.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import SwiftUI
import UIKit

/// Forces the host app's layout direction, without switching it to an RTL language.
///
/// Separated from ``PseudoLocalization`` because right-to-left is not a string transformation at
/// all: no character changes, and none of the string plumbing in this feature is involved. It is a
/// UIKit semantic attribute, which is also why it is the one mode with no gap between Scyther's
/// interface and the host app's — it does not care how the app loads its copy.
///
/// ## Two halves, and only one of them is immediate
///
/// The first draft of this type had only the UIKit half, and switching the mode on visibly did
/// nothing at all — not in the host app, not even in Scyther's own menu. Two reasons, both worth
/// recording so the mistake is not repeated:
///
/// 1. `UIView.appearance()` applies to views created *after* it changes, so nothing already on
///    screen moves. That is inherent to the appearance proxy, and working around it would mean
///    tearing down and rebuilding the host app's view hierarchy, which a debug toolkit has no
///    business doing.
/// 2. SwiftUI does not consult the appearance proxy at all. Its direction comes from the
///    `\.layoutDirection` environment value — and ``MenuView`` *sets* that value explicitly, from
///    the language override, so Scyther's own interface was pinned left-to-right by Scyther's own
///    code no matter what the proxy said.
///
/// The mode therefore has two halves. ``layoutDirection(forcingRightToLeft:languageIdentifier:)``
/// is the SwiftUI half: it decides the environment value ``MenuView`` and ``PseudoLocalizationView``
/// install, which is what makes Scyther's own interface flip the instant the switch moves. It is
/// pure, and it is tested. ``apply(rightToLeft:allowed:)`` is the UIKit half: it reaches the host
/// app's UIKit views on the next launch, and its SwiftUI views not at all.
///
/// ## What would reach a SwiftUI host app, and what it would cost
///
/// Nothing here can, and the reason is structural rather than a missing trick: a SwiftUI view's
/// direction comes from `\.layoutDirection` in *its own* environment, which the host app owns.
/// There is no public API for a library to modify another view tree's environment, and the
/// appearance proxy — measured, twice — does not seed it.
///
/// One route does exist and is deliberately *not* taken. Xcode's own "Right to Left
/// Pseudolanguage" scheme option works by launching the process with `-AppleTextDirection YES` and
/// `-NSForceRightToLeftWritingDirection YES`, which are resolved at launch and do reach SwiftUI.
/// Scyther could write those into the host's standard `UserDefaults` the same way
/// ``LanguageOverride`` already writes `AppleLanguages`, and they would take effect on the next
/// launch. The cost is why it is not built: it writes into the host app's own defaults domain for
/// a second reason, it is undocumented as a defaults key rather than a launch argument, it cannot
/// be undone within the session that set it, and — the decisive one — nothing in this repository
/// can verify it, since `ScytherTests` has no host app and the example app would have to be driven
/// by hand. This feature has already shipped three claims about reach that were reasoned from
/// mechanism and turned out to be wrong on a simulator. A fourth, resting on an undocumented
/// defaults key, is not worth an accurate limit.
///
/// Testing the UIKit half is honest only up to a point, and the point is `UIView.appearance()`: it
/// is process-wide state with no reliable way to read the applied value back, and `ScytherTests`
/// has no host app whose windows could be inspected. It is therefore driven only through
/// ``attribute(rightToLeft:)``, which is pure and is tested.
///
/// ## Topics
///
/// ### Deciding
/// - ``layoutDirection(forcingRightToLeft:languageIdentifier:)``
/// - ``attribute(rightToLeft:)``
///
/// ### Applying
/// - ``apply(rightToLeft:allowed:)``
@MainActor
internal enum PseudoLocalizationLayout {
    /// The layout direction Scyther's own SwiftUI interface should be laid out in.
    ///
    /// This is the half of the mode that works immediately, and it is the only half that can:
    /// SwiftUI takes its direction from the environment, so the value has to be *decided* where
    /// the environment is installed rather than *forced onto* a view that has already been built.
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

    /// The semantic content attribute matching a switch position.
    ///
    /// `.unspecified` rather than `.forceLeftToRight` for the off case, so switching the mode off
    /// hands the decision back to the user's actual language instead of pinning a genuinely
    /// Arabic or Hebrew device to left-to-right — which would be a worse bug than the one the
    /// mode exists to find.
    ///
    /// - Parameter rightToLeft: Whether right-to-left is being forced.
    /// - Returns: The attribute to apply.
    internal static func attribute(rightToLeft: Bool) -> UISemanticContentAttribute {
        rightToLeft ? .forceRightToLeft : .unspecified
    }

    /// Applies the layout direction to the appearance proxy and to the windows already on screen,
    /// for the *host app*.
    ///
    /// Described in deliberately weaker terms than the SwiftUI half, because it is weaker, and the
    /// first version of this feature shipped a toggle whose subtitle promised what only this half
    /// could deliver — which, on the screens anyone actually looked at, was nothing.
    ///
    /// What it does: sets the proxy, so UIKit views the host app creates from now on are laid out
    /// mirrored, and sets the attribute on the existing windows, which flips UIKit content already
    /// on screen. What it does not do: move a SwiftUI view. SwiftUI reads `\.layoutDirection` from
    /// its environment, seeded when its hosting view was built, and nothing here reaches back into
    /// it.
    ///
    /// A relaunch makes the UIKit half complete but no more than that.
    /// ``PseudoLocalization/setup()`` sets the proxy from `Scyther.start(allowProductionBuilds:)`,
    /// before any of the app's views exist, so every *UIKit* view is built mirrored. A SwiftUI
    /// view is not, measured on a simulator after a relaunch with the switch left on: SwiftUI does
    /// not consult the proxy at any point in its life, so being early does not help.
    ///
    /// This is the one part of the mode whose behaviour has not been observed directly here, and
    /// it should be read as such: the example app is SwiftUI, so what a relaunch does for a UIKit
    /// host rests on documented appearance-proxy behaviour rather than on a screenshot. The
    /// difference is why the surface table in the DocC article marks which rows were checked.
    ///
    /// Like ``PseudoLocalizationHostHook/setEnabled(_:isTestCase:isAppStore:)``, it carries the
    /// production guard itself rather than trusting its caller, because the promise that Scyther
    /// never forces a shipping app's layout direction is made about this function.
    ///
    /// The XCTest half of the guard has no injection seam, unlike the hook's. There is nothing a
    /// test could usefully do with it: there is no host app whose windows could be flipped, and
    /// `UIView.appearance()` is process-wide state a test has no reliable way to restore for the
    /// tests that run after it.
    ///
    /// - Parameters:
    ///   - rightToLeft: Whether to force right-to-left layout.
    ///   - allowed: Whether the host app may be touched at all, per
    ///     ``PseudoLocalization/canAffectHostApp(isTestCase:isAppStore:)``.
    internal static func apply(rightToLeft: Bool, allowed: Bool = true) {
        guard allowed, !AppEnvironment.isTestCase, !AppEnvironment.isAppStore else { return }
        let attribute = attribute(rightToLeft: rightToLeft)
        UIView.appearance().semanticContentAttribute = attribute
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.semanticContentAttribute = attribute
                window.setNeedsLayout()
            }
        }
    }
}
#endif
