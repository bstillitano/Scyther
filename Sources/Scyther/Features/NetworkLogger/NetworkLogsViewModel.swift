//
//  NetworkLogsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import Foundation
import Combine

class NetworkLogsViewModel: ViewModel {
    @Published var requests: [HTTPRequest] = []

    private var searchTerm: String = ""
    private var searchSubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()

    private var networkLogger: NetworkLogger = NetworkLogger.instance
    private var updateTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var items: [HTTPRequest] = [] {
        didSet {
            scheduleFilter()
        }
    }

    deinit {
        updateTask?.cancel()
        filterTask?.cancel()
    }

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

    private func startListening() {
        updateTask = Task {
            for await updatedItems in await networkLogger.updates {
                await MainActor.run {
                    self.items = Array(updatedItems)
                }
            }
        }
    }

    func setSearchTerm(to searchTerm: String) {
        searchSubject.send(searchTerm)
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task {
            await updateData()
        }
    }

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
