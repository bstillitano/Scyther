//
//  TextEntryView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for editing text content with search and save functionality.
///
/// `TextEntryView` provides a text editor with:
/// - Monospaced font for code/structured data
/// - Integrated search functionality
/// - Optional save callback
/// - Share functionality
/// - Auto-correction disabled
/// - Auto-capitalization disabled
///
/// ## Features
///
/// - **Editing**: Full-featured text editor with monospaced font
/// - **Search**: Built-in search bar in navigation drawer
/// - **Save**: Optional save callback with automatic dismissal
/// - **Share**: Export text via system share sheet
/// - **Code-Friendly**: Optimized for editing JSON, XML, code, and structured data
///
/// ## Usage Example
///
/// ```swift
/// @State private var jsonText = """
/// {
///     "name": "John",
///     "age": 30
/// }
/// """
///
/// NavigationStack {
///     TextEntryView(
///         text: $jsonText,
///         title: "Edit JSON",
///         onSave: { updatedText in
///             // Save the updated text
///             print("Saved: \(updatedText)")
///         }
///     )
/// }
/// ```
///
/// ## Without Save Callback
///
/// The view can also be used without a save button, allowing the binding
/// to update in real-time:
///
/// ```swift
/// TextEntryView(
///     text: $myText,
///     title: "Notes"
/// )
/// ```
struct TextEntryView: View {
    /// A binding to the text being edited.
    ///
    /// Changes to the text are immediately reflected in this binding.
    @Binding var text: String

    /// The navigation title for the view.
    var title: String = "Edit Text"

    /// Optional callback invoked when the save button is tapped.
    ///
    /// If provided, a "Save" button appears in the toolbar. When tapped,
    /// this callback is called with the current text, and the view is dismissed.
    ///
    /// If `nil`, no save button is shown and the binding updates in real-time.
    var onSave: ((String) -> Void)? = nil

    /// Environment value for dismissing the view.
    @Environment(\.dismiss) private var dismiss

    /// The current search query in the search bar.
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
