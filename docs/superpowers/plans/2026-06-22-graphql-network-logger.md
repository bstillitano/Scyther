# GraphQL Network Logger + Request-Body Button Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface GraphQL operation name/type in the network logger list, details view, and search; and fix the Request Body section so it offers the same tinted "Browse"/"View" links as the Response Body section.

**Architecture:** A new pure `GraphQLOperation` value type parses a request body once at capture time inside `HTTPRequest.saveRequestBody(_:)`; lightweight results (`isGraphQL`, name, type) are cached on `HTTPRequest` so the list and search never read the body from disk. View models expose these fields; the list row uses the "operation name + trailing type lozenge" layout (brainstorming Option B), and the details view gains a GraphQL section plus a fixed Request Body section.

**Tech Stack:** Swift 6, SwiftUI, UIKit, XCTest. iOS only.

## Global Constraints

- iOS only. Build/test on the booted iOS Simulator (fallback: `iPhone 17 Pro`).
- Build command: `xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Test command: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- MVVM + Repository. Separate view-model files. One responsibility per file (SoC).
- Tests live under `Tests/ScytherTests/...` using XCTest and `@testable import Scyther`.
- DocC comments on every new public/internal type, property, and method.
- Use SwiftUI built-ins; no custom share sheets; alerts not tooltip dialogs (not relevant here but keep in mind).
- Status/accent colour is driven ONLY by response code, never by HTTP method — do not change this.
- Detection scope: POST JSON request bodies only. GraphQL-over-GET / persisted queries are out of scope.
- Work happens on branch `feature/graphql-network-logger` (already created).

---

## File Structure

New:
- `Sources/Scyther/Features/NetworkLogger/GraphQLOperation.swift` — pure parser + types.
- `Tests/ScytherTests/Features/GraphQLOperationTests.swift` — parser unit tests.

Modified:
- `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift` — cached GraphQL props; parse in `saveRequestBody`; `getRequestBodyDictionary()`; `getGraphQLVariablesDictionary()`.
- `Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift` — `HTTPRequestViewModel` GraphQL fields + `HTTPRequestView` Option B layout.
- `Sources/Scyther/Features/NetworkLogger/NetworkLogsViewModel.swift` — search predicate.
- `Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift` — searchable prompt.
- `Sources/Scyther/Features/NetworkLogger/LogDetailsViewModel.swift` — GraphQL + request-body-dictionary members.
- `Sources/Scyther/Features/NetworkLogger/LogDetailsView.swift` — `graphQLSection`; fixed `requestBodySection`.
- `Tests/ScytherTests/Features/HTTPRequestTests.swift` — caching tests.
- `README.md`.

---

## Task 1: `GraphQLOperation` parser

**Files:**
- Create: `Sources/Scyther/Features/NetworkLogger/GraphQLOperation.swift`
- Test: `Tests/ScytherTests/Features/GraphQLOperationTests.swift`

**Interfaces:**
- Consumes: nothing (pure `Foundation`).
- Produces:
  - `enum GraphQLOperationType: String, Sendable { case query, mutation, subscription }` with `var displayName: String` (capitalised) and `var badgeText: String` (uppercased).
  - `struct GraphQLOperation: Sendable` with `let operationName: String`, `let type: GraphQLOperationType?`, `let isBatch: Bool`, `let batchCount: Int`, `let variables: [String: Any]?`.
  - `static func parse(body data: Data?, url: String?) -> GraphQLOperation?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/GraphQLOperationTests.swift`:

```swift
//
//  GraphQLOperationTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class GraphQLOperationTests: XCTestCase {

    private func body(_ string: String) -> Data { string.data(using: .utf8)! }

    // MARK: - Detection

    func testNamedQueryByBodyShape() {
        let data = body(#"{"operationName":"GetUser","query":"query GetUser { me { id } }","variables":{"id":"1"}}"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/v1")
        XCTAssertNotNil(op)
        XCTAssertEqual(op?.operationName, "GetUser")
        XCTAssertEqual(op?.type, .query)
        XCTAssertFalse(op?.isBatch ?? true)
        XCTAssertEqual(op?.variables?["id"] as? String, "1")
    }

    func testOperationNameFieldTakesPrecedenceOverDocumentName() {
        let data = body(#"{"operationName":"Explicit","query":"query Document { a }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.operationName, "Explicit")
    }

    func testNameParsedFromDocumentWhenNoOperationNameField() {
        let data = body(#"{"query":"mutation UpdateAvatar($f:Upload!) { upload(f:$f) }"}"#)
        let op = GraphQLOperation.parse(body: data, url: nil)
        XCTAssertEqual(op?.operationName, "UpdateAvatar")
        XCTAssertEqual(op?.type, .mutation)
    }

    func testSubscriptionType() {
        let data = body(#"{"query":"subscription OnPing { ping }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.type, .subscription)
    }

    func testAnonymousShorthandQuery() {
        let data = body(#"{"query":"{ me { id } }"}"#)
        let op = GraphQLOperation.parse(body: data, url: nil)
        XCTAssertEqual(op?.operationName, "(anonymous)")
        XCTAssertEqual(op?.type, .query)
    }

    func testNamedQueryKeywordButNoName() {
        let data = body(#"{"query":"query { me { id } }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.operationName, "(anonymous)")
    }

    func testPathHintDetectsWhenNoQueryField() {
        // No "query" field, but the path says graphql and the body is JSON.
        let data = body(#"{"persistedQuery":{"sha256Hash":"abc"}}"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/graphql")
        XCTAssertNotNil(op)
        XCTAssertEqual(op?.operationName, "(anonymous)")
    }

    func testBatchedOperations() {
        let data = body(#"[{"query":"query A { a }"},{"query":"query B { b }"}]"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/graphql")
        XCTAssertEqual(op?.isBatch, true)
        XCTAssertEqual(op?.batchCount, 2)
        XCTAssertEqual(op?.operationName, "Batch (2 operations)")
        XCTAssertNil(op?.type)
    }

    // MARK: - Negative

    func testRestJSONIsNotGraphQL() {
        let data = body(#"{"name":"John","age":30}"#)
        XCTAssertNil(GraphQLOperation.parse(body: data, url: "https://api.example.com/users"))
    }

    func testNonJSONIsNotGraphQL() {
        XCTAssertNil(GraphQLOperation.parse(body: body("not json"), url: "https://api.example.com/x"))
    }

    func testEmptyBodyIsNotGraphQL() {
        XCTAssertNil(GraphQLOperation.parse(body: Data(), url: "https://api.example.com/x"))
        XCTAssertNil(GraphQLOperation.parse(body: nil, url: "https://api.example.com/x"))
    }

    // MARK: - Display helpers

    func testTypeDisplayHelpers() {
        XCTAssertEqual(GraphQLOperationType.query.displayName, "Query")
        XCTAssertEqual(GraphQLOperationType.mutation.badgeText, "MUTATION")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/GraphQLOperationTests`
Expected: FAIL — `cannot find 'GraphQLOperation' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/NetworkLogger/GraphQLOperation.swift`:

```swift
//
//  GraphQLOperation.swift
//  Scyther
//

import Foundation

/// The kind of a GraphQL operation as declared by the leading keyword of its document.
enum GraphQLOperationType: String, Sendable {
    case query
    case mutation
    case subscription

    /// A capitalised label suitable for detail rows, e.g. "Query".
    var displayName: String { rawValue.capitalized }

    /// An uppercased label suitable for a list-row lozenge, e.g. "QUERY".
    var badgeText: String { rawValue.uppercased() }
}

/// A parsed representation of a GraphQL request body.
///
/// Use ``parse(body:url:)`` to interpret a request body. The parser is pure: it performs
/// no disk or network access and is safe to call on any thread.
struct GraphQLOperation: Sendable {
    /// The resolved operation name. `"(anonymous)"` when the document has no name, or
    /// `"Batch (N operations)"` for batched requests.
    let operationName: String

    /// The operation type, or `nil` for batched requests.
    let type: GraphQLOperationType?

    /// Whether the request is a batched array of operations.
    let isBatch: Bool

    /// The number of operations (1 for a single operation).
    let batchCount: Int

    /// The raw `variables` object, if present, for structured browsing.
    let variables: [String: Any]?

    /// Parses `data` as a GraphQL request body.
    ///
    /// A request is treated as GraphQL when the JSON body contains a `query` string field,
    /// or when `url`'s path contains `graphql`/`gql` and the body is JSON.
    ///
    /// - Parameters:
    ///   - data: The raw request body.
    ///   - url: The request URL string, used for the path heuristic.
    /// - Returns: A parsed operation, or `nil` if the body is not GraphQL.
    static func parse(body data: Data?, url: String?) -> GraphQLOperation? {
        guard let data, !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let pathHint = urlHasGraphQLHint(url)

        // Batched operations: an array of operation objects.
        if let array = json as? [[String: Any]] {
            let queryCount = array.filter { $0["query"] is String }.count
            guard queryCount > 0 || pathHint else { return nil }
            let count = queryCount > 0 ? queryCount : array.count
            return GraphQLOperation(
                operationName: "Batch (\(count) operations)",
                type: nil,
                isBatch: true,
                batchCount: count,
                variables: nil
            )
        }

        // Single operation object.
        guard let object = json as? [String: Any] else { return nil }
        let query = object["query"] as? String
        guard query != nil || pathHint else { return nil }

        return GraphQLOperation(
            operationName: resolveName(explicit: object["operationName"] as? String, query: query),
            type: operationType(from: query),
            isBatch: false,
            batchCount: 1,
            variables: object["variables"] as? [String: Any]
        )
    }

    private static func urlHasGraphQLHint(_ url: String?) -> Bool {
        guard let url else { return false }
        let path = (URL(string: url)?.path ?? url).lowercased()
        return path.contains("graphql") || path.contains("gql")
    }

    private static func operationType(from query: String?) -> GraphQLOperationType? {
        guard let query else { return nil }
        switch firstKeyword(in: query) {
        case "mutation": return .mutation
        case "subscription": return .subscription
        default: return .query // explicit `query`, or shorthand `{ ... }`
        }
    }

    private static func resolveName(explicit: String?, query: String?) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let parsed = parsedName(from: query) { return parsed }
        return "(anonymous)"
    }

    /// The lowercased leading keyword of the document, or `nil` for shorthand `{ ... }`.
    private static func firstKeyword(in query: String) -> String? {
        let trimmed = query.drop(while: { $0.isWhitespace })
        if trimmed.first == "{" { return nil }
        let letters = trimmed.prefix(while: { $0.isLetter })
        return letters.isEmpty ? nil : String(letters).lowercased()
    }

    /// The operation name declared after the leading keyword, e.g. `GetUser`.
    private static func parsedName(from query: String?) -> String? {
        guard let query else { return nil }
        var scanner = query.drop(while: { $0.isWhitespace })
        let keyword = scanner.prefix(while: { $0.isLetter })
        if ["query", "mutation", "subscription"].contains(String(keyword).lowercased()) {
            scanner = scanner.dropFirst(keyword.count).drop(while: { $0.isWhitespace })
        } else if scanner.first == "{" {
            return nil
        }
        let nameChars = scanner.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
        return nameChars.isEmpty ? nil : String(nameChars)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/GraphQLOperationTests`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/GraphQLOperation.swift Tests/ScytherTests/Features/GraphQLOperationTests.swift
git commit -m "feat: add GraphQLOperation parser for network logger"
```

---

## Task 2: Cache GraphQL metadata on `HTTPRequest`

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift`
- Test: `Tests/ScytherTests/Features/HTTPRequestTests.swift`

**Interfaces:**
- Consumes: `GraphQLOperation.parse(body:url:)`, `GraphQLOperationType` (Task 1).
- Produces (on `HTTPRequest`):
  - `var isGraphQL: Bool`
  - `var graphQLOperationName: String?`
  - `var graphQLOperationType: GraphQLOperationType?`
  - `func getRequestBodyDictionary() -> [String: [String: Any]]`
  - `func getGraphQLVariablesDictionary() -> [String: [String: Any]]`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ScytherTests/Features/HTTPRequestTests.swift` (inside the class, after the existing `getResponseBodyDictionary` tests):

```swift
    // MARK: - GraphQL Caching Tests

    private func makeGraphQLRequest(url: String, body: String) -> HTTPRequest {
        let model = HTTPRequest()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        model.saveRequest(request)
        model.saveRequestBody(request)
        return model
    }

    func testSaveRequestBodyCachesGraphQLMetadata() {
        let model = makeGraphQLRequest(
            url: "https://api.example.com/graphql",
            body: #"{"operationName":"GetUser","query":"query GetUser { me { id } }"}"#
        )
        XCTAssertTrue(model.isGraphQL)
        XCTAssertEqual(model.graphQLOperationName, "GetUser")
        XCTAssertEqual(model.graphQLOperationType, .query)
    }

    func testSaveRequestBodyMarksNonGraphQL() {
        let model = makeGraphQLRequest(
            url: "https://api.example.com/users",
            body: #"{"name":"John"}"#
        )
        XCTAssertFalse(model.isGraphQL)
        XCTAssertNil(model.graphQLOperationName)
        XCTAssertNil(model.graphQLOperationType)
    }

    func testGraphQLVariablesDictionaryWrapsVariables() {
        let model = makeGraphQLRequest(
            url: "https://api.example.com/graphql",
            body: #"{"query":"query Q($id:ID!){ a }","variables":{"id":"42"}}"#
        )
        let dict = model.getGraphQLVariablesDictionary()
        XCTAssertEqual((dict["Variables"]?["id"]) as? String, "42")
    }

    func testRequestBodyDictionaryEmptyWhenNoBody() {
        let model = HTTPRequest()
        XCTAssertTrue(model.getRequestBodyDictionary().isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/HTTPRequestTests`
Expected: FAIL — `value of type 'HTTPRequest' has no member 'isGraphQL'`.

- [ ] **Step 3: Add the cached properties**

In `HTTPRequest.swift`, after the `noResponse` property (around line 121), add:

```swift
    /// Whether this request was detected as a GraphQL operation.
    var isGraphQL: Bool = false

    /// The resolved GraphQL operation name, if this is a GraphQL request.
    var graphQLOperationName: String?

    /// The GraphQL operation type, if known. `nil` for non-GraphQL or batched requests.
    var graphQLOperationType: GraphQLOperationType?
```

- [ ] **Step 4: Parse in `saveRequestBody`**

Replace the existing `saveRequestBody(_:)` (around lines 143-145) with:

```swift
    /// Saves the HTTP body of the given URL request to disk and caches any GraphQL metadata.
    /// - Parameter request: The `URLRequest` whose body will be saved.
    func saveRequestBody(_ request: URLRequest) {
        let bodyData = request.body
        saveRequestBodyData(bodyData)

        if let operation = GraphQLOperation.parse(body: bodyData, url: requestURL) {
            isGraphQL = true
            graphQLOperationName = operation.operationName
            graphQLOperationType = operation.type
        } else {
            isGraphQL = false
            graphQLOperationName = nil
            graphQLOperationType = nil
        }
    }
```

- [ ] **Step 5: Add the request-body dictionary helpers**

In `HTTPRequest.swift`, immediately after `getResponseBodyDictionary()` (around line 223), add:

```swift
    /// Retrieves the request body as a dictionary representation suitable for the data browser.
    /// - Returns: A dictionary containing the JSON request body, or an empty dictionary if unavailable or not JSON.
    func getRequestBodyDictionary() -> [String: [String: Any]] {
        guard let data = readRawData(getRequestBodyFilepath()) else { return [:] }
        let jsonString = prettyOutput(data, contentType: requestType)

        guard let json = jsonString.jsonRepresentation else { return [:] }

        if let dictionary = json as? [String: Any] {
            return ["JSON Body": dictionary]
        } else if let array = json as? [Any] {
            var indexedDict: [String: Any] = [:]
            for (index, element) in array.enumerated() {
                indexedDict["[\(index)]"] = element
            }
            return ["JSON Array (\(array.count) items)": indexedDict]
        }

        return [:]
    }

    /// Retrieves the GraphQL `variables` object as a browsable dictionary.
    /// - Returns: A dictionary keyed by `"Variables"`, or an empty dictionary if there are none.
    func getGraphQLVariablesDictionary() -> [String: [String: Any]] {
        guard let data = readRawData(getRequestBodyFilepath()),
              let operation = GraphQLOperation.parse(body: data, url: requestURL),
              let variables = operation.variables else {
            return [:]
        }
        return ["Variables": variables]
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/HTTPRequestTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift Tests/ScytherTests/Features/HTTPRequestTests.swift
git commit -m "feat: cache GraphQL metadata on HTTPRequest at capture time"
```

---

## Task 3: List row — `HTTPRequestViewModel` fields + Option B layout

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift`
- Test: `Tests/ScytherTests/Features/HTTPRequestViewModelTests.swift` (create)

**Interfaces:**
- Consumes: `HTTPRequest.isGraphQL`, `.graphQLOperationName`, `.graphQLOperationType`; `GraphQLOperationType` (Tasks 1-2).
- Produces (on `HTTPRequestViewModel`):
  - `var isGraphQL: Bool`
  - `var operationName: String`
  - `var operationBadgeText: String?`
  - `var operationBadgeColor: Color`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/HTTPRequestViewModelTests.swift`:

```swift
//
//  HTTPRequestViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import XCTest

@MainActor
final class HTTPRequestViewModelTests: XCTestCase {

    func testGraphQLFieldsExposed() {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationName = "GetUser"
        request.graphQLOperationType = .query

        let viewModel = HTTPRequestViewModel(request: request)
        XCTAssertTrue(viewModel.isGraphQL)
        XCTAssertEqual(viewModel.operationName, "GetUser")
        XCTAssertEqual(viewModel.operationBadgeText, "QUERY")
        XCTAssertEqual(viewModel.operationBadgeColor, .green)
    }

    func testMutationBadgeColor() {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationType = .mutation
        XCTAssertEqual(HTTPRequestViewModel(request: request).operationBadgeColor, .orange)
    }

    func testNonGraphQLFallback() {
        let request = HTTPRequest()
        let viewModel = HTTPRequestViewModel(request: request)
        XCTAssertFalse(viewModel.isGraphQL)
        XCTAssertEqual(viewModel.operationName, "-")
        XCTAssertNil(viewModel.operationBadgeText)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/HTTPRequestViewModelTests`
Expected: FAIL — `value of type 'HTTPRequestViewModel' has no member 'isGraphQL'`.

- [ ] **Step 3: Add the view-model fields**

In `HTTPResponseView.swift`, add these computed properties to `HTTPRequestViewModel` (after the `accentColor` property):

```swift
    /// Whether the underlying request is a GraphQL operation.
    var isGraphQL: Bool {
        request.isGraphQL
    }

    /// The GraphQL operation name, or `"-"` when unavailable.
    var operationName: String {
        request.graphQLOperationName ?? "-"
    }

    /// The uppercased badge text for the operation type, or `nil` (e.g. batched requests).
    var operationBadgeText: String? {
        request.graphQLOperationType?.badgeText
    }

    /// The lozenge colour for the operation type.
    var operationBadgeColor: Color {
        switch request.graphQLOperationType {
        case .query: return .green
        case .mutation: return .orange
        case .subscription: return .purple
        case .none: return .secondary
        }
    }
```

Add `import SwiftUI` at the top of the file if it is not already imported (it is, via `import SwiftUI`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/HTTPRequestViewModelTests`
Expected: PASS.

- [ ] **Step 5: Update `HTTPRequestView` to the Option B layout**

In `HTTPResponseView.swift`, replace the trailing content of the inner `HStack` (the `HighlightingText(viewModel.url, ...)` block, lines ~36-39) so the body becomes a two-line stack for GraphQL rows. Replace:

```swift
                HighlightingText(viewModel.url, substring: searchTerm)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(alignment: .leading)
```

with:

```swift
                if viewModel.isGraphQL {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(viewModel.operationName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                            if let badge = viewModel.operationBadgeText {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(viewModel.operationBadgeColor, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        HighlightingText(viewModel.url, substring: searchTerm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HighlightingText(viewModel.url, substring: searchTerm)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .frame(alignment: .leading)
                }
```

Note: the outer `HStack` already centres content vertically (default `.center` alignment), so both the one-line and two-line bodies stay vertically centred against the method/status column.

- [ ] **Step 6: Build to verify the view compiles**

Run: `xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift Tests/ScytherTests/Features/HTTPRequestViewModelTests.swift
git commit -m "feat: show GraphQL operation name and type in network log rows"
```

---

## Task 4: Search by operation name

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/NetworkLogsViewModel.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift`
- Test: `Tests/ScytherTests/Features/NetworkLogsViewModelTests.swift` (create)

**Interfaces:**
- Consumes: `HTTPRequest.graphQLOperationName` (Task 2); existing `setSearchTerm(to:)`, `requests`.
- Produces: search now matches operation name.

- [ ] **Step 1: Write the failing test**

Create `Tests/ScytherTests/Features/NetworkLogsViewModelTests.swift`:

```swift
//
//  NetworkLogsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkLogsViewModelTests: XCTestCase {

    func testSearchMatchesOperationName() async {
        let gql = HTTPRequest()
        gql.requestURL = "https://api.example.com/graphql"
        gql.requestMethod = "POST"
        gql.graphQLOperationName = "GetUserProfile"

        let rest = HTTPRequest()
        rest.requestURL = "https://api.example.com/users"
        rest.requestMethod = "GET"

        let filtered = NetworkLogsViewModel.filter(
            items: [gql, rest],
            searchTerm: "getuserprofile"
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.requestURL, "https://api.example.com/graphql")
    }

    func testEmptySearchReturnsAll() {
        let a = HTTPRequest()
        let b = HTTPRequest()
        XCTAssertEqual(NetworkLogsViewModel.filter(items: [a, b], searchTerm: "").count, 2)
    }
}
```

> Design note: this extracts the filter predicate into a pure, testable static method, because the existing filtering runs inside a debounced async pipeline that is awkward to drive from a test.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/NetworkLogsViewModelTests`
Expected: FAIL — `type 'NetworkLogsViewModel' has no member 'filter'`.

- [ ] **Step 3: Extract and extend the filter predicate**

In `NetworkLogsViewModel.swift`, add this static method to the class (e.g. just above `updateData()`):

```swift
    /// Filters requests by matching the search term against URL, operation name, status code, or method.
    ///
    /// - Parameters:
    ///   - items: The requests to filter.
    ///   - searchTerm: The raw search term (case-insensitive; whitespace is trimmed).
    /// - Returns: All items when the term is empty, otherwise the matching subset.
    static func filter(items: [HTTPRequest], searchTerm: String) -> [HTTPRequest] {
        let predicate = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !predicate.isEmpty else { return items }
        return items.filter { item in
            item.responseCode?.description.lowercased().contains(predicate) == true ||
            item.requestURL?.lowercased().contains(predicate) == true ||
            item.requestMethod?.lowercased().contains(predicate) == true ||
            item.graphQLOperationName?.lowercased().contains(predicate) == true
        }
    }
```

Then replace the body of `updateData()`'s non-empty branch so it reuses this method. Change:

```swift
        if currentSearchTerm.isEmpty {
            requests = currentItems
        } else {
            // Filter on background thread
            let filtered = await Task.detached(priority: .userInitiated) {
                let predicate = currentSearchTerm.lowercased()
                return currentItems.filter { item in
                    item.responseCode?.description.lowercased().contains(predicate) == true ||
                    item.requestURL?.lowercased().contains(predicate) == true ||
                    item.requestMethod?.lowercased().contains(predicate) == true
                }
            }.value

            // Check if task was cancelled before updating
            guard !Task.isCancelled else { return }
            requests = filtered
        }
```

to:

```swift
        if currentSearchTerm.isEmpty {
            requests = currentItems
        } else {
            // Filter on background thread
            let filtered = await Task.detached(priority: .userInitiated) {
                Self.filter(items: currentItems, searchTerm: currentSearchTerm)
            }.value

            // Check if task was cancelled before updating
            guard !Task.isCancelled else { return }
            requests = filtered
        }
```

- [ ] **Step 4: Update the search prompt**

In `NetworkLogsView.swift`, change the `.searchable` prompt (line ~66) from:

```swift
            prompt: "Search via URL, Status Code or Method"
```

to:

```swift
            prompt: "Search via URL, Operation, Status Code or Method"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/NetworkLogsViewModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/NetworkLogsViewModel.swift Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift Tests/ScytherTests/Features/NetworkLogsViewModelTests.swift
git commit -m "feat: match GraphQL operation name in network log search"
```

---

## Task 5: `LogDetailsViewModel` — GraphQL + request-body dictionary

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/LogDetailsViewModel.swift`
- Test: `Tests/ScytherTests/Features/LogDetailsViewModelTests.swift` (create)

**Interfaces:**
- Consumes: `HTTPRequest.isGraphQL`, `.graphQLOperationName`, `.graphQLOperationType`, `.getRequestBodyDictionary()`, `.getGraphQLVariablesDictionary()` (Task 2).
- Produces (on `LogDetailsViewModel`, all `@Published`):
  - `hasGraphQL: Bool`
  - `graphQLOperationName: String`
  - `graphQLOperationType: String`
  - `graphQLVariablesDictionary: [String: [String: Any]]`
  - `requestBodyDictionary: [String: [String: Any]]`

- [ ] **Step 1: Write the failing test**

Create `Tests/ScytherTests/Features/LogDetailsViewModelTests.swift`:

```swift
//
//  LogDetailsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class LogDetailsViewModelTests: XCTestCase {

    func testGraphQLFieldsPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationName = "GetUser"
        request.graphQLOperationType = .mutation

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertTrue(viewModel.hasGraphQL)
        XCTAssertEqual(viewModel.graphQLOperationName, "GetUser")
        XCTAssertEqual(viewModel.graphQLOperationType, "Mutation")
    }

    func testNonGraphQLHasNoGraphQLSection() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.hasGraphQL)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/LogDetailsViewModelTests`
Expected: FAIL — `value of type 'LogDetailsViewModel' has no member 'hasGraphQL'`.

- [ ] **Step 3: Add the published properties**

In `LogDetailsViewModel.swift`, after `responseBodyDictionary` (line ~110), add:

```swift
    /// Whether the request is a GraphQL operation.
    @Published var hasGraphQL: Bool = false

    /// The GraphQL operation name.
    @Published var graphQLOperationName: String = ""

    /// The GraphQL operation type as a display string (e.g. "Query").
    @Published var graphQLOperationType: String = ""

    /// The GraphQL `variables` object as a browsable dictionary structure.
    @Published var graphQLVariablesDictionary: [String: [String: Any]] = [:]

    /// The request body parsed as a browsable dictionary structure.
    @Published var requestBodyDictionary: [String: [String: Any]] = [:]
```

- [ ] **Step 4: Populate them in `loadDetails()`**

In `loadDetails()`, after the `requestBody`/`hasRequestBody` lines (~171-172), add:

```swift
        requestBodyDictionary = httpRequest.getRequestBodyDictionary()

        hasGraphQL = httpRequest.isGraphQL
        graphQLOperationName = httpRequest.graphQLOperationName ?? "-"
        graphQLOperationType = httpRequest.graphQLOperationType?.displayName ?? "-"
        graphQLVariablesDictionary = httpRequest.getGraphQLVariablesDictionary()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/LogDetailsViewModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/LogDetailsViewModel.swift Tests/ScytherTests/Features/LogDetailsViewModelTests.swift
git commit -m "feat: expose GraphQL and request-body dictionary on LogDetailsViewModel"
```

---

## Task 6: `LogDetailsView` — GraphQL section + fixed Request Body section

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/LogDetailsView.swift`

**Interfaces:**
- Consumes: `LogDetailsViewModel.hasGraphQL`, `.graphQLOperationName`, `.graphQLOperationType`, `.graphQLVariablesDictionary`, `.requestBodyDictionary`, `.requestBody`, `.hasRequestBody` (Task 5); `DataBrowserView(data:title:)`; `TextReaderView(text:title:)`.
- Produces: the rendered detail UI.

- [ ] **Step 1: Add the GraphQL section to the body**

In `LogDetailsView.swift`, insert `graphQLSection` into the `List` (line ~22), immediately after `overviewSection`:

```swift
        List {
            overviewSection
            graphQLSection
            requestHeadersSection
            requestBodySection
            responseHeadersSection
            responseBodySection
            developerSection
        }
```

- [ ] **Step 2: Implement `graphQLSection`**

Add this computed property to `LogDetailsView` (e.g. after `overviewSection`):

```swift
    @ViewBuilder
    private var graphQLSection: some View {
        if viewModel.hasGraphQL {
            Section("GraphQL") {
                LabeledContent("Operation", value: viewModel.graphQLOperationName)
                LabeledContent("Type", value: viewModel.graphQLOperationType)

                if !viewModel.graphQLVariablesDictionary.isEmpty {
                    NavigationLink("Browse variables") {
                        DataBrowserView(data: viewModel.graphQLVariablesDictionary, title: "Variables")
                    }
                    .foregroundStyle(.tint)
                }
            }
        }
    }
```

- [ ] **Step 3: Fix the Request Body section**

Replace `requestBodySection` (lines ~73-86) with:

```swift
    private var requestBodySection: some View {
        Section("Request Body") {
            if viewModel.hasRequestBody {
                NavigationLink("Browse request body") {
                    DataBrowserView(data: viewModel.requestBodyDictionary, title: "Request Body")
                }
                .foregroundStyle(.tint)

                NavigationLink("View request body") {
                    TextReaderView(text: viewModel.requestBody, title: "Request Body")
                }
                .foregroundStyle(.tint)
            } else {
                Text("No content sent")
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
```

- [ ] **Step 4: Build to verify the view compiles**

Run: `xcodebuild build -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger/LogDetailsView.swift
git commit -m "feat: add GraphQL section and fix Request Body links in details view"
```

---

## Task 7: README, full test run, and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README**

Find the NetworkLogger / Network Logging section in `README.md` and add documentation describing:
- GraphQL operations are detected (by body shape or a `graphql`/`gql` URL path) and the operation name + type (query/mutation/subscription) are shown in the request list.
- The request details view shows a GraphQL section with operation, type, and browsable variables.
- Search matches the GraphQL operation name in addition to URL, status code, and method.
- The Request Body section offers both "Browse request body" (structured) and "View request body" (raw), matching the Response Body section.

Use the existing README's heading style and tone. If there is a features list/table, add a "GraphQL-aware network logging" entry.

- [ ] **Step 2: Run the full test suite**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: TEST SUCCEEDED — all tests pass, including the four new test files.

- [ ] **Step 3: Build documentation (DocC sanity check)**

Run: `xcodebuild docbuild -scheme Scyther -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ./docbuild`
Expected: BUILD SUCCEEDED (verifies DocC comments are well-formed).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document GraphQL support in the network logger"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Request-body button fix (Problem 1) → Task 6 (tinted Browse + View) + Task 2/5 (`requestBodyDictionary`). ✔
- `GraphQLOperation` parser, "both combined" detection, batch/anonymous handling → Task 1. ✔
- Capture-time caching for cheap list/search → Task 2. ✔
- List row Option B (name + trailing lozenge, URL subtitle, status colour unchanged) → Task 3. ✔
- Search by operation name + prompt update → Task 4. ✔
- Details GraphQL section + browsable variables → Tasks 5-6. ✔
- Tests for parser, HTTPRequest caching, both list/details view models, search → Tasks 1-5. ✔
- DocC + README → all tasks (DocC) + Task 7 (README) + Task 7 docbuild. ✔
- Non-goals (GET/persisted queries, response parsing) → not implemented, noted in Global Constraints. ✔

**Placeholder scan:** No TBD/TODO; all steps contain concrete code and exact commands. ✔

**Type consistency:** `GraphQLOperationType` (`.query/.mutation/.subscription`, `displayName`, `badgeText`), `GraphQLOperation.parse(body:url:)`, `HTTPRequest.{isGraphQL, graphQLOperationName, graphQLOperationType, getRequestBodyDictionary(), getGraphQLVariablesDictionary()}`, view-model member names, and `DataBrowserView(data:title:)` / `TextReaderView(text:title:)` signatures are consistent across all tasks. ✔
