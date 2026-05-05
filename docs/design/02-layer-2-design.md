# Layer 2: Serialisation — Detailed Design (RFC 8620)

## Preface

This document specifies every `toJson`/`fromJson` pair, the parse boundary,
and the module layout for Layer 2 of the jmap-client library. It builds upon
the decisions made in `00-architecture.md` and the types defined in
`01-layer-1-design.md` so that implementation is mechanical.

**Scope.** Layer 2 covers: JSON serialisation and deserialisation for all
Layer 1 types — primitive data types (RFC 8620 §1.2–1.4), the Session object
and everything it contains (§2), the Request/Response envelope (§3.2–3.4,
§3.7), request-level and method-level errors (§3.6), the generic method
framework types (§5.5 Filter/Comparator, §5.6 AddedItem), and per-item set
errors (§5.3, §5.4, RFC 8621 §4.6 / §7.5). Protocol logic (Layer 3),
transport (Layer 4), and the C ABI (Layer 5) are out of scope. Binary data
(§6) and push (§7) are deferred; see architecture.md §4.5–4.6.

**Design principles.** Every decision follows:

- **Structured violation rail** — `fromJson` returns
  `Result[T, SerdeViolation]`. `SerdeViolation` is a sum type with nine
  variants (wrong kind, nil node, missing field, empty required, array
  length, field-parser failure, conflicting fields, unrecognised enum,
  depth exceeded), each carrying a structured `JsonPath` (RFC 6901 JSON
  Pointer) plus variant-specific payload. A single translator,
  `toValidationError`, projects a `SerdeViolation` to the wire
  `ValidationError` shape at the L3/L4 boundary.
- **Layer 1 compose via `wrapInner`** — Layer 1 smart constructors return
  `Result[T, ValidationError]`. The `wrapInner` combinator lifts that
  error into an `svkFieldParserFailed` violation tagged with the current
  `JsonPath`, preserving the inner `typeName` and `value` losslessly. The
  `?` operator then propagates seamlessly through nested deserialisers —
  no `try/except`, no `mapErr`, no exception hierarchy.
- **Path threading** — Every `fromJson` accepts a `JsonPath` parameter
  (default `emptyJsonPath()`). As deserialisation descends into nested
  objects and arrays, the path is extended via the `/` operator
  (`path / key`, `path / idx`). The translator renders the final path as
  an RFC 6901 pointer (`""` for the root, `/foo/0/bar` otherwise) and
  appends `" at <pointer>"` to the error message.
- **Compiler-enforced purity and totality** — Every Layer 2 source module
  starts with `{.push raises: [], noSideEffect.}` and
  `{.experimental: "strictCaseObjects".}`. All routines are `func`. The
  `proc` keyword is reserved for Layer 4/5; callback-typed parameters use
  `{.noSideEffect, raises: [].}` annotations on the proc type so they
  remain callable from inside `func` bodies.
- **Immutability by default** — `let` bindings throughout. Local `var`
  is permitted only inside a `func` for building a return value from
  stdlib containers whose APIs require mutation (e.g.,
  `var node = newJObject(); node["key"] = val`). The mutation is not
  observable to the caller, so the function remains pure by the pragma.
- **Total functions** — Every `fromJson` validates `JsonNodeKind` before
  extraction via the `expectKind` combinator (which returns
  `err(svkWrongKind|svkNilNode)` on mismatch). `getStr`,
  `getBiggestInt`, `getBool`, `getFloat` silently return defaults on
  wrong kinds, which would produce incorrect values rather than errors.
  The canonical pattern is: check `node.kind`, return `err` on mismatch,
  then extract.
- **Parse, don't validate** — `fromJson` produces well-typed values by
  calling Layer 1 smart constructors via `wrapInner`, or returns a
  structured `SerdeViolation`. Every `fromJson` that produces a Layer 1
  type with a smart constructor MUST call it (never direct object
  construction bypassing validation). Types without smart constructors
  (`Account`, `CoreCapabilities`) are constructed directly after
  validating each field individually.
- **Make illegal states unrepresentable** — deserialisation constructs
  Layer 1 types via their smart constructors, never bypassing
  invariants. Distinct types require explicit unwrap (`string(id)`) for
  `toJson` and explicit wrap via smart constructor for `fromJson`.
- **Dual validation strictness** — server-originated data uses lenient
  constructors (`parseIdFromServer`, `parseAccountId`); client-originated
  data uses strict constructors (`parseId`). Each `fromJson` documents
  which constructor it calls.
- **I-JSON compliance** — all serialised output is valid I-JSON
  (RFC 7493). `std/json` produces I-JSON by default (UTF-8, no duplicate
  keys via `%*{}`).

**Compiler flags.** These constrain every function definition (from
`config.nims`):

```
--mm:arc
--experimental:strictDefs
--panics:on
```

Every Layer 2 module pushes `raises: [], noSideEffect` at the top — the
compiler enforces that no `CatchableError` can escape any function and
that all routines are pure. `{.experimental: "strictCaseObjects".}` is
also enabled per-module so that variant-field reads must occur inside a
`case` arm whose discriminator literal matches the field's declaration.

---

## Standard Library Utilisation

Layer 2 maximises use of the Nim standard library. Every adoption and
rejection has a concrete reason.

### Modules used in Layer 2

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/json` | `%`, `%*`, `newJObject`, `newJArray`, `newJNull`, `{key}` accessor, `getStr`, `getBiggestInt`, `getBool`, `getElems`, `pairs`, `JsonNodeKind` | Layer 1 selectively imports `JsonNode`/`JsonNodeKind` as data types only; Layer 2 needs the accessors and construction API. `parseJson` is NOT used — the `string → JsonNode` boundary is a Layer 4 concern |
| `std/strutils` | `replace` for RFC 6901 pointer escaping | Used by `jsonPointerEscape` in `serde.nim` |
| `std/tables` | `Table` iteration via `pairs`, construction via `[]=`, `initTable` | Session accounts, primaryAccounts, createdIds, generic `parseKeyedTable` ser/de |
| `std/sets` | `toHashSet` | `CoreCapabilities.collationAlgorithms`: JSON array → `HashSet[CollationAlgorithm]` |

nim-results (`Opt[T]`, `Result[T, E]`, `?` operator, `valueOr:`) is used
throughout for optional fields and error handling. It is imported
transitively via Layer 1's `types.nim`.

### Modules evaluated and rejected

| Module | Reason not used in Layer 2 |
|--------|---------------------------|
| `std/options` | Replaced by `Opt[T]` from nim-results. `Opt[T]` is `Result[T, void]`, sharing the full Result API (`?`, `valueOr:`, `map`, `flatMap`, iterators). Consistent with Layer 1's `Opt[T]` usage throughout. |
| `std/jsonutils` | `jsonTo` and the stdlib `fromJson` raise exceptions (`KeyError`, `JsonKindError`) that do not carry structured context. Layer 2 needs `SerdeViolation` with its structured fields and JSON path for diagnostic quality. |
| `std/marshal` | Deprecated; uses `streams`; incompatible with `--mm:arc`. |
| `jsony` (third-party) | Third-party dependency; project has zero-dependency policy. |
| `std/sugar` | `collect` not needed at this layer — Layer 2 builds sequences via `var` + `add` loop, which is clearer for the kind-check-then-extract pattern threaded with structured paths. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `node{key}` returns `nil` on missing key (raises-free) | Primary navigation accessor throughout Layer 2. Always nil-safe. Chaining `node{"a"}{"b"}.getStr("")` is safe — returns `""` if any level is missing. |
| `node["key"]` raises `KeyError` | NOT used — Layer 2 uses `node{"key"}` + `expectKind` / `fieldOfKind` for structured error context. |
| `getInt` returns `int` (pointer-sized); `getBiggestInt` returns `BiggestInt` (`int64`) | `UnsignedInt` and `JmapInt` are `distinct int64` — must use `getBiggestInt` to avoid truncation on 32-bit platforms. |
| `%` on distinct types does not auto-unwrap | Must explicitly unwrap: `%string(id)`, `%int64(val)`. The `%` operator has overloads for `string`, `int64`, `float`, `bool`, `seq[T]`, `Table[K,V]`, and `Option[T]` (note: this project uses `Opt[T]` from nim-results, not `std/options`). |
| `$` on string-backed enum returns the backing string; catch-all variants without backing return the symbolic name | `$ckCore` → `"urn:ietf:params:jmap:core"` but `$ckUnknown` → `"ckUnknown"` (not a URI). Serialisation must use `rawUri`/`rawType`/`rawName` from the containing object for lossless round-trip, never `$enumVal` for catch-all-bearing enums. |
| `node.len` is NOT nil-safe — crashes on nil with `FieldDefect` | Always check `isNil` before `.len`. The `expectLen` combinator assumes the caller has already checked `JArray` kind. |
| `items`/`pairs`/`keys` iterators assert node kind | Assert `JArray` for `items`, `JObject` for `pairs`/`keys`. The assert produces `AssertionDefect` (a `Defect`, not tracked by `raises`). Always check `node.kind` before iterating. |
| `getElems(@[])` returns empty defaults on nil or wrong kind | Safe to call after a kind check — `for i, elem in arr.getElems(@[])` enumerates indices for path threading even when the array is empty. |
| `parseJson(string)` raises `JsonParsingError` (a `ValueError` descendant); `parseFile` additionally raises `IOError` | NOT used in Layer 2. The `string → JsonNode` boundary requires exception handling and is a Layer 4 concern. Layer 2 receives only pre-parsed `JsonNode` trees. |
| `node.copy()` produces a deep clone | Used by `ServerCapability` and `AccountCapabilityEntry` to prevent ARC double-free on shared `JsonNode` refs. |

---

## 1. Deserialisation Infrastructure

### 1.1 Error Type: `SerdeViolation`

Layer 2's `fromJson` functions return `Result[T, SerdeViolation]`.
`SerdeViolation` is a structured ADT defined in `serde.nim`:

```nim
type SerdeViolationKind* = enum
  svkWrongKind          ## Node present but the wrong JsonNodeKind.
  svkNilNode            ## Node absent where one was required (top-level only).
  svkMissingField       ## Required object field not present.
  svkEmptyRequired      ## Wire-boundary non-empty invariant violated.
  svkArrayLength        ## Array had the wrong number of elements.
  svkFieldParserFailed  ## An inner smart constructor rejected the value.
  svkConflictingFields  ## Two mutually-exclusive fields both present.
  svkEnumNotRecognised  ## Token outside the enum's accepted set.
  svkDepthExceeded      ## Recursive nesting exceeded the stack-safety cap.

type SerdeViolation* = object
  path*: JsonPath
  case kind*: SerdeViolationKind
  of svkWrongKind:
    expectedKind*: JsonNodeKind
    actualKind*: JsonNodeKind
  of svkNilNode:
    expectedKindForNil*: JsonNodeKind
  of svkMissingField:
    missingFieldName*: string
  of svkEmptyRequired:
    emptyFieldLabel*: string
  of svkArrayLength:
    expectedLen*: int
    actualLen*: int
  of svkFieldParserFailed:
    inner*: ValidationError
  of svkConflictingFields:
    conflictKeyA*: string
    conflictKeyB*: string
    conflictRule*: string
  of svkEnumNotRecognised:
    enumTypeLabel*: string
    rawValue*: string
  of svkDepthExceeded:
    maxDepth*: int
```

Every variant carries a `path: JsonPath` so the violation locates itself
inside the wire tree. Layer 1 smart-constructor failures are wrapped via
`wrapInner` into `svkFieldParserFailed`, preserving the inner
`ValidationError` losslessly so the original `typeName`, `message`, and
`value` survive the bridge.

Adding a new violation kind forces a compile error in
`toValidationError` (the sole translator) and nowhere else — the
exhaustive `case` is the spine of Layer 2's error rail.

**Module:** `src/jmap_client/serde.nim`

### 1.2 `JsonPath` — Structured RFC 6901 Pointer

Every `fromJson` threads a `JsonPath` so violations carry their location
verbatim:

```nim
type JsonPathElementKind* = enum
  jpeKey
  jpeIndex

type JsonPathElement* = object
  case kind*: JsonPathElementKind
  of jpeKey:
    key*: string
  of jpeIndex:
    idx*: int

type JsonPath* = distinct seq[JsonPathElement]

func emptyJsonPath*(): JsonPath
func `/`*(p: JsonPath, key: string): JsonPath  ## extend with object key
func `/`*(p: JsonPath, idx: int): JsonPath     ## extend with array index
func `$`*(p: JsonPath): string                 ## render as RFC 6901 string
```

`$path` produces an RFC 6901 JSON Pointer: `""` for the root, otherwise
a leading `/` per segment with `~` escaped to `~0` and `/` escaped to
`~1` (escape order matters — `~` first, then `/`). Index segments render
as the decimal index. Object-key segments render the escaped key.

Composition is purely functional: `path / "foo"` returns a fresh `JsonPath`
with the segment appended; `path` is unchanged.

### 1.3 Function Signature Conventions

Two canonical signatures:

```nim
func toJson*(x: T): JsonNode =
  ## Pure, infallible. Returns a JsonNode tree.

func fromJson*(T: typedesc[T], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[T, SerdeViolation] =
  ## Validating parser. Returns ok(value) or err(SerdeViolation).
```

All routines are `func`. Callback parameters that take a deserialiser
use a proc-type with explicit `{.noSideEffect, raises: [].}` annotation
(required because `{.push raises: [], noSideEffect.}` does not
propagate to proc-type parameters):

```nim
func fromJson*[C](T: typedesc[Filter[C]], node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation]
        {.noSideEffect, raises: [].},
    path: JsonPath = emptyJsonPath()): Result[Filter[C], SerdeViolation]
```

The named `T` parameter enables `T.fromJson(node)` call syntax via UFCS.
Where the function body cannot naturally consume `T` (templates that
already specialise on it; trampolines), `discard $T` satisfies
nimalyzer's `params` rule without a `ruleOff` suppression.

For types that require additional context beyond the `JsonNode`
(`ServerCapability` and `AccountCapabilityEntry` need the URI string,
`Referencable[T]` needs the field name), the signature adds parameters:

```nim
func fromJson*(T: typedesc[ServerCapability], uri: string,
    data: JsonNode, path: JsonPath = emptyJsonPath()
    ): Result[ServerCapability, SerdeViolation]
```

**camelCase convention.** All field names in Nim match wire names exactly.
No conversion logic. `accountId` in Nim → `"accountId"` in JSON. Nim's
style insensitivity makes this zero-cost. `nph` preserves the casing
written. `--styleCheck:error` requires consistency (use the same casing
everywhere), not a specific convention.

### 1.4 Combinators — Field Access and Kind Checks

Every `fromJson` validates `JsonNodeKind` before extraction. The
raises-free accessors (`getStr`, `getBiggestInt`, `getBool`) silently
return defaults on wrong kinds — this is a totality hazard because it
produces incorrect values rather than errors.

`serde.nim` exports a family of combinators that encode the
"check-kind-then-extract" pattern with structured error context:

```nim
func expectKind*(node: JsonNode, expected: JsonNodeKind, path: JsonPath
    ): Result[void, SerdeViolation]
  ## Nil → svkNilNode at path (top-level expected-but-absent).
  ## Wrong kind → svkWrongKind at path.

func fieldOfKind*(node: JsonNode, key: string, expected: JsonNodeKind,
    path: JsonPath): Result[JsonNode, SerdeViolation]
  ## Missing → svkMissingField at parent path (the child doesn't exist).
  ## Wrong kind → svkWrongKind at path / key.
  ## Precondition: caller has verified node.kind == JObject.

func fieldJObject*(node: JsonNode, key: string, path: JsonPath
    ): Result[JsonNode, SerdeViolation]
func fieldJString*(node: JsonNode, key: string, path: JsonPath
    ): Result[JsonNode, SerdeViolation]
func fieldJArray*(node: JsonNode, key: string, path: JsonPath
    ): Result[JsonNode, SerdeViolation]
func fieldJBool*(node: JsonNode, key: string, path: JsonPath
    ): Result[JsonNode, SerdeViolation]
func fieldJInt*(node: JsonNode, key: string, path: JsonPath
    ): Result[JsonNode, SerdeViolation]
  ## Short-hands over fieldOfKind for each JSON kind.

func expectLen*(node: JsonNode, n: int, path: JsonPath
    ): Result[void, SerdeViolation]
  ## Asserts JArray length. Precondition: caller has verified JArray kind.

func nonEmptyStr*(s: string, label: string, path: JsonPath
    ): Result[void, SerdeViolation]
  ## Wire-boundary non-empty check. label describes the field's purpose
  ## ("method name", "type field", etc.) — the translator renders it
  ## verbatim followed by " must not be empty".

func wrapInner*[T](r: Result[T, ValidationError], path: JsonPath
    ): Result[T, SerdeViolation]
  ## Bridge an L1 smart-constructor failure into the serde railway,
  ## preserving the inner ValidationError losslessly inside
  ## svkFieldParserFailed.
```

**Optional helpers:**

```nim
func optField*(node: JsonNode, key: string): Opt[JsonNode]
  ## Lenient optional access: absent → Opt.none. Kind NOT validated.

func optJsonField*(node: JsonNode, key: string, kind: JsonNodeKind
    ): Opt[JsonNode]
  ## Lenient typed-optional access: absent, null, or wrong kind → Opt.none.

func optToJsonOrNull*[T](opt: Opt[T]): JsonNode
  ## opt.optToJsonOrNull() returns toJson(val) when some, newJNull() when none.

func optStringToJsonOrNull*(opt: Opt[string]): JsonNode
  ## Specialisation for plain string (which has no toJson overload — % is the idiom).
```

**Canonical patterns:**

```nim
# Distinct string type — validate JString before extraction
func fromJson*(t: typedesc[Id], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[Id, SerdeViolation] =
  ?expectKind(node, JString, path)
  return wrapInner(parseIdFromServer(node.getStr("")), path)
```

```nim
# Object with required typed fields
func fromJson*(T: typedesc[Account], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[Account, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  let isPersonalNode = ?fieldJBool(node, "isPersonal", path)
  let isPersonal = isPersonalNode.getBool(false)
  let isReadOnlyNode = ?fieldJBool(node, "isReadOnly", path)
  let isReadOnly = isReadOnlyNode.getBool(false)
  let acctCapsNode = ?fieldJObject(node, "accountCapabilities", path)
  var accountCapabilities: seq[AccountCapabilityEntry] = @[]
  for uri, data in acctCapsNode.pairs:
    let entry = ?AccountCapabilityEntry.fromJson(
      uri, data, path / "accountCapabilities" / uri)
    accountCapabilities.add(entry)
  ok(Account(
    name: name, isPersonal: isPersonal, isReadOnly: isReadOnly,
    accountCapabilities: accountCapabilities))
```

```nim
# Array with len precondition
func fromJson*(T: typedesc[Invocation], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[Invocation, SerdeViolation] =
  ?expectKind(node, JArray, path)
  ?expectLen(node, 3, path)
  let elems = node.getElems(@[])
  let nameNode = elems[0]
  ?expectKind(nameNode, JString, path / 0)
  let name = nameNode.getStr("")
  let arguments = elems[1]
  let callIdNode = elems[2]
  ?expectKind(callIdNode, JString, path / 2)
  let callIdRaw = callIdNode.getStr("")
  ?expectKind(arguments, JObject, path / 1)
  ?nonEmptyStr(name, "method name", path / 0)
  ?nonEmptyStr(callIdRaw, "method call ID", path / 2)
  let mcid = ?wrapInner(parseMethodCallId(callIdRaw), path / 2)
  return wrapInner(parseInvocation(name, arguments, mcid), path)
```

These patterns are non-negotiable for totality.

### 1.5 The Translator — Sole Boundary to `ValidationError`

A single function projects a `SerdeViolation` to the wire `ValidationError`
shape. New violation kinds force a compile error here and nowhere else.

```nim
func toValidationError*(v: SerdeViolation, rootType: string): ValidationError
```

The path renders as `" at <rfc-6901-pointer>"` and is appended to the
message when non-empty. For `svkFieldParserFailed`, the inner
`typeName` and `value` are preserved verbatim and only the message gains
the suffix; otherwise `rootType` is used. This is the only site in the
codebase that produces a `ValidationError` from a `SerdeViolation`.

### 1.6 Bulk Helpers for Common Shapes

`serde.nim` exports a small suite of helpers for shapes that recur across
methods and entities:

```nim
func collectExtras*(node: JsonNode, knownKeys: openArray[string]
    ): Opt[JsonNode]
  ## Collect non-standard fields into Opt[JsonNode]. Returns none when
  ## no extras exist. Precondition: caller has verified JObject kind.

func parseIdArray*(node: JsonNode, path: JsonPath
    ): Result[seq[Id], SerdeViolation]
  ## node IS the array. Strict — non-array → svkWrongKind.

func parseIdArrayField*(parent: JsonNode, key: string, path: JsonPath
    ): Result[seq[Id], SerdeViolation]
  ## Required id-array field on an object: missing → svkMissingField,
  ## wrong kind → svkWrongKind, per-element failure → svkFieldParserFailed.
  ## Preferred over parseIdArray(parent{"key"}, …) because it
  ## distinguishes missing from wrong-kind.

func parseOptIdArray*(node: JsonNode, path: JsonPath = emptyJsonPath()
    ): Result[seq[Id], SerdeViolation]
  ## Lenient: absent or non-array → empty seq. For optional id arrays
  ## like GetResponse.notFound. Per-element failures still surface.

func collapseNullToEmptySeq*[T](
    node: JsonNode, key: string,
    parser: proc(s: string): Result[T, ValidationError]
        {.noSideEffect, raises: [].},
    path: JsonPath): Result[seq[T], SerdeViolation]
  ## Parse a T[]|null field by key where null or absent collapses to
  ## an empty seq. Generic over the element type so Id and BlobId arrays
  ## share this helper.

func parseKeyedTable*[K, T](
    node: JsonNode,
    parseKey: proc(raw: string): Result[K, ValidationError]
        {.noSideEffect, raises: [].},
    parseValue: proc(n: JsonNode, p: JsonPath): Result[T, SerdeViolation]
        {.noSideEffect, raises: [].},
    path: JsonPath): Result[Table[K, T], SerdeViolation]
  ## Parse a JSON object into Table[K, T]. Lenient: nil or non-object
  ## → empty table. K must satisfy Table's hash/== requirements (every
  ## opaque-token distinct-string in this codebase does so via the
  ## borrow convention).
```

These helpers are imported by `methods.nim` (Layer 3) for response
deserialisation; they are not used inside the Layer 2 modules themselves
beyond the primitive ser/de.

`serde_errors.nim` defines two private helpers that encapsulate the
lenient pattern for scalar `Opt` fields shared by all three error types:

```nim
func optString(node: JsonNode, key: string): Opt[string] =
  Opt.some((?optJsonField(node, key, JString)).getStr(""))

func optInt(node: JsonNode, key: string): Opt[int] =
  Opt.some(int((?optJsonField(node, key, JInt)).getBiggestInt(0)))
```

When `optJsonField` yields `Opt.none`, the `?` operator early-returns
`Opt.none` from the helper. When it yields `Opt.some(child)`, the value
is unwrapped and extraction proceeds.

### 1.7 Layer Boundary

Layer 2 operates exclusively on pre-parsed `JsonNode` trees — `func`
transforms from `JsonNode` to `Result[T, SerdeViolation]`. The
`string → JsonNode` step requires exception handling
(`std/json.parseJson` raises `JsonParsingError`) and is out of scope.
Layer 4 owns that boundary and composes it with Layer 2's `fromJson`
functions.

### 1.8 Error Context Scope

When `fromJson` fails deep inside a nested call chain (e.g.,
`Session → Account → CoreCapabilities → UnsignedInt`), the propagated
`SerdeViolation` carries:

- A precise RFC 6901 path
  (`"/capabilities/urn:ietf:params:jmap:core/maxSizeUpload"`).
- Variant-specific structured payload (e.g., expected vs actual kind,
  missing field name, depth limit).
- For `svkFieldParserFailed`: the inner `ValidationError` with its
  `typeName` and `value` preserved verbatim.

The translator renders this as a human-readable suffix
(`" at /capabilities/urn:ietf:params:jmap:core/maxSizeUpload"`) when
projecting to the wire `ValidationError`. Callers above the L3/L4
boundary need only the wire shape; tests and library-internal logic can
inspect the structured violation directly.

### 1.9 Opt Field Leniency Policy

All `Opt[T]` scalar fields use a lenient pattern: absent, null, or wrong
kind all map to `Opt.none(T)`. Wrong kind does NOT return an error.

**Rationale:**

- This is a CLIENT library parsing server-originated data. Postel's law
  applies: "be liberal in what you accept."
- `Opt` fields are optional by definition — callers already handle the
  absent case via `for val in opt:`.
- For error types specifically, strictness is actively harmful: if
  `MethodError.description` has wrong kind, a strict approach fails the
  entire `MethodError` parse, and the caller loses the critical `type`
  field entirely.
- "Absent" and "malformed" are equivalent for optional fields: both mean
  "not usable."

**Canonical helper** (in `serde_errors.nim`, used by all three error
types):

```nim
func optString(node: JsonNode, key: string): Opt[string]
func optInt(node: JsonNode, key: string): Opt[int]
```

For container `Opt` types like `Opt[Table[CreationId, Id]]`
(Request/Response `createdIds`), the policy is stricter: a wrong
container kind (e.g., `"createdIds": "string"`) returns `err` rather
than collapsing to `none`, because container-shape mismatch indicates
a clear protocol violation rather than a supplementary-field issue.
Required (non-`Opt`) fields always use strict `expectKind` /
`fieldOfKind`.

### 1.10 Enum Deserialisation Totality

`fromJson` for enum types is total — unknown values map to catch-all
variants (`ckUnknown`, `metUnknown`, `setUnknown`, `mnUnknown`),
matching Layer 1's total `parseEnum` functions.

**Exception: `FilterOperator`.** The three operators (`AND`, `OR`,
`NOT`) are exhaustive per RFC §5.5. Unknown operators return
`err(SerdeViolation(kind: svkEnumNotRecognised, …))` because there is
no catch-all variant — the RFC does not define a mechanism for
server-extended operators.

**Module:** `src/jmap_client/serde_framework.nim` (for `FilterOperator`)

### 1.11 `func`, `noSideEffect`, and `strictCaseObjects`

Every Layer 2 source module starts with:

```nim
{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}
```

The compiler enforces:

- No `CatchableError` can escape any function.
- No observable side effects (the `var node = newJObject(); node[k] = v`
  builder pattern is permitted because the mutation is local —
  `noSideEffect` forbids effects visible to the caller, not local
  mutation).
- All variant-field reads must occur inside a `case` arm whose
  discriminator literal matches the field's declaration.

All routines are `func`. Callback parameters use proc-types with
`{.noSideEffect, raises: [].}` annotations (required because the push
pragma does not propagate through proc-type parameters). The hidden
pointer indirection in proc parameters is compatible with `func` once
the callback's purity is asserted on its proc type.

---

## 2. Serialisation Pattern Catalogue

Most types follow one of three patterns; a few special types require
custom handling.

### Pattern A: Simple Object

Field-by-field `%*{...}` construction for `toJson`; `node{"field"}` or
`fieldOfKind` extraction with kind checks for `fromJson`.

**Canonical example: `Comparator`**

```nim
func toJson*(c: Comparator): JsonNode =
  var node = %*{"property": string(c.property), "isAscending": c.isAscending}
  for col in c.collation:
    node["collation"] = %($col)
  return node

func fromJson*(T: typedesc[Comparator], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[Comparator, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let propNode = ?fieldJString(node, "property", path)
  let property = ?wrapInner(
    parsePropertyName(propNode.getStr("")), path / "property")
  let ascNode = node{"isAscending"}
  if not ascNode.isNil and ascNode.kind != JBool:
    return err(SerdeViolation(
      kind: svkWrongKind, path: path / "isAscending",
      expectedKind: JBool, actualKind: ascNode.kind))
  let isAscending = ascNode.getBool(true)  # nil-safe; true is RFC default
  let collNode = node{"collation"}
  var collation = Opt.none(CollationAlgorithm)
  if not collNode.isNil and collNode.kind == JString:
    let raw = collNode.getStr("")
    if raw.len > 0:
      # Empty string is the RFC-default sentinel; treat as Opt.none.
      let alg = ?wrapInner(parseCollationAlgorithm(raw), path / "collation")
      collation = Opt.some(alg)
  ok(parseComparator(property, isAscending, collation))
```

Types using Pattern A: `CoreCapabilities`, `Account`,
`AccountCapabilityEntry`, `Session` (composite), `Comparator`, `AddedItem`,
`ResultReference`, `Request`, `Response`, `RequestError`, `MethodError`.

### Pattern B: Case Object

Discriminator dispatch in `fromJson`, branch-specific construction in
`toJson`. Each branch uses a compile-time literal discriminator.

**Canonical example: `ServerCapability`**

```nim
func toJson*(cap: ServerCapability): JsonNode =
  case cap.kind
  of ckCore: cap.core.toJson()
  else:
    if cap.rawData.isNil: newJObject() else: cap.rawData.copy()

func ownData(data: JsonNode): JsonNode =
  if data.isNil: newJObject() else: data.copy()

template mkNonCoreCap(k: CapabilityKind): untyped =
  return ok(ServerCapability(kind: k, rawUri: uri, rawData: ownData(data)))

func fromJson*(T: typedesc[ServerCapability], uri: string, data: JsonNode,
    path: JsonPath = emptyJsonPath()
    ): Result[ServerCapability, SerdeViolation] =
  discard $T
  let parsedKind = parseCapabilityKind(uri)
  case parsedKind
  of ckCore:
    ?expectKind(data, JObject, path)
    let core = ?CoreCapabilities.fromJson(data, path)
    return ok(ServerCapability(kind: ckCore, rawUri: uri, core: core))
  of ckMail: mkNonCoreCap(ckMail)
  of ckSubmission: mkNonCoreCap(ckSubmission)
  of ckVacationResponse: mkNonCoreCap(ckVacationResponse)
  of ckWebsocket: mkNonCoreCap(ckWebsocket)
  of ckMdn: mkNonCoreCap(ckMdn)
  of ckSmimeVerify: mkNonCoreCap(ckSmimeVerify)
  of ckBlob: mkNonCoreCap(ckBlob)
  of ckQuota: mkNonCoreCap(ckQuota)
  of ckContacts: mkNonCoreCap(ckContacts)
  of ckCalendars: mkNonCoreCap(ckCalendars)
  of ckSieve: mkNonCoreCap(ckSieve)
  of ckUnknown: mkNonCoreCap(ckUnknown)
```

**ARC safety: deep copy + exhaustive case + `mkNonCoreCap` template.**
Non-core branches deep-copy `data` via `ownData()` to avoid ARC
double-free when the input `JsonNode` tree is shared between multiple
capabilities. The `mkNonCoreCap` template eliminates boilerplate while
preserving ARC safety — each call site expands with a compile-time
literal discriminator (`ckMail`, `ckSubmission`, etc.). Runtime
discriminator reassignment corrupts ARC's branch tracking on case
objects whose `else` branch contains `ref` fields (like `rawData:
JsonNode`). The exhaustive case avoids this by never mutating the
discriminator after construction.

Types using Pattern B: `ServerCapability`, `SetError`.

### Pattern C: Special Format

Type-specific wire formats that do not follow the object convention.

- **Invocation** — 3-element JSON array (see §6.1)
- **Referencable[T]** — `#`-prefix key dispatch (see §6.5)
- **Filter[C]** — recursive with operator/condition discriminator (see §7.2)

### Type Classification Table

| Type | Pattern | Notes |
|------|---------|-------|
| Id, AccountId, JmapState, MethodCallId, CreationId, BlobId, PropertyName, Date, UTCDate | Identity (unwrap/wrap) | Subset of A; generated via templates |
| UnsignedInt, JmapInt, MaxChanges | Identity (unwrap/wrap) | Subset of A; generated via templates (MaxChanges is manual — two-step validation) |
| UriTemplate | Identity-via-`$` (manual) | Layer 1 sealed object — `$t` returns `rawSource`; `parseUriTemplate` re-parses it |
| CollationAlgorithm | Identity-via-`$` | `$` returns the lossless identifier; `parseCollationAlgorithm` round-trips. Embedded inside `Comparator` and `CoreCapabilities`. |
| FilterOperator | Enum string | NOT total — exhaustive per RFC §5.5 |
| CapabilityKind, MethodErrorType, RequestErrorType, SetErrorType, MethodName, RefPath | Enum string | Not standalone; routed through containing object's `rawUri` / `rawType` / `rawName` / `rawPath` |
| CoreCapabilities | A: Simple Object | 8 fields |
| Account | A: Simple Object | with nested accountCapabilities |
| AccountCapabilityEntry | A: Simple Object | URI is also a parameter |
| Session | A: Composite Object | Composes all sub-parsers |
| Comparator | A: Simple Object | with defaults; `Opt[CollationAlgorithm]` |
| AddedItem | A: Simple Object | |
| ResultReference | A: Simple Object | uses `rawName` / `rawPath` for round-trip |
| Request | A: Simple Object | with Opt createdIds |
| Response | A: Simple Object | with Opt createdIds |
| RequestError | A: Simple Object | with extras collection |
| MethodError | A: Simple Object | with extras collection |
| ServerCapability | B: Case Object | URI dispatch |
| SetError | B: Case Object | seven payload-bearing variants |
| Invocation | C: Special | 3-element JSON array; uses `rawName` for round-trip |
| Referencable[T] | C: Special | `#`-prefix field-level |
| Filter[C] | C: Special | Recursive with mixin (`toJson`) and callback (`fromJson`) |

---

## 3. Primitive Type Serialisation

### 3.1 Distinct String Types

**RFC reference:** §1.2 (lines 287–319), §1.4 (lines 343–354), §2 (lines
477–733).

Nine distinct string types share the same serialisation pattern: unwrap
with `string(x)` for `toJson`, extract with `getStr` and call the smart
constructor for `fromJson`. These are generated via templates to
eliminate boilerplate.

**Templates (in `serde.nim`):**

```nim
template defineDistinctStringToJson*(T: typedesc) =
  func toJson*(x: T): JsonNode =
    return %(string(x))

template defineDistinctStringFromJson*(T: typedesc, parser: untyped) =
  func fromJson*(t: typedesc[T], node: JsonNode,
      path: JsonPath = emptyJsonPath()): Result[T, SerdeViolation] =
    discard $t
    ?expectKind(node, JString, path)
    return wrapInner(parser(node.getStr("")), path)
```

**Instantiations:**

```nim
defineDistinctStringToJson(Id)
defineDistinctStringToJson(AccountId)
defineDistinctStringToJson(JmapState)
defineDistinctStringToJson(MethodCallId)
defineDistinctStringToJson(CreationId)
defineDistinctStringToJson(BlobId)
defineDistinctStringToJson(PropertyName)
defineDistinctStringToJson(Date)
defineDistinctStringToJson(UTCDate)

defineDistinctStringFromJson(Id, parseIdFromServer)
defineDistinctStringFromJson(AccountId, parseAccountId)
defineDistinctStringFromJson(JmapState, parseJmapState)
defineDistinctStringFromJson(MethodCallId, parseMethodCallId)
defineDistinctStringFromJson(CreationId, parseCreationId)
defineDistinctStringFromJson(BlobId, parseBlobId)
defineDistinctStringFromJson(PropertyName, parsePropertyName)
defineDistinctStringFromJson(Date, parseDate)
defineDistinctStringFromJson(UTCDate, parseUtcDate)
```

**`fromJson` smart constructor mapping:**

| Type | `fromJson` calls | Rationale |
|------|------------------|-----------|
| Id | `parseIdFromServer` | Server-assigned; lenient (1-255 octets, no control chars) |
| AccountId | `parseAccountId` | Server-assigned; lenient (1-255 octets, no control chars) |
| JmapState | `parseJmapState` | Server-assigned (non-empty, no control chars) |
| MethodCallId | `parseMethodCallId` | Echoed from client request (non-empty) |
| CreationId | `parseCreationId` | Client-assigned, echoed back (non-empty, no `#` prefix) |
| BlobId | `parseBlobId` | Server-assigned blob identifier |
| PropertyName | `parsePropertyName` | Server-provided in responses (non-empty) |
| Date | `parseDate` | Server-provided (RFC 3339 structural validation) |
| UTCDate | `parseUtcDate` | Server-provided (RFC 3339, Z suffix) |

Each template-generated `fromJson` validates `JString` kind via
`expectKind`, then delegates to the appropriate Layer 1 smart
constructor. The smart constructor returns `Result[T, ValidationError]`,
which `wrapInner` lifts to `Result[T, SerdeViolation]` tagged at the
current path.

**`UriTemplate` is manual.** `UriTemplate` is a Layer 1 sealed object
(with `rawSource` preserving the verbatim wire string), not a distinct
string. Its ser/de pair is hand-written but follows the same identity
shape as the distinct-string templates:

```nim
func toJson*(x: UriTemplate): JsonNode = %($x)

func fromJson*(t: typedesc[UriTemplate], node: JsonNode,
    path: JsonPath = emptyJsonPath()
    ): Result[UriTemplate, SerdeViolation] =
  discard $t
  ?expectKind(node, JString, path)
  return wrapInner(parseUriTemplate(node.getStr("")), path)
```

`$template` produces the lossless source string preserved on the parsed
template's `rawSource` field; `parseUriTemplate` re-parses it.

**Module:** `src/jmap_client/serde.nim`

### 3.2 Distinct Int Types

**RFC reference:** §1.3 (lines 320–342).

Three types: `UnsignedInt` (0 to 2^53-1), `JmapInt` (-2^53+1 to 2^53-1),
and `MaxChanges` (UnsignedInt > 0).

**Templates (in `serde.nim`):**

```nim
template defineDistinctIntToJson*(T: typedesc, Base: typedesc) =
  func toJson*(x: T): JsonNode =
    return %(Base(x))

template defineDistinctIntFromJson*(T: typedesc, parser: untyped) =
  func fromJson*(t: typedesc[T], node: JsonNode,
      path: JsonPath = emptyJsonPath()): Result[T, SerdeViolation] =
    discard $t
    ?expectKind(node, JInt, path)
    return wrapInner(parser(node.getBiggestInt(0)), path)
```

**Instantiations:**

```nim
defineDistinctIntToJson(UnsignedInt, int64)
defineDistinctIntToJson(JmapInt, int64)

defineDistinctIntFromJson(UnsignedInt, parseUnsignedInt)
defineDistinctIntFromJson(JmapInt, parseJmapInt)
```

**`MaxChanges`** has a manual implementation (two-step validation: parse
as `UnsignedInt`, then enforce > 0):

```nim
func toJson*(x: MaxChanges): JsonNode =
  return %(int64(UnsignedInt(x)))

func fromJson*(T: typedesc[MaxChanges], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[MaxChanges, SerdeViolation] =
  discard $T
  ?expectKind(node, JInt, path)
  let ui = ?wrapInner(parseUnsignedInt(node.getBiggestInt(0)), path)
  return wrapInner(parseMaxChanges(ui), path)
```

`getBiggestInt` returns `BiggestInt` (`int64`) — correct for `distinct
int64` types. `getInt` returns pointer-sized `int` and would truncate on
32-bit platforms.

**Module:** `src/jmap_client/serde.nim`

### 3.3 Enum Types

**RFC reference:** §9.4 (capability URIs), §5.5 (FilterOperator), §3.6
(error types).

**`toJson` for enums embedded in containing objects.** Enums with
catch-all variants (`ckUnknown`, `retUnknown`, `metUnknown`,
`setUnknown`, `mnUnknown`) are NEVER serialised directly via
`$enumVal` — the containing object's `rawUri`, `rawType`, `rawName`, or
`rawPath` field is used instead. `$ckUnknown` returns `"ckUnknown"`
(symbolic name, not a URI), which would corrupt the wire format.

| Source enum | Wire field | Containing object |
|-------------|-----------|-------------------|
| `CapabilityKind` | `rawUri` | `ServerCapability`, `AccountCapabilityEntry` |
| `RequestErrorType` | `rawType` | `RequestError` |
| `MethodErrorType` | `rawType` | `MethodError` |
| `SetErrorType` | `rawType` | `SetError` |
| `MethodName` | `rawName` | `Invocation`, `ResultReference` |
| `RefPath` | `rawPath` | `ResultReference` |

**`fromJson` for enums.** All use Layer 1's total parse functions called
inline within the containing type's `fromJson`:

```nim
let kind = parseCapabilityKind(uri)
let errorType = parseRequestErrorType(raw)
let errorType = parseMethodErrorType(raw)
let errorType = parseSetErrorType(raw)
# MethodName/RefPath: containing types preserve raw strings; the
# parsed enum is computed lazily by typed accessors on the L1 object.
```

**`FilterOperator` exception.** The three operators are exhaustive per
RFC §5.5 — no catch-all variant exists. Deserialisation of unknown
operators returns `err(SerdeViolation(kind: svkEnumNotRecognised, …))`:

```nim
func toJson*(op: FilterOperator): JsonNode =
  return %($op)  # $ returns backing string: "AND", "OR", "NOT"

func fromJson*(T: typedesc[FilterOperator], node: JsonNode,
    path: JsonPath = emptyJsonPath()
    ): Result[FilterOperator, SerdeViolation] =
  discard $T
  ?expectKind(node, JString, path)
  let raw = node.getStr("")
  case raw
  of "AND": ok(foAnd)
  of "OR": ok(foOr)
  of "NOT": ok(foNot)
  else:
    err(SerdeViolation(kind: svkEnumNotRecognised, path: path,
      enumTypeLabel: "FilterOperator", rawValue: raw))
```

**Module:** `src/jmap_client/serde_framework.nim` (FilterOperator only).
The other enum types have no standalone `toJson`/`fromJson` — they are
parsed inline within their containing type's `fromJson`.

### 3.4 `CollationAlgorithm`

`CollationAlgorithm` is a Layer 1 case object with named RFC variants
(`caAsciiCasemap`, `caOctet`, `caAsciiNumeric`, `caUnicodeCasemap`) and
a catch-all `caOther` carrying the verbatim identifier string. `$` on a
`CollationAlgorithm` returns its lossless identifier; `parseCollationAlgorithm`
re-parses it.

It has no standalone `toJson`/`fromJson` — it is serialised inline by its
containing types:

- `Comparator.collation: Opt[CollationAlgorithm]` — emitted as
  `node["collation"] = %($col)` when present; `parseCollationAlgorithm`
  on the receive path with empty-string fallback to `Opt.none`.
- `CoreCapabilities.collationAlgorithms: HashSet[CollationAlgorithm]` —
  emitted as a JSON array of identifier strings; receive path parses
  each element via `parseCollationAlgorithm` and collects via
  `toHashSet`.

---

## 4. Capability Serialisation

### 4.1 CoreCapabilities

**RFC reference:** §2 (lines 511–572). Part of
`capabilities["urn:ietf:params:jmap:core"]`.

Eight fields, all required. Seven `UnsignedInt` fields for server limits,
plus `collationAlgorithms` as a JSON array → `HashSet[CollationAlgorithm]`.

**Wire format:**

```json
{
  "maxSizeUpload": 50000000,
  "maxConcurrentUpload": 8,
  "maxSizeRequest": 10000000,
  "maxConcurrentRequests": 8,
  "maxCallsInRequest": 32,
  "maxObjectsInGet": 256,
  "maxObjectsInSet": 128,
  "collationAlgorithms": [
    "i;ascii-numeric",
    "i;ascii-casemap",
    "i;unicode-casemap"
  ]
}
```

**`toJson`:**

```nim
func toJson*(caps: CoreCapabilities): JsonNode =
  var node = %*{
    "maxSizeUpload": int64(caps.maxSizeUpload),
    "maxConcurrentUpload": int64(caps.maxConcurrentUpload),
    "maxSizeRequest": int64(caps.maxSizeRequest),
    "maxConcurrentRequests": int64(caps.maxConcurrentRequests),
    "maxCallsInRequest": int64(caps.maxCallsInRequest),
    "maxObjectsInGet": int64(caps.maxObjectsInGet),
    "maxObjectsInSet": int64(caps.maxObjectsInSet),
  }
  var algArr = newJArray()
  for alg in caps.collationAlgorithms:
    algArr.add(%($alg))
  node["collationAlgorithms"] = algArr
  return node
```

**`fromJson`:** Calls `UnsignedInt.fromJson` for each numeric field
(which delegates to `parseUnsignedInt` via `wrapInner`). Each algorithm
element is parsed via `parseCollationAlgorithm`.

**RFC typo tolerance.** The RFC §2.1 example (line 753) uses
`"maxConcurrentRequest"` (singular) instead of `"maxConcurrentRequests"`
(plural, per the field definition in §2). `fromJson` accepts both forms
— real servers may follow the example. Missing both yields
`svkMissingField` for `maxConcurrentRequests`.

**No smart constructor.** Layer 1 defines no `parseCoreCapabilities`.
Construction happens exclusively during JSON deserialisation (Layer 2),
which validates each field individually.

**Module:** `src/jmap_client/serde_session.nim`

### 4.2 ServerCapability

**RFC reference:** §2 (Session.capabilities values).

A case object discriminated by `CapabilityKind`. Only `ckCore` has a
typed representation in RFC 8620. All other capabilities store raw JSON
data on the `rawData: JsonNode` field.

**Wire format:** The `capabilities` object in Session has URIs as keys
and capability data as values:

```json
"capabilities": {
  "urn:ietf:params:jmap:core": { ... CoreCapabilities ... },
  "urn:ietf:params:jmap:mail": {},
  "https://example.com/apis/foobar": { "maxFoosFinangled": 42 }
}
```

Layer 2 receives each `(uri, data)` pair from the Session parser and
dispatches on `parseCapabilityKind(uri)`.

**`toJson`** (Pattern B canonical example, see §2). Non-core branches
deep-copy `rawData` via `.copy()` to prevent callers from mutating
internal state through the returned ref.

**`fromJson`:** Dispatches on `parseCapabilityKind(uri)`. `ckCore` calls
`CoreCapabilities.fromJson(data, path)` with a preceding `expectKind`
for improved error context. All other kinds use the `mkNonCoreCap`
template with exhaustive `case` branches and compile-time literal
discriminators.

**Module:** `src/jmap_client/serde_session.nim`

### 4.3 AccountCapabilityEntry

**RFC reference:** §2 (nested in Session.accounts[].accountCapabilities).

A flat object storing per-account capability data as raw JSON. Each
entry records the parsed `CapabilityKind`, the original URI string, and
the raw capability data.

**Wire format:** The `accountCapabilities` object has URIs as keys:

```json
"accountCapabilities": {
  "urn:ietf:params:jmap:mail": {},
  "urn:ietf:params:jmap:contacts": {}
}
```

**`toJson`:**

```nim
func toJson*(entry: AccountCapabilityEntry): JsonNode =
  if entry.data.isNil: newJObject() else: entry.data.copy()
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[AccountCapabilityEntry], uri: string,
    data: JsonNode, path: JsonPath = emptyJsonPath()
    ): Result[AccountCapabilityEntry, SerdeViolation] =
  discard $T
  if uri.len == 0:
    return err(SerdeViolation(kind: svkEmptyRequired, path: path,
      emptyFieldLabel: "capability URI"))
  ok(AccountCapabilityEntry(
    kind: parseCapabilityKind(uri), rawUri: uri, data: ownData(data)))
```

Validates URI is non-empty. Deep-copies `data` via `ownData()` to avoid
ARC double-free when the input `JsonNode` tree and the parsed
`AccountCapabilityEntry` are destroyed independently.

**Module:** `src/jmap_client/serde_session.nim`

---

## 5. Session Serialisation

### 5.1 Account

**RFC reference:** §2 (lines 583–643).

An account the user has access to. Contains a user-friendly name, access
flags, and per-account capability information.

**Wire format:**

```json
{
  "name": "john@example.com",
  "isPersonal": true,
  "isReadOnly": false,
  "accountCapabilities": {
    "urn:ietf:params:jmap:mail": {},
    "urn:ietf:params:jmap:contacts": {}
  }
}
```

**`toJson`:**

```nim
func toJson*(acct: Account): JsonNode =
  var node = %*{
    "name": acct.name, "isPersonal": acct.isPersonal,
    "isReadOnly": acct.isReadOnly}
  var acctCaps = newJObject()
  for _, entry in acct.accountCapabilities:
    acctCaps[entry.rawUri] = entry.toJson()
  node["accountCapabilities"] = acctCaps
  return node
```

**`fromJson`:** Validates JObject, extracts `name` (string),
`isPersonal` (bool), `isReadOnly` (bool), `accountCapabilities`
(object), then iterates `acctCapsNode.pairs` calling
`AccountCapabilityEntry.fromJson(uri, data, path / "accountCapabilities" / uri)`
for each entry.

**No standalone smart constructor.** Accounts are validated as part of
Session parsing.

**Module:** `src/jmap_client/serde_session.nim`

### 5.2 Session

**RFC reference:** §2 (lines 477–733). The most complex deserialisation
target.

**Wire format:** RFC §2.1 example — see §13.1 for the complete JSON.

**`toJson`:**

```nim
func toJson*(s: Session): JsonNode =
  var node = %*{
    "username": s.username,
    "apiUrl": s.apiUrl,
    "downloadUrl": $s.downloadUrl,
    "uploadUrl": $s.uploadUrl,
    "eventSourceUrl": $s.eventSourceUrl,
    "state": string(s.state),
  }
  var caps = newJObject()
  for _, cap in s.capabilities:
    caps[cap.rawUri] = cap.toJson()
  node["capabilities"] = caps
  var accts = newJObject()
  for id, acct in s.accounts:
    accts[string(id)] = acct.toJson()
  node["accounts"] = accts
  var primary = newJObject()
  for uri, id in s.primaryAccounts:
    primary[uri] = %string(id)
  node["primaryAccounts"] = primary
  return node
```

**Assumption:** `capabilities` contains no duplicate `rawUri` values.
This is guaranteed by `fromJson` (JSON object keys are unique via
`OrderedTable`). Programmatic construction must ensure uniqueness;
duplicates cause silent overwrite in `toJson`.

**`fromJson`:** Seven sub-parse steps, each returning early via `?` on
violation:

1. Capabilities — iterate `capabilities` object, call
   `ServerCapability.fromJson(uri, data, path / "capabilities" / uri)`.
2. Accounts — iterate `accounts` object, call `parseAccountId(idStr)`
   and `Account.fromJson(acctData, path / "accounts" / idStr)`.
3. Primary accounts — iterate `primaryAccounts` object, call
   `parseAccountId(idNode.getStr(""))`.
4. Scalar fields — `username`, `apiUrl`.
5. URI templates — `downloadUrl`, `uploadUrl`, `eventSourceUrl` parsed
   via `parseUriTemplate`.
6. State — `parseJmapState(...)`.
7. `parseSession(...)` — Layer 1 smart constructor for structural
   invariant validation (ckCore present, apiUrl non-empty, URI template
   variables, etc.). Result wrapped via `wrapInner` at the root path.

**Module:** `src/jmap_client/serde_session.nim`

---

## 6. Envelope Serialisation

### 6.1 Invocation

**RFC reference:** §3.2 (lines 865–881).

A tuple of three elements: method name, arguments object, method call
ID. Serialised as a 3-element JSON array, NOT a JSON object.

**Wire format:**

```json
["Mailbox/get", {"accountId": "A13824", "ids": null}, "c1"]
```

**`toJson`:**

```nim
func toJson*(inv: Invocation): JsonNode =
  return %*[inv.rawName, inv.arguments, string(inv.methodCallId)]
```

`inv.rawName` is the verbatim wire string preserved on the L1
`Invocation` object. Using `$inv.name` would collapse unknown method
names to the symbol name `mnUnknown`, breaking lossless round-trip.

**`fromJson`** (canonical array example, see §1.4): Validates `JArray`
with length 3, extracts by index, calls `parseMethodCallId` and the
`parseInvocation` smart constructor for final construction.
`parseInvocation` accepts the raw method name string; the typed
`name(): MethodName` accessor on the resulting Invocation parses it
lazily via `parseMethodName`.

**Module:** `src/jmap_client/serde_envelope.nim`

### 6.2 Request

**RFC reference:** §3.3 (lines 882–974).

**Wire format:**

```json
{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["method1", {"arg1": "arg1data", "arg2": "arg2data"}, "c1"],
    ["method2", {"arg1": "arg1data"}, "c2"],
    ["method3", {}, "c3"]
  ]
}
```

**`toJson`:**

```nim
func toJson*(r: Request): JsonNode =
  var node = newJObject()
  node["using"] = %r.`using`
  var calls = newJArray()
  for _, inv in r.methodCalls:
    calls.add(inv.toJson())
  node["methodCalls"] = calls
  for createdIds in r.createdIds:
    var ids = newJObject()
    for k, v in createdIds:
      ids[string(k)] = %string(v)
    node["createdIds"] = ids
  return node
```

**`fromJson`:** Validates JObject, extracts `using` (string array via
`fieldJArray` + per-element `expectKind`), `methodCalls` (array of
Invocations), and optional `createdIds` via `parseCreatedIds`.

**Shared helper — `parseCreatedIds`:** Container-strict — wrong
container kind returns `err(svkWrongKind)`, not lenient `none`.

```nim
func parseCreatedIds(node: JsonNode, path: JsonPath
    ): Result[Opt[Table[CreationId, Id]], SerdeViolation] =
  let cnode = node{"createdIds"}
  if cnode.isNil:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind == JNull:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind != JObject:
    return err(SerdeViolation(kind: svkWrongKind,
      path: path / "createdIds",
      expectedKind: JObject, actualKind: cnode.kind))
  var tbl = initTable[CreationId, Id]()
  for k, v in cnode.pairs:
    let cid = ?wrapInner(parseCreationId(k), path / "createdIds" / k)
    ?expectKind(v, JString, path / "createdIds" / k)
    let id = ?wrapInner(parseIdFromServer(v.getStr("")), path / "createdIds" / k)
    tbl[cid] = id
  return ok(Opt.some(tbl))
```

**Module:** `src/jmap_client/serde_envelope.nim`

### 6.3 Response

**RFC reference:** §3.4 (lines 975–1035).

**Wire format:**

```json
{
  "methodResponses": [
    ["method1", {"arg1": 3, "arg2": "foo"}, "c1"],
    ["error", {"type": "unknownMethod"}, "c3"]
  ],
  "sessionState": "75128aab4b1b"
}
```

**`toJson`:**

```nim
func toJson*(r: Response): JsonNode =
  var node = newJObject()
  var responses = newJArray()
  for _, inv in r.methodResponses:
    responses.add(inv.toJson())
  node["methodResponses"] = responses
  node["sessionState"] = %string(r.sessionState)
  for createdIds in r.createdIds:
    var ids = newJObject()
    for k, v in createdIds:
      ids[string(k)] = %string(v)
    node["createdIds"] = ids
  return node
```

**`fromJson`:** Validates JObject, extracts `methodResponses` (array of
Invocations), `sessionState` (string → JmapState via `parseJmapState`),
and optional `createdIds` via `parseCreatedIds`.

**Module:** `src/jmap_client/serde_envelope.nim`

### 6.4 ResultReference

**RFC reference:** §3.7 (lines 1220–1493).

**Wire format:**

```json
{"resultOf": "c0", "name": "Foo/query", "path": "/ids"}
```

**`toJson`:**

```nim
func toJson*(r: ResultReference): JsonNode =
  return %*{"resultOf": string(r.resultOf), "name": r.rawName, "path": r.rawPath}
```

`rawName` and `rawPath` preserve verbatim wire strings, including any
forward-compatible unknown variants. The typed `name(): MethodName` and
`path(): RefPath` accessors on the L1 object parse them lazily.

**`fromJson`:**

```nim
func fromJson*(T: typedesc[ResultReference], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[ResultReference, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let resultOfNode = ?fieldJString(node, "resultOf", path)
  let resultOfRaw = resultOfNode.getStr("")
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  let pathNode = ?fieldJString(node, "path", path)
  let pathValue = pathNode.getStr("")
  let resultOf = ?wrapInner(parseMethodCallId(resultOfRaw), path / "resultOf")
  return wrapInner(parseResultReference(resultOf, name, pathValue), path)
```

`fromJson` delegates to the `parseResultReference` smart constructor for
validation. `parseResultReference` is the wire-boundary constructor that
accepts any non-empty `name` and `path` so forward-compatible references
(unknown method names, unknown ref paths) round-trip losslessly. The
typed `name(): MethodName` and `path(): RefPath` accessors on the L1
object parse the raw strings lazily.

**Module:** `src/jmap_client/serde_envelope.nim`

### 6.5 Referencable[T]

**Architecture reference:** Decision 1.3B, Decision 2.3.

NOT a standalone `toJson`/`fromJson` pair — handled at the
containing-object level. The wire format uses the JSON key name as the
discriminator:

- `rkDirect`: normal key with the value serialised as `T`.
  `{ "ids": ["id1", "id2"] }`
- `rkReference`: key prefixed with `#`, value is a `ResultReference`
  object.
  `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

**Helper functions:**

```nim
func referencableKey*[T](fieldName: string, r: Referencable[T]): string =
  case r.kind
  of rkDirect: fieldName
  of rkReference: "#" & fieldName

func fromJsonField*[T](
    fieldName: string,
    node: JsonNode,
    fromDirect: proc(n: JsonNode): T {.noSideEffect, raises: [].},
    path: JsonPath = emptyJsonPath()
): Result[Referencable[T], SerdeViolation] =
  let refKey = "#" & fieldName
  let refNode = node{refKey}
  let directNode = node{fieldName}
  # RFC 8620 §3.7: reject when both direct and referenced forms are present
  if not refNode.isNil and not directNode.isNil:
    return err(SerdeViolation(kind: svkConflictingFields, path: path,
      conflictKeyA: fieldName, conflictKeyB: refKey,
      conflictRule: "RFC 8620 §3.7"))
  if not refNode.isNil:
    ?expectKind(refNode, JObject, path / refKey)
    let resultRef = ?ResultReference.fromJson(refNode, path / refKey)
    return ok(referenceTo[T](resultRef))
  if directNode.isNil:
    return err(SerdeViolation(kind: svkMissingField, path: path,
      missingFieldName: fieldName & " or " & refKey))
  let value = fromDirect(directNode)
  return ok(direct[T](value))
```

**Mutual exclusion enforcement.** `fromJsonField` rejects the ambiguous
case outright per RFC 8620 §3.7: if both `"ids"` and `"#ids"` are
present, it returns `err(SerdeViolation(kind: svkConflictingFields, …))`.

**Serialisation-side design.** The `#`-prefix dispatch is a data
transform on the field name, not a mutation operation.
`referencableKey` is a total pure function —
`(string, Referencable[T]) → string` — that computes the wire key. The
value serialisation uses existing `toJson` overloads for the inner
types.

**Deserialisation-side design.** `fromJsonField` is a combined helper
because key dispatch and value parsing are genuinely coupled on the
deserialisation side — the key determines whether to parse `T` or
`ResultReference`. The asymmetry between `referencableKey` (pure key
transform) and `fromJsonField` (combined dispatch + parse) reflects the
genuine asymmetry in the problem: serialisation knows the variant
(dispatch is trivial), deserialisation must discover it from the key.

**Rationale.** The `#`-prefix is on the JSON key, not the value. This
makes it impossible to serialise as a standalone `toJson`/`fromJson`
pair — the containing object's serialiser must handle the key dispatch.

**Module:** `src/jmap_client/serde_envelope.nim`

---

## 7. Framework Type Serialisation

### 7.1 Comparator

**RFC reference:** §5.5 (lines 2339–2638).

Full `toJson`/`fromJson` code shown in §2 (Pattern A canonical example).
`isAscending` defaults to `true` when absent from JSON (per RFC §5.5).
`collation` is `Opt[CollationAlgorithm]` — omit when `isNone`. Empty
string in the wire `collation` field is treated as the RFC default
sentinel and maps to `Opt.none`. `fromJson` delegates to
`parseComparator` smart constructor for final construction.

**Module:** `src/jmap_client/serde_framework.nim`

### 7.2 Filter[C]

**RFC reference:** §5.5 (lines 2368–2394).

A recursive algebraic data type parameterised by condition type `C`. On
the wire, an operator node has an `"operator"` field (`"AND"`, `"OR"`,
`"NOT"`) and a `"conditions"` array. A condition node lacks the
`"operator"` field.

**Wire format (operator):**

```json
{
  "operator": "AND",
  "conditions": [
    {"hasKeyword": "$seen"},
    {"header": ["X-Spam", ""]}
  ]
}
```

**Wire format (condition):**

```json
{"hasKeyword": "$seen"}
```

**`toJson` (mixin-resolved condition serialiser):**

```nim
func toJson*[C](f: Filter[C]): JsonNode =
  ## Leaf condition C.toJson resolves via mixin at the caller's
  ## instantiation scope — every entity that uses Filter[C] must have
  ## C.toJson in import scope at the builder call site. The recursive
  ## child.toJson() call dispatches back to this overload for nested
  ## operator nodes (same-module lookup, no mixin needed).
  mixin toJson
  case f.kind
  of fkCondition:
    return f.condition.toJson()
  of fkOperator:
    var conditions = newJArray()
    for child in f.conditions:
      conditions.add(child.toJson())
    return %*{"operator": $f.operator, "conditions": conditions}
```

**`fromJson` (callback-based condition parser):**

```nim
const MaxFilterDepth* = 128
  ## Maximum nesting depth for Filter[C].fromJson deserialisation.
  ## Defence-in-depth guard against stack overflow (StackOverflowDefect
  ## is uncatchable). 128 is generous for any realistic JMAP query while
  ## preventing pathological nesting. std/json's parseJson has its own
  ## DepthLimit of 1000, but this layer accepts pre-parsed JsonNode.

func fromJsonImpl[C](
    node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation]
        {.noSideEffect, raises: [].},
    depth: int,
    path: JsonPath,
): Result[Filter[C], SerdeViolation] =
  ?expectKind(node, JObject, path)
  if depth <= 0:
    return err(SerdeViolation(kind: svkDepthExceeded, path: path,
      maxDepth: MaxFilterDepth))
  let opNode = node{"operator"}
  if opNode.isNil:
    let cond = ?fromCondition(node, path)
    return ok(filterCondition(cond))
  let op = ?FilterOperator.fromJson(opNode, path / "operator")
  let conditionsNode = ?fieldJArray(node, "conditions", path)
  var children: seq[Filter[C]] = @[]
  for i, childNode in conditionsNode.getElems(@[]):
    let child = ?fromJsonImpl[C](childNode, fromCondition, depth - 1,
      path / "conditions" / i)
    children.add(child)
  return ok(filterOperator(op, children))

func fromJson*[C](
    T: typedesc[Filter[C]], node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation]
        {.noSideEffect, raises: [].},
    path: JsonPath = emptyJsonPath(),
): Result[Filter[C], SerdeViolation] =
  discard $T
  return fromJsonImpl[C](node, fromCondition, MaxFilterDepth, path)
```

**Asymmetric callback strategy.** `toJson` resolves the leaf condition's
serialiser via `mixin` — every entity that uses `Filter[C]` provides
`C.toJson` in the call site's instantiation scope. `fromJson` cannot
use `mixin` for the inner deserialiser because it must thread `path`
and a `Result[C, SerdeViolation]` return shape, so the caller passes a
typed proc parameter. The recursive `fromJsonImpl` call dispatches
internally to the same overload (same-module lookup; no mixin needed).

**Depth-limiting defence.** `fromJsonImpl` tracks recursion depth and
returns `err(SerdeViolation(kind: svkDepthExceeded, …))` when
`MaxFilterDepth` (128) is exceeded.

**Module:** `src/jmap_client/serde_framework.nim`

### 7.3 AddedItem

**RFC reference:** §5.6 (lines 2639–2819).

**Wire format:**

```json
{"id": "msg1023", "index": 10}
```

**`toJson`:**

```nim
func toJson*(item: AddedItem): JsonNode =
  return %*{"id": string(item.id), "index": int64(item.index)}
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[AddedItem], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[AddedItem, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let indexNode = ?fieldJInt(node, "index", path)
  let index = ?UnsignedInt.fromJson(indexNode, path / "index")
  return ok(initAddedItem(id, index))
```

**Module:** `src/jmap_client/serde_framework.nim`

### 7.4 PropertyName

Distinct string type — same pattern as §3.1, generated via
`defineDistinctStringToJson`/`defineDistinctStringFromJson` templates.
`toJson` unwraps with `string(x)`, `fromJson` calls `parsePropertyName`.

**Module:** `src/jmap_client/serde.nim`

---

## 8. Error Type Serialisation

### 8.1 RequestError

**RFC reference:** §3.6.1 (lines 1079–1136), RFC 7807.

Represents a request-level error — an HTTP response with
`Content-Type: application/problem+json`. The server returns these when
the entire request is rejected before any method calls are processed.

**Wire format (RFC 7807 problem details):**

```json
{
  "type": "urn:ietf:params:jmap:error:unknownCapability",
  "status": 400,
  "detail": "The Request object used capability 'https://example.com/apis/foobar', which is not supported by this server."
}
```

**`toJson`:**

```nim
const RequestErrorKnownKeys = ["type", "status", "title", "detail", "limit"]

func toJson*(re: RequestError): JsonNode =
  var node = newJObject()
  node["type"] = %re.rawType
  for v in re.status:
    node["status"] = %v
  for v in re.title:
    node["title"] = %v
  for v in re.detail:
    node["detail"] = %v
  for v in re.limit:
    node["limit"] = %v
  for extras in re.extras:
    for key, val in extras.pairs:
      if key notin RequestErrorKnownKeys:
        node[key] = val
  return node
```

**Opt[T] iteration pattern.** `toJson` uses `for v in opt:` to iterate
over `Opt` fields — the loop body executes only when the value is
`some`. This is the idiomatic Opt consumption pattern per the project
conventions.

**Collision guard.** `toJson` skips extras whose keys collide with
standard fields. This prevents manually constructed `RequestError`
objects with extras containing e.g. `"type"` from corrupting the wire
format.

**`fromJson`:**

```nim
func fromJson*(T: typedesc[RequestError], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[RequestError, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let status = optInt(node, "status")
  let title = optString(node, "title")
  let detail = optString(node, "detail")
  let limit = optString(node, "limit")
  let extras = collectExtras(node, RequestErrorKnownKeys)
  ok(requestError(
    rawType = rawType, status = status, title = title, detail = detail,
    limit = limit, extras = extras))
```

The `requestError` smart constructor auto-parses the raw type string to
the `RequestErrorType` enum via `parseRequestErrorType`.

**Module:** `src/jmap_client/serde_errors.nim`

### 8.2 MethodError

**RFC reference:** §3.6.2 (lines 1137–1219).

Per-invocation error within a JMAP response. When the server returns
`["error", {...}, "c1"]`, the `Invocation.name` is `mnUnknown` (no
backing string for `"error"`) and the `arguments` JSON is parsed as a
`MethodError`.

**Wire format:**

```json
{"type": "unknownMethod", "description": "No method 'Foo/bar' exists."}
```

**`toJson`:**

```nim
const MethodErrorKnownKeys = ["type", "description"]

func toJson*(me: MethodError): JsonNode =
  var node = newJObject()
  node["type"] = %me.rawType
  for v in me.description:
    node["description"] = %v
  for extras in me.extras:
    for key, val in extras.pairs:
      if key notin MethodErrorKnownKeys:
        node[key] = val
  return node
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[MethodError], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[MethodError, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let description = optString(node, "description")
  let extras = collectExtras(node, MethodErrorKnownKeys)
  ok(methodError(rawType = rawType, description = description, extras = extras))
```

**Module:** `src/jmap_client/serde_errors.nim`

### 8.3 SetError

**RFC reference:** §5.3 (lines 2060–2190), §5.4 (lines 2191–2338),
RFC 8621 §4.6 / §7.5.

Per-item error within `/set` and `/copy` responses. A case object with
seven payload-bearing variants and a shared payload-less arm:

| Variant | Wire field | RFC | Payload |
|---------|-----------|-----|---------|
| `setInvalidProperties` | `properties` | RFC 8620 §5.3 SHOULD | `seq[string]` |
| `setAlreadyExists` | `existingId` | RFC 8620 §5.4 MUST | `Id` |
| `setBlobNotFound` | `notFound` | RFC 8621 §4.6 MUST | `seq[BlobId]` |
| `setInvalidEmail` | `properties` | RFC 8621 §7.5 SHOULD | `seq[string]` (stored as `invalidEmailPropertyNames`) |
| `setTooManyRecipients` | `maxRecipients` | RFC 8621 §7.5 MUST | `UnsignedInt` (stored as `maxRecipientCount`) |
| `setInvalidRecipients` | `invalidRecipients` | RFC 8621 §7.5 MUST | `seq[string]` |
| `setTooLarge` | `maxSize` | RFC 8621 §7.5 SHOULD | `Opt[UnsignedInt]` (stored as `maxSizeOctets`) |

All other RFC variants (forbidden, overQuota, rateLimit, notFound,
invalidPatch, willDestroy, singleton, mailboxHasChild, mailboxHasEmail,
tooManyKeywords, tooManyMailboxes, noRecipients, forbiddenMailFrom,
forbiddenFrom, forbiddenToSend, cannotUnsend, plus `setUnknown`) carry
no payload — only the shared `rawType`, `description: Opt[string]`, and
`extras: Opt[JsonNode]`.

**Wire format examples:**

```json
{"type": "invalidProperties", "properties": ["name", "role"]}
{"type": "alreadyExists", "existingId": "msg42"}
{"type": "blobNotFound", "notFound": ["B1", "B2"]}
{"type": "tooLarge", "maxSize": 50000000}
{"type": "forbidden"}
```

**Shared helper — `setErrorKnownKeys`:** Returns the per-variant set of
known JSON keys. Used by both `toJson` (collision guard) and `fromJson`
(extras collection):

```nim
func setErrorKnownKeys(errorType: SetErrorType): seq[string] =
  case errorType
  of setInvalidProperties: @["type", "description", "properties"]
  of setAlreadyExists:     @["type", "description", "existingId"]
  of setBlobNotFound:      @["type", "description", "notFound"]
  of setInvalidEmail:      @["type", "description", "properties"]
  of setTooManyRecipients: @["type", "description", "maxRecipients"]
  of setInvalidRecipients: @["type", "description", "invalidRecipients"]
  of setTooLarge:          @["type", "description", "maxSize"]
  else:                    @["type", "description"]
```

Each payload-bearing variant names its RFC wire field so a parser on a
non-matching variant preserves the field in `extras` rather than
silently dropping it.

**`toJson`:**

```nim
func toJson*(se: SetError): JsonNode =
  var node = newJObject()
  node["type"] = %se.rawType
  for v in se.description:
    node["description"] = %v
  case se.errorType
  of setInvalidProperties:
    node["properties"] = %se.properties
  of setAlreadyExists:
    node["existingId"] = %string(se.existingId)
  of setBlobNotFound:
    var arr = newJArray()
    for id in se.notFound:
      arr.add(%string(id))
    node["notFound"] = arr
  of setInvalidEmail:
    node["properties"] = %se.invalidEmailPropertyNames
  of setTooManyRecipients:
    node["maxRecipients"] = %int64(se.maxRecipientCount)
  of setInvalidRecipients:
    node["invalidRecipients"] = %se.invalidRecipients
  of setTooLarge:
    for v in se.maxSizeOctets:
      node["maxSize"] = %int64(v)
  else:
    discard
  for extras in se.extras:
    let knownKeys = setErrorKnownKeys(se.errorType)
    for key, val in extras.pairs:
      if key notin knownKeys:
        node[key] = val
  return node
```

`setTooLarge` omits `maxSize` when `Opt.none` (SHOULD, not MUST, per
RFC §7.5). All other payload-bearing variants always emit their RFC
field — for `setInvalidProperties`, this means even an empty `properties`
array is serialised, because omitting the key would let `fromJson`
apply the defensive fallback and produce `setUnknown` instead.

**`fromJson` (defensive fallback):**

```nim
func fromJson*(T: typedesc[SetError], node: JsonNode,
    path: JsonPath = emptyJsonPath()): Result[SetError, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let description = optString(node, "description")
  let errorType = parseSetErrorType(rawType)
  let knownKeys = setErrorKnownKeys(errorType)
  let extras = collectExtras(node, knownKeys)
  case errorType
  of setInvalidProperties:
    return fromJsonInvalidProperties(rawType, description, extras, node, path)
  of setAlreadyExists:
    return ok(fromJsonAlreadyExists(rawType, description, extras, node))
  of setBlobNotFound:
    return fromJsonBlobNotFound(rawType, description, extras, node, path)
  of setInvalidEmail:
    return fromJsonInvalidEmail(rawType, description, extras, node, path)
  of setTooManyRecipients:
    return fromJsonTooManyRecipients(rawType, description, extras, node, path)
  of setInvalidRecipients:
    return fromJsonInvalidRecipients(rawType, description, extras, node, path)
  of setTooLarge:
    return ok(fromJsonTooLarge(rawType, description, extras, node))
  else:
    return ok(setError(rawType, description, extras))
```

Each `fromJsonXyz` private helper parses the variant's RFC field. When
the field is missing or malformed, the helper falls through to
`setError(rawType, description, extras)`, which calls Layer 1's generic
constructor — that constructor maps required-payload variants to
`setUnknown` (preserving `rawType`).

**Defensive fallback rationale.** When a server sends `"type":
"invalidProperties"` without the `properties` array, or `"type":
"alreadyExists"` without `existingId`, `fromJson` calls the generic
`setError` constructor which maps these to `setUnknown`. This ensures
pattern-matching consumers never encounter a `setInvalidProperties`
variant with missing properties or a `setAlreadyExists` variant with a
bogus `existingId`. The fallback uses `parseXyz(...).isOk` checks rather
than `try/except` — no `try/except` blocks exist in Layer 2.

**Shared array parser:**

```nim
func parseStringArrayField(node: JsonNode, fieldName: string, path: JsonPath
    ): Result[seq[string], SerdeViolation]
```

Used by `fromJsonInvalidProperties`, `fromJsonInvalidEmail`, and
`fromJsonInvalidRecipients` to parse string arrays with rigorous
per-element kind checks.

**Module:** `src/jmap_client/serde_errors.nim`

### 8.4 Types NOT Serialised

Explicit list of Layer 1 types with NO `toJson`/`fromJson`:

- `TransportError` — library-internal, constructed by Layer 4 from
  `std/httpclient` exceptions. No wire format.
- `TransportErrorKind` — discriminator enum for `TransportError`.
- `ClientError` — error wrapper, constructed by Layer 4.
- `ClientErrorKind` — discriminator enum for `ClientError`.
- `ValidationError` — returned via `wrapInner` on the error rail (lifted
  into `svkFieldParserFailed`); not itself serialised to JSON.
- `SerdeViolation` and `SerdeViolationKind` — Layer 2's own error rail.
  Translated to `ValidationError` via `toValidationError` at the L3/L4
  boundary; not serialised to JSON.
- `JsonPath`, `JsonPathElement`, `JsonPathElementKind` — diagnostic
  pointer machinery. `$path` renders RFC 6901; not parsed back.
- `ReferencableKind` — discriminator enum; `Referencable[T]`
  serialisation uses `#`-prefix key dispatch instead.
- `FilterKind` — discriminator enum; `Filter[C]` serialisation uses
  `"operator"` key presence instead.

---

## 9. Opt[T] Field Handling Convention

Cross-cutting concern documented here once, referenced throughout
Sections 3–8. See §1.9 for the leniency policy rationale.

**`toJson` convention.** `Opt.none` → omit key entirely (NOT emit
`null`). `Opt.some` → emit value. Uses the `for v in opt:` iteration
pattern (loop body executes only when some). This is consistent with
JMAP's "absent means default" semantics. The `setTooLarge` arm follows
this rule for its `maxSizeOctets: Opt[UnsignedInt]` payload field.

**`fromJson` convention.** For simple scalar `Opt` fields:
`node{"field"}.isNil` or wrong `JsonNodeKind` → `Opt.none(T)`. Correct
kind → extract value. Wrong kind maps to `none`, not an error — this is
the lenient policy (§1.9). For complex container `Opt` types
(`Opt[Table[CreationId, Id]]`), wrong container kind returns `err`.

**Per-type Opt[T] field table** (every Opt field in Layer 1 carrying
through Layer 2):

| Type | Field | Opt Semantics | Wrong Kind | Notes |
|------|-------|---------------|------------|-------|
| `Request` | `createdIds` | Absent = not provided | returns err (container) | Presence triggers proxy splitting |
| `Response` | `createdIds` | Absent = not in request | returns err (container) | Only present if request included it |
| `Comparator` | `collation` | Absent = server default | `none` | Empty-string sentinel maps to `none` |
| `RequestError` | `status` | Absent = not provided | `none` | |
| `RequestError` | `title` | Absent = not provided | `none` | |
| `RequestError` | `detail` | Absent = not provided | `none` | |
| `RequestError` | `limit` | Absent = not provided | `none` | Only meaningful for `retLimit` |
| `RequestError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |
| `MethodError` | `description` | Absent = not provided | `none` | |
| `MethodError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |
| `SetError` | `description` | Absent = not provided | `none` | |
| `SetError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |
| `SetError.setTooLarge` | `maxSizeOctets` | Absent = no cap supplied | `none` | RFC 8621 §7.5 SHOULD |

---

## 10. Serialisation Pair Inventory

Complete verification table — every Layer 1 type with its ser/de status:

| Type | Module | Pattern | Direction | L1 Constructor(s) Called | Notes |
|------|--------|---------|-----------|--------------------------|-------|
| `Id` | serde | Identity (template) | Both | `parseIdFromServer` | Lenient (server-assigned) |
| `BlobId` | serde | Identity (template) | Both | `parseBlobId` | Server-assigned |
| `UnsignedInt` | serde | Identity (template) | Both | `parseUnsignedInt` | `getBiggestInt` accessor |
| `JmapInt` | serde | Identity (template) | Both | `parseJmapInt` | `getBiggestInt` accessor |
| `MaxChanges` | serde | Identity (manual) | Both | `parseUnsignedInt`, `parseMaxChanges` | Must be > 0 |
| `Date` | serde | Identity (template) | Both | `parseDate` | String round-trip |
| `UTCDate` | serde | Identity (template) | Both | `parseUtcDate` | String round-trip |
| `AccountId` | serde | Identity (template) | Both | `parseAccountId` | Lenient (server-assigned) |
| `JmapState` | serde | Identity (template) | Both | `parseJmapState` | |
| `MethodCallId` | serde | Identity (template) | Both | `parseMethodCallId` | |
| `CreationId` | serde | Identity (template) | Both | `parseCreationId` | No `#` prefix in stored value |
| `UriTemplate` | serde | Identity (manual) | Both | `parseUriTemplate` | Layer 1 sealed object; round-trips via `$template` (rawSource) |
| `PropertyName` | serde | Identity (template) | Both | `parsePropertyName` | |
| `CapabilityKind` | — | Enum | — | `parseCapabilityKind` | Not standalone; via `rawUri` |
| `FilterOperator` | serde_framework | Enum | Both | Manual case dispatch | NOT total — `svkEnumNotRecognised` on unknown |
| `RequestErrorType` | — | — | — | `parseRequestErrorType` | Embedded in `requestError()` |
| `MethodErrorType` | — | — | — | `parseMethodErrorType` | Embedded in `methodError()` |
| `SetErrorType` | — | — | — | `parseSetErrorType` | Embedded in `setError()` |
| `MethodName` | — | — | — | `parseMethodName` | Routed via `Invocation.rawName` / `ResultReference.rawName` |
| `RefPath` | — | — | — | (parsed lazily) | Routed via `ResultReference.rawPath` |
| `CollationAlgorithm` | — | Identity-via-`$` | Inline | `parseCollationAlgorithm` | Embedded in `Comparator` and `CoreCapabilities` |
| `CoreCapabilities` | serde_session | A: Object | Both | `parseUnsignedInt` ×7, `parseCollationAlgorithm` ×N | RFC typo tolerance |
| `ServerCapability` | serde_session | B: Case | Both | `parseCapabilityKind` + sub-parse | URI dispatch; deep-copy non-core data |
| `AccountCapabilityEntry` | serde_session | A: Object | Both | `parseCapabilityKind` | Deep-copy data |
| `Account` | serde_session | A: Object | Both | — | Fields use sub-parsers |
| `Session` | serde_session | A: Composite | Both | `parseSession` + all sub-parsers | Most complex |
| `Invocation` | serde_envelope | C: Array | Both | `parseMethodCallId`, `parseInvocation` | 3-element JSON array; `rawName` round-trip |
| `Request` | serde_envelope | A: Object | Both | `parseCreationId`, `parseIdFromServer` | Opt createdIds |
| `Response` | serde_envelope | A: Object | Both | `parseJmapState`, `parseCreationId`, `parseIdFromServer` | |
| `ResultReference` | serde_envelope | A: Object | Both | `parseMethodCallId`, `parseResultReference` | `rawName`/`rawPath` round-trip |
| `Referencable[T]` | serde_envelope | C: Field | Both | Sub-parser + `ResultReference.fromJson` | `#`-prefix dispatch |
| `Comparator` | serde_framework | A: Object | Both | `parsePropertyName`, `parseCollationAlgorithm`, `parseComparator` | `isAscending` default |
| `Filter[C]` | serde_framework | C: Recursive | Both | Mixin (toJson) + callback (fromJson) | Generic, depth-limited |
| `AddedItem` | serde_framework | A: Object | Both | `Id.fromJson`, `UnsignedInt.fromJson`, `initAddedItem` | |
| `RequestError` | serde_errors | A: Object | Both | `requestError` | `collectExtras` |
| `MethodError` | serde_errors | A: Object | Both | `methodError` | `collectExtras` |
| `SetError` | serde_errors | B: Case | Both | `setError`, `setErrorInvalidProperties`, `setErrorAlreadyExists`, `setErrorBlobNotFound`, `setErrorInvalidEmail`, `setErrorTooManyRecipients`, `setErrorInvalidRecipients`, `setErrorTooLarge` | Defensive fallback; 7 payload variants |
| `TransportError` | — | — | Not serialised | — | Library-internal |
| `TransportErrorKind` | — | — | Not serialised | — | Discriminator enum |
| `ClientError` | — | — | Not serialised | — | Error wrapper |
| `ClientErrorKind` | — | — | Not serialised | — | Discriminator enum |
| `ValidationError` | — | — | Not serialised | — | Lifted into `svkFieldParserFailed` |
| `SerdeViolation` | — | — | Not serialised | — | L2 error rail |
| `JsonPath` | — | — | Not serialised | — | RFC 6901 pointer; rendered via `$` |
| `ReferencableKind` | — | — | Not serialised | — | Discriminator enum |
| `FilterKind` | — | — | Not serialised | — | Discriminator enum |

---

## 11. Round-Trip Invariants

Properties that must hold for every serialised type:

- **Identity:** `T.fromJson(x.toJson()) == x` for all `x` produced by
  `fromJson` or by Layer 3 builders. Values constructed by direct
  Layer 1 object construction may violate wire-format invariants not
  expressible in the type system (e.g., empty `Invocation.name`).
  Round-trip tests compare parsed values (structural equality), not
  JSON strings (Table iteration order is non-deterministic).
- **Lossless raw fields:** For error types, capabilities, methods, and
  result references with catch-all variants, the raw string is preserved
  through round-trip (`rawType`, `rawUri`, `rawName`, `rawPath`).
  `$enumVal` is never used for serialisation of catch-all-bearing
  enums.
- **Opt[T] omission:** `Opt.none` values produce no JSON key; parsing
  absent keys produces `Opt.none`.
- **Invocation format:** `Invocation.toJson` always produces a 3-element
  `JArray`, never `JObject`.
- **Referencable dispatch:** `rkDirect` values serialise without `#`
  prefix; `rkReference` values serialise with `#` prefix. Round-trip
  preserves the variant.
- **Capability URI uniqueness:** `Session.toJson` assumes no duplicate
  `rawUri` in `capabilities`. Round-trip identity holds when this
  precondition is met (always true for `fromJson`-constructed Sessions).
- **Losslessness scope:** Round-trip losslessness applies to fields
  stored in the Layer 1 type. Error types (`RequestError`,
  `MethodError`, `SetError`) preserve non-standard server fields via
  `extras: Opt[JsonNode]`. `Session`, `Account`, and `CoreCapabilities`
  do not carry an `extras` field — unknown fields are dropped during
  deserialisation. This is a Layer 1 scope decision, not a Layer 2 gap.
- **JSON Pointer paths:** `SerdeViolation.path` renders via `$` to a
  valid RFC 6901 pointer. Empty path → `""` (root). Object keys are
  escaped (`~` → `~0`, `/` → `~1`, in that order). Indices render in
  decimal.
- **`SetError` variant fidelity:** Payload-bearing variants always emit
  their RFC field (even when the seq is empty), so that round-trip
  preserves the variant. `setTooLarge` is the sole exception — its
  `maxSize` is `Opt[UnsignedInt]` and is omitted when `none`, per RFC
  8621 §7.5 SHOULD.

---

## 12. Module File Layout

**File header template** (required for `reuse lint` — every `.nim` file):

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}
```

SPDX header on line 1. No blank line before. `{.push raises: [],
noSideEffect.}` is applied to every Layer 2 source module — the
compiler enforces totality and purity. `{.experimental:
"strictCaseObjects".}` enforces case-object branch-tracking on
variant-field reads.

**Docstring requirement** (required for nimalyzer `hasDoc` rule): every
exported `func`/`template` must have a `##` docstring. Comments and
docstrings use British English spelling (CLAUDE.md §Language).

**Source modules:**

```
src/jmap_client/
  serialisation.nim      <- Re-export hub (Layer 2 equivalent of types.nim);
                           imports and re-exports serde + all domain modules
  serde.nim              <- JsonPath, SerdeViolation, toValidationError,
                           combinators (expectKind, fieldJString, ...),
                           shared helpers (collectExtras, parseIdArray,
                           parseKeyedTable, etc.), serde templates,
                           primitive/identifier ser/de
  serde_session.nim      <- CoreCapabilities, ServerCapability,
                           AccountCapabilityEntry, Account, Session
  serde_envelope.nim     <- Invocation, Request, Response,
                           ResultReference, Referencable[T] helpers
  serde_framework.nim    <- Comparator, Filter[C], AddedItem,
                           FilterOperator
  serde_errors.nim       <- RequestError, MethodError, SetError
                           (plus private optString/optInt helpers and
                           the seven setError variant parsers)
```

**Test modules** (testament auto-discovers `tests/t*.nim`):

```
tests/serde/
  tserde.nim                <- Shared helpers, primitive/identifier/enum
                              round-trips
  tserde_session.nim        <- Session, plus references to capabilities
                              and account tests
  tserde_envelope.nim       <- Invocation, Request, Response,
                              ResultReference, Referencable[T]
  tserde_framework.nim      <- Comparator, Filter[C], AddedItem,
                              FilterOperator
  tserde_errors.nim         <- RequestError, MethodError, SetError
  tserde_capabilities.nim   <- Capability discovery and serialisation
  tserde_account.nim        <- Account-specific tests
  tserde_adversarial.nim    <- Adversarial input tests
  tserde_properties.nim     <- Property-related tests
  tserde_type_safety.nim    <- Type safety verification tests
  tserialisation.nim        <- Integration smoke test; verifies all
                              toJson/fromJson pairs accessible via hub
```

Tests use `doAssert` (testament), block-scoped tests with labelled
blocks, and existing `massertions.nim` helpers. No `unittest` module.

**Import graph** (flat — no internal Layer 2 dependencies):

```
Layer 1: types.nim (re-exports all L1 modules)
  ^          ^          ^          ^          ^
  |          |          |          |          |
serde.nim  serde_session  serde_envelope  serde_framework  serde_errors
  ^          |          |          |          |
  +----------+----------+----------+----------+
  (all domain serde modules import serde.nim for shared helpers)

serialisation.nim <- re-exports serde + all domain modules
  (Layer 3 imports serialisation.nim)
```

`serialisation.nim` is the re-export hub (Layer 2 equivalent of
`types.nim`), re-exporting `serde.nim` and all domain serde modules.
`serde.nim` defines the `JsonPath`/`SerdeViolation` ADT, the translator,
all combinators and shared helpers, and primitive/identifier ser/de
functions (via templates). Domain serde modules import `serde.nim` for
the combinators and ADT — they do NOT import each other. No circular
dependencies.

**Downstream:** Layer 3 modules import `serialisation.nim` (which
re-exports everything). `methods.nim` (standard method request/response
types) and the `mail/` entity modules consume the combinators
(`expectKind`, `fieldOfKind` plus the kind-specific shortcuts
`fieldJObject` / `fieldJString` / `fieldJArray` / `fieldJBool` /
`fieldJInt`, `optField`, `optJsonField`, `expectLen`, `nonEmptyStr`),
the bulk helpers (`collectExtras`, `parseIdArray`, `parseIdArrayField`,
`parseOptIdArray`, `parseKeyedTable`, `collapseNullToEmptySeq`,
`optToJsonOrNull`, `optStringToJsonOrNull`), the `wrapInner` bridge,
all the primitive/identifier `toJson`/`fromJson` pairs, and
`SetError.fromJson` from `serde_errors.nim`. Tests import individual
serde modules for focused testing.

**Why six files, not one.** With ~30 ser/de pairs producing roughly
1600 lines of content, six files provide: (a) independently testable
modules (each test file mirrors one serde file), (b) parallel structure
with Layer 1's module grouping, (c) bounded content-module size
(~180–530 lines each; `serialisation.nim` is the small re-export hub),
(d) acyclic import graph (`serialisation.nim` re-exports without
creating import cycles). The flat import graph means no cost to the
split.

---

## 13. Test Fixtures

### 13.1 RFC §2.1 Session Golden Test (Round-Trip)

The complete Session JSON from RFC §2.1 (lines 735–817):

```json
{
  "capabilities": {
    "urn:ietf:params:jmap:core": {
      "maxSizeUpload": 50000000,
      "maxConcurrentUpload": 8,
      "maxSizeRequest": 10000000,
      "maxConcurrentRequest": 8,
      "maxCallsInRequest": 32,
      "maxObjectsInGet": 256,
      "maxObjectsInSet": 128,
      "collationAlgorithms": [
        "i;ascii-numeric",
        "i;ascii-casemap",
        "i;unicode-casemap"
      ]
    },
    "urn:ietf:params:jmap:mail": {},
    "urn:ietf:params:jmap:contacts": {},
    "https://example.com/apis/foobar": {
      "maxFoosFinangled": 42
    }
  },
  "accounts": {
    "A13824": {
      "name": "john@example.com",
      "isPersonal": true,
      "isReadOnly": false,
      "accountCapabilities": {
        "urn:ietf:params:jmap:mail": {},
        "urn:ietf:params:jmap:contacts": {}
      }
    },
    "A97813": {
      "name": "jane@example.com",
      "isPersonal": false,
      "isReadOnly": true,
      "accountCapabilities": {
        "urn:ietf:params:jmap:mail": {}
      }
    }
  },
  "primaryAccounts": {
    "urn:ietf:params:jmap:mail": "A13824",
    "urn:ietf:params:jmap:contacts": "A13824"
  },
  "username": "john@example.com",
  "apiUrl": "https://jmap.example.com/api/",
  "downloadUrl": "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
  "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
  "eventSourceUrl": "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
  "state": "75128aab4b1b"
}
```

**Expected parsed values** (same as Layer 1 §12.1):

- `session.capabilities` has 4 entries (ckCore, ckMail, ckContacts, ckUnknown)
- `session.coreCapabilities.maxSizeUpload == UnsignedInt(50000000)`
- `session.coreCapabilities.collationAlgorithms` contains 3 algorithms
- `session.accounts` has 2 entries (A13824, A97813)
- `session.accounts[AccountId("A13824")].isPersonal == true`
- `session.primaryAccounts["urn:ietf:params:jmap:mail"] == AccountId("A13824")`
- `session.username == "john@example.com"`
- `session.state == JmapState("75128aab4b1b")`

**Round-trip test:**
`Session.fromJson(session.toJson()).get() == session`

Note: RFC example uses `"maxConcurrentRequest"` (singular) — typo
tolerance ensures this parses correctly.

### 13.2 RFC §3.3.1 Request Example

```json
{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["method1", {"arg1": "arg1data", "arg2": "arg2data"}, "c1"],
    ["method2", {"arg1": "arg1data"}, "c2"],
    ["method3", {}, "c3"]
  ]
}
```

- `request.using == @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"]`
- `request.methodCalls.len == 3`
- `request.methodCalls[0].rawName == "method1"`
  (and `request.methodCalls[0].name == mnUnknown`, since `"method1"`
  has no backing literal)
- `request.methodCalls[0].methodCallId == MethodCallId("c1")`
- `request.createdIds.isNone`

### 13.3 RFC §3.4.1 Response Example

```json
{
  "methodResponses": [
    ["method1", {"arg1": 3, "arg2": "foo"}, "c1"],
    ["method2", {"isBlah": true}, "c2"],
    ["anotherResponseFromMethod2", {"data": 10, "yetmoredata": "Hello"}, "c2"],
    ["error", {"type": "unknownMethod"}, "c3"]
  ],
  "sessionState": "75128aab4b1b"
}
```

- `response.methodResponses.len == 4`
- `response.methodResponses[2].methodCallId == MethodCallId("c2")`
- `response.methodResponses[3].rawName == "error"` (method-level error)
- `response.sessionState == JmapState("75128aab4b1b")`
- `response.createdIds.isNone`

### 13.4 Edge Cases per Type

| Type | Input JSON | Expected | Reason |
|------|-----------|----------|--------|
| `Id` (deser) | `%"abc123-_XYZ"` | `ok` | Valid base64url (lenient) |
| `Id` (deser) | `%42` | `err(svkWrongKind)` | Wrong JSON kind (JInt, not JString) |
| `Id` (deser) | `nil` (missing field) | `err(svkNilNode)` | Nil JsonNode |
| `Id` (deser) | `newJNull()` | `err(svkWrongKind)` | JNull, not JString |
| `Id` (deser) | `%*[1,2,3]` | `err(svkWrongKind)` | JArray, not JString |
| `Id` (deser) | `%""` | `err(svkFieldParserFailed)` | Empty string (parseIdFromServer rejects) |
| `UnsignedInt` (deser) | `%0` | `ok` | Minimum valid |
| `UnsignedInt` (deser) | `%9007199254740991` | `ok` | 2^53-1, maximum valid |
| `UnsignedInt` (deser) | `%(-1)` | `err(svkFieldParserFailed)` | Negative (parseUnsignedInt rejects) |
| `UnsignedInt` (deser) | `%"42"` | `err(svkWrongKind)` | Wrong JSON kind (JString, not JInt) |
| `UnsignedInt` (deser) | `nil` | `err(svkNilNode)` | Nil JsonNode |
| `UnsignedInt` (deser) | `newJNull()` | `err(svkWrongKind)` | JNull, not JInt |
| `JmapInt` (deser) | `%(-9007199254740991)` | `ok` | -(2^53-1), minimum valid |
| `JmapInt` (deser) | `%"hello"` | `err(svkWrongKind)` | Wrong JSON kind |
| `Date` (deser) | `%"2014-10-30T14:12:00+08:00"` | `ok` | RFC example |
| `Date` (deser) | `%42` | `err(svkWrongKind)` | Wrong JSON kind |
| `Date` (deser) | `%"2014-10-30t14:12:00Z"` | `err(svkFieldParserFailed)` | Lowercase 't' (parseDate rejects) |
| `UTCDate` (deser) | `%"2014-10-30T06:12:00Z"` | `ok` | RFC example |
| `UTCDate` (deser) | `%"2014-10-30T06:12:00+00:00"` | `err(svkFieldParserFailed)` | Must be Z, not +00:00 |
| `AccountId` (deser) | `%"A13824"` | `ok` | RFC §2.1 example |
| `AccountId` (deser) | `%""` | `err(svkFieldParserFailed)` | Empty string |
| `AccountId` (deser) | `%42` | `err(svkWrongKind)` | Wrong JSON kind |
| `JmapState` (deser) | `%"75128aab4b1b"` | `ok` | RFC §2.1 example |
| `JmapState` (deser) | `%""` | `err(svkFieldParserFailed)` | Empty string |
| `MethodCallId` (deser) | `%"c1"` | `ok` | RFC example |
| `MethodCallId` (deser) | `%""` | `err(svkFieldParserFailed)` | Empty string |
| `CreationId` (deser) | `%"abc"` | `ok` | Valid creation ID |
| `CreationId` (deser) | `%"#abc"` | `err(svkFieldParserFailed)` | Must not include `#` prefix |
| `BlobId` (deser) | `%"B-abc"` | `ok` | Valid blob ID |
| `PropertyName` (deser) | `%"name"` | `ok` | Valid property name |
| `PropertyName` (deser) | `%""` | `err(svkFieldParserFailed)` | Empty property name |
| `Invocation` (deser) | `%*["Mailbox/get", {}, "c1"]` | `ok` | Valid 3-element array |
| `Invocation` (deser) | `%*{"name": "x", "args": {}, "id": "c1"}` | `err(svkWrongKind)` | JSON object instead of array |
| `Invocation` (deser) | `%*["Mailbox/get", {}]` | `err(svkArrayLength)` | Only 2 elements |
| `Invocation` (deser) | `%*["Mailbox/get", {}, "c1", "extra"]` | `err(svkArrayLength)` | 4 elements |
| `Invocation` (deser) | `%*[42, {}, "c1"]` | `err(svkWrongKind)` | name must be JString |
| `Invocation` (deser) | `%*["Mailbox/get", "notobject", "c1"]` | `err(svkWrongKind)` | arguments must be JObject |
| `Invocation` (deser) | `%*["Mailbox/get", {}, 42]` | `err(svkWrongKind)` | callId must be JString |
| `Invocation` (deser) | `%*["", {}, "c1"]` | `err(svkEmptyRequired)` | Empty method name |
| `Invocation` (round-trip) | Valid Invocation | `toJson` produces JArray len 3 | Format verification |
| `Invocation` (round-trip) | Valid Invocation | `Invocation.fromJson(x.toJson()).get() == x` | Identity (rawName preserved) |
| `Session` (deser) | RFC §2.1 JSON | `ok` | Golden test |
| `Session` (deser) | Missing `capabilities` key | `err(svkMissingField)` | Required field |
| `Session` (deser) | `capabilities` not an object | `err(svkWrongKind)` | Wrong kind |
| `Session` (deser) | Missing core capability | `err(svkFieldParserFailed)` | `parseSession` rejects |
| `Session` (deser) | Unknown capability URIs | `ok` with `ckUnknown` | Preserved via rawUri |
| `Session` (deser) | `maxConcurrentRequest` (singular) | `ok` | RFC typo tolerance |
| `Session` (deser) | Extra unknown top-level fields | `ok` | Ignored per RFC |
| `Session` (deser) | Missing `primaryAccounts` key | `err(svkMissingField)` | Required field |
| `Session` (deser) | `primaryAccounts` value is integer | `err(svkWrongKind)` | Inner expectKind rejects |
| `Session` (deser) | Empty accounts object | `ok` | |
| `CoreCapabilities` (deser) | Valid with all 8 fields | `ok` | |
| `CoreCapabilities` (deser) | Missing required field | `err(svkMissingField/svkNilNode)` | Inner field deserialiser rejects |
| `CoreCapabilities` (deser) | `"maxSizeUpload": "string"` | `err(svkWrongKind)` | Wrong kind for UnsignedInt |
| `CoreCapabilities` (deser) | `"maxSizeUpload": -1` | `err(svkFieldParserFailed)` | `parseUnsignedInt` rejects |
| `CoreCapabilities` (deser) | Empty `collationAlgorithms` | `ok` | Empty HashSet |
| `ServerCapability` (deser) | `ckCore` with valid data | `ok` | |
| `ServerCapability` (deser) | `ckCore` missing required field | `err` | Propagated from CoreCapabilities |
| `ServerCapability` (deser) | Unknown URI + arbitrary JSON | `ok` with `ckUnknown` | rawData deep-copied |
| `ServerCapability` (deser) | Known non-core URI (ckMail) | `ok` with `rawData` | |
| `Referencable` (deser) | `"ids": [...]` | `rkDirect` | Direct value |
| `Referencable` (deser) | `"#ids": {"resultOf":..}` | `rkReference` | Reference |
| `Referencable` (deser) | Reference missing `resultOf` | `err(svkMissingField)` | Invalid reference |
| `Referencable` (deser) | Both `"ids"` and `"#ids"` present | `err(svkConflictingFields)` | RFC 8620 §3.7: mutual exclusion |
| `Referencable` (deser) | `"#ids": 42` (wrong kind) | `err(svkWrongKind)` | `#` prefix is a semantic commitment — malformed reference is an error |
| `Referencable` (deser) | `"#ids": "string"` (wrong kind) | `err(svkWrongKind)` | Reference value must be JObject |
| `Filter` (deser) | Condition (no `operator` key) | `fkCondition` | Leaf node |
| `Filter` (deser) | Operator with conditions | `fkOperator` | Composed node |
| `Filter` (deser) | Nested operators (depth 2) | `ok` | Recursive |
| `Filter` (deser) | Operator with empty conditions | `ok` | Valid per RFC |
| `Filter` (deser) | Operator missing `conditions` | `err(svkMissingField)` | Required field |
| `Filter` (deser) | Nesting exceeds MaxFilterDepth | `err(svkDepthExceeded)` | Stack overflow defence |
| `SetError` (deser) | `{"type": "forbidden"}` | `setForbidden` | Non-payload variant |
| `SetError` (deser) | `{"type": "invalidProperties", "properties": ["name"]}` | `setInvalidProperties` | With variant data |
| `SetError` (deser) | `{"type": "invalidProperties"}` | `setUnknown` | Defensive fallback — missing properties |
| `SetError` (deser) | `{"type": "alreadyExists", "existingId": "msg42"}` | `setAlreadyExists` | With variant data |
| `SetError` (deser) | `{"type": "alreadyExists"}` | `setUnknown` | Defensive fallback — missing existingId |
| `SetError` (deser) | `{"type": "blobNotFound", "notFound": ["B1"]}` | `setBlobNotFound` | With variant data |
| `SetError` (deser) | `{"type": "blobNotFound"}` | `setUnknown` | Defensive fallback |
| `SetError` (deser) | `{"type": "tooLarge"}` | `setTooLarge` with `maxSizeOctets.isNone` | maxSize is SHOULD, not MUST |
| `SetError` (deser) | `{"type": "tooLarge", "maxSize": 50000000}` | `setTooLarge` with `Opt.some(50000000)` | |
| `SetError` (deser) | `{"type": "tooManyRecipients", "maxRecipients": 100}` | `setTooManyRecipients` | With variant data |
| `SetError` (deser) | `{"type": "invalidRecipients", "invalidRecipients": ["x@y"]}` | `setInvalidRecipients` | With variant data |
| `SetError` (deser) | `{"type": "invalidEmail", "properties": ["from"]}` | `setInvalidEmail` | With variant data |
| `SetError` (deser) | `{"type": "vendorSpecific"}` | `setUnknown` | rawType preserved |
| `SetError` (deser) | `{"type": "forbidden", "properties": ["name"]}` | `setForbidden` with `extras` containing `properties` | Per-variant known keys |
| `RequestError` (deser) | Valid RFC 7807 with known type URI | `ok` | Parsed errorType |
| `RequestError` (deser) | Unknown type URI | `ok` with `retUnknown` | rawType preserved |
| `RequestError` (deser) | With extra fields | extras collected in `Opt[JsonNode]` | Lossless |
| `RequestError` (deser) | Missing `type` field | `err(svkMissingField)` | Required |
| `RequestError` (deser) | `"type": 42` (wrong kind) | `err(svkWrongKind)` | `fieldJString` rejects JInt |
| `MethodError` (deser) | Valid with known type | `ok` | |
| `MethodError` (deser) | Unknown type | `ok` with `metUnknown` | rawType preserved |
| `MethodError` (deser) | With `description` | `description.isSome` | |
| `MethodError` (deser) | With extra server fields | extras collected | |
| `MethodError` (deser) | `"description": 42` (wrong kind) | `ok` with `description.isNone` | §1.9 lenient |
| `SetError` (deser) | `"description": 42` (wrong kind) | `ok` with `description.isNone` | §1.9 lenient |
| `Request` (deser) | With `createdIds` | `Opt.some` | |
| `Request` (deser) | Without `createdIds` | `Opt.none` | |
| `Response` (deser) | With `createdIds` | `Opt.some` | |
| `Response` (deser) | `sessionState` via `parseJmapState` | validated | |
| `Response` (deser) | Empty `methodResponses` | `ok` | |
| `Response` (deser) | Missing `sessionState` | `err(svkMissingField)` | Required |
| `Comparator` (deser) | All fields present | `ok` | |
| `Comparator` (deser) | Missing `isAscending` | `ok` with default `true` | RFC default |
| `Comparator` (deser) | Missing `property` | `err(svkMissingField)` | Required |
| `Comparator` (deser) | `{"property": 42, "isAscending": true}` | `err(svkWrongKind)` | Wrong kind for property |
| `Comparator` (deser) | `"collation": ""` | `ok` with `collation.isNone` | Empty-string sentinel |
| `AddedItem` (deser) | Valid `{"id": "x", "index": 5}` | `ok` | |
| `AddedItem` (deser) | Invalid `id` | `err(svkFieldParserFailed)` | Propagated from Id.fromJson |
| `ResultReference` (deser) | Valid | `ok` | |
| `FilterOperator` (deser) | `"AND"` | `foAnd` | |
| `FilterOperator` (deser) | `"CUSTOM"` | `err(svkEnumNotRecognised)` | Not total — exhaustive per RFC |

---

## 14. Design Decisions Summary

| ID | Decision | Alternatives | Rationale |
|----|----------|-------------|-----------|
| D2.1 | Error type: structured `SerdeViolation` ADT with RFC 6901 `JsonPath` | Reuse `ValidationError` directly | Path threading + variant-specific payload yields precise diagnostics; sole `toValidationError` translator at the boundary keeps the wire shape stable |
| D2.2 | Module layout: 6 files (5 content + 1 re-export hub) | Single `serde.nim` | Independently testable; mirrors L1 grouping; bounded file size |
| D2.3 | Parse boundary: Layer 4 concern | `safeParseJson` in Layer 2 | Layer 2 receives `JsonNode`, not raw strings. `string -> JsonNode` requires exception handling, which belongs in Layer 4 |
| D2.4 | Generic `Filter[C]`: mixin for `toJson`, callback for `fromJson` | All-mixin or all-callback | `toJson` needs no path/Result threading and works under `mixin`; `fromJson` threads path + Result and must take a typed callback |
| D2.5 | `Referencable[T]`: field-level scope | Standalone `toJson`/`fromJson` | `#`-prefix is on JSON key, not value — containing object must dispatch |
| D2.6 | RFC typo: accept both singular/plural for `maxConcurrentRequest(s)` | Strict plural only | RFC §2.1 example has singular; servers may follow |
| D2.7 | `Opt[T]`: omit key when `isNone` | Emit `null` | JMAP "absent means default" semantics |
| D2.8 | `fromJson` returns `Result[T, SerdeViolation]` | Raises exception | ROP composes via `?` and `wrapInner`; compiler enforces `{.push raises: [].}` |
| D2.9 | Int accessor: `getBiggestInt` | `getInt` | `UnsignedInt`/`JmapInt` are `distinct int64`; `getInt` may truncate on 32-bit |
| D2.10 | Provide `toJson` for all types | Deser-only for server types | Round-trip testing and debugging require both directions |
| D2.11 | Enum deser: total (except `FilterOperator`) | All return err on unknown | Matches L1 total parse functions; `FilterOperator` exhaustive per RFC |
| D2.12 | `extras` collection: `collectExtras` helper | Inline per-type | Shared pattern across `RequestError`, `MethodError`, `SetError` |
| D2.13 | `toJson` output: compact (default `$`) | Pretty-printed | Wire format; human readability via `pretty()` at call site if needed |
| D2.14 | String encoding: UTF-8, automatic escaping | Manual escaping | `std/json` handles UTF-8 and escaping per I-JSON (RFC 7493) |
| D2.15 | `Opt[T]` wrong kind: lenient (`none`) | Strict (return err) | Client library parsing server data — Postel's law. Strictness on error-type supplementary fields loses the critical `type` field (§1.9) |
| D2.16 | All routines `func`; callback parameters with `{.noSideEffect, raises: [].}` | All `proc` | `func` provides compiler-enforced purity; module-level `{.push raises: [], noSideEffect.}`; annotated proc-type parameters preserve purity through callbacks |
| D2.17 | `Referencable` mutual exclusion | `#`-prefixed key takes precedence | RFC 8620 §3.7 specifies both forms cannot coexist; reject ambiguity |
| D2.18 | `Filter[C]` depth limiting | No depth limit | Defence-in-depth against `StackOverflowDefect`; MaxFilterDepth = 128 |
| D2.19 | `toJson` extras collision guard | Include all extras | Prevents manual construction from corrupting wire format by skipping extras with known-key names |
| D2.20 | Distinct type serde via templates | Per-type manual functions | Templates eliminate boilerplate for 9 string types + 2 int types; pattern is identical |
| D2.21 | `Invocation` / `ResultReference` round-trip via `rawName` / `rawPath` | `$enumVal` on `MethodName` / `RefPath` | Catch-all variants (`mnUnknown`) collapse to symbol name; `raw*` preserves the verbatim wire string |
| D2.22 | `SetError` payload-bearing `toJson` always emits the RFC field | Omit empty arrays | Variant identity must round-trip; an absent field on a payload-bearing variant maps back to `setUnknown` |
| D2.23 | Non-core capability data deep-copied via `.copy()` | Share `JsonNode` ref | ARC double-free hazard when input tree and parsed object are destroyed independently |
| D2.24 | `setTooLarge.maxSize` is `Opt[UnsignedInt]` | Required `UnsignedInt` | RFC 8621 §7.5 marks the field SHOULD, not MUST |

---

## Appendix: RFC Section Cross-Reference

| Type | RFC 8620 / 8621 Section | Wire Format |
|------|-----------------------|-------------|
| `Id` | RFC 8620 §1.2 (lines 287–319) | JSON String |
| `BlobId` | RFC 8620 §1.2 / §6 | JSON String |
| `UnsignedInt` | RFC 8620 §1.3 (lines 320–342) | JSON Number |
| `JmapInt` | RFC 8620 §1.3 (lines 320–342) | JSON Number |
| `Date` | RFC 8620 §1.4 (lines 343–354) | JSON String (RFC 3339) |
| `UTCDate` | RFC 8620 §1.4 (lines 343–354) | JSON String (RFC 3339, Z suffix) |
| `Session` | RFC 8620 §2 (lines 477–733) | JSON Object |
| `CoreCapabilities` | RFC 8620 §2 (lines 511–572) | JSON Object |
| `Account` | RFC 8620 §2 (lines 583–643) | JSON Object |
| `Invocation` | RFC 8620 §3.2 (lines 865–881) | JSON Array (3 elements) |
| `Request` | RFC 8620 §3.3 (lines 882–974) | JSON Object |
| `Response` | RFC 8620 §3.4 (lines 975–1035) | JSON Object |
| `RequestError` | RFC 8620 §3.6.1 (lines 1079–1136), RFC 7807 | JSON Object (problem details) |
| `MethodError` | RFC 8620 §3.6.2 (lines 1137–1219) | JSON Object (via error Invocation) |
| `ResultReference` | RFC 8620 §3.7 (lines 1220–1493) | JSON Object |
| `Referencable[T]` | RFC 8620 §3.7 (lines 1220–1493) | `#`-prefix key dispatch |
| `Comparator` | RFC 8620 §5.5 (lines 2339–2638) | JSON Object |
| `Filter[C]` | RFC 8620 §5.5 (lines 2368–2394) | JSON Object (recursive) |
| `AddedItem` | RFC 8620 §5.6 (lines 2639–2819) | JSON Object |
| `SetError` (core arms) | RFC 8620 §5.3 (lines 2060–2190), §5.4 (lines 2191–2338) | JSON Object |
| `SetError` (mail arms) | RFC 8621 §4.6 / §7.5 | JSON Object |
| `CollationAlgorithm` | RFC 8620 §5.5; RFC 4790 | JSON String (identifier) |
