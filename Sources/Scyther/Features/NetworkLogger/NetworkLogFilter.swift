//
//  NetworkLogFilter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// A coarse grouping of HTTP response status codes used for filtering network logs.
///
/// Requests that have not yet received a response (or that failed without one) are
/// grouped under ``pending``.
enum HTTPStatusClass: String, CaseIterable, Hashable, Sendable {
    /// 2xx responses.
    case success
    /// 3xx responses.
    case redirect
    /// 4xx responses.
    case clientError
    /// 5xx responses.
    case serverError
    /// No response received, or a response code outside the standard ranges.
    case pending

    /// A short label suitable for display in a chip or list row.
    var displayName: String {
        switch self {
        case .success: return "2xx Success"
        case .redirect: return "3xx Redirect"
        case .clientError: return "4xx Client Error"
        case .serverError: return "5xx Server Error"
        case .pending: return "Pending / No Response"
        }
    }

    /// Derives the status class for a captured request from its response code.
    ///
    /// - Parameter request: The request to classify.
    init(request: HTTPRequest) {
        switch request.responseCode ?? 0 {
        case 200..<300: self = .success
        case 300..<400: self = .redirect
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default: self = .pending
        }
    }
}

/// Whether a request is plain REST or a GraphQL operation.
enum APIKind: String, CaseIterable, Hashable, Sendable {
    /// Not detected as GraphQL.
    case rest
    /// Detected as GraphQL.
    case graphQL

    /// A short label suitable for display in a list row.
    var displayName: String {
        switch self {
        case .rest: return "REST"
        case .graphQL: return "GraphQL"
        }
    }

    /// Derives the kind for a captured request.
    ///
    /// - Parameter request: The request to classify.
    init(request: HTTPRequest) {
        self = request.isGraphQL ? .graphQL : .rest
    }
}

/// The operation type of a GraphQL request.
enum GraphQLOperationFilter: String, CaseIterable, Hashable, Sendable {
    /// A GraphQL query.
    case query
    /// A GraphQL mutation.
    case mutation
    /// A GraphQL subscription.
    case subscription
    /// A GraphQL request with no single operation type, such as a batched payload.
    case batch

    /// A short label suitable for display in a list row.
    var displayName: String {
        switch self {
        case .query: return "Query"
        case .mutation: return "Mutation"
        case .subscription: return "Subscription"
        case .batch: return "Batch / Unknown"
        }
    }

    /// Derives the operation for a captured GraphQL request, or `nil` for a non-GraphQL request.
    ///
    /// - Parameter request: The request to classify.
    init?(request: HTTPRequest) {
        guard request.isGraphQL else { return nil }
        switch request.graphQLOperationType {
        case .query: self = .query
        case .mutation: self = .mutation
        case .subscription: self = .subscription
        case nil: self = .batch
        }
    }
}

/// A coarse bucket for how long a request took, from send to response.
enum DurationBucket: String, CaseIterable, Hashable, Sendable {
    case under100ms
    case from100msTo500ms
    case from500msTo1s
    case from1sTo3s
    case over3s

    /// A short label suitable for display in a list row.
    var displayName: String {
        switch self {
        case .under100ms: return "Under 100ms"
        case .from100msTo500ms: return "100ms to 500ms"
        case .from500msTo1s: return "500ms to 1s"
        case .from1sTo3s: return "1s to 3s"
        case .over3s: return "Over 3s"
        }
    }

    /// Derives the bucket for a captured request, or `nil` if it has no duration yet.
    ///
    /// - Parameter request: The request to classify.
    init?(request: HTTPRequest) {
        guard let milliseconds = request.requestDuration else { return nil }
        switch milliseconds {
        case ..<100: self = .under100ms
        case ..<500: self = .from100msTo500ms
        case ..<1000: self = .from500msTo1s
        case ..<3000: self = .from1sTo3s
        default: self = .over3s
        }
    }
}

/// A trailing time window measured back from "now" in which a request must have been sent.
enum RecencyWindow: String, CaseIterable, Hashable, Sendable {
    case lastMinute
    case lastFiveMinutes
    case lastFifteenMinutes
    case lastHour

    /// A short label suitable for display in a list row.
    var displayName: String {
        switch self {
        case .lastMinute: return "Last minute"
        case .lastFiveMinutes: return "Last 5 minutes"
        case .lastFifteenMinutes: return "Last 15 minutes"
        case .lastHour: return "Last hour"
        }
    }

    /// The window length in seconds.
    var seconds: TimeInterval {
        switch self {
        case .lastMinute: return 60
        case .lastFiveMinutes: return 300
        case .lastFifteenMinutes: return 900
        case .lastHour: return 3600
        }
    }

    /// Whether `date` falls inside this window ending at `now`.
    ///
    /// - Parameters:
    ///   - date: The request date to test.
    ///   - now: The end of the window.
    func contains(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) <= seconds
    }
}

/// Whether the selected hosts in a ``NetworkLogFilter`` are the only ones shown or the ones hidden.
enum HostFilterMode: String, CaseIterable, Hashable, Sendable {
    /// Show only requests to the selected hosts.
    case include
    /// Hide requests to the selected hosts.
    case exclude

    /// The segment label for this mode.
    var displayName: String {
        switch self {
        case .include: return "Include"
        case .exclude: return "Exclude"
        }
    }
}

/// A logical grouping of ``NetworkLogFilterDimension`` values, used to section the all-filters sheet.
enum NetworkLogFilterGroup: String, CaseIterable, Identifiable, Sendable {
    /// Dimensions describing what was sent.
    case request
    /// Dimensions describing what came back.
    case response
    /// Dimensions describing when and how long.
    case timing

    var id: String { rawValue }

    /// The section header for this group.
    var title: String {
        switch self {
        case .request: return "Request"
        case .response: return "Response"
        case .timing: return "Timing"
        }
    }

    /// The dimensions in this group, in display order.
    var dimensions: [NetworkLogFilterDimension] {
        switch self {
        case .request: return [.method, .host, .api, .graphQL]
        case .response: return [.status, .statusCode, .contentType]
        case .timing: return [.duration, .recency]
        }
    }
}

/// The dimensions a ``NetworkLogFilter`` can constrain, one per chip in the filter bar.
enum NetworkLogFilterDimension: String, CaseIterable, Identifiable, Sendable {
    case method
    case status
    case host
    case contentType
    case api
    case graphQL
    case duration
    case statusCode
    case recency

    var id: String { rawValue }

    /// The group this dimension is sectioned under in the all-filters sheet.
    var group: NetworkLogFilterGroup {
        switch self {
        case .method, .host, .api, .graphQL: return .request
        case .status, .statusCode, .contentType: return .response
        case .duration, .recency: return .timing
        }
    }

    /// The chip and sheet title for this dimension.
    var title: String {
        switch self {
        case .method: return "Method"
        case .status: return "Status"
        case .host: return "Host"
        case .contentType: return "Type"
        case .api: return "API"
        case .graphQL: return "GraphQL"
        case .duration: return "Duration"
        case .statusCode: return "Code"
        case .recency: return "Recency"
        }
    }

    /// The SF Symbol shown on the chip for this dimension.
    var systemImage: String {
        switch self {
        case .method: return "arrow.left.arrow.right"
        case .status: return "checkmark.circle"
        case .host: return "globe"
        case .contentType: return "doc.text"
        case .api: return "network"
        case .graphQL: return "point.3.connected.trianglepath.dotted"
        case .duration: return "timer"
        case .statusCode: return "number"
        case .recency: return "clock"
        }
    }

    /// Whether only one option may be selected at a time. Selecting another option replaces it.
    var isSingleSelect: Bool {
        self == .recency
    }

    /// Whether this dimension's options are derived from the captured logs rather than a fixed list.
    var isDerivedFromLogs: Bool {
        switch self {
        case .method, .host, .statusCode: return true
        case .status, .contentType, .api, .graphQL, .duration, .recency: return false
        }
    }
}

/// A set of constraints applied to the network log list in addition to text search.
///
/// Each dimension holds a set of accepted values. An empty set means the dimension is
/// not constrained. Dimensions combine with AND; values within a dimension combine with OR.
///
/// ## Usage
///
/// ```swift
/// var filter = NetworkLogFilter()
/// filter.methods = ["GET"]
/// filter.statusClasses = [.clientError, .serverError]
/// let failures = requests.filter(filter.matches)
/// ```
struct NetworkLogFilter: Equatable, Sendable {
    /// Accepted HTTP methods, compared case-insensitively. Stored uppercased.
    var methods: Set<String> = []

    /// Accepted response status classes.
    var statusClasses: Set<HTTPStatusClass> = []

    /// Selected request hosts, compared case-insensitively. Stored lowercased.
    ///
    /// Whether these are included or excluded is governed by ``hostMode``.
    var hosts: Set<String> = []

    /// Whether ``hosts`` is an allow list or a deny list. Has no effect while ``hosts`` is empty.
    var hostMode: HostFilterMode = .include

    /// Accepted response content types.
    var contentTypes: Set<HTTPModelShortType> = []

    /// Accepted API kinds (REST or GraphQL).
    var apiKinds: Set<APIKind> = []

    /// Accepted GraphQL operation types. REST requests never match when this is non-empty.
    var graphQLOperations: Set<GraphQLOperationFilter> = []

    /// Accepted duration buckets. Requests with no duration never match when this is non-empty.
    var durationBuckets: Set<DurationBucket> = []

    /// Accepted exact response status codes.
    var statusCodes: Set<Int> = []

    /// The window in which a request must have been sent, or `nil` for no constraint.
    var recencyWindow: RecencyWindow?

    /// Creates an empty filter that matches every request.
    init() {}

    /// Whether any dimension is constrained.
    var isActive: Bool {
        totalSelectionCount > 0
    }

    /// The number of selected values across every dimension.
    var totalSelectionCount: Int {
        NetworkLogFilterDimension.allCases.reduce(0) { $0 + selectionCount(for: $1) }
    }

    /// Removes every constraint.
    mutating func clear() {
        self = NetworkLogFilter()
    }

    /// The number of selected values for a dimension.
    ///
    /// - Parameter dimension: The dimension to count.
    func selectionCount(for dimension: NetworkLogFilterDimension) -> Int {
        selection(for: dimension).count
    }

    /// The selected values for a dimension as raw strings.
    ///
    /// Methods and hosts are returned as stored; status classes and content types are
    /// returned as their `rawValue`.
    ///
    /// - Parameter dimension: The dimension to read.
    func selection(for dimension: NetworkLogFilterDimension) -> Set<String> {
        switch dimension {
        case .method: return methods
        case .status: return Set(statusClasses.map(\.rawValue))
        case .host: return hosts
        case .contentType: return Set(contentTypes.map(\.rawValue))
        case .api: return Set(apiKinds.map(\.rawValue))
        case .graphQL: return Set(graphQLOperations.map(\.rawValue))
        case .duration: return Set(durationBuckets.map(\.rawValue))
        case .statusCode: return Set(statusCodes.map(String.init))
        case .recency: return recencyWindow.map { [$0.rawValue] } ?? []
        }
    }

    /// Replaces the selected values for a dimension using raw strings.
    ///
    /// Unknown raw values are ignored. For a single-select dimension such as recency, the widest
    /// window among `values` is kept.
    ///
    /// - Parameters:
    ///   - values: The raw values to select.
    ///   - dimension: The dimension to write.
    mutating func setSelection(_ values: Set<String>, for dimension: NetworkLogFilterDimension) {
        switch dimension {
        case .method: methods = Set(values.map { $0.uppercased() })
        case .status: statusClasses = Set(values.compactMap(HTTPStatusClass.init(rawValue:)))
        case .host: hosts = Set(values.map { $0.lowercased() })
        case .contentType: contentTypes = Set(values.compactMap(HTTPModelShortType.init(rawValue:)))
        case .api: apiKinds = Set(values.compactMap(APIKind.init(rawValue:)))
        case .graphQL: graphQLOperations = Set(values.compactMap(GraphQLOperationFilter.init(rawValue:)))
        case .duration: durationBuckets = Set(values.compactMap(DurationBucket.init(rawValue:)))
        case .statusCode: statusCodes = Set(values.compactMap(Int.init))
        case .recency: recencyWindow = values.compactMap(RecencyWindow.init(rawValue:)).max { $0.seconds < $1.seconds }
        }
    }

    /// Whether a request satisfies every constrained dimension.
    ///
    /// - Parameters:
    ///   - request: The request to test.
    ///   - now: The reference time for recency windows. Defaults to the current time.
    func matches(_ request: HTTPRequest, now: Date = Date()) -> Bool {
        if !methods.isEmpty {
            guard let method = request.requestMethod?.uppercased(), methods.contains(method) else {
                return false
            }
        }
        if !statusClasses.isEmpty, !statusClasses.contains(HTTPStatusClass(request: request)) {
            return false
        }
        if !hosts.isEmpty {
            let isListed = request.host.map(hosts.contains) ?? false
            switch hostMode {
            case .include where !isListed: return false
            case .exclude where isListed: return false
            default: break
            }
        }
        if !contentTypes.isEmpty {
            guard let type = HTTPModelShortType(rawValue: request.shortType),
                  contentTypes.contains(type) else { return false }
        }
        if !apiKinds.isEmpty, !apiKinds.contains(APIKind(request: request)) {
            return false
        }
        if !graphQLOperations.isEmpty {
            guard let operation = GraphQLOperationFilter(request: request),
                  graphQLOperations.contains(operation) else { return false }
        }
        if !durationBuckets.isEmpty {
            guard let bucket = DurationBucket(request: request), durationBuckets.contains(bucket) else {
                return false
            }
        }
        if !statusCodes.isEmpty {
            guard let code = request.responseCode, statusCodes.contains(code) else { return false }
        }
        if let recencyWindow {
            guard let date = request.requestDate, recencyWindow.contains(date, now: now) else { return false }
        }
        return true
    }
}

extension HTTPRequest {
    /// The lowercased host of the request URL, or `nil` if the URL has no host.
    var host: String? {
        if let host = requestURLComponents?.host, !host.isEmpty {
            return host.lowercased()
        }
        guard let urlString = requestURL,
              let host = URLComponents(string: urlString)?.host,
              !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }
}

/// A single selectable row in a ``NetworkLogFilterSheet`` or ``NetworkLogAllFiltersSheet``.
struct NetworkLogFilterOption: Identifiable, Hashable, Sendable {
    /// The raw value stored in the filter when selected.
    let id: String

    /// The label shown to the user.
    let title: String

    /// The fixed option list for a dimension whose values are not derived from the logs.
    ///
    /// Returns an empty array for ``NetworkLogFilterDimension/isDerivedFromLogs`` dimensions;
    /// callers must build those from the captured requests.
    ///
    /// - Parameter dimension: The dimension to list.
    static func staticOptions(for dimension: NetworkLogFilterDimension) -> [NetworkLogFilterOption] {
        switch dimension {
        case .status:
            return HTTPStatusClass.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.displayName) }
        case .contentType:
            return HTTPModelShortType.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.rawValue) }
        case .api:
            return APIKind.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.displayName) }
        case .graphQL:
            return GraphQLOperationFilter.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.displayName) }
        case .duration:
            return DurationBucket.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.displayName) }
        case .recency:
            return RecencyWindow.allCases.map { NetworkLogFilterOption(id: $0.rawValue, title: $0.displayName) }
        case .method, .host, .statusCode:
            return []
        }
    }
}
