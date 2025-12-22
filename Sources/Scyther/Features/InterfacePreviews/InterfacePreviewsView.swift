//
//  InterfacePreviewsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A gallery view displaying previews of custom UI components.
///
/// Shows all classes conforming to the `ScytherPreviewable` protocol,
/// rendering a preview of each component along with its name and description.
/// Useful for showcasing custom UIKit views and controls.
struct InterfacePreviewsView: View {
    @StateObject private var viewModel = InterfacePreviewsViewModel()

    var body: some View {
        List {
            ForEach(viewModel.previewables) { item in
                PreviewableRowView(item: item)
            }
        }
        .navigationTitle("UI Previews")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

/// A row displaying a single previewable UI component.
struct PreviewableRowView: View {
    /// The previewable item to display.
    let item: PreviewableItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.headline)
            Text(item.details)
                .font(.caption)
                .foregroundColor(.secondary)

            PreviewableUIViewWrapper(view: item.previewView)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }
}

/// A SwiftUI wrapper for displaying UIKit views.
struct PreviewableUIViewWrapper: UIViewRepresentable {
    /// The UIView to wrap and display.
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A model representing a previewable UI component.
struct PreviewableItem: Identifiable {
    let id = UUID()

    /// The display name of the component.
    let name: String

    /// A description of what the component does.
    let details: String

    /// The UIView instance to preview.
    let previewView: UIView
}

#Preview {
    NavigationStack {
        InterfacePreviewsView()
    }
}
