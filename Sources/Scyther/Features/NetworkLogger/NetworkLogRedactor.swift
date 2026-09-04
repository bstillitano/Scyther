//
//  NetworkLogRedactor.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// Best-effort scrubbing of secrets from an exported network log.
///
/// Replaces values with `REDACTED` when their header name, query parameter, JSON key, or form
/// field looks sensitive (authorization, tokens, cookies, passwords, API keys, sessions), and
/// replaces `Bearer` credentials and JWT-shaped strings wherever they appear in text.
///
/// This is an attempt, not a guarantee: secrets under unusual names, inside binary bodies, or in
/// formats the patterns do not cover will pass through untouched.
///
/// ## Usage
///
/// ```swift
/// let safeHAR = NetworkLogRedactor.redact(har)
/// let safeCurl = NetworkLogRedactor.redactCurl(curl)
/// ```
enum NetworkLogRedactor {
    /// The replacement written in place of a redacted value.
    static let placeholder = "REDACTED"

    /// The `log.comment` written into a redacted HAR document.
    static let harComment = "Sensitive values replaced with REDACTED by Scyther. Best effort only, not a guarantee of privacy."

    /// Whole words that mark a name as sensitive, matched after splitting on separators and camel case.
    private static let sensitiveWords: Set<String> = [
        "authorization", "auth", "token", "secret", "password", "passwd", "pwd", "cookie", "session",
        "signature", "credential", "credentials", "bearer", "jwt", "otp", "csrf", "xsrf", "apikey",
    ]

    /// Substrings that mark a name as sensitive after separators are removed, e.g. `x-api-key`.
    private static let sensitiveFragments = ["apikey", "token", "secret", "password", "cookie", "session"]

    // MARK: - Names

    /// Whether a header, query, JSON, or form name should have its value redacted.
    ///
    /// - Parameter name: The name to test, in any casing or separator style.
    static func isSensitiveName(_ name: String) -> Bool {
        let words = Set(splitWords(name))
        if !words.isDisjoint(with: sensitiveWords) { return true }
        let compact = name.lowercased().filter(\.isLetter)
        return sensitiveFragments.contains { compact.contains($0) }
    }

    private static func splitWords(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in name {
            if character.isLetter || character.isNumber {
                if character.isUppercase, previousWasLower, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(character.lowercased())
                previousWasLower = character.isLowercase
            } else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLower = false
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: - Structured values

    /// Redacts the values of any sensitively named pairs.
    ///
    /// - Parameter pairs: Header or query pairs.
    static func redact(_ pairs: [HARNameValue]) -> [HARNameValue] {
        pairs.map { isSensitiveName($0.name) ? HARNameValue(name: $0.name, value: placeholder) : $0 }
    }

    /// Redacts sensitively named query parameters in a URL string.
    ///
    /// - Parameter url: The URL to scrub. Returned unchanged if it cannot be parsed.
    static func redactURL(_ url: String) -> String {
        guard var components = URLComponents(string: url),
              let items = components.queryItems, !items.isEmpty else { return url }
        components.queryItems = items.map {
            isSensitiveName($0.name) ? URLQueryItem(name: $0.name, value: placeholder) : $0
        }
        return components.string ?? url
    }

    /// Redacts response content unless it is base64 encoded binary.
    ///
    /// - Parameter content: The content to scrub.
    static func redact(_ content: HARContent) -> HARContent {
        guard content.encoding == nil, let text = content.text else { return content }
        return HARContent(size: content.size, mimeType: content.mimeType, text: redactText(text), encoding: nil)
    }

    /// Redacts every field of a HAR document and stamps ``harComment`` on the log.
    ///
    /// - Parameter log: The document to scrub.
    static func redact(_ log: HARLog) -> HARLog {
        HARLog(log: HARLogBody(
            version: log.log.version,
            creator: log.log.creator,
            comment: harComment,
            entries: log.log.entries.map(redact(_:))
        ))
    }

    private static func redact(_ entry: HAREntry) -> HAREntry {
        let request = HARRequest(
            method: entry.request.method,
            url: redactURL(entry.request.url),
            httpVersion: entry.request.httpVersion,
            cookies: entry.request.cookies.map { HARCookie(name: $0.name, value: placeholder) },
            headers: redact(entry.request.headers),
            queryString: redact(entry.request.queryString),
            postData: entry.request.postData.map { HARPostData(mimeType: $0.mimeType, text: redactText($0.text)) },
            headersSize: entry.request.headersSize,
            bodySize: entry.request.bodySize
        )
        let response = HARResponse(
            status: entry.response.status,
            statusText: entry.response.statusText,
            httpVersion: entry.response.httpVersion,
            cookies: entry.response.cookies.map { HARCookie(name: $0.name, value: placeholder) },
            headers: redact(entry.response.headers),
            content: redact(entry.response.content),
            redirectURL: redactURL(entry.response.redirectURL),
            headersSize: entry.response.headersSize,
            bodySize: entry.response.bodySize
        )
        return HAREntry(
            startedDateTime: entry.startedDateTime,
            time: entry.time,
            request: request,
            response: response,
            cache: entry.cache,
            timings: entry.timings
        )
    }

    // MARK: - Free text

    private static let jsonPairPattern = try! NSRegularExpression(
        pattern: #""((?:[^"\\]|\\.)+)"(\s*:\s*)("(?:[^"\\]|\\.)*"|[^,}\]\s"{\[]+)"#
    )
    private static let formPairPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_\-\.\[\]])([A-Za-z0-9_\-\.\[\]]+)=([^&\s'"]+)"#
    )
    private static let bearerPattern = try! NSRegularExpression(
        pattern: #"(?i)\bBearer\s+[A-Za-z0-9\-._~+/]+=*"#
    )
    private static let jwtPattern = try! NSRegularExpression(
        pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
    )

    /// Redacts sensitively keyed JSON and form values, `Bearer` credentials, and JWTs in text.
    ///
    /// - Parameter text: A body, log line, or command to scrub.
    static func redactText(_ text: String) -> String {
        var output = replace(jsonPairPattern, in: text) { match, source in
            let key = source.substring(match.range(at: 1))
            guard isSensitiveName(key) else { return nil }
            return "\"\(key)\"\(source.substring(match.range(at: 2)))\"\(placeholder)\""
        }
        output = replace(formPairPattern, in: output) { match, source in
            let key = source.substring(match.range(at: 1))
            guard isSensitiveName(key) else { return nil }
            return "\(key)=\(placeholder)"
        }
        output = replace(bearerPattern, in: output) { _, _ in "Bearer \(placeholder)" }
        output = replace(jwtPattern, in: output) { _, _ in placeholder }
        return output
    }

    private static let curlSingleQuotedHeader = try! NSRegularExpression(pattern: #"-H '([^:']+):\s*([^']*)'"#)
    private static let curlDoubleQuotedHeader = try! NSRegularExpression(pattern: #"-H "([^:"]+):\s*([^"]*)""#)
    private static let quotedURLPattern = try! NSRegularExpression(pattern: #"(['"])(https?://[^'"]+)\1"#)

    /// Redacts sensitive headers, query parameters, and body values in a cURL command.
    ///
    /// - Parameter curl: The command to scrub.
    static func redactCurl(_ curl: String) -> String {
        var output = replace(curlSingleQuotedHeader, in: curl) { match, source in
            let name = source.substring(match.range(at: 1))
            guard isSensitiveName(name) else { return nil }
            return "-H '\(name): \(placeholder)'"
        }
        output = replace(curlDoubleQuotedHeader, in: output) { match, source in
            let name = source.substring(match.range(at: 1))
            guard isSensitiveName(name) else { return nil }
            return "-H \"\(name): \(placeholder)\""
        }
        output = replace(quotedURLPattern, in: output) { match, source in
            let quote = source.substring(match.range(at: 1))
            return quote + redactURL(source.substring(match.range(at: 2))) + quote
        }
        return redactText(output)
    }

    /// Applies `replacement` to each match, right to left so ranges stay valid. A `nil` result leaves the match as is.
    private static func replace(
        _ regex: NSRegularExpression,
        in text: String,
        with replacement: (NSTextCheckingResult, NSString) -> String?
    ) -> String {
        let source = text as NSString
        var output = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let value = replacement(match, source),
                  let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: value)
        }
        return output
    }
}

private extension NSString {
    func substring(_ range: NSRange) -> String {
        range.location == NSNotFound ? "" : substring(with: range)
    }
}
