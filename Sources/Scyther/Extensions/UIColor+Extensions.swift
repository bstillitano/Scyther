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
    var hexCode: String {
        let components = cgColor.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        return String.init(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
    }
    
    /// Converts a hex code in the #RRGGBB format into a `UIColor`
    /// - Parameter hexCode: Color Hex Code in #RRGGBB format
    /// - Returns: A `UIColor` representing the provide code
    static func fromHex(_ hexCode: String?) -> UIColor? {
        guard let colorCode: String = hexCode else {
            return nil
        }
        
        let alpha: CGFloat = 1.0
        let red: CGFloat = UIColor.colorComponentFrom(colorCode, start: 0, length: 2)
        let green: CGFloat = UIColor.colorComponentFrom(colorCode, start: 2, length: 2)
        let blue: CGFloat = UIColor.colorComponentFrom(colorCode, start: 4, length: 2)

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    /// Converts a given string (from a hex code) into the relevant `UIColor` component
    /// - Parameters:
    ///   - colorString: Hex code in #RRGGBB format or RRGGBB format
    ///   - start: Start position in respect to the provide string
    ///   - length: Length of the component that is to be retrieved
    /// - Returns: A `CGFloat` representing the R, G or B value of a `UIColor`
    private static func colorComponentFrom(_ colorString: String, start: Int, length: Int) -> CGFloat {
        let colorCode = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "").uppercased()

        let startIndex = colorCode.index(colorCode.startIndex, offsetBy: start)
        let endIndex = colorCode.index(startIndex, offsetBy: length)
        let subString = colorCode[startIndex..<endIndex]
        let fullHexString = length == 2 ? subString : "\(subString)\(subString)"
        var hexComponent: UInt32 = 0

        guard Scanner(string: String(fullHexString)).scanHexInt32(&hexComponent) else {
            return 0
        }
        let hexFloat: CGFloat = CGFloat(hexComponent)
        let floatValue: CGFloat = CGFloat(hexFloat / 255.0)

        return floatValue
    }
}
#endif
