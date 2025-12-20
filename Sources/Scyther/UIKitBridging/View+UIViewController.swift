import SwiftUI
import UIKit

/// A generic view controller that hosts any SwiftUI view.
/// - Note: Designed for iOS 15 and later.
public final class HostedViewController<Content: View>: UIViewController {
    /// Creates a view controller wrapping the provided SwiftUI view.
    ///
    /// - Parameter rootView: The SwiftUI view to host.
    /// - Complexity: O(1) time and space.
    public init(rootView: Content) {
        let hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)

        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostedView)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Required initializer stub — do not use.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
