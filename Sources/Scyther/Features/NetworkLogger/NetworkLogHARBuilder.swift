//
//  NetworkLogHARBuilder.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// The root of an HTTP Archive (HAR) 1.2 document.
struct HARLog: Codable, Sendable {
    let log: HARLogBody
}

/// The `log` object of a HAR document.
struct HARLogBody: Codable, Sendable {
    let version: String
    let creator: HARCreator
    /// Free text about the log, e.g. a redaction notice. Omitted from JSON when `nil`.
    let comment: String?
    let entries: [HAREntry]
}

/// The tool that produced a HAR document.
struct HARCreator: Codable, Sendable {
    let name: String
    let version: String
}

/// One captured request/response pair in a HAR document.
struct HAREntry: Codable, Sendable {
    let startedDateTime: String
    let time: Double
    let request: HARRequest
    let response: HARResponse
    let cache: HARCache
    let timings: HARTimings
}

/// The request half of a ``HAREntry``.
struct HARRequest: Codable, Sendable {
    let method: String
    let url: String
    let httpVersion: String
    let cookies: [HARCookie]
    let headers: [HARNameValue]
    let queryString: [HARNameValue]
    let postData: HARPostData?
    let headersSize: Int
    let bodySize: Int
}

/// The response half of a ``HAREntry``.
struct HARResponse: Codable, Sendable {
    let status: Int
    let statusText: String
    let httpVersion: String
    let cookies: [HARCookie]
    let headers: [HARNameValue]
    let content: HARContent
    let redirectURL: String
    let headersSize: Int
    let bodySize: Int
}

/// A header or query string pair.
struct HARNameValue: Codable, Sendable {
    let name: String
    let value: String
}

/// A cookie entry. Scyther does not capture cookies separately, so this is always empty.
struct HARCookie: Codable, Sendable {
    let name: String
    let value: String
}

/// A request body.
struct HARPostData: Codable, Sendable {
    let mimeType: String
    let text: String
}

/// A response body. `encoding` is `"base64"` when `text` is base64 rather than literal text.
struct HARContent: Codable, Sendable {
    let size: Int
    let mimeType: String
    let text: String?
    let encoding: String?
}

/// Cache information. Always empty; Scyther does not inspect the URL cache.
struct HARCache: Codable, Sendable {}

/// Phase timings in milliseconds. Scyther only measures total duration, reported as `wait`.
struct HARTimings: Codable, Sendable {
    let send: Double
    let wait: Double
    let receive: Double
}

/// Builds HAR 1.2 documents from captured ``HTTPRequest`` values.
///
/// HAR is the interchange format read by Charles, Proxyman, Chrome DevTools, and most HTTP
/// tooling. Bodies are embedded as text; image bodies are embedded as base64 and flagged with
/// `encoding: "base64"`.
///
/// ## Usage
///
/// ```swift
/// let har = NetworkLogHARBuilder.build(from: requests)
/// let data = try NetworkLogHARBuilder.encode(har)
/// ```
enum NetworkLogHARBuilder {
    /// The version reported for the creator when none is supplied: the host app's marketing
    /// version, since the toolkit does not embed its own.
    static var defaultCreatorVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Builds a HAR document from captured requests, ordered oldest first.
    ///
    /// - Parameters:
    ///   - requests: The requests to include.
    ///   - creatorVersion: The version recorded in the `creator` object.
    /// - Returns: The HAR document.
    static func build(from requests: [HTTPRequest], creatorVersion: String = defaultCreatorVersion) -> HARLog {
        let ordered = requests.sorted { ($0.requestDate ?? .distantPast) < ($1.requestDate ?? .distantPast) }
        return HARLog(log: HARLogBody(
            version: "1.2",
            creator: HARCreator(name: "Scyther", version: creatorVersion),
            comment: nil,
            entries: ordered.map(entry(for:))
        ))
    }

    /// Encodes a HAR document as pretty-printed JSON with stable key order.
    ///
    /// - Parameter log: The document to encode.
    static func encode(_ log: HARLog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(log)
    }

    // MARK: - Mapping

    private static func iso8601(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    private static func entry(for request: HTTPRequest) -> HAREntry {
        let duration = Double(request.requestDuration ?? 0)
        return HAREntry(
            startedDateTime: iso8601(request.requestDate ?? .distantPast),
            time: duration,
            request: harRequest(for: request),
            response: harResponse(for: request),
            cache: HARCache(),
            timings: HARTimings(send: 0, wait: duration, receive: 0)
        )
    }

    private static func harRequest(for request: HTTPRequest) -> HARRequest {
        let bodyData = request.readRawData(request.getRequestBodyFilepath())
        let postData: HARPostData? = bodyData.flatMap { data in
            guard !data.isEmpty else { return nil }
            return HARPostData(
                mimeType: request.requestType ?? "",
                text: String(decoding: data, as: UTF8.self)
            )
        }
        return HARRequest(
            method: request.requestMethod ?? "GET",
            url: request.requestURL ?? "",
            httpVersion: "HTTP/1.1",
            cookies: [],
            headers: nameValues(from: request.requestHeaders),
            queryString: (request.requestURLQueryItems ?? []).map {
                HARNameValue(name: $0.name, value: $0.value ?? "")
            },
            postData: postData,
            headersSize: -1,
            bodySize: bodyData?.count ?? 0
        )
    }

    private static func harResponse(for request: HTTPRequest) -> HARResponse {
        let status = request.responseCode ?? 0
        let bodyData = request.readRawData(request.getResponseBodyFilepath())
        let isImage = request.shortType == HTTPModelShortType.IMAGE.rawValue
        let text = bodyData.map { String(decoding: $0, as: UTF8.self) }
        let size = request.responseBodyLength ?? bodyData?.count ?? 0
        return HARResponse(
            status: status,
            statusText: status > 0 ? HTTPURLResponse.localizedString(forStatusCode: status) : "",
            httpVersion: "HTTP/1.1",
            cookies: [],
            headers: nameValues(from: request.responseHeaders),
            content: HARContent(
                size: size,
                mimeType: request.responseType ?? "",
                text: text,
                encoding: (isImage && text != nil) ? "base64" : nil
            ),
            redirectURL: "",
            headersSize: -1,
            bodySize: size
        )
    }

    private static func nameValues(from headers: [AnyHashable: Any]?) -> [HARNameValue] {
        (headers ?? [:])
            .compactMap { key, value -> HARNameValue? in
                guard let name = key as? String else { return nil }
                return HARNameValue(name: name, value: "\(value)")
            }
            .sorted { $0.name < $1.name }
    }
}
