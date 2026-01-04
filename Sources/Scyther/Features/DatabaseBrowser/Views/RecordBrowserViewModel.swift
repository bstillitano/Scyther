//
//  RecordBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the record browser view.
///
/// Manages the loading, pagination, and CRUD operations for table records.
@MainActor
final class RecordBrowserViewModel: ViewModel {
    // MARK: - Properties

    /// The adapter for the database.
    let adapter: any DatabaseBrowserAdapter

    /// The table being browsed.
    let table: TableInfo

    /// The number of records to load per page.
    let pageSize: Int = 50

    // MARK: - Published Properties

    /// The loaded records.
    @Published var records: [DatabaseRecord] = []

    /// The total count of records in the table.
    @Published var totalCount: Int = 0

    /// Whether records are loading.
    @Published var isLoading: Bool = false

    /// Whether more records are available.
    @Published var hasMore: Bool = false

    /// Whether an error occurred.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    /// The record selected for deletion.
    @Published var recordToDelete: DatabaseRecord?

    /// Whether the delete confirmation is showing.
    @Published var showingDeleteConfirmation: Bool = false

    /// The table schema.
    @Published var schema: TableSchema?

    // MARK: - Private Properties

    private var currentOffset: Int = 0

    // MARK: - Initialization

    init(adapter: any DatabaseBrowserAdapter, table: TableInfo) {
        self.adapter = adapter
        self.table = table
        super.init()
    }

    // MARK: - Lifecycle

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSchema()
        await refresh()
    }

    // MARK: - Actions

    /// Loads the table schema.
    func loadSchema() async {
        do {
            schema = try await adapter.schema(for: table.name)
        } catch {
            // Schema loading is optional, continue without it
        }
    }

    /// Refreshes the record list from the beginning.
    func refresh() async {
        currentOffset = 0
        records = []
        await loadRecords()
        await loadTotalCount()
    }

    /// Loads more records (pagination).
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await loadRecords()
    }

    /// Deletes the selected record.
    func deleteRecord() async {
        guard let record = recordToDelete,
              let primaryKey = record.primaryKey else {
            return
        }

        do {
            try await adapter.delete(from: table.name, primaryKey: primaryKey)
            records.removeAll { $0.id == record.id }
            totalCount -= 1
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }

        recordToDelete = nil
    }

    // MARK: - Private Methods

    private func loadRecords() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let orderBy = schema?.primaryKeyColumn?.name
            let newRecords = try await adapter.records(
                in: table.name,
                offset: currentOffset,
                limit: pageSize,
                orderBy: orderBy,
                ascending: true
            )

            records.append(contentsOf: newRecords)
            currentOffset += newRecords.count
            hasMore = newRecords.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadTotalCount() async {
        do {
            totalCount = try await adapter.recordCount(in: table.name)
        } catch {
            // Count loading is optional
        }
    }
}
#endif
