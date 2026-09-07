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
///    business doing. It is not the whole story for *Scyther's own* views, though, and the half
///    that was missing is a defect this shipped with: see below.
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
/// ## Why the appearance proxy can never undo itself
///
/// The UIKit half shipped with a defect that took a while to see, because it looks like the proxy
/// is symmetrical and it is not. `UIView.appearance()` does not *govern* a view; it *stamps* one.
/// The value is copied onto each view as it is added to a window, and it stays on that view for
/// the rest of its life. Setting the proxy back therefore changes nothing that already exists:
/// switching the mode off left every view built while it was on holding `.forceRightToLeft`, and a
/// developer who switched right-to-left on, off, and navigated back to the menu found it still
/// mirrored until the process was relaunched.
///
/// Measured on a simulator rather than reasoned about, since this feature has a history of the
/// second: with the proxy set to `.forceRightToLeft`, a view added to a window reads back
/// `.forceRightToLeft`, and still reads back `.forceRightToLeft` after the proxy is reset to
/// `.unspecified` and the window is reset and laid out again. A `UINavigationBar` and a
/// `UIHostingController`'s view behave the same way. Resetting the window is not enough either,
/// because the stamp is on each view rather than inherited from an ancestor — which cuts the other
/// way too, and usefully: a view set back to `.unspecified` lays out left-to-right even while its
/// superview is still forced right-to-left, so only the views that were stamped have to be found.
///
/// ``applyToOwnedViews(rightToLeft:in:)`` is the answer, and it is deliberately narrow. Scyther
/// resets the views *Scyther owns* — its menu, everything presented from it, and its overlays —
/// because those it is entitled to reach into. The host app's views are left to the proxy and the
/// next launch, exactly as documented, and the walk reads them only to find its own.
///
/// Testing ``apply(rightToLeft:allowed:)`` itself is honest only up to a point, and the point is
/// `UIView.appearance()`: it is process-wide state with no reliable way to read the applied value
/// back, and `ScytherTests` has no host app whose windows could be inspected. It is therefore
/// driven only through ``attribute(rightToLeft:)`` and ``applyToOwnedViews(rightToLeft:in:)``,
/// which are pure enough to be tested against a hierarchy built by hand — which is what the view
/// walk is tested against.
///
/// ## Topics
///
/// ### Deciding
/// - ``layoutDirection(forcingRightToLeft:languageIdentifier:)``
/// - ``attribute(rightToLeft:)``
///
/// ### Applying
/// - ``apply(rightToLeft:allowed:)``
/// - ``applyToOwnedViews(rightToLeft:in:)``
/// - ``isScytherOwned(_:)``
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
    /// It then hands off to ``applyToOwnedViews(rightToLeft:in:)`` for the views Scyther itself
    /// owns, which the proxy cannot help with in either direction — it stamps a view once, as the
    /// view joins a window, and never revisits it. Nothing about the host app changes because of
    /// that step.
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
        var windows: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.semanticContentAttribute = attribute
                window.setNeedsLayout()
                windows.append(window)
            }
        }
        applyToOwnedViews(rightToLeft: rightToLeft, in: windows)
    }

    /// Puts the views *Scyther* owns into the direction the mode now calls for, instead of waiting
    /// for them to be built again.
    ///
    /// This is the half of the UIKit story the proxy cannot do, in either direction. Off is the
    /// case that shipped broken — a mirrored menu that stayed mirrored for the rest of the session
    /// — and on had the same weakness wearing better clothes: it happened to look right only
    /// because a developer switching it on usually navigates somewhere afterwards, and the views
    /// they arrive at are new. Both directions now go through here, so both behave the same and
    /// neither depends on when a view happened to be created.
    ///
    /// The walk descends from `roots`, and the only views it *writes* to are Scyther's own: a
    /// subtree recognised by ``isScytherOwned(_:)`` is stamped whole and not descended into again,
    /// and everything else is passed over and its subviews examined instead. The host app's views
    /// are read to find Scyther's and never written, which is the line this feature draws
    /// everywhere else too: the app's UIKit views mirror through the appearance proxy on their next
    /// launch, and its SwiftUI views not at all.
    ///
    /// Each stamped view is marked for layout and each owned root is laid out immediately, because
    /// the point of the fix is that the screen the developer is looking at changes *now*. Without
    /// the forced pass the attribute would sit correct-but-unrendered until something else
    /// invalidated the layout, which on a menu nobody is scrolling is indefinitely.
    ///
    /// Cost is a full descent of the window's view tree with a responder climb per view, which is
    /// far too much to do per frame and entirely fine here: it runs when a switch moves, and the
    /// alternative — tracking every view Scyther creates — would be a registry to keep correct
    /// forever in exchange for microseconds nobody is waiting on.
    ///
    /// Carries no production guard of its own, unlike ``apply(rightToLeft:allowed:)``: it writes
    /// only to views Scyther owns, which on an App Store build do not exist, and its caller has
    /// already refused. Not carrying one is also what makes it testable — the XCTest half of that
    /// guard would otherwise make every test below assert that nothing happened.
    ///
    /// - Parameters:
    ///   - rightToLeft: Whether right-to-left is being forced.
    ///   - roots: The views to descend from. In production the app's windows; in a test, a
    ///     hierarchy built by hand.
    internal static func applyToOwnedViews(rightToLeft: Bool, in roots: [UIView]) {
        let attribute = attribute(rightToLeft: rightToLeft)
        for root in roots {
            applyToOwnedSubtrees(of: root, attribute: attribute)
        }
    }

    /// Finds Scyther's own subtrees below `view` and stamps them.
    ///
    /// Stops descending the moment it finds one, because everything inside a view of Scyther's is
    /// Scyther's too and asking again per descendant would be the same answer bought at the price
    /// of a responder climb each time.
    ///
    /// - Parameters:
    ///   - view: The view to examine.
    ///   - attribute: The attribute to stamp onto anything owned.
    private static func applyToOwnedSubtrees(of view: UIView, attribute: UISemanticContentAttribute) {
        if isScytherOwned(view) {
            stamp(view, with: attribute)
            view.layoutIfNeeded()
            return
        }
        for subview in view.subviews {
            applyToOwnedSubtrees(of: subview, attribute: attribute)
        }
    }

    /// Sets `attribute` on `view` and everything below it.
    ///
    /// Every descendant, not just the root, because the stamp the appearance proxy leaves is on
    /// each view individually rather than inherited: a subtree whose root alone was reset would
    /// keep every mirrored label, button and image view it already had.
    ///
    /// - Parameters:
    ///   - view: The root of the subtree to stamp.
    ///   - attribute: The attribute to apply.
    private static func stamp(_ view: UIView, with attribute: UISemanticContentAttribute) {
        view.semanticContentAttribute = attribute
        view.setNeedsLayout()
        for subview in view.subviews {
            stamp(subview, with: attribute)
        }
    }

    /// Whether a view belongs to Scyther rather than to the app being debugged.
    ///
    /// Two questions, because Scyther's UI arrives on screen two ways. `isScytherOwnedType(_:)` —
    /// the same rule the accessibility audit uses, deliberately shared rather than restated —
    /// catches the overlays Scyther installs straight into the app's key window, which are its own
    /// classes and have no view controller. The controller question catches everything Scyther
    /// *presents*, whose views are SwiftUI's `_UIHostingView` and name Scyther nowhere; they are
    /// recognised by the controller that owns them instead.
    ///
    /// Ownership is asked of the controller through ``ScytherPresentation/containsScytherUI(_:)``
    /// rather than by testing it against ``ScytherPresentedUI`` directly, and that is what makes
    /// the menu's navigation bar come with it: `Scyther.showMenu(from:)` presents a stock
    /// `UINavigationController` whose child is the ``ScytherHostingController``, so the navigation
    /// bar's owning controller is a UIKit container and only its children give it away. A
    /// navigation bar left mirrored above an un-mirrored list would be a half-fix a developer
    /// would report as the same bug.
    ///
    /// - Parameter view: The view to test.
    /// - Returns: `true` when the view is Scyther's own.
    internal static func isScytherOwned(_ view: UIView) -> Bool {
        if isScytherOwnedType(view) { return true }
        guard let controller = owningController(of: view) else { return false }
        return ScytherPresentation.containsScytherUI(controller)
    }

    /// How far ``owningController(of:)`` climbs before giving up.
    ///
    /// A responder chain is not cyclic, so this is belt-and-braces of the same kind
    /// ``ScytherPresentation`` and ``AuditNode`` already keep — and it costs one integer compare
    /// per link of a walk that runs once per view on a screen.
    private static let maximumResponderSteps = 100

    /// The view controller a view belongs to, if any.
    ///
    /// Climbs the *responder* chain rather than `superview`, which is the whole trick:
    /// `UIResponder.next` hands back a view's owning view controller when the view is that
    /// controller's root view and its superview otherwise, so one loop crosses from the deepest
    /// label in a SwiftUI list up to the controller hosting it. A `superview` walk would stop at
    /// the hosting view and never reach the marker that identifies it as Scyther's.
    ///
    /// Stops as soon as the chain leaves views and controllers — at a `UIWindowScene`, and beyond
    /// it `UIApplication` and the app's delegate — because those belong to the app.
    ///
    /// - Parameter view: The view to resolve an owner for.
    /// - Returns: The owning controller, or `nil` when the chain runs out first.
    private static func owningController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view.next
        var steps = 0
        while let current = responder, steps < maximumResponderSteps {
            if let controller = current as? UIViewController { return controller }
            guard current is UIView else { return nil }
            responder = current.next
            steps += 1
        }
        return nil
    }
}
#endif
