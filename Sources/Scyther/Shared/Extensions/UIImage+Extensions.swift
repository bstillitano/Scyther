//
//  UIImage+Extensions.swift
//
//
//  Created by Brandon Stillitano on 22/12/20.
//

#if !os(macOS)
import UIKit

/// Provides convenient extensions for UIImage creation and manipulation.
///
/// This extension adds utility methods for creating images from SF Symbols with backward
/// compatibility, accessing the app icon, and generating programmatic images.
extension UIImage {
    /// Creates a UIImage from an SF Symbol name with backward compatibility.
    ///
    /// This convenience initializer provides a version-safe way to use SF Symbols
    /// (introduced in iOS 13) by internally checking the iOS version and only attempting
    /// to load system images on supported versions.
    ///
    /// - Parameter systemImage: The name of the SF Symbol to load
    ///
    /// - Returns: A UIImage if the symbol exists and iOS 13+ is available, otherwise `nil`
    ///
    /// ## Example
    /// ```swift
    /// // Load an SF Symbol
    /// if let image = UIImage(systemImage: "heart.fill") {
    ///     imageView.image = image
    /// }
    ///
    /// // Fallback for when symbol isn't available
    /// let icon = UIImage(systemImage: "star") ?? UIImage(named: "fallback-star")
    /// ```
    ///
    /// - Note: This initializer returns `nil` on iOS versions below 13.0, even if a
    ///         valid SF Symbol name is provided.
    ///
    /// - Important: Always provide a fallback image when targeting iOS versions below 13.0.
    public convenience init?(systemImage: String) {
        if #available(iOS 13.0, *) {
            self.init(systemName: systemImage)
        } else {
            return nil
        }
    }

    /// Returns the application's icon as a UIImage.
    ///
    /// Retrieves the app icon from the app's bundle by reading the `CFBundleIcons` dictionary
    /// from the Info.plist and loading the primary icon file.
    ///
    /// - Returns: A UIImage containing the app icon, or `nil` if the icon cannot be loaded
    ///
    /// ## Example
    /// ```swift
    /// if let icon = UIImage.appIcon {
    ///     // Display the app icon in an about screen
    ///     iconImageView.image = icon
    /// }
    /// ```
    ///
    /// - Note: This property reads the icon files from the `CFBundlePrimaryIcon` key and
    ///         uses the last icon in the array, which is typically the largest version.
    ///
    /// - Warning: This may return `nil` if:
    ///   - The Info.plist doesn't contain the expected icon configuration
    ///   - The icon files aren't properly included in the bundle
    ///   - The app is running in certain test environments
    public static var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else {
            return nil
        }
        return UIImage(named: lastIcon)
    }

    /// Creates a circular indicator image with the specified color and size.
    ///
    /// This internal method generates a programmatic circular image that can be used
    /// for touch indicators or other visual feedback elements.
    ///
    /// - Parameters:
    ///   - color: The fill color for the circle
    ///   - size: The size of the resulting image
    ///
    /// - Returns: A circular UIImage with template rendering mode, or `nil` if generation fails
    ///
    /// ## Example
    /// ```swift
    /// let indicator = UIImage.touchIndicatorImage(
    ///     withColor: .systemBlue,
    ///     andSize: CGSize(width: 44, height: 44)
    /// )
    /// ```
    ///
    /// - Note: The returned image uses `.alwaysTemplate` rendering mode, allowing its
    ///         color to be changed via the `tintColor` property.
    internal static func touchIndicatorImage(withColor color: UIColor, andSize size: CGSize) -> UIImage? {
        let rect = CGRect(x: 0.0,
                          y: 0.0,
                          width: size.width,
                          height: size.height)
        UIGraphicsBeginImageContextWithOptions(rect.size,
                                               false,
                                               0.0)
        let contextRef = UIGraphicsGetCurrentContext()
        contextRef?.setFillColor(color.cgColor)
        contextRef?.fillEllipse(in: rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.withRenderingMode(.alwaysTemplate)
    }
}
#endif
