//
//  LogDetailsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct LogDetailsView: View {
    let httpRequest: HTTPRequest

    @StateObject private var viewModel: LogDetailsViewModel

    /// The override **Save as mock** built from this capture, while its editor is presented.
    ///
    /// Held as the sheet's item rather than behind a `Bool` so the override is built exactly
    /// once, when the button is tapped. Building it inside the sheet's content closure would
    /// write a fresh copy of the response body to disk on every evaluation.
    @State private var mockDraft: NetworkRule?

    init(httpRequest: HTTPRequest) {
        self.httpRequest = httpRequest
        _viewModel = StateObject(wrappedValue: LogDetailsViewModel(httpRequest: httpRequest))
    }

    var body: some View {
        List {
            mockedSection
            overviewSection
            graphQLSection
            requestHeadersSection
            requestBodySection
            responseHeadersSection
            responseBodySection
            developerSection
        }
        .navigationTitle(localized("Request Details"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                exportButton
            }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .sheet(item: $mockDraft) { rule in
            NavigationStack {
                NetworkRuleEditorView(prefilled: rule, store: viewModel.ruleStore)
            }
        }
    }

    /// Shares the request as a cURL command from the navigation bar.
    ///
    /// Presents the same system share sheet as the "Export cURL request" row in the
    /// developer section, using ``LogDetailsViewModel/curlRequest`` as the shared item.
    private var exportButton: some View {
        ShareLink(item: viewModel.curlRequest) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(localized("Export cURL request"))
    }

    private var overviewSection: some View {
        Section(localized("Overview")) {
            NavigationLink {
                TextReaderView(text: viewModel.requestURL, title: localized("Request URL"))
            } label: {
                LabeledContent(localized("URL"), value: viewModel.requestURL)
            }

            LabeledContent(localized("Method"), value: viewModel.method)
            LabeledContent(localized("Response Code"), value: viewModel.responseCode)
            LabeledContent(localized("Response Size"), value: viewModel.responseSize)
            LabeledContent(localized("Date"), value: viewModel.date)
            LabeledContent(localized("Duration"), value: viewModel.duration)
        }
    }

    @ViewBuilder
    private var graphQLSection: some View {
        if viewModel.hasGraphQL {
            Section("GraphQL") { // scyther:unlocalised technical token
                LabeledContent(localized("Operation"), value: viewModel.graphQLOperationName)
                LabeledContent(localized("Type"), value: viewModel.graphQLOperationType)

                if !viewModel.graphQLVariablesDictionary.isEmpty {
                    NavigationLink(localized("Browse variables")) {
                        DataBrowserView(data: viewModel.graphQLVariablesDictionary, title: localized("Variables"))
                    }
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private var requestHeadersSection: some View {
        Section(localized("Request Headers")) {
            if viewModel.requestHeaders.isEmpty {
                Text(localized("No headers sent"))
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.requestHeaders) { header in
                    LabeledContent(header.key, value: header.value)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(header.key): \(header.value)"
                            } label: {
                                Label(localized("Copy"), systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    private var requestBodySection: some View {
        Section(localized("Request Body")) {
            if viewModel.hasRequestBody {
                NavigationLink(localized("Browse request body")) {
                    DataBrowserView(data: viewModel.requestBodyDictionary, title: localized("Request Body"))
                }
                .foregroundStyle(.tint)

                NavigationLink(localized("View request body")) {
                    TextReaderView(text: viewModel.requestBody, title: localized("Request Body"))
                }
                .foregroundStyle(.tint)
            } else {
                Text(localized("No content sent"))
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var responseHeadersSection: some View {
        Section(localized("Response Headers")) {
            if viewModel.responseHeaders.isEmpty {
                Text(localized("No headers received"))
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.responseHeaders) { header in
                    LabeledContent(header.key, value: header.value)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(header.key): \(header.value)"
                            } label: {
                                Label(localized("Copy"), systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    private var responseBodySection: some View {
        Section(localized("Response Body")) {
            if viewModel.hasResponseBody {
                NavigationLink(localized("Browse response body")) {
                    DataBrowserView(data: viewModel.responseBodyDictionary, title: localized("Response Body"))
                }
                .foregroundStyle(.tint)

                NavigationLink(localized("View response body")) {
                    TextReaderView(text: viewModel.responseBody, title: localized("Response Body"))
                }
                .foregroundStyle(.tint)
            } else {
                Text(localized("No data received"))
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// The pink banner shown above everything else when this response was synthesised.
    ///
    /// A mocked response is the one thing in the log that is not what the app actually received,
    /// so it is called out before any of the captured values rather than left to a row far down
    /// the page. Each override that shaped the request is a link into its editor.
    @ViewBuilder
    private var mockedSection: some View {
        if viewModel.wasStubbed || !viewModel.appliedRuleNames.isEmpty {
            Section {
                if viewModel.wasStubbed {
                    Label {
                        Text(localized("This response was synthesised by an override, not received from the network."))
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .foregroundStyle(.pink)
                }
                overrideRows
            } header: {
                if viewModel.wasStubbed {
                    Text(localized("MOCKED"))
                        .foregroundStyle(.pink)
                } else {
                    Text(localized("Overrides"))
                }
            }
        }
    }

    /// One row per override that shaped this request.
    ///
    /// Overrides the store still holds push their editor; ones that have since been deleted are
    /// named but inert, because there is nothing left to open.
    @ViewBuilder
    private var overrideRows: some View {
        if viewModel.appliedOverrides.isEmpty {
            ForEach(viewModel.appliedRuleNames, id: \.self) { name in
                LabeledContent(localized("Override"), value: name)
            }
        } else {
            ForEach(viewModel.appliedOverrides) { rule in
                NavigationLink {
                    NetworkRuleEditorView(rule: rule, store: viewModel.ruleStore, showsCancel: false)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name)
                        Text(rule.action.kind.title)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var developerSection: some View {
        Section(localized("Developer Info")) {
            LabeledContent(localized("Request time"), value: viewModel.requestTime)
            LabeledContent(localized("Response time"), value: viewModel.responseTime)
            LabeledContent(localized("Cache Policy"), value: viewModel.cachePolicy)
            LabeledContent(localized("Timeout"), value: viewModel.timeout)

            ShareLink(item: viewModel.curlRequest) {
                Text(localized("Export cURL request"))
            }

            if viewModel.canSaveAsMock {
                Button(localized("Save as mock")) {
                    mockDraft = viewModel.makeMockRule()
                }
            }
        }
    }
}

/// Represents an HTTP header key-value pair for display.
struct HeaderItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

#Preview {
    NavigationStack {
        Text("LogDetailsView requires an HTTPRequest") // scyther:unlocalised Xcode preview placeholder
    }
}
