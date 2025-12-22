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

    init(httpRequest: HTTPRequest) {
        self.httpRequest = httpRequest
        _viewModel = StateObject(wrappedValue: LogDetailsViewModel(httpRequest: httpRequest))
    }

    var body: some View {
        List {
            overviewSection
            requestHeadersSection
            requestBodySection
            responseHeadersSection
            responseBodySection
            developerSection
        }
        .navigationTitle("Request Details")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            NavigationLink {
                TextReaderView(text: viewModel.requestURL, title: "Request URL")
            } label: {
                LabeledContent("URL", value: viewModel.requestURL)
            }

            LabeledContent("Method", value: viewModel.method)
            LabeledContent("Response Code", value: viewModel.responseCode)
            LabeledContent("Response Size", value: viewModel.responseSize)
            LabeledContent("Date", value: viewModel.date)
            LabeledContent("Duration", value: viewModel.duration)
        }
    }

    private var requestHeadersSection: some View {
        Section("Request Headers") {
            if viewModel.requestHeaders.isEmpty {
                Text("No headers sent")
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
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    private var requestBodySection: some View {
        Section("Request Body") {
            if viewModel.hasRequestBody {
                NavigationLink("View request body") {
                    TextReaderView(text: viewModel.requestBody, title: "Request Body")
                }
            } else {
                Text("No content sent")
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var responseHeadersSection: some View {
        Section("Response Headers") {
            if viewModel.responseHeaders.isEmpty {
                Text("No headers received")
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
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    private var responseBodySection: some View {
        Section("Response Body") {
            if viewModel.hasResponseBody {
                NavigationLink("Browse response body") {
                    DataBrowserView(data: viewModel.responseBodyDictionary, title: "Response Body")
                }
                .foregroundStyle(.tint)

                NavigationLink("View response body") {
                    TextReaderView(text: viewModel.responseBody, title: "Response Body")
                }
                .foregroundStyle(.tint)
            } else {
                Text("No data received")
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var developerSection: some View {
        Section("Developer Info") {
            LabeledContent("Request time", value: viewModel.requestTime)
            LabeledContent("Response time", value: viewModel.responseTime)
            LabeledContent("Cache Policy", value: viewModel.cachePolicy)
            LabeledContent("Timeout", value: viewModel.timeout)

            ShareLink(item: viewModel.curlRequest) {
                Text("Export cURL request")
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
        Text("LogDetailsView requires an HTTPRequest")
    }
}
