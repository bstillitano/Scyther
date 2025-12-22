//
//  QuickLookPreview.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI
import QuickLook

/// A SwiftUI wrapper for QLPreviewController to preview files.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

/// A button that presents a Quick Look preview.
struct QuickLookButton: View {
    let url: URL
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Quick Look", systemImage: "eye")
        }
        .sheet(isPresented: $isPresented) {
            QuickLookPreview(url: url)
        }
    }
}
#endif
