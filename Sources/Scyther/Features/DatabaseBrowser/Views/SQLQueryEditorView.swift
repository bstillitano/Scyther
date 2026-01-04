//
//  SQLQueryEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Raw SQL query editor with results display.
struct SQLQueryEditorView: View {
    let adapter: any DatabaseBrowserAdapter

    @StateObject private var viewModel: SQLQueryEditorViewModel
    @State private var queryText = ""
    @FocusState private var isEditorFocused: Bool

    init(adapter: any DatabaseBrowserAdapter) {
        self.adapter = adapter
        _viewModel = StateObject(wrappedValue: SQLQueryEditorViewModel(adapter: adapter))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Query Editor
            VStack(alignment: .leading, spacing: 8) {
                Text("SQL Query")
                    .font(.headline)
                    .padding(.horizontal)

                TextEditor(text: $queryText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .focused($isEditorFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Button {
                        Task { await viewModel.execute(queryText) }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Execute")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isExecuting)

                    if viewModel.isExecuting {
                        ProgressView()
                            .padding(.leading, 8)
                    }

                    Spacer()

                    Button("Clear") {
                        queryText = ""
                        viewModel.clearResults()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)

            Divider()

            // Results
            resultsView
        }
        .navigationTitle("SQL Query")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    // MARK: - Results View

    @ViewBuilder
    private var resultsView: some View {
        if let result = viewModel.result {
            if result.isReadOnly {
                // SELECT results - show as list
                List {
                    Section {
                        if let executionTime = result.executionTime {
                            LabeledContent("Execution Time", value: String(format: "%.3f ms", executionTime * 1000))
                        }
                        LabeledContent("Rows", value: "\(result.rows.count)")
                    } header: {
                        Text("Query Info")
                    }

                    if result.rows.isEmpty {
                        Section {
                            emptyStateView(
                                title: "No Results",
                                systemImage: "doc.text",
                                description: "Query returned no rows."
                            )
                        }
                    } else {
                        Section {
                            ForEach(Array(result.rows.enumerated()), id: \.offset) { index, row in
                                rowView(row: row, index: index, columns: result.columns)
                            }
                        } header: {
                            Text("Results")
                        }
                    }
                }
            } else {
                // Non-SELECT results
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Query Executed Successfully")
                        .font(.headline)
                        .padding(.top, 8)
                    Text("\(result.rowsAffected) row(s) affected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let executionTime = result.executionTime {
                        Text(String(format: "%.3f ms", executionTime * 1000))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        } else if let error = viewModel.errorMessage {
            VStack {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.headline)
                    .padding(.top, 8)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Enter a SQL query and press Execute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rowView(row: [String: DatabaseValue], index: Int, columns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Row \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(columns, id: \.self) { column in
                HStack(spacing: 4) {
                    Text(column)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

                    Text(row[column]?.displayString ?? "NULL")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                let rowString = columns.map { "\($0): \(row[$0]?.displayString ?? "NULL")" }.joined(separator: "\n")
                UIPasteboard.general.string = rowString
            } label: {
                Label("Copy Row", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func emptyStateView(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
#endif
