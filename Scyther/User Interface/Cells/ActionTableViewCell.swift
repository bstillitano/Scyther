//
//  ActionTableViewCell.swift
//  DebugMenu
//
//  Created by Jack Perry on 1/1/20.
//  Copyright © 2020 Jack Perry. All rights reserved.
//

#if !os(macOS)
import UIKit
import Foundation

final internal class ActionTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)

        textLabel?.textAlignment = .center
        textLabel?.textColor = UIColor.systemBlue
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        textLabel?.textAlignment = .center
        textLabel?.textColor = UIColor.systemBlue
        textLabel?.font = textLabel?.font.bold()
        textLabel?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        imageView?.image = nil
    }

}


fileprivate extension UIFont {

    func bold() -> UIFont? {
        let fontDescriptorSymbolicTraits: UIFontDescriptor.SymbolicTraits = [fontDescriptor.symbolicTraits, .traitBold]
        let bondFontDescriptor = fontDescriptor.withSymbolicTraits(fontDescriptorSymbolicTraits)
        return bondFontDescriptor.flatMap { UIFont(descriptor: $0, size: pointSize) }
    }

}
#endif
