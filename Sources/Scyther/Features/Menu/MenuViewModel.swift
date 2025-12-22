//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import Foundation
import SwiftUI

/// View model for the main menu interface.
///
/// `MenuViewModel` manages the state and data loading for the Scyther developer menu,
/// including network information retrieval and UI toolkit settings synchronization.
///
/// ## Features
///
/// - **Network Information**: Asynchronously fetches and displays the device's current IP address
/// - **Animation Controls**: Manages slow animations mode for UI debugging
/// - **View Debugging**: Controls visibility of view frames and sizes
/// - **Automatic Synchronization**: Two-way binding with ``InterfaceToolkit`` settings
///
/// ## Usage
///
/// The view model is used by ``MenuView`` to manage its state:
///
/// ```swift
/// struct MenuView: View {
///     @StateObject private var viewModel = MenuViewModel()
///
///     var body: some View {
///         List {
///             // IP address with loading indicator
///             row(
///                 withLabel: "IP Address",
///                 description: viewModel.ipAddress,
///                 andLoadingState: viewModel.isLoadingIPAddress
///             )
///
///             // Toggle controls bound to view model
///             Toggle("Slow Animations", isOn: $viewModel.slowAnimationsEnabled)
///             Toggle("Show View Frames", isOn: $viewModel.showViewFrames)
///             Toggle("Show View Sizes", isOn: $viewModel.showViewSizes)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Network Information
///
/// - ``ipAddress``
/// - ``isLoadingIPAddress``
///
/// ### UI Debugging Controls
///
/// - ``slowAnimationsEnabled``
/// - ``showViewFrames``
/// - ``showViewSizes``
///
/// ### Lifecycle
///
/// - ``onFirstAppear()``
@MainActor
class MenuViewModel: ViewModel {
    // MARK: - Network Properties

    /// The device's current IP address.
    ///
    /// This property is populated asynchronously during ``onFirstAppear()`` using
    /// ``NetworkHelper`` to fetch the device's IP address. While loading, this
    /// will be an empty string and ``isLoadingIPAddress`` will be `true`.
    @Published var ipAddress: String = ""

    /// Whether the IP address is currently being fetched.
    ///
    /// This property is `true` while the IP address is being loaded from ``NetworkHelper``.
    /// Use this to display a loading indicator in the UI.
    @Published var isLoadingIPAddress: Bool = true

    // MARK: - UI Debugging Properties

    /// Whether slow animations mode is enabled.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/slowAnimationsEnabled``.
    /// When enabled, all animations in the app run at a slower speed to aid in debugging
    /// UI transitions and animations.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var slowAnimationsEnabled: Bool = InterfaceToolkit.slowAnimationsEnabled {
        didSet {
            InterfaceToolkit.slowAnimationsEnabled = slowAnimationsEnabled
        }
    }

    /// Whether view frames are shown.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/showViewFrames``.
    /// When enabled, visual overlays are drawn around all view frames to help with
    /// layout debugging.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var showViewFrames: Bool = InterfaceToolkit.showViewFrames {
        didSet {
            InterfaceToolkit.showViewFrames = showViewFrames
        }
    }

    /// Whether view sizes are shown.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/showViewSizes``.
    /// When enabled, view dimensions are displayed as overlays on each view to help
    /// with layout debugging.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var showViewSizes: Bool = InterfaceToolkit.showViewSizes {
        didSet {
            InterfaceToolkit.showViewSizes = showViewSizes
        }
    }

    // MARK: - Lifecycle Methods

    /// Called the first time the menu view appears.
    ///
    /// This method initiates the asynchronous loading of the device's IP address.
    /// The loading state is tracked via ``isLoadingIPAddress`` and the result is
    /// stored in ``ipAddress``.
    ///
    /// - Important: Always call `await super.onFirstAppear()` to ensure proper lifecycle tracking.
    override func onFirstAppear() async {
        await super.onFirstAppear()

        await loadIPAddress()
    }

    // MARK: - Private Methods

    /// Loads the device's IP address from ``NetworkHelper``.
    ///
    /// This method fetches the IP address asynchronously and updates ``ipAddress``
    /// and ``isLoadingIPAddress`` accordingly. The loading state is automatically
    /// set to `false` when the operation completes, regardless of success or failure.
    private func loadIPAddress() async {
        defer { isLoadingIPAddress = false }
        isLoadingIPAddress = true
        ipAddress = await NetworkHelper.instance.ipAddress
    }
}
