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
/// - ``init(httpRequest:store:)``
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
/// ### Request Overrides
/// - ``appliedRuleNames``
/// - ``wasStubbed``
/// - ``canSaveAsMock``
/// - ``ruleStore``
/// - ``makeMockRule()``
///
/// ### Replays
/// - ``canReplay``
/// - ``replayLinks``
/// - ``originalRequest``
/// - ``originalSummary``
///
/// ### Lifecycle
/// - ``onFirstAppear()``
class LogDetailsViewModel: ViewModel {
    /// Response headers that describe how the body travelled rather than what it holds.
    ///
    /// The logger stores the body `URLSession` already decoded and re-framed, so copying these
    /// into a mock would advertise a length and an encoding the mock's bytes do not have. They
    /// are dropped when a capture is saved as a mock; every other header is carried over.
    private static let wireEncodingHeaders: Set<String> = [
        "content-encoding", "content-length", "transfer-encoding"
    ]

    /// The HTTP request being displayed.
    private let httpRequest: HTTPRequest

    /// The token for the log observation, removed when this view model goes away.
    ///
    /// `nonisolated(unsafe)` because `deinit` is not main-actor isolated. It is written exactly
    /// once, in ``setup()``, before anything else can reach this instance, and read exactly once,
    /// in `deinit`, after everything else has let go of it — so there is no interleaving for
    /// isolation to protect.
    private nonisolated(unsafe) var logObserver: (any NSObjectProtocol)?

    /// The override store a mock built from this capture is written to.
    ///
    /// Exposed so the view can hand the same store to the editor it presents; a test passes a
    /// throwaway one so saving a mock never touches the developer's real overrides.
    let ruleStore: NetworkRuleStore

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

    /// Whether the request is a GraphQL operation.
    @Published var hasGraphQL: Bool = false

    /// The GraphQL operation name.
    @Published var graphQLOperationName: String = ""

    /// The GraphQL operation type as a display string (e.g. "Query").
    @Published var graphQLOperationType: String = ""

    /// The GraphQL `variables` object as a browsable dictionary structure.
    @Published var graphQLVariablesDictionary: [String: [String: Any]] = [:]

    /// The request body parsed as a browsable dictionary structure.
    @Published var requestBodyDictionary: [String: [String: Any]] = [:]

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

    /// The names of the request overrides that shaped this request, in the order they applied.
    ///
    /// Empty when no override matched, which is the case for every request captured while the
    /// master switch is off.
    @Published var appliedRuleNames: [String] = []

    /// The overrides that shaped this request, resolved from the store, in the order they applied.
    ///
    /// Only overrides the store still holds appear here, so a capture whose override has since
    /// been deleted keeps its names in ``appliedRuleNames`` without offering a link to nothing.
    @Published var appliedOverrides: [NetworkRule] = []

    /// Whether the response was synthesised by a mock or map-local override rather than received
    /// from the network.
    @Published var wasStubbed: Bool = false

    /// Whether a response was ever recorded for this request.
    ///
    /// A request that is still in flight, or that failed before any response arrived, has nothing
    /// worth turning into a mock.
    @Published var hasResponse: Bool = false

    /// The replays of this request that are currently in the log, newest first.
    ///
    /// Empty on a request nothing has been replayed from, which is the common case.
    @Published var replayLinks: [ReplayLink] = []

    /// The request this one replays, when it is a replay and the original is still in the log.
    @Published var originalRequest: HTTPRequest?

    /// Whether this request is a replay, whether or not its original survives in the log.
    ///
    /// Distinct from ``originalRequest`` being non-`nil`: clearing the log removes the original
    /// while this capture is still a replay, and the page says so rather than silently dropping
    /// the section.
    @Published var isReplay: Bool = false

    /// A one-line description of ``originalRequest`` for the row that links back to it.
    @Published var originalSummary: String = ""

    /// Whether the "Replay this request" button is offered.
    ///
    /// A synthesised response has no real request behind it worth resending — the override that
    /// made it would simply make it again — so the button is hidden there, matching the
    /// "Save as mock" button's refusal to mock a mock. A capture with no URL cannot be sent
    /// anywhere.
    var canReplay: Bool {
        !wasStubbed && !requestURL.isEmpty
    }

    /// Whether the "Save as mock" button is offered.
    ///
    /// There must be a response to copy, and it must have come off the wire: offering to mock a
    /// response an override already synthesised would only duplicate the override that made it.
    var canSaveAsMock: Bool {
        hasResponse && !wasStubbed
    }

    /// Creates a new log details view model.
    ///
    /// - Parameters:
    ///   - httpRequest: The HTTP request to display details for
    ///   - store: The override store a mock built from this capture is written to. Defaults to
    ///     the shared store; a test passes a throwaway one.
    ///
    /// - Note: Isolated to the main actor because the default store is, and because the view that
    ///   builds this view model is itself main-actor isolated.
    @MainActor
    init(httpRequest: HTTPRequest, store: NetworkRuleStore = .shared) {
        self.httpRequest = httpRequest
        self.ruleStore = store
        super.init()
    }

    /// Starts watching the log so the Replays section keeps up with what arrives after the page
    /// opened.
    ///
    /// A replay is only added to the log once it has finished, which is seconds after the editor
    /// dismissed and the developer is already looking at this page. Loading the related requests
    /// once on appearance would show an empty Replays section for the request they had just
    /// replayed, and never correct itself.
    ///
    /// The log's own `AsyncStream` is deliberately not used: it holds a single continuation, so
    /// subscribing here would silently steal it from ``NetworkLogsViewModel`` and stop the log
    /// list updating. The notification the interceptor already posts alongside every insertion
    /// carries the same news without that cost.
    override func setup() {
        super.setup()
        logObserver = NotificationCenter.default.addObserver(
            forName: .LoggerReloadData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadRelatedRequests()
            }
        }
    }

    /// Stops watching the log.
    deinit {
        if let logObserver {
            NotificationCenter.default.removeObserver(logObserver)
        }
    }

    /// Prepares the view model when the view first appears.
    ///
    /// This method triggers processing of the HTTP request data into all formatted properties.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadDetails()
        await loadRelatedRequests()
    }

    /// Reloads the replays of this request and the request it replays, from the current log.
    ///
    /// Cheap enough to run on every insertion: two passes over an in-memory array and a handful
    /// of subtractions.
    @MainActor
    func loadRelatedRequests() async {
        let items = await NetworkLogger.instance.items
        replayLinks = NetworkLogsViewModel.replays(of: httpRequest, in: items).map {
            ReplayLink(replay: $0, original: httpRequest)
        }
        isReplay = httpRequest.replayOfID != nil
        let original = NetworkLogsViewModel.original(of: httpRequest, in: items)
        originalRequest = original
        originalSummary = original.map(Self.summary(of:)) ?? localized("No longer in the log")
    }

    /// A one-line description of a request, for the row that links to it.
    ///
    /// - Parameter request: The request to describe.
    /// - Returns: Its method and status, e.g. `POST 200`, or its method and a failure marker.
    nonisolated static func summary(of request: HTTPRequest) -> String {
        let method = request.requestMethod ?? "-"
        guard let code = request.responseCode else { return "\(method) \(localized("Failed"))" }
        return "\(method) \(code)"
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
        responseSize = localized("\(httpRequest.responseBodyLength ?? 0) bytes")
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
        requestBodyDictionary = httpRequest.getRequestBodyDictionary()

        hasGraphQL = httpRequest.isGraphQL
        graphQLOperationName = httpRequest.graphQLOperationName ?? "-"
        graphQLOperationType = httpRequest.graphQLOperationType?.displayName ?? "-"
        graphQLVariablesDictionary = httpRequest.getGraphQLVariablesDictionary()

        responseBody = httpRequest.getResponseBody() as String? ?? ""
        hasResponseBody = !responseBody.isEmpty
        responseBodyDictionary = httpRequest.getResponseBodyDictionary()

        requestTime = httpRequest.requestTime ?? "-"
        responseTime = httpRequest.responseTime ?? "-"
        cachePolicy = httpRequest.requestCachePolicy ?? "-"
        timeout = httpRequest.requestTimeout ?? "-"
        curlRequest = httpRequest.requestCurl ?? ""

        appliedRuleNames = httpRequest.appliedRuleNames
        appliedOverrides = resolveOverrides(for: httpRequest)
        wasStubbed = httpRequest.wasStubbed
        hasResponse = httpRequest.responseCode != nil
    }

    /// Resolves the overrides a capture recorded into the ones the store still holds.
    ///
    /// Matching is by identifier rather than by name, so two overrides sharing a name cannot send
    /// the developer to the wrong one. A capture recorded before identifiers were carried has an
    /// empty ``HTTPRequest/appliedRuleIDs`` and therefore resolves to nothing, which is correct:
    /// its names are still displayed, just not as links.
    ///
    /// - Parameter httpRequest: The capture to resolve.
    /// - Returns: The overrides still present in the store, in the order they applied.
    private func resolveOverrides(for httpRequest: HTTPRequest) -> [NetworkRule] {
        let known = ruleStore.rules + ruleStore.transientRules
        return httpRequest.appliedRuleIDs.compactMap { id in
            known.first { $0.id == id }
        }
    }

    /// Builds a disabled mock override pre-filled from this capture.
    ///
    /// The override matches the captured method, host and path exactly, and answers with the
    /// captured status code, headers and body, so enabling it replays the response the app
    /// actually received. The query string is deliberately left unconstrained — pinning a mock to
    /// the page number that happened to be captured is almost never what was meant.
    ///
    /// It starts disabled: creating it from the log should never change the behaviour of the app
    /// until the developer says so in the editor.
    ///
    /// The path is taken percent-encoded, because that is the form ``NetworkRuleMatch/matches(_:)``
    /// compares against — a captured `/v1/a%2Fb` has to keep its escaped separator or the override
    /// would match a different endpoint than the one it was built from.
    ///
    /// - Returns: The pre-filled override, not yet added to ``ruleStore``. The response body
    ///   travels with the override rather than being written here, so abandoning the editor leaves
    ///   nothing on disk to reclaim.
    @MainActor
    func makeMockRule() -> NetworkRule {
        let components = httpRequest.requestURL.flatMap { URLComponents(string: $0) }
        let method = (httpRequest.requestMethod ?? "GET").uppercased()
        let path = (components?.percentEncodedPath).flatMap { $0.isEmpty ? nil : $0 } ?? "/"

        let match = NetworkRuleMatch(
            methods: [method],
            host: components?.host.map { NetworkRulePattern(kind: .exact, value: $0) },
            path: NetworkRulePattern(kind: .exact, value: path)
        )

        var headers: [String: String] = [:]
        for (key, value) in httpRequest.responseHeaders ?? [:] {
            guard let key = key as? String, let value = value as? String,
                  !Self.wireEncodingHeaders.contains(key.lowercased()) else { continue }
            headers[key] = value
        }

        let body = httpRequest.readRawData(httpRequest.getResponseBodyFilepath())
        var mock = MockResponse(statusCode: httpRequest.responseCode ?? 200,
                                headers: headers,
                                bodyID: nil,
                                delay: 0)
        if let body, !body.isEmpty {
            mock.pendingBody = body
        }

        return NetworkRule(
            name: "\(method) \(path)",
            isEnabled: false,
            match: match,
            actions: NetworkRuleActions(stub: .mock(mock))
        )
    }
}

/// One row of the Replays section: a replay of the request on screen, and how it differed.
///
/// The formatting is done once, when the log changes, rather than in the view body, so a row is a
/// pair of strings by the time SwiftUI draws it.
struct ReplayLink: Identifiable {
    /// The replay this row links to.
    let replay: HTTPRequest

    /// How the replay compares to the request it was built from.
    let comparison: ReplayComparison

    /// The row's leading text: the replay's method and status, e.g. `POST 401`.
    let title: String

    /// The row's trailing text: the signed duration and size deltas, e.g. `+24 ms · -460 B`.
    ///
    /// Empty when neither delta could be computed, which is the case for a replay that failed
    /// before a response arrived — its title already says `Failed`, and an em dash beside it
    /// would add nothing.
    let detail: String

    /// A stable identity for `ForEach`, taken from the capture itself.
    var id: ObjectIdentifier { ObjectIdentifier(replay) }

    /// Builds a row.
    ///
    /// - Parameters:
    ///   - replay: The replay to describe.
    ///   - original: The request it was built from.
    init(replay: HTTPRequest, original: HTTPRequest) {
        self.replay = replay
        let comparison = ReplayComparison(original: original, replay: replay)
        self.comparison = comparison
        self.title = LogDetailsViewModel.summary(of: replay)
        self.detail = [comparison.durationDeltaText, comparison.sizeDeltaText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
