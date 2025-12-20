//
//  ScytherPreviewable.swift
//
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

/// A protocol that enables custom views and components to be previewed within the Scyther UI Previews section.
///
/// Conform to `ScytherPreviewable` to make your custom UI components available for inspection
/// and testing within the Scyther developer menu. This is particularly useful for:
/// - Previewing custom UI components in isolation
/// - Testing different states and configurations
/// - Demonstrating design system components
/// - Debugging complex view hierarchies
///
/// ## Conformance Requirements
///
/// Types conforming to this protocol must provide:
/// - A static preview view instance
/// - A descriptive name for the preview
/// - Additional details about the component
///
/// ## Usage Example
///
/// ```swift
/// class CustomButton: UIButton, ScytherPreviewable {
///     static var previewView: UIView {
///         let button = CustomButton()
///         button.setTitle("Preview Button", for: .normal)
///         button.backgroundColor = .systemBlue
///         return button
///     }
///
///     static var name: String {
///         return "Custom Button"
///     }
///
///     static var details: String {
///         return "A custom styled button with rounded corners and shadow"
///     }
/// }
/// ```
///
/// - Note: This protocol is only available on iOS, tvOS, and watchOS platforms.
@objc
public protocol ScytherPreviewable: AnyObject {
    /// The view instance to display in the preview.
    ///
    /// Return a configured instance of your view that demonstrates its typical appearance
    /// and behavior. This view will be displayed within the Scyther UI Previews section.
    ///
    /// ## Implementation Guidelines
    /// - Return a fully configured view with appropriate styling
    /// - Set a reasonable frame size or use Auto Layout constraints
    /// - Include any necessary setup or initial state
    ///
    /// ## Example
    ///
    /// ```swift
    /// static var previewView: UIView {
    ///     let view = MyCustomView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    ///     view.configure(with: .sampleData)
    ///     return view
    /// }
    /// ```
    static var previewView: UIView { get }

    /// The display name for this preview.
    ///
    /// Provide a human-readable name that clearly identifies the component being previewed.
    /// This name appears in the UI Previews list within Scyther.
    ///
    /// ## Example
    ///
    /// ```swift
    /// static var name: String {
    ///     return "Product Card"
    /// }
    /// ```
    static var name: String { get }

    /// Additional information about the component being previewed.
    ///
    /// Provide descriptive details about the component, its purpose, or any special
    /// characteristics. This helps developers understand what they're looking at.
    ///
    /// ## Example
    ///
    /// ```swift
    /// static var details: String {
    ///     return "Displays product information including image, title, price, and rating"
    /// }
    /// ```
    static var details: String { get }
}
#endif
