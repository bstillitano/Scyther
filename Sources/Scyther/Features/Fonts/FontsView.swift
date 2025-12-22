//
//  FontsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A browser for exploring all fonts available on the device.
///
/// Displays all system and custom fonts organized by family, with each
/// font rendered in its own typeface for easy visual identification.
struct FontsView: View {
    @StateObject private var viewModel = FontsViewModel()

    var body: some View {
        List {
            ForEach(viewModel.fontFamilies) { family in
                Section {
                    ForEach(family.fonts) { font in
                        FontRowView(fontName: font.name, font: font.uiFont)
                    }
                } header: {
                    Text(family.name)
                }
            }
        }
        .navigationTitle("Fonts")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

/// A row displaying a single font, rendered in its own typeface.
struct FontRowView: View {
    /// The PostScript name of the font.
    let fontName: String

    /// The UIFont instance for rendering, if available.
    let font: UIFont?

    var body: some View {
        Text(fontName)
            .font(font.map { Font($0) } ?? .body)
    }
}

/// A group of related fonts sharing the same family name.
struct FontFamily: Identifiable {
    let id = UUID()

    /// The font family name (e.g., "Helvetica", "San Francisco").
    let name: String

    /// All font variants in this family.
    let fonts: [FontItem]
}

/// An individual font within a font family.
struct FontItem: Identifiable {
    let id = UUID()

    /// The PostScript name of the font.
    let name: String

    /// The UIFont instance for this font at 16pt size.
    let uiFont: UIFont?
}

#Preview {
    NavigationStack {
        FontsView()
    }
}
