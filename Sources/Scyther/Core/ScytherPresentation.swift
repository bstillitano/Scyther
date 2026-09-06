//
//  ScytherPresentation.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import SwiftUI
import UIKit

/// Marks a view controller as one Scyther itself put on screen, rather than one belonging to the
/// app being debugged.
///
/// This exists because there is no honest way to recognise Scyther's own presentations from the
/// outside. ``AuditNode`` recognises Scyther's *non-presented* views by class — ``TopLevelView``,
/// ``TopLevelViewsWrapper``, or a type whose name begins with `Scyther` — and that rule works
/// there because those views really are Scyther's own classes. A presented screen is not: it is a
/// `UIHostingController` whose view is SwiftUI's `_UIHostingView`, a type belonging to SwiftUI
/// that names Scyther nowhere. Sniffing that class name would be guessing at a private type, so
/// Scyther says so itself instead, by hosting everything it presents in a
/// ``ScytherHostingController``.
///
/// Two things ask: ``ScytherPresentation/isCoveringScreen``, which decides whether the contrast
/// check can be measured honestly and whether the live overlay should draw at all; and
/// `AuditNode.isScytherOwned`, which walks a view up its responder chain to whichever controller
/// owns it and skips the whole subtree when that controller is marked. Before the second of those,
/// the audit walked Scyther's own menu and report and drew error boxes over Scyther's own buttons.
///
/// - Note: `AnyObject`-constrained so `is`/`as?` can be used on it without boxing a value type
///   that could never be a view controller in the first place.
internal protocol ScytherPresentedUI: AnyObject { }

/// The `UIHostingController` every screen Scyther presents over the app is hosted in.
///
/// Adds no behaviour of its own — it exists purely so that ``ScytherPresentation`` can tell
/// Scyther's own modals apart from the app's. Three places create one: `Scyther.showMenu(from:)`,
/// ``BreakpointPresenter``, and ``AccessibilityAuditReportPresenter``. Anything Scyther presents
/// in future should use it too, or it will be mistaken for the app's own UI.
///
/// - Note: Declares no initialisers of its own, so it inherits `UIHostingController`'s —
///   including the `required init?(coder:)` a subclass would otherwise have to restate.
internal final class ScytherHostingController<Content: View>: UIHostingController<Content>, ScytherPresentedUI {
    /// Announces that Scyther has just covered the app.
    ///
    /// Nothing else can see this happen. A modal presentation changes no frame the live
    /// accessibility overlay owns and posts no system notification the overlay could observe, so
    /// without this the overlay would keep drawing the boxes it drew for the screen underneath —
    /// over the top of Scyther's own report, which is exactly the defect this pairs with.
    ///
    /// - Parameter animated: Whether the appearance was animated. Passed straight to `super`.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ScytherPresentation.coverageDidChange()
    }

    /// Announces that Scyther may have just stopped covering the app.
    ///
    /// "May", not "has": another Scyther screen can still be up — the menu disappearing behind
    /// the breakpoint editor it presented, say — which is why observers are told to *recompute*
    /// ``ScytherPresentation/isCoveringScreen`` rather than being handed a boolean from here.
    /// It also fires for a swipe-dismissal, which no presenter of Scyther's is told about at all.
    ///
    /// - Parameter animated: Whether the disappearance was animated. Passed straight to `super`.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ScytherPresentation.coverageDidChange()
    }
}

/// Answers one question: is Scyther's own UI in front of the app right now?
///
/// The accessibility audit's contrast check is the caller. A modally presented screen dims and
/// scales the content behind it, so a snapshot of the window taken while Scyther's menu — or its
/// own report — is up is a snapshot of the app *through* Scyther's dimming. Every contrast ratio
/// measured from it is an artefact of Scyther rather than a fact about the app, which is worse
/// than no measurement at all. Knowing when that is the case is what lets the check be skipped and
/// said to have been skipped.
///
/// ## Why the presented chain, and not `Scyther.topViewController`
///
/// `Scyther.topViewController` walks the same chain but keeps only its last link, which is not
/// enough for two reasons. Scyther's menu is presented *inside* a `UINavigationController`, so the
/// top of the chain is that container rather than anything of Scyther's — hence the search through
/// ``children``. And an app that presents one of its own screens over Scyther's menu puts a
/// non-Scyther controller on top while Scyther's dimming is still between the audit and the app —
/// hence looking at every link rather than the last one.
@MainActor
internal enum ScytherPresentation {
    /// Posted whenever a ``ScytherHostingController`` appears or disappears, meaning the answer
    /// ``isCoveringScreen`` gives may have changed.
    ///
    /// A notification rather than a direct call into `InterfaceToolkit` so the dependency runs the
    /// same way round as the rest of Scyther's overlays: this file knows nothing about the
    /// accessibility audit, and the toolkit — which already observes four other UIKit
    /// notifications — subscribes to one more. `nonisolated` so an observer can be registered from
    /// wherever it happens to be set up.
    nonisolated static let coverageDidChangeNotification = NSNotification.Name("Scyther_presentation_coverage_did_change")

    /// Posts ``coverageDidChangeNotification``.
    ///
    /// Carries no payload on purpose. Whether Scyther is covering the app is a fact about the
    /// whole presented chain, not about the one controller that just appeared or disappeared, so
    /// an observer that trusted a boolean sent from here would be wrong the moment two Scyther
    /// screens are stacked and the upper one goes away.
    static func coverageDidChange() {
        NotificationCenter.default.post(name: coverageDidChangeNotification, object: nil)
    }

    /// Whether anything Scyther presented is currently on screen over the app.
    static var isCoveringScreen: Bool {
        isScytherPresented(in: presentedControllers(over: keyWindow?.rootViewController))
    }

    /// Every controller presented over `root`, innermost first.
    ///
    /// `root` itself is deliberately not included: the app's own root controller is the app, not
    /// something covering it, and a root that somehow *were* one of Scyther's would mean Scyther
    /// is the app under audit rather than on top of it.
    ///
    /// - Parameter root: The window's root view controller, or `nil` when there is no window.
    /// - Returns: The presented controllers, in the order they were presented.
    static func presentedControllers(over root: UIViewController?) -> [UIViewController] {
        var chain: [UIViewController] = []
        var current = root?.presentedViewController
        while let controller = current {
            chain.append(controller)
            current = controller.presentedViewController
        }
        return chain
    }

    /// Whether any controller in `chain`, or anything it contains, is one of Scyther's.
    ///
    /// Separated from ``presentedControllers(over:)`` so it can be tested against a chain built by
    /// hand: a test cannot present a real modal without a window, an app delegate and an
    /// animation, and none of those would make the answer any more true.
    ///
    /// - Parameter chain: The presented controllers to inspect.
    /// - Returns: `true` when Scyther's UI is somewhere in the chain.
    static func isScytherPresented(in chain: [UIViewController]) -> Bool {
        chain.contains(where: containsScytherUI)
    }

    /// Whether `controller` is one of Scyther's, or contains one.
    ///
    /// The containment search is what catches the menu: `Scyther.showMenu(from:)` presents a
    /// `UINavigationController` whose only child is the ``ScytherHostingController`` holding the
    /// menu, so the presented controller itself is a stock UIKit container and only its child
    /// gives it away. Recursive rather than one level deep, since a split or tab container would
    /// add another level and none of this is hot code — it runs once per audit, over a chain that
    /// is nearly always empty.
    ///
    /// - Parameter controller: The controller to inspect.
    /// - Returns: `true` when it or one of its descendants is Scyther's.
    private static func containsScytherUI(_ controller: UIViewController) -> Bool {
        if controller is ScytherPresentedUI { return true }
        return controller.children.contains(where: containsScytherUI)
    }

    /// The app's key window, resolved the same way `Scyther`, `InterfaceToolkit` and
    /// ``AccessibilityAudit`` each already resolve it.
    ///
    /// Repeated here rather than shared for the same reason they repeat it between themselves:
    /// there is no existing shared accessor, `Scyther`'s own is private, and a single-expression
    /// lookup is not worth introducing one for.
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
