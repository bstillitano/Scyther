//
//  NetworkLogFilterSheet.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// A modal checklist for choosing the accepted values of one ``NetworkLogFilterDimension``.
///
/// Presented from a chip in ``NetworkLogFilterBar``. Selections apply immediately through the
/// view model's change callback, so the list behind the sheet updates as rows are toggled.
/// A Reset button appears in the leading toolbar slot only while something is selected. The host
/// sheet adds an Include / Exclude segmented control as its section header.
struct NetworkLogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: NetworkLogFilterSheetViewModel

    /// Creates a filter sheet for one dimension.
    ///
    /// - Parameter viewModel: The view model owning the options and working selection.
    init(viewModel: NetworkLogFilterSheetViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.options.isEmpty {
                        NetworkLogFilterEmptyRow(dimensionName: viewModel.title.lowercased())
                    } else {
                        ForEach(viewModel.options) { option in
                            NetworkLogFilterOptionRow(
                                title: option.title,
                                isSelected: viewModel.isSelected(option),
                                action: { viewModel.toggle(option) }
                            )
                        }
                    }
                } header: {
                    if viewModel.supportsHostMode {
                        NetworkLogHostModePicker(mode: viewModel.hostMode, onChange: viewModel.setHostMode)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.canReset {
                        Button(localized("Reset")) { viewModel.reset() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    NetworkLogFilterConfirmButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
