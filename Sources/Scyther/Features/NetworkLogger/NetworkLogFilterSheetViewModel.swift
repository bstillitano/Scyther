//
//  NetworkLogFilterSheetViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// View model backing ``NetworkLogFilterSheet``, the per-dimension checklist presented from a filter chip.
///
/// The view model owns the working selection for a single ``NetworkLogFilterDimension`` and
/// reports every change to its owner through `onChange`, so the list behind the sheet updates live.
///
/// ## Usage
///
/// ```swift
/// let viewModel = NetworkLogFilterSheetViewModel(
///     dimension: .method,
///     options: listViewModel.options(for: .method),
///     selected: listViewModel.filter.selection(for: .method)
/// ) { listViewModel.filter.setSelection($0, for: .method) }
/// ```
final class NetworkLogFilterSheetViewModel: ViewModel {
    /// The dimension being edited.
    let dimension: NetworkLogFilterDimension

    /// The selectable rows, in display order.
    let options: [NetworkLogFilterOption]

    /// The ids of the currently selected options.
    @Published private(set) var selected: Set<String>

    /// Whether the selected hosts are included or excluded. Only meaningful for the host dimension.
    @Published private(set) var hostMode: HostFilterMode

    /// Invoked with the full selection after every change.
    private let onChange: (Set<String>) -> Void

    /// Invoked with the new host mode after it changes.
    private let onHostModeChange: (HostFilterMode) -> Void

    /// Creates a sheet view model for one filter dimension.
    ///
    /// - Parameters:
    ///   - dimension: The dimension being edited.
    ///   - options: The selectable rows.
    ///   - selected: The ids selected when the sheet opens.
    ///   - hostMode: The host include/exclude mode when the sheet opens. Ignored for other dimensions.
    ///   - onChange: Called with the full selection after every change.
    ///   - onHostModeChange: Called with the new mode after ``setHostMode(_:)``.
    init(
        dimension: NetworkLogFilterDimension,
        options: [NetworkLogFilterOption],
        selected: Set<String>,
        hostMode: HostFilterMode = .include,
        onChange: @escaping (Set<String>) -> Void,
        onHostModeChange: @escaping (HostFilterMode) -> Void = { _ in }
    ) {
        self.dimension = dimension
        self.options = options
        self.selected = selected
        self.hostMode = hostMode
        self.onChange = onChange
        self.onHostModeChange = onHostModeChange
        super.init()
    }

    /// Whether this sheet shows the include/exclude control. True only for the host dimension.
    var supportsHostMode: Bool { dimension == .host }

    /// Updates the host include/exclude mode and notifies the owner.
    ///
    /// - Parameter mode: The new mode.
    func setHostMode(_ mode: HostFilterMode) {
        hostMode = mode
        onHostModeChange(mode)
    }

    /// The navigation title for the sheet.
    var title: String { dimension.title }

    /// The number of selected options.
    var selectedCount: Int { selected.count }

    /// Whether the sheet has a selection that can be reset.
    var canReset: Bool { !selected.isEmpty }

    /// Whether an option is currently selected.
    ///
    /// - Parameter option: The option to check.
    func isSelected(_ option: NetworkLogFilterOption) -> Bool {
        selected.contains(option.id)
    }

    /// Adds or removes an option from the selection.
    ///
    /// For a single-select dimension, selecting an option replaces any other selection.
    ///
    /// - Parameter option: The option to toggle.
    func toggle(_ option: NetworkLogFilterOption) {
        if selected.contains(option.id) {
            selected.remove(option.id)
        } else if dimension.isSingleSelect {
            selected = [option.id]
        } else {
            selected.insert(option.id)
        }
        onChange(selected)
    }

    /// Clears the selection, which removes this dimension's constraint.
    func reset() {
        selected = []
        onChange(selected)
    }
}
