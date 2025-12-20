//
//  FirstAppearModifier.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/3/2024.
//

import SwiftUI

extension View {
    /// Performs an asynchronous action when the view first appears.
    ///
    /// Unlike `onAppear`, this modifier ensures the action is only called once,
    /// even if the view appears multiple times. This is useful for one-time
    /// initialization tasks like loading data.
    ///
    /// ```swift
    /// struct MyView: View {
    ///     var body: some View {
    ///         Text("Hello")
    ///             .onFirstAppear {
    ///                 await loadInitialData()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter action: An asynchronous closure to execute when the view first appears.
    /// - Returns: A view that triggers the action on first appearance.
    func onFirstAppear(_ action: @escaping () async -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

/// A view modifier that executes an action only on the first appearance of a view.
///
/// This modifier uses a `@State` variable to track whether the view has appeared
/// before, ensuring the action is only executed once throughout the view's lifetime.
private struct FirstAppearModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasAppeared else { return }
            hasAppeared = true
            await action()
        }
    }
}
