# Layer 2 Implementation Plan

Layer 1 is complete. Layer 2 adds JSON serialisation/deserialisation for all
Layer 1 types. Full specification: `docs/design/02-layer-2-design.md`.

6 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

Cross-cutting sections apply to all steps: §9 (Opt[T] field handling —
omit-when-none for `toJson`, lenient wrong-kind handling per the per-field
table), §11 (round-trip invariants — 6 properties every ser/de pair must
satisfy), §13.4 (~108 edge-case rows — test coverage targets per type).

---

## Step 1: serde.nim — Shared helpers + primitive/identifier ser/de

**Create:** `src/jmap_client/serde.nim`, `tests/tserde.nim`

**Design doc:** §§1–3, §12.

Implement the 3 shared helpers (`parseError`, `checkJsonKind`,
`collectExtras`) and `toJson`/`fromJson` for all 11 primitive and identifier
types (`Id`, `AccountId`, `JmapState`, `MethodCallId`, `CreationId`,
`UriTemplate`, `PropertyName`, `Date`, `UTCDate`, `UnsignedInt`, `JmapInt`).

---

## Step 2: serde_session.nim — Capabilities + Account + Session

**Create:** `src/jmap_client/serde_session.nim`, `tests/tserde_session.nim`

**Design doc:** §§4–5.

Serialise `CoreCapabilities`, `ServerCapability`, `AccountCapabilityEntry`,
`Account`, and `Session`. Session is the most complex `fromJson` (7-step
composite). Tests include the RFC §2.1 golden example (design doc §13.1).

---

## Step 3: serde_envelope.nim — Invocation, Request, Response

**Create:** `src/jmap_client/serde_envelope.nim`, `tests/tserde_envelope.nim`

**Design doc:** §6.

Serialise `Invocation` (3-element JSON array), `ResultReference`,
`Referencable[T]` (field-level `#`-prefix dispatch), `Request`, and
`Response`. Tests include RFC §3.3.1 Request and §3.4.1 Response examples
(design doc §§13.2–13.3).

---

## Step 4: serde_framework.nim — Filter, Comparator, PatchObject

**Create:** `src/jmap_client/serde_framework.nim`, `tests/tserde_framework.nim`

**Design doc:** §§3.3, §7.

Serialise `FilterOperator` (non-total enum), `Comparator` (with RFC default
for `isAscending`), `Filter[C]` (generic recursive with callbacks),
`PatchObject` (opaque, via smart constructors only), and `AddedItem`.

---

## Step 5: serde_errors.nim — RequestError, MethodError, SetError

**Create:** `src/jmap_client/serde_errors.nim`, `tests/tserde_errors.nim`

**Design doc:** §8.

Serialise `RequestError` (RFC 7807 with extras), `MethodError` (with extras),
and `SetError` (case object with defensive fallback — missing variant data
maps to `setUnknown`). All use `rawType` for lossless round-trip.

---

## Step 6: serialisation.nim — Re-export hub + entry point

**Create:** `src/jmap_client/serialisation.nim`, `tests/tserialisation.nim`
**Update:** `src/jmap_client.nim`

**Design doc:** §12.

`serialisation.nim` imports and re-exports all 5 serde modules (`serde` +
4 domain modules). Update the library entry point to expose Layer 2.
Integration test verifies all `toJson`/`fromJson` pairs are accessible
through the single import.

---
