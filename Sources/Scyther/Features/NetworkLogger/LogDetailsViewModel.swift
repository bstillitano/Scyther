//
//  LogDetailsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Combine
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
/// - ``appliedOverrideRows``
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

    /// Keeps the override store's publisher alive for the lifetime of the page.
    private var cancellables: Set<AnyCancellable> = []

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

    /// One row per override credited on this capture, in the order they applied.
    ///
    /// Every credit gets a row, whether or not the store still holds the override behind it: a
    /// deleted override is named but inert, and so is the global network conditioning, which is a
    /// screen rather than a rule. The list used to be the resolvable ones only, so as soon as any
    /// one name resolved the rest vanished — contradicting its own documentation.
    ///
    /// Rebuilt whenever the store changes, so a rename made through one of these rows is on the
    /// row when the developer comes back. It used to be filled in once, on first appear, and
    /// reopening the row handed the editor the rule as it was before the rename — which the next
    /// confirm then wrote back.
    @Published var appliedOverrideRows: [AppliedOverrideRow] = []

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

    /// Whether any row in the Replays section describes an exchange Scyther shaped.
    ///
    /// Drives the extra footer line explaining what such a row's figures do and do not measure.
    var hasShapedReplay: Bool { replayLinks.contains { !$0.comparison.isLikeForLike } }

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

        // The Overrides rows push the override's own editor, and confirming there writes back
        // through this store. Resolving once on first appear meant the second visit handed the
        // editor the rule as it was before the first edit, and the next confirm reverted it.
        //
        // The rules come from the publisher rather than from the store: `@Published` emits in
        // `willSet`, so reading `ruleStore.rules` back inside the sink would see the array as it
        // was *before* the edit that woke us — the same staleness this exists to fix. No
        // `receive(on:)` for the same reason `NetworkRulesViewModel` uses none: the store is
        // main-actor isolated and so is this, so hopping would only delay the redraw a frame.
        ruleStore.$rules
            .combineLatest(ruleStore.$transientRules)
            .sink { [weak self] rules, transient in
                guard let self else { return }
                self.appliedOverrideRows = self.resolveOverrides(for: self.httpRequest,
                                                                 known: rules + transient)
            }
            .store(in: &cancellables)
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
        appliedOverrideRows = resolveOverrides(for: httpRequest)
        wasStubbed = httpRequest.wasStubbed
        hasResponse = httpRequest.responseCode != nil
    }

    /// Builds one row per credit the capture recorded, resolving each against the store.
    ///
    /// Matching is by identifier rather than by name, so two overrides sharing a name cannot send
    /// the developer to the wrong one, and two sharing a name still get a row each — the rows are
    /// identified by their position, which is the only thing that is guaranteed unique.
    ///
    /// A capture recorded before identifiers were carried has an empty
    /// ``HTTPRequest/appliedRuleIDs``, and one credited to the global conditioning carries a `nil`
    /// entry. Both produce a named row that opens nothing, which is correct: there is nothing to
    /// open.
    ///
    /// - Parameters:
    ///   - httpRequest: The capture to resolve.
    ///   - known: The overrides the store holds, persisted and transient. Defaults to reading them
    ///     off the store, which is right everywhere but inside its own `willSet` publisher.
    /// - Returns: One row per credited name, in the order they applied.
    private func resolveOverrides(for httpRequest: HTTPRequest,
                                  known: [NetworkRule]? = nil) -> [AppliedOverrideRow] {
        let known = known ?? (ruleStore.rules + ruleStore.transientRules)
        return httpRequest.appliedRuleNames.enumerated().map { position, name in
            let id = httpRequest.appliedRuleIDs.indices.contains(position)
                ? httpRequest.appliedRuleIDs[position]
                : nil
            return AppliedOverrideRow(
                position: position,
                name: name,
                rule: id.flatMap { identifier in known.first { $0.id == identifier } }
            )
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

    /// The row's subtitle: what Scyther did to either side, or `nil` when it did nothing.
    ///
    /// Uses the same words as the log's own badges. Without it the section reported a duration
    /// and a size delta across a mocked, conditioned, held or edited exchange with nothing said —
    /// in the one place on the page built for comparison, and against the reason the replay
    /// editor's own footer exists.
    let note: String?

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
        self.note = Self.note(for: comparison)
    }

    /// Names what shaped each side, in the log's own badge words.
    ///
    /// - Parameter comparison: The comparison to describe.
    /// - Returns: For example `Original: MOCKED · Replay: HELD`, or `nil` when neither side was
    ///   shaped and the figures are the server's alone.
    private static func note(for comparison: ReplayComparison) -> String? {
        var parts: [String] = []
        if let words = words(for: comparison.originalShaping) {
            parts.append(localized("Original: \(words)"))
        }
        if let words = words(for: comparison.replayShaping) {
            parts.append(localized("Replay: \(words)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") // scyther:unlocalised separator
    }

    /// The badge words one shaping reads as.
    ///
    /// - Parameter shaping: What Scyther did to one side.
    /// - Returns: The words, joined, or `nil` when it did nothing.
    private static func words(for shaping: ReplayComparison.Shaping) -> String? {
        var words: [String] = []
        if shaping.contains(.stubbed) { words.append(localized("MOCKED")) }
        if shaping.contains(.overridden) { words.append(localized("OVERRIDDEN")) }
        if shaping.contains(.held) { words.append(localized("HELD")) }
        if shaping.contains(.edited) { words.append(localized("EDITED")) }
        return words.isEmpty ? nil : words.joined(separator: " ") // scyther:unlocalised separator
    }
}

/// One row of the request details page's Overrides section.
///
/// Carries the name the capture recorded and, when the store still holds it, the override behind
/// it. The two are separate because a credit can outlive its override — deleted since the capture
/// — and because one credit never had an override at all: the global network conditioning, which
/// is a screen rather than a rule.
struct AppliedOverrideRow: Identifiable, Equatable {
    /// The credit's position among this capture's credits, which is the row's identity.
    ///
    /// Position rather than name or override identifier: two overrides can share a name, and an
    /// unresolvable credit has no identifier at all, so neither is unique. The order is the order
    /// they applied in, which does not change for a capture already recorded.
    let id: Int

    /// The name the capture recorded, shown whether or not the override survives.
    let name: String

    /// The override the store still holds, or `nil` when there is nothing to open.
    let rule: NetworkRule?

    /// Whether tapping the row opens an editor.
    var isOpenable: Bool { rule != nil }

    /// Builds a row.
    ///
    /// - Parameters:
    ///   - position: The credit's position among this capture's credits.
    ///   - name: The name the capture recorded.
    ///   - rule: The override the store still holds, or `nil`.
    init(position: Int, name: String, rule: NetworkRule?) {
        self.id = position
        self.name = name
        self.rule = rule
    }
}
