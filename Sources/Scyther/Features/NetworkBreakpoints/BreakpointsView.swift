//
//  BreakpointsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The list of breakpoints, reached from **Networking → Breakpoints**.
///
/// Each row is a `NavigationLink` that pushes the editor, matching every other row in the Scyther
/// menu. A disabled breakpoint is drawn in the system's secondary hierarchy, so it reads as
/// disabled instead of saying so in small grey text.
///
/// The master switch defaults to off and its footer says what a breakpoint does, because this is
/// the one feature in the toolkit that deliberately holds the app up: a developer switching it on
/// should know that before their next request stops rather than after.
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     BreakpointsView()
/// }
/// ```
struct BreakpointsView: View {
    /// The list's view model, mirroring ``BreakpointStore``.
    @StateObject private var viewModel: BreakpointsViewModel

    /// The store this screen and every editor it opens read and write.
    private let store: BreakpointStore

    /// Whether the sheet that creates a new breakpoint is presented.
    ///
    /// Creation is a sheet rather than a push because it is reached from a toolbar button, which
    /// cannot drive a navigation destination.
    @State private var isCreatingBreakpoint: Bool = false

    /// Creates the list.
    ///
    /// - Parameter store: The store to show. Defaults to the shared store; a preview or a test
    ///   harness passes a throwaway one.
    init(store: BreakpointStore = .shared) {
        self.store = store
        _viewModel = StateObject(wrappedValue: BreakpointsViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Toggle(localized("Enable Breakpoints"), isOn: $viewModel.isEnabled)
            } footer: {
                Text(localized("A matching request or response is held until you continue it. Every hold has a timeout, and nothing is ever held during a test run."))
            }

            if viewModel.isEmpty {
                Section {
                    emptyState
                }
            }

            if !viewModel.breakpoints.isEmpty {
                Section {
                    ForEach(viewModel.breakpoints) { breakpoint in
                        breakpointRow(for: breakpoint)
                    }
                    .onDelete { viewModel.requestDeletion(at: $0) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingBreakpoint = true
                } label: {
                    // An icon-only `Label` rather than a bare `Image`: the title is what VoiceOver
                    // reads, so the button keeps a name without an `accessibilityLabel`.
                    Label(localized("New Breakpoint"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $isCreatingBreakpoint) {
            NavigationStack {
                BreakpointEditorView(breakpoint: nil, store: store)
            }
        }
        .alert(
            localized("Delete this breakpoint?"),
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
        .navigationTitle(localized("Breakpoints"))
    }

    /// One breakpoint's row: a link into the editor, labelled with its name and a subtitle naming
    /// the side it holds and for how long.
    private func breakpointRow(for breakpoint: NetworkBreakpoint) -> some View {
        NavigationLink {
            BreakpointEditorView(breakpoint: breakpoint, store: store, showsCancel: false)
        } label: {
            // Matches the override list's rows, which in turn match
            // `MenuView.searchResultLabel(title:icon:tint:breadcrumbText:)` — the way every
            // title-over-subtitle row in this menu is built.
            // The same stock title-over-subtitle row the overrides list uses: `LabeledContent`
            // supplies the secondary font and colour, and `EmptyView` because the row's accessory
            // is the `NavigationLink`'s own chevron.
            LabeledContent {
                EmptyView()
            } label: {
                Text(breakpoint.name)
                Text(viewModel.subtitle(for: breakpoint))
            }
            .foregroundStyle(breakpoint.isEnabled ? .primary : .secondary)
        }
        .swipeActions(edge: .trailing) {
            // Spelled out rather than left to `onDelete`, because declaring any trailing swipe
            // action replaces the default one `onDelete` would have drawn. `onDelete` stays on the
            // `ForEach` so the `EditButton`'s delete circles still work.
            Button(role: .destructive) {
                viewModel.requestDeletion(of: breakpoint)
            } label: {
                Label(localized("Delete"), systemImage: "trash")
            }
            Button {
                viewModel.setEnabled(breakpoint, to: !breakpoint.isEnabled)
            } label: {
                Label(
                    breakpoint.isEnabled ? localized("Disable") : localized("Enable"),
                    systemImage: breakpoint.isEnabled ? "pause.circle" : "play.circle"
                )
            }
        }
    }

    /// The placeholder shown while no breakpoints are configured.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Breakpoints"),
                systemImage: "pause.circle",
                description: Text(
                    localized("Hold a matching request or response so you can read it, change it, and decide what happens next. Add a breakpoint to get started.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Breakpoints"))
                    .font(.headline)
                Text(localized("Hold a matching request or response so you can read it, change it, and decide what happens next. Add a breakpoint to get started."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}
