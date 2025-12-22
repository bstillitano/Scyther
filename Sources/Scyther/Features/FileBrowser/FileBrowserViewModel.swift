//
//  FileBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation
import SwiftUI

/// View model for the file browser.
///
/// Manages the state and business logic for browsing files and directories in the app's sandbox.
/// Handles loading directory contents, calculating folder sizes, and file deletion operations.
///
/// ## Features
///
/// - **Directory Browsing**: Lists files and subdirectories for a given directory
/// - **Root Directory View**: Displays app sandbox root directories (Documents, Library, Caches, tmp)
/// - **Folder Size Calculation**: Asynchronously calculates and displays folder sizes
/// - **File Deletion**: Provides confirmation and deletion capabilities for files and folders
/// - **Error Handling**: Displays user-friendly error messages for failed operations
/// - **Pull to Refresh**: Supports manual refresh of directory contents
///
/// ## Usage
///
/// ```swift
/// // For root directories
/// let rootViewModel = FileBrowserViewModel(directory: nil, title: "File Browser")
///
/// // For specific directory
/// let directoryViewModel = FileBrowserViewModel(
///     directory: someURL,
///     title: "Documents"
/// )
/// ```
///
/// ## Topics
///
/// ### Initialization
/// - ``init(directory:title:)``
///
/// ### Properties
/// - ``directory``
/// - ``title``
/// - ``items``
/// - ``folderSizes``
/// - ``isLoading``
/// - ``showingDeleteConfirmation``
/// - ``showingError``
/// - ``errorMessage``
/// - ``itemToDelete``
///
/// ### Methods
/// - ``onFirstAppear()``
/// - ``refresh()``
/// - ``deleteSelectedItem()``
@MainActor
class FileBrowserViewModel: ViewModel {
    /// The directory being browsed, or `nil` for root directories.
    let directory: URL?

    /// The navigation title for this browser view.
    let title: String

    /// The files and directories in the current location.
    @Published var items: [FileItem] = []

    /// Calculated sizes for directories, keyed by directory URL.
    @Published var folderSizes: [URL: Int64] = [:]

    /// Indicates whether the view model is currently loading data.
    @Published var isLoading = false

    /// Controls the visibility of the delete confirmation dialog.
    @Published var showingDeleteConfirmation = false

    /// Controls the visibility of the error alert.
    @Published var showingError = false

    /// The error message to display in the error alert.
    @Published var errorMessage = ""

    /// The item pending deletion, set when user initiates delete action.
    @Published var itemToDelete: FileItem?

    /// Creates a file browser view model.
    ///
    /// - Parameters:
    ///   - directory: The directory to browse, or `nil` to show root directories.
    ///   - title: The navigation title for the browser.
    init(directory: URL?, title: String) {
        self.directory = directory
        self.title = title
        super.init()
    }

    /// Called when the view first appears.
    ///
    /// Loads the directory contents and calculates folder sizes.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadItems()
    }

    /// Refreshes the directory contents.
    ///
    /// Reloads all items and recalculates folder sizes. Can be called manually
    /// or via pull-to-refresh gesture.
    func refresh() async {
        await loadItems()
    }

    /// Loads items from the file system.
    ///
    /// If a directory is specified, loads its contents. Otherwise, loads the
    /// root sandbox directories. Folder sizes are calculated asynchronously
    /// after items are loaded.
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

    /// Calculates sizes for all directories in the current list.
    ///
    /// Runs on a background thread to avoid blocking the UI during
    /// potentially expensive filesystem operations.
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

    /// Deletes the currently selected item.
    ///
    /// Removes the file or directory from the filesystem and updates the UI.
    /// If deletion fails, displays an error alert with the failure reason.
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
#endif
