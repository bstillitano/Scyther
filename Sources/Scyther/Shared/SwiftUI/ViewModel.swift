//
//  ViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import Foundation

/// Base view model class for all Scyther view models.
///
/// `ViewModel` provides a structured lifecycle for SwiftUI views with distinct phases
/// for initialization, first appearance, and subsequent appearances. This pattern ensures
/// proper separation of concerns and prevents redundant data loading.
///
/// ## Lifecycle Methods
///
/// The lifecycle methods are called in the following order:
///
/// 1. ``setup()`` - Called during `init()`, before the view appears
/// 2. ``onFirstAppear()`` - Called once when the view first appears
/// 3. ``onAppear()`` - Called every time the view appears
/// 4. ``onSubsequentAppear()`` - Called on every appearance after the first
///
/// ## Usage
///
/// Subclass `ViewModel` and override the lifecycle methods you need:
///
/// ```swift
/// class MyFeatureViewModel: ViewModel {
///     @Published var data: [Item] = []
///     @Published var isLoading = false
///
///     override func onFirstAppear() async {
///         await super.onFirstAppear()
///         await loadInitialData()
///     }
///
///     override func onSubsequentAppear() async {
///         await super.onSubsequentAppear()
///         await refreshData()
///     }
///
///     private func loadInitialData() async {
///         isLoading = true
///         defer { isLoading = false }
///         // Load data...
///     }
/// }
/// ```
///
/// Use the view model in your SwiftUI view with the `onFirstAppear` modifier:
///
/// ```swift
/// struct MyFeatureView: View {
///     @StateObject private var viewModel = MyFeatureViewModel()
///
///     var body: some View {
///         List(viewModel.data) { item in
///             Text(item.name)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Best Practices
///
/// - **Always call `super`** when overriding lifecycle methods to ensure proper tracking
/// - **Use `onFirstAppear()` for initial data loading** to avoid redundant network calls
/// - **Use `onSubsequentAppear()` for refresh operations** when returning to a view
/// - **Use `setup()` for non-async initialization** like setting up NotificationCenter observers
/// - **Mark expensive operations as `@MainActor`** to ensure UI updates happen on the main thread
///
/// ## Thread Safety
///
/// This class is marked `@MainActor` to ensure all lifecycle methods and published properties
/// execute on the main thread, preventing common concurrency issues in SwiftUI.
@MainActor
class ViewModel: ObservableObject {
    /// Initializes the view model and calls ``setup()``.
    init() {
        setup()
    }

    /// Called during initialization.
    ///
    /// Override this method to perform synchronous setup tasks that need to happen
    /// before the view appears, such as:
    /// - Configuring NotificationCenter observers
    /// - Setting initial property values
    /// - Registering callbacks or delegates
    ///
    /// This method is called from `init()` and runs synchronously.
    ///
    /// ## Example
    ///
    /// ```swift
    /// override func setup() {
    ///     NotificationCenter.default.addObserver(
    ///         self,
    ///         selector: #selector(handleNotification),
    ///         name: .myNotification,
    ///         object: nil
    ///     )
    /// }
    /// ```
    func setup() {

    }

    /// Called the first time the view appears.
    ///
    /// Override this method to perform one-time initialization tasks that require
    /// async operations, such as:
    /// - Loading initial data from a network or database
    /// - Fetching user preferences
    /// - Performing expensive calculations
    ///
    /// This method is only called once during the view's lifetime, preventing
    /// redundant data loads when navigating back to the view.
    ///
    /// ## Example
    ///
    /// ```swift
    /// override func onFirstAppear() async {
    ///     await super.onFirstAppear()
    ///     isLoading = true
    ///     defer { isLoading = false }
    ///
    ///     async let userData = fetchUserData()
    ///     async let settings = fetchSettings()
    ///     (user, appSettings) = await (userData, settings)
    /// }
    /// ```
    ///
    /// - Important: Always call `await super.onFirstAppear()` to ensure proper lifecycle tracking.
    func onFirstAppear() async {

    }

    /// Called every time the view appears.
    ///
    /// Override this method to perform tasks that should happen on every appearance,
    /// regardless of whether it's the first time or a subsequent appearance.
    ///
    /// Common use cases include:
    /// - Starting timers or animations
    /// - Updating analytics
    /// - Refreshing time-sensitive data
    ///
    /// ## Example
    ///
    /// ```swift
    /// override func onAppear() async {
    ///     await super.onAppear()
    ///     Analytics.trackScreenView("MyFeature")
    ///     startAutoRefreshTimer()
    /// }
    /// ```
    ///
    /// - Note: This is called in addition to ``onFirstAppear()`` on the first appearance.
    /// - Important: Always call `await super.onAppear()` to ensure proper lifecycle tracking.
    func onAppear() async {

    }

    /// Called every time the view appears after the first appearance.
    ///
    /// Override this method to perform refresh tasks that should skip the initial load.
    /// This is useful for:
    /// - Refreshing data that may have changed while the view was hidden
    /// - Updating UI state based on external changes
    /// - Performing incremental updates
    ///
    /// ## Example
    ///
    /// ```swift
    /// override func onSubsequentAppear() async {
    ///     await super.onSubsequentAppear()
    ///     // Only refresh if data is stale
    ///     if isDataStale {
    ///         await refreshData()
    ///     }
    /// }
    /// ```
    ///
    /// - Note: This is **not** called on the first appearance, only on subsequent appearances.
    /// - Important: Always call `await super.onSubsequentAppear()` to ensure proper lifecycle tracking.
    func onSubsequentAppear() async {

    }
}
