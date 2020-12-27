//
//  UIImage+Extensions.swift
//  
//
//  Created by Brandon Stillitano on 22/12/20.
//

#if !os(macOS)
import UIKit

extension UIImage {
    /// Version safe method of accessing `UIImage(systemName: String)` below iOS 13.0. Internally references `UIImage(systemName: String)` initialiser.
    convenience init?(systemImage: String) {
        if #available(iOS 13.0, *) {
            self.init(systemName: systemImage)
        } else {
            return nil
        }
    }
}
#endif
