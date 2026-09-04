//
//  NetworkLogAllFiltersSheet.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// A full-height sheet listing every ``NetworkLogFilterDimension`` as a row that pushes its own page.
///
/// Presented from the leading icon-only chip in ``NetworkLogFilterBar``. Rows are sectioned by
/// ``NetworkLogFilterGroup`` (Request, Response, Timing). Each row shows the dimension's icon,
/// title, and a summary of its current selection. Tapping a row pushes
/// ``NetworkLogFilterDimensionPage`` for that dimension. Selections apply immediately through the
/// view model's change callback. A Reset button appears in the leading toolbar slot only while any
/// dimension has a selection.
struct NetworkLogAllFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: NetworkLogAllFiltersSheetViewModel

    /// Creates the all-filters sheet.
    ///
    /// - Parameter viewModel: The view model owning the sections and working filter.
    init(viewModel: NetworkLogAllFiltersSheetViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.groups) { grouped in
                    Section(grouped.group.title) {
                        ForEach(grouped.sections) { section in
                            NavigationLink {
                                NetworkLogFilterDimensionPage(viewModel: viewModel, section: section)
                            } label: {
                                LabeledContent {
                                    Text(viewModel.summary(for: section.dimension))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                } label: {
                                    Label(section.dimension.title, systemImage: section.dimension.systemImage)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.canReset {
                        Button("Reset") { viewModel.reset() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    NetworkLogFilterConfirmButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The pushed page for one dimension inside ``NetworkLogAllFiltersSheet``.
///
/// Shows the dimension's options as a checklist backed by the shared
/// ``NetworkLogAllFiltersSheetViewModel``. A Reset button for this dimension alone appears in the
/// trailing toolbar slot while it has a selection. The host page adds an Include / Exclude
/// segmented control as its section header.
struct NetworkLogFilterDimensionPage: View {
    @ObservedObject var viewModel: NetworkLogAllFiltersSheetViewModel

    /// The dimension and options this page edits.
    let section: NetworkLogFilterSection

    var body: some View {
        List {
            Section {
                if section.options.isEmpty {
                    NetworkLogFilterEmptyRow(dimensionName: section.dimension.title.lowercased())
                } else {
                    ForEach(section.options) { option in
                        NetworkLogFilterOptionRow(
                            title: option.title,
                            isSelected: viewModel.isSelected(option, in: section.dimension),
                            action: { viewModel.toggle(option, in: section.dimension) }
                        )
                    }
                }
            } header: {
                if section.dimension == .host {
                    NetworkLogHostModePicker(mode: viewModel.hostMode, onChange: viewModel.setHostMode)
                }
            }
        }
        .navigationTitle(section.dimension.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.canReset(section.dimension) {
                    Button("Reset") { viewModel.reset(section.dimension) }
                }
            }
        }
    }
}
