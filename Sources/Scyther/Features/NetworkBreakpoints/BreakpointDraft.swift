//
//  BreakpointDraft.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// An editable snapshot of a request or a response held at a breakpoint.
///
/// The same type serves both stages: a request draft has a ``method`` and a ``url`` and no
/// ``statusCode``; a response draft has a ``statusCode`` and neither of the other two. One type
/// rather than two because everything downstream of it — the pause, the editor, the resolution —
/// is identical for both, and splitting it would double all three to express one absent field.
///
/// Headers are an ordered array rather than a dictionary because a duplicated header (`Accept`,
/// `Set-Cookie`) is meaningful on the wire and a dictionary would silently collapse it.
///
/// The type is pure: it reads a request or a response and produces one, and nothing about
/// pausing, presenting or logging happens here.
///
/// ## Topics
///
/// ### Capturing
/// - ``init(request:)``
/// - ``init(response:body:)``
///
/// ### Rebuilding
/// - ``makeURLRequest(basedOn:)``
/// - ``makeResponse(url:)``
///
/// ### The Body
/// - ``bodyText``
/// - ``isBodyEditable``
/// - ``bodyByteCount``
/// - ``setBodyText(_:)``
struct BreakpointDraft: Identifiable, Equatable, Sendable {
    /// One editable header row.
    ///
    /// Identity is carried so a `ForEach` row keeps its focus while its name is being typed, and
    /// is deliberately excluded from equality: rebuilding the same headers must not read as an
    /// edit, which is what decides whether the log marks the exchange as edited.
    struct Header: Identifiable, Equatable, Sendable {
        /// A stable identity, so a row keeps its focus while it is being typed into.
        let id = UUID()

        /// The header name, e.g. `Authorization`.
        var name: String

        /// The header value.
        var value: String

        /// Creates a header row.
        ///
        /// - Parameters:
        ///   - name: The header name.
        ///   - value: The header value.
        init(name: String, value: String) {
            self.name = name
            self.value = value
        }

        /// Compares two rows by what they say, not by which row said it.
        ///
        /// - Parameters:
        ///   - lhs: The first row.
        ///   - rhs: The second row.
        /// - Returns: Whether both name and value match.
        static func == (lhs: Header, rhs: Header) -> Bool {
            lhs.name == rhs.name && lhs.value == rhs.value
        }
    }

    /// A stable identity for the editor's `ForEach`, excluded from equality for the same reason
    /// ``Header/id`` is.
    let id = UUID()

    /// The HTTP method, for a request draft. `nil` for a response.
    var method: String?

    /// The absolute URL as text, for a request draft. `nil` for a response.
    var url: String?

    /// The status code, for a response draft. `nil` for a request.
    var statusCode: Int?

    /// The headers, in the order they will be applied.
    var headers: [Header]

    /// The body, or `nil` when the exchange carries none.
    var body: Data?

    /// Captures a request.
    ///
    /// Header rows are ordered alphabetically, because `URLRequest` stores them in a dictionary
    /// and there is no original order left to preserve.
    ///
    /// - Parameter request: The request about to be sent.
    init(request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url?.absoluteString ?? ""
        statusCode = nil
        headers = (request.allHTTPHeaderFields ?? [:])
            .map { Header(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        // `httpBody` is nil for the requests that actually reach a `URLProtocol`: `URLSession`
        // hands the body over as a stream, so reading it directly reported every POST as empty
        // and made the body uneditable for exactly the requests worth holding. `body` is the
        // toolkit's existing reader, which drains the stream and falls back to the property the
        // interceptor stashes.
        // `httpBody` first for a request that carries one directly, then the toolkit's reader for
        // the streamed case. The reader alone is not enough: it does not look at `httpBody`.
        let captured = request.httpBody ?? request.body
        body = (captured?.isEmpty == false) ? captured : nil
    }

    /// Captures a response and the body that came with it.
    ///
    /// - Parameters:
    ///   - response: The response about to be handed to the app.
    ///   - body: Every byte of the body, already buffered.
    init(response: HTTPURLResponse, body: Data) {
        method = nil
        url = nil
        statusCode = response.statusCode
        headers = response.allHeaderFields
            .compactMap { key, value in
                guard let name = key as? String else { return nil }
                return Header(name: name, value: "\(value)")
            }
            .sorted { $0.name < $1.name }
        self.body = body.isEmpty ? nil : body
    }

    /// The body as text, or `nil` when it is not valid UTF-8.
    ///
    /// An absent body reads as empty text, so the editor can open on it without a special case.
    var bodyText: String? {
        guard let body else { return "" }
        return String(data: body, encoding: .utf8)
    }

    /// Whether the body can be edited as text.
    ///
    /// False only for a body that is present and is not valid UTF-8. Such a body is passed on
    /// unchanged rather than mangled through a text editor.
    var isBodyEditable: Bool {
        bodyText != nil
    }

    /// The number of bytes the body carries.
    var bodyByteCount: Int {
        body?.count ?? 0
    }

    /// The URL a request draft would be sent to, or `nil` when what has been typed is not one.
    ///
    /// A scheme and a host are both required. `URL(string:)` alone is not a validity check —
    /// since iOS 17 it happily percent-encodes `not a url at all` into a relative URL — and a
    /// request needs somewhere absolute to go. Surrounding whitespace is trimmed, because a URL
    /// pasted from a terminal usually arrives with some.
    var parsedURL: URL? {
        guard let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme != nil, parsed.host != nil else {
            return nil
        }
        return parsed
    }

    /// Whether the URL as typed can be sent. Drives the editor's inline warning.
    ///
    /// True for a response draft, which carries no URL to be wrong about.
    var isURLValid: Bool {
        url == nil || parsedURL != nil
    }

    /// Replaces the body with the UTF-8 bytes of `text`.
    ///
    /// Empty text clears the body outright rather than carrying a zero-length one, because an
    /// emptied field reads as "send nothing".
    ///
    /// - Parameter text: The new body text.
    mutating func setBodyText(_ text: String) {
        body = text.isEmpty ? nil : Data(text.utf8)
    }

    /// Rebuilds the outgoing request from this draft.
    ///
    /// Starts from `original` rather than from a fresh `URLRequest` so that everything the draft
    /// does not describe — the cache policy, the timeout, and above all the protocol properties
    /// the interceptor stamps on a request it is about to send — travels with it. Losing those
    /// properties would have the rebuilt request intercepted a second time, which is a loop.
    ///
    /// The header rows **replace** the original's headers rather than being set over the top of
    /// them, so a row the developer deleted actually leaves the request. Rows with no name are
    /// dropped, as are the headers `URLSession` manages: sending a stale `Content-Length`
    /// alongside an edited body produces a failure with nothing pointing back at the breakpoint.
    /// A repeated name is added rather than set, so two `Accept` rows travel as the one
    /// comma-joined field HTTP defines rather than one of them silently winning.
    ///
    /// A ``url`` that is not an absolute HTTP URL leaves the original's URL alone. The editor
    /// already warns about it; refusing to send anything at all would strand the app instead.
    ///
    /// - Parameter original: The request the draft was captured from.
    /// - Returns: The request to send.
    func makeURLRequest(basedOn original: URLRequest) -> URLRequest {
        guard let mutable = (original as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return original
        }
        if let method, !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mutable.httpMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        if let parsed = parsedURL {
            mutable.url = parsed
        }
        /// Each existing header is removed by name. Assigning an empty dictionary to
        /// `allHTTPHeaderFields` leaves the request's headers exactly as they were, so a row the
        /// developer deleted would still have gone out.
        for name in (mutable.allHTTPHeaderFields ?? [:]).keys {
            mutable.setValue(nil, forHTTPHeaderField: name)
        }
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ReplayableRequest.isManaged(name) else { continue }
            mutable.addValue(header.value, forHTTPHeaderField: name)
        }
        mutable.httpBody = body
        return mutable as URLRequest
    }

    /// Rebuilds the response the app is about to be handed.
    ///
    /// - Parameter url: The URL the response belongs to, which `HTTPURLResponse` requires and a
    ///   draft does not carry.
    /// - Returns: The response and its body, or `nil` when this is a request draft or the status
    ///   code is one `HTTPURLResponse` refuses.
    func makeResponse(url: URL) -> (HTTPURLResponse, Data)? {
        guard let statusCode else { return nil }
        var fields: [String: String] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            fields[name] = header.value
        }
        guard let response = HTTPURLResponse(url: url,
                                             statusCode: statusCode,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: fields) else {
            return nil
        }
        return (response, body ?? Data())
    }

    /// Compares two drafts by what they carry, not by which draft carried it.
    ///
    /// - Parameters:
    ///   - lhs: The first draft.
    ///   - rhs: The second draft.
    /// - Returns: Whether the two describe the same exchange.
    static func == (lhs: BreakpointDraft, rhs: BreakpointDraft) -> Bool {
        lhs.method == rhs.method
            && lhs.url == rhs.url
            && lhs.statusCode == rhs.statusCode
            && lhs.headers == rhs.headers
            && lhs.body == rhs.body
    }
}
