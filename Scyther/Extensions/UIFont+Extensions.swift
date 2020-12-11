//
//  UIFont+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import UIKit

extension UIFont {
    var bold: UIFont? {
        let fontDescriptorSymbolicTraits: UIFontDescriptor.SymbolicTraits = [fontDescriptor.symbolicTraits, .traitBold]
        let bondFontDescriptor = fontDescriptor.withSymbolicTraits(fontDescriptorSymbolicTraits)
        return bondFontDescriptor.flatMap { UIFont(descriptor: $0, size: pointSize) }
    }
}
