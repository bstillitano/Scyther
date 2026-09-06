# Composable Actions and Standalone Network Conditioning

**Date:** 2026-09-05
**Status:** Approved by the repo owner, ready for implementation
**Extends:** [Network Rules](2026-09-05-network-rules-design.md), on branch `feature/network-rules`

## Why

Two things the shipped shape got wrong, both raised by the owner against the running app.

An override carries exactly one action, so choosing **Rewrite Headers** replaces the **Mock
Response** section rather than sitting beside it. Worse, the correctness passes found that when a
mock wins, a matching header rewrite and a matching condition are skipped entirely — and still
credited in the log as applied. So the combination is not merely awkward to express, it is
silently inert.

Network conditioning is miscast as a per-override action. Latency, a bandwidth ceiling and a
failure rate are things a developer wants to apply to the whole app at once, which is what Network
Link Conditioner does. Per-override conditioning stays useful for targeting one endpoint, but it
cannot be the only way to reach it.

## Part 1 — Composable actions

### Model

`NetworkRule.action: NetworkRuleAction` becomes:

```swift
public struct NetworkRuleActions: Codable, Sendable, Equatable {
    /// The response to serve instead of performing the request, if any.
    public var stub: NetworkRuleStub?
    /// Headers to set or remove on the outgoing request.
    public var rewriteHeaders: NetworkHeaderRewrite?
    /// Latency, bandwidth ceiling and failure rate applied to this request.
    public var condition: NetworkCondition?
}

public enum NetworkRuleStub: Codable, Sendable, Equatable {
    case mock(MockResponse)
    case mapLocal(MapLocalFile)
}
```

Mock and map local stay mutually exclusive, and now structurally so — an override cannot hold
both, which is the one combination that has no meaning. Everything else composes.

`NetworkRuleAction` is retired. It is public but the branch is unreleased, so nothing outside
this repo depends on it.

### Decoding what is already on disk

`NetworkRule` gains an explicit `init(from:)` that accepts **either** shape: the new `actions`
object, or the old single `action` key, which it lifts into the equivalent `NetworkRuleActions`.
A correctness pass showed a decode failure costs the developer every override they have
configured, so this is not optional politeness.

Explicit `CodingKeys` are added at the same time, so the persisted format stops depending on
compiler-synthesised positional keys like `_0`.

### Semantics

Evaluation stays first-match-wins per facet, over rules in order:

| Facet | Rule |
|---|---|
| Stub | The first matching stub wins and short-circuits the network. |
| Header rewrite | Every matching rewrite merges, sets before removes. |
| Condition | The first matching condition wins. |

What changes is that a stub no longer suppresses the other two:

- **A condition applies to a stubbed response.** Latency delays it, a failure rate can fail it,
  and a bandwidth ceiling paces the synthetic body. This is what a developer means by "mock this
  endpoint and make it slow", and it is what the log already claimed was happening.
- **A header rewrite is recorded but has no wire effect when the request is stubbed**, because no
  request is sent. It still shapes the logged request so the log shows what would have gone out.
  Documented on the type and in the editor's footer.

`RuleOutcome.stubRuleName` / `networkRuleNames` and their id counterparts keep crediting only what
actually contributed, which is now a larger and more honest set.

### Editor

The Action picker is replaced by a section per action kind, each with its own switch:

- **Stub** — a segmented `Picker` for None / Mock Response / Map Local File, then that kind's fields.
- **Rewrite Headers** — a switch, then the set and remove lists.
- **Condition** — a switch, then latency, bandwidth and failure rate.

Validity is unchanged except that an override with no action at all is invalid, alongside the
existing requirement of at least one of host, path or query.

## Part 2 — Standalone network conditioning

### Model

```swift
@MainActor final class NetworkConditioningStore: ObservableObject {
    @Published var isEnabled: Bool          // Scyther.NetworkConditioning.Enabled, default off
    @Published var condition: NetworkCondition  // Scyther.NetworkConditioning.Condition
}
```

Published into the existing `NetworkRuleSnapshot` alongside the rules, so the interceptor reads it
through the one lock-guarded channel it already has rather than gaining a second global.

### Behaviour

Applies to every intercepted request. A per-override condition that matches takes precedence, so
targeted conditioning still beats the global one; the global condition is the floor, not an
addition. Off by default, and inert on App Store builds through the existing gate.

### Surface

A **Network Conditioning** row in the Networking section, above Request Overrides, showing the
active preset or Off as its detail text. The screen carries the master switch, the three fields,
and a set of presets a developer recognises — Wi-Fi, 4G, 3G, Edge, Very bad network — implemented
as a stock `Picker` that fills the three fields, plus Custom.

## Also in this work

- **Map Local gets a file picker.** `.fileImporter`, and the picked file is copied into the
  override's own storage under the rules directory, exactly as mock bodies already are. That
  removes the security-scoped bookmark problem entirely and makes the stored path meaningful
  across launches. The typed field goes away.
- **The list rows show enabled state properly.** A disabled override reads as disabled rather than
  saying so in small grey text.

## Testing

- Decoding both persisted shapes, including a rule written before this change.
- A stub with a condition: the response is delayed, can fail, and is paced.
- A stub with a rewrite: the logged request carries the rewrite, the wire does not.
- Global conditioning applies with no override present; a matching override's condition beats it.
- The preset picker fills the fields and Custom leaves them alone.
- Map Local: a picked file is copied, survives a relaunch, and is served.
- Every new string in twelve languages, catalogue regenerated.
