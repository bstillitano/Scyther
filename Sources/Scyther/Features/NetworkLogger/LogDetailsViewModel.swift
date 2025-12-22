//
//  LogDetailsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the presentation of HTTP request details.
///
/// `LogDetailsViewModel` processes raw `HTTPRequest` data into formatted, human-readable
/// information suitable for display in the network logger's detail view. It handles header
/// parsing, body content extraction, metadata formatting, and cURL command generation.
///
/// ## Features
///
/// - **Request Overview**: Formats URL, method, response code, size, date, and duration
/// - **Header Processing**: Parses and sorts request/response headers alphabetically
/// - **Body Handling**: Extracts and formats request/response bodies as text and structured data
/// - **Developer Tools**: Provides request/response timestamps, cache policy, timeout info, and cURL export
/// - **Lazy Loading**: Processes data on first appearance for optimal performance
///
/// ## Usage
///
/// ```swift
/// let request = HTTPRequest(/* ... */)
/// let viewModel = LogDetailsViewModel(httpRequest: request)
/// await viewModel.onFirstAppear()
/// // Access formatted properties like viewModel.requestURL, viewModel.method, etc.
/// ```
///
/// ## Topics
///
/// ### Creating a View Model
/// - ``init(httpRequest:)``
///
/// ### Request Overview
/// - ``requestURL``
/// - ``method``
/// - ``responseCode``
/// - ``responseSize``
/// - ``date``
/// - ``duration``
///
/// ### Headers
/// - ``requestHeaders``
/// - ``responseHeaders``
///
/// ### Request Body
/// - ``hasRequestBody``
/// - ``requestBody``
///
/// ### Response Body
/// - ``hasResponseBody``
/// - ``responseBody``
/// - ``responseBodyDictionary``
///
/// ### Developer Information
/// - ``requestTime``
/// - ``responseTime``
/// - ``cachePolicy``
/// - ``timeout``
/// - ``curlRequest``
///
/// ### Lifecycle
/// - ``onFirstAppear()``
class LogDetailsViewModel: ViewModel {
    /// The HTTP request being displayed.
    private let httpRequest: HTTPRequest

    /// The formatted request URL.
    @Published var requestURL: String = ""

    /// The HTTP method (GET, POST, etc.).
    @Published var method: String = ""

    /// The HTTP response status code.
    @Published var responseCode: String = ""

    /// The formatted response size in bytes.
    @Published var responseSize: String = ""

    /// The formatted request date/time.
    @Published var date: String = ""

    /// The formatted request duration in milliseconds.
    @Published var duration: String = ""

    /// The sorted list of request headers.
    @Published var requestHeaders: [HeaderItem] = []

    /// The sorted list of response headers.
    @Published var responseHeaders: [HeaderItem] = []

    /// Whether the request includes a body.
    @Published var hasRequestBody: Bool = false

    /// Whether the response includes a body.
    @Published var hasResponseBody: Bool = false

    /// The request body as a formatted string.
    @Published var requestBody: String = ""

    /// The response body as a formatted string.
    @Published var responseBody: String = ""

    /// The response body parsed as a browsable dictionary structure.
    @Published var responseBodyDictionary: [String: [String: Any]] = [:]

    /// The formatted request timestamp.
    @Published var requestTime: String = ""

    /// The formatted response timestamp.
    @Published var responseTime: String = ""

    /// The cache policy used for the request.
    @Published var cachePolicy: String = ""

    /// The request timeout value.
    @Published var timeout: String = ""

    /// The cURL command equivalent of this request.
    @Published var curlRequest: String = ""

    /// Creates a new log details view model.
    ///
    /// - Parameter httpRequest: The HTTP request to display details for
    init(httpRequest: HTTPRequest) {
        self.httpRequest = httpRequest
        super.init()
    }

    /// Prepares the view model when the view first appears.
    ///
    /// This method triggers processing of the HTTP request data into all formatted properties.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDetails()
    }

    /// Processes the HTTP request into formatted display properties.
    ///
    /// This method extracts all relevant information from the `HTTPRequest` object and
    /// formats it appropriately for display, including:
    /// - Request metadata (URL, method, response code, etc.)
    /// - Headers (sorted alphabetically)
    /// - Request/response bodies
    /// - Developer information (timestamps, cache policy, timeout)
    /// - cURL export command
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
