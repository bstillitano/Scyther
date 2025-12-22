//
//  EnvironmentVariablesViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the environment variables display.
///
/// This view model is responsible for loading and sorting custom environment variables
/// configured in the application via `Scyther.environmentVariables`. It provides a reactive
/// interface for displaying key-value pairs of configuration data.
///
/// ## Features
///
/// - Loads environment variables from `Scyther.environmentVariables`
/// - Alphabetical sorting by key for consistent display
/// - Reactive state management via `@Published` properties
/// - Asynchronous loading during first appearance
/// - Support for empty state handling
///
/// ## Usage
///
/// The view model is typically used with `EnvironmentVariablesView`:
///
/// ```swift
/// struct EnvironmentVariablesView: View {
///     @StateObject private var viewModel = EnvironmentVariablesViewModel()
///
///     var body: some View {
///         List {
///             ForEach(viewModel.variables, id: \.key) { key, value in
///                 LabeledContent(key, value: value)
///             }
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
/// ### Properties
///
/// - ``variables``
///
/// ### Methods
///
/// - ``onFirstAppear()``
/// - ``loadVariables()``
class EnvironmentVariablesViewModel: ViewModel {
    /// The sorted list of environment variables.
    ///
    /// This array contains key-value pairs from `Scyther.environmentVariables`,
    /// sorted alphabetically by key. Each tuple contains:
    /// - `key`: The environment variable name
    /// - `value`: The environment variable value
    @Published var variables: [(key: String, value: String)] = []

    /// Called when the view appears for the first time.
    ///
    /// Triggers the loading of environment variables from the Scyther configuration.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadVariables()
    }

    /// Loads and sorts environment variables from Scyther configuration.
    ///
    /// This method retrieves all environment variables from `Scyther.environmentVariables`
    /// and sorts them alphabetically by key for consistent display in the UI.
    @MainActor
    private func loadVariables() async {
        variables = Scyther.environmentVariables
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }
}
