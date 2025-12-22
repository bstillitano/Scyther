//
//  CrashDetailsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import Foundation
import UIKit

/// View model for managing the crash details view.
///
/// `CrashDetailsViewModel` handles the state and logic for displaying
/// detailed crash information, including stack trace filtering and
/// clipboard operations.
///
/// ## Features
/// - Stack trace search and filtering with highlighting
/// - Copy to clipboard with visual feedback
/// - Formatted crash report generation for sharing
///
/// ## Usage
/// ```swift
/// @StateObject private var viewModel: CrashDetailsViewModel
///
/// init(crash: CrashLogEntry) {
///     _viewModel = StateObject(wrappedValue: CrashDetailsViewModel(crash: crash))
/// }
///
/// // Filter stack trace
/// viewModel.searchText = "UIKit"
/// let filtered = viewModel.filteredStackTrace
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``crash``
/// - ``searchText``
/// - ``copied``
/// - ``filteredStackTrace``
///
/// ### Methods
/// - ``copyToClipboard()``
@MainActor
class CrashDetailsViewModel: ViewModel {
    // MARK: - Properties

    /// The crash log entry being displayed.
    let crash: CrashLogEntry

    // MARK: - Published Properties

    /// The current search text for filtering the stack trace.
    ///
    /// When set, ``filteredStackTrace`` will only include frames
    /// that contain this text (case-insensitive).
    @Published var searchText: String = ""

    /// Whether the crash report was recently copied to clipboard.
    ///
    /// This property is automatically reset to `false` after 2 seconds
    /// to provide visual feedback for the copy action.
    @Published var copied: Bool = false

    // MARK: - Computed Properties

    /// Stack trace entries filtered by the current search text.
    ///
    /// Each entry includes its original index and the symbol text.
    /// If ``searchText`` is empty, all frames are returned.
    var filteredStackTrace: [(index: Int, symbol: String)] {
        let indexed = crash.stackTrace.enumerated().map { (index: $0.offset, symbol: $0.element) }
        if searchText.isEmpty {
            return indexed
        }
        return indexed.filter { $0.symbol.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Initialization

    /// Creates a new crash details view model.
    ///
    /// - Parameter crash: The crash log entry to display details for.
    init(crash: CrashLogEntry) {
        self.crash = crash
        super.init()
    }

    // MARK: - Public Methods

    /// Copies the full crash report to the clipboard.
    ///
    /// This method copies ``CrashLogEntry/fullReport`` to the system
    /// clipboard and sets ``copied`` to `true` for visual feedback.
    /// The `copied` flag is automatically reset after 2 seconds.
    func copyToClipboard() {
        UIPasteboard.general.string = crash.fullReport
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                copied = false
            }
        }
    }
}
#endif
