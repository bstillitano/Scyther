//
//  SubsequentAppearModifier.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/3/2024.
//

import SwiftUI

extension View {
    /// Performs an asynchronous action when the view appears, skipping the first appearance.
    ///
    /// This modifier executes the action on every appearance after the initial one.
    /// Useful for refresh operations that shouldn't run during initial load.
    ///
    /// ```swift
    /// struct MyView: View {
    ///     var body: some View {
    ///         Text("Hello")
    ///             .onFirstAppear {
    ///                 await loadInitialData()
    ///             }
    ///             .onSubsequentAppear {
    ///                 await refreshData()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter action: An asynchronous closure to execute on subsequent appearances.
    /// - Returns: A view that triggers the action on subsequent appearances.
    func onSubsequentAppear(_ action: @escaping () async -> Void) -> some View {
        modifier(SubsequentAppearModifier(action: action))
    }
}

/// A view modifier that executes an action on every appearance except the first.
///
/// This modifier tracks whether the view has appeared before and only executes
/// the action after the initial appearance, making it ideal for refresh operations.
private struct SubsequentAppearModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.task {
            guard hasAppeared else {
                hasAppeared = true
                return
            }
            await action()
        }
    }
}
