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
internal enum NetworkRuleStubResponder {
    /// Materialises a stub into an `HTTPURLResponse` and its body.
    ///
    /// - Parameters:
    ///   - stub: The mock or map-local action that matched.
    ///   - url: The request's URL, used as the response's URL.
    ///   - bodyProvider: Resolves a stored body id to its bytes. Injected so the responder
    ///     performs no I/O of its own and stays testable.
    /// - Returns: The response and body, or `nil` when a mapped file cannot be read — in which
    ///   case the caller performs the request normally rather than failing it.
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
            let fileURL = URL(fileURLWithPath: file.relativePath)
            guard let body = try? Data(contentsOf: fileURL) else { return nil }
            var headers: [String: String] = [:]
            if let contentType = file.contentType { headers["Content-Type"] = contentType }
            guard let response = HTTPURLResponse(
                url: url, statusCode: file.statusCode, httpVersion: "HTTP/1.1", headerFields: headers
            ) else { return nil }
            return (response, body)
        }
    }
}
