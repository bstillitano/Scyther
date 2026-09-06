//
//  NetworkRuleMethodsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// The HTTP method checklist, pushed from the Match section of ``NetworkRuleEditorView``.
///
/// Multi-selection in this toolkit is a `NavigationLink` row summarising the selection over a
/// sub-page of checkmark rows, so the same shape is reused here rather than filling the editor
/// with one switch per method.
///
/// The rows are ``NetworkLogFilterOptionRow``, the same checklist row the network log filter
/// sheets use, so a method behaves exactly like a host or a status code does over there.
///
/// It holds no state of its own: selection lives on ``NetworkRuleEditorViewModel`` alongside the
/// rest of the draft, which is where the tests reach it, so this page needs no view model.
///
/// ## Usage
/// ```swift
/// NavigationLink {
///     NetworkRuleMethodsView(viewModel: viewModel)
/// } label: {
///     LabeledContent(localized("Methods"), value: viewModel.methodsSummary)
/// }
/// ```
struct NetworkRuleMethodsView: View {
    /// The editor's view model, which owns the draft's selected methods.
    @ObservedObject var viewModel: NetworkRuleEditorViewModel

    var body: some View {
        List {
            Section {
                ForEach(NetworkRuleEditorViewModel.availableMethods, id: \.self) { method in
                    NetworkLogFilterOptionRow(
                        title: method,
                        isSelected: viewModel.isSelected(method: method),
                        action: { viewModel.toggle(method: method) }
                    )
                }
            } footer: {
                Text(localized("Select no methods to match any method."))
            }
        }
        .navigationTitle(localized("Methods"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
