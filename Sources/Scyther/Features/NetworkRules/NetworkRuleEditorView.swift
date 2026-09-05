//
//  NetworkRuleEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// The form used to create a network rule or edit an existing one.
///
/// Presented as a sheet from ``NetworkRulesView``. Nothing is written until **Save** is tapped,
/// and **Save** stays disabled until the rule is named and constrains at least one facet of a
/// request — see ``NetworkRuleEditorViewModel/isValid``.
///
/// The Action section swaps its fields for whichever behaviour the picker names, and remembers
/// what was typed into the others, so comparing two ways of stubbing the same endpoint does not
/// mean retyping either of them.
struct NetworkRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// The view model owning the draft rule and every field binding.
    @StateObject private var viewModel: NetworkRuleEditorViewModel

    /// Creates the editor.
    ///
    /// - Parameter viewModel: The view model owning the draft rule.
    init(viewModel: NetworkRuleEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(localized("Name"), text: $viewModel.draft.name)
                    Toggle(localized("Enabled"), isOn: $viewModel.draft.isEnabled)
                }

                Section {
                    ForEach(NetworkRuleEditorViewModel.availableMethods, id: \.self) { method in
                        Toggle(method, isOn: Binding(
                            get: { viewModel.isSelected(method: method) },
                            set: { _ in viewModel.toggle(method: method) }
                        ))
                    }
                } header: {
                    Text(localized("Methods"))
                } footer: {
                    Text(localized("Leave every method off to match any method."))
                }

                Section(localized("Match")) {
                    TextField(localized("Host"), text: $viewModel.hostText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Picker(localized("Host matching"), selection: $viewModel.hostKind) {
                        ForEach(NetworkRuleEditorViewModel.patternKinds, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField(localized("Path"), text: $viewModel.pathText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Picker(localized("Path matching"), selection: $viewModel.pathKind) {
                        ForEach(NetworkRuleEditorViewModel.patternKinds, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }

                Section(localized("Action")) {
                    Picker(localized("Action"), selection: $viewModel.actionKind) {
                        ForEach(NetworkRuleActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }

                NetworkRuleActionFields(viewModel: viewModel)
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Save")) {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}
