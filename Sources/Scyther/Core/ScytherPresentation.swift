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
        resolvedPresentationSpace = nil
        NotificationCenter.default.post(name: coverageDidChangeNotification, object: nil)
    }

    /// Whether anything Scyther presented is currently on screen over the app.
    static var isCoveringScreen: Bool {
        isScytherPresented(in: presentedControllers(over: keyWindow?.rootViewController))
    }

    /// How far ``untransformedMeasurementSpace(for:)`` climbs before giving up.
    ///
    /// A view hierarchy is not cyclic, so this is belt-and-braces rather than a fix — but the
    /// property that calls this runs once per node inside a walk that is already fighting for its
    /// 0.25s budget, and a bounded loop costs one integer compare per link.
    private static let maximumAncestorSteps = 100

    /// The coordinate space a node's geometry should be measured in, when window coordinates would
    /// be a lie.
    ///
    /// The audit measures touch targets, and a touch target is geometry rather than a property of
    /// the accessibility tree — which means anything that transforms the app's views changes the
    /// audit's answer. One thing reliably does: Scyther itself. Both routes into the report present
    /// a page sheet, and UIKit builds the card behind a page sheet by scaling and translating the
    /// *presenting* view controller's view — the app under audit. Every frame read while the report
    /// is up therefore came through roughly a 0.92 scale, so 44 × 44pt controls measured about
    /// 40.5pt and were reported as errors that do not exist, on the primary path a developer reads
    /// touch-target numbers by.
    ///
    /// Of the two fixes available — refuse to report geometry while the window is transformed, or
    /// measure somewhere the transform cannot reach — this is the second. Refusing would have made
    /// the touch-target check unrunnable from the report screen, which is the only screen it is
    /// read from; the check would be correct and useless. Measuring in the transformed view's own
    /// coordinate space is exactly as honest and keeps the check working: converting *into* a
    /// view's bounds space stops below that view's own transform, so the sheet's scale is removed
    /// and everything below it — including any transform the app itself applies — still counts.
    ///
    /// ## Which transform is the presentation's
    ///
    /// The rule used to be "the highest transformed ancestor, whenever Scyther is covering the
    /// app", and that is two facts neither of which identifies a transform's *owner*: the
    /// outermost transform is the presentation's only while the presentation actually transforms
    /// something, and "Scyther is covering the app" is a fact about the whole process rather than
    /// about this node's ancestors. UIKit does not scale the presenting view behind a page or form
    /// sheet in a regular-width environment, and never behind a `.fullScreen` presentation — so on
    /// an iPad, or under any custom presentation controller, the old rule deleted the app's *own*
    /// outermost transform instead. An app using the standard slide-out-drawer idiom then had a
    /// control it really does draw at 36pt measured at 44pt and its touch-target finding vanished.
    ///
    /// So the question is asked the other way round, and answered once for the screen rather than
    /// once per node: ``presentationMeasurementSpace()`` finds the view UIKit actually transformed
    /// to build the card behind Scyther's presentation, and a node is corrected only when it is
    /// inside that view. Everything the app transforms below it survives, and when the presentation
    /// transforms nothing there is nothing to correct and window coordinates are the honest answer.
    ///
    /// - Parameter view: The node whose geometry is being measured.
    /// - Returns: The view to measure in, or `nil` when window coordinates are honest.
    static func untransformedMeasurementSpace(for view: UIView) -> UIView? {
        guard let space = presentationMeasurementSpaceProbe() else { return nil }
        guard view.isDescendant(of: space) else { return nil }
        return space
    }

    /// How ``untransformedMeasurementSpace(for:)`` asks which view Scyther's presentation
    /// transformed.
    ///
    /// A seam, for the same reason `AccessibilityAuditor.now` is one: the real answer needs a key
    /// window, a scene and a live presentation, none of which a unit-test process has, so a test
    /// that could not replace it could only ever exercise the "nothing presented" branch — and the
    /// branch that matters is the other one. Production is unaffected: the default is
    /// ``presentationMeasurementSpace()`` itself.
    static var presentationMeasurementSpaceProbe: () -> UIView? = { presentationMeasurementSpace() }

    /// The view Scyther's presentation transformed, as last resolved.
    ///
    /// Double-optional on purpose: the outer `nil` means "not worked out yet", the inner one means
    /// "worked out, and there is no such view". Cleared by ``coverageDidChange()``, which every
    /// ``ScytherHostingController`` posts as it appears and disappears — the only events that can
    /// change *which* view is the presentation's. The view's own transform is deliberately not
    /// cached: it is read live on every conversion, so an interactive sheet drag stays correct.
    private static var resolvedPresentationSpace: UIView??

    /// The view UIKit transformed to build the card behind Scyther's presentation, if any.
    ///
    /// Resolved once per screen state rather than once per node, because it is a fact about the
    /// screen. The walk asks this for every one of up to 5,000 nodes, and answering it properly
    /// costs a key-window lookup that allocates, a walk of the presented chain, and a recursive
    /// search of every controller's `children` — round two measured that at three to eleven times
    /// per node on the one path a developer reads touch-target numbers by.
    ///
    /// - Returns: The transformed view, or `nil` when nothing of Scyther's is presented or the
    ///   presentation applies no transform at all.
    static func presentationMeasurementSpace() -> UIView? {
        if let resolved = resolvedPresentationSpace {
            if let view = resolved, view.window == nil {
                resolvedPresentationSpace = nil
            } else {
                return resolved
            }
        }
        let space = resolvePresentationMeasurementSpace()
        resolvedPresentationSpace = .some(space)
        return space
    }

    /// Works out which view Scyther's presentation transformed, from scratch.
    ///
    /// The presenting view controller's root view is the boundary: UIKit applies the sheet's scale
    /// to that view or to a container it inserts above it, and everything *below* it belongs to the
    /// app. So candidates are that view and its ancestors, and the highest transformed one among
    /// them is the presentation's. No candidate transformed means the presentation transformed
    /// nothing, which is the ordinary iPad and full-screen case.
    ///
    /// - Returns: The transformed view, or `nil` when there is none to correct for.
    private static func resolvePresentationMeasurementSpace() -> UIView? {
        guard let window = keyWindow else { return nil }
        let chain = presentedControllers(over: window.rootViewController)
        guard let scyther = chain.first(where: containsScytherUI),
              let presenting = scyther.presentingViewController?.viewIfLoaded else { return nil }
        return highestTransformedView(atOrAbove: presenting)
    }

    /// The transformed view closest to the window, starting from `view` itself.
    ///
    /// The *highest* one rather than the nearest, because UIKit may transform the presenting view
    /// or a container it wraps it in, and the outermost of those is the whole of the presentation's
    /// correction. Windows are skipped: a window's own transform moves the whole screen, so
    /// removing it would not be a correction of anything.
    ///
    /// - Parameter view: The presenting view controller's root view.
    /// - Returns: The highest transformed view at or above it, or `nil` when none is transformed.
    static func highestTransformedView(atOrAbove view: UIView) -> UIView? {
        var highest: UIView?
        var current: UIView? = view
        var steps = 0
        while let candidate = current, steps < maximumAncestorSteps {
            if !(candidate is UIWindow), !candidate.transform.isIdentity {
                highest = candidate
            }
            current = candidate.superview
            steps += 1
        }
        return highest
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
