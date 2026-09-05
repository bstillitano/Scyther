//
//  NetworkRulesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// The list of request overrides, reached from **Networking → Request Overrides**.
///
/// Each row is a `NavigationLink` that pushes the editor, matching the way every other row in the
/// Scyther menu behaves. The row's subtitle names both the behaviour the override performs and
/// whether it is currently on, so a disabled override reads as disabled without any row being
/// recoloured by hand.
///
/// ## Features
/// - A master switch that suspends every override without deleting any of them
/// - Tap to edit; swipe to enable, disable, or delete behind a confirmation alert
/// - A read-only section for overrides the host app registered in code, which the engine applies
///   just as it does the saved ones
/// - Drag-to-reorder, because the first matching mock or map-local override wins
/// - HAR import through the system file importer, reporting how many overrides were added
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     NetworkRulesView()
/// }
/// ```
struct NetworkRulesView: View {
    /// The list's view model, mirroring ``NetworkRuleStore``.
    @StateObject private var viewModel: NetworkRulesViewModel

    /// The store this screen and every editor it opens read and write.
    private let store: NetworkRuleStore

    /// Creates the list.
    ///
    /// - Parameter store: The store to show. Defaults to the shared store; a preview or a test
    ///   harness passes a throwaway one.
    init(store: NetworkRuleStore = .shared) {
        self.store = store
        _viewModel = StateObject(wrappedValue: NetworkRulesViewModel(store: store))
    }

    /// Whether the sheet that creates a new override is presented.
    ///
    /// Creation is a sheet rather than a push because it is reached from a toolbar `Menu`, and a
    /// menu item cannot drive a navigation destination.
    @State private var isCreatingOverride: Bool = false

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
                Toggle(localized("Enable Request Overrides"), isOn: $viewModel.isEnabled)
            } footer: {
                Text(localized("Overrides are applied in order. The first matching mock or map local wins."))
            }

            if viewModel.isEmpty {
                Section {
                    emptyState
                }
            }

            if !viewModel.rules.isEmpty {
                Section {
                    ForEach(viewModel.rules) { rule in
                        ruleRow(for: rule)
                    }
                    .onDelete { viewModel.requestDeletion(at: $0) }
                    .onMove { viewModel.move(from: $0, to: $1) }
                }
            }

            if !viewModel.transientRules.isEmpty {
                Section {
                    ForEach(viewModel.transientRules) { rule in
                        LabeledContent(rule.name, value: viewModel.subtitle(for: rule))
                    }
                } header: {
                    Text(localized("Registered in Code"))
                } footer: {
                    Text(localized("Registered by the app for this launch only. These overrides cannot be edited or reordered and do not persist."))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.rules.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .sheet(isPresented: $isCreatingOverride) {
            NavigationStack {
                NetworkRuleEditorView(rule: nil, store: store)
            }
        }
        .fileImporter(
            isPresented: $isImportingHAR,
            allowedContentTypes: harContentTypes
        ) { result in
            switch result {
            case .success(let url): Task { await viewModel.importHAR(from: url) }
            case .failure: viewModel.reportImportFailure()
            }
        }
        .alert(
            viewModel.deletionTitle,
            isPresented: Binding(
                get: { !viewModel.pendingDeletions.isEmpty },
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
        .navigationTitle(localized("Request Overrides"))
    }

    /// The toolbar menu offering the two ways to add overrides.
    private var addMenu: some View {
        Menu {
            Button {
                isCreatingOverride = true
            } label: {
                Label(localized("New Override"), systemImage: "plus")
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

    /// One override's row: a link into the editor, labelled with the override's name and a
    /// subtitle naming its behaviour and whether it is on.
    private func ruleRow(for rule: NetworkRule) -> some View {
        NavigationLink {
            NetworkRuleEditorView(rule: rule, store: store, showsCancel: false)
        } label: {
            // Matches `MenuView.searchResultLabel(title:icon:tint:breadcrumbText:)`, which is how
            // every other title-over-subtitle row in the menu is built. A bare two-`Text` label is
            // documented for `Toggle` and `LabeledContent` but not for `NavigationLink`, so the
            // stack is explicit rather than left to an unspecified layout.
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                Text(viewModel.subtitle(for: rule))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            // Spelled out rather than left to `onDelete`, because declaring any trailing swipe
            // action replaces the default one `onDelete` would have drawn. `onDelete` stays on
            // the `ForEach` so the `EditButton`'s delete circles still work.
            Button(role: .destructive) {
                viewModel.requestDeletion(of: rule)
            } label: {
                Label(localized("Delete"), systemImage: "trash")
            }
            Button {
                viewModel.setEnabled(rule, to: !rule.isEnabled)
            } label: {
                Label(
                    rule.isEnabled ? localized("Disable") : localized("Enable"),
                    systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                )
            }
        }
    }

    /// The placeholder shown while no overrides are configured.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Overrides"),
                systemImage: "arrow.triangle.branch",
                description: Text(
                    localized("Mock, redirect, rewrite or slow down matching requests. Add an override to get started.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Overrides"))
                    .font(.headline)
                Text(localized("Mock, redirect, rewrite or slow down matching requests. Add an override to get started."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}
