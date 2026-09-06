//
//  NetworkRuleActionFields.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// The action sections of ``NetworkRuleEditorView``: what answers the request, what is rewritten
/// on it, and how it is conditioned.
///
/// Split out of the editor so that the three actions can be read in one place rather than buried
/// in the middle of the form. Each has its own switch and its own fields, because an override
/// composes as many of them as it likes — a mocked endpoint can be slow, and a conditioned one can
/// carry a rewrite. Every field binds straight to ``NetworkRuleEditorViewModel``, which folds it
/// back into the draft rule.
struct NetworkRuleActionFields: View {
    /// The editor's view model.
    @ObservedObject var viewModel: NetworkRuleEditorViewModel

    /// Whether the system file importer is presented for a map-local file.
    @State private var isImportingFile: Bool = false

    var body: some View {
        stubSection
        if viewModel.stubKind == .mock { mockFields }
        if viewModel.stubKind == .mapLocal { mapLocalFields }
        rewriteSection
        if viewModel.isRewritingHeaders { rewriteFields }
        conditionSection
        if viewModel.isConditioning { conditionFields }
    }

    // MARK: - Stub

    /// The picker choosing what answers the request in place of the network.
    private var stubSection: some View {
        Section {
            Picker(localized("Stub"), selection: $viewModel.stubKind) {
                ForEach(NetworkRuleStubKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        } footer: {
            Text(localized("A stubbed request is answered without leaving the device."))
        }
    }

    /// Status code, delay, body and response headers for a mock response.
    @ViewBuilder
    private var mockFields: some View {
        Section(localized("Mock Response")) {
            LabeledContent(localized("Response Code")) {
                TextField(localized("Response Code"), value: $viewModel.statusCode, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            LabeledContent(localized("Delay (seconds)")) {
                TextField(localized("Delay (seconds)"), value: $viewModel.delay, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
            bodyRow
        }

        Section(localized("Response Headers")) {
            NetworkRuleHeaderFields(fields: $viewModel.responseHeaders, showsValue: true)
        }
    }

    /// The body row: a link into the text editor, or a plain row saying why there is no link.
    ///
    /// A body that is not UTF-8 — a captured image saved as a mock, most often — is shown as a
    /// size and left alone. Opening it as text and touching the field wrote every byte back as a
    /// replacement character, which destroyed the response the override existed to serve.
    @ViewBuilder
    private var bodyRow: some View {
        switch viewModel.bodyEditability {
        case .editable:
            NavigationLink {
                TextEntryView(text: $viewModel.bodyText, title: localized("Body"))
            } label: {
                LabeledContent(localized("Body"), value: viewModel.bodySummary)
            }
        case .notText:
            LabeledContent(localized("Body"), value: viewModel.bodySummary)
            Text(localized("This body is not text, so it is served as captured and cannot be edited here."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .tooLarge:
            LabeledContent(localized("Body"), value: viewModel.bodySummary)
            Text(localized("This body is too large to edit here. It is served as captured."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The picked file, status code, content type and delay for a map-local response.
    ///
    /// The file is chosen with the system file importer and copied into the rules directory, so
    /// there is nothing to type: a container path is not something anyone can enter on a device,
    /// and a path to a document outside the app cannot be read again after a relaunch.
    ///
    /// The content type is picked rather than typed, because MIME types are a registered set and
    /// one spelled wrong fails silently at request time. Picking the file fills it in.
    @ViewBuilder
    private var mapLocalFields: some View {
        Section(localized("Map Local File")) {
            // One row chooses the file and reports which one is chosen. Two rows saying the same
            // thing — a `File` row and a `Choose File` button beneath it — read as two facts.
            Button {
                isImportingFile = true
            } label: {
                LabeledContent(localized("File"), value: viewModel.mapLocalSummary)
            }
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url): viewModel.importMapLocalFile(from: url)
                case .failure: viewModel.reportFileImportFailure()
                }
            }
            .alert(localized("Import Failed"), isPresented: $viewModel.didFailToImportFile) {
                Button(localized("OK"), role: .cancel) { viewModel.didFailToImportFile = false }
            } message: {
                Text(localized("The selected file could not be copied."))
            }
            LabeledContent(localized("Response Code")) {
                TextField(localized("Response Code"), value: $viewModel.statusCode, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            Picker(localized("Content type"), selection: $viewModel.contentTypeSelection) {
                Text(localized("None")).tag(NetworkRuleEditorViewModel.ContentTypeChoice.unset)
                ForEach(NetworkRuleEditorViewModel.contentTypes, id: \.self) { type in
                    // A registered MIME token, shown as it goes out on the wire.
                    Text(type).tag(NetworkRuleEditorViewModel.ContentTypeChoice.listed(type))
                }
                Text(localized("Custom")).tag(NetworkRuleEditorViewModel.ContentTypeChoice.custom)
            }
            if viewModel.isCustomContentType {
                TextField(localized("Content type"), text: $viewModel.contentType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            LabeledContent(localized("Delay (seconds)")) {
                TextField(localized("Delay (seconds)"), value: $viewModel.delay, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
        }
    }

    // MARK: - Rewrite

    /// The switch turning the header rewrite on, and what it means alongside a stub.
    private var rewriteSection: some View {
        Section {
            Toggle(localized("Rewrite Headers"), isOn: $viewModel.isRewritingHeaders)
        } footer: {
            Text(localized("Recorded on the log. Nothing is sent while the request is stubbed."))
        }
    }

    /// The headers a rewrite sets, and the header names it removes.
    @ViewBuilder
    private var rewriteFields: some View {
        Section(localized("Set headers")) {
            NetworkRuleHeaderFields(fields: $viewModel.setHeaders, showsValue: true)
        }
        Section(localized("Remove headers")) {
            NetworkRuleHeaderFields(fields: $viewModel.removedHeaders, showsValue: false)
        }
    }

    // MARK: - Condition

    /// The switch turning conditioning on, and the note that it reaches a stub too.
    private var conditionSection: some View {
        Section {
            Toggle(localized("Network Condition"), isOn: $viewModel.isConditioning)
        } footer: {
            Text(localized("Also applies to a stubbed response."))
        }
    }

    /// Latency, bandwidth ceiling and failure rate for a conditioned request.
    @ViewBuilder
    private var conditionFields: some View {
        Section {
            LabeledContent(localized("Latency (seconds)")) {
                TextField(localized("Latency (seconds)"), value: $viewModel.latency, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
            LabeledContent(localized("Bandwidth (KB/s)")) {
                TextField(localized("Bandwidth (KB/s)"), value: $viewModel.bandwidthKBps, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
        } footer: {
            Text(localized("0 means unthrottled."))
        }

        Section {
            LabeledContent(
                localized("Failure rate"),
                value: viewModel.failureRate.formatted(.percent.precision(.fractionLength(0)))
            )
            Slider(value: $viewModel.failureRate, in: 0...1, step: 0.05)
                .accessibilityLabel(localized("Failure rate"))
        }
    }
}

/// An editable list of header rows, used for a mock's response headers and for both halves of a
/// header rewrite.
///
/// Rows are deleted with a trailing swipe, matching the rest of the toolkit, and added with a
/// trailing button. Unnamed rows are dropped when the editor folds the list back into the rule,
/// so a half-typed row costs nothing.
struct NetworkRuleHeaderFields: View {
    /// The rows being edited.
    @Binding var fields: [NetworkRuleHeaderField]

    /// Whether each row carries a value. `false` for the "remove these headers" list, where the
    /// name is the whole instruction.
    let showsValue: Bool

    var body: some View {
        ForEach($fields) { $field in
            if showsValue {
                LabeledContent {
                    TextField(localized("Value"), text: $field.value)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    TextField(localized("Header name"), text: $field.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } else {
                TextField(localized("Header name"), text: $field.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .onDelete { fields.remove(atOffsets: $0) }

        Button {
            fields.append(NetworkRuleHeaderField())
        } label: {
            Label(localized("Add header"), systemImage: "plus")
        }
    }
}
