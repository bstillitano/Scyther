//
//  TextCarryingView.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// The UIKit types the inspector will read text from, and the three properties it reads.
///
/// The list — `UILabel`, `UIButton`, `UITextField` — is a deliberate whitelist rather than a
/// search. **An accessibility label would be a richer answer and is exactly the property this
/// must not touch**: asking a `UIView` about accessibility forces `UIAccessibility` to compute a
/// subtree recursively, which is what hung this app in 4.3.0, and a walk over every view on
/// screen is that mistake's natural home.
///
/// It exists as a type because the same three-case switch was being written out once in
/// ``ViewHierarchyWalker`` and twice in ``ViewDetailViewModel``, each reading a different
/// property. That is parallel structure rather than duplicated logic, but it means a fourth
/// text-carrying type has to be remembered in three places and only one of them is exercised.
/// Here it is added once.
@MainActor
enum TextCarryingView {
    /// A label, whose text is its `text`.
    case label(UILabel)

    /// A button, whose text is the title it is currently showing.
    case button(UIButton)

    /// A text field, whose text is its `text`.
    case textField(UITextField)

    /// Classifies a view, if it is one of the three.
    ///
    /// - Parameter view: The view to classify.
    /// - Returns: The case it falls into, or `nil` for every other view.
    init?(_ view: UIView) {
        switch view {
        case let label as UILabel: self = .label(label)
        case let button as UIButton: self = .button(button)
        case let textField as UITextField: self = .textField(textField)
        default: return nil
        }
    }

    /// The text the view carries itself, or `nil` when it carries none.
    ///
    /// A button reports `currentTitle` rather than its title label's `text`, so a button showing
    /// an attributed or state-specific title still answers with what is on screen.
    var text: String? {
        switch self {
        case .label(let label): return label.text
        case .button(let button): return button.currentTitle
        case .textField(let textField): return textField.text
        }
    }

    /// The font the view draws its text with, or `nil`.
    var font: UIFont? {
        switch self {
        case .label(let label): return label.font
        case .button(let button): return button.titleLabel?.font
        case .textField(let textField): return textField.font
        }
    }

    /// The colour the view draws its text in, or `nil`.
    var textColour: UIColor? {
        switch self {
        case .label(let label): return label.textColor
        case .button(let button): return button.titleColor(for: .normal)
        case .textField(let textField): return textField.textColor
        }
    }
}
#endif
