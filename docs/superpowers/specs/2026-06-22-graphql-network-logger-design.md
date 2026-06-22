# GraphQL Support in the Network Logger + Request-Body Button Fix

**Date:** 2026-06-22
**Status:** Approved design — ready for implementation planning

## Summary

Two improvements to the Scyther NetworkLogger feature:

1. **Request-body button styling (Problem 1).** In `LogDetailsView`, the "View request
   body" link renders as plain primary-coloured text and offers no structured browser,
   while the Response Body section offers two tinted links ("Browse" + "View"). Make the
   Request Body section mirror the Response Body section: a tinted "Browse request body"
   (`DataBrowserView`) and a tinted "View request body" (`TextReaderView`).

2. **GraphQL support (Problem 2).** GraphQL calls are all `POST`s to the same endpoint, so
   the request list is a wall of identical-looking rows distinguished only by
   method/status/duration. Surface the GraphQL operation name and type in the list row,
   enrich the details view with a GraphQL section, and let search match the operation name.

## Background

Current behaviour (confirmed in code):

- **List row** (`HTTPRequestView` / `HTTPRequestViewModel` in `HTTPResponseView.swift`):
  shows a status-coloured accent bar, a method/status/duration column, and the full URL.
  The accent/status colour is driven **only by the response code**, never the method.
- **Details view** (`LogDetailsView` / `LogDetailsViewModel`): Overview, Request Headers,
  Request Body, Response Headers, Response Body, Developer Info sections. The Response Body
  section already has both `DataBrowserView` ("Browse") and `TextReaderView` ("View")
  links, both `.foregroundStyle(.tint)`. The Request Body section has only a single
  untinted "View request body" link.
- **Data model** (`HTTPRequest`): request/response bodies are stored to disk (not held in
  memory) and read lazily via `getRequestBody()` / `getResponseBody()` /
  `getResponseBodyDictionary()`. `saveRequestBody(_:)` is the capture point where the
  request body `Data` is in hand.
- **Search** (`NetworkLogsViewModel.updateData()`): debounced (300ms), filters on a
  background task by response code, URL, and method.
- **GraphQL:** no awareness anywhere in the codebase today.

## Goals

- Show GraphQL operation name + type in the request list (Option B layout, below).
- Enrich the details view with a GraphQL section (operation, type, browsable variables).
- Make search match the GraphQL operation name.
- Add the structured "Browse request body" option and tint both request-body links.
- Keep list rendering and search cheap (no per-row disk reads).

## Non-Goals

- GraphQL-over-GET / persisted queries (query passed as URL query parameters). Detection is
  scoped to POST JSON request bodies for this pass; GET-based variants are future work.
- GraphQL response parsing (e.g. surfacing the `errors` array). Out of scope.
- Schema introspection, query syntax highlighting, or a GraphQL-aware variable editor.

## Design

### Component 1: `GraphQLOperation` parser (new, isolated)

A new value type in `Sources/Scyther/Features/NetworkLogger/` responsible solely for
interpreting a request body as a GraphQL operation. It has one clear purpose, a small
interface, and depends only on `Foundation`.

**Type:**

```swift
enum GraphQLOperationType: String, Sendable {
    case query
    case mutation
    case subscription
}

struct GraphQLOperation: Sendable {
    let operationName: String        // resolved display name; "(anonymous)" if unnamed
    let type: GraphQLOperationType?  // nil for batched requests
    let isBatch: Bool
    let batchCount: Int              // 1 for a single operation
    let variables: [String: Any]?    // raw variables object, for the data browser
}
```

**Detection + parsing** — a static factory:

```swift
extension GraphQLOperation {
    /// Returns a parsed operation if `data` (with the given request URL) looks like a
    /// GraphQL request, otherwise nil.
    static func parse(body data: Data?, url: String?) -> GraphQLOperation?
}
```

Rules (the "both combined" detection chosen during brainstorming):

1. A request is GraphQL if **either**:
   - the body parses as a JSON object containing a `query` field whose value is a string, **or**
   - the URL path contains `graphql` or `gql` (case-insensitive) **and** the body parses as
     JSON (object or array).
2. **Single operation** (JSON object): `operationName` taken from the JSON `operationName`
   field if present and non-empty; otherwise parsed from the document by scanning the first
   meaningful token — `query Name`, `mutation Name`, `subscription Name`. If the document
   starts with `{` (shorthand) or has no name, `operationName = "(anonymous)"`. `type`
   derived from the leading keyword; a shorthand `{ ... }` document defaults to `.query`.
3. **Batched operations** (JSON array of objects each with a `query`): `isBatch = true`,
   `batchCount = N`, `operationName = "Batch (N operations)"`, `type = nil`,
   `variables = nil`.
4. Non-JSON, malformed, or JSON lacking a `query` string (and no path hint) → returns
   `nil` (safely treated as a normal request).

This type contains all string/JSON parsing so it can be unit-tested in isolation without
any UI or disk dependencies.

### Component 2: `HTTPRequest` enrichment (capture-time caching)

Parse **once at capture time** to avoid per-row disk reads when rendering the list.

In `HTTPRequest.saveRequestBody(_ request:)`, after saving the body to disk, call
`GraphQLOperation.parse(body: request.body, url: requestURL)` and cache lightweight
properties on the model:

```swift
/// Whether this request was detected as a GraphQL operation.
var isGraphQL: Bool = false
/// The resolved GraphQL operation name, if this is a GraphQL request.
var graphQLOperationName: String?
/// The GraphQL operation type, if known (nil for batched requests).
var graphQLOperationType: GraphQLOperationType?
```

Variables are **not** cached on the model; they are read lazily from disk only when the
details view requests them (see Component 5). Rationale: the list and search only need the
name/type, and keeping the model lightweight matches the existing on-disk body strategy.

### Component 3: List row — Option B layout

`HTTPRequestViewModel` gains:

- `isGraphQL: Bool`
- `operationName: String` (falls back to `"-"`)
- `operationType: GraphQLOperationType?`
- `operationBadgeText: String?` (e.g. `"QUERY"`, `"MUTATION"`, `"SUBSCRIPTION"`; nil for batch)
- `operationBadgeColor: Color` (query = green, mutation = orange, subscription = purple)

`HTTPRequestView`: when `isGraphQL`, the right-hand body becomes a vertically-centered
two-line stack:

- **Line 1 (title):** operation name (bold) with the type lozenge **trailing** it. The
  lozenge is a small rounded, filled pill coloured per `operationBadgeColor`.
- **Line 2 (subtitle):** the URL in grey caption, with existing search-term highlighting.

When not GraphQL, the row is unchanged (single highlighted URL line). The status accent bar
and code colour remain driven solely by the response code.

### Component 4: Search by operation name

In `NetworkLogsViewModel.updateData()`, extend the background filter predicate to also match
`graphQLOperationName`:

```swift
item.graphQLOperationName?.lowercased().contains(predicate) == true
```

Update the `.searchable` prompt in `NetworkLogsView` to:
`"Search via URL, Operation, Status Code or Method"`.

### Component 5: Details view

`LogDetailsViewModel` gains:

- `hasGraphQL: Bool`
- `graphQLOperationName: String`
- `graphQLOperationType: String` (display string, e.g. "Query")
- `graphQLVariablesDictionary: [String: [String: Any]]` — read lazily from the on-disk
  request body and shaped for `DataBrowserView` (mirrors `responseBodyDictionary`).
- `requestBodyDictionary: [String: [String: Any]]` — mirrors the existing
  `responseBodyDictionary`, built from the on-disk request body.

`LogDetailsView`:

- **New `graphQLSection`** (rendered only when `hasGraphQL`), placed immediately after
  `overviewSection`:
  - `LabeledContent("Operation", value: graphQLOperationName)`
  - `LabeledContent("Type", ...)` showing a badge
  - A tinted `NavigationLink("Browse variables")` →
    `DataBrowserView(data: viewModel.graphQLVariablesDictionary, title: "Variables")`
- **Fixed `requestBodySection`** (Problem 1): mirror `responseBodySection` exactly —
  ```swift
  NavigationLink("Browse request body") {
      DataBrowserView(data: viewModel.requestBodyDictionary, title: "Request Body")
  }
  .foregroundStyle(.tint)

  NavigationLink("View request body") {
      TextReaderView(text: viewModel.requestBody, title: "Request Body")
  }
  .foregroundStyle(.tint)
  ```

## Data Flow

```
URLSession traffic
  → HTTPInterceptorURLProtocol
  → HTTPRequest.saveRequestBody(request)
       ├─ body Data written to disk (unchanged)
       └─ GraphQLOperation.parse(body:url:)  ──► cache isGraphQL / name / type on model
                                                  (variables NOT cached)

NetworkLogsViewModel (list)
  → reads cached isGraphQL / graphQLOperationName (cheap, no disk)
  → HTTPRequestView renders Option B row
  → search predicate matches graphQLOperationName

LogDetailsView (details)
  → graphQLSection: name/type from model; variables read lazily from disk
  → requestBodySection: Browse (requestBodyDictionary, lazy from disk) + View (raw text)
```

## Error Handling / Edge Cases

- **Non-JSON or malformed body:** `parse` returns nil → request treated as normal. No crash.
- **JSON without a `query` string and no path hint:** not GraphQL.
- **Anonymous / shorthand query:** `operationName = "(anonymous)"`, type defaults to `.query`.
- **Batched array:** `isBatch = true`, name = `"Batch (N operations)"`, type/variables nil;
  list shows the name without a type lozenge; details view omits the type badge and
  "Browse variables".
- **Missing `variables`:** `graphQLVariablesDictionary` is empty; the data browser shows an
  empty structure (consistent with existing response-body behaviour).
- **Large bodies:** parsing happens once at capture; list/search never re-read the body.

## Testing

Per CLAUDE.md (always add/update tests, build for the booted iOS simulator):

- **`GraphQLOperation` unit tests:** body-shape detection (positive), path-heuristic
  detection, negative (REST JSON / non-JSON / empty), named operation, `operationName`-field
  precedence over document name, anonymous/shorthand, mutation/subscription type, batched
  array, malformed JSON, variables extraction.
- **`HTTPRequestViewModel` tests:** GraphQL fields and badge text/colour mapping; non-GraphQL
  fallback unchanged.
- **`LogDetailsViewModel` tests:** `hasGraphQL`, operation name/type, `requestBodyDictionary`
  and `graphQLVariablesDictionary` shaping.
- **`NetworkLogsViewModel` tests:** search matches operation name.

## Documentation

- DocC comments on all new types, properties, and methods (`GraphQLOperation`,
  `GraphQLOperationType`, new `HTTPRequest` properties, new view-model members).
- Update README to document GraphQL support in the network logger (list display, details
  enrichment, search by operation) and the request-body browse/view options.

## Files Touched

New:
- `Sources/Scyther/Features/NetworkLogger/GraphQLOperation.swift`
- Test file(s) under the existing test target for the above.

Modified:
- `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift` — cached GraphQL properties; parse in `saveRequestBody`.
- `Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift` — `HTTPRequestViewModel` + `HTTPRequestView` Option B row.
- `Sources/Scyther/Features/NetworkLogger/NetworkLogsViewModel.swift` — search predicate.
- `Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift` — searchable prompt.
- `Sources/Scyther/Features/NetworkLogger/LogDetailsViewModel.swift` — GraphQL + request-body-dictionary members.
- `Sources/Scyther/Features/NetworkLogger/LogDetailsView.swift` — `graphQLSection`; fixed `requestBodySection`.
- `README.md`.
