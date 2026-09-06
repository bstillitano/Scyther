//
//  ReplayEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI

/// The editor that resends a captured request, with whatever has been changed about it.
///
/// Presented as a sheet from the request details page. It does not wrap itself in a
/// `NavigationStack` — the sheet that presents it supplies one — so the body row can push the
/// existing text editor.
///
/// Sending is not special-cased anywhere: the request goes out on an ordinary session and comes
/// back through the interceptor like traffic the app made, which means an enabled override
/// matches it too. The overview footer says so, because a developer comparing a replay against
/// an original needs to know whether they are looking at the network or at their own mock.
struct ReplayEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// The view model owning the draft and every field binding.
    @StateObject private var viewModel: ReplayEditorViewModel

    /// Creates the editor.
    ///
    /// The view model is built inside `StateObject`'s autoclosure rather than by the caller, so
    /// the construction — which reads the captured body off disk — happens once, when SwiftUI
    /// first needs the object, and not on every evaluation of the sheet that presents it.
    ///
    /// - Parameter capture: The captured request to start from.
    init(capture: HTTPRequest) {
        _viewModel = StateObject(wrappedValue: ReplayEditorViewModel(capturing: capture))
    }

    var body: some View {
        List {
            requestSection
            headersSection
            bodySection
        }
        .navigationTitle(localized("Replay Request"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton {
                    // A method that can change server state asks first; everything else goes
                    // straight out, because a confirmation on a GET is a tap that teaches the
                    // developer to dismiss confirmations without reading them.
                    if viewModel.requiresConfirmation {
                        viewModel.showingConfirmation = true
                    } else {
                        viewModel.send()
                        dismiss()
                    }
                }
                .disabled(!viewModel.canSend)
            }
        }
        .alert(localized("Send this request again?"), isPresented: $viewModel.showingConfirmation) {
            Button(localized("Cancel"), role: .cancel) { }
            Button(localized("Send"), role: .destructive) {
                viewModel.send()
                dismiss()
            }
        } message: {
            Text(viewModel.confirmationMessage)
        }
    }

    /// The method and URL, and the two things a developer has to know before sending.
    private var requestSection: some View {
        Section {
            Picker(localized("Method"), selection: $viewModel.methodSelection) {
                ForEach(ReplayEditorViewModel.commonMethods, id: \.self) { method in
                    Text(method).tag(method)
                }
                Text(localized("Other")).tag(ReplayEditorViewModel.otherMethodTag)
            }

            if viewModel.methodSelection == ReplayEditorViewModel.otherMethodTag {
                TextField(localized("Custom method"), text: $viewModel.customMethod)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }

            TextField(localized("URL"), text: $viewModel.draft.url)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        } header: {
            Text(localized("Overview"))
        } footer: {
            requestFooter
        }
    }

    /// The warnings and the note about overrides, stacked under the overview section.
    ///
    /// A `Section` takes one footer, so the lines that apply are gathered into a single stack
    /// rather than fighting over it. The warnings are the same list the confirmation alert
    /// shows, so the editor and the alert can never tell the developer different things.
    @ViewBuilder
    private var requestFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.hasValidURL {
                Text(localized("This URL cannot be sent."))
            }
            ForEach(viewModel.warnings, id: \.self) { warning in
                Text(warning)
            }
            Text(localized("Replays are sent like app traffic, so any enabled override applies to them too."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The editable header rows.
    ///
    /// Headers the system owns are shown but disabled, because seeing that `Content-Length` was
    /// sent and being unable to change it is more informative than not seeing it at all.
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
                .disabled(ReplayableRequest.isManaged(header.name))
            }
            .onDelete { viewModel.removeHeaders(at: $0) }

            Button {
                viewModel.addHeader()
            } label: {
                Label(localized("Add header"), systemImage: "plus")
            }
        } header: {
            Text(localized("Request Headers"))
        } footer: {
            Text(localized("Content-Length, Host and Connection are set by the system and cannot be edited."))
        }
    }

    /// The body row, opening the existing text editor.
    ///
    /// A capture whose body the log could not keep says so on the row rather than showing an
    /// editable `0 bytes`, and the section's footer explains what will be sent instead. The
    /// developer can still type a body of their own, which is why the row stays a link.
    private var bodySection: some View {
        Section {
            NavigationLink {
                TextEntryView(text: bodyText, title: localized("Request Body"))
            } label: {
                LabeledContent(localized("Body"), value: bodySummary)
            }
        } header: {
            Text(localized("Request Body"))
        } footer: {
            if viewModel.draft.hasUncapturedBody {
                Text(localized("The original body was not text, so the log did not keep it. This replay is sent without a body."))
            }
        }
    }

    /// What the body row's trailing value says.
    private var bodySummary: String {
        viewModel.draft.hasUncapturedBody
            ? localized("Binary body, not replayed")
            : localized("\(viewModel.draft.bodyByteCount) bytes")
    }

    /// The body as editable text.
    private var bodyText: Binding<String> {
        Binding(
            get: { viewModel.draft.bodyText },
            set: { viewModel.draft.setBodyText($0) }
        )
    }
}
