//
//  NetworkLogExporterTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkLogExporterTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkLogExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func makeRequest(url: String, method: String = "GET", body: String? = nil) -> HTTPRequest {
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        if let body {
            mutable.setValue("application/json", forHTTPHeaderField: "Content-Type")
            URLProtocol.setProperty(Data(body.utf8), forKey: "ScytherBodyData", in: mutable)
        }
        let urlRequest = mutable as URLRequest
        let request = HTTPRequest()
        request.saveRequest(urlRequest)
        request.saveRequestBody(urlRequest)
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        request.saveResponse(response, data: Data("{\"ok\":true}".utf8))
        return request
    }

    func testArchiveNameUsesHostAppNameAndTimestamp() {
        let now = Date(timeIntervalSince1970: 0)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(
            NetworkLogExporter.archiveName(now: now, timeZone: utc, appName: "Scyther Example"),
            "Scyther-Example-Network-Log-1970-01-01-000000"
        )
        XCTAssertEqual(
            NetworkLogExporter.archiveName(now: now, timeZone: utc, appName: "My/App: v2"),
            "My_App_-v2-Network-Log-1970-01-01-000000"
        )
        XCTAssertEqual(
            NetworkLogExporter.archiveName(now: now, timeZone: utc, appName: "   "),
            "App-Network-Log-1970-01-01-000000"
        )
    }

    func testDefaultAppNameComesFromHostBundle() {
        let expected = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
        XCTAssertEqual(NetworkLogExporter.hostAppName, expected)
    }

    func testFolderNameIsIndexedAndFilesystemSafe() {
        let request = makeRequest(url: "https://api.example.com/users/1?x=y", method: "DELETE")
        XCTAssertEqual(NetworkLogExporter.folderName(index: 3, request: request), "003-DELETE-api.example.com")
    }

    func testWriteArchiveDirectoryLaysOutHARAndPerRequestFolders() throws {
        let requests = [
            makeRequest(url: "https://api.example.com/a", method: "POST", body: "{\"k\":1}"),
            makeRequest(url: "https://cdn.example.com/b"),
        ]
        let root = try NetworkLogExporter.writeArchiveDirectory(for: requests, in: scratch, name: "archive")
        let fm = FileManager.default

        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("network-log.har").path))
        let first = root.appendingPathComponent("requests/001-POST-api.example.com")
        XCTAssertTrue(fm.fileExists(atPath: first.appendingPathComponent("request.curl").path))
        XCTAssertTrue(fm.fileExists(atPath: first.appendingPathComponent("request-body.json").path))
        XCTAssertTrue(fm.fileExists(atPath: first.appendingPathComponent("response-body.json").path))
        XCTAssertEqual(
            try String(contentsOf: first.appendingPathComponent("request-body.json"), encoding: .utf8),
            "{\"k\":1}"
        )

        let second = root.appendingPathComponent("requests/002-GET-cdn.example.com")
        XCTAssertTrue(fm.fileExists(atPath: second.appendingPathComponent("request.curl").path))
        XCTAssertFalse(fm.fileExists(atPath: second.appendingPathComponent("request-body.json").path))
    }

    func testExportProducesZipFile() throws {
        let zip = try NetworkLogExporter.export([makeRequest(url: "https://api.example.com/a")], in: scratch)
        XCTAssertEqual(zip.pathExtension, "zip")
        XCTAssertTrue(zip.lastPathComponent.contains("-Network-Log-"))
        let data = try Data(contentsOf: zip)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]), "expected zip magic bytes")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: zip.deletingPathExtension().path),
            "staging directory should be removed after zipping"
        )
    }

    func testRedactedExportScrubsHARBodiesAndCurl() throws {
        let mutable = NSMutableURLRequest(url: URL(string: "https://api.example.com/login?token=abc")!)
        mutable.httpMethod = "POST"
        mutable.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutable.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
        URLProtocol.setProperty(Data(#"{"password":"hunter2"}"#.utf8), forKey: "ScytherBodyData", in: mutable)
        let urlRequest = mutable as URLRequest
        let request = HTTPRequest()
        request.saveRequest(urlRequest)
        request.saveRequestBody(urlRequest)
        let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        request.saveResponse(response, data: Data(#"{"access_token":"tok"}"#.utf8))

        let root = try NetworkLogExporter.writeArchiveDirectory(for: [request], in: scratch, name: "redacted", redact: true)
        let har = try String(contentsOf: root.appendingPathComponent("network-log.har"), encoding: .utf8)
        XCTAssertFalse(har.contains("secret-token"))
        XCTAssertFalse(har.contains("hunter2"))
        XCTAssertFalse(har.contains("\"tok\""))
        XCTAssertFalse(har.contains("token=abc"))
        XCTAssertTrue(har.contains(NetworkLogRedactor.harComment))

        let folder = root.appendingPathComponent("requests/001-POST-api.example.com")
        let curl = try String(contentsOf: folder.appendingPathComponent("request.curl"), encoding: .utf8)
        XCTAssertFalse(curl.contains("secret-token"))
        XCTAssertFalse(curl.contains("token=abc"))
        let requestBody = try String(contentsOf: folder.appendingPathComponent("request-body.json"), encoding: .utf8)
        XCTAssertEqual(requestBody, #"{"password":"REDACTED"}"#)
        let responseBody = try String(contentsOf: folder.appendingPathComponent("response-body.json"), encoding: .utf8)
        XCTAssertEqual(responseBody, #"{"access_token":"REDACTED"}"#)

        let raw = try NetworkLogExporter.writeArchiveDirectory(for: [request], in: scratch, name: "raw", redact: false)
        let rawHar = try String(contentsOf: raw.appendingPathComponent("network-log.har"), encoding: .utf8)
        XCTAssertTrue(rawHar.contains("secret-token"))
    }

    func testExportRefusesEmptyList() {
        XCTAssertThrowsError(try NetworkLogExporter.export([], in: scratch)) { error in
            XCTAssertEqual(error as? NetworkLogExporter.ExportError, .nothingToExport)
        }
    }
}
