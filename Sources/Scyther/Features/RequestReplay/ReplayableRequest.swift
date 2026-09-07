//
//  ReplayableRequest.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// An editable copy of a captured request, and the bridge back to a live `URLRequest`.
///
/// Headers are an ordered array rather than a dictionary because a duplicated header
/// (`Accept`, `Cookie`) is meaningful on the wire, and a dictionary would silently collapse it.
/// The rows a draft starts with are ordered alphabetically — the capture stores its headers in a
/// dictionary, so there is no original order left to preserve — but every order the developer
/// then puts them in survives all the way onto the request.
///
/// The type is pure: it reads a capture and produces a `URLRequest`, and nothing about sending,
/// logging or presenting it happens here.
struct ReplayableRequest: Equatable, Sendable {
    /// One editable header row.
    ///
    /// Identity is carried so a `ForEach` row keeps its focus while its name is being typed, and
    /// is deliberately excluded from equality: rebuilding the same headers must not read as an
    /// edit — see ``ReplayableRequest/isModified(from:)``.
    struct Header: Identifiable, Equatable, Sendable {
        /// A stable identity, so a row keeps its focus while it is being typed into.
        let id = UUID()

        /// The header name, e.g. `Authorization`.
        var name: String

        /// The header value.
        var value: String

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

    /// The HTTP method the replay is sent with.
    var method: String

    /// The absolute URL the replay is sent to, as typed.
    var url: String

    /// The headers the replay is sent with, in the order they will be applied.
    var headers: [Header]

    /// The request body, or `nil` when the replay carries none.
    ///
    /// Always either absent or valid UTF-8. A capture only ever supplies a body the logger wrote,
    /// and the logger writes one only when it decodes as UTF-8; every other way in goes through
    /// ``setBodyText(_:)``. That invariant is what retires the editor's old "binary body, sent
    /// unchanged" branch, which nothing could reach.
    private(set) var body: Data?

    /// How many bytes of body the capture had that the log could not keep, or `nil` when there
    /// were none.
    ///
    /// The logger writes a request body to disk only when it decodes as UTF-8, but it measures it
    /// either way, so a capture that reports a length with nothing on disk had a binary body — a
    /// protobuf, a multipart upload — that cannot be recovered and therefore cannot be replayed.
    ///
    /// Recording it is what lets the editor say so. Without it the draft simply had no body, read
    /// as an empty one, and a protobuf `POST` was resent with nothing in it while the comparison
    /// row reported a size delta as though the server had answered with less.
    ///
    /// Editing the body clears it: once the developer has typed a body of their own there is
    /// nothing missing from the request any more.
    private(set) var uncapturedBodyByteCount: Int?

    /// Headers `URLSession` sets itself. Editing them has no effect, so the UI marks them managed
    /// and ``makeURLRequest(replayOf:)`` drops them rather than sending a value the system will
    /// overwrite or reject.
    static let managedHeaderNames: Set<String> = ["content-length", "host", "connection"]

    /// Whether a header name is one the system manages.
    ///
    /// Matching is case-insensitive and ignores surrounding whitespace, because a header name is
    /// case-insensitive on the wire and a typed row can carry either.
    ///
    /// - Parameter name: The header name to test.
    /// - Returns: Whether `URLSession` owns this header.
    static func isManaged(_ name: String) -> Bool {
        managedHeaderNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Builds a draft from a captured request, reading its body from disk.
    ///
    /// A body that was never valid UTF-8 was never written to disk by the logger, so it comes
    /// back `nil` here. The capture still knows how big it was, and that length is kept in
    /// ``uncapturedBodyByteCount`` so the editor can say the request had a body it cannot resend
    /// rather than quietly sending none.
    ///
    /// - Parameter request: The capture to start from.
    init(capturing request: HTTPRequest) {
        method = request.requestMethod ?? "GET"
        url = request.requestURL ?? ""
        headers = (request.requestHeaders ?? [:])
            .compactMap { key, value in
                guard let name = key as? String else { return nil }
                return Header(name: name, value: "\(value)")
            }
            .sorted { $0.name < $1.name }
        let data = request.readRawData(request.getRequestBodyFilepath())
        body = (data?.isEmpty == false) ? data : nil
        if body == nil, let captured = request.requestBodyLength, captured > 0 {
            uncapturedBodyByteCount = captured
        }
    }

    /// The body as text. An absent body reads as empty text, so the editor opens on it without a
    /// special case.
    var bodyText: String {
        guard let body else { return "" }
        return String(decoding: body, as: UTF8.self)
    }

    /// Whether the capture carried a body that this replay cannot send.
    ///
    /// Drives every place the editor says so: the body row, the overview footer, and the
    /// confirmation the send button asks for.
    var hasUncapturedBody: Bool { uncapturedBodyByteCount != nil }

    /// The number of bytes the body carries.
    var bodyByteCount: Int {
        body?.count ?? 0
    }

    /// Replaces the body with the UTF-8 bytes of `text`.
    ///
    /// Empty text clears the body outright rather than sending a zero-length one, because an
    /// emptied field reads as "send nothing" and a zero-length body is a different request.
    ///
    /// Writing a body also clears ``uncapturedBodyByteCount``: the developer has supplied the
    /// bytes the log could not, so there is no longer anything missing to warn about.
    ///
    /// - Parameter text: The new body text.
    mutating func setBodyText(_ text: String) {
        body = text.isEmpty ? nil : Data(text.utf8)
        uncapturedBodyByteCount = nil
    }

    /// The URL the draft would be sent to, or `nil` when what has been typed is not one.
    ///
    /// A request needs somewhere absolute to go, so a scheme and a host are both required: a bare
    /// path or a scheme on its own parse as a `URL` but cannot be sent. Surrounding whitespace is
    /// trimmed, because a URL pasted from a terminal usually arrives with some.
    var parsedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme != nil, parsed.host != nil else { return nil }
        return parsed
    }

    /// Whether the URL as typed can be sent. Drives the editor's inline warning.
    var isURLValid: Bool { parsedURL != nil }

    /// Builds the outgoing request, stamped with the hash of the request it replays.
    ///
    /// The URL and method are trimmed, and the method uppercased, so a stray space typed into
    /// either does not produce a request the server rejects for a reason the developer cannot
    /// see. Unnamed header rows — an add row that was never filled in — are dropped, as are the
    /// headers in ``managedHeaderNames``.
    ///
    /// Duplicated header names are added rather than set, so two `Accept` rows travel as the one
    /// comma-joined field HTTP defines rather than one of them silently winning.
    ///
    /// The request is also marked as Scyther's own — see ``ScytherOriginatedRequest``. A replay is
    /// composed and sent by the toolkit, not by the app, and what the developer asked for is *this
    /// request, as edited, against the server*. A mock answering it would have made the editor's
    /// comparison against the original a comparison against a stub, silently; a breakpoint holding
    /// it would have stalled the editor that sent it; a rewrite would have put back a header the
    /// developer had just deleted. It is still logged, so it still lands beside the original.
    ///
    /// - Parameter originalID: The original's `getRandomHash()` value.
    /// - Returns: The request, or `nil` when `url` does not parse into an absolute HTTP URL.
    func makeURLRequest(replayOf originalID: String) -> URLRequest? {
        guard let parsed = parsedURL else { return nil }
        let mutable = NSMutableURLRequest(url: parsed)
        mutable.httpMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !Self.isManaged(name) else { continue }
            mutable.addValue(header.value, forHTTPHeaderField: name)
        }
        mutable.httpBody = body
        URLProtocol.setProperty(originalID, forKey: replayOfRequestKey, in: mutable)
        ScytherOriginatedRequest.mark(mutable)
        return mutable as URLRequest
    }

    /// Whether anything differs from the draft this one started as.
    ///
    /// - Parameter original: The draft the editor opened on.
    /// - Returns: Whether the two differ in method, URL, headers or body.
    func isModified(from original: ReplayableRequest) -> Bool { self != original }
}
