//
//  UIColor+Extensions.swift
//
//
//  Created by Brandon Stillitano on 24/2/21.
//

#if !os(macOS)
import UIKit

/// Provides convenient extensions for UIColor manipulation and conversion.
///
/// This extension adds utility methods for generating random colors, converting between
/// colors and hex codes, and creating colors from hex string representations.
extension UIColor {
    /// Generates a random UIColor with full opacity.
    ///
    /// Creates a color with randomly generated red, green, and blue components,
    /// each ranging from 0.0 to 1.0. Alpha is always set to 1.0 (fully opaque).
    ///
    /// ## Example
    /// ```swift
    /// let randomColor = UIColor.random
    /// view.backgroundColor = randomColor
    ///
    /// // Generate multiple random colors
    /// let colors = (0..<5).map { _ in UIColor.random }
    /// ```
    ///
    /// - Returns: A randomly generated UIColor with full opacity
    class var random: UIColor {
        return UIColor(red: .random(in: 0...1),
                       green: .random(in: 0...1),
                       blue: .random(in: 0...1),
                       alpha: 1.0)
    }

    /// Returns the hex code representation of the color.
    ///
    /// Converts the color's RGB(A) components to a hexadecimal string representation.
    /// The format can include or exclude the alpha channel based on the parameter.
    ///
    /// - Parameter withAlpha: Whether to include the alpha channel in the output.
    ///                        Defaults to `true`.
    ///
    /// - Returns: A hex code string in either `RRGGBBAA` (8 digits) or `RRGGBB` (6 digits) format,
    ///           or `nil` if the color cannot be converted.
    ///
    /// ## Example
    /// ```swift
    /// let redColor = UIColor.red
    /// print(redColor.hexCode(withAlpha: false)) // Prints "FF0000"
    /// print(redColor.hexCode(withAlpha: true))  // Prints "FF0000FF"
    ///
    /// let customColor = UIColor(red: 0.5, green: 0.75, blue: 1.0, alpha: 0.8)
    /// print(customColor.hexCode(withAlpha: false)) // Prints "7FBFFF"
    /// ```
    ///
    /// - Note: The returned string does not include a leading "#" character.
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

    /// Creates a UIColor from a hexadecimal color code string.
    ///
    /// This convenience initializer accepts hex codes in various formats and converts them
    /// to a UIColor. The hex string can optionally include a "#" prefix and supports both
    /// RGB (6 digits) and RGBA (8 digits) formats.
    ///
    /// - Parameter hex: A hexadecimal color code string. Can be in formats:
    ///   - `"RRGGBB"` (6 digits, assumes full opacity)
    ///   - `"#RRGGBB"` (6 digits with prefix)
    ///   - `"RRGGBBAA"` (8 digits with alpha)
    ///   - `"#RRGGBBAA"` (8 digits with prefix)
    ///
    /// - Returns: A UIColor if the hex string is valid, or `nil` if parsing fails.
    ///
    /// ## Example
    /// ```swift
    /// // Creating colors from hex codes
    /// let red = UIColor(hex: "FF0000")
    /// let blue = UIColor(hex: "#0000FF")
    /// let transparentGreen = UIColor(hex: "#00FF0080") // 50% opacity
    ///
    /// // Using with optional binding
    /// if let customColor = UIColor(hex: userInputHex) {
    ///     view.backgroundColor = customColor
    /// }
    /// ```
    ///
    /// - Note: The initializer automatically trims whitespace and removes "#" prefixes.
    ///         Invalid hex strings or strings of incorrect length will result in `nil`.
    convenience init?(hex: String?) {
        //Check data
        guard let hexString: String = hex else {
            return nil
        }

        //Sanitise hex string
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        //Setup RGB values
        var rgb: UInt64 = 0
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        //Confirm hex code can be represented as Int64
        let length = hexSanitized.count
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

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
