//
//  TextEntryView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct TextEntryView: View {
    @Binding var text: String
    var title: String = "Edit Text"
    var onSave: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 8)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                        }

                        if let onSave {
                            Button("Save") {
                                onSave(text)
                                dismiss()
                            }
                        }
                    }
                }
            }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = """
        {
            "name": "John Doe",
            "email": "john@example.com"
        }
        """

        var body: some View {
            NavigationStack {
                TextEntryView(text: $text, title: "Edit JSON")
            }
        }
    }

    return PreviewWrapper()
}
