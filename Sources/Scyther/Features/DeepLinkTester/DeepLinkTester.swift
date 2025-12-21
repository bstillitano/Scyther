//
//  DeepLinkTester.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import UIKit

/// A preset deep link for quick testing.
///
/// Use this to configure commonly-used deep links that appear in the tester UI.
///
/// ```swift
/// Scyther.deepLinks.presets = [
///     DeepLinkPreset(name: "Home", url: "myapp://home"),
///     DeepLinkPreset(name: "Profile", url: "myapp://profile/123"),
/// ]
/// ```
public struct DeepLinkPreset: Sendable, Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.id = UUID()
        self.name = name
        self.url = url
    }
}

/// A record of a tested deep link.
public struct DeepLinkHistoryEntry: Sendable, Identifiable, Codable {
    public let id: UUID
    public let url: String
    public let timestamp: Date
    public let success: Bool
    public let errorMessage: String?

    init(url: String, success: Bool, errorMessage: String? = nil) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Errors that can occur when opening a deep link.
public enum DeepLinkError: Error, LocalizedError {
    case invalidURL
    case cannotOpen
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL format"
        case .cannotOpen:
            return "This URL cannot be opened"
        case .openFailed:
            return "Failed to open URL"
        }
    }
}

/// A singleton manager for testing deep links and URL schemes.
///
/// `DeepLinkTester` provides functionality to:
/// - Open custom URL schemes and universal links
/// - Maintain a history of tested links
/// - Configure preset links for quick access
///
/// ```swift
/// // Open a deep link
/// let result = await DeepLinkTester.instance.open("myapp://profile/123")
///
/// // Configure presets
/// DeepLinkTester.instance.presets = [
///     DeepLinkPreset(name: "Home", url: "myapp://home")
/// ]
/// ```
@MainActor
public final class DeepLinkTester: Sendable {
    // MARK: - Static Data

    /// UserDefaults key for storing deep link history.
    nonisolated static let HistoryDefaultsKey: String = "Scyther_deep_link_history"

    /// UserDefaults key for storing deep link presets.
    nonisolated static let PresetsDefaultsKey: String = "Scyther_deep_link_presets"

    /// Maximum number of history entries to retain.
    public static let maxHistoryCount: Int = 50

    /// Private init to stop re-initialisation and allow singleton creation.
    private init() {
        loadHistory()
        loadPresets()
    }

    /// The shared singleton instance of `DeepLinkTester`.
    public static let instance = DeepLinkTester()

    // MARK: - Data

    /// History of tested deep links.
    public private(set) var history: [DeepLinkHistoryEntry] = []

    /// Developer-configured preset deep links.
    public var presets: [DeepLinkPreset] = [] {
        didSet {
            savePresets()
        }
    }

    // MARK: - Opening Links

    /// Opens a deep link URL.
    ///
    /// - Parameter urlString: The URL string to open.
    /// - Returns: A result indicating success or the specific error.
    @discardableResult
    public func open(_ urlString: String) async -> Result<Void, DeepLinkError> {
        // Validate URL
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            addHistoryEntry(url: urlString, success: false, error: .invalidURL)
            return .failure(.invalidURL)
        }

        // Check if we can open the URL
        let canOpen = await UIApplication.shared.canOpenURL(url)
        if !canOpen {
            // Still try to open - canOpenURL can return false for universal links
            // that the system can still handle
        }

        // Attempt to open
        let success = await UIApplication.shared.open(url)

        if success {
            addHistoryEntry(url: trimmed, success: true, error: nil)
            return .success(())
        } else {
            let error: DeepLinkError = canOpen ? .openFailed : .cannotOpen
            addHistoryEntry(url: trimmed, success: false, error: error)
            return .failure(error)
        }
    }

    // MARK: - History Management

    private func addHistoryEntry(url: String, success: Bool, error: DeepLinkError?) {
        let entry = DeepLinkHistoryEntry(
            url: url,
            success: success,
            errorMessage: error?.errorDescription
        )

        // Add to beginning (most recent first)
        history.insert(entry, at: 0)

        // Trim to max count
        if history.count > Self.maxHistoryCount {
            history = Array(history.prefix(Self.maxHistoryCount))
        }

        saveHistory()
    }

    /// Clears all history entries.
    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    /// Removes a specific history entry.
    public func removeHistoryEntry(_ entry: DeepLinkHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.HistoryDefaultsKey),
              let decoded = try? JSONDecoder().decode([DeepLinkHistoryEntry].self, from: data) else {
            return
        }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.HistoryDefaultsKey)
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: Self.PresetsDefaultsKey),
              let decoded = try? JSONDecoder().decode([DeepLinkPreset].self, from: data) else {
            return
        }
        presets = decoded
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Self.PresetsDefaultsKey)
    }
}
#endif
