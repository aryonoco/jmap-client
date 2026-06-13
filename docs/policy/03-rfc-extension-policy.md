# RFC extension policy

This document reserves the **names** — capability variants, types, module
paths, and procedures — that future JMAP RFCs and the deferred parts of
RFC 8620 will inhabit, without implementing them. Reserving the names pre-1.0
makes every future extension a purely **additive** minor release (P20): the
shape is fixed now, so landing an implementation later cannot force a rename or
a repurpose (P1).

The rule is: **post-1.0, implementing any reserved feature means landing the
named type at the named path with the named capability variant.** Deviating
from a reservation in this table is a 2.0 break, not a 1.x addition.

## Reserved extensions

| RFC / feature | `CapabilityKind` variant | Reserved type | Reserved module path | Status |
|---|---|---|---|---|
| RFC 8887 — JMAP over WebSocket | `ckWebsocket` (exists) | `WebSocketChannel` (A24) | `jmap_client/websocket` | deferred |
| RFC 8620 §7 — Push | future `ckPush` | `PushChannel` (A23) | `jmap_client/push` | deferred |
| RFC 8620 §6.5 — Blob upload/download | `ckBlob` (exists) | — (additive methods on `JmapClient`) | — | deferred |
| RFC 9007 — JMAP MDN | `ckMdn` (exists) | new entity module mirroring `mail/` | `jmap_client/mdn` | deferred |
| RFC 8624 — JMAP Contacts | `ckContacts` (exists) | new entity module | `jmap_client/contacts` | deferred |
| Future Calendars draft | `ckCalendars` (exists) | new entity module | `jmap_client/calendars` | deferred |

Notes on the non-obvious rows:

- **Push and WebSocket are separate types (A23 / A24).** WebSocket is a
  bidirectional transport upgraded from HTTPS; Push is HTTP push notification.
  Conflating them onto one type — or retrofitting either onto `JmapClient` as a
  method — is the libdbus failure mode (P23). Each is a distinct handle type;
  P23 reserves the *type* now, P5 keeps the *module path* out of the closed
  public-path set (A10) until the implementation earns it (a path addition is a
  minor bump per P20).
- **Blob extends `JmapClient` additively.** Upload/download (RFC 8620 §6.5) land
  as `uploadBlob` / `downloadBlob` methods on the existing handle, never as a
  separate context type (P9). Document the rationale before 1.0.
- **New entity RFCs (MDN, Contacts, Calendars)** ship as a new entity directory
  with the same shape as `internal/mail/`, registered through the existing
  `registerJmapEntity` / `registerExtractableEntity` / `registerSettableEntity`
  framework (D7) — never as new top-level procs mirroring old ones (P20).
  Capability-extension *gettable properties* on existing entities need no
  library change: they are requestable through the typed `…Other` escape arm on
  the A3.6 get-property selectors (forward-compat, P20).

## Async dispatch (lands with A19 + E1)

The synchronous request/response API is the headline (P22); async is a separate,
additive type with a different lifecycle, never a flag on the sync path (P23).
The asynchronous chain extends the existing sync chain additively:

`RequestBuilder` → `BuiltRequest` → `DispatchedRequest` (in-flight token) →
`DispatchedResponse` (received).

> **Async dispatch (lands with A19 + E1).** The async overload is a separate
> procedure `sendAsync` — never an overload of `send`, never a runtime flag
> (P22). Signature: `proc sendAsync(client: JmapClient, req: sink BuiltRequest):
> JmapResult[DispatchedRequest]`. `proc await(dr: sink DispatchedRequest):
> JmapResult[DispatchedResponse]` consumes the in-flight token and yields the
> same `DispatchedResponse` the sync path produces. The names `sendAsync` and
> `DispatchedRequest` are reserved for this contract; no public API claims them
> pre-1.0.

`DispatchedRequest` and `sendAsync` are reserved **by policy, not by type stub**
(unlike `PushChannel` / `WebSocketChannel`, which have consumer-facing type
declarations now). Their shapes depend on the `Transport` interface (A19);
committing a stub before A19 fixes the transport contract is the libdbus failure
P23 cites — retrofitting a shape that does not fit the runtime. Because no public
API claims either name pre-1.0, adding them once async lands is purely additive
(P20). F6's re-export-hub snapshot fails CI if any public module exports
`sendAsync` or `DispatchedRequest` before the async surface lands.
