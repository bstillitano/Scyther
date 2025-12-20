//
//  UIFont+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

#if !os(macOS)
import UIKit

/// Provides convenient extensions for font manipulation.
///
/// This extension adds utility properties to create font variations such as bold versions
/// of existing fonts while preserving size and other attributes.
extension UIFont {
    /// Returns a bold version of the font.
    ///
    /// Creates a new font with the same characteristics as the current font but with
    /// the bold trait applied. The point size and other attributes are preserved.
    ///
    /// - Returns: A bold version of the font, or `nil` if the bold trait cannot be applied
    ///
    /// ## Example
    /// ```swift
    /// let regularFont = UIFont.systemFont(ofSize: 16)
    /// if let boldFont = regularFont.bold {
    ///     label.font = boldFont
    /// }
    ///
    /// // Using with custom fonts
    /// let customFont = UIFont(name: "Helvetica", size: 18)
    /// let boldCustomFont = customFont?.bold
    /// ```
    ///
    /// - Note: This property may return `nil` if:
    ///   - The font family doesn't have a bold variant
    ///   - The symbolic traits cannot be applied to the font
    ///   - The font descriptor cannot be modified
    ///
    /// - Important: For some custom fonts that don't have a bold variant, this will
    ///              return `nil`. In such cases, consider using a different font family
    ///              or manually specifying a bold font name.
    var bold: UIFont? {
        let fontDescriptorSymbolicTraits: UIFontDescriptor.SymbolicTraits = [fontDescriptor.symbolicTraits, .traitBold]
        let bondFontDescriptor = fontDescriptor.withSymbolicTraits(fontDescriptorSymbolicTraits)
        return bondFontDescriptor.flatMap { UIFont(descriptor: $0, size: pointSize) }
    }
}
#endif
