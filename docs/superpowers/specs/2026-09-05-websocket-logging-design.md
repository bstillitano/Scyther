# WebSocket Logging

**Date:** 2026-09-05
**Status:** Approved design — ready for implementation planning
**Part:** 5 of 5 in the networking backlog
**Depends on:** nothing. Needs its own capture mechanism.

## Summary

Capture WebSocket sessions and the frames that flow through them, and show them beside the HTTP
log. This is the only networking feature that cannot use the interceptor: a `URLProtocol` is never
consulted for a `URLSessionWebSocketTask`, because the loading system handles the upgrade itself.

It therefore needs a capture mechanism of its own, and that mechanism is the whole design
question.

## Background

Confirmed on 2026-09-05:

- `URLProtocol.canInit(with task:)` is called for data, upload and download tasks. A
  `URLSessionWebSocketTask` never reaches it — after the HTTP upgrade the connection is no longer
  a request/response exchange the protocol layer models. Nothing in the current interceptor sees
  a single WebSocket frame.
- `NetworkHelper` already swizzles `URLSessionConfiguration` to insert the protocol class, so
  **method swizzling is established practice in this codebase**, not a new kind of risk.
- `URLSessionWebSocketTask` is not designed for subclassing: it is returned from
  `URLSession.webSocketTask(with:)` as a concrete instance, and its `send`, `receive`, `sendPing`
  and `cancel(with:reason:)` are the entire surface a frame can pass through.
- `receive(completionHandler:)` is called by the app in a loop, and the `async` variant wraps the
  same underlying method, so swizzling the completion-handler form captures both.
- `NetworkLogger` is an actor over `[HTTPRequest]`; a WebSocket session is a different shape and
  does not belong in that array.

## Goals

- Record each WebSocket session: URL, protocols, when it opened, when and how it closed.
- Record each frame: direction, kind (text or binary), payload, size and timestamp.
- Show sessions in a list and frames in a detail view, searchable, with the same look as the
  network log.
- Add nothing to the request path when the feature is off, and stay off by default.
- Be honest, in the API and the docs, that capture is best-effort.

## Non-Goals

- **Mocking, conditioning or breaking on frames.** Rules and breakpoints do not extend here.
- **Third-party WebSocket libraries.** Starscream and SocketRocket use raw sockets and never touch
  `URLSessionWebSocketTask`. They cannot be captured this way, and the docs say so plainly rather
  than appearing to support them.
- **Frames in the HAR export.** HAR has no standard for WebSocket messages; Chrome's
  `_webSocketMessages` is a vendor extension. Frames export as JSON alongside the HAR in the
  bundle instead.
- **Reconstructing a session after a relaunch.** Sessions live in memory like the HTTP log.

## Design

### Component 1: Two capture paths, one supported

**The opt-in wrapper is the supported path.** An app that wants reliable capture hands its task
to Scyther:

```swift
let task = session.webSocketTask(with: url)
Scyther.network.observe(task)   // returns immediately; capture starts now
```

`observe(_:)` wraps the task in a `WebSocketProbe` that records frames as they pass. This is
explicit, has no swizzling risk, and is what the documentation recommends.

**Swizzling is the convenience path**, off by default:

```swift
Scyther.network.webSocketLogging = true   // swizzles on first set, logs a warning
```

When enabled, `URLSession.webSocketTask(with:)` and `webSocketTask(with:protocols:)` are swizzled
to return a task already registered with the probe registry, and `send(_:completionHandler:)`,
`receive(completionHandler:)`, `sendPing(pongReceiveHandler:)` and `cancel(with:reason:)` are
swizzled on `URLSessionWebSocketTask` to record as they forward to the original implementations.

The two paths share one recorder, so a session captured either way looks identical downstream.
Swizzling is applied once, guarded, and never in an App Store build (the existing `Scyther.isStarted`
gate) — but the spec is explicit that it depends on private-ish behaviour of a system class and may
break on a future iOS release. That is why it is opt-in and why the wrapper exists.

### Component 2: The model

```swift
public final class WebSocketSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let url: String
    public let requestedProtocols: [String]
    public let openedAt: Date
    public private(set) var closedAt: Date?
    public private(set) var closeCode: URLSessionWebSocketTask.CloseCode?
    public private(set) var closeReason: String?
    public private(set) var frames: [WebSocketFrame]
}

public struct WebSocketFrame: Identifiable, Sendable {
    public enum Direction: Sendable { case sent, received }
    public enum Kind: Sendable { case text, binary, ping, pong }
    public let id: UUID
    public let direction: Direction
    public let kind: Kind
    public let date: Date
    public let byteCount: Int
    /// Text payloads inline; binary payloads on disk, read on demand.
    public let payloadID: UUID?
}
```

Payload storage follows `HTTPRequest`: text under a few KB is held inline, everything larger is
written to `<Application Support>/Scyther/WebSockets/<uuid>` and read when a frame is opened.
A chat app can produce thousands of frames a minute, so frames are held in a per-session ring
buffer capped at 2,000 with the oldest dropped, and the UI states when frames have been dropped.

### Component 3: `WebSocketLogger` (new actor)

Mirrors `NetworkLogger`: an actor holding `[WebSocketSession]`, an `AsyncStream` of updates, a
`clear()`, and the same seven-day cleanup `NetworkLogCleaner` already performs for the HTTP log.

### Component 4: UI

A new **Networking → WebSockets** menu row, id `webSockets`, icon `bolt.horizontal`, shown with a
live session count. Search keywords: `socket`, `ws`, `wss`, `frames`, `realtime`.

- **Session list** — URL, open or closed with a coloured status bar in the same treatment as the
  HTTP rows, frame count and duration.
- **Session detail** — an overview section (URL, protocols, opened, closed, close code) and a
  frame list. Frames show direction with an arrow glyph, kind, size and time, and are searchable
  by payload. Tapping a frame opens the existing `TextReaderView` for text or the data browser for
  JSON.
- **Export** — the session as JSON, through the same `ShareLink` treatment as the cURL export, and
  included in the bug report bundle when that feature exists.

When `webSocketLogging` is off and no task has been passed to `observe(_:)`, the screen explains
both ways to turn capture on rather than showing an empty list.

### Component 5: Testing

- `WebSocketProbeTests` — a probe wrapping a fake task records sent and received frames with the
  right direction, kind and byte count; a close records code and reason; the ring buffer drops
  the oldest and sets the dropped flag.
- `WebSocketLoggerTests` — sessions accumulate, `clear()` empties, the update stream fires, and
  the cleanup drops sessions older than seven days.
- `WebSocketPayloadStoreTests` — small text stays inline, large payloads round-trip through disk,
  and deleting a session deletes its payloads.
- Swizzling is **not** unit-tested against the real class; it is verified once in the example app
  by connecting to a public echo endpoint and confirming frames appear. The spec is explicit that
  this is manual verification, because a test that swizzles a system class inside a test host is
  more likely to break the suite than to catch a regression.
- Strings go in a `WebSockets.json` fragment in all twelve languages.

## Risks and mitigations

- **Swizzling a system class may break on a future iOS.** It is off by default, the wrapper is the
  supported path, and the docs say which is which. If a future release breaks it, the wrapper keeps
  working and the toggle can be removed without touching the model or the UI.
- **Frame volume.** The ring buffer caps memory per session; large payloads go to disk; the UI
  reports dropped frames rather than silently lying about the history.
- **Third-party libraries look unsupported.** They are unsupported, and saying so in the empty
  state is better than a developer concluding the feature is broken.
- **Ordering under concurrency.** Frames are timestamped and appended inside the actor, so
  interleaved sends and receives keep a stable order.
