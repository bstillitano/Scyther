//
//  Button.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 18/2/21.
//

import Foundation
import Scyther
import UIKit

public struct ButtonOption {
    public var text: String?
    public var action: ActionBlock?
}

public enum ButtonStyle {
    case plain
    case plainLeft
    case primary
    case secondary

    var buttonHeight: CGFloat {
        switch self {
        case .primary:
            return 60
        case .secondary:
            return 60
        case .plain:
            return 48
        case .plainLeft:
            return 48
        }
    }

    var titleColor: UIColor {
        switch self {
        case .primary:
            return .white
        case .secondary:
            return .systemGreen
        case .plain:
            return .systemGreen
        case .plainLeft:
            return .systemGreen
        }
    }

    var titleFont: UIFont {
        switch self {
        case .primary:
            return .boldSystemFont(ofSize: 16)
        case .secondary:
            return .boldSystemFont(ofSize: 16)
        case .plain:
            return .boldSystemFont(ofSize: 16)
        case .plainLeft:
            return .systemFont(ofSize: 14)
        }
    }

    var iconTintColor: UIColor {
        switch self {
        case .primary:
            return .white
        case .secondary:
            return .systemGreen
        case .plain:
            return .systemGreen
        case .plainLeft:
            return .systemGreen
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .primary:
            return .systemGreen
        case .secondary:
            return .clear
        case .plain:
            return .clear
        case .plainLeft:
            return .clear
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        default:
            return 6
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .secondary:
            return 2
        default:
            return 0
        }
    }

    var borderColor: CGColor {
        switch self {
        case .secondary:
            return UIColor.systemGreen.cgColor
        default:
            return UIColor.clear.cgColor
        }
    }
    
    var disabledTitleColor: UIColor {
        switch self {
        default:
            return .systemGray
        }
    }
    
    var disabledBackgroundColor: UIColor {
        switch self {
        default:
            return .systemGray
        }
    }
    
    var disabledBorderColor: CGColor {
        switch self {
        case .secondary:
            return UIColor.systemGray.cgColor
        default:
            return UIColor.clear.cgColor
        }
    }
    
    var disabledIconTintColor: UIColor {
        switch self {
        default:
            return UIColor.systemGray
        }
    }
}

class Button: UIButton {
    // MARK: - Data
    var type: ButtonStyle = .primary {
        didSet {
            self.setType(type)
        }
    }
    
    // MARK: - Overrides
    override var isEnabled: Bool {
        didSet {
            self.isEnabled ? self.enable() : self.disable()
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init(_ type: ButtonStyle) {
        self.init(frame: .zero)
        self.type = type
        setType(type)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        //Update Constraints
        heightAnchor.constraint(equalToConstant: type.buttonHeight).isActive = true
    }

    private func setType(_ type: ButtonStyle) {
        guard let titleLabel = titleLabel,
              let imageView = imageView,
              let superview = superview
        else {
            return
        }
        
        //Set Padding
        if type == .plain || type == .plainLeft {
            self.contentEdgeInsets = .zero
        } else {
            self.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 15.0, bottom: 0.0, right: 15.0)
        }
        
        //Set Content Alignment
        if type == .plainLeft {
            contentHorizontalAlignment = .left
        }
        
        //Set Constants
        titleLabel.font = type.titleFont
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = type.cornerRadius
        clipsToBounds = true
        backgroundColor = type.backgroundColor
        imageView.tintColor = type.iconTintColor
        layer.borderColor = type.borderColor
        layer.borderWidth = type.borderWidth
        setTitleColor(type.titleColor, for: .normal)
        setTitleColor(type.disabledBackgroundColor, for: .disabled)
        
        //Set Constraints
        NSLayoutConstraint.activate([
            titleLabel.heightAnchor.constraint(equalToConstant: type.buttonHeight),
            titleLabel.topAnchor.constraint(equalTo: superview.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }

    func setImage(_ buttonImage: UIImage?, withRightInset rightInset: CGFloat = 16) {
        //Set Image
        self.setImage(buttonImage?.withRenderingMode(.alwaysTemplate), for: .normal)

        //Set Padding
        self.imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: rightInset)
        self.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 0, bottom: 0.0, right: 0.0)
    }

    private func disable() {
        backgroundColor = type.disabledBackgroundColor
        layer.borderColor = type.disabledBorderColor
        imageView?.tintColor = type.disabledIconTintColor
    }

    private func enable() {
        backgroundColor = type.backgroundColor
        layer.borderColor = type.borderColor
        imageView?.tintColor = type.iconTintColor
    }
}
