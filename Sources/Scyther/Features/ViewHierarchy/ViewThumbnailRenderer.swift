//
//  ViewThumbnailRenderer.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Renders a single view to an image, on demand.
///
/// **This is the one expensive thing the inspector does.** Rendering a view is rasterisation, on
/// the same list of costs as the accessibility audit's recursive subtree walk. It runs for the
/// selected view only — never per row, never eagerly for the tree — is capped, and does not wait
/// for screen updates.
@MainActor
enum ViewThumbnailRenderer {
    /// The largest image produced, in points. A larger view is scaled to fit, so a full-screen
    /// view costs no more than a button.
    static let maximumSize = CGSize(width: 512, height: 512)

    /// What there is to show for a view.
    ///
    /// The three failure cases are distinct on purpose: the page says *which* it is, rather than
    /// presenting an empty box as though it were the view's true appearance.
    enum Thumbnail: Equatable {
        /// A rendered image.
        case image(UIImage)

        /// The view is invisible, so there is nothing to render.
        case hidden

        /// The view has no area, so there is nothing to render.
        case zeroSize

        /// The view has been deallocated since the snapshot was taken.
        case unavailable
    }

    /// Renders `view`, or says why it cannot.
    ///
    /// - Parameters:
    ///   - view: The live view, or `nil` when the snapshot's weak reference has gone.
    ///   - isHidden: The node's hidden flag.
    ///   - isZeroSize: The node's zero-size flag.
    /// - Returns: The image, or the reason there is not one.
    static func thumbnail(of view: UIView?, isHidden: Bool, isZeroSize: Bool) -> Thumbnail {
        guard let view else { return .unavailable }
        guard !isZeroSize, view.bounds.width > 0, view.bounds.height > 0 else { return .zeroSize }
        guard !isHidden else { return .hidden }

        let scale = min(1, min(maximumSize.width / view.bounds.width,
                               maximumSize.height / view.bounds.height))
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            view.layer.render(in: context.cgContext)
        }
        return .image(image)
    }
}
#endif
