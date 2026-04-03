# Revision Steps: File-by-File Migration Order

Per-file changes to implement the architecture revision described in
`04-architecture-revision.md`. Files are listed in the order they should
be modified — leaf dependencies first, dependents after.

Changes applied to **every** src file (not repeated per file):

- Remove `{.push raises: [].}` (line 4)
- Remove `{.experimental: "strictCaseObjects".}` (line 5, where present)
- Remove `import results`
- Change all `func` to `proc`

---

## Phase 0: Build Configuration

### `config.nims`

- Remove `system.switch("path", ... & "/vendor/nim-results")` (line 10)
- Remove `system.switch("experimental", "strictFuncs")` (line 31)
- Remove `system.switch("experimental", "strictNotNil")` and its
  `nimsuggest` guard (lines 33–36)
- Remove comments referencing nim-results patches, `strictCaseObjects`,
  `Uninit`/`UnsafeSetLen` workarounds (lines 17–21, 52–58)

### `jmap_client.nimble`

- Remove `strictFuncs`, `strictNotNil`, `strictCaseObjects` experimental
  flags
- Remove `Uninit` and `UnsafeSetLen` from warningAsError
- Remove `requires "results == 0.5.1"`

### `vendor/nim-results/`

- Delete the entire directory

---

## Phase 1: Layer 1 — Domain Types

Files are ordered by the internal import DAG: `validation` has no L1
imports, then `primitives` and `identifiers` (import `validation`), then
outward.

### 1. `src/jmap_client/validation.nim`

- Change `ValidationError` from plain `object` to
  `object of CatchableError` — drop `message` field (inherited from
  `CatchableError`), keep `typeName` and `value`
- Change `validationError` helper to construct and return the exception
  object (or replace with a `newValidationError` proc that creates a
  `ref ValidationError`)
- In `defineStringDistinctOps` / `defineIntDistinctOps` templates: change
  `func` to `proc` in the generated borrow bodies

### 2. `src/jmap_client/primitives.nim`

- Remove `{.requiresInit.}` from `Id`, `UnsignedInt`, `JmapInt`, `Date`,
  `UTCDate`, `MaxChanges`
- Add `import std/options` (for `Option[T]`)
- Smart constructors (`parseId`, `parseIdFromServer`, `parseUnsignedInt`,
  `parseJmapInt`, `parseDate`, `parseUtcDate`, `parseMaxChanges`): change
  return type from `Result[T, ValidationError]` to `T`; raise
  `ValidationError` on failure instead of returning `err(...)`
- Internal validation helpers (`validateDatePortion`,
  `validateTimePortion`, etc.): change from `Result[void, ValidationError]`
  to raising on failure
- Remove `?` operator usage — calls to sub-validators simply propagate
  exceptions

### 3. `src/jmap_client/identifiers.nim`

- Remove `{.requiresInit.}` from `AccountId`, `JmapState`,
  `MethodCallId`, `CreationId`
- Smart constructors (`parseAccountId`, `parseJmapState`,
  `parseMethodCallId`, `parseCreationId`): change return type from
  `Result[T, ValidationError]` to `T`; raise on failure
- Remove `?` operator usage

### 4. `src/jmap_client/capabilities.nim`

- Replace `Opt[string]` in `capabilityUri` return type with
  `Option[string]`
- Add `import std/options`

### 5. `src/jmap_client/errors.nim`

- Make `TransportError`, `RequestError`, and `ClientError` inherit from
  `CatchableError` (these are raised by L4 transport, caught by L5)
- `MethodError` and `SetError` remain plain objects (they are response
  data, not control flow)
- Replace all `Opt[T]` with `Option[T]` (`status`, `title`, `detail`,
  `limit`, `extras` on `RequestError`; `description`, `extras` on
  `MethodError` and `SetError`)
- Remove `{.cast(uncheckedAssign).}:` block in `setError` constructor
- Add `import std/options`

### 6. `src/jmap_client/session.nim`

- Remove `{.requiresInit.}` from `UriTemplate`
- `parseUriTemplate`: change return type from
  `Result[UriTemplate, ValidationError]` to `UriTemplate`; raise on failure
- `parseSession`: change return type from
  `Result[Session, ValidationError]` to `Session`; raise on failure
- Replace all `Opt[T]` return types with `Option[T]` (`findCapability`,
  `findCapabilityByUri`, `primaryAccount`, `findAccount`)
- Remove `?` operator usage
- Add `import std/options`

### 7. `src/jmap_client/envelope.nim`

- Replace `rawMethodCallId: string` private field with
  `methodCallId*: MethodCallId` — `{.requiresInit.}` removal makes this
  safe in containers; `initInvocation` remains the construction path
- Replace `Opt[Table[CreationId, Id]]` with
  `Option[Table[CreationId, Id]]` in `Request` and `Response`
- Add `import std/options`

### 8. `src/jmap_client/framework.nim`

- Remove `{.requiresInit.}` from `PropertyName` and `PatchObject`
- Replace `rawProperty: string` private field in `Comparator` with
  `property*: PropertyName` — remove the `property()` accessor proc
- Replace `rawId: string` / `rawIndex: int64` private fields in
  `AddedItem` with `id*: Id` / `index*: UnsignedInt` — remove the `id()`
  and `index()` accessor procs; remove `initAddedItem` (direct
  construction now possible)
- `parsePropertyName`, `parseComparator`, `setProp`, `deleteProp`: change
  return types from `Result[T, ...]` to `T`; raise on failure
- Replace `Opt[string]` in `Comparator.collation` and `Opt[JsonNode]`
  in `getKey` return type with `Option` equivalents
- Add `import std/options`

### 9. `src/jmap_client/entity.nim`

- Remove the `{.noSideEffect, raises: [].}` annotations on the expected
  proc signatures documented in comments
- No other structural changes (compile-time registration templates remain)

### 10. `src/jmap_client/types.nim`

- Remove `import results`
- Remove `JmapResult[T] = Result[T, ClientError]` type alias
- Add `import std/options` (re-exported for downstream)

---

## Phase 2: Layer 2 — Serialisation

### 11. `src/jmap_client/serde.nim`

- Remove `initResultErr` helper entirely
- Remove `checkJsonKind` template (no longer needed — exceptions from
  `node["key"]` and kind mismatches propagate naturally)
- Remove `jStr`, `jInt`, `jBool`, `jObj`, `jArr` wrapper procs — replace
  all call sites with `%`, `newJObject()`, `newJArray()` directly
- Remove all `{.cast(noSideEffect).}:` blocks
- `parseError` helper: change to raise `ValidationError` instead of
  returning one (or remove if `newValidationError` from `validation.nim`
  suffices)
- `collectExtras`: change return type from `Opt[JsonNode]` to
  `Option[JsonNode]`
- All `toJson` procs: use `%` and `newJString()` directly (no wrappers)
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`; call smart constructors directly
  (they now raise on failure); use `node["key"]` for required fields
- Remove `?` operator usage throughout
- Add `import std/options`

### 12. `src/jmap_client/serde_session.nim`

- Remove all `{.cast(noSideEffect).}:` blocks (7 occurrences)
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`
- Replace `?` with direct calls (exceptions propagate)
- Replace `node{"key"}` with `node["key"]` for required fields; keep
  `node{"key"}` or `hasKey` pattern for optional fields
- Replace `Opt` with `Option` where used
- Use `%*{...}` directly in `toJson` procs (no `{.cast.}` needed)

### 13. `src/jmap_client/serde_envelope.nim`

- Remove all `{.cast(noSideEffect).}:` blocks
- Remove `initResultErr` call sites
- Remove `parseResponseCore` tuple-packing helper — construct `Response`
  directly in `fromJson`
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`
- `fromJsonField` for `Referencable[T]`: change proc parameter type from
  `proc(...): Result[T, ValidationError] {.noSideEffect, raises: [].}` to
  `proc(...): T` — the callback now raises on failure instead of returning
  `Result`
- Replace `?` with direct calls
- Replace `Opt` with `Option`

### 14. `src/jmap_client/serde_framework.nim`

- Remove all `{.cast(noSideEffect).}:` blocks
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`
- `toJson` for `Filter[C]` and `fromJson` / `fromJsonImpl` for
  `Filter[C]`: change proc parameter types from
  `proc(...): JsonNode {.noSideEffect, raises: [].}` and
  `proc(...): Result[C, ValidationError] {.noSideEffect, raises: [].}` to
  plain `proc(...): JsonNode` and `proc(...): C`
- Replace `?` with direct calls
- Replace `Opt` with `Option`

### 15. `src/jmap_client/serde_errors.nim`

- Remove all `{.cast(noSideEffect).}:` blocks
- `optString` / `optInt` internal helpers: change return type from
  `Opt[T]` to `Option[T]`
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`
- Replace `?` with direct calls
- Replace `Opt` with `Option`

### 16. `src/jmap_client/serialisation.nim`

- No changes beyond the universal pragma/import removals (this is a
  re-export hub)

---

## Phase 3: Layer 3 — Protocol Logic

### 17. `src/jmap_client/methods.nim`

- Remove all `{.cast(noSideEffect).}:` blocks
- Remove `initResultErr` call sites (10+ occurrences)
- Remove `*Core` tuple-packing helper procs (`parseGetResponseCore`,
  `parseChangesResponseCore`, `parseSetResponseCore`,
  `parseCopyResponseCore`, `parseQueryResponseCore`,
  `parseQueryChangesResponseCore`) — construct response objects directly
  in each `fromJson`
- Remove `optState` / `optUnsignedInt` internal helpers (replace with
  `Option`-returning equivalents or inline the logic)
- All `fromJson` procs: change return type from
  `Result[T, ValidationError]` to `T`
- All `toJson` procs with proc parameters: change from
  `proc(...): JsonNode {.noSideEffect, raises: [].}` to
  `proc(...): JsonNode`
- `SetResponse[T]` and `CopyResponse[T]`: the `createResults`,
  `updateResults`, `destroyResults` fields currently use
  `Result[JsonNode, SetError]` — these represent per-item outcomes in the
  JMAP response; replace with a dedicated type or keep `Result` from
  nim-results for this one use case. **Alternative**: define a simple
  `ItemResult[T] = object` case variant or use `Either[T, SetError]`
  locally. The simplest approach: keep per-item results as
  `Table[CreationId, JsonNode]` (successes) and
  `Table[CreationId, SetError]` (failures) as separate fields — mirroring
  the wire format directly (§3.9A from `00-architecture.md`)
- Replace all `Opt[T]` with `Option[T]` in request/response type fields
- Replace `?` with direct calls throughout
- Add `import std/options`

---

## Phase 4: Entry Point

### 18. `src/jmap_client.nim`

- **Keep** `{.push raises: [].}` (this is the Layer 5 boundary)
- Remove `import results` (no longer needed)
- Confirm re-exports of `types` and `serialisation` still compile
