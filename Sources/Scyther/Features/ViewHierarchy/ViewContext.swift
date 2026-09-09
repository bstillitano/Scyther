//
//  ViewContext.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Where a view sits in the app, beyond its geometry.
///
/// Often the fastest answer to "which screen is this actually from" in a deep navigation stack,
/// and much cheaper than the Auto Layout inspection this feature deliberately does not do.
@MainActor
enum ViewContext {
    /// The nearest view controller above `view` in the responder chain.
    ///
    /// Nearest rather than outermost: in a nested container the answer to "which screen is this"
    /// is the child, not the navigation controller that happens to contain everything.
    ///
    /// - Parameter view: The view to trace from.
    /// - Returns: The owning controller, or `nil` for a view not yet in a chain.
    static func owningController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view.next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    /// The class names of the responder chain starting at `view`, nearest first.
    ///
    /// - Parameter view: The view to trace from.
    /// - Returns: Class names, beginning with the view's own.
    static func responderChain(from view: UIView) -> [String] {
        var names: [String] = []
        var responder: UIResponder? = view
        while let current = responder {
            names.append(String(describing: type(of: current)))
            responder = current.next
        }
        return names
    }

    /// Whether the view is currently first responder.
    ///
    /// - Parameter view: The view to ask.
    /// - Returns: `true` when it holds first responder status.
    static func isFirstResponder(_ view: UIView) -> Bool {
        view.isFirstResponder
    }
}
#endif
