# Layer 3 Implementation Plan

Layer 2 is complete. Layer 3 adds protocol logic: entity type framework,
request building, response dispatch, and serialisation for all six standard
JMAP methods (RFC 8620 §5.1–5.6) plus Core/echo (§4). Full specification:
`docs/design/03-layer-3-design.md`.

6 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

Cross-cutting sections apply to all steps: §5a (serialisation patterns —
L3-A request `toJson`, L3-B response `fromJson`, L3-C SetResponse merging),
§11 (round-trip invariants — builder identity, response identity, Opt
omission symmetry, Referencable dispatch), §12 (Opt[T] field handling —
omit-when-none for `toJson`, lenient absent/null/wrong-kind for `fromJson`),
§14.6 (66 edge-case rows — test coverage targets per component).

---

## Step 1: Prerequisites — MaxChanges type + Layer 2 enhancements

**Update:** `src/jmap_client/primitives.nim`, `src/jmap_client/serde.nim`,
`src/jmap_client/serde_envelope.nim`, `tests/unit/tprimitives.nim`,
`tests/serde/tserde.nim`, `tests/serde/tserde_envelope.nim`

**Design doc:** §15 (MaxChanges), Decision D3.12, §15 (Referencable conflict).

Add `MaxChanges` distinct type to `primitives.nim` with `parseMaxChanges`
smart constructor (rejects 0). Add `toJson`/`fromJson` for `MaxChanges` to
`serde.nim`. Add `jStr`/`jInt`/`jBool`/`jObj`/`jArr` wrapper funcs to
`serde.nim` (D3.12) and refactor existing primitive `toJson` functions to use
them. Add RFC §3.7 conflict detection to `fromJsonField` in
`serde_envelope.nim` (reject when both `"foo"` and `"#foo"` are present).

---

## Step 2: entity.nim — Entity type framework

**Create:** `src/jmap_client/entity.nim`, `tests/protocol/tentity.nim`

**Design doc:** §4.

`registerJmapEntity` template with `when not compiles` + `{.error.}` for
domain-specific messages. `registerQueryableEntity` for entities supporting
`/query`. Documents the `methodNamespace`/`capabilityUri`/`filterType`
overload interface and `mixin` resolution pattern. Tests use a mock entity
type to verify compile-time registration and missing-overload detection.

---

## Step 3: methods.nim — Request/response types + serialisation

**Create:** `src/jmap_client/methods.nim`, `tests/protocol/tmethods.nim`

**Design doc:** §§5a–8.

12 type definitions (6 request + 6 response), all generic over entity type
`T`. Request `toJson` (Pattern L3-A) for all 6 types. Response `fromJson`
(Pattern L3-B) for all 6 types. `SetResponse` merging algorithm (§8) — parallel
wire maps to unified `Result` maps for create/update/destroy. `CopyResponse`
reuses the create-merging branch; evaluate extracting a shared
`mergeCreateResults` helper per deferred decision R2. All type and field
doc comments must include §5b behavioural semantics and per-method error
notes from the RFC. `fromJson` must apply §5a.4 expected-kinds table and
§5a.5 leniency policy (structurally critical fields strict, supplementary
fields lenient-to-default). Tests include golden tests §14.2 and §14.4
plus all response-type edge cases from §14.6 (GetResponse through
QueryChangesResponse rows).

---

## Step 4: builder.nim — RequestBuilder + add* functions

**Create:** `src/jmap_client/builder.nim`, `tests/protocol/tbuilder.nim`

**Design doc:** §§1–2, §9.

`RequestBuilder` with private fields, `initRequestBuilder`, `build` (pure
snapshot), `nextId` (auto-incrementing call IDs `"c0"`, `"c1"`, ...),
`addCapability` (dedup), `addInvocation` (internal helper with centralised
`{.cast(noSideEffect).}:`). `addEcho` (§9) plus 6 standard `add*` functions
returning `ResponseHandle[ResponseType]`. `addQuery`/`addQueryChanges` take
a `filterConditionToJson` callback (§2.6.6–2.6.7). Tests include golden
test §14.1 and builder edge cases from §14.6.

---

## Step 5: dispatch.nim — ResponseHandle + extraction + references

**Create:** `src/jmap_client/dispatch.nim`, `tests/protocol/tdispatch.nim`

**Design doc:** §§3, 9, 10.

`ResponseHandle[T]` distinct type with borrowed ops. `get[T]` extraction
function with `findInvocation`, error detection (`name == "error"`), and
`validationToMethodError` railway conversion. `echoFromJson` callback (§9).
Generic `reference` constructor plus type-safe convenience functions
`referenceIds`, `referenceListIds`, `referenceAddedIds` (§10). Tests include
golden tests §14.3 and §14.5, and dispatch/reference edge cases from §14.6.

---

## Step 6: protocol.nim — Re-export hub + entry point

**Create:** `src/jmap_client/protocol.nim`
**Update:** `src/jmap_client.nim`

**Design doc:** §13.

`protocol.nim` imports and re-exports all four Layer 3 modules (`entity`,
`methods`, `builder`, `dispatch`). Update the library entry point to expose
Layer 3. Verify all Layer 3 public symbols are accessible through the single
import.

---
