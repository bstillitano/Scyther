//
//  FontsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the fonts list.
///
/// This view model is responsible for loading and organizing all fonts available on the device.
/// It groups fonts by family and provides them in a structured format for display in the UI.
///
/// ## Features
///
/// - Automatic discovery of all system and custom fonts
/// - Organization by font family
/// - Alphabetical sorting of font families
/// - Creation of UIFont instances for rendering
/// - Reactive state management via `@Published` properties
/// - Asynchronous loading during first appearance
///
/// ## Usage
///
/// The view model is typically used with `FontsView`:
///
/// ```swift
/// struct FontsView: View {
///     @StateObject private var viewModel = FontsViewModel()
///
///     var body: some View {
///         List {
///             ForEach(viewModel.fontFamilies) { family in
///                 Section(family.name) {
///                     ForEach(family.fonts) { font in
///                         FontRowView(fontName: font.name, font: font.uiFont)
///                     }
///                 }
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
/// - ``fontFamilies``
///
/// ### Methods
///
/// - ``onFirstAppear()``
/// - ``loadFonts()``
class FontsViewModel: ViewModel {
    /// The list of font families available on the device.
    ///
    /// This array contains all font families sorted alphabetically, with each family
    /// containing its individual font variants. Each font is instantiated at 16pt size
    /// for preview purposes.
    @Published var fontFamilies: [FontFamily] = []

    /// Called when the view appears for the first time.
    ///
    /// Triggers the loading of all available fonts from the system.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadFonts()
    }

    /// Loads all available fonts from the system, organized by family.
    ///
    /// This method uses `UIFont.familyNames` to discover all font families, then
    /// retrieves all font variants for each family. Fonts are sorted alphabetically
    /// by family name, and each font is instantiated at 16pt size for rendering.
    @MainActor
    private func loadFonts() async {
        fontFamilies = UIFont.familyNames.sorted().map { familyName in
            FontFamily(
                name: familyName,
                fonts: UIFont.fontNames(forFamilyName: familyName).map { fontName in
                    FontItem(name: fontName, uiFont: UIFont(name: fontName, size: 16.0))
                }
            )
        }
    }
}
