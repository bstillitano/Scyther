//
//  FileDetailViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation
import SwiftUI
import UIKit

/// View model for the file detail view.
///
/// Manages the presentation of detailed file information, content previews, and file operations
/// for a single file item. Supports loading and displaying text-based file contents, image
/// previews, and file metadata.
///
/// ## Features
///
/// - **File Information**: Displays comprehensive metadata (size, dates, permissions, etc.)
/// - **Content Preview**: Shows content for text, JSON, and plist files
/// - **Image Preview**: Displays image files with proper scaling
/// - **File Operations**: Supports deletion with confirmation
/// - **Error Handling**: Provides user feedback for failed operations
/// - **Copy Support**: Allows copying file paths and content to clipboard
///
/// ## Usage
///
/// ```swift
/// let fileItem = FileItem(
///     url: someURL,
///     name: "example.txt",
///     isDirectory: false,
///     size: 1024,
///     modificationDate: Date(),
///     creationDate: Date(),
///     fileType: .text
/// )
///
/// let viewModel = FileDetailViewModel(item: fileItem)
/// ```
///
/// ## Topics
///
/// ### Initialization
/// - ``init(item:)``
///
/// ### Properties
/// - ``item``
/// - ``fileInfo``
/// - ``fileContent``
/// - ``imagePreview``
/// - ``showingDeleteConfirmation``
/// - ``showingError``
/// - ``errorMessage``
///
/// ### Methods
/// - ``onFirstAppear()``
/// - ``delete()``
@MainActor
class FileDetailViewModel: ViewModel {
    /// The file item being displayed.
    let item: FileItem

    /// File metadata as key-value pairs for display.
    ///
    /// Includes information such as file size, modification date, creation date,
    /// permissions, and file path.
    @Published var fileInfo: [(String, String)] = []

    /// Text content of the file, if applicable.
    ///
    /// Populated for text, JSON, and plist files. `nil` for binary or unsupported formats.
    @Published var fileContent: String?

    /// Image preview for image files.
    ///
    /// Populated when the file type is `.image` and the file can be decoded as a valid image.
    @Published var imagePreview: UIImage?

    /// Controls the visibility of the delete confirmation dialog.
    @Published var showingDeleteConfirmation = false

    /// Controls the visibility of the error alert.
    @Published var showingError = false

    /// The error message to display in the error alert.
    @Published var errorMessage = ""

    /// Creates a file detail view model.
    ///
    /// - Parameter item: The file item to display details for.
    init(item: FileItem) {
        self.item = item
        super.init()
    }

    /// Called when the view first appears.
    ///
    /// Loads file information and content preview based on the file type.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        loadFileInfo()
        loadContent()
    }

    /// Loads file metadata information.
    ///
    /// Retrieves comprehensive file attributes including size, dates, and permissions
    /// from the file system.
    private func loadFileInfo() {
        fileInfo = FileBrowser.instance.fileInfo(at: item.url)
    }

    /// Loads file content based on file type.
    ///
    /// For text-based files (.text, .json, .plist), reads and formats the content as a string.
    /// For image files, loads the image data for preview. Other file types are not loaded.
    private func loadContent() {
        switch item.fileType {
        case .text:
            fileContent = FileBrowser.instance.readTextFile(at: item.url)
        case .json:
            fileContent = FileBrowser.instance.readJSONFile(at: item.url)
        case .plist:
            fileContent = FileBrowser.instance.readPlistFile(at: item.url)
        case .image:
            if let data = FileManager.default.contents(atPath: item.url.path) {
                imagePreview = UIImage(data: data)
            }
        default:
            break
        }
    }

    /// Deletes the current file item.
    ///
    /// Removes the file from the filesystem. If deletion fails, sets the error message
    /// and shows an error alert. The caller should dismiss the detail view after successful deletion.
    func delete() {
        do {
            try FileBrowser.instance.delete(item: item)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
#endif
