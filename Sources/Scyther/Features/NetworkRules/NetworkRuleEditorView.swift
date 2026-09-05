//
//  NetworkRuleEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// The form used to create a request override or edit an existing one.
///
/// Pushed from a row of ``NetworkRulesView`` when editing, and presented as a sheet when creating.
/// It deliberately does not wrap itself in a `NavigationStack` — the pushed case already sits in
/// one, and the sheet supplies its own — so the same view serves both. Nothing is written until
/// **Save** is tapped, and **Save** stays disabled until the override is named and given a host,
/// path or query — see ``NetworkRuleEditorViewModel/isValid``.
///
/// The Action section swaps its fields for whichever behaviour the picker names, and remembers
/// what was typed into the others, so comparing two ways of stubbing the same endpoint does not
/// mean retyping either of them.
struct NetworkRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// The view model owning the draft rule and every field binding.
    @StateObject private var viewModel: NetworkRuleEditorViewModel

    /// Whether to offer a Cancel button beside the confirm button.
    ///
    /// True when the editor is presented as a sheet, which has no other way out. False when it is
    /// pushed, where the back button already discards.
    private let showsCancel: Bool

    /// Creates the editor.
    ///
    /// The view model is built inside `StateObject`'s autoclosure rather than by the caller, so
    /// the construction — which reads the mock body off disk — happens once, when SwiftUI first
    /// needs the object, and not on every evaluation of the row or sheet that presents it.
    ///
    /// - Parameters:
    ///   - rule: The override to edit, or `nil` to create one.
    ///   - store: Where the override is written on save. Defaults to the shared store.
    ///   - showsCancel: Whether to offer a Cancel button. Pass `false` when pushing the editor,
    ///     where the back button already discards.
    init(rule: NetworkRule?, store: NetworkRuleStore = .shared, showsCancel: Bool = true) {
        _viewModel = StateObject(wrappedValue: NetworkRuleEditorViewModel(rule: rule, store: store))
        self.showsCancel = showsCancel
    }

    /// Creates the editor on an override that has been built elsewhere but not yet saved.
    ///
    /// Used by **Save as mock** on the request details page, which fills in the whole override
    /// from a captured response. Saving *adds* it, unlike ``init(rule:store:)``, which updates an
    /// override the store already holds.
    ///
    /// - Parameters:
    ///   - rule: The pre-filled override. Nothing is written until **Save** is tapped.
    ///   - store: Where the override is written on save. Defaults to the shared store.
    init(prefilled rule: NetworkRule, store: NetworkRuleStore = .shared) {
        _viewModel = StateObject(wrappedValue: NetworkRuleEditorViewModel(prefilled: rule, store: store))
        self.showsCancel = true
    }

    var body: some View {
        List {
            Section {
                TextField(localized("Name"), text: $viewModel.draft.name)
                Toggle(localized("Enabled"), isOn: $viewModel.draft.isEnabled)
            }

            Section(localized("Match")) {
                NavigationLink {
                    NetworkRuleMethodsView(viewModel: viewModel)
                } label: {
                    LabeledContent(localized("Methods"), value: viewModel.methodsSummary)
                }

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
            // Only a sheet needs a worded way out. When the editor is pushed, the navigation bar
            // already carries a back button that discards exactly as Cancel would, and offering
            // both puts two identical exits side by side.
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton {
                    viewModel.save()
                    dismiss()
                }
                .disabled(!viewModel.isValid)
            }
        }
    }
}
