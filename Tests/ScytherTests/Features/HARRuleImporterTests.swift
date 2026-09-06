//
//  HARRuleImporterTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class HARRuleImporterTests: XCTestCase {

    private let har = """
    {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
      {"startedDateTime":"2026-09-05T00:00:00.000Z","time":12,
       "request":{"method":"get","url":"https://api.example.com/v1/users?page=2","httpVersion":"HTTP/1.1",
                  "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
       "response":{"status":200,"statusText":"no error","httpVersion":"HTTP/1.1","cookies":[],
                   "headers":[{"name":"Content-Type","value":"application/json"}],
                   "content":{"size":2,"mimeType":"application/json","text":"[]"},
                   "redirectURL":"","headersSize":-1,"bodySize":2},
       "cache":{},"timings":{"send":0,"wait":12,"receive":0}}
    ]}}
    """

    /// The bytes an imported rule is carrying for the store to write, if any.
    private func pendingBody(of rule: NetworkRule) -> Data? {
        guard case .mock(let mock) = rule.actions.stub else { return nil }
        return mock.pendingBody
    }

    func testEachEntryBecomesOneDisabledMockRule() throws {
        let result = try HARRuleImporter.result(from: Data(har.utf8))

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.skippedEntries, 0)
        let rule = try XCTUnwrap(result.rules.first)
        XCTAssertFalse(rule.isEnabled, "imported rules arrive disabled so an import cannot change behaviour")
        XCTAssertEqual(rule.name, "GET /v1/users", "a lowercase HAR method must be uppercased in the rule name")
        XCTAssertEqual(rule.match.methods, ["GET"], "a lowercase HAR method must be uppercased in the match")
        XCTAssertEqual(rule.match.host?.value, "api.example.com")
        XCTAssertEqual(rule.match.path?.value, "/v1/users")
        guard case .mock(let mock) = rule.actions.stub else { return XCTFail("expected a mock action") }
        XCTAssertEqual(mock.statusCode, 200)
        XCTAssertEqual(mock.headers["Content-Type"], "application/json")
        XCTAssertNil(mock.bodyID, "the body has not been written yet, so there is no identifier to point at")
        XCTAssertEqual(mock.pendingBody, Data("[]".utf8))
    }

    func testAnEntryWithNoBodyCarriesNoBytes() throws {
        let noBody = har.replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":null")
        let result = try HARRuleImporter.result(from: Data(noBody.utf8))
        XCTAssertNil(pendingBody(of: try XCTUnwrap(result.rules.first)))
    }

    func testBase64ContentIsDecodedBeforeItTravelsWithTheRule() throws {
        let encoded = Data("binary".utf8).base64EncodedString()
        let base64 = har
            .replacingOccurrences(of: "\"size\":2", with: "\"size\":6")
            .replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":\"\(encoded)\",\"encoding\":\"base64\"")
        let result = try HARRuleImporter.result(from: Data(base64.utf8))
        XCTAssertEqual(pendingBody(of: try XCTUnwrap(result.rules.first)), Data("binary".utf8))
    }

    /// Classic MIME base64 is wrapped, and Scyther's own exporter wraps image bodies at 64
    /// columns. Decoding with the default options rejects every one of those, and the body was
    /// dropped in silence while the override was still created and still counted.
    func testWrappedBase64IsStillDecoded() throws {
        let bytes = Data((0..<200).map { UInt8($0 % 251) })
        let wrapped = bytes.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        XCTAssertTrue(wrapped.contains("\n"), "this test is only meaningful with a wrapped string")
        let document = har
            .replacingOccurrences(of: "\"size\":2", with: "\"size\":200")
            .replacingOccurrences(
                of: "\"text\":\"[]\"",
                with: "\"text\":\"\(wrapped.replacingOccurrences(of: "\n", with: "\\n"))\",\"encoding\":\"base64\""
            )
        let result = try HARRuleImporter.result(from: Data(document.utf8))
        XCTAssertEqual(pendingBody(of: try XCTUnwrap(result.rules.first)), bytes)
    }

    /// `encoding: "base64"` is a claim, not a fact. Text that cannot be base64 is taken as the
    /// literal body it plainly is rather than decoded into garbage or dropped.
    func testTextMislabelledAsBase64IsTakenLiterally() throws {
        let document = har.replacingOccurrences(
            of: "\"text\":\"[]\"",
            with: "\"text\":\"{\\\"ok\\\":true}\",\"encoding\":\"base64\""
        )
        let result = try HARRuleImporter.result(from: Data(document.utf8))
        XCTAssertEqual(pendingBody(of: try XCTUnwrap(result.rules.first)), Data("{\"ok\":true}".utf8))
    }

    /// Short text can be base64-shaped by accident — `test` is four characters of the alphabet —
    /// and decoding it yields three bytes of nonsense. The declared size settles it: it is the
    /// length of the literal, so the literal is what the entry meant.
    func testBase64ShapedTextIsTakenLiterallyWhenTheDeclaredSizeSaysSo() throws {
        let document = har
            .replacingOccurrences(of: "\"size\":2", with: "\"size\":4")
            .replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":\"test\",\"encoding\":\"base64\"")
        let result = try HARRuleImporter.result(from: Data(document.utf8))
        XCTAssertEqual(pendingBody(of: try XCTUnwrap(result.rules.first)), Data("test".utf8))
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try HARRuleImporter.result(from: Data("not json".utf8)))
    }

    func testADocumentWithNoEntriesAtAllThrows() {
        XCTAssertThrowsError(try HARRuleImporter.result(from: Data(#"{"log":{"version":"1.2"}}"#.utf8)))
    }

    func testEntryWithUnparseableURLIsSkippedButItsSiblingSurvives() throws {
        let twoEntries = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"http://exa mple.com/bad","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}},
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/ok","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(twoEntries.utf8))
        XCTAssertEqual(result.rules.count, 1, "the entry with an unparseable URL must be skipped, not the whole import")
        XCTAssertEqual(result.skippedEntries, 1)
        XCTAssertEqual(result.rules.first?.match.path?.value, "/v1/ok")
    }

    /// An aborted request has no response at all. Decoding the document in one call meant that
    /// one entry threw and the import produced nothing whatsoever.
    func testAnEntryWithNoResponseIsSkippedButItsSiblingSurvives() throws {
        let twoEntries = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/aborted","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}},
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/ok","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(twoEntries.utf8))
        XCTAssertEqual(result.rules.count, 1, "one entry with no response must not discard the other")
        XCTAssertEqual(result.skippedEntries, 1)
        XCTAssertEqual(result.rules.first?.match.path?.value, "/v1/ok")
    }

    /// A structurally malformed entry — here a `time` that is not a number — costs that entry
    /// and nothing else.
    func testAnEntryOfTheWrongShapeIsSkippedButItsSiblingSurvives() throws {
        let twoEntries = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":"a while",
           "request":{"method":"GET","url":"https://api.example.com/v1/odd","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}},
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/ok","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(twoEntries.utf8))
        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.skippedEntries, 1)
        XCTAssertEqual(result.rules.first?.match.path?.value, "/v1/ok")
    }

    /// A multipart upload as Chrome DevTools exports it: `postData` carries `params` and no
    /// `text` at all. The entry is complete and its response is perfectly importable.
    func testAMultipartEntryWhosePostDataHasParamsAndNoTextIsStillImported() throws {
        let multipart = """
        {"log":{"version":"1.2","creator":{"name":"Chrome DevTools","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"POST","url":"https://api.example.com/v1/upload","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],
                      "postData":{"mimeType":"multipart/form-data; boundary=x",
                                  "params":[{"name":"file","fileName":"a.png","contentType":"image/png"}]},
                      "headersSize":-1,"bodySize":1024},
           "response":{"status":201,"statusText":"Created","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":2,"mimeType":"application/json","text":"{}"},
                       "redirectURL":"","headersSize":-1,"bodySize":2},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(multipart.utf8))
        XCTAssertEqual(result.rules.count, 1, "a request body Scyther never reads must not fail the entry")
        XCTAssertEqual(result.skippedEntries, 0)
        XCTAssertEqual(result.rules.first?.name, "POST /v1/upload")
        XCTAssertEqual(pendingBody(of: try XCTUnwrap(result.rules.first)), Data("{}".utf8))
    }

    func testRepeatedResponseHeaderNameKeepsTheLastValue() throws {
        let repeatedHeader = har.replacingOccurrences(
            of: "\"headers\":[{\"name\":\"Content-Type\",\"value\":\"application/json\"}]",
            with: "\"headers\":[{\"name\":\"X-Cache\",\"value\":\"HIT\"},{\"name\":\"X-Cache\",\"value\":\"MISS\"}]"
        )
        let result = try HARRuleImporter.result(from: Data(repeatedHeader.utf8))
        guard case .mock(let mock) = try XCTUnwrap(result.rules.first).actions.stub else {
            return XCTFail("expected a mock")
        }
        XCTAssertEqual(mock.headers["X-Cache"], "MISS")
    }

    func testURLWithNoPathIsNormalisedToRoot() throws {
        let noPath = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(noPath.utf8))
        let rule = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(rule.name, "GET /", "an empty path must be normalised to \"/\", not left as a trailing space")
        XCTAssertEqual(rule.match.path?.value, "/")
    }

    /// A captured path keeps its escaped separator: `%2F` is one segment on the wire, and that is
    /// what ``NetworkRuleMatch/matches(_:)`` compares against.
    func testAnEncodedPathIsImportedEncoded() throws {
        let encodedPath = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/a%2Fb","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let result = try HARRuleImporter.result(from: Data(encodedPath.utf8))
        let rule = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(rule.match.path?.value, "/v1/a%2Fb")
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/a%2Fb")!)
        request.httpMethod = "GET"
        XCTAssertTrue(rule.match.matches(request), "an imported override must match the request it was built from")
    }
}
