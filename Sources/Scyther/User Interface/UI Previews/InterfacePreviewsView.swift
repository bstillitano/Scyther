//
//  InterfacePreviewsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct InterfacePreviewsView: View {
    @StateObject private var viewModel = InterfacePreviewsSwiftUIViewModel()

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

struct PreviewableRowView: View {
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

struct PreviewableUIViewWrapper: UIViewRepresentable {
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

struct PreviewableItem: Identifiable {
    let id = UUID()
    let name: String
    let details: String
    let previewView: UIView
}

class InterfacePreviewsSwiftUIViewModel: ViewModel {
    @Published var previewables: [PreviewableItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadPreviewables()
    }

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

#Preview {
    NavigationStack {
        InterfacePreviewsView()
    }
}
