//
//  NetworkRulesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// The list of network rules, reached from **Networking → Network Rules**.
///
/// Each row is a `Toggle` whose label names the rule and the behaviour it performs, so tapping
/// anywhere on the row turns the rule on or off. Editing is a leading swipe action, deletion a
/// trailing one, and reordering — which is what changes a rule's precedence — is done through the
/// `EditButton`.
///
/// ## Features
/// - A master switch that suspends every rule without deleting any of them
/// - Per-rule enable toggles, editing and swipe-to-delete behind a confirmation alert
/// - Drag-to-reorder, because the first matching mock or map-local rule wins
/// - HAR import through the system file importer, reporting how many rules were added
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     NetworkRulesView()
/// }
/// ```
struct NetworkRulesView: View {
    /// The list's view model, mirroring ``NetworkRuleStore``.
    @StateObject private var viewModel = NetworkRulesViewModel()

    /// The rule being edited, or a new one, presented as a sheet. `nil` while none is open.
    @State private var editorTarget: NetworkRuleEditorTarget?

    /// Whether the system file importer is presented.
    @State private var isImportingHAR: Bool = false

    /// The content types the file importer accepts.
    ///
    /// Falls back to JSON in the impossible case that the system cannot derive a type for the
    /// `har` extension, so the importer can never open with nothing selectable.
    private var harContentTypes: [UTType] {
        [UTType(filenameExtension: "har") ?? .json]
    }

    var body: some View {
        List {
            Section {
                Toggle(localized("Enable Rules"), isOn: $viewModel.isEnabled)
            } footer: {
                Text(localized("Rules are applied in order. The first matching mock or map local wins."))
            }

            if viewModel.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    ForEach(viewModel.rules) { rule in
                        ruleRow(for: rule)
                    }
                    .onDelete { viewModel.requestDeletion(at: $0) }
                    .onMove { viewModel.move(from: $0, to: $1) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .sheet(item: $editorTarget) { target in
            NetworkRuleEditorView(viewModel: NetworkRuleEditorViewModel(rule: target.rule))
        }
        .fileImporter(
            isPresented: $isImportingHAR,
            allowedContentTypes: harContentTypes
        ) { result in
            switch result {
            case .success(let url): viewModel.importHAR(from: url)
            case .failure: viewModel.reportImportFailure()
            }
        }
        .alert(
            localized("Delete \(viewModel.pendingDeletion?.name ?? "")?"),
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.cancelDeletion() } }
            )
        ) {
            Button(localized("Cancel"), role: .cancel) { viewModel.cancelDeletion() }
            Button(localized("Delete"), role: .destructive) { viewModel.confirmDeletion() }
        } message: {
            Text(localized("This action cannot be undone."))
        }
        .alert(
            viewModel.importOutcome?.title ?? "",
            isPresented: Binding(
                get: { viewModel.importOutcome != nil },
                set: { if !$0 { viewModel.importOutcome = nil } }
            ),
            presenting: viewModel.importOutcome
        ) { _ in
            Button(localized("OK"), role: .cancel) { viewModel.importOutcome = nil }
        } message: { outcome in
            Text(outcome.message)
        }
        .navigationTitle(localized("Network Rules"))
    }

    /// The toolbar menu offering the two ways to add rules.
    private var addMenu: some View {
        Menu {
            Button {
                editorTarget = NetworkRuleEditorTarget(rule: nil)
            } label: {
                Label(localized("New rule"), systemImage: "plus")
            }
            Button {
                isImportingHAR = true
            } label: {
                Label(localized("Import from HAR"), systemImage: "square.and.arrow.down")
            }
        } label: {
            // An icon-only `Label` rather than a bare `Image`: the title is what VoiceOver reads,
            // so the button keeps a name without an `accessibilityLabel` wrapping the menu itself.
            Label(localized("Add"), systemImage: "plus")
                .labelStyle(.iconOnly)
        }
    }

    /// One rule's row: a toggle labelled with the rule's name and the behaviour it performs.
    private func ruleRow(for rule: NetworkRule) -> some View {
        Toggle(isOn: Binding(
            get: { rule.isEnabled },
            set: { viewModel.setEnabled(rule, to: $0) }
        )) {
            // A two-`Text` label is the stock way to give a row a title and a subtitle; SwiftUI
            // styles the second line itself, so nothing here restyles the control by hand.
            Text(rule.name)
            Text(rule.action.kind.title)
        }
        .swipeActions(edge: .leading) {
            Button {
                editorTarget = NetworkRuleEditorTarget(rule: rule)
            } label: {
                Label(localized("Edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    /// The placeholder shown while no rules are configured.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Rules"),
                systemImage: "arrow.triangle.branch",
                description: Text(
                    localized("Mock, redirect, rewrite or slow down matching requests. Add a rule to get started.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Rules"))
                    .font(.headline)
                Text(localized("Mock, redirect, rewrite or slow down matching requests. Add a rule to get started."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}

/// Identifies the rule an editor sheet is open on.
///
/// `sheet(item:)` needs an `Identifiable` value, and a `nil` rule — the "create a new one" case —
/// has no identity of its own. Wrapping the optional gives both cases one.
struct NetworkRuleEditorTarget: Identifiable {
    /// A fresh identity per presentation.
    let id = UUID()

    /// The rule being edited, or `nil` when the sheet is creating one.
    let rule: NetworkRule?
}
