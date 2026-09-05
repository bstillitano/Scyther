//
//  HeldRequestEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The editor for one held request or response.
///
/// Pushed from ``HeldRequestsView``, which supplies the navigation stack. Everything on it is a
/// stock form row: the exchange is the interesting part, and a bespoke layout in front of a
/// paused app would only be something else to read.
///
/// There are three ways out, and they are deliberately different shapes. The confirm button
/// continues with whatever has been edited; **Continue without changes** passes the exchange on
/// exactly as it arrived; **Abort** fails it with an error the app has to handle. Doing nothing is
/// a fourth: the countdown continues the exchange unchanged when it runs out.
struct HeldRequestEditorView: View {
    /// The editor's view model, owning the editable copy and the decision.
    @StateObject private var viewModel: HeldRequestEditorViewModel

    /// Creates the editor.
    ///
    /// - Parameters:
    ///   - pending: The pause being decided.
    ///   - coordinator: Where the decision is delivered. Defaults to the shared coordinator.
    init(pending: PendingBreakpoint, coordinator: BreakpointCoordinator = .shared) {
        _viewModel = StateObject(wrappedValue: HeldRequestEditorViewModel(pending: pending,
                                                                         coordinator: coordinator))
    }

    var body: some View {
        List {
            overviewSection
            headersSection
            bodySection
            actionsSection
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton { viewModel.continueWithEdits() }
                    .disabled(!viewModel.hasValidURL)
            }
        }
        .alert(localized("Which error should the app see?"), isPresented: $viewModel.showingAbortOptions) {
            ForEach(HeldRequestEditorViewModel.abortCodes, id: \.rawValue) { code in
                Button(code.abortTitle, role: .destructive) { viewModel.abort(with: code) }
            }
            Button(localized("Cancel"), role: .cancel) { }
        } message: {
            Text(localized("The request fails with this error, exactly as though the network had produced it."))
        }
    }

    /// Which breakpoint holds this exchange, how long is left, and the fields that identify it.
    private var overviewSection: some View {
        Section {
            LabeledContent(localized("Breakpoint"), value: viewModel.pending.breakpointName)

            // Re-rendered once a second, so the countdown is a function of the date the timeline
            // hands it rather than of a timer this view has to own and invalidate.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                LabeledContent(localized("Timeout"), value: viewModel.remainingText(at: context.date))
            }

            if viewModel.isRequest {
                TextField(localized("Method"), text: $viewModel.method)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField(localized("URL"), text: $viewModel.url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } else {
                LabeledContent(localized("Response Code")) {
                    TextField(localized("Response Code"), value: $viewModel.statusCode, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
            }
        } header: {
            Text(localized("Overview"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !viewModel.hasValidURL {
                    Text(localized("This URL cannot be sent."))
                }
                Text(localized("The app is waiting on this. It continues unchanged when the timeout runs out."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The editable header rows.
    private var headersSection: some View {
        Section {
            ForEach($viewModel.draft.headers) { $header in
                LabeledContent {
                    TextField(localized("Value"), text: $header.value)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    TextField(localized("Header name"), text: $header.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .onDelete { viewModel.removeHeaders(at: $0) }

            Button {
                viewModel.addHeader()
            } label: {
                Label(localized("Add header"), systemImage: "plus")
            }
        } header: {
            Text(viewModel.isRequest ? localized("Request Headers") : localized("Response Headers"))
        }
    }

    /// The body row, opening the existing text editor.
    private var bodySection: some View {
        Section {
            if viewModel.draft.isBodyEditable {
                NavigationLink {
                    TextEntryView(text: $viewModel.bodyText,
                                  title: viewModel.isRequest ? localized("Request Body") : localized("Response Body"))
                } label: {
                    LabeledContent(localized("Body"), value: viewModel.bodySummary)
                }
            } else {
                LabeledContent(localized("Body"), value: localized("Binary body, sent unchanged"))
            }
        } header: {
            Text(viewModel.isRequest ? localized("Request Body") : localized("Response Body"))
        }
    }

    /// The two decisions the toolbar's confirm button does not cover.
    private var actionsSection: some View {
        Section {
            Button(localized("Continue Without Changes")) { viewModel.continueUnchanged() }
            Button(localized("Abort"), role: .destructive) { viewModel.showingAbortOptions = true }
        } footer: {
            Text(localized("Continuing applies your edits. The log records the exchange as the app actually saw it."))
        }
    }
}
