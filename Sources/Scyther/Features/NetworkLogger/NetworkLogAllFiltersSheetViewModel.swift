//
//  NetworkLogAllFiltersSheetViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// One section of ``NetworkLogAllFiltersSheet``: a dimension and its selectable options.
struct NetworkLogFilterSection: Identifiable, Sendable {
    /// The dimension this section edits.
    let dimension: NetworkLogFilterDimension

    /// The selectable rows for the dimension, in display order.
    let options: [NetworkLogFilterOption]

    var id: String { dimension.id }
}

/// A group of sections in ``NetworkLogAllFiltersSheet``.
struct NetworkLogFilterGroupedSections: Identifiable, Sendable {
    /// The group these sections belong to.
    let group: NetworkLogFilterGroup

    /// The sections in this group, in ``NetworkLogFilterGroup/dimensions`` order.
    let sections: [NetworkLogFilterSection]

    var id: String { group.id }
}

/// View model backing ``NetworkLogAllFiltersSheet`` and the dimension pages it pushes.
///
/// The view model holds a working copy of the ``NetworkLogFilter`` and reports the whole filter
/// to its owner through `onChange` after every toggle or reset, so the list behind the sheet
/// updates live.
///
/// ## Usage
///
/// ```swift
/// let viewModel = NetworkLogAllFiltersSheetViewModel(
///     filter: listViewModel.filter,
///     options: listViewModel.options(for:)
/// ) { listViewModel.filter = $0 }
/// ```
final class NetworkLogAllFiltersSheetViewModel: ViewModel {
    /// The working filter reflected by the sheet.
    @Published private(set) var filter: NetworkLogFilter

    /// One section per dimension, in ``NetworkLogFilterDimension/allCases`` order.
    let sections: [NetworkLogFilterSection]

    /// The sections grouped for display, in ``NetworkLogFilterGroup/allCases`` order.
    var groups: [NetworkLogFilterGroupedSections] {
        NetworkLogFilterGroup.allCases.map { group in
            NetworkLogFilterGroupedSections(
                group: group,
                sections: group.dimensions.compactMap { dimension in
                    sections.first { $0.dimension == dimension }
                }
            )
        }
    }

    /// Invoked with the full filter after every change.
    private let onChange: (NetworkLogFilter) -> Void

    /// Creates a view model for the all-filters sheet.
    ///
    /// - Parameters:
    ///   - filter: The filter as it stands when the sheet opens.
    ///   - options: Supplies the selectable options for each dimension.
    ///   - onChange: Called with the full filter after every change.
    init(
        filter: NetworkLogFilter,
        options: (NetworkLogFilterDimension) -> [NetworkLogFilterOption],
        onChange: @escaping (NetworkLogFilter) -> Void
    ) {
        self.filter = filter
        self.sections = NetworkLogFilterDimension.allCases.map {
            NetworkLogFilterSection(dimension: $0, options: options($0))
        }
        self.onChange = onChange
        super.init()
    }

    /// Whether any dimension has a selection that can be reset.
    var canReset: Bool { filter.isActive }

    /// Whether a single dimension has a selection that can be reset.
    ///
    /// - Parameter dimension: The dimension to check.
    func canReset(_ dimension: NetworkLogFilterDimension) -> Bool {
        filter.selectionCount(for: dimension) > 0
    }

    /// A one-line description of a dimension's selection for its row in the root list.
    ///
    /// Returns "Any" when nothing is selected, otherwise the selected option titles in
    /// display order, comma separated.
    ///
    /// - Parameter dimension: The dimension to describe.
    func summary(for dimension: NetworkLogFilterDimension) -> String {
        let selected = filter.selection(for: dimension)
        guard !selected.isEmpty else { return localized("Any") }
        let options = sections.first { $0.dimension == dimension }?.options ?? []
        let titles = options.filter { selected.contains($0.id) }.map(\.title)
        let joined = titles.isEmpty ? selected.sorted().joined(separator: ", ") : titles.joined(separator: ", ")
        if dimension == .host, filter.hostMode == .exclude {
            return localized("Exclude: \(joined)")
        }
        return joined
    }

    /// The current host include/exclude mode.
    var hostMode: HostFilterMode { filter.hostMode }

    /// Updates the host include/exclude mode and notifies the owner.
    ///
    /// - Parameter mode: The new mode.
    func setHostMode(_ mode: HostFilterMode) {
        filter.hostMode = mode
        onChange(filter)
    }

    /// Whether an option is selected within a dimension.
    ///
    /// - Parameters:
    ///   - option: The option to check.
    ///   - dimension: The dimension the option belongs to.
    func isSelected(_ option: NetworkLogFilterOption, in dimension: NetworkLogFilterDimension) -> Bool {
        filter.selection(for: dimension).contains(option.id)
    }

    /// Adds or removes an option from a dimension's selection.
    ///
    /// For a single-select dimension, selecting an option replaces any other selection.
    ///
    /// - Parameters:
    ///   - option: The option to toggle.
    ///   - dimension: The dimension the option belongs to.
    func toggle(_ option: NetworkLogFilterOption, in dimension: NetworkLogFilterDimension) {
        var selection = filter.selection(for: dimension)
        if selection.contains(option.id) {
            selection.remove(option.id)
        } else if dimension.isSingleSelect {
            selection = [option.id]
        } else {
            selection.insert(option.id)
        }
        filter.setSelection(selection, for: dimension)
        onChange(filter)
    }

    /// Clears a single dimension.
    ///
    /// - Parameter dimension: The dimension to clear.
    func reset(_ dimension: NetworkLogFilterDimension) {
        filter.setSelection([], for: dimension)
        if dimension == .host {
            filter.hostMode = .include
        }
        onChange(filter)
    }

    /// Clears every dimension.
    func reset() {
        filter.clear()
        onChange(filter)
    }
}
