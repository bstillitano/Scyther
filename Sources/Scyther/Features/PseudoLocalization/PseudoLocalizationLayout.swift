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
/// ``clearForcedDirection(in:)`` is the answer, and it is narrow in two ways that matter. It runs
/// on the way *off* only, and the only value it ever writes is `.unspecified`, to a view of
/// Scyther's that currently reads `.forceRightToLeft`. It never forces a direction onto anything.
///
/// ## Why it does nothing on the way on
///
/// Because forcing the attribute onto Scyther's own views broke the rendering, which is worth
/// recording precisely. Switching the mode on already worked through the environment half, and
/// adding the UIKit half to the same views gave them two signals saying the same thing. A hosting
/// view told to force a direction mirrors what it *renders* rather than reordering what it lays
/// out, so the menu came back with every label reversed glyph by glyph — `Fonts` drawn as `stnoF`
/// — while every unit test still passed, because the attribute values were exactly what the tests
/// asked for. An attribute being set is not evidence that the result is readable. Switching on is
/// therefore left entirely to the environment half, which is where it always worked.
///
/// The same mismatch, from the other side, is what the off direction has to repair: a stamp left
/// behind there forces right-to-left on a view whose contents SwiftUI has since laid out
/// left-to-right, and UIKit mirrors the difference. Clearing the stamp removes one of the two
/// signals; forcing one adds a second. Only the first is ever done here.
///
/// Testing ``apply(rightToLeft:allowed:)`` itself is honest only up to a point, and the point is
/// `UIView.appearance()`: it is process-wide state with no reliable way to read the applied value
/// back, and `ScytherTests` has no host app whose windows could be inspected. It is therefore
/// driven only through ``attribute(rightToLeft:)`` and ``clearForcedDirection(in:)``, which are
/// pure enough to be tested against a hierarchy built by hand. What those tests can prove is
/// bounded, and this file has now been the proof: they can say which attribute a view carries;
/// they cannot say what the screen looks like.
///
/// ## Topics
///
/// ### Deciding
/// - ``layoutDirection(forcingRightToLeft:languageIdentifier:)``
/// - ``attribute(rightToLeft:)``
///
/// ### Applying
/// - ``apply(rightToLeft:allowed:)``
/// - ``clearForcedDirection(in:)``
/// - ``role(of:)``
/// - ``ViewRole``
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
    /// On the way *off* it then hands to ``clearForcedDirection(in:)``, which takes the proxy's
    /// stamp back off the UIKit chrome Scyther owns — the proxy cannot do that itself, since it
    /// stamps a view once as the view joins a window and never revisits it. There is no matching
    /// step on the way on: forcing the attribute onto Scyther's own views is what made a hosting
    /// view mirror its rendered text, and the environment half already flips Scyther's interface
    /// the moment the switch moves. Nothing about the host app changes because of either.
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
        guard !rightToLeft else { return }
        clearForcedDirection(in: windows)
    }

    /// Clears the forced direction the appearance proxy stamped onto Scyther's own UIKit chrome
    /// while the mode was on.
    ///
    /// ## Why only this direction, and only a clear
    ///
    /// The two directions are not symmetric, and an earlier attempt to make them symmetric was
    /// worse than the bug it replaced. Switching the mode **on** already works, through the
    /// `\.layoutDirection` environment value ``MenuView`` and ``PseudoLocalizationView`` install:
    /// Scyther's interface mirrors the instant the switch moves and its text stays readable.
    /// Forcing `.forceRightToLeft` onto Scyther's view tree as well added a second, contradictory
    /// signal to the same views, and a hosting view told to force a direction mirrors what it
    /// *renders* rather than reordering what it lays out: on a device the menu came back with
    /// every label reversed glyph by glyph — `Fonts` as `stnoF` — which no assertion about an
    /// attribute value can detect. So nothing here forces anything on. Switching on is left
    /// entirely to the environment half.
    ///
    /// Switching **off** is the half that genuinely needed fixing, because the proxy cannot undo
    /// itself: it stamps `.forceRightToLeft` onto each view as the view joins a window and never
    /// revisits it, so views built while the mode was on keep forcing a direction the environment
    /// has already left behind. The repair is to take the stamp back off, which is all this does —
    /// write `.unspecified` to a view of Scyther's that currently reads `.forceRightToLeft`, and
    /// nothing else. A view holding any other value was never stamped by this feature and is left
    /// exactly as it is.
    ///
    /// ## Why it reaches inside the hosting view, and why that is safe
    ///
    /// Because that is where the damage was. Measured on a device across the two states: with the
    /// mode **on**, the environment and the stamp agree that everything is right-to-left and the
    /// menu is mirrored and perfectly readable. With the mode **off**, the environment has flipped
    /// back to left-to-right while the collection view backing the `List` is still stamped
    /// `.forceRightToLeft`, and UIKit mirrors content SwiftUI has already laid out the other way —
    /// which is text drawn backwards, `Fonts` as `stnoF`. The reversal is the *mismatch*, not the
    /// stamp on its own, which is why only the off direction was ever broken.
    ///
    /// So the stamps inside a hosting view are cleared like any others, and the rule that keeps
    /// this safe is the narrow one: never *set* `.forceRightToLeft` on anything, in either
    /// direction. Removing a forced direction leaves the view where a view built with the mode off
    /// would have been, and restores the agreement between the two halves. Imposing one is what
    /// made a hosting view mirror its own rendering, and nothing here does it.
    ///
    /// The chrome around the hosting view is cleared too — the navigation controller Scyther's
    /// menu is presented in, its navigation bar, and the overlays Scyther installs straight into
    /// the app's key window.
    ///
    /// The host app's views are read to find Scyther's and never written, in either direction. Its
    /// UIKit views still mirror on the next launch and un-mirror on the one after, through the
    /// proxy alone, and its SwiftUI views still never.
    ///
    /// Cost is a descent of the window's view tree with a responder climb per view. Far too much
    /// per frame, entirely fine when a switch moves.
    ///
    /// Carries no production guard of its own, unlike ``apply(rightToLeft:allowed:)``: it writes
    /// only to views Scyther owns, which on an App Store build do not exist, and its caller has
    /// already refused. Not carrying one is also what makes it testable — the XCTest half of that
    /// guard would otherwise make every test of it assert that nothing happened.
    ///
    /// - Parameter roots: The views to descend from. In production the app's windows; in a test, a
    ///   hierarchy built by hand.
    internal static func clearForcedDirection(in roots: [UIView]) {
        for root in roots {
            clearForcedDirection(below: root)
            root.layoutIfNeeded()
        }
    }

    /// Clears `view` if it qualifies, then examines its subviews.
    ///
    /// Every view is asked individually rather than a subtree being cleared wholesale once its
    /// root qualifies. That is the difference between undoing a stamp and applying one: this walk
    /// must be able to leave a view exactly as it found it, and a subtree sweep cannot, because it
    /// would also write to views the proxy never stamped.
    ///
    /// - Parameter view: The view to examine.
    private static func clearForcedDirection(below view: UIView) {
        if role(of: view).isScythers, view.semanticContentAttribute == .forceRightToLeft {
            view.semanticContentAttribute = .unspecified
            view.setNeedsLayout()
        }
        for subview in view.subviews {
            clearForcedDirection(below: subview)
        }
    }

    /// What a view is, as far as clearing a forced direction is concerned.
    ///
    /// Three cases rather than a boolean because the two Scyther ones are recognised by different
    /// evidence and are worth telling apart when reading a hierarchy — but they are cleared
    /// identically, and deliberately so. A stamp inside a hosting view is the same stamp,
    /// left by the same proxy, and it was the one doing the damage.
    ///
    /// ## Topics
    ///
    /// ### Cases
    /// - ``swiftUIHosted``
    /// - ``scytherChrome``
    /// - ``foreign``
    ///
    /// ### Deciding
    /// - ``isScythers``
    internal enum ViewRole {
        /// A view SwiftUI hosts for Scyther: the hosting view of a presented screen, and
        /// everything the proxy stamped inside it — the collection view backing a `List`, its
        /// cells, and whatever else was created while the mode was on.
        ///
        /// Cleared, never forced. The distinction is the whole of what went wrong on this
        /// feature: *setting* `.forceRightToLeft` on a hosted view while SwiftUI's environment
        /// says left-to-right makes UIKit mirror content SwiftUI has already laid out, which
        /// renders text backwards — `Fonts` as `stnoF`. *Removing* that stamp is the repair for
        /// exactly that mismatch, which is why this walk only ever writes `.unspecified`.
        case swiftUIHosted

        /// Scyther's own UIKit chrome: its overlays, and the containers around a screen it
        /// presents.
        case scytherChrome

        /// A view belonging to the app being debugged.
        ///
        /// Read to find Scyther's own, never written to. Its direction is the appearance proxy's
        /// business and the next launch's.
        case foreign

        /// Whether a `.forceRightToLeft` stamp on a view with this role is Scyther's to remove.
        internal var isScythers: Bool { self != .foreign }
    }

    /// Which of the three a view is.
    ///
    /// Answered from the *responder chain* rather than from the view's class, because Scyther's
    /// screens are SwiftUI: the view a screen hangs off is `_UIHostingView`, a private type that
    /// names Scyther nowhere, and the views inside it are private types too. What can be asked is
    /// which controller the view ultimately belongs to.
    ///
    /// The climb does not stop at the first controller it meets, and that matters. SwiftUI puts
    /// container view controllers of its own inside a hosting controller — a `List` is backed by
    /// one — so a cell's nearest controller is a private SwiftUI type that is neither Scyther's
    /// nor contains anything of Scyther's. Stopping there classified every row of the menu as the
    /// app's and left the stamps that were reversing their text in place. Climbing on reaches the
    /// ``ScytherHostingController`` above it.
    ///
    /// The three tests, in the order they are asked:
    ///
    /// - `isScytherOwnedType(_:)` — the same rule the accessibility audit uses, shared rather than
    ///   restated — recognises the overlays Scyther installs straight into the app's key window,
    ///   which have no controller at all and can only be known by class.
    /// - A ``ScytherPresentedUI`` anywhere up the chain means SwiftUI is hosting this view for
    ///   Scyther.
    /// - ``ScytherPresentation/containsScytherUI(_:)`` recognises the chrome around a presented
    ///   screen. `Scyther.showMenu(from:)` presents a stock `UINavigationController` whose child
    ///   is the ``ScytherHostingController``, so the navigation bar's owning controller is a UIKit
    ///   container and only its children give it away.
    ///
    /// The climb stops when the chain leaves views and controllers — at a `UIWindowScene`, and
    /// beyond it `UIApplication` and the app's delegate. Those belong to the app and may be named
    /// anything at all, which is the same boundary ``AuditNode`` draws for the same reason.
    ///
    /// - Parameter view: The view to classify.
    /// - Returns: The view's role.
    internal static func role(of view: UIView) -> ViewRole {
        if isScytherOwnedType(view) { return .scytherChrome }
        var responder: UIResponder? = view.next
        var steps = 0
        var chrome = false
        while let current = responder, steps < maximumResponderSteps {
            if let controller = current as? UIViewController {
                if controller is ScytherPresentedUI { return .swiftUIHosted }
                if ScytherPresentation.containsScytherUI(controller) { chrome = true }
            } else if !(current is UIView) {
                break
            }
            responder = current.next
            steps += 1
        }
        return chrome ? .scytherChrome : .foreign
    }

    /// How far ``role(of:)`` climbs before giving up.
    ///
    /// A responder chain is not cyclic, so this is belt-and-braces of the same kind
    /// ``ScytherPresentation`` and ``AuditNode`` already keep — and it costs one integer compare
    /// per link of a walk that runs once per view on a screen.
    private static let maximumResponderSteps = 100
}
#endif
