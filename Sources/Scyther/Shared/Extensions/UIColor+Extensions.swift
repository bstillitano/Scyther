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

    /// Provides the given color's hex code in the #RRGGBB format
    /// - Parameter withAlpha: Whether or not the string returned should include alpha values
    /// - Returns: A hex code in either 8 or 6 digit format depending on the `withAlpha` value
    func hexCode(withAlpha: Bool = true) -> String? {
        //Confirm enough components exist to construct a `UIColor`
        guard let components = cgColor.components, components.count >= 3 else {
            return nil
        }

        //Create color components
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        //Set alpha value
        if components.count >= 4 {
            a = Float(components[3])
        }

        //Construct hex string
        if withAlpha {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }

    /// Convenience initialiser which allows initialising a `UIColor` from a hex code
    /// - Parameter hex: Hex code in `#RRGGBB` format
    convenience init?(hex: String?) {
        //Check data
        guard let hexString: String = hex else {
            return nil
        }
        
        //Sanitise hex string
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        //Setup RGB values
        var rgb: UInt32 = 0
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        //Confirm hex code can be represented as Int32
        let length = hexSanitized.count
        guard Scanner(string: hexSanitized).scanHexInt32(&rgb) else { return nil }

        //Assign RGB values
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        //Initialise color
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif
