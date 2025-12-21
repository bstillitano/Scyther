//
//  FileItem.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation
import UniformTypeIdentifiers

/// Represents a file or directory in the file system.
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let fileType: FileType

    /// The type of file, used for determining how to display and handle it.
    enum FileType: String, CaseIterable {
        case directory
        case text
        case image
        case plist
        case json
        case sqlite
        case pdf
        case video
        case audio
        case archive
        case binary
        case unknown

        /// SF Symbol name for this file type.
        var iconName: String {
            switch self {
            case .directory: return "folder.fill"
            case .text: return "doc.text.fill"
            case .image: return "photo.fill"
            case .plist: return "list.bullet.rectangle.fill"
            case .json: return "curlybraces"
            case .sqlite: return "cylinder.fill"
            case .pdf: return "doc.richtext.fill"
            case .video: return "video.fill"
            case .audio: return "waveform"
            case .archive: return "doc.zipper"
            case .binary: return "doc.fill"
            case .unknown: return "doc.fill"
            }
        }

        /// Whether this file type can be displayed inline as text.
        var canDisplayAsText: Bool {
            switch self {
            case .text, .json, .plist:
                return true
            default:
                return false
            }
        }

        /// Whether this file type can be previewed with Quick Look.
        var canQuickLook: Bool {
            switch self {
            case .image, .pdf, .video, .audio, .text, .json:
                return true
            default:
                return false
            }
        }
    }

    /// Creates a FileItem from a URL by reading its attributes.
    /// - Parameter url: The file URL to create an item from.
    /// - Returns: A FileItem if the URL is valid, nil otherwise.
    static func from(url: URL) -> FileItem? {
        let fileManager = FileManager.default

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
        let size = attributes[.size] as? Int64
        let modificationDate = attributes[.modificationDate] as? Date
        let creationDate = attributes[.creationDate] as? Date
        let fileType = Self.detectFileType(for: url, isDirectory: isDirectory)

        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: size,
            modificationDate: modificationDate,
            creationDate: creationDate,
            fileType: fileType
        )
    }

    /// Detects the file type based on the file extension and UTI.
    private static func detectFileType(for url: URL, isDirectory: Bool) -> FileType {
        if isDirectory {
            return .directory
        }

        let ext = url.pathExtension.lowercased()

        // Check by extension first
        switch ext {
        case "txt", "md", "markdown", "rtf", "log", "swift", "m", "h", "c", "cpp", "js", "ts", "py", "rb", "java", "kt", "go", "rs", "html", "css", "xml", "yaml", "yml", "sh", "bash", "zsh":
            return .text
        case "json":
            return .json
        case "plist":
            return .plist
        case "sqlite", "sqlite3", "db":
            return .sqlite
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "ico":
            return .image
        case "pdf":
            return .pdf
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm":
            return .video
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff":
            return .audio
        case "zip", "tar", "gz", "bz2", "7z", "rar", "xz":
            return .archive
        default:
            break
        }

        // Try UTI detection
        if let uti = UTType(filenameExtension: ext) {
            if uti.conforms(to: .text) || uti.conforms(to: .sourceCode) {
                return .text
            } else if uti.conforms(to: .image) {
                return .image
            } else if uti.conforms(to: .movie) || uti.conforms(to: .video) {
                return .video
            } else if uti.conforms(to: .audio) {
                return .audio
            } else if uti.conforms(to: .pdf) {
                return .pdf
            } else if uti.conforms(to: .archive) {
                return .archive
            }
        }

        return .unknown
    }

    /// Formatted file size string.
    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Formatted modification date string.
    var formattedModificationDate: String? {
        guard let date = modificationDate else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}
#endif
