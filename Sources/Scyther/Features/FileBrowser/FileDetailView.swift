//
//  FileDetailView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A view that displays detailed information about a file and its contents.
struct FileDetailView: View {
    @StateObject private var viewModel: FileDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(item: FileItem) {
        _viewModel = StateObject(wrappedValue: FileDetailViewModel(item: item))
    }

    var body: some View {
        List {
            // File Information
            Section {
                ForEach(viewModel.fileInfo, id: \.0) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(value)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = value
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
            } header: {
                Text("Information")
            }

            // Actions
            Section {
                // Quick Look
                if viewModel.item.fileType.canQuickLook {
                    QuickLookButton(url: viewModel.item.url)
                }

                // Share
                ShareLink(item: viewModel.item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                // Copy Path
                Button {
                    UIPasteboard.general.string = viewModel.item.url.path
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                // Delete
                Button(role: .destructive) {
                    viewModel.showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Actions")
            }

            // File Content (for text-based files)
            if let content = viewModel.fileContent {
                Section {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 8)
                    }
                } header: {
                    HStack {
                        Text("Content")
                        Spacer()
                        Button {
                            UIPasteboard.general.string = content
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }

            // Image Preview
            if viewModel.item.fileType == .image, let image = viewModel.imagePreview {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("Preview")
                }
            }
        }
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \(viewModel.item.name)?",
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.delete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

#Preview {
    NavigationStack {
        FileDetailView(item: FileItem(
            url: URL(fileURLWithPath: "/tmp/test.txt"),
            name: "test.txt",
            isDirectory: false,
            size: 1024,
            modificationDate: Date(),
            creationDate: Date(),
            fileType: .text
        ))
    }
}
#endif
