//
//  LogDetailsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct LogDetailsView: View {
    let httpRequest: HTTPRequest

    @StateObject private var viewModel: LogDetailsSwiftUIViewModel

    init(httpRequest: HTTPRequest) {
        self.httpRequest = httpRequest
        _viewModel = StateObject(wrappedValue: LogDetailsSwiftUIViewModel(httpRequest: httpRequest))
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

struct HeaderItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class LogDetailsSwiftUIViewModel: ViewModel {
    private let httpRequest: HTTPRequest

    @Published var requestURL: String = ""
    @Published var method: String = ""
    @Published var responseCode: String = ""
    @Published var responseSize: String = ""
    @Published var date: String = ""
    @Published var duration: String = ""
    @Published var requestHeaders: [HeaderItem] = []
    @Published var responseHeaders: [HeaderItem] = []
    @Published var hasRequestBody: Bool = false
    @Published var hasResponseBody: Bool = false
    @Published var requestBody: String = ""
    @Published var responseBody: String = ""
    @Published var responseBodyDictionary: [String: [String: Any]] = [:]
    @Published var requestTime: String = ""
    @Published var responseTime: String = ""
    @Published var cachePolicy: String = ""
    @Published var timeout: String = ""
    @Published var curlRequest: String = ""

    init(httpRequest: HTTPRequest) {
        self.httpRequest = httpRequest
        super.init()
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDetails()
    }

    @MainActor
    private func loadDetails() async {
        requestURL = httpRequest.requestURL ?? ""
        method = httpRequest.requestMethod ?? "-"
        responseCode = "\(httpRequest.responseCode ?? 0)"
        responseSize = "\(httpRequest.responseBodyLength ?? 0) bytes"
        date = httpRequest.requestDate?.formatted() ?? "-"
        duration = String(format: "%.0fms", httpRequest.requestDuration ?? 0)

        requestHeaders = (httpRequest.requestHeaders ?? [:]).compactMap { key, value in
            guard let keyStr = key as? String, let valueStr = value as? String else { return nil }
            return HeaderItem(key: keyStr, value: valueStr)
        }.sorted { $0.key < $1.key }

        responseHeaders = (httpRequest.responseHeaders ?? [:]).compactMap { key, value in
            guard let keyStr = key as? String, let valueStr = value as? String else { return nil }
            return HeaderItem(key: keyStr, value: valueStr)
        }.sorted { $0.key < $1.key }

        requestBody = httpRequest.getRequestBody() as String? ?? ""
        hasRequestBody = !requestBody.isEmpty

        responseBody = httpRequest.getResponseBody() as String? ?? ""
        hasResponseBody = !responseBody.isEmpty
        responseBodyDictionary = httpRequest.getResponseBodyDictionary()

        requestTime = httpRequest.requestTime ?? "-"
        responseTime = httpRequest.responseTime ?? "-"
        cachePolicy = httpRequest.requestCachePolicy ?? "-"
        timeout = httpRequest.requestTimeout ?? "-"
        curlRequest = httpRequest.requestCurl ?? ""
    }
}

#Preview {
    NavigationStack {
        Text("LogDetailsView requires an HTTPRequest")
    }
}
