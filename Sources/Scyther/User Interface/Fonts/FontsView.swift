//
//  FontsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct FontsView: View {
    @StateObject private var viewModel = FontsSwiftUIViewModel()

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

struct FontRowView: View {
    let fontName: String
    let font: UIFont?

    var body: some View {
        Text(fontName)
            .font(font.map { Font($0) } ?? .body)
    }
}

struct FontFamily: Identifiable {
    let id = UUID()
    let name: String
    let fonts: [FontItem]
}

struct FontItem: Identifiable {
    let id = UUID()
    let name: String
    let uiFont: UIFont?
}

class FontsSwiftUIViewModel: ViewModel {
    @Published var fontFamilies: [FontFamily] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadFonts()
    }

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

#Preview {
    NavigationStack {
        FontsView()
    }
}
