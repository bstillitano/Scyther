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
       "request":{"method":"GET","url":"https://api.example.com/v1/users?page=2","httpVersion":"HTTP/1.1",
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
        XCTAssertEqual(rule.name, "GET /v1/users")
        XCTAssertEqual(rule.match.methods, ["GET"])
        XCTAssertEqual(rule.match.host?.value, "api.example.com")
        XCTAssertEqual(rule.match.path?.value, "/v1/users")
        guard case .mock(let mock) = rule.action else { return XCTFail("expected a mock action") }
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
        guard case .mock(let mock) = try XCTUnwrap(rules.first).action else { return XCTFail("expected a mock") }
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
}
