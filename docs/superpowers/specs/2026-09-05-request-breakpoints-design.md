# Request Breakpoints

**Date:** 2026-09-05
**Status:** Approved design — ready for implementation planning
**Part:** 2 of 5 in the networking backlog
**Depends on:** [Network Rules](2026-09-05-network-rules-design.md) — reuses `NetworkRuleMatch`
and the `startLoading()` hook

## Summary

Pause a matching request before it is sent, or a matching response before the app sees it, so it
can be inspected and edited in place. This is the feature developers reach for Charles or
Proxyman to get, and the only one in the networking backlog that deliberately blocks the app.

## Background

Beyond the background in the Network Rules spec:

- `startLoading()` is invoked by the URL loading system on a private, per-request thread — not the
  main thread, and not a queue shared with other requests. Blocking inside it stalls exactly one
  request and nothing else. This is what makes a request breakpoint possible at all.
- Response data is forwarded to the client incrementally: `urlSession(_:dataTask:didReceive:)`
  calls `client?.urlProtocol(self, didLoad: data)` as each chunk arrives. **Once a chunk has been
  forwarded, it cannot be taken back**, so a response breakpoint has to withhold forwarding rather
  than intercept after the fact.
- `Scyther.showMenu(from:)` presents a `UIHostingController` over the top view controller, and
  `AppEnvironment.isTestCase` already exists to detect a test run.
- `LoggerAuthenticationChallengeSender` is an existing example of the codebase wrapping a
  completion handler to defer a decision.

## Goals

- Pause a request matching a breakpoint before it leaves the app; edit method, URL, headers and
  body; then continue, or abort with a chosen `URLError`.
- Pause a matching response before the app receives any of it; edit status, headers and body;
  then continue or abort.
- Surface a paused request immediately, wherever the developer is in the app.
- Guarantee the app cannot be left hanging: every pause has a timeout that continues unmodified.
- Never fire in a test run.

## Non-Goals

- **Breaking on WebSocket frames.** Spec 5, and not planned there either.
- **Scripted or conditional breakpoints** (pause only when a body field equals X). Matching is
  the same facet set as a rule; anything finer belongs in a scripting feature that does not exist.
- **Editing a streaming response chunk by chunk.** A response breakpoint buffers the whole body
  and presents it once. Large downloads should not have breakpoints set on them, and the UI says
  so.
- **Pausing redirects independently.** A redirect is followed as today; the breakpoint applies to
  the original request and the final response.

## Design

### Component 1: The breakpoint model

```swift
public struct NetworkBreakpoint: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Reused verbatim from the Network Rules spec.
    public var match: NetworkRuleMatch
    /// Which side of the exchange to pause. Both is allowed and pauses twice.
    public var stage: Stage

    public enum Stage: String, Codable, Sendable { case request, response, both }
}
```

Stored alongside rules in `UserDefaults.scyther` under `Scyther.NetworkBreakpoints.Breakpoints`,
with the same snapshot mechanism (`NetworkBreakpointSnapshot.current`) so the interceptor can read
them off the main actor. A master switch lives under `Scyther.NetworkBreakpoints.Enabled` and
**defaults to off**.

### Component 2: The pause primitive

```swift
/// A request or response held mid-flight, awaiting a decision.
@MainActor
final class PendingBreakpoint: Identifiable, ObservableObject {
    let id: UUID
    let breakpointName: String
    let stage: NetworkBreakpoint.Stage
    @Published var draft: BreakpointDraft   // editable copy
    let deadline: Date
}

enum BreakpointResolution: Sendable {
    case `continue`(BreakpointDraft)   // possibly edited
    case abort(URLError.Code)
    case timedOut                      // continue unmodified
}
```

The interceptor thread and the UI meet through a `BreakpointCoordinator`:

```swift
final class BreakpointCoordinator: Sendable {
    static let shared: BreakpointCoordinator
    /// Called from the protocol's thread. Blocks until resolved or the timeout elapses.
    func pause(_ draft: BreakpointDraft, name: String, stage: NetworkBreakpoint.Stage) -> BreakpointResolution
    /// Called from the UI.
    @MainActor func resolve(id: UUID, with resolution: BreakpointResolution)
    @MainActor var pending: [PendingBreakpoint] { get }
}
```

`pause` enqueues the draft, notifies the UI on the main actor, then waits on a
`DispatchSemaphore` with `timeout(.now() + interval)`. The default interval is 60 seconds,
configurable per breakpoint between 5 and 300 seconds. A timeout resolves as `.timedOut` and the
request proceeds unmodified — **the app is never left blocked indefinitely**.

Concurrent pauses are supported: each has its own semaphore and its own row in the UI, resolved
in any order.

### Component 3: Interceptor integration

**Request stage**, in `startLoading()`, after rules are applied and before the data task is
created:

1. If a request-stage breakpoint matches, build a `BreakpointDraft` from the (already
   rule-rewritten) request and call `pause`.
2. On `.continue(draft)`, rebuild the `URLRequest` from the draft and proceed.
3. On `.abort(code)`, call `client?.urlProtocol(self, didFailWithError: URLError(code))` and log
   the model as failed.
4. On `.timedOut`, proceed unmodified.

**Response stage** changes how data is forwarded. When a response-stage breakpoint matches the
request:

- `urlSession(_:dataTask:didReceive response:)` **withholds** the call to
  `client?.urlProtocol(_:didReceive:cacheStoragePolicy:)`.
- `urlSession(_:dataTask:didReceive data:)` **withholds** `didLoad:` and buffers instead.
- `urlSession(_:task:didCompleteWithError:)` calls `pause` with the buffered response, then emits
  the resolved response and body through the normal trio before finishing.

A response breakpoint therefore delays the app's first byte until the whole body has arrived,
which is stated in the UI when the stage is selected.

`HTTPRequest` gains `breakpointNames: [String]` and `wasEdited: Bool`, and the log row shows a
**HELD** lozenge beside the existing MOCKED one.

### Component 4: Reaching the developer

When the first pause enqueues and Scyther's menu is not already on screen, the coordinator
presents the breakpoint sheet over the key window using the same
`UIHostingController` path as `Scyther.showMenu(from:)`. If the menu is on screen, it pushes the
sheet on top. Either way the developer lands on the editor without hunting for it.

The sheet shows the pending list when more than one request is held, and a per-item editor:
method, URL, header rows and a body editor for a request; status, header rows and a body editor
for a response. Each has **Continue**, **Continue without changes**, and a destructive **Abort**.
A countdown shows the remaining time before the automatic continue.

### Component 5: Safety rails

- The master switch defaults to **off** and the menu row shows the count of enabled breakpoints.
- **Disabled entirely when `AppEnvironment.isTestCase` is true**, so a breakpoint left enabled can
  never hang a CI run.
- Disabled on App Store builds by the existing `Scyther.isStarted` gate.
- The timeout cannot be disabled, and its maximum is 300 seconds.
- A pause is skipped, and logged via `logMessage`, if the app is in the background: a paused
  request the developer cannot see would look like a hang.

### Component 6: Testing

- `BreakpointCoordinatorTests` — resolve continues, resolve aborts, timeout returns `.timedOut`
  within tolerance, concurrent pauses resolve independently, and `pause` never blocks the main
  thread (asserted with a main-thread guard).
- `BreakpointInterceptorTests` — a request-stage breakpoint edits a header that arrives on the
  wire; an abort surfaces the chosen `URLError`; a response-stage breakpoint withholds every byte
  until resolution and then delivers the edited body; a non-matching request is unaffected.
- `BreakpointStoreTests` — persistence round-trip, master switch default is off, `isTestCase`
  suppresses evaluation.
- Every new string goes in a `Breakpoints.json` fragment in all twelve languages.

## Risks and mitigations

- **A forgotten breakpoint makes the app look broken.** The timeout continues automatically, the
  master switch defaults to off, the menu row shows a count, and the log marks held requests.
- **Blocking a thread is inherently uncomfortable.** It is one per-request thread, never the main
  thread or a shared queue; a main-thread assertion in the coordinator makes a regression fail a
  test rather than ship.
- **Buffering a large response.** The UI warns when a response breakpoint's match could apply to
  a download, and the buffered body is capped at 10 MB, above which the pause is skipped and
  logged.
- **Reuse coupling to spec 1.** `NetworkRuleMatch` is shared. If spec 1's implementation changes
  the matcher's shape, this spec's model follows it rather than forking a second matcher.
