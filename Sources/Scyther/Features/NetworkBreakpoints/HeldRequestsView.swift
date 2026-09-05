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
        .onChange(of: presenter.pending.count) { _ in
            viewModel.pendingChanged(presenter.pending)
        }
    }

    /// One held exchange's row: the breakpoint's name over what it is holding.
    private func row(for pause: PendingBreakpoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pause.breakpointName)
            Text(pause.draft.url ?? pause.stage.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
