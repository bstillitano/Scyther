//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 24/2/21.
//

#if !os(macOS)
import UIKit

extension UIColor {
    /// Generates a random color
    class var random: UIColor {
        return UIColor(red: .random(in: 0...1),
                       green: .random(in: 0...1),
                       blue: .random(in: 0...1),
                       alpha: 1.0)
    }
}
#endif
