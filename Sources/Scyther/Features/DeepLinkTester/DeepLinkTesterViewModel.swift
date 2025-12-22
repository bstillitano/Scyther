//
//  DeepLinkTesterViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation

/// View model for managing the deep link tester interface.
///
/// `DeepLinkTesterViewModel` handles user input for testing deep links,
/// managing history, and coordinating with ``DeepLinkTester`` to open URLs.
///
/// ## Features
/// - Validates and opens custom URL schemes and universal links
/// - Displays developer-configured preset deep links
/// - Maintains a history of tested links with success/failure status
/// - Supports QR code scanning integration
///
/// ## Usage
/// ```swift
/// @StateObject private var viewModel = DeepLinkTesterViewModel()
///
/// // Open a URL
/// await viewModel.openURL()
///
/// // Open a preset
/// await viewModel.openPreset(preset)
///
/// // Clear history
/// viewModel.clearHistory()
/// ```
///
/// ## Topics
///
/// ### Input State
/// - ``urlText``
/// - ``isLoading``
///
/// ### Result Handling
/// - ``showingResult``
/// - ``resultMessage``
///
/// ### Data
/// - ``presets``
/// - ``history``
///
/// ### Actions
/// - ``openURL()``
/// - ``openPreset(_:)``
/// - ``deleteHistoryEntry(_:)``
/// - ``clearHistory()``
@MainActor
class DeepLinkTesterViewModel: ViewModel {
    // MARK: - Published Properties

    /// The URL text entered by the user.
    ///
    /// This is bound to the text field in the UI and used when
    /// ``openURL()`` is called.
    @Published var urlText: String = ""

    /// Indicates whether a URL is currently being opened.
    ///
    /// When `true`, the UI should show a loading indicator and
    /// disable the open button.
    @Published var isLoading: Bool = false

    /// Controls the visibility of the result alert.
    ///
    /// Set to `true` after attempting to open a URL to show
    /// the success or failure message.
    @Published var showingResult: Bool = false

    /// The message to display in the result alert.
    ///
    /// Contains either a success message or error description
    /// based on the URL open attempt.
    @Published var resultMessage: String = ""

    /// Developer-configured preset deep links.
    ///
    /// Loaded from ``DeepLinkTester/presets`` on first appear.
    /// Configure via `Scyther.deepLinks.presets`.
    @Published var presets: [DeepLinkPreset] = []

    /// History of previously tested deep links.
    ///
    /// Loaded from ``DeepLinkTester/history`` and updated after
    /// each URL open attempt. Most recent entries appear first.
    @Published var history: [DeepLinkHistoryEntry] = []

    // MARK: - Lifecycle

    /// Called when the view first appears.
    ///
    /// Loads presets and history from ``DeepLinkTester``.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadData()
    }

    // MARK: - Private Methods

    /// Loads presets and history from the DeepLinkTester singleton.
    @MainActor
    private func loadData() async {
        presets = DeepLinkTester.instance.presets
        history = DeepLinkTester.instance.history
    }

    // MARK: - Public Methods

    /// Opens the URL currently entered in ``urlText``.
    ///
    /// This method:
    /// 1. Validates that ``urlText`` is not empty
    /// 2. Shows loading state
    /// 3. Attempts to open the URL via ``DeepLinkTester``
    /// 4. Updates ``resultMessage`` and shows the result alert
    /// 5. Refreshes the history list
    ///
    /// The result is shown via ``showingResult`` and ``resultMessage``.
    func openURL() async {
        guard !urlText.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let result = await DeepLinkTester.instance.open(urlText)

        switch result {
        case .success:
            resultMessage = "Successfully opened: \(urlText)"
        case .failure(let error):
            resultMessage = "Failed to open URL: \(error.localizedDescription)"
        }

        showingResult = true
        history = DeepLinkTester.instance.history
    }

    /// Opens a preset deep link.
    ///
    /// Copies the preset's URL to ``urlText`` and calls ``openURL()``.
    ///
    /// - Parameter preset: The preset deep link to open.
    func openPreset(_ preset: DeepLinkPreset) async {
        urlText = preset.url
        await openURL()
    }

    /// Deletes a specific entry from the history.
    ///
    /// - Parameter entry: The history entry to remove.
    func deleteHistoryEntry(_ entry: DeepLinkHistoryEntry) {
        DeepLinkTester.instance.removeHistoryEntry(entry)
        history = DeepLinkTester.instance.history
    }

    /// Clears all history entries.
    ///
    /// Removes all tested URLs from the history. This action cannot be undone.
    func clearHistory() {
        DeepLinkTester.instance.clearHistory()
        history = []
    }
}
#endif
