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
/// - Chip-driven filtering by method, status class, host, content type, API kind, GraphQL operation, duration,
///   exact status code, and recency via ``NetworkLogFilter``
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

    /// The chip-driven filter applied alongside the search term.
    ///
    /// Changing this value re-runs filtering immediately (no debounce).
    @Published var filter: NetworkLogFilter = NetworkLogFilter() {
        didSet {
            guard filter != oldValue else { return }
            scheduleFilter()
        }
    }

    /// The distinct HTTP methods present in the captured logs, uppercased and sorted.
    @Published private(set) var availableMethods: [String] = []

    /// The distinct request hosts present in the captured logs, lowercased and sorted.
    @Published private(set) var availableHosts: [String] = []

    /// The distinct response status codes present in the captured logs, sorted ascending.
    @Published private(set) var availableStatusCodes: [Int] = []

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
            availableMethods = Self.availableMethods(in: items)
            availableHosts = Self.availableHosts(in: items)
            availableStatusCodes = Self.availableStatusCodes(in: items)
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

    /// Filters requests by matching the search term against URL, operation name, status code, or method,
    /// and by the chip-driven ``NetworkLogFilter``.
    ///
    /// - Parameters:
    ///   - items: The requests to filter.
    ///   - searchTerm: The raw search term (case-insensitive; whitespace is trimmed).
    ///   - filter: The dimension constraints to apply. Defaults to an empty filter.
    /// - Returns: All items when the term is empty and the filter is inactive, otherwise the matching subset.
    nonisolated static func filter(
        items: [HTTPRequest],
        searchTerm: String,
        filter: NetworkLogFilter = NetworkLogFilter()
    ) -> [HTTPRequest] {
        let predicate = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !predicate.isEmpty || filter.isActive else { return items }
        return items.filter { item in
            guard filter.matches(item) else { return false }
            guard !predicate.isEmpty else { return true }
            return item.responseCode?.description.lowercased().contains(predicate) == true ||
                item.requestURL?.lowercased().contains(predicate) == true ||
                item.requestMethod?.lowercased().contains(predicate) == true ||
                item.graphQLOperationName?.lowercased().contains(predicate) == true
        }
    }

    /// The distinct HTTP methods present in `items`, uppercased and sorted.
    ///
    /// - Parameter items: The requests to inspect.
    nonisolated static func availableMethods(in items: [HTTPRequest]) -> [String] {
        Set(items.compactMap { $0.requestMethod?.uppercased() }).sorted()
    }

    /// The distinct request hosts present in `items`, lowercased and sorted.
    ///
    /// - Parameter items: The requests to inspect.
    nonisolated static func availableHosts(in items: [HTTPRequest]) -> [String] {
        Set(items.compactMap(\.host)).sorted()
    }

    /// The distinct response status codes present in `items`, sorted ascending.
    ///
    /// Requests with no response (a `nil` or zero code) are excluded.
    ///
    /// - Parameter items: The requests to inspect.
    nonisolated static func availableStatusCodes(in items: [HTTPRequest]) -> [Int] {
        Set(items.compactMap { $0.responseCode }.filter { $0 > 0 }).sorted()
    }

    /// The selectable options for a filter dimension.
    ///
    /// Method, host, and exact status code options are derived from the captured logs; every
    /// other dimension uses its fixed list from ``NetworkLogFilterOption/staticOptions(for:)``.
    ///
    /// - Parameter dimension: The dimension being edited.
    func options(for dimension: NetworkLogFilterDimension) -> [NetworkLogFilterOption] {
        switch dimension {
        case .method:
            return availableMethods.map { NetworkLogFilterOption(id: $0, title: $0) }
        case .host:
            return availableHosts.map { NetworkLogFilterOption(id: $0, title: $0) }
        case .statusCode:
            return availableStatusCodes.map { NetworkLogFilterOption(id: String($0), title: String($0)) }
        case .status, .contentType, .api, .graphQL, .duration, .recency:
            return NetworkLogFilterOption.staticOptions(for: dimension)
        }
    }

    /// The text shown on a dimension's chip.
    ///
    /// Returns the dimension title when nothing is selected, the selected option's title when
    /// exactly one value is selected (prefixed with "Not " for a single excluded host), and
    /// "Title · N" when several are selected.
    ///
    /// - Parameter dimension: The dimension whose chip is being drawn.
    func chipTitle(for dimension: NetworkLogFilterDimension) -> String {
        let selected = filter.selection(for: dimension)
        switch selected.count {
        case 0:
            return dimension.title
        case 1:
            let id = selected.first ?? ""
            let title = options(for: dimension).first { $0.id == id }?.title ?? id
            if dimension == .host, filter.hostMode == .exclude {
                return "Not \(title)"
            }
            return title
        default:
            return "\(dimension.title) · \(selected.count)"
        }
    }

    /// Removes every chip constraint.
    func clearFilter() {
        filter.clear()
    }

    /// Filters the network requests based on the current search term.
    ///
    /// If the search term is empty, all requests are shown. Otherwise, filtering
    /// is performed on a background thread and matches requests where the search
    /// term appears in the URL, operation name, status code, or HTTP method.
    @MainActor
    private func updateData() async {
        let currentItems = items
        let currentSearchTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFilter = filter

        if currentSearchTerm.isEmpty && !currentFilter.isActive {
            requests = currentItems
        } else {
            // Filter on background thread
            let filtered = await Task.detached(priority: .userInitiated) {
                Self.filter(items: currentItems, searchTerm: currentSearchTerm, filter: currentFilter)
            }.value

            // Check if task was cancelled before updating
            guard !Task.isCancelled else { return }
            requests = filtered
        }
    }
    
    func didPressDeleteButton() async {
        await networkLogger.clear()
    }
}
