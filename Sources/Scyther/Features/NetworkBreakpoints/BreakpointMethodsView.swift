//
//  BreakpointMethodsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The HTTP method checklist, pushed from the Match section of ``BreakpointEditorView``.
///
/// Multi-selection in this toolkit is a `NavigationLink` row summarising the selection over a
/// sub-page of checkmark rows, so the same shape is reused here — and the rows are
/// ``NetworkLogFilterOptionRow``, the same checklist row the network log filter sheets and the
/// override editor use.
///
/// It holds no state of its own: selection lives on ``BreakpointEditorViewModel`` alongside the
/// rest of the draft, which is where the tests reach it, so this page needs no view model.
struct BreakpointMethodsView: View {
    /// The editor's view model, which owns the draft's selected methods.
    @ObservedObject var viewModel: BreakpointEditorViewModel

    var body: some View {
        List {
            Section {
                ForEach(BreakpointEditorViewModel.availableMethods, id: \.self) { method in
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
