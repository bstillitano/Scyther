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
    public convenience init?(systemImage: String) {
        if #available(iOS 13.0, *) {
            self.init(systemName: systemImage)
        } else {
            return nil
        }
    }
    
    /// `UIImage` representation of the current application icon
    public static var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else {
            return nil
        }
        return UIImage(named: lastIcon)
    }
}
#endif
