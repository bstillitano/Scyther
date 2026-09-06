//
//  BreakpointEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The form used to create a breakpoint or edit an existing one.
///
/// Pushed from a row of ``BreakpointsView`` when editing, and presented as a sheet when creating.
/// It deliberately does not wrap itself in a `NavigationStack` — the pushed case already sits in
/// one, and the sheet supplies its own — so the same view serves both.
///
/// The match section is the override editor's, field for field, because a breakpoint matches with
/// the same ``NetworkRuleMatch`` a rule does. Anything that reads differently here would be a
/// second set of semantics for the same value.
struct BreakpointEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// The view model owning the draft and every field binding.
    @StateObject private var viewModel: BreakpointEditorViewModel

    /// Whether to offer a Cancel button beside the confirm button.
    ///
    /// True when the editor is presented as a sheet, which has no other way out. False when it is
    /// pushed, where the back button already discards.
    private let showsCancel: Bool

    /// Creates the editor.
    ///
    /// - Parameters:
    ///   - breakpoint: The breakpoint to edit, or `nil` to create one.
    ///   - store: Where the breakpoint is written on save. Defaults to the shared store.
    ///   - showsCancel: Whether to offer a Cancel button. Pass `false` when pushing the editor,
    ///     where the back button already discards.
    init(breakpoint: NetworkBreakpoint?, store: BreakpointStore = .shared, showsCancel: Bool = true) {
        _viewModel = StateObject(wrappedValue: BreakpointEditorViewModel(breakpoint: breakpoint, store: store))
        self.showsCancel = showsCancel
    }

    /// Creates the editor on a breakpoint that does not exist yet but is already filled in — the
    /// one **Break on requests like this** builds from a log entry.
    ///
    /// Saving *adds* it, unlike ``init(breakpoint:store:showsCancel:)``, which updates a
    /// breakpoint the store already holds.
    ///
    /// - Parameters:
    ///   - breakpoint: The pre-filled breakpoint. Nothing is written until it is confirmed.
    ///   - store: Where the breakpoint is written on save. Defaults to the shared store.
    init(prefilled breakpoint: NetworkBreakpoint, store: BreakpointStore = .shared) {
        _viewModel = StateObject(wrappedValue: BreakpointEditorViewModel(prefilled: breakpoint, store: store))
        self.showsCancel = true
    }

    var body: some View {
        List {
            Section {
                TextField(localized("Name"), text: $viewModel.draft.name)
                Toggle(localized("Enabled"), isOn: $viewModel.draft.isEnabled)
            }

            matchSection
            stageSection
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only a sheet needs a worded way out. When the editor is pushed, the navigation bar
            // already carries a back button that discards exactly as Cancel would.
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton {
                    if viewModel.save() { dismiss() }
                }
                .disabled(!viewModel.isValid)
            }
        }
    }

    /// The facets a request has to satisfy before it is held.
    private var matchSection: some View {
        Section {
            NavigationLink {
                BreakpointMethodsView(viewModel: viewModel)
            } label: {
                LabeledContent(localized("Methods"), value: viewModel.methodsSummary)
            }

            TextField(localized("Host"), text: $viewModel.hostText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Picker(localized("Host matching"), selection: $viewModel.hostKind) {
                ForEach(BreakpointEditorViewModel.patternKinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            TextField(localized("Path"), text: $viewModel.pathText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Picker(localized("Path matching"), selection: $viewModel.pathKind) {
                ForEach(BreakpointEditorViewModel.patternKinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        } header: {
            Text(localized("Match"))
        } footer: {
            Text(localized("The path is matched exactly as it appears on the wire, including percent-encoding."))
        }
    }

    /// Which side of the exchange is held, and for how long.
    private var stageSection: some View {
        Section {
            Picker(localized("Stage"), selection: $viewModel.draft.stage) {
                ForEach(NetworkBreakpoint.Stage.allCases) { stage in
                    Text(stage.title).tag(stage)
                }
            }

            Stepper(value: $viewModel.timeout,
                    in: NetworkBreakpoint.timeoutRange,
                    step: BreakpointEditorViewModel.timeoutStep) {
                LabeledContent(localized("Timeout"), value: viewModel.timeoutText)
            }
        } header: {
            Text(localized("Stage"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("A held exchange continues on its own, unchanged, once the timeout elapses. It cannot be switched off."))
                if viewModel.draft.stage.holdsResponse {
                    Text(localized("Holding a response buffers the whole body before the app sees any of it, so avoid setting one on a large download."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
