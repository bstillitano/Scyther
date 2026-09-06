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
/// There is no way to dismiss it by hand. Every held exchange has to be continued, aborted, or
/// left to its timeout, and a sheet that could be swiped away while an app sat paused behind it
/// would be a way to lose the request without deciding anything.
struct HeldRequestsView: View {
    /// The presenter holding the live list of paused exchanges.
    @ObservedObject var presenter: BreakpointPresenter

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
                    Text(localized("The app is waiting on these. Each one continues unchanged when its timeout runs out."))
                }
            }
            .navigationTitle(localized("Held Requests"))
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
