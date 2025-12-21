//
//  FileBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A view for browsing files in the app's sandbox.
///
/// Displays the root directories (Documents, Library, Caches, tmp) and allows
/// navigation into subdirectories. Files can be viewed, shared, and deleted.
struct FileBrowserView: View {
    @StateObject private var viewModel: FileBrowserViewModel

    /// Creates a file browser starting at the root directories.
    init() {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(directory: nil, title: "File Browser"))
    }

    /// Creates a file browser for a specific directory.
    /// - Parameters:
    ///   - directory: The directory to browse.
    ///   - title: The navigation title.
    init(directory: URL, title: String) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(directory: directory, title: title))
    }

    var body: some View {
        List {
            if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                ForEach(viewModel.items) { item in
                    if item.isDirectory {
                        NavigationLink {
                            FileBrowserView(directory: item.url, title: item.name)
                        } label: {
                            FileRowView(item: item, folderSize: viewModel.folderSizes[item.url])
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.itemToDelete = item
                                viewModel.showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } else {
                        NavigationLink {
                            FileDetailView(item: item)
                        } label: {
                            FileRowView(item: item, folderSize: nil)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.itemToDelete = item
                                viewModel.showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.title)
        .confirmationDialog(
            "Delete \(viewModel.itemToDelete?.name ?? "item")?",
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedItem()
            }
            Button("Cancel", role: .cancel) {
                viewModel.itemToDelete = nil
            }
        } message: {
            if viewModel.itemToDelete?.isDirectory == true {
                Text("This will delete the folder and all its contents. This action cannot be undone.")
            } else {
                Text("This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Empty Folder")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
}

/// A row view for displaying a file or directory.
struct FileRowView: View {
    let item: FileItem
    let folderSize: Int64?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.fileType.iconName)
                .font(.title2)
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let size = displaySize {
                        Text(size)
                    }
                    if let date = item.formattedModificationDate {
                        Text(date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var displaySize: String? {
        if item.isDirectory {
            if let size = folderSize {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            return nil
        } else {
            return item.formattedSize
        }
    }
}

/// View model for the file browser.
@MainActor
class FileBrowserViewModel: ViewModel {
    let directory: URL?
    let title: String

    @Published var items: [FileItem] = []
    @Published var folderSizes: [URL: Int64] = [:]
    @Published var isLoading = false
    @Published var showingDeleteConfirmation = false
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var itemToDelete: FileItem?

    init(directory: URL?, title: String) {
        self.directory = directory
        self.title = title
        super.init()
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadItems()
    }

    func refresh() async {
        await loadItems()
    }

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        if let directory = directory {
            items = FileBrowser.instance.contents(of: directory)
        } else {
            items = FileBrowser.instance.rootDirectories()
        }

        // Calculate folder sizes in background
        await calculateFolderSizes()
    }

    private func calculateFolderSizes() async {
        let directories = items.filter { $0.isDirectory }

        for directory in directories {
            let url = directory.url
            let size = await Task.detached {
                FileBrowser.folderSize(at: url)
            }.value
            folderSizes[url] = size
        }
    }

    func deleteSelectedItem() {
        guard let item = itemToDelete else { return }

        do {
            try FileBrowser.instance.delete(item: item)
            items.removeAll { $0.id == item.id }
            folderSizes.removeValue(forKey: item.url)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }

        itemToDelete = nil
    }
}

#Preview {
    NavigationStack {
        FileBrowserView()
    }
}
#endif
