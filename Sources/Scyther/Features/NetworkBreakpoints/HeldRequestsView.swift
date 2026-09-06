//
//  HeldRequestsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The screen that appears over the app when a breakpoint holds something.
///
/// It supplies its own `NavigationStack`, because it is presented over whatever the app happens to
/// be showing rather than pushed inside Scyther's menu. One held exchange opens its editor
/// immediately; several are listed, so a burst of matching requests can be worked through in any
/// order.
///
/// While anything is held there is no way to dismiss it by hand. Every held exchange has to be
/// continued, aborted, or left to its timeout, and a sheet that could be swiped away while an app
/// sat paused behind it would be a way to lose the request without deciding anything.
///
/// Once nothing is held the opposite is true. The presenter takes the screen away on its own, but
/// if it ever fails to — its controller and UIKit having disagreed about what is on screen — a
/// modal listing nothing, over an app that is waiting for nothing, is a dead end. So an empty list
/// says so and offers a way out.
struct HeldRequestsView: View {
    /// The presenter holding the live list of paused exchanges.
    @ObservedObject var presenter: BreakpointPresenter

    /// Closes the presentation this view was put up in, whatever the presenter believes about it.
    @Environment(\.dismiss) private var dismiss

    /// The screen's view model, owning the navigation path.
    @StateObject private var viewModel = HeldRequestsViewModel()

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            List {
                Section {
                    ForEach(presenter.pending) { pause in
                        NavigationLink(value: pause.id) {
                            row(for: pause)
                        }
                    }
                } footer: {
                    // The footer describes the rows above it. With nothing held there are no rows,
                    // and an app that is waiting on nothing should not be told it is waiting.
                    if !presenter.pending.isEmpty {
                        Text(localized("The app is waiting on these. Each one continues unchanged when its timeout runs out."))
                    }
                }
            }
            .overlay {
                if presenter.pending.isEmpty {
                    emptyState
                }
            }
            .navigationTitle(localized("Held Requests"))
            .toolbar {
                // Only ever offered with nothing held: closing while an exchange waits would lose
                // it without a decision, which is the thing this screen exists to prevent. A close
                // rather than a confirm, because there is nothing left here to agree to — the
                // decisions have all been made, and this only puts the screen away.
                if presenter.pending.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            presenter.dismiss()
                            // And again from the view's own side. This button exists for the case
                            // where the presenter's idea of what is on screen has come apart from
                            // UIKit's, so it cannot be the only way out.
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let pause = presenter.pending.first(where: { $0.id == id }) {
                    HeldRequestEditorView(pending: pause, coordinator: presenter.coordinator)
                }
            }
        }
        .onAppear { viewModel.pendingChanged(presenter.pending) }
        /// Keyed on the identities rather than the count. One exchange resolving while another is
        /// held — a burst of matching traffic, or a decision that races a new request — leaves the
        /// count exactly as it was, so the path is never brought back into line: the editor stays
        /// pushed for a pause that has gone, `navigationDestination` finds nothing to build, and
        /// the developer is left on a blank screen with the app still paused behind it.
        .onChange(of: presenter.pending.map(\.id)) { _ in
            viewModel.pendingChanged(presenter.pending)
        }
    }

    /// Shown when nothing is held, which should only ever be the moment before the presenter takes
    /// the screen away.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("Nothing Held"),
                systemImage: "pause.circle",
                description: Text(localized("Every held request has been decided. The app is no longer waiting."))
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("Nothing Held"))
                    .font(.headline)
                Text(localized("Every held request has been decided. The app is no longer waiting."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    /// One held exchange's row: the breakpoint's name over what it is holding.
    private func row(for pause: PendingBreakpoint) -> some View {
        // The same stock title-over-subtitle row the overrides and breakpoints lists use.
        // Title over subtitle, the shape `MenuView.searchResultLabel` uses for every
        // two-line row in the menu. A bare two-`Text` label inside `LabeledContent`
        // renders both lines at almost the same weight, which reads as two titles.
        VStack(alignment: .leading, spacing: 2) {
            Text(pause.breakpointName)
            Text(pause.draft.url ?? pause.stage.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
