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

    func testEachEntryBecomesOneDisabledMockRule() throws {
        var stored: [Data] = []
        let rules = try HARRuleImporter.rules(from: Data(har.utf8)) { data in
            stored.append(data)
            return UUID()
        }

        XCTAssertEqual(rules.count, 1)
        let rule = try XCTUnwrap(rules.first)
        XCTAssertFalse(rule.isEnabled, "imported rules arrive disabled so an import cannot change behaviour")
        XCTAssertEqual(rule.name, "GET /v1/users", "a lowercase HAR method must be uppercased in the rule name")
        XCTAssertEqual(rule.match.methods, ["GET"], "a lowercase HAR method must be uppercased in the match")
        XCTAssertEqual(rule.match.host?.value, "api.example.com")
        XCTAssertEqual(rule.match.path?.value, "/v1/users")
        guard case .mock(let mock) = rule.actions.stub else { return XCTFail("expected a mock action") }
        XCTAssertEqual(mock.statusCode, 200)
        XCTAssertEqual(mock.headers["Content-Type"], "application/json")
        XCTAssertNotNil(mock.bodyID)
        XCTAssertEqual(stored, [Data("[]".utf8)])
    }

    func testAnEntryWithNoBodyStoresNothing() throws {
        let noBody = har.replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":null")
        var stored: [Data] = []
        let rules = try HARRuleImporter.rules(from: Data(noBody.utf8)) { data in
            stored.append(data); return UUID()
        }
        guard case .mock(let mock) = try XCTUnwrap(rules.first).actions.stub else { return XCTFail("expected a mock") }
        XCTAssertNil(mock.bodyID)
        XCTAssertTrue(stored.isEmpty)
    }

    func testBase64ContentIsDecodedBeforeStorage() throws {
        let encoded = Data("binary".utf8).base64EncodedString()
        let base64 = har
            .replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":\"\(encoded)\",\"encoding\":\"base64\"")
        var stored: [Data] = []
        _ = try HARRuleImporter.rules(from: Data(base64.utf8)) { data in stored.append(data); return UUID() }
        XCTAssertEqual(stored, [Data("binary".utf8)])
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try HARRuleImporter.rules(from: Data("not json".utf8)) { _ in UUID() })
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
        let rules = try HARRuleImporter.rules(from: Data(twoEntries.utf8)) { _ in UUID() }
        XCTAssertEqual(rules.count, 1, "the entry with an unparseable URL must be skipped, not the whole import")
        XCTAssertEqual(rules.first?.match.path?.value, "/v1/ok")
    }

    func testRepeatedResponseHeaderNameKeepsTheLastValue() throws {
        let repeatedHeader = har.replacingOccurrences(
            of: "\"headers\":[{\"name\":\"Content-Type\",\"value\":\"application/json\"}]",
            with: "\"headers\":[{\"name\":\"X-Cache\",\"value\":\"HIT\"},{\"name\":\"X-Cache\",\"value\":\"MISS\"}]"
        )
        let rules = try HARRuleImporter.rules(from: Data(repeatedHeader.utf8)) { _ in UUID() }
        guard case .mock(let mock) = try XCTUnwrap(rules.first).actions.stub else { return XCTFail("expected a mock") }
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
        let rules = try HARRuleImporter.rules(from: Data(noPath.utf8)) { _ in UUID() }
        let rule = try XCTUnwrap(rules.first)
        XCTAssertEqual(rule.name, "GET /", "an empty path must be normalised to \"/\", not left as a trailing space")
        XCTAssertEqual(rule.match.path?.value, "/")
    }
}
