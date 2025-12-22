//
//  InterfacePreviewsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the interface previews list.
///
/// This view model is responsible for discovering and managing UI components that conform to the `ScytherPreviewable` protocol.
/// It automatically loads all previewable components and creates preview items for display in the UI.
///
/// ## Features
///
/// - Automatic discovery of classes conforming to `ScytherPreviewable`
/// - Alphabetical sorting of previewable components
/// - Reactive state management via `@Published` properties
/// - Asynchronous loading during first appearance
///
/// ## Usage
///
/// The view model is typically used with `InterfacePreviewsView`:
///
/// ```swift
/// struct InterfacePreviewsView: View {
///     @StateObject private var viewModel = InterfacePreviewsViewModel()
///
///     var body: some View {
///         List {
///             ForEach(viewModel.previewables) { item in
///                 PreviewableRowView(item: item)
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
/// - ``previewables``
///
/// ### Methods
///
/// - ``onFirstAppear()``
/// - ``loadPreviewables()``
class InterfacePreviewsViewModel: ViewModel {
    /// The list of previewable UI components.
    ///
    /// This array contains all discovered components that conform to `ScytherPreviewable`,
    /// sorted alphabetically by name. Each item includes the component's name, description,
    /// and preview view instance.
    @Published var previewables: [PreviewableItem] = []

    /// Called when the view appears for the first time.
    ///
    /// Triggers the loading of all previewable components.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadPreviewables()
    }

    /// Loads all classes conforming to `ScytherPreviewable` protocol.
    ///
    /// This method uses runtime introspection to discover all classes that conform to
    /// the `ScytherPreviewable` protocol, sorts them alphabetically, and creates
    /// `PreviewableItem` instances for each one.
    @MainActor
    private func loadPreviewables() async {
        guard let classes = NSObject().classesConformingToProtocol(ScytherPreviewable.self) as? [ScytherPreviewable.Type] else {
            return
        }

        previewables = classes
            .sorted { $0.name < $1.name }
            .map { previewable in
                PreviewableItem(
                    name: previewable.name,
                    details: previewable.details,
                    previewView: previewable.previewView
                )
            }
    }
}
