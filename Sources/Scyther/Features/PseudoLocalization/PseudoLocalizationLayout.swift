//
//  PseudoLocalizationLayout.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import UIKit

/// Forces the host app's layout direction, without switching it to an RTL language.
///
/// Separated from ``PseudoLocalization`` because right-to-left is not a string transformation at
/// all: no character changes, and none of the string plumbing in this feature is involved. It is a
/// UIKit semantic attribute, which is also why it is the one mode with no gap between Scyther's
/// interface and the host app's — it does not care how the app loads its copy.
///
/// Testing it is honest only up to a point, and the point is `UIView.appearance()`: it is
/// process-wide UIKit state with no reliable way to read the applied value back, and `ScytherTests`
/// has no host app whose windows could be inspected. ``apply(rightToLeft:)`` is therefore driven
/// only through ``attribute(rightToLeft:)``, which is pure and is tested.
///
/// ## Topics
///
/// ### Applying
/// - ``apply(rightToLeft:)``
/// - ``attribute(rightToLeft:)``
@MainActor
internal enum PseudoLocalizationLayout {
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

    /// Applies the layout direction to the appearance proxy and to every window already on screen.
    ///
    /// Both are needed and neither is sufficient. The appearance proxy governs views created from
    /// now on, so on its own the change would appear only as the developer navigated somewhere
    /// new. Setting the attribute on the live windows flips what is already visible, and SwiftUI
    /// content picks the change up through its hosting view's trait environment.
    ///
    /// It is still not complete, and the limit is worth stating: a view that has already resolved
    /// its constraints against a direction does not always re-resolve them, so a screen built
    /// before the switch can end up half-flipped. Relaunching the app settles it — the persisted
    /// switch is re-applied by ``PseudoLocalization/setup()`` before any of the app's own views
    /// exist.
    ///
    /// - Parameter rightToLeft: Whether to force right-to-left layout.
    internal static func apply(rightToLeft: Bool) {
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
