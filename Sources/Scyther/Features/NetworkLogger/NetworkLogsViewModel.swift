//
//  NetworkLogsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import Foundation
import Combine

/// View model for managing network request logs and search functionality.
///
/// `NetworkLogsViewModel` handles fetching network requests from `NetworkLogger`,
/// filtering them based on search criteria, and managing the async stream subscription.
/// It uses Combine for debounced search and background filtering for performance.
///
/// ## Features
/// - Real-time updates from `NetworkLogger`
/// - Debounced search (300ms delay)
/// - Background filtering for better performance
/// - Automatic cleanup on deinitialization
///
/// ## Usage
/// ```swift
/// @StateObject private var viewModel = NetworkLogsViewModel()
///
/// // Set search term
/// viewModel.setSearchTerm(to: "api.example.com")
/// ```
class NetworkLogsViewModel: ViewModel {
    /// Published array of filtered network requests to display in the UI.
    @Published var requests: [HTTPRequest] = []

    /// Current search term used for filtering requests.
    private var searchTerm: String = ""

    /// Subject for debouncing search input.
    private var searchSubject = PassthroughSubject<String, Never>()

    /// Set of Combine cancellables for cleanup.
    private var cancellables = Set<AnyCancellable>()

    /// Reference to the network logger singleton.
    private var networkLogger: NetworkLogger = NetworkLogger.instance

    /// Task for listening to network logger updates.
    private var updateTask: Task<Void, Never>?

    /// Task for filtering requests in the background.
    private var filterTask: Task<Void, Never>?

    /// Internal array of all network requests before filtering.
    private var items: [HTTPRequest] = [] {
        didSet {
            scheduleFilter()
        }
    }

    /// Cleans up tasks when the view model is deallocated.
    deinit {
        updateTask?.cancel()
        filterTask?.cancel()
    }

    /// Sets up the view model by initializing search debouncing and starting the network logger subscription.
    override func setup() {
        super.setup()

        // Debounce search input by 300ms
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] term in
                self?.searchTerm = term
                self?.scheduleFilter()
            }
            .store(in: &cancellables)

        startListening()
    }

    /// Starts listening to network logger updates via async stream.
    ///
    /// This method subscribes to the network logger's update stream and updates
    /// the internal items array whenever new requests are logged.
    private func startListening() {
        updateTask = Task {
            for await updatedItems in await networkLogger.updates {
                await MainActor.run {
                    self.items = Array(updatedItems)
                }
            }
        }
    }

    /// Sets the search term for filtering network requests.
    ///
    /// The search is debounced by 300ms to avoid excessive filtering operations
    /// while the user is still typing.
    ///
    /// - Parameter searchTerm: The search text to filter requests by.
    func setSearchTerm(to searchTerm: String) {
        searchSubject.send(searchTerm)
    }

    /// Schedules a background filtering operation.
    ///
    /// Cancels any existing filter task and starts a new one. This ensures
    /// only the most recent search request is processed.
    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task {
            await updateData()
        }
    }

    /// Filters the network requests based on the current search term.
    ///
    /// If the search term is empty, all requests are shown. Otherwise, filtering
    /// is performed on a background thread and matches requests where the search
    /// term appears in the URL, status code, or HTTP method.
    @MainActor
    private func updateData() async {
        let currentItems = items
        let currentSearchTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentSearchTerm.isEmpty {
            requests = currentItems
        } else {
            // Filter on background thread
            let filtered = await Task.detached(priority: .userInitiated) {
                let predicate = currentSearchTerm.lowercased()
                return currentItems.filter { item in
                    item.responseCode?.description.lowercased().contains(predicate) == true ||
                    item.requestURL?.lowercased().contains(predicate) == true ||
                    item.requestMethod?.lowercased().contains(predicate) == true
                }
            }.value

            // Check if task was cancelled before updating
            guard !Task.isCancelled else { return }
            requests = filtered
        }
    }
}
