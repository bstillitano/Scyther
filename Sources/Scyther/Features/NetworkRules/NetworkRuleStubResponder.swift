//
//  NetworkRuleStubResponder.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Builds the response a stub rule serves in place of a real one.
///
/// Kept separate from `HTTPInterceptorURLProtocol` so that turning a ``NetworkRuleStub`` into bytes can
/// be tested without a `URLSession`, a client or a network. The responder performs no I/O beyond
/// reading a mapped file, and it never touches the `@MainActor` ``NetworkRuleStore``: mock bodies
/// arrive through the injected `bodyProvider`.
///
/// ## Topics
///
/// ### Serving a Stub
/// - ``response(for:url:bodyProvider:)``
/// - ``maximumMappedFileBytes``
internal enum NetworkRuleStubResponder {
    /// The largest local file a map-local override will serve, in bytes.
    ///
    /// A map-local override points at whatever the developer chose, and the file is read whole:
    /// the bytes have to be handed to the client in one piece and written to the log beside it, so
    /// there is nowhere to stream them to. A 200 MB fixture would therefore be resident twice over
    /// inside a host app that has no idea Scyther is holding it, which is a way to have a
    /// debugging tool terminated for memory rather than a way to debug.
    ///
    /// Ten megabytes matches the cap on a held response body, which is the other place the
    /// interceptor keeps a whole body in memory.
    static let maximumMappedFileBytes: Int = 10 * 1024 * 1024

    /// Materialises a stub into an `HTTPURLResponse` and its body.
    ///
    /// A mapped file larger than ``maximumMappedFileBytes`` is refused and logged rather than
    /// read, so the request falls through to the network exactly as one pointing at a file that
    /// has been deleted does. Refusing loudly is the point: silently serving a file that costs the
    /// host app a low-memory termination is not a trade a debugging tool gets to make on the
    /// developer's behalf.
    ///
    /// - Parameters:
    ///   - stub: The mock or map-local action that matched.
    ///   - url: The request's URL, used as the response's URL.
    ///   - bodyProvider: Resolves a stored body id to its bytes. Injected so the responder
    ///     performs no I/O of its own and stays testable.
    /// - Returns: The response and body, or `nil` when a mapped file cannot be read or is over the
    ///   size cap — in which case the caller performs the request normally rather than failing it.
    static func response(
        for stub: NetworkRuleStub,
        url: URL,
        bodyProvider: (UUID) -> Data?
    ) -> (HTTPURLResponse, Data)? {
        switch stub {
        case .mock(let mock):
            let body = mock.bodyID.flatMap(bodyProvider) ?? Data()
            guard let response = HTTPURLResponse(
                url: url, statusCode: mock.statusCode, httpVersion: "HTTP/1.1", headerFields: mock.headers
            ) else { return nil }
            return (response, body)

        case .mapLocal(let file):
            let fileURL = URL(fileURLWithPath: file.path)
            guard let body = mappedFileBody(at: fileURL) else { return nil }
            var headers: [String: String] = [:]
            if let contentType = file.contentType { headers["Content-Type"] = contentType }
            guard let response = HTTPURLResponse(
                url: url, statusCode: file.statusCode, httpVersion: "HTTP/1.1", headerFields: headers
            ) else { return nil }
            return (response, body)
        }
    }

    /// Reads a mapped file, refusing one that is too large to hold in memory.
    ///
    /// The size is taken with a `stat` before anything is read, so an oversized file costs a file
    /// system lookup rather than its own length in bytes. Reading is memory-mapped where the
    /// platform can, which keeps even a file inside the cap off the heap until it is used.
    ///
    /// - Parameter url: The file the override points at.
    /// - Returns: The file's bytes, or `nil` when it cannot be read or is over
    ///   ``maximumMappedFileBytes``.
    private static func mappedFileBody(at url: URL) -> Data? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, size > maximumMappedFileBytes {
            logMessage("Map local skipped: \(url.lastPathComponent) is \(size) bytes, over the \(maximumMappedFileBytes) byte limit for a mapped file.")
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
