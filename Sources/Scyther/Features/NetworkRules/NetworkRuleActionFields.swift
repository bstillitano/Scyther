//
//  NetworkRuleActionFields.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// The Action-specific sections of ``NetworkRuleEditorView``.
///
/// Split out of the editor so that each behaviour's fields can be read in one place rather than
/// buried inside a four-way `switch` in the middle of the form. Every field binds straight to
/// ``NetworkRuleEditorViewModel``, which folds it back into the draft rule's action.
struct NetworkRuleActionFields: View {
    /// The editor's view model.
    @ObservedObject var viewModel: NetworkRuleEditorViewModel

    var body: some View {
        switch viewModel.actionKind {
        case .mock: mockFields
        case .mapLocal: mapLocalFields
        case .rewriteHeaders: rewriteFields
        case .condition: conditionFields
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
            NavigationLink {
                TextEntryView(text: $viewModel.bodyText, title: localized("Body"))
            } label: {
                LabeledContent(localized("Body"), value: viewModel.bodySummary)
            }
        }

        Section(localized("Response Headers")) {
            NetworkRuleHeaderFields(fields: $viewModel.responseHeaders, showsValue: true)
        }
    }

    /// File path, status code, content type and delay for a map-local response.
    @ViewBuilder
    private var mapLocalFields: some View {
        Section(localized("Map Local File")) {
            TextField(localized("File path"), text: $viewModel.filePath)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            LabeledContent(localized("Response Code")) {
                TextField(localized("Response Code"), value: $viewModel.statusCode, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            TextField(localized("Content type"), text: $viewModel.contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            LabeledContent(localized("Delay (seconds)")) {
                TextField(localized("Delay (seconds)"), value: $viewModel.delay, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
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
        } header: {
            Text(localized("Network Condition"))
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
