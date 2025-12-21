//
//  FileBrowser.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation

/// A utility class for browsing and managing files in the app's sandbox.
@MainActor
public final class FileBrowser: Sendable {
    /// Shared singleton instance.
    public static let instance = FileBrowser()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Root Directories

    /// Returns the root directories available for browsing.
    func rootDirectories() -> [FileItem] {
        var items: [FileItem] = []

        // Documents
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let item = FileItem.from(url: documentsURL) {
                items.append(FileItem(
                    url: item.url,
                    name: "Documents",
                    isDirectory: true,
                    size: nil,
                    modificationDate: item.modificationDate,
                    creationDate: item.creationDate,
                    fileType: .directory
                ))
            }
        }

        // Library
        if let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            if let item = FileItem.from(url: libraryURL) {
                items.append(FileItem(
                    url: item.url,
                    name: "Library",
                    isDirectory: true,
                    size: nil,
                    modificationDate: item.modificationDate,
                    creationDate: item.creationDate,
                    fileType: .directory
                ))
            }
        }

        // Caches
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let item = FileItem.from(url: cachesURL) {
                items.append(FileItem(
                    url: item.url,
                    name: "Caches",
                    isDirectory: true,
                    size: nil,
                    modificationDate: item.modificationDate,
                    creationDate: item.creationDate,
                    fileType: .directory
                ))
            }
        }

        // tmp
        let tmpURL = fileManager.temporaryDirectory
        if let item = FileItem.from(url: tmpURL) {
            items.append(FileItem(
                url: item.url,
                name: "tmp",
                isDirectory: true,
                size: nil,
                modificationDate: item.modificationDate,
                creationDate: item.creationDate,
                fileType: .directory
            ))
        }

        return items
    }

    // MARK: - Directory Contents

    /// Returns the contents of a directory.
    /// - Parameter directory: The directory URL to list.
    /// - Returns: An array of FileItems, sorted with directories first, then by name.
    func contents(of directory: URL) -> [FileItem] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let items = urls.compactMap { FileItem.from(url: $0) }

        // Sort: directories first, then alphabetically by name
        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - File Operations

    /// Deletes a file or directory.
    /// - Parameter item: The FileItem to delete.
    /// - Throws: An error if the deletion fails.
    func delete(item: FileItem) throws {
        try fileManager.removeItem(at: item.url)
    }

    /// Calculates the size of a directory recursively.
    /// - Parameter url: The directory URL.
    /// - Returns: The total size in bytes.
    nonisolated static func folderSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - File Content

    /// Reads the contents of a text file.
    /// - Parameter url: The file URL.
    /// - Parameter maxBytes: Maximum bytes to read (default 1MB).
    /// - Returns: The file contents as a string, or nil if unreadable.
    func readTextFile(at url: URL, maxBytes: Int = 1_000_000) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Don't try to read files larger than maxBytes
        if fileSize > maxBytes {
            return "[File too large to display: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))]"
        }

        guard let data = fileManager.contents(atPath: url.path) else {
            return nil
        }

        // Try UTF-8 first, then other encodings
        if let string = String(data: data, encoding: .utf8) {
            return string
        } else if let string = String(data: data, encoding: .isoLatin1) {
            return string
        } else if let string = String(data: data, encoding: .ascii) {
            return string
        }

        return nil
    }

    /// Reads a plist file and returns a formatted string representation.
    /// - Parameter url: The plist file URL.
    /// - Returns: A formatted string representation of the plist.
    func readPlistFile(at url: URL) -> String? {
        guard let data = fileManager.contents(atPath: url.path) else {
            return nil
        }

        do {
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            return formatPlistValue(plist, indent: 0)
        } catch {
            return "Error reading plist: \(error.localizedDescription)"
        }
    }

    /// Formats a plist value as a readable string.
    private func formatPlistValue(_ value: Any, indent: Int) -> String {
        let indentString = String(repeating: "  ", count: indent)

        switch value {
        case let dict as [String: Any]:
            if dict.isEmpty { return "{}" }
            var result = "{\n"
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                result += "\(indentString)  \"\(key)\": \(formatPlistValue(val, indent: indent + 1))\n"
            }
            result += "\(indentString)}"
            return result

        case let array as [Any]:
            if array.isEmpty { return "[]" }
            var result = "[\n"
            for item in array {
                result += "\(indentString)  \(formatPlistValue(item, indent: indent + 1))\n"
            }
            result += "\(indentString)]"
            return result

        case let string as String:
            return "\"\(string)\""

        case let number as NSNumber:
            return "\(number)"

        case let data as Data:
            return "<Data: \(data.count) bytes>"

        case let date as Date:
            return date.formatted()

        default:
            return String(describing: value)
        }
    }

    /// Reads a JSON file and returns a pretty-printed string.
    /// - Parameter url: The JSON file URL.
    /// - Returns: A pretty-printed JSON string.
    func readJSONFile(at url: URL) -> String? {
        guard let data = fileManager.contents(atPath: url.path) else {
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            // If JSON parsing fails, try to return as plain text
            return String(data: data, encoding: .utf8)
        }
    }

    // MARK: - File Information

    /// Gets detailed information about a file.
    /// - Parameter url: The file URL.
    /// - Returns: A dictionary of attribute names to values.
    func fileInfo(at url: URL) -> [(String, String)] {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return []
        }

        var info: [(String, String)] = []

        info.append(("Path", url.path))
        info.append(("Name", url.lastPathComponent))

        if let size = attributes[.size] as? Int64 {
            info.append(("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }

        if let type = attributes[.type] as? FileAttributeType {
            let typeString: String
            switch type {
            case .typeDirectory: typeString = "Directory"
            case .typeRegular: typeString = "File"
            case .typeSymbolicLink: typeString = "Symbolic Link"
            default: typeString = "Unknown"
            }
            info.append(("Type", typeString))
        }

        if let created = attributes[.creationDate] as? Date {
            info.append(("Created", created.formatted(date: .long, time: .standard)))
        }

        if let modified = attributes[.modificationDate] as? Date {
            info.append(("Modified", modified.formatted(date: .long, time: .standard)))
        }

        if let permissions = attributes[.posixPermissions] as? Int {
            info.append(("Permissions", String(format: "%o", permissions)))
        }

        return info
    }
}
#endif
