# Layer 1 Implementation Plan

9 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

**Prerequisite:** `mkdir -p src/jmap_client` and `nimble install -d --accept`.

**Reference documents:**
- `docs/design/layer-1-design.md` — full specification (types, constructors, edge cases)
- `docs/design/architecture.md` — governing decisions
- `.claude/rules/nim-conventions.md` — module boilerplate, import ordering

**File header (every `.nim` file):**

```nim
# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
```

---

## Step 1: validation.nim + scaffolding

**Create:** `src/jmap_client/validation.nim`, `src/jmap_client/types.nim` (stub),
`src/jmap_client.nim` (entry point)
**Test:** `tests/tvalidation.nim`

### validation.nim

Design doc §1.

- `ValidationError*` object — `typeName`, `message`, `value` (all `string`)
- `func validationError*(typeName, message, value: string): ValidationError`
- `template defineStringDistinctOps*(T: typedesc)` — borrows `==`, `$`, `hash`, `len`
- `template defineIntDistinctOps*(T: typedesc)` — borrows `==`, `<`, `<=`, `$`, `hash`
- `const Base64UrlChars*`, `const AsciiDigits*`

### types.nim (stub)

```nim
import ./validation
export validation
```

### src/jmap_client.nim

```nim
import jmap_client/types
export types
```

### tvalidation.nim

- `validationError` constructor: fields match inputs
- `defineStringDistinctOps`: create a local `distinct string`, verify `==`, `$`, `hash`, `len`
- `defineIntDistinctOps`: create a local `distinct int64`, verify `==`, `<`, `<=`, `$`, `hash`
- `Base64UrlChars`: `'A' in`, `'=' notin`, `'+' notin`

**Verify:** `just ci`

---

## Step 2: primitives.nim

**Create:** `src/jmap_client/primitives.nim`
**Test:** `tests/tprimitives.nim`
**Update:** `types.nim` — add `import ./primitives; export primitives`

Design doc §2.

### Types

- `Id* {.requiresInit.} = distinct string` + `defineStringDistinctOps`
- `UnsignedInt* {.requiresInit.} = distinct int64` + `defineIntDistinctOps`
- `JmapInt* {.requiresInit.} = distinct int64` + `defineIntDistinctOps` + borrow unary `-`
- `Date* {.requiresInit.} = distinct string` + `defineStringDistinctOps`
- `UTCDate* {.requiresInit.} = distinct string` + `defineStringDistinctOps`

### Constants

- `MaxUnsignedInt*: int64 = 9_007_199_254_740_991'i64`
- `MinJmapInt*`, `MaxJmapInt*`

### Smart constructors

- `parseId` — strict: 1-255 octets, base64url charset
- `parseIdFromServer` — lenient: 1-255 octets, no control chars
- `parseUnsignedInt` — 0..2^53-1
- `parseJmapInt` — -(2^53-1)..2^53-1
- `parseDate` — RFC 3339 structural validation (T separator, uppercase, fractional seconds rules)
- `parseUtcDate` — Date rules + must end with `Z`

### tprimitives.nim — edge cases (design doc §12.4)

| Constructor | Input | Expected |
|-------------|-------|----------|
| `parseId` | `""` | err |
| `parseId` | 256 chars | err |
| `parseId` | 255 chars | ok |
| `parseId` | `"abc123-_XYZ"` | ok |
| `parseId` | `"abc=def"` | err |
| `parseId` | `"abc def"` | err |
| `parseIdFromServer` | `"abc+def"` | ok |
| `parseIdFromServer` | `"abc\x00def"` | err |
| `parseUnsignedInt` | `0` | ok |
| `parseUnsignedInt` | `MaxUnsignedInt` | ok |
| `parseUnsignedInt` | `-1` | err |
| `parseUnsignedInt` | `MaxUnsignedInt + 1` | err |
| `parseJmapInt` | `MinJmapInt` | ok |
| `parseJmapInt` | `MaxJmapInt` | ok |
| `parseDate` | `"2014-10-30T14:12:00+08:00"` | ok |
| `parseDate` | `"2014-10-30T14:12:00.123Z"` | ok |
| `parseDate` | lowercase `t` | err |
| `parseDate` | `.000Z` (zero frac) | err |
| `parseDate` | `.Z` (empty frac) | err |
| `parseDate` | `.0Z` (zero frac) | err |
| `parseDate` | `.100Z` (trailing zero) | ok |
| `parseDate` | lowercase `z` | err |
| `parseDate` | `"2014-10-30"` (too short) | err |
| `parseUtcDate` | `"2014-10-30T06:12:00Z"` | ok |
| `parseUtcDate` | `"2014-10-30T06:12:00+00:00"` | err |

Also: verify borrowed ops (`==`, `$`, `hash`, `len`) on `Id`, `Date`, `UTCDate`; verify
`==`, `<`, `<=`, `$`, `hash` and unary `-` on `UnsignedInt`, `JmapInt`.

**Verify:** `just ci`

---

## Step 3: identifiers.nim

**Create:** `src/jmap_client/identifiers.nim`
**Test:** `tests/tidentifiers.nim`
**Update:** `types.nim` — add `import ./identifiers; export identifiers`

Design doc §3.

### Types (all `{.requiresInit.} = distinct string`)

- `AccountId*` — `defineStringDistinctOps` (has `len`)
- `JmapState*` — manual borrows: `==`, `$`, `hash` only (no `len`)
- `MethodCallId*` — manual borrows: `==`, `$`, `hash` only (no `len`)
- `CreationId*` — manual borrows: `==`, `$`, `hash` only (no `len`)

### Smart constructors

- `parseAccountId` — lenient: 1-255, no control chars
- `parseJmapState` — non-empty, no control chars
- `parseMethodCallId` — non-empty
- `parseCreationId` — non-empty, no `#` prefix

### tidentifiers.nim — edge cases (design doc §12.4)

| Constructor | Input | Expected |
|-------------|-------|----------|
| `parseAccountId` | `""` | err |
| `parseAccountId` | `"A13824"` | ok |
| `parseAccountId` | 256 chars | err |
| `parseAccountId` | 255 chars | ok |
| `parseAccountId` | `"abc\x00def"` | err |
| `parseJmapState` | `""` | err |
| `parseJmapState` | `"75128aab4b1b"` | ok |
| `parseJmapState` | `"abc\x00def"` | err |
| `parseMethodCallId` | `""` | err |
| `parseMethodCallId` | `"c1"` | ok |
| `parseCreationId` | `""` | err |
| `parseCreationId` | `"#abc"` | err |
| `parseCreationId` | `"abc"` | ok |

Verify `JmapState`, `MethodCallId`, `CreationId` do NOT have `len` (compile-time check
or just verify the ops that should work).

**Verify:** `just ci`

---

## Step 4: capabilities.nim

**Create:** `src/jmap_client/capabilities.nim`
**Test:** `tests/tcapabilities.nim`
**Update:** `types.nim` — add `import ./capabilities; export capabilities`

Design doc §4.

### Types

- `CapabilityKind*` enum — string-backed, 12 IANA variants + `ckUnknown`
- `CoreCapabilities*` object — 7 `UnsignedInt` fields + `collationAlgorithms: HashSet[string]`
- `ServerCapability*` case object — `rawUri: string`, discriminated by `CapabilityKind`
  (`ckCore` → `core: CoreCapabilities`; `else` → `rawData: JsonNode`)

### Functions

- `func parseCapabilityKind*(uri: string): CapabilityKind` — total via `parseEnum`
- `func capabilityUri*(kind: CapabilityKind): Opt[string]` — `err()` for `ckUnknown`
- `func hasCollation*(caps: CoreCapabilities, algorithm: string): bool`

### tcapabilities.nim — edge cases (design doc §12.4)

| Input | Expected |
|-------|----------|
| `parseCapabilityKind("urn:ietf:params:jmap:core")` | `ckCore` |
| `parseCapabilityKind("urn:ietf:params:jmap:mail")` | `ckMail` |
| `parseCapabilityKind("https://vendor.example/ext")` | `ckUnknown` |
| `parseCapabilityKind("")` | `ckUnknown` |
| `capabilityUri(ckCore)` | `ok("urn:ietf:params:jmap:core")` |
| `capabilityUri(ckUnknown)` | `err()` |

Also: construct `CoreCapabilities` with `HashSet`, verify `hasCollation`; construct
`ServerCapability` in both branches, verify field access.

**Verify:** `just ci`

---

## Step 5: errors.nim

**Create:** `src/jmap_client/errors.nim`
**Test:** `tests/terrors.nim`
**Update:** `types.nim` — add `import ./errors; export errors`; add
`type JmapResult*[T] = Result[T, ClientError]`

Design doc §8.

### Types

- `TransportErrorKind*` enum (4 variants, no string backing)
- `TransportError*` case object — shared `message: string`; `tekHttpStatus` → `httpStatus: int`
- `RequestErrorType*` enum (4 string-backed + `retUnknown`)
- `RequestError*` flat object — `errorType`, `rawType`, `status/title/detail/limit/extras` as `Opt`
- `ClientErrorKind*` enum (2 variants)
- `ClientError*` case object — `cekTransport` / `cekRequest`
- `MethodErrorType*` enum (19 string-backed + `metUnknown`)
- `MethodError*` flat object — `errorType`, `rawType`, `description`, `extras`
- `SetErrorType*` enum (10 string-backed + `setUnknown`)
- `SetError*` case object — shared `rawType`, `description`, `extras`;
  `setInvalidProperties` → `properties: seq[string]`;
  `setAlreadyExists` → `existingId: Id`

### Functions

- `parseRequestErrorType`, `parseMethodErrorType`, `parseSetErrorType` — total via `parseEnum`
- `transportError`, `httpStatusError` — direct constructors
- `requestError` — lossless round-trip (populates both `errorType` and `rawType`)
- `clientError` (2 overloads), `message` accessor
- `methodError` — lossless round-trip
- `setError` — generic with defensive fallback for `setInvalidProperties`/`setAlreadyExists`
- `setErrorInvalidProperties`, `setErrorAlreadyExists` — variant-specific constructors

### terrors.nim — edge cases (design doc §12.4)

Enum parsers:
- Known strings → correct variant; unknown strings → `*Unknown`; empty → `*Unknown`
- All 19 `MethodErrorType` known strings

Constructors:
- `transportError(tekTimeout, "timed out")` → `kind == tekTimeout`
- `httpStatusError(502, "Bad Gateway")` → `httpStatus == 502`
- `requestError("urn:ietf:params:jmap:error:limit", limit = ok("maxCallsInRequest"))` → `errorType == retLimit`, rawType preserved
- `requestError("urn:vendor:custom")` → `errorType == retUnknown`, rawType preserved
- `clientError` both overloads, `message()` accessor
- `methodError("unknownMethod")` → `errorType == metUnknownMethod`
- `methodError("custom", extras = ...)` → `errorType == metUnknown`, extras preserved
- `setError("forbidden")` → `errorType == setForbidden`
- `setErrorInvalidProperties("invalidProperties", @["name"])` → variant correct
- `setErrorAlreadyExists("alreadyExists", someId)` → variant correct
- `setError("invalidProperties")` (no properties) → `errorType == setUnknown` (defensive fallback)
- `setError("alreadyExists")` (no existingId) → `errorType == setUnknown` (defensive fallback)

**Verify:** `just ci`

---

## Step 6: framework.nim

**Create:** `src/jmap_client/framework.nim`
**Test:** `tests/tframework.nim`
**Update:** `types.nim` — add `import ./framework; export framework`

Design doc §7.

### Types

- `PropertyName* {.requiresInit.} = distinct string` + `defineStringDistinctOps`
- `FilterOperator*` enum (`foAnd = "AND"`, `foOr = "OR"`, `foNot = "NOT"`)
- `FilterKind*` enum (`fkCondition`, `fkOperator`)
- `Filter*[C]` generic case object — recursive via `seq[Filter[C]]`
- `Comparator*` object — `property: PropertyName`, `isAscending: bool`, `collation: Opt[string]`
- `PatchObject* {.requiresInit.} = distinct Table[string, JsonNode]` — borrow `len` only
- `AddedItem*` object — `id: Id`, `index: UnsignedInt`

### Functions

- `parsePropertyName` — non-empty
- `filterCondition[C]`, `filterOperator[C]` — total constructors
- `parseComparator` — infallible given valid `PropertyName`
- `emptyPatch`, `setProp`, `deleteProp` — PatchObject smart constructors

### tframework.nim — edge cases (design doc §12.4)

| Test | Expected |
|------|----------|
| `parsePropertyName("")` | err |
| `parsePropertyName("name")` | ok |
| `filterCondition` / `filterOperator` | construct and verify kind; recursive nesting compiles |
| `parseComparator` with valid PropertyName | ok, `isAscending == true` (default) |
| `parseComparator` with collation | ok, collation accessible |
| `emptyPatch().len` | `0` |
| `setProp(emptyPatch(), "", ...)` | err |
| `setProp(emptyPatch(), "name", ...)` | ok, `len == 1` |
| `deleteProp(emptyPatch(), "addresses/0")` | ok |
| Chained `setProp` calls | entries accumulate |

**Verify:** `just ci`

---

## Step 7: envelope.nim

**Create:** `src/jmap_client/envelope.nim`
**Test:** `tests/tenvelope.nim`
**Update:** `types.nim` — add `import ./envelope; export envelope`

Design doc §6.

### Types

- `Invocation*` object — `name: string`, `arguments: JsonNode`, `methodCallId: MethodCallId`
- `Request*` object — `using: seq[string]`, `methodCalls: seq[Invocation]`,
  `createdIds: Opt[Table[CreationId, Id]]`
- `Response*` object — `methodResponses: seq[Invocation]`,
  `createdIds: Opt[Table[CreationId, Id]]`, `sessionState: JmapState`
- `ResultReference*` object — `resultOf: MethodCallId`, `name: string`, `path: string`
- `ReferencableKind*` enum, `Referencable*[T]` generic case object

### Constants

`RefPathIds*`, `RefPathListIds*`, `RefPathAddedIds*`, `RefPathCreated*`,
`RefPathUpdated*`, `RefPathUpdatedProperties*`

### Functions

- `func direct*[T](value: T): Referencable[T]`
- `func referenceTo*[T](reference: ResultReference): Referencable[T]`

### tenvelope.nim

- Construct `Invocation`, verify fields
- Construct `Request` with/without `createdIds`
- Construct `Response`, verify `sessionState`, `createdIds.isNone`
- `ResultReference` construction, verify fields
- Path constants have expected values
- `direct(value)` → `kind == rkDirect`
- `referenceTo[seq[Id]](ref)` → `kind == rkReference`
- `Referencable` works with concrete type parameters

**Verify:** `just ci`

---

## Step 8: session.nim

**Create:** `src/jmap_client/session.nim`
**Test:** `tests/tsession.nim`
**Update:** `types.nim` — add `import ./session; export session`

Design doc §5.

### Types

- `AccountCapabilityEntry*` object — `kind: CapabilityKind`, `rawUri: string`, `data: JsonNode`
- `Account*` object — `name`, `isPersonal`, `isReadOnly`, `accountCapabilities: seq[AccountCapabilityEntry]`
- `UriTemplate* {.requiresInit.} = distinct string` + `defineStringDistinctOps`
- `Session*` object — all fields per design doc §5.3

### Functions

- `parseUriTemplate` — non-empty
- `hasVariable` — string search for `{name}`
- Account helpers: `findCapability`, `findCapabilityByUri`, `hasCapability`
- `parseSession` — validates: ckCore present, apiUrl non-empty, downloadUrl has 4 vars,
  uploadUrl has `{accountId}`, eventSourceUrl has 3 vars
- `coreCapabilities` — total over `parseSession` output, `raiseAssert` on invariant violation
- Session helpers: `findCapability`, `findCapabilityByUri`, `primaryAccount`, `findAccount`

### tsession.nim — edge cases (design doc §12.4)

Build test helpers to construct valid sub-components.

| Test | Expected |
|------|----------|
| `parseUriTemplate("")` | err |
| `parseUriTemplate("https://...")` | ok |
| `hasVariable(tmpl, "accountId")` | true |
| `hasVariable(tmpl, "nonexistent")` | false |
| Account `findCapability(account, ckMail)` | ok |
| Account `findCapabilityByUri(account, "urn:ietf:params:jmap:mail")` | ok |
| `parseSession` missing ckCore | err |
| `parseSession` empty apiUrl | err |
| `parseSession` downloadUrl missing `{blobId}` | err |
| `parseSession` uploadUrl missing `{accountId}` | err |
| `parseSession` eventSourceUrl missing `{types}` | err |
| Valid session (RFC §2.1 example shape) | ok |
| `coreCapabilities(validSession)` | returns `CoreCapabilities` |
| `findCapabilityByUri(session, "https://example.com/apis/foobar")` | ok, `kind == ckUnknown` |
| `findCapabilityByUri(session, "urn:nonexistent")` | err |
| `primaryAccount(session, ckMail)` | `ok(AccountId("A13824"))` |
| `primaryAccount(session, ckUnknown)` | err |
| `primaryAccount(session, ckBlob)` | err |
| `findAccount(session, AccountId("A13824"))` | ok |
| `findAccount(session, AccountId("nonexistent"))` | err |

**Verify:** `just ci`

---

## Step 9: types.nim finalisation + ttypes.nim

**Update:** `src/jmap_client/types.nim` to final form
**Test:** `tests/ttypes.nim`

### Final types.nim

```nim
import pkg/results
import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope
import ./framework
import ./errors

export validation, primitives, identifiers, capabilities,
       session, envelope, framework, errors

type JmapResult*[T] = Result[T, ClientError]
```

### ttypes.nim

- Import only `jmap_client/types`, verify all public types accessible through re-export
- `JmapResult[Response].ok(resp).isOk`
- `JmapResult[Response].err(clientErr).isErr`
- Cross-module composition: `Response` containing `Invocation` values, wrapped in `JmapResult`
- `?` operator works across the `JmapResult` railway

**Verify:** `just ci`

---

## Summary

| Step | Module | Key Types | Depends On |
|------|--------|-----------|------------|
| 1 | `validation` | `ValidationError`, borrow templates | — |
| 2 | `primitives` | `Id`, `UnsignedInt`, `JmapInt`, `Date`, `UTCDate` | validation |
| 3 | `identifiers` | `AccountId`, `JmapState`, `MethodCallId`, `CreationId` | validation |
| 4 | `capabilities` | `CapabilityKind`, `CoreCapabilities`, `ServerCapability` | primitives |
| 5 | `errors` | `TransportError`, `RequestError`, `ClientError`, `MethodError`, `SetError` | primitives |
| 6 | `framework` | `PropertyName`, `Filter[C]`, `Comparator`, `PatchObject`, `AddedItem` | primitives |
| 7 | `envelope` | `Invocation`, `Request`, `Response`, `ResultReference`, `Referencable[T]` | identifiers, primitives |
| 8 | `session` | `Account`, `UriTemplate`, `Session` | identifiers, capabilities |
| 9 | `types` | `JmapResult[T]` (re-export hub) | all |

Each step: create source + test, update `types.nim`, run `just ci`, commit.
