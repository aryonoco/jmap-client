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
framework types (§5.3 PatchObject, §5.5 Filter/Comparator, §5.6 AddedItem),
and per-item set errors. Protocol logic (Layer 3), transport (Layer 4), and
the C ABI (Layer 5) are out of scope. Binary data (§6) and push (§7) are
deferred; see architecture.md §4.5–4.6.

**Relationship to architecture-options.md.** That document records broad
decisions across all 5 layers. This document is the detailed specification for
Layer 2 only. Decisions here are consistent with — and build upon — the
architecture document's choices 2.1A (std/json manual ser/de), 2.2A
(camelCase zero conversion), and 2.3 (Referencable `#`-prefix dispatch).
Layer 1 decisions that constrain Layer 2: 1.1A (distinct types require
unwrap/wrap in `toJson`/`fromJson`), 1.2A (case object capabilities with
enum + fallback), 1.3B (Referencable[T] variant type), 1.5B (opaque
PatchObject — smart constructors only), 1.6C (three railways), 1.7C
(lossless round-trip via rawType/rawUri).

**Design principles.** Every decision follows:

- **Railway Oriented Programming** — `fromJson` is a **parsing entry point
  into the construction railway** (not a new lifecycle phase). It returns
  `Result[T, ValidationError]` — the same error type as Layer 1 smart
  constructors — so `?` composes `fromJson` field extraction with Layer 1
  smart constructors in a single pipeline. Layer 4 lifts the result to
  `JmapResult[T]` (transport railway) at the IO boundary.
- **Functional Core, Imperative Shell** — **Layer 2 is entirely `func`.**
  No `proc` **definitions**, no exception handling, no `try/except`.
  Callback parameters use `proc {.noSideEffect.}` for Nim's type system
  (functionally equivalent to `func`; see §1.2). Every function in
  Layer 2 is a pure transform: `JsonNode → Result[T, ValidationError]`
  (deserialisation) or `T → JsonNode` (serialisation). Layer 2 receives
  pre-parsed `JsonNode` trees — the `string → JsonNode` step requires
  exception handling (`std/json.parseJson` raises `JsonParsingError`) and
  is therefore a Layer 4 concern. This cleanly preserves the functional
  core / imperative shell boundary: Layers 1–3 are pure; Layer 4 is the
  sole `proc` boundary.
- **Immutability by default** — `let` bindings. Local `var` only for building
  `JsonNode` trees (pattern (a) from architecture: local variable inside
  `func` building a return value from stdlib containers whose APIs require
  mutation, e.g., `var obj = newJObject(); obj["key"] = val`). `strictFuncs`
  enforces the mutation does not escape.
- **Total functions** — `{.push raises: [].}` on every module. **Every
  `fromJson` must validate `JsonNodeKind` before extraction** — `getStr`,
  `getBiggestInt`, `getBool`, `getFloat` silently return defaults on wrong
  kinds, which would produce incorrect values rather than errors. The
  canonical pattern is: check `node.kind`, return
  `err(parseError(...))` on mismatch, then extract. For container types:
  check `JObject`/`JArray` before iterating.
- **Parse, don't validate** — `fromJson` produces well-typed values by
  calling Layer 1 smart constructors, or structured `ValidationError`. Every
  `fromJson` that produces a Layer 1 type with a smart constructor MUST call
  it (never direct object construction bypassing validation). Types without
  smart constructors (`Account`, `CoreCapabilities`) are constructed directly
  after validating each field individually.
- **Make illegal states unrepresentable** — deserialisation constructs
  Layer 1 types via their smart constructors, never bypassing invariants.
  Distinct types require explicit unwrap (`string(id)`) for `toJson` and
  explicit wrap via smart constructor for `fromJson`.
- **Dual validation strictness** — server-originated data uses lenient
  constructors (`parseIdFromServer`, `parseAccountId`); client-originated
  data uses strict constructors (`parseId`). Each `fromJson` documents which
  constructor it calls.
- **I-JSON compliance** — all serialised output is valid I-JSON (RFC 7493).
  `std/json` produces I-JSON by default (UTF-8, no duplicate keys via
  `%*{}`).

**Compiler flags.** These constrain every function definition (from
`jmap_client.nimble`):

```
--mm:arc
--experimental:strictDefs
--experimental:strictNotNil
--experimental:strictFuncs
--experimental:strictCaseObjects
--styleCheck:error
{.push raises: [].}  (per-module)
```

---

## Standard Library Utilisation

Layer 2 maximises use of the Nim standard library. Every adoption and
rejection has a concrete reason tied to the strict compiler constraints.

### Modules used in Layer 2

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/json` | `%`, `%*`, `newJObject`, `newJArray`, `{key}` accessor, `getStr`, `getBiggestInt`, `getBool`, `getFloat`, `getElems`, `getFields`, `JsonNodeKind` | Layer 1 selectively imports `JsonNode`/`JsonNodeKind` as data types only; Layer 2 needs the raises-free accessors and construction API. `parseJson` is NOT used — the `string → JsonNode` boundary is a Layer 4 concern |
| `std/tables` | `Table` iteration via `pairs`, construction via `[]=`, `initTable` | Session accounts, primaryAccounts, createdIds ser/de |
| `std/sets` | `toHashSet` | `CoreCapabilities.collationAlgorithms`: JSON array → `HashSet[string]` |
| `std/sugar` | `collect` | Building seqs from iterators — architecture convention for Layer 2+ (L1 has no collection-building operations) |
| `std/strutils` | `startsWith` | `#`-prefix detection for `Referencable[T]` field dispatch |

### Modules evaluated and rejected

| Module | Reason not used in Layer 2 |
|--------|---------------------------|
| `std/jsonutils` | `jsonTo` and the stdlib `fromJson` raise exceptions (`KeyError`, `JsonKindError`); incompatible with `{.push raises: [].}` and manual field-level validation. |
| `std/marshal` | Deprecated; uses `streams`; incompatible with `--mm:arc`. |
| `jsony` (third-party) | Uses exceptions internally; incompatible with `raises: []`. Implicit parsing prevents field-level validation injection without hooks. Compatibility with `--mm:arc` + `strictFuncs` + `strictNotNil` unverified. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `node{key}` returns `nil` on missing key (raises-free) | Primary navigation accessor throughout Layer 2. Always nil-safe. Chaining `node{"a"}{"b"}.getStr("")` is safe — returns `""` if any level is missing. |
| `node["key"]` raises `KeyError` | NEVER used — incompatible with `{.push raises: [].}`. |
| `getInt` returns `int` (pointer-sized); `getBiggestInt` returns `BiggestInt` (`int64`) | `UnsignedInt` and `JmapInt` are `distinct int64` — must use `getBiggestInt` to avoid truncation on 32-bit platforms. |
| `%` on distinct types does not auto-unwrap | Must explicitly unwrap: `%string(id)`, `%int64(val)`. The `%` operator has overloads for `string`, `int64`, `float`, `bool`, `seq[T]`, `Table[K,V]`, and `Option[T]` (stdlib only — no overload for `Opt[T]` from nim-results). |
| `$` on string-backed enum returns the backing string; catch-all variants without backing return the symbolic name | `$ckCore` → `"urn:ietf:params:jmap:core"` but `$ckUnknown` → `"ckUnknown"` (not a URI). Serialisation must use `rawUri`/`rawType` from the containing object for lossless round-trip (Decision 1.7C), never `$enumVal`. |
| `node.len` is NOT nil-safe — crashes on nil with `FieldDefect` | Always check `isNil` before `.len`, or use `getElems(@[]).len` as safe alternative. Split nil/kind checks from len checks for clarity. |
| `items`/`pairs`/`keys` iterators assert node kind | Assert `JArray` for `items`, `JObject` for `pairs`/`keys`. The assert produces `AssertionDefect` (a `Defect`, not tracked by `raises: []`). Always check `node.kind` before iterating. |
| `getElems(@[])` and `getFields()` are raises-free | Return empty defaults on nil or wrong kind. Safe to call without kind check when a default is acceptable. |
| `parseJson(string)` raises `JsonParsingError` (a `ValueError` descendant); `parseFile` additionally raises `IOError` | NOT used in Layer 2. The `string → JsonNode` boundary requires exception handling and is a Layer 4 concern. Layer 2 receives only pre-parsed `JsonNode` trees. |
| `%*{...}` macro produces `JObject` at compile time | Safe for `toJson`; field names are string literals, no runtime key collision risk. Requires `{.cast(noSideEffect).}:` in `func` — the macro expands to `%` overloads which are side-effectful `proc`s (§1.6). |
| `newJObject()` + `obj[key] = val` mutation is **NOT** compatible with `func` under `strictFuncs` | `JsonNode` is `ref JsonNodeObj`. `[]=` and `add` mutate through a `ref` parameter — forbidden by `strictFuncs`. See §1.6 for the workaround. Not analogous to `PatchObject.setProp` (which mutates a value-type `Table`). |
| `getFields()` returns `OrderedTable` by value (copy); `pairs` iterates in-place | Where `JObject` kind is already verified, prefer `node.pairs` over `node.getFields()` to avoid the copy. `pairs` asserts kind — safe after prior check. |
| `%` for `openArray[tuple[key: string, val: JsonNode]]` returns `newJArray()` when `keyVals.len == 0` | Footgun: an empty seq of key-value tuples produces a JSON array, not an object. All types in this layer have at least one mandatory field, so this does not arise in practice. |

---

## 1. Deserialisation Infrastructure

### 1.1 Error Type Decision

Layer 2's `fromJson` functions compose with Layer 1 smart constructors via
the `?` operator. This requires a compatible error type.

**Option 1.1A: New `DeserialiseError` type.** A dedicated type carrying
`typeName`, `field` (JSON path), and `message`. Richer context for
debugging.

- **Pros:** More specific error context (JSON field path).
- **Cons:** Breaks `?` composition with Layer 1 smart constructors. Every
  call to `parseIdFromServer`, `parseUnsignedInt`, etc., would need
  `mapErr` to convert `ValidationError` to `DeserialiseError`. ~30+
  `mapErr` calls across the codebase.

**Option 1.1B: Reuse `ValidationError` with `parseError` helper.** Layer 2
populates the existing `ValidationError` fields with deserialisation-specific
context. The `value` field carries empty string (the JSON context is
captured in `message`).

- **Pros:** Composes directly with Layer 1 smart constructors via `?` —
  zero `mapErr` overhead. Single error type for the entire construction
  railway.
- **Cons:** `value` field semantics stretched (empty for deser errors vs.
  raw input for smart constructor errors). No JSON path threading.

**Decision: 1.1B.** Reuse `ValidationError`. The `parseError` helper:

```nim
func parseError*(typeName, message: string): ValidationError =
  ## Convenience constructor for deserialisation errors.
  ## Sets value to empty — JSON context is captured in message.
  validationError(typeName, message, "")
```

Rationale: `fromJson` calls Layer 1 smart constructors
(e.g., `? parseIdFromServer(raw)` in composite types, or returning the
constructor `Result` directly in simple types) — same error type means
zero `mapErr` overhead.
The `value` field carries empty string for deserialisation errors. This
aligns with Layer 1's `ValidationError` carrying `typeName` + `message` +
`value`, not a full call trace.

**Module:** `src/jmap_client/serde.nim`

### 1.2 Function Signature Conventions

Two canonical signatures:

```nim
func toJson*(x: T): JsonNode =
  ## Pure, infallible. Returns a JsonNode tree.

func fromJson*(T: typedesc[T], node: JsonNode): Result[T, ValidationError] =
  ## Pure, total, validating parser. Returns a well-typed value or
  ## a structured error.
```

The named `T` parameter enables `T.fromJson(node)` call syntax
via UFCS, and `$T` provides the type name string for error messages
(satisfying nimalyzer's `check params used all` rule without
`ruleOff` suppression).

For types that require additional context beyond the `JsonNode` (e.g.,
`ServerCapability` needs the URI string, `Referencable[T]` needs the field
name), the signature adds parameters:

```nim
func fromJson*(T: typedesc[ServerCapability], uri: string, data: JsonNode
    ): Result[ServerCapability, ValidationError] =
  ## Dispatches on parsed CapabilityKind from uri.
```

For generic types (`Filter[C]`), the callback parameter requires a
`{.noSideEffect.}` callable. In Nim, `func` is `proc {.noSideEffect.}`,
so the parameter type `proc(...) {.noSideEffect.}` should be
effect-compatible with `strictFuncs`. However, this must be verified at
compile time. Two options:

- **Primary:** `func fromJson*[C](T: typedesc[Filter[C]], node: JsonNode,
  fromCondition: proc(n: JsonNode): Result[C, ValidationError]
  {.noSideEffect.}): Result[Filter[C], ValidationError]` — if the compiler
  accepts `proc {.noSideEffect.}` parameter inside `func`.
- **Fallback:** If `strictFuncs` rejects the `proc` parameter type, use a
  template wrapper or pass the condition parser as a generic type parameter.
  This is a compile-time verification step, not a design choice.

**camelCase convention (Decision 2.2A).** All field names in Nim match wire
names exactly. No conversion logic. `accountId` in Nim → `"accountId"` in
JSON. Nim's style insensitivity (`accountId` and `account_id` are the same
identifier) makes this zero-cost. `nph` preserves the casing written.
`--styleCheck:error` requires consistency (use the same casing everywhere),
not a specific convention.

### 1.2a Kind-Checking Pattern (Totality Requirement)

Every `fromJson` MUST validate `JsonNodeKind` before extraction. The
raises-free accessors (`getStr`, `getBiggestInt`, `getBool`, `getFloat`)
silently return defaults on wrong kinds — this is a **totality hazard**
because it produces incorrect values rather than errors.

**Canonical patterns:**

```nim
# Distinct string type — validate JString before extraction
func fromJson*(T: typedesc[Id], node: JsonNode
    ): Result[Id, ValidationError] =
  ## Deserialise a JSON string to Id (lenient: server-assigned).
  checkJsonKind(node, JString, $T)
  parseIdFromServer(node.getStr(""))
```

```nim
# Distinct int type — validate JInt before extraction
func fromJson*(T: typedesc[UnsignedInt], node: JsonNode
    ): Result[UnsignedInt, ValidationError] =
  ## Deserialise a JSON integer to UnsignedInt.
  checkJsonKind(node, JInt, $T)
  parseUnsignedInt(node.getBiggestInt(0))
```

```nim
# Object type — validate JObject, then extract fields with kind checks
func fromJson*(T: typedesc[CoreCapabilities], node: JsonNode
    ): Result[CoreCapabilities, ValidationError] =
  ## Deserialise urn:ietf:params:jmap:core capability data.
  checkJsonKind(node, JObject, $T)
  let maxSizeUpload = ? UnsignedInt.fromJson(node{"maxSizeUpload"})
  let maxConcurrentUpload = ? UnsignedInt.fromJson(node{"maxConcurrentUpload"})
  let maxSizeRequest = ? UnsignedInt.fromJson(node{"maxSizeRequest"})
  # Decision D2.6: accept both singular and plural forms (RFC §2.1 typo)
  let maxConcurrentRequests = block:
    let plural = node{"maxConcurrentRequests"}
    let singular = node{"maxConcurrentRequest"}
    if not plural.isNil:
      ? UnsignedInt.fromJson(plural)
    elif not singular.isNil:
      ? UnsignedInt.fromJson(singular)
    else:
      return err(parseError($T,
        "missing maxConcurrentRequests"))
  let maxCallsInRequest = ? UnsignedInt.fromJson(node{"maxCallsInRequest"})
  let maxObjectsInGet = ? UnsignedInt.fromJson(node{"maxObjectsInGet"})
  let maxObjectsInSet = ? UnsignedInt.fromJson(node{"maxObjectsInSet"})
  let collationAlgorithms = block:
    let arr = node{"collationAlgorithms"}
    checkJsonKind(arr, JArray, $T,
      "missing or invalid collationAlgorithms")
    var algs: seq[string]
    for elem in arr.getElems(@[]):
      checkJsonKind(elem, JString, $T,
        "collationAlgorithms element must be string")
      algs.add(elem.getStr(""))
    toHashSet(algs)
  ok(CoreCapabilities(
    maxSizeUpload: maxSizeUpload,
    maxConcurrentUpload: maxConcurrentUpload,
    maxSizeRequest: maxSizeRequest,
    maxConcurrentRequests: maxConcurrentRequests,
    maxCallsInRequest: maxCallsInRequest,
    maxObjectsInGet: maxObjectsInGet,
    maxObjectsInSet: maxObjectsInSet,
    collationAlgorithms: collationAlgorithms,
  ))
```

```nim
# Array type — validate JArray first, THEN check len (split for clarity)
func fromJson*(T: typedesc[Invocation], node: JsonNode
    ): Result[Invocation, ValidationError] =
  ## Deserialise a 3-element JSON array to Invocation (RFC 8620 §3.2).
  checkJsonKind(node, JArray, $T)
  if node.len != 3:
    return err(parseError($T, "expected exactly 3 elements"))
  let elems = node.getElems(@[])
  checkJsonKind(elems[0], JString, $T,
    "method name must be string")
  let name = elems[0].getStr("")
  let arguments = elems[1]
  checkJsonKind(elems[2], JString, $T,
    "method call ID must be string")
  let callIdRaw = elems[2].getStr("")
  if name.len == 0:
    return err(parseError($T, "empty method name"))
  checkJsonKind(arguments, JObject, $T,
    "arguments must be JSON object")
  if callIdRaw.len == 0:
    return err(parseError($T, "empty method call ID"))
  let mcid = ? parseMethodCallId(callIdRaw)
  ok(Invocation(name: name, arguments: arguments, methodCallId: mcid))
```

Note: Nim's `or` short-circuits, so
`node.isNil or node.kind != JArray or node.len != 3` is technically safe
(`.len` only evaluated when node is non-nil JArray). However, splitting the
check is clearer and avoids any doubt about nil-safety of `.len`.

**Opt[T] field extraction patterns** (for fields like `description:
Opt[string]`, `isAscending: bool` with default):

```nim
# Required bool field with RFC default — use getBool AFTER kind check
let isAscending =
  if node{"isAscending"}.isNil:
    true  # RFC §5.5 default when absent
  elif node{"isAscending"}.kind == JBool:
    node{"isAscending"}.getBool(true)
  else:
    return err(parseError($T, "isAscending must be boolean"))
```

```nim
# Opt[string] field — absent, null, or wrong kind → Opt.none (§1.4b)
let description: Opt[string] =
  if node{"description"}.isNil or node{"description"}.kind != JString:
    Opt.none(string)
  else:
    Opt.some(node{"description"}.getStr(""))
```

```nim
# Opt[seq[string]] field — absent → empty seq (defensive, per L1 §8.10)
let properties: seq[string] =
  if node{"properties"}.isNil or node{"properties"}.kind != JArray:
    @[]
  else:
    var items: seq[string]
    for item in node{"properties"}.getElems(@[]):
      checkJsonKind(item, JString, "MethodResponse",
        "properties element must be string")
      items.add(item.getStr(""))
    items
```

These patterns are **non-negotiable for totality**. Documented here once,
referenced throughout Sections 3–8.

### 1.3 Layer Boundary

Layer 2 operates exclusively on pre-parsed `JsonNode` trees — pure `func`
transforms from `JsonNode` to typed values (or `ValidationError`). The
`string → JsonNode` step requires exception handling
(`std/json.parseJson` raises `JsonParsingError`) and is out of scope.
Layer 4 owns that boundary and composes it with Layer 2's `fromJson`
functions.

### 1.4 Shared Helpers

```nim
func parseError*(typeName, message: string): ValidationError =
  ## Convenience constructor for deserialisation errors.
  validationError(typeName, message, "")
```

```nim
template checkJsonKind*(node: JsonNode, expected: JsonNodeKind,
    typeName: string, message: string = "") =
  ## Validates JsonNodeKind before extraction. Returns err on mismatch.
  ## The `return` exits the calling function (template inlines at call site).
  if node.isNil or node.kind != expected:
    return err(parseError(typeName,
      if message.len > 0: message else: "expected JSON " & $expected))
```

```nim
func collectExtras*(node: JsonNode, knownKeys: openArray[string]
    ): Opt[JsonNode] =
  ## Collect non-standard fields from a JSON object into Opt[JsonNode].
  ## Returns Opt.none if no extra fields exist.
  ## Precondition: caller has verified node.kind == JObject.
  var extras = newJObject()
  var found = false
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    for key, val in node.pairs:  # kind already verified by caller
      if key notin knownKeys:
        extras[key] = val
        found = true
  if found: Opt.some(extras) else: Opt.none(JsonNode)
```

`collectExtras` is a **`func`** (no side effects). It requires
`node.kind == JObject` pre-check by the caller. Iterates via
`node.pairs` (kind pre-verified; avoids `getFields()` OrderedTable copy).
Uses `{.cast(noSideEffect).}:` for `JsonNode` mutation (§1.6). Used by
`RequestError`, `MethodError`, and `SetError` to preserve non-standard
server fields for lossless round-trip (Decision 1.7C).

**Module:** `src/jmap_client/serde.nim`

### 1.4a Error Context Scope (Explicit Trade-Off)

When `fromJson` fails deep inside a nested call chain (e.g.,
`Session → Account → CoreCapabilities → UnsignedInt`), the propagated
`ValidationError` carries only `typeName` ("UnsignedInt") and `message`
("expected JSON integer") — it does NOT include a JSON path (e.g.,
`"capabilities.urn:ietf:params:jmap:core.maxSizeUpload"`).

This is an **intentional trade-off**:

- **Pro:** `ValidationError` is the same type as Layer 1 smart constructors,
  enabling zero-`mapErr` composition via `?`. Adding a `context` field
  would break this alignment or require modifying the Layer 1 type.
- **Pro:** The `typeName` field narrows the search space (e.g.,
  "UnsignedInt" means one of ~7 fields in `CoreCapabilities`).
- **Con:** Debugging requires reading the `fromJson` implementation to
  trace the exact field.
- **Mitigation:** Layer 4 can wrap `ValidationError` with additional context
  (e.g., "while parsing Session response") when constructing `ClientError`.

This matches Layer 1's design: `ValidationError` carries `typeName` +
`message` + `value`, not a full call trace.

### 1.4b Opt Field Leniency Policy

All `Opt[T]` fields use a **lenient two-branch pattern** for wrong JSON
kinds: absent, null, or wrong kind all map to `Opt.none(T)`. Wrong kind
does NOT return `err`.

**Rationale:**

- This is a CLIENT library parsing server-originated data. Postel's law
  applies: "be liberal in what you accept."
- `Opt` fields are optional by definition — callers already handle the
  absent case via `isNone`/`isSome`.
- For error types specifically, strictness is actively harmful: if
  `MethodError.description` has wrong kind, a strict approach fails the
  entire `MethodError` parse, and the caller loses the critical `type`
  field entirely.
- "Absent" and "malformed" are equivalent for optional fields: both mean
  "not usable."

**Canonical patterns:**

```nim
# Opt[string] — lenient (wrong kind → none):
let field: Opt[string] =
  if node{"field"}.isNil or node{"field"}.kind != JString:
    Opt.none(string)
  else:
    Opt.some(node{"field"}.getStr(""))

# Opt[int] — lenient (wrong kind → none):
let field: Opt[int] =
  if node{"field"}.isNil or node{"field"}.kind != JInt:
    Opt.none(int)
  else:
    Opt.some(int(node{"field"}.getBiggestInt(0)))
```

**Scope:** This policy applies to simple scalar `Opt` fields (Sections
4–8). Complex container `Opt` types like `Opt[Table[CreationId, Id]]`
(Request/Response `createdIds`) retain strict three-branch handling
because a wrong container kind (e.g., `"createdIds": "string"`)
indicates a clear protocol violation, not a supplementary field issue.
Required (non-`Opt`) fields always use strict `checkJsonKind`.

### 1.5 Enum Deserialisation Totality

`fromJson` for enum types is **total** — unknown values map to catch-all
variants (`ckUnknown`, `metUnknown`, `setUnknown`, `retUnknown`), matching
Layer 1's total `parseEnum` functions (`parseCapabilityKind`,
`parseMethodErrorType`, etc.).

**Exception:** `FilterOperator`. The three operators (`AND`, `OR`, `NOT`)
are exhaustive per RFC §5.5. Unknown operators return
`err(ValidationError)` because there is no catch-all variant — the RFC does
not define a mechanism for server-extended operators.

**Module:** `src/jmap_client/serde_framework.nim` (for `FilterOperator`)

### 1.6 `strictFuncs` and `JsonNode` Mutation

`config.nims` applies `strictFuncs` globally via
`switch("experimental", "strictFuncs")`. `JsonNode` is `ref JsonNodeObj`
(std/json line 194). Under `strictFuncs`, `std/json`'s `[]=`, `.add()`,
`%`, and `%*` are all rejected inside `func` — they mutate through `ref`
indirection or are declared as `proc` without `{.noSideEffect.}`.

Every `toJson` function that constructs or mutates `JsonNode` MUST wrap the
body in `{.cast(noSideEffect).}:`. This is mandatory under the project's
compiler configuration.

**What works in `func` without cast:**

- All read-only accessors (`getStr`, `getBiggestInt`, `{}`, `getElems`,
  `getFields`, `pairs`, `isNil`, `.kind`) — inferred as side-effect-free.
  All `fromJson` functions are unaffected.
- `newJNull()` — accepted in `func` under `strictFuncs` in Nim 2.2.8.
  Confirmed by existing Layer 1 code (`framework.nim:98`).

**What does NOT work in `func` without cast:**

- `%*{...}` — the macro expands to `%` overloads which are side-effectful
  `proc`s. Rejected by `strictFuncs`.
- `result["key"] = val` — calls `proc []=*(obj: JsonNode, ...)` which
  mutates through a `ref` parameter. Rejected by `strictFuncs`.
- `arr.add(child)` — calls `proc add*(father, child: JsonNode)`. Rejected.
- Scalar `%string(x)`, `%int64(x)` — the `%` overloads are `proc`s.
  Rejected by `strictFuncs`.

This means ALL `toJson` functions need the cast, including simple ones
returning `%string(x)`. The only exceptions are `fromJson` functions (which
use only read-only accessors) and `referencableKey` (which returns a
`string`, not `JsonNode`).

**Decision: `{.cast(noSideEffect).}:` wrapping the entire function body
("full cast").**

The single pattern wraps the entire `toJson` body in one cast block:

```nim
func toJson*(re: RequestError): JsonNode =
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    result["type"] = %re.rawType
    if re.status.isSome:
      result["status"] = %re.status.get()
    if re.detail.isSome:
      result["detail"] = %re.detail.get()
```

The cast is safe because: (a) mutations target only the locally-created
`result` or locally-created intermediate `JsonNode` objects; (b) no
pre-existing shared state is read or written; (c) the function is
referentially transparent. This is the Nim equivalent of a scoped
`unsafePerformIO` in Haskell.

All `toJson` functions in Sections 3–8 use the full cast pattern. The cast
block is documented once here and referenced throughout.

---

## 2. Serialisation Pattern Catalogue

Decision 2.1A specifies manual `toJson`/`fromJson` for each type. Most types
follow one of three patterns; ~4-5 special types require custom handling.

### Pattern A: Simple Object

Field-by-field `%*{...}` construction for `toJson`; `node{"field"}.getType(default)`
extraction with kind checks for `fromJson`.

**Canonical example: `Comparator`**

```nim
func toJson*(c: Comparator): JsonNode =
  ## Serialise Comparator to JSON (RFC 8620 §5.5).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{
      "property": string(c.property),
      "isAscending": c.isAscending,
    }
    if c.collation.isSome:
      result["collation"] = %c.collation.get()

func fromJson*(T: typedesc[Comparator], node: JsonNode
    ): Result[Comparator, ValidationError] =
  ## Deserialise JSON to Comparator (RFC 8620 §5.5).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"property"}, JString, $T,
    "missing or invalid property")
  let property = ? parsePropertyName(node{"property"}.getStr(""))
  let isAscending =
    if node{"isAscending"}.isNil: true  # RFC default
    elif node{"isAscending"}.kind == JBool:
      node{"isAscending"}.getBool(true)
    else:
      return err(parseError($T, "isAscending must be boolean"))
  let collation: Opt[string] =  # §1.4b: lenient
    if node{"collation"}.isNil or node{"collation"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"collation"}.getStr(""))
  ? parseComparator(property, isAscending, collation)
```

Types using Pattern A: `CoreCapabilities`, `Account`,
`AccountCapabilityEntry`, `Session` (composite), `Comparator`, `AddedItem`,
`ResultReference`, `Request`, `Response`, `RequestError`, `MethodError`.

### Pattern B: Case Object

Discriminator dispatch in `fromJson`, branch-specific construction in
`toJson`. Discriminator must be a compile-time literal at construction site
(`strictCaseObjects`).

**Canonical example: `ServerCapability`**

```nim
func toJson*(cap: ServerCapability): JsonNode =
  ## Serialise capability data (not the URI key — handled by Session.toJson).
  case cap.kind
  of ckCore: cap.core.toJson()
  else:
    if cap.rawData.isNil: newJObject() else: cap.rawData

func fromJson*(T: typedesc[ServerCapability], uri: string, data: JsonNode
    ): Result[ServerCapability, ValidationError] =
  ## Deserialise a capability from its URI and JSON data.
  let parsedKind = parseCapabilityKind(uri)
  case parsedKind
  of ckCore:
    let core = ? CoreCapabilities.fromJson(data)
    ok(ServerCapability(kind: ckCore, rawUri: uri, core: core))
  else:
    # All non-core known kinds (ckMail, ckContacts, etc.) and ckUnknown
    # store raw data. Use uncheckedAssign for runtime discriminator.
    var cap = ServerCapability(kind: ckUnknown, rawUri: uri, rawData: data)
    if parsedKind != ckUnknown:
      {.cast(uncheckedAssign).}:
        cap.kind = parsedKind
    ok(cap)
```

**`strictCaseObjects` note.** The `of ckCore:` branch uses the compile-time
literal `ckCore` for the discriminator. The `else:` branch first constructs
with the literal `ckUnknown`, then reassigns the discriminator via
`{.cast(uncheckedAssign).}` if the actual kind is a known non-core variant
(e.g., `ckMail`). This is safe because all `else`-branch variants share the
same memory layout (`rawData: JsonNode`). This pattern mirrors Layer 1's
`SetError` constructor (see 01-layer-1-design.md §8.10).

Types using Pattern B: `ServerCapability`, `SetError`.

### Pattern C: Special Format

Type-specific wire formats that do not follow the object convention.

- **Invocation** — 3-element JSON array (see §6.1)
- **Referencable[T]** — `#`-prefix key dispatch (see §6.5)
- **PatchObject** — JSON Pointer path keys (see §7.3)
- **Filter[C]** — recursive with operator/condition discriminator (see §7.2)

Types using Pattern C: `Invocation`, `Referencable[T]`, `PatchObject`,
`Filter[C]`.

### Type Classification Table

| Type | Pattern | Notes |
|------|---------|-------|
| Id, AccountId, JmapState, MethodCallId, CreationId, UriTemplate, PropertyName, Date, UTCDate | Identity (unwrap/wrap) | Subset of A |
| UnsignedInt, JmapInt | Identity (unwrap/wrap) | Subset of A |
| CapabilityKind, FilterOperator, RequestErrorType, MethodErrorType, SetErrorType | Enum string | Subset of A |
| CoreCapabilities | A: Simple Object | 8 fields |
| Account | A: Simple Object | with nested accountCapabilities |
| AccountCapabilityEntry | A: Simple Object | |
| Session | A: Composite Object | Composes all sub-parsers |
| Comparator | A: Simple Object | with defaults |
| AddedItem | A: Simple Object | |
| ResultReference | A: Simple Object | |
| Request | A: Simple Object | with Opt field |
| Response | A: Simple Object | with Opt field |
| RequestError | A: Simple Object | with extras collection |
| MethodError | A: Simple Object | with extras collection |
| ServerCapability | B: Case Object | URI dispatch |
| SetError | B: Case Object | variant-specific fields |
| Invocation | C: Special | 3-element JSON array |
| Referencable[T] | C: Special | `#`-prefix field-level |
| PatchObject | C: Special | JSON Pointer keys |
| Filter[C] | C: Special | Recursive with callback |

---

## 3. Primitive Type Serialisation

### 3.1 Distinct String Types

**RFC reference:** §1.2 (lines 287–319), §1.4 (lines 343–354), §2 (lines
477–733).

Nine distinct string types share the same serialisation pattern: unwrap with
`string(x)` for `toJson`, extract with `getStr` and call the smart
constructor for `fromJson`.

**`toJson` (shared pattern):**

```nim
func toJson*(x: Id): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: AccountId): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: JmapState): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: MethodCallId): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: CreationId): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: UriTemplate): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: PropertyName): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: Date): JsonNode = {.cast(noSideEffect).}: %string(x)
func toJson*(x: UTCDate): JsonNode = {.cast(noSideEffect).}: %string(x)
```

**`fromJson` (per-type, documenting which smart constructor is called):**

| Type | `fromJson` calls | Rationale |
|------|------------------|-----------|
| Id | `parseIdFromServer` | Server-assigned; lenient (1-255 octets, no control chars) |
| AccountId | `parseAccountId` | Server-assigned; lenient (1-255 octets, no control chars) |
| JmapState | `parseJmapState` | Server-assigned (non-empty, no control chars) |
| MethodCallId | `parseMethodCallId` | Echoed from client request (non-empty) |
| CreationId | `parseCreationId` | Client-assigned, echoed back (non-empty, no `#` prefix) |
| UriTemplate | `parseUriTemplate` | Server-provided (non-empty) |
| PropertyName | `parsePropertyName` | Server-provided in responses (non-empty) |
| Date | `parseDate` | Server-provided (RFC 3339 structural validation) |
| UTCDate | `parseUtcDate` | Server-provided (RFC 3339, Z suffix) |

All `fromJson` share the same structure (Id shown in §1.2a). Each validates
`JString` kind via `$T` (the type name derived from the `typedesc`
parameter), then delegates to the appropriate Layer 1 smart constructor.
The smart constructor returns `Result[T, ValidationError]` which is
returned directly — no `?` operator needed since the return types match.

```nim
func fromJson*(T: typedesc[AccountId], node: JsonNode
    ): Result[AccountId, ValidationError] =
  ## Deserialise a JSON string to AccountId (lenient: server-assigned).
  checkJsonKind(node, JString, $T)
  parseAccountId(node.getStr(""))
```

Each remaining distinct string type follows this exact pattern with the
appropriate smart constructor.

**Module:** `src/jmap_client/serde.nim`

### 3.2 Distinct Int Types

**RFC reference:** §1.3 (lines 320–342).

Two types: `UnsignedInt` (0 to 2^53-1) and `JmapInt` (-2^53+1 to 2^53-1).

```nim
func toJson*(x: UnsignedInt): JsonNode =
  ## Serialise UnsignedInt to JSON integer.
  {.cast(noSideEffect).}: %int64(x)

func toJson*(x: JmapInt): JsonNode =
  ## Serialise JmapInt to JSON integer.
  {.cast(noSideEffect).}: %int64(x)
```

```nim
func fromJson*(T: typedesc[UnsignedInt], node: JsonNode
    ): Result[UnsignedInt, ValidationError] =
  ## Deserialise a JSON integer to UnsignedInt.
  checkJsonKind(node, JInt, $T)
  parseUnsignedInt(node.getBiggestInt(0))

func fromJson*(T: typedesc[JmapInt], node: JsonNode
    ): Result[JmapInt, ValidationError] =
  ## Deserialise a JSON integer to JmapInt.
  checkJsonKind(node, JInt, $T)
  parseJmapInt(node.getBiggestInt(0))
```

`getBiggestInt` returns `BiggestInt` (`int64`) — correct for `distinct int64`
types. `getInt` returns pointer-sized `int` and would truncate on 32-bit
platforms.

**Module:** `src/jmap_client/serde.nim`

### 3.3 Enum Types

**RFC reference:** §9.4 (capability URIs), §5.5 (FilterOperator), §3.6
(error types).

Five enum types: `CapabilityKind`, `FilterOperator`, `RequestErrorType`,
`MethodErrorType`, `SetErrorType`.

**`toJson` for enums embedded in containing objects.** Enums with catch-all
variants (`ckUnknown`, `retUnknown`, `metUnknown`, `setUnknown`) are
NEVER serialised directly via `$enumVal` — the containing object's `rawUri`
or `rawType` field is used instead (Decision 1.7C: lossless round-trip).
`$ckUnknown` returns `"ckUnknown"` (symbolic name, not a URI).

`CapabilityKind` is serialised via `ServerCapability.rawUri`.
`RequestErrorType` is serialised via `RequestError.rawType`.
`MethodErrorType` is serialised via `MethodError.rawType`.
`SetErrorType` is serialised via `SetError.rawType`.

**`fromJson` for enums.** All use Layer 1's total parse functions:

```nim
# Not standalone fromJson — called within containing type's fromJson:
let kind = parseCapabilityKind(uri)        # total, returns CapabilityKind
let errorType = parseRequestErrorType(raw) # total, returns RequestErrorType
let errorType = parseMethodErrorType(raw)  # total, returns MethodErrorType
let errorType = parseSetErrorType(raw)     # total, returns SetErrorType
```

**FilterOperator exception.** The three operators are exhaustive per
RFC §5.5 — no catch-all variant exists. Deserialisation of unknown
operators returns `Result.err`:

```nim
func toJson*(op: FilterOperator): JsonNode =
  ## Serialise FilterOperator to its RFC string.
  {.cast(noSideEffect).}: %($op)  # $ returns backing string: "AND", "OR", "NOT"

func fromJson*(T: typedesc[FilterOperator], node: JsonNode
    ): Result[FilterOperator, ValidationError] =
  ## Deserialise a JSON string to FilterOperator. Not total — unknown
  ## operators return err because the RFC defines exactly three.
  checkJsonKind(node, JString, $T)
  case node.getStr("")
  of "AND": ok(foAnd)
  of "OR": ok(foOr)
  of "NOT": ok(foNot)
  else:
    err(parseError($T,
      "unknown operator: " & node.getStr("")))
```

**Module:** `src/jmap_client/serde_framework.nim` (FilterOperator only).
`CapabilityKind` and error type enums (`RequestErrorType`,
`MethodErrorType`, `SetErrorType`) have no standalone `toJson`/`fromJson`
— they are parsed inline via Layer 1's total parse functions
(`parseCapabilityKind`, `parseRequestErrorType`, etc.) within their
containing type's `fromJson`. See §10 inventory for details.

---

## 4. Capability Serialisation

### 4.1 CoreCapabilities

**RFC reference:** §2 (lines 511–572). Part of
`capabilities["urn:ietf:params:jmap:core"]`.

Eight fields, all required. Seven `UnsignedInt` fields for server limits,
plus `collationAlgorithms` as a JSON array → `HashSet[string]`.

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
  ## Serialise CoreCapabilities to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{
      "maxSizeUpload": int64(caps.maxSizeUpload),
      "maxConcurrentUpload": int64(caps.maxConcurrentUpload),
      "maxSizeRequest": int64(caps.maxSizeRequest),
      "maxConcurrentRequests": int64(caps.maxConcurrentRequests),
      "maxCallsInRequest": int64(caps.maxCallsInRequest),
      "maxObjectsInGet": int64(caps.maxObjectsInGet),
      "maxObjectsInSet": int64(caps.maxObjectsInSet),
      "collationAlgorithms": collect(
        for alg in caps.collationAlgorithms: %alg
      ),
    }
```

**Macro nesting verification.** `collect(for alg in ...: %alg)` inside
`%*{...}` nests two macros. Verified to compile and produce correct output
(Nim 2.2.8): `collect` expands first (inner-to-outer), producing
`seq[JsonNode]`; the `%*` macro then wraps the result via `%` for
`openArray[JsonNode]` (`std/json` line 366), producing a `JArray`.

**`fromJson`:** Full code shown in §1.2a (the canonical object example).
Calls `parseUnsignedInt` for each numeric field via `?`. Uses `toHashSet`
from `std/sets` for `collationAlgorithms`.

**Decision D2.6: RFC typo tolerance.** The RFC §2.1 example (line 753)
uses `"maxConcurrentRequest"` (singular) instead of
`"maxConcurrentRequests"` (plural, per the field definition in §2).
`fromJson` accepts both forms — real servers may follow the example.

**No smart constructor.** Layer 1 defines no `parseCoreCapabilities`.
Construction happens exclusively during JSON deserialisation (Layer 2),
which validates each field individually through `parseUnsignedInt`.

**Module:** `src/jmap_client/serde_session.nim`

### 4.2 ServerCapability

**RFC reference:** §2 (Session.capabilities values).

A case object discriminated by `CapabilityKind`. Only `ckCore` has a typed
representation in RFC 8620. All other capabilities store raw JSON data.

**Wire format:** The `capabilities` object in Session has URIs as keys and
capability data as values:

```json
"capabilities": {
  "urn:ietf:params:jmap:core": { ... CoreCapabilities ... },
  "urn:ietf:params:jmap:mail": {},
  "https://example.com/apis/foobar": { "maxFoosFinangled": 42 }
}
```

Layer 2 receives each `(uri, data)` pair from the Session parser and
dispatches based on the URI.

**`toJson`/`fromJson`:** Full code shown in §2 (Pattern B canonical
example). Dispatches on `parseCapabilityKind(uri)` → `ckCore` calls
`CoreCapabilities.fromJson(data)`, `else` stores `rawData: data`.

**`strictCaseObjects` compliance.** The `of ckCore:` branch uses compile-time
literal `ckCore`. The `else:` branch constructs with literal `ckUnknown`
then uses `{.cast(uncheckedAssign).}` for the actual kind — safe because
all `else` variants share memory layout.

**Module:** `src/jmap_client/serde_session.nim`

### 4.3 AccountCapabilityEntry

**RFC reference:** §2 (nested in Session.accounts[].accountCapabilities).

A flat object storing per-account capability data as raw JSON. Each entry
records the parsed `CapabilityKind`, the original URI string, and the raw
capability data.

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
  ## Serialise the capability data (URI key handled by Account.toJson).
  if entry.data.isNil: newJObject() else: entry.data
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[AccountCapabilityEntry], uri: string,
    data: JsonNode): Result[AccountCapabilityEntry, ValidationError] =
  ## Deserialise an account capability entry from URI and JSON data.
  ok(AccountCapabilityEntry(
    kind: parseCapabilityKind(uri),
    rawUri: uri,
    data: if data.isNil: newJObject() else: data,
  ))
```

No validation beyond kind parsing — all account capability data is stored
as raw JSON in the Core-only implementation. When specific RFCs are added,
this may evolve to a case object with typed branches.

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
  ## Serialise Account to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{
      "name": acct.name,
      "isPersonal": acct.isPersonal,
      "isReadOnly": acct.isReadOnly,
    }
    var acctCaps = newJObject()
    for entry in acct.accountCapabilities:
      acctCaps[entry.rawUri] = entry.toJson()
    result["accountCapabilities"] = acctCaps
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[Account], node: JsonNode
    ): Result[Account, ValidationError] =
  ## Deserialise JSON to Account (RFC 8620 §2).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"name"}, JString, $T,
    "missing or invalid name")
  let name = node{"name"}.getStr("")
  checkJsonKind(node{"isPersonal"}, JBool, $T,
    "missing or invalid isPersonal")
  let isPersonal = node{"isPersonal"}.getBool(false)
  checkJsonKind(node{"isReadOnly"}, JBool, $T,
    "missing or invalid isReadOnly")
  let isReadOnly = node{"isReadOnly"}.getBool(false)
  let acctCapsNode = node{"accountCapabilities"}
  checkJsonKind(acctCapsNode, JObject, $T,
    "missing or invalid accountCapabilities")
  var accountCapabilities: seq[AccountCapabilityEntry]
  for uri, data in acctCapsNode.pairs:  # kind verified above
    let entry = ? AccountCapabilityEntry.fromJson(uri, data)
    accountCapabilities.add(entry)
  ok(Account(
    name: name,
    isPersonal: isPersonal,
    isReadOnly: isReadOnly,
    accountCapabilities: accountCapabilities,
  ))
```

**No standalone smart constructor.** Accounts are validated as part of
Session parsing.

**Module:** `src/jmap_client/serde_session.nim`

### 5.2 Session

**RFC reference:** §2 (lines 477–733). The most complex deserialisation
target.

**Wire format:** RFC §2.1 example (lines 735–817) — see test fixture §13.1
for the complete JSON.

**`toJson`:**

```nim
func toJson*(s: Session): JsonNode =
  ## Serialise Session to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{
      "username": s.username,
      "apiUrl": s.apiUrl,
      "downloadUrl": string(s.downloadUrl),
      "uploadUrl": string(s.uploadUrl),
      "eventSourceUrl": string(s.eventSourceUrl),
      "state": string(s.state),
    }
    # capabilities: URI → capability data
    var caps = newJObject()
    for cap in s.capabilities:
      caps[cap.rawUri] = cap.toJson()
    result["capabilities"] = caps
    # accounts: AccountId → Account
    var accts = newJObject()
    for id, acct in s.accounts:
      accts[string(id)] = acct.toJson()
    result["accounts"] = accts
    # primaryAccounts: capability URI → AccountId
    var primary = newJObject()
    for uri, id in s.primaryAccounts:
      primary[uri] = %string(id)
    result["primaryAccounts"] = primary
```

**Assumption:** `capabilities` contains no duplicate `rawUri` values. This
is guaranteed by `fromJson` (JSON object keys are unique via
`OrderedTable`). Programmatic construction must ensure uniqueness;
duplicates cause silent overwrite in `toJson`. Enforcing uniqueness in
the type system (e.g., `Table[string, ServerCapability]`) is a Layer 1
concern — see architecture §1.2A rationale for `seq` (ordered iteration,
pattern-matchable by kind).

**`fromJson`:**

```nim
func fromJson*(T: typedesc[Session], node: JsonNode
    ): Result[Session, ValidationError] =
  ## Deserialise JSON to Session (RFC 8620 §2). Calls parseSession for
  ## structural invariant validation.
  checkJsonKind(node, JObject, $T)

  # 1. Parse capabilities
  let capsNode = node{"capabilities"}
  checkJsonKind(capsNode, JObject, $T,
    "missing or invalid capabilities")
  var capabilities: seq[ServerCapability]
  for uri, data in capsNode.pairs:  # kind verified above
    let cap = ? ServerCapability.fromJson(uri, data)
    capabilities.add(cap)

  # 2. Parse accounts
  let acctsNode = node{"accounts"}
  checkJsonKind(acctsNode, JObject, $T,
    "missing or invalid accounts")
  var accounts = initTable[AccountId, Account]()
  for idStr, acctData in acctsNode.pairs:  # kind verified above
    let accountId = ? parseAccountId(idStr)
    let account = ? Account.fromJson(acctData)
    accounts[accountId] = account

  # 3. Parse primaryAccounts (required per RFC §2)
  let primaryNode = node{"primaryAccounts"}
  checkJsonKind(primaryNode, JObject, $T,
    "missing or invalid primaryAccounts")
  var primaryAccounts = initTable[string, AccountId]()
  for uri, idNode in primaryNode.pairs:  # kind verified above
    checkJsonKind(idNode, JString, $T,
      "primaryAccounts value must be string")
    let accountId = ? parseAccountId(idNode.getStr(""))
    primaryAccounts[uri] = accountId

  # 4. Parse scalar fields
  checkJsonKind(node{"username"}, JString, $T,
    "missing or invalid username")
  let username = node{"username"}.getStr("")
  checkJsonKind(node{"apiUrl"}, JString, $T,
    "missing or invalid apiUrl")
  let apiUrl = node{"apiUrl"}.getStr("")

  # 5. Parse URI templates
  checkJsonKind(node{"downloadUrl"}, JString, $T,
    "missing or invalid downloadUrl")
  let downloadUrl = ? parseUriTemplate(node{"downloadUrl"}.getStr(""))
  checkJsonKind(node{"uploadUrl"}, JString, $T,
    "missing or invalid uploadUrl")
  let uploadUrl = ? parseUriTemplate(node{"uploadUrl"}.getStr(""))
  checkJsonKind(node{"eventSourceUrl"}, JString, $T,
    "missing or invalid eventSourceUrl")
  let eventSourceUrl = ? parseUriTemplate(node{"eventSourceUrl"}.getStr(""))

  # 6. Parse state
  checkJsonKind(node{"state"}, JString, $T,
    "missing or invalid state")
  let state = ? parseJmapState(node{"state"}.getStr(""))

  # 7. Call parseSession for structural invariant validation
  ? parseSession(
    capabilities = capabilities,
    accounts = accounts,
    primaryAccounts = primaryAccounts,
    username = username,
    apiUrl = apiUrl,
    downloadUrl = downloadUrl,
    uploadUrl = uploadUrl,
    eventSourceUrl = eventSourceUrl,
    state = state,
  )
```

**Rationale.** Session deserialisation is a 7-step sub-parse chain. Each
step returns `Result[T, ValidationError]` and is composed via `?`. The
final call to `parseSession(...)` validates structural invariants (ckCore
present, apiUrl non-empty, URI template variables). This ensures that all
Sessions produced by `fromJson` satisfy the same invariants as those
produced by the Layer 1 smart constructor.

**Module:** `src/jmap_client/serde_session.nim`

---

## 6. Envelope Serialisation

### 6.1 Invocation

**RFC reference:** §3.2 (lines 865–881).

A tuple of three elements: method name, arguments object, method call ID.
Serialised as a **3-element JSON array**, NOT a JSON object.

**Wire format:**

```json
["Mailbox/get", {"accountId": "A13824", "ids": null}, "c1"]
```

**`toJson`:**

```nim
func toJson*(inv: Invocation): JsonNode =
  ## Serialise Invocation as 3-element JSON array (RFC 8620 §3.2).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*[inv.name, inv.arguments, string(inv.methodCallId)]
```

**`fromJson`:** Full code shown in §1.2a (the canonical array example).
Validates `JArray`, `len == 3`, extracts by index, calls
`parseMethodCallId`. Also validates that `arguments` is `JObject` and
`name` is non-empty.

**Rationale.** This is the most distinctive JMAP serialisation quirk.
Invocations are NOT objects on the wire — they are ordered tuples. The
3-element array format is mandated by RFC §3.2.

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
  ## Serialise Request to JSON (RFC 8620 §3.3).
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    result["using"] = %r.`using`
    var calls = newJArray()
    for inv in r.methodCalls:
      calls.add(inv.toJson())
    result["methodCalls"] = calls
    if r.createdIds.isSome:
      var ids = newJObject()
      for k, v in r.createdIds.get():
        ids[string(k)] = %string(v)
      result["createdIds"] = ids
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[Request], node: JsonNode
    ): Result[Request, ValidationError] =
  ## Deserialise JSON to Request (RFC 8620 §3.3).
  checkJsonKind(node, JObject, $T)

  let usingNode = node{"using"}
  checkJsonKind(usingNode, JArray, $T,
    "missing or invalid using")
  var usingSeq: seq[string]
  for elem in usingNode.getElems(@[]):
    checkJsonKind(elem, JString, $T,
      "using element must be string")
    usingSeq.add(elem.getStr(""))

  let callsNode = node{"methodCalls"}
  checkJsonKind(callsNode, JArray, $T,
    "missing or invalid methodCalls")
  var methodCalls: seq[Invocation]
  for callNode in callsNode.getElems(@[]):
    let inv = ? Invocation.fromJson(callNode)
    methodCalls.add(inv)

  let createdIds: Opt[Table[CreationId, Id]] =
    if node{"createdIds"}.isNil or node{"createdIds"}.kind == JNull:
      Opt.none(Table[CreationId, Id])
    elif node{"createdIds"}.kind == JObject:
      var tbl = initTable[CreationId, Id]()
      for k, v in node{"createdIds"}.pairs:  # kind verified above
        let cid = ? parseCreationId(k)
        checkJsonKind(v, JString, $T,
          "createdIds value must be string")
        let id = ? parseIdFromServer(v.getStr(""))
        tbl[cid] = id
      Opt.some(tbl)
    else:
      return err(parseError($T, "createdIds must be object or null"))

  ok(Request(
    `using`: usingSeq,
    methodCalls: methodCalls,
    createdIds: createdIds,
  ))
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
  ## Serialise Response to JSON (RFC 8620 §3.4).
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    var responses = newJArray()
    for inv in r.methodResponses:
      responses.add(inv.toJson())
    result["methodResponses"] = responses
    result["sessionState"] = %string(r.sessionState)
    if r.createdIds.isSome:
      var ids = newJObject()
      for k, v in r.createdIds.get():
        ids[string(k)] = %string(v)
      result["createdIds"] = ids
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[Response], node: JsonNode
    ): Result[Response, ValidationError] =
  ## Deserialise JSON to Response (RFC 8620 §3.4).
  checkJsonKind(node, JObject, $T)

  let responsesNode = node{"methodResponses"}
  checkJsonKind(responsesNode, JArray, $T,
    "missing or invalid methodResponses")
  var methodResponses: seq[Invocation]
  for respNode in responsesNode.getElems(@[]):
    let inv = ? Invocation.fromJson(respNode)
    methodResponses.add(inv)

  checkJsonKind(node{"sessionState"}, JString, $T,
    "missing or invalid sessionState")
  let sessionState = ? parseJmapState(
    node{"sessionState"}.getStr(""))

  let createdIds: Opt[Table[CreationId, Id]] =
    if node{"createdIds"}.isNil or node{"createdIds"}.kind == JNull:
      Opt.none(Table[CreationId, Id])
    elif node{"createdIds"}.kind == JObject:
      var tbl = initTable[CreationId, Id]()
      for k, v in node{"createdIds"}.pairs:  # kind verified above
        let cid = ? parseCreationId(k)
        checkJsonKind(v, JString, $T,
          "createdIds value must be string")
        let id = ? parseIdFromServer(v.getStr(""))
        tbl[cid] = id
      Opt.some(tbl)
    else:
      return err(parseError($T, "createdIds must be object or null"))

  ok(Response(
    methodResponses: methodResponses,
    createdIds: createdIds,
    sessionState: sessionState,
  ))
```

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
  ## Serialise ResultReference to JSON (RFC 8620 §3.7).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{
      "resultOf": string(r.resultOf),
      "name": r.name,
      "path": r.path,
    }
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[ResultReference], node: JsonNode
    ): Result[ResultReference, ValidationError] =
  ## Deserialise JSON to ResultReference (RFC 8620 §3.7).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"resultOf"}, JString, $T,
    "missing or invalid resultOf")
  let resultOf = ? parseMethodCallId(node{"resultOf"}.getStr(""))
  checkJsonKind(node{"name"}, JString, $T,
    "missing or invalid name")
  let name = node{"name"}.getStr("")
  checkJsonKind(node{"path"}, JString, $T,
    "missing or invalid path")
  let path = node{"path"}.getStr("")
  if name.len == 0:
    return err(parseError($T, "missing name"))
  if path.len == 0:
    return err(parseError($T, "missing path"))
  ok(ResultReference(resultOf: resultOf, name: name, path: path))
```

**Module:** `src/jmap_client/serde_envelope.nim`

### 6.5 Referencable[T]

**Architecture reference:** Decision 1.3B, Decision 2.3.

NOT a standalone `toJson`/`fromJson` pair — handled at the containing-object
level. The wire format uses the JSON key name as the discriminator:

- `rkDirect`: normal key with the value serialised as `T`.
  `{ "ids": ["id1", "id2"] }`
- `rkReference`: key prefixed with `#`, value is a `ResultReference` object.
  `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

There are only ~4 referenceable fields across the standard methods.

**Helper functions:**

```nim
func referencableKey*[T](fieldName: string, r: Referencable[T]): string =
  ## Returns the wire key: "fieldName" for direct, "#fieldName" for reference.
  ## Pure string transform — no JsonNode, no cast, no mutation.
  case r.kind
  of rkDirect: fieldName
  of rkReference: "#" & fieldName

func fromJsonField*[T](
    fieldName: string,
    node: JsonNode,
    fromDirect: proc(n: JsonNode): Result[T, ValidationError] {.noSideEffect.},
): Result[Referencable[T], ValidationError] =
  ## Parse a Referencable field from a JSON object.
  ## Checks for "#fieldName" (reference) first, then "fieldName" (direct).
  ## Returns err if "#fieldName" exists but is not JObject — the # prefix
  ## is a semantic commitment to a reference, so malformed references are
  ## errors, not absent references.
  let refKey = "#" & fieldName
  let refNode = node{refKey}
  if not refNode.isNil:
    if refNode.kind != JObject:
      return err(parseError("Referencable",
        refKey & " must be a JSON object (ResultReference)"))
    let resultRef = ? ResultReference.fromJson(refNode)
    return ok(referenceTo[T](resultRef))
  let directNode = node{fieldName}
  if directNode.isNil:
    return err(parseError("Referencable",
      "missing field: " & fieldName & " or " & refKey))
  let value = ? fromDirect(directNode)
  ok(direct[T](value))
```

**Serialisation-side design.** The `#`-prefix dispatch is a data transform
on the field name, not a mutation operation. `referencableKey` is a total
pure function — `(string, Referencable[T]) → string` — that computes
the wire key. The value serialisation uses existing `toJson` overloads for
the inner types. These are orthogonal concerns: the caller composes key
transform + value serialisation within its own `{.cast(noSideEffect).}`
block (where the `result` is locally owned):

```nim
{.cast(noSideEffect).}:  # §1.6: local ref mutation
  if req.ids.isSome:
    let r = req.ids.get()
    result[referencableKey("ids", r)] = case r.kind
      of rkDirect: toJson(r.value)    # existing seq[Id] toJson
      of rkReference: r.reference.toJson()
```

With ~4 referenceable fields across the standard methods, the call-site
verbosity is negligible and each site is self-documenting.

**Deserialisation-side design.** `fromJsonField` remains a combined helper
because key dispatch and value parsing are genuinely coupled on the
deserialisation side — the key determines whether to parse `T` or
`ResultReference`. The asymmetry between `referencableKey` (pure key
transform) and `fromJsonField` (combined dispatch + parse) reflects
the genuine asymmetry in the problem: serialisation knows the variant
(dispatch is trivial), deserialisation must discover it from the key.

**Rationale.** The `#`-prefix is on the JSON key, not the value. This makes
it impossible to serialise as a standalone `toJson`/`fromJson` pair — the
containing object's serialiser must handle the key dispatch.

**Module:** `src/jmap_client/serde_envelope.nim`

---

## 7. Framework Type Serialisation

### 7.1 Comparator

**RFC reference:** §5.5 (lines 2339–2638).

Full `toJson`/`fromJson` code shown in §2 (Pattern A canonical example).
`isAscending` defaults to `true` when absent from JSON (per RFC §5.5).
`collation` is `Opt[string]` — omit when `isNone`. `fromJson` calls
`parsePropertyName` for the `property` field and `parseComparator` for
construction.

**Module:** `src/jmap_client/serde_framework.nim`

### 7.2 Filter[C]

**RFC reference:** §5.5 (lines 2368–2394).

A recursive algebraic data type parameterised by condition type `C`. On the
wire, an operator node has an `"operator"` field (`"AND"`, `"OR"`, `"NOT"`)
and a `"conditions"` array. A condition node lacks the `"operator"` field.

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

**`toJson`:**

```nim
func toJson*[C](f: Filter[C],
    condToJson: proc(c: C): JsonNode {.noSideEffect.}): JsonNode =
  ## Serialise Filter[C] to JSON. Caller provides condition serialiser.
  case f.kind
  of fkCondition:
    condToJson(f.condition)
  of fkOperator:
    {.cast(noSideEffect).}:  # §1.6: local ref mutation
      var conditions = newJArray()
      for child in f.conditions:
        conditions.add(child.toJson(condToJson))
      %*{"operator": $f.operator, "conditions": conditions}
```

**`fromJson`:**

```nim
func fromJson*[C](T: typedesc[Filter[C]], node: JsonNode,
    fromCondition: proc(n: JsonNode): Result[C, ValidationError]
    {.noSideEffect.}): Result[Filter[C], ValidationError] =
  ## Deserialise JSON to Filter[C]. Caller provides condition deserialiser.
  ## Dispatches on presence of "operator" key.
  checkJsonKind(node, JObject, $T)
  let opNode = node{"operator"}
  if opNode.isNil:
    # No "operator" key → leaf condition
    let cond = ? fromCondition(node)
    ok(filterCondition(cond))
  else:
    # Has "operator" key → composed filter
    let op = ? FilterOperator.fromJson(opNode)
    let conditionsNode = node{"conditions"}
    checkJsonKind(conditionsNode, JArray, $T,
      "missing or invalid conditions array")
    var children: seq[Filter[C]]
    for childNode in conditionsNode.getElems(@[]):
      let child = ? Filter[C].fromJson(childNode, fromCondition)
      children.add(child)
    ok(filterOperator(op, children))
```

**Generic callback note.** The `fromCondition` callback has type
`proc(...) {.noSideEffect.}`. Under `strictFuncs`, this should be
effect-compatible since `func` is `proc {.noSideEffect.}`. If the compiler
rejects this parameter type, use a template wrapper as fallback (see §1.2).

**Module:** `src/jmap_client/serde_framework.nim`

### 7.3 PatchObject

**RFC reference:** §5.3 (lines 1895–1940).

A map of JSON Pointer paths to values. Keys are property paths (implicit
leading `/`). `null` value means "delete property".

**Wire format:**

```json
{
  "name": "New Mailbox Name",
  "parentId": "id-of-parent",
  "role": null
}
```

**`toJson`:**

```nim
func toJson*(patch: PatchObject): JsonNode =
  ## Serialise PatchObject to JSON. Keys are JSON Pointer paths,
  ## null values represent property deletion.
  let tbl = Table[string, JsonNode](patch)
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    for path, value in tbl:
      result[path] = value
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[PatchObject], node: JsonNode
    ): Result[PatchObject, ValidationError] =
  ## Deserialise JSON to PatchObject using smart constructors.
  ## null values → deleteProp, other values → setProp.
  checkJsonKind(node, JObject, $T)
  var patch = emptyPatch()
  for path, value in node.pairs:  # kind verified above
    if value.isNil or value.kind == JNull:
      patch = ? deleteProp(patch, path)
    else:
      patch = ? setProp(patch, path, value)
  ok(patch)
```

**Rationale.** `fromJson` uses only the smart constructors (`emptyPatch`,
`setProp`, `deleteProp`) — never accesses the underlying
`Table[string, JsonNode]` directly. This respects Layer 1's opaque
`PatchObject` design (Decision 1.5B).

**Module:** `src/jmap_client/serde_framework.nim`

### 7.4 AddedItem

**RFC reference:** §5.6 (lines 2639–2819).

**Wire format:**

```json
{"id": "msg1023", "index": 10}
```

**`toJson`:**

```nim
func toJson*(item: AddedItem): JsonNode =
  ## Serialise AddedItem to JSON (RFC 8620 §5.6).
  {.cast(noSideEffect).}:  # §1.6: full cast
    result = %*{"id": string(item.id), "index": int64(item.index)}
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[AddedItem], node: JsonNode
    ): Result[AddedItem, ValidationError] =
  ## Deserialise JSON to AddedItem.
  checkJsonKind(node, JObject, $T)
  let id = ? Id.fromJson(node{"id"})
  let index = ? UnsignedInt.fromJson(node{"index"})
  ok(AddedItem(id: id, index: index))
```

**Module:** `src/jmap_client/serde_framework.nim`

### 7.5 PropertyName

Distinct string type — same pattern as §3.1. `toJson` unwraps with
`string(x)`, `fromJson` calls `parsePropertyName`.

**Module:** `src/jmap_client/serde.nim`

---

## 8. Error Type Serialisation

### 8.1 RequestError

**RFC reference:** §3.6.1 (lines 1079–1136), RFC 7807.

Represents a request-level error — an HTTP response with
`Content-Type: application/problem+json`. The server returns these when the
entire request is rejected before any method calls are processed.

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
func toJson*(re: RequestError): JsonNode =
  ## Serialise RequestError to RFC 7807 problem details JSON.
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    result["type"] = %re.rawType  # Decision 1.7C: always use rawType
    if re.status.isSome:
      result["status"] = %re.status.get()
    if re.title.isSome:
      result["title"] = %re.title.get()
    if re.detail.isSome:
      result["detail"] = %re.detail.get()
    if re.limit.isSome:
      result["limit"] = %re.limit.get()
    if re.extras.isSome:
      for key, val in re.extras.get().pairs:
        result[key] = val
```

**`fromJson`:**

```nim
const RequestErrorKnownKeys = [
  "type", "status", "title", "detail", "limit"]

func fromJson*(T: typedesc[RequestError], node: JsonNode
    ): Result[RequestError, ValidationError] =
  ## Deserialise RFC 7807 problem details JSON to RequestError.
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T,
    "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let status: Opt[int] =
    if node{"status"}.isNil or node{"status"}.kind != JInt:
      Opt.none(int)
    else:
      Opt.some(int(node{"status"}.getBiggestInt(0)))
  let title: Opt[string] =
    if node{"title"}.isNil or node{"title"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"title"}.getStr(""))
  let detail: Opt[string] =
    if node{"detail"}.isNil or node{"detail"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"detail"}.getStr(""))
  let limit: Opt[string] =
    if node{"limit"}.isNil or node{"limit"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"limit"}.getStr(""))
  let extras = collectExtras(node, RequestErrorKnownKeys)
  ok(requestError(
    rawType = rawType,
    status = status,
    title = title,
    detail = detail,
    limit = limit,
    extras = extras,
  ))
```

Note: `fromJson` calls `requestError(rawType, ...)` which auto-parses the
raw type string to the `RequestErrorType` enum via `parseRequestErrorType`.

**Module:** `src/jmap_client/serde_errors.nim`

### 8.2 MethodError

**RFC reference:** §3.6.2 (lines 1137–1219).

Per-invocation error within a JMAP response. When the server returns
`["error", {...}, "c1"]`, the `Invocation.name` is `"error"` and the
`arguments` JSON is parsed as a `MethodError`.

**Wire format:**

```json
{"type": "unknownMethod", "description": "No method 'Foo/bar' exists."}
```

**`toJson`:**

```nim
func toJson*(me: MethodError): JsonNode =
  ## Serialise MethodError to JSON (RFC 8620 §3.6.2).
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    result["type"] = %me.rawType  # Decision 1.7C: always use rawType
    if me.description.isSome:
      result["description"] = %me.description.get()
    if me.extras.isSome:
      for key, val in me.extras.get().pairs:
        result[key] = val
```

**`fromJson`:**

```nim
const MethodErrorKnownKeys = ["type", "description"]

func fromJson*(T: typedesc[MethodError], node: JsonNode
    ): Result[MethodError, ValidationError] =
  ## Deserialise error invocation arguments to MethodError.
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T,
    "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let description: Opt[string] =  # §1.4b: lenient
    if node{"description"}.isNil or node{"description"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"description"}.getStr(""))
  let extras = collectExtras(node, MethodErrorKnownKeys)
  ok(methodError(rawType = rawType, description = description, extras = extras))
```

**Module:** `src/jmap_client/serde_errors.nim`

### 8.3 SetError

**RFC reference:** §5.3 (lines 2060–2190), §5.4 (lines 2191–2338).

Per-item error within `/set` and `/copy` responses. A case object with
variant-specific fields: `invalidProperties` carries `properties: seq[string]`,
`alreadyExists` carries `existingId: Id`.

**Wire format:**

```json
{"type": "invalidProperties", "properties": ["name", "role"]}
```

```json
{"type": "alreadyExists", "existingId": "msg42"}
```

**`toJson`:**

```nim
func toJson*(se: SetError): JsonNode =
  ## Serialise SetError to JSON (RFC 8620 §5.3, §5.4).
  {.cast(noSideEffect).}:  # §1.6: local ref mutation
    result = newJObject()
    result["type"] = %se.rawType  # Decision 1.7C: always use rawType
    if se.description.isSome:
      result["description"] = %se.description.get()
    case se.errorType
    of setInvalidProperties:
      if se.properties.len > 0:
        result["properties"] = %se.properties
    of setAlreadyExists:
      result["existingId"] = %string(se.existingId)
    else:
      discard
    if se.extras.isSome:
      for key, val in se.extras.get().pairs:
        result[key] = val
```

**`fromJson`:**

```nim
func fromJson*(T: typedesc[SetError], node: JsonNode
    ): Result[SetError, ValidationError] =
  ## Deserialise JSON to SetError with defensive fallback (L1 §8.10).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T,
    "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let description: Opt[string] =  # §1.4b: lenient
    if node{"description"}.isNil or node{"description"}.kind != JString:
      Opt.none(string)
    else:
      Opt.some(node{"description"}.getStr(""))
  let errorType = parseSetErrorType(rawType)
  # Per-variant known keys: variant-specific fields are "known" only for
  # their own variant. Misplaced RFC fields on other variants are preserved
  # in extras rather than silently dropped (Decision 1.7C: lossless).
  let knownKeys = case errorType
    of setInvalidProperties: @["type", "description", "properties"]
    of setAlreadyExists: @["type", "description", "existingId"]
    else: @["type", "description"]
  let extras = collectExtras(node, knownKeys)

  # Defensive fallback: dispatch to variant-specific constructors only
  # when variant data is present. Otherwise fall back to generic setError
  # which maps invalidProperties/alreadyExists to setUnknown.
  case errorType
  of setInvalidProperties:
    let propsNode = node{"properties"}
    if not propsNode.isNil and propsNode.kind == JArray:
      var properties: seq[string]
      for item in propsNode.getElems(@[]):
        checkJsonKind(item, JString, $T,
          "properties element must be string")
        properties.add(item.getStr(""))
      return ok(setErrorInvalidProperties(
        rawType, properties, description, extras))
    # properties absent — defensive fallback to setUnknown via setError
    ok(setError(rawType, description, extras))
  of setAlreadyExists:
    let idNode = node{"existingId"}
    if not idNode.isNil and idNode.kind == JString:
      let existingId = ? parseIdFromServer(idNode.getStr(""))
      return ok(setErrorAlreadyExists(
        rawType, existingId, description, extras))
    # existingId absent — defensive fallback to setUnknown via setError
    ok(setError(rawType, description, extras))
  else:
    ok(setError(rawType, description, extras))
```

**Rationale.** The defensive fallback matches Layer 1 §8.10: when a server
sends `"type": "invalidProperties"` without the `properties` array, or
`"type": "alreadyExists"` without `existingId`, `fromJson` calls the generic
`setError` constructor which maps these to `setUnknown` (preserving
`rawType`). This ensures pattern-matching consumers never encounter a
`setInvalidProperties` variant with empty properties or a `setAlreadyExists`
variant with a bogus `existingId`.

**Module:** `src/jmap_client/serde_errors.nim`

### 8.4 Types NOT Serialised

Explicit list of Layer 1 types with NO `toJson`/`fromJson`:

- `TransportError` — library-internal, constructed by Layer 4 from
  `std/httpclient` exceptions. No wire format.
- `TransportErrorKind` — discriminator enum for `TransportError`.
- `ClientError` — outer railway wrapper, constructed by Layer 4.
- `ClientErrorKind` — discriminator enum for `ClientError`.
- `ValidationError` — returned by `fromJson`, not itself serialised to JSON.
- `JmapResult[T]` — type alias for `Result[T, ClientError]`; serialisation
  handled by the contained `T`.
- `ReferencableKind` — discriminator enum; `Referencable[T]` serialisation
  uses `#`-prefix key dispatch instead.
- `FilterKind` — discriminator enum; `Filter[C]` serialisation uses
  `"operator"` key presence instead.

---

## 9. Opt[T] Field Handling Convention

Cross-cutting concern documented here once, referenced throughout
Sections 3–8. See §1.4b for the leniency policy rationale.

**`toJson` convention.** `isNone` → omit key entirely (NOT emit `null`).
`isSome` → emit value. This is consistent with JMAP's "absent means
default" semantics.

**`fromJson` convention.** For simple scalar `Opt` fields:
`node{"field"}.isNil` or wrong `JsonNodeKind` → `Opt.none(T)`.
Correct kind → extract value. Wrong kind maps to `Opt.none`, not `err`
— this is the lenient policy (§1.4b). For complex container `Opt` types
(`Opt[Table[...]]`), wrong container kind returns `err`.

**Per-type Opt[T] field table** (every Opt field in Layer 1 with its null
semantics and wrong-kind handling):

| Type | Field | Opt Semantics | Wrong Kind | Notes |
|------|-------|---------------|------------|-------|
| `Request` | `createdIds` | Absent = not provided | `err` (container) | Presence triggers proxy splitting |
| `Response` | `createdIds` | Absent = not in request | `err` (container) | Only present if request included it |
| `Comparator` | `collation` | Absent = server default | `Opt.none` | |
| `RequestError` | `status` | Absent = not provided | `Opt.none` | |
| `RequestError` | `title` | Absent = not provided | `Opt.none` | |
| `RequestError` | `detail` | Absent = not provided | `Opt.none` | |
| `RequestError` | `limit` | Absent = not provided | `Opt.none` | Only meaningful for `retLimit` |
| `RequestError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |
| `MethodError` | `description` | Absent = not provided | `Opt.none` | |
| `MethodError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |
| `SetError` | `description` | Absent = not provided | `Opt.none` | |
| `SetError` | `extras` | Absent = no non-standard fields | N/A | `collectExtras` helper |

---

## 10. Serialisation Pair Inventory

Complete verification table — every Layer 1 type with its ser/de status:

| Type | Module | Pattern | Direction | L1 Constructor(s) Called | Notes |
|------|--------|---------|-----------|--------------------------|-------|
| `Id` | serde | Identity | Both | `parseIdFromServer` | Lenient (server-assigned) |
| `UnsignedInt` | serde | Identity | Both | `parseUnsignedInt` | `getBiggestInt` accessor |
| `JmapInt` | serde | Identity | Both | `parseJmapInt` | `getBiggestInt` accessor |
| `Date` | serde | Identity | Both | `parseDate` | String round-trip |
| `UTCDate` | serde | Identity | Both | `parseUtcDate` | String round-trip |
| `AccountId` | serde | Identity | Both | `parseAccountId` | Lenient (server-assigned) |
| `JmapState` | serde | Identity | Both | `parseJmapState` | |
| `MethodCallId` | serde | Identity | Both | `parseMethodCallId` | |
| `CreationId` | serde | Identity | Both | `parseCreationId` | No `#` prefix in stored value |
| `UriTemplate` | serde | Identity | Both | `parseUriTemplate` | |
| `PropertyName` | serde | Identity | Both | `parsePropertyName` | |
| `CapabilityKind` | — | Enum | — | `parseCapabilityKind` | Not standalone; via `rawUri` |
| `FilterOperator` | serde_framework | Enum | Both | Manual case dispatch | NOT total — err on unknown |
| `RequestErrorType` | — | — | — | `parseRequestErrorType` | Embedded in `requestError()` |
| `MethodErrorType` | — | — | — | `parseMethodErrorType` | Embedded in `methodError()` |
| `SetErrorType` | — | — | — | `parseSetErrorType` | Embedded in `setError()` |
| `CoreCapabilities` | serde_session | A: Object | Both | `parseUnsignedInt` ×7 | RFC typo tolerance |
| `ServerCapability` | serde_session | B: Case | Both | `parseCapabilityKind` + sub-parse | URI dispatch |
| `AccountCapabilityEntry` | serde_session | A: Object | Both | `parseCapabilityKind` | |
| `Account` | serde_session | A: Object | Both | — | Fields use sub-parsers |
| `Session` | serde_session | A: Composite | Both | `parseSession` + all sub-parsers | Most complex |
| `Invocation` | serde_envelope | C: Array | Both | `parseMethodCallId` | 3-element JSON array |
| `Request` | serde_envelope | A: Object | Both | `parseCreationId`, `parseIdFromServer` | Opt createdIds |
| `Response` | serde_envelope | A: Object | Both | `parseJmapState`, `parseCreationId`, `parseIdFromServer` | |
| `ResultReference` | serde_envelope | A: Object | Both | `parseMethodCallId` | |
| `Referencable[T]` | serde_envelope | C: Field | Both | Sub-parser + `ResultReference.fromJson` | `#`-prefix dispatch |
| `Comparator` | serde_framework | A: Object | Both | `parsePropertyName`, `parseComparator` | `isAscending` default |
| `Filter[C]` | serde_framework | C: Recursive | Both | Callback for `C` | Generic |
| `PatchObject` | serde_framework | C: Pointer | Both | `emptyPatch`, `setProp`, `deleteProp` | `JNull` → delete |
| `AddedItem` | serde_framework | A: Object | Both | `parseIdFromServer`, `parseUnsignedInt` | |
| `RequestError` | serde_errors | A: Object | Both | `requestError` | `collectExtras` |
| `MethodError` | serde_errors | A: Object | Both | `methodError` | `collectExtras` |
| `SetError` | serde_errors | B: Case | Both | `setError`, `setErrorInvalidProperties`, `setErrorAlreadyExists` | Defensive fallback |
| `TransportError` | — | — | Not serialised | — | Library-internal |
| `TransportErrorKind` | — | — | Not serialised | — | Discriminator enum |
| `ClientError` | — | — | Not serialised | — | Outer railway wrapper |
| `ClientErrorKind` | — | — | Not serialised | — | Discriminator enum |
| `ValidationError` | — | — | Not serialised | — | Error return type |
| `JmapResult[T]` | — | — | Not serialised | — | Type alias |
| `ReferencableKind` | — | — | Not serialised | — | Discriminator enum |
| `FilterKind` | — | — | Not serialised | — | Discriminator enum |

---

## 11. Round-Trip Invariants

Properties that must hold for every serialised type:

- **Identity:** `T.fromJson(x.toJson()).isOk` and
  `T.fromJson(x.toJson()).get() == x` for all `x` **produced by `fromJson`
  or by Layer 3 builders**. Values constructed by direct Layer 1 object
  construction may violate wire-format invariants not expressible in the
  type system (e.g., empty `Invocation.name`). Round-trip tests compare
  **parsed values** (structural equality), not JSON strings (Table
  iteration order is non-deterministic).
- **Lossless rawType/rawUri:** For error types and capabilities with
  catch-all variants, the raw string is preserved through round-trip.
  `$enumVal` is never used for serialisation.
- **Opt[T] omission:** `isNone` values produce no JSON key; parsing absent
  keys produces `Opt.none`.
- **Invocation format:** `Invocation.toJson` always produces a 3-element
  `JArray`, never `JObject`.
- **Referencable dispatch:** `rkDirect` values serialise without `#` prefix;
  `rkReference` values serialise with `#` prefix. Round-trip preserves the
  variant.
- **Capability URI uniqueness:** `Session.toJson` assumes no duplicate
  `rawUri` in `capabilities`. Round-trip identity holds when this
  precondition is met (always true for `fromJson`-constructed Sessions).
- **Losslessness scope:** Round-trip losslessness applies to fields stored
  in the Layer 1 type. Error types (`RequestError`, `MethodError`,
  `SetError`) preserve non-standard server fields via `extras:
  Opt[JsonNode]`. `Session`, `Account`, and `CoreCapabilities` do not
  carry an `extras` field — unknown fields are dropped during
  deserialisation. This is a Layer 1 scope decision, not a Layer 2 gap.

---

## 12. Module File Layout

**File header template** (required for `reuse lint` — every `.nim` file):

```nim
# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
```

SPDX header on line 1. No blank line before. Matches existing Layer 1
pattern.

**Docstring requirement** (required for nimalyzer `hasDoc` rule): every
exported `func` must have a `##` docstring (Layer 2 defines no `proc`
— callback parameter types use `proc {.noSideEffect.}`).
Comments and docstrings use British English spelling (CLAUDE.md §Language).

**Source modules:**

```
src/jmap_client/
  serialisation.nim      ← Re-export hub (Layer 2 equivalent of types.nim);
                           imports and re-exports serde + all domain modules
  serde.nim              ← parseError, checkJsonKind, collectExtras,
                           primitive/identifier/enum ser/de
  serde_session.nim      ← CoreCapabilities, ServerCapability,
                           AccountCapabilityEntry, Account, Session
  serde_envelope.nim     ← Invocation, Request, Response,
                           ResultReference, Referencable[T] helpers
  serde_framework.nim    ← Comparator, Filter[C], PatchObject, AddedItem,
                           PropertyName, FilterOperator
  serde_errors.nim       ← RequestError, MethodError, SetError
```

**Test modules** (testament auto-discovers `tests/t*.nim`):

```
tests/
  tserde.nim             ← Shared helpers, primitive/identifier/enum
                           round-trips
  tserde_session.nim     ← CoreCapabilities, ServerCapability, Account,
                           Session (§13.1 golden test)
  tserde_envelope.nim    ← Invocation, Request, Response,
                           ResultReference, Referencable[T] (§13.2–3)
  tserde_framework.nim   ← Comparator, Filter[C], PatchObject, AddedItem,
                           FilterOperator
  tserde_errors.nim      ← RequestError, MethodError, SetError
```

Tests use `doAssert` (testament), block-scoped tests with labelled blocks,
and existing `massertions.nim` helpers (`assertOk`, `assertErr`,
`assertErrFields`, `assertErrType`). No `unittest` module. No nimble
registration needed — auto-discovery via glob pattern.

**Import graph** (flat — no internal Layer 2 dependencies):

```
Layer 1: types.nim (re-exports all L1 modules)
  ^          ^          ^          ^          ^
  |          |          |          |          |
serde.nim  serde_session  serde_envelope  serde_framework  serde_errors
  ^          |          |          |          |
  +----------+----------+----------+----------+
  (all domain serde modules import serde.nim for shared helpers)

serialisation.nim ← re-exports serde + all domain modules
  (Layer 3 imports serialisation.nim)
```

`serialisation.nim` is the re-export hub (Layer 2 equivalent of
`types.nim`), re-exporting `serde.nim` and all domain serde modules.
`serde.nim` defines shared helpers (`parseError`, `checkJsonKind`,
`collectExtras`) and primitive/identifier ser/de functions. Domain serde
modules import `serde.nim` for helpers — they do NOT import each other.
No circular dependencies.

All domain serde modules (`serde_session`, `serde_envelope`,
`serde_framework`, `serde_errors`) import `serde.nim` for shared helpers
and `types.nim` for Layer 1 types. No domain serde module imports another
domain serde module — `serde_session.nim` does not need envelope types,
and vice versa. This mirrors Layer 1's flat-dependency pattern within
each group.

**Downstream:** Layer 3 imports `serialisation.nim` (which re-exports
everything). Tests import individual serde modules for focused testing.

**Why 6 files, not 1.** With ~15-20 ser/de pairs producing ~600-900 lines, a
single file is feasible. However, 6 files provide: (a) independently testable
modules (each test file mirrors one serde file), (b) parallel structure with
Layer 1's module grouping, (c) bounded file size (~120-180 lines each),
(d) acyclic import graph (`serialisation.nim` re-exports without creating
import cycles). The flat import graph means no cost to the split.

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
`Session.fromJson(Session.toJson(parsed)).get() == parsed`

Note: RFC example uses `"maxConcurrentRequest"` (singular) — D2.6 typo
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
- `request.methodCalls[0].name == "method1"`
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
- `response.methodResponses[3].name == "error"` (method-level error)
- `response.sessionState == JmapState("75128aab4b1b")`
- `response.createdIds.isNone`

### 13.4 Edge Cases per Type

| Type | Input JSON | Expected | Reason |
|------|-----------|----------|--------|
| `Id` (deser) | `%"abc123-_XYZ"` | `ok` | Valid base64url (lenient) |
| `Id` (deser) | `%42` | `err` | Wrong JSON kind (JInt, not JString) |
| `Id` (deser) | `nil` (missing field) | `err` | Nil JsonNode |
| `Id` (deser) | `newJNull()` | `err` | JNull, not JString |
| `Id` (deser) | `%*[1,2,3]` | `err` | JArray, not JString |
| `Id` (deser) | `%""` | `err` | Empty string (parseIdFromServer rejects) |
| `UnsignedInt` (deser) | `%0` | `ok` | Minimum valid |
| `UnsignedInt` (deser) | `%9007199254740991` | `ok` | 2^53-1, maximum valid |
| `UnsignedInt` (deser) | `%(-1)` | `err` | Negative (parseUnsignedInt rejects) |
| `UnsignedInt` (deser) | `%"42"` | `err` | Wrong JSON kind (JString, not JInt) |
| `UnsignedInt` (deser) | `nil` | `err` | Nil JsonNode |
| `UnsignedInt` (deser) | `newJNull()` | `err` | JNull, not JInt |
| `JmapInt` (deser) | `%(-9007199254740991)` | `ok` | -(2^53-1), minimum valid |
| `JmapInt` (deser) | `%"hello"` | `err` | Wrong JSON kind |
| `Date` (deser) | `%"2014-10-30T14:12:00+08:00"` | `ok` | RFC example |
| `Date` (deser) | `%42` | `err` | Wrong JSON kind |
| `Date` (deser) | `%"2014-10-30t14:12:00Z"` | `err` | Lowercase 't' (parseDate rejects) |
| `UTCDate` (deser) | `%"2014-10-30T06:12:00Z"` | `ok` | RFC example |
| `UTCDate` (deser) | `%"2014-10-30T06:12:00+00:00"` | `err` | Must be Z, not +00:00 |
| `AccountId` (deser) | `%"A13824"` | `ok` | RFC §2.1 example |
| `AccountId` (deser) | `%""` | `err` | Empty string |
| `AccountId` (deser) | `%42` | `err` | Wrong JSON kind |
| `JmapState` (deser) | `%"75128aab4b1b"` | `ok` | RFC §2.1 example |
| `JmapState` (deser) | `%""` | `err` | Empty string |
| `MethodCallId` (deser) | `%"c1"` | `ok` | RFC example |
| `MethodCallId` (deser) | `%""` | `err` | Empty string |
| `CreationId` (deser) | `%"abc"` | `ok` | Valid creation ID |
| `CreationId` (deser) | `%"#abc"` | `err` | Must not include `#` prefix |
| `PropertyName` (deser) | `%"name"` | `ok` | Valid property name |
| `PropertyName` (deser) | `%""` | `err` | Empty property name |
| `Invocation` (deser) | `%*["Mailbox/get", {}, "c1"]` | `ok` | Valid 3-element array |
| `Invocation` (deser) | `%*{"name": "x", "args": {}, "id": "c1"}` | `err` | JSON object instead of array |
| `Invocation` (deser) | `%*["Mailbox/get", {}]` | `err` | Only 2 elements |
| `Invocation` (deser) | `%*["Mailbox/get", {}, "c1", "extra"]` | `err` | 4 elements |
| `Invocation` (deser) | `%*[42, {}, "c1"]` | `err` | `checkJsonKind` rejects JInt → "method name must be string" |
| `Invocation` (deser) | `%*["Mailbox/get", "notobject", "c1"]` | `err` | `checkJsonKind` rejects JString → "arguments must be JSON object" |
| `Invocation` (deser) | `%*["Mailbox/get", {}, 42]` | `err` | `checkJsonKind` rejects JInt → "method call ID must be string" |
| `Invocation` (deser) | `%*["", {}, "c1"]` | `err` | Empty method name |
| `Invocation` (round-trip) | Valid Invocation | `toJson` produces JArray len 3 | Format verification |
| `Invocation` (round-trip) | Valid Invocation | `fromJson(toJson(x)).get() == x` | Identity |
| `Session` (deser) | RFC §2.1 JSON | `ok` | Golden test |
| `Session` (deser) | Missing `capabilities` key | `err` | Required field |
| `Session` (deser) | `capabilities` not an object | `err` | Wrong kind |
| `Session` (deser) | Missing core capability | `err` | `parseSession` rejects |
| `Session` (deser) | Unknown capability URIs | `ok` with `ckUnknown` | Preserved |
| `Session` (deser) | `maxConcurrentRequest` (singular) | `ok` | D2.6 typo tolerance |
| `Session` (deser) | Extra unknown top-level fields | `ok` | Ignored per RFC |
| `Session` (deser) | Missing `primaryAccounts` key | `err` | Required field |
| `Session` (deser) | `primaryAccounts` value is integer | `err` | `checkJsonKind` rejects |
| `Session` (deser) | Empty accounts object | `ok` | |
| `CoreCapabilities` (deser) | Valid with all 8 fields | `ok` | |
| `CoreCapabilities` (deser) | Missing required field | `err` | |
| `CoreCapabilities` (deser) | `"maxSizeUpload": "string"` | `err` | Wrong kind for UnsignedInt |
| `CoreCapabilities` (deser) | `"maxSizeUpload": -1` | `err` | `parseUnsignedInt` rejects |
| `CoreCapabilities` (deser) | Empty `collationAlgorithms` | `ok` | Empty HashSet |
| `ServerCapability` (deser) | `ckCore` with valid data | `ok` | |
| `ServerCapability` (deser) | `ckCore` missing required field | `err` | Propagated from CoreCapabilities |
| `ServerCapability` (deser) | Unknown URI + arbitrary JSON | `ok` with `ckUnknown` | |
| `ServerCapability` (deser) | Known non-core URI (ckMail) | `ok` with `rawData` | |
| `Referencable` (deser) | `"ids": [...]` | `rkDirect` | Direct value |
| `Referencable` (deser) | `"#ids": {"resultOf":..}` | `rkReference` | Reference |
| `Referencable` (deser) | Reference missing `resultOf` | `err` | Invalid reference |
| `Referencable` (deser) | Both `"ids"` and `"#ids"` present | `rkReference` | `#`-prefixed key takes precedence; direct key ignored. Consistent with RFC intent: if a reference is present, the server resolves it |
| `Referencable` (deser) | `"#ids": 42` (wrong kind) | `err` | `#` prefix is a semantic commitment — malformed reference is an error, not an absent reference |
| `Referencable` (deser) | `"#ids": "string"` (wrong kind) | `err` | Reference value must be JObject |
| `Filter` (deser) | Condition (no `operator` key) | `fkCondition` | Leaf node |
| `Filter` (deser) | Operator with conditions | `fkOperator` | Composed node |
| `Filter` (deser) | Nested operators (depth 2) | `ok` | Recursive |
| `Filter` (deser) | Operator with empty conditions | `ok` | Valid per RFC |
| `Filter` (deser) | Operator missing `conditions` | `err` | Required field |
| `PatchObject` (deser) | `{"name": "New Name"}` | `ok` | Single property set |
| `PatchObject` (deser) | `{"role": null}` | `ok` with `deleteProp` | Null = delete |
| `PatchObject` (deser) | `{"a": 1, "b": 2}` | `ok` | Multiple properties |
| `PatchObject` (deser) | `{}` | `ok` | Empty patch |
| `PatchObject` (deser) | `"notobject"` | `err` | Non-object JSON |
| `SetError` (deser) | `{"type": "forbidden"}` | `setForbidden` | Non-variant |
| `SetError` (deser) | `{"type": "invalidProperties", "properties": ["name"]}` | `setInvalidProperties` | With variant data |
| `SetError` (deser) | `{"type": "invalidProperties"}` | `setUnknown` | Defensive fallback — missing properties |
| `SetError` (deser) | `{"type": "alreadyExists", "existingId": "msg42"}` | `setAlreadyExists` | With variant data |
| `SetError` (deser) | `{"type": "alreadyExists"}` | `setUnknown` | Defensive fallback — missing existingId |
| `SetError` (deser) | `{"type": "vendorSpecific"}` | `setUnknown` | rawType preserved |
| `SetError` (deser) | `{"type": "forbidden", "properties": ["name"]}` | `setForbidden` with `extras` containing `properties` | Per-variant known keys: `properties` is unknown for `setForbidden`, preserved in extras |
| `RequestError` (deser) | Valid RFC 7807 with known type URI | `ok` | Parsed errorType |
| `RequestError` (deser) | Unknown type URI | `ok` with `retUnknown` | rawType preserved |
| `RequestError` (deser) | With extra fields | extras collected in `Opt[JsonNode]` | Lossless |
| `RequestError` (deser) | Missing `type` field | `err` | `checkJsonKind` rejects |
| `RequestError` (deser) | `"type": 42` (wrong kind) | `err` | `checkJsonKind` rejects JInt — "missing or invalid type" |
| `MethodError` (deser) | Valid with known type | `ok` | |
| `MethodError` (deser) | Unknown type | `ok` with `metUnknown` | rawType preserved |
| `MethodError` (deser) | With `description` | `description.isSome` | |
| `MethodError` (deser) | With extra server fields | extras collected | |
| `MethodError` (deser) | `"description": 42` (wrong kind) | `ok` with `description.isNone` | §1.4b lenient |
| `SetError` (deser) | `"description": 42` (wrong kind) | `ok` with `description.isNone` | §1.4b lenient |
| `Request` (deser) | With `createdIds` | `Opt.some` | |
| `Request` (deser) | Without `createdIds` | `Opt.none` | |
| `Response` (deser) | With `createdIds` | `Opt.some` | |
| `Response` (deser) | `sessionState` via `parseJmapState` | validated | |
| `Response` (deser) | Empty `methodResponses` | `ok` | |
| `Response` (deser) | Missing `sessionState` | `err` | Required |
| `Comparator` (deser) | All fields present | `ok` | |
| `Comparator` (deser) | Missing `isAscending` | `ok` with default `true` | RFC default |
| `Comparator` (deser) | Missing `property` | `err` | Required |
| `Comparator` (deser) | `{"property": 42, "isAscending": true}` | `err` | Wrong kind for property (JInt, not JString) |
| `AddedItem` (deser) | Valid `{"id": "x", "index": 5}` | `ok` | |
| `AddedItem` (deser) | Invalid `id` | `err` | Propagated from Id.fromJson |
| `ResultReference` (deser) | Valid | `ok` | |
| `FilterOperator` (deser) | `"AND"` | `ok(foAnd)` | |
| `FilterOperator` (deser) | `"CUSTOM"` | `err` | Not total — exhaustive per RFC |

**Total: ~108 enumerated edge case rows.**

---

## 14. Design Decisions Summary

| ID | Decision | Alternatives | Rationale |
|----|----------|-------------|-----------|
| D2.1 | Error type: reuse `ValidationError` (1.1B) | New `DeserialiseError` (1.1A) | Composes with L1 smart constructors via `?` without `mapErr` |
| D2.2 | Module layout: 6 files (5 content + 1 re-export hub) | Single `serde.nim` | Independently testable; mirrors L1 grouping; bounded file size |
| D2.3 | Parse boundary: Layer 4 concern | `safeParseJson` in Layer 2 | Layer 2 is pure `func` — receives `JsonNode`, not raw strings. `string → JsonNode` requires exception handling, which belongs in the imperative shell (Layer 4) |
| D2.4 | Generic `Filter[C]`: callback parameter | Typeclass/concept | L2 Core cannot know entity condition types; verify at compile time |
| D2.5 | `Referencable[T]`: field-level scope | Standalone `toJson`/`fromJson` | `#`-prefix is on JSON key, not value — containing object must dispatch |
| D2.6 | RFC typo: accept both singular/plural | Strict plural only | RFC §2.1 example has `maxConcurrentRequest` (singular); servers may follow |
| D2.7 | `Opt[T]`: omit key when `isNone` | Emit `null` | JMAP "absent means default" semantics |
| D2.8 | `fromJson` returns `Result[T, ValidationError]` | `JmapResult[T]` | `parseError` produces `ValidationError`; lift to `JmapResult` is Layer 4 |
| D2.9 | Int accessor: `getBiggestInt` | `getInt` | `UnsignedInt`/`JmapInt` are `distinct int64`; `getInt` may truncate on 32-bit |
| D2.10 | Provide `toJson` for all types | Deser-only for server types | Round-trip testing and debugging require both directions |
| D2.11 | Enum deser: total (except `FilterOperator`) | All return `Result` | Matches L1 total parse functions; `FilterOperator` exhaustive per RFC |
| D2.12 | `extras` collection: `collectExtras` helper func | Inline per-type | Shared pattern across `RequestError`, `MethodError`, `SetError` |
| D2.13 | `toJson` output: compact (default `$`) | Pretty-printed | Wire format; human readability via `pretty()` at call site if needed |
| D2.14 | String encoding: UTF-8, automatic escaping | Manual escaping | `std/json` handles UTF-8 and escaping per I-JSON (RFC 7493) |
| D2.15 | `Opt[T]` wrong kind: lenient (`Opt.none`) | Strict (`err`) | Client library parsing server data — Postel's law. Strictness on error-type supplementary fields loses the critical `type` field (§1.4b) |

---

## Appendix: RFC Section Cross-Reference

| Type | RFC 8620 Section | Wire Format |
|------|-----------------|-------------|
| `Id` | §1.2 (lines 287–319) | JSON String |
| `UnsignedInt` | §1.3 (lines 320–342) | JSON Number |
| `JmapInt` | §1.3 (lines 320–342) | JSON Number |
| `Date` | §1.4 (lines 343–354) | JSON String (RFC 3339) |
| `UTCDate` | §1.4 (lines 343–354) | JSON String (RFC 3339, Z suffix) |
| `Session` | §2 (lines 477–733) | JSON Object |
| `CoreCapabilities` | §2 (lines 511–572) | JSON Object |
| `Account` | §2 (lines 583–643) | JSON Object |
| `Invocation` | §3.2 (lines 865–881) | JSON Array (3 elements) |
| `Request` | §3.3 (lines 882–974) | JSON Object |
| `Response` | §3.4 (lines 975–1035) | JSON Object |
| `RequestError` | §3.6.1 (lines 1079–1136), RFC 7807 | JSON Object (problem details) |
| `MethodError` | §3.6.2 (lines 1137–1219) | JSON Object (via error Invocation) |
| `ResultReference` | §3.7 (lines 1220–1493) | JSON Object |
| `Referencable[T]` | §3.7 (lines 1220–1493) | `#`-prefix key dispatch |
| `Comparator` | §5.5 (lines 2339–2638) | JSON Object |
| `Filter[C]` | §5.5 (lines 2368–2394) | JSON Object (recursive) |
| `PatchObject` | §5.3 (lines 1895–1940) | JSON Object (pointer keys) |
| `AddedItem` | §5.6 (lines 2639–2819) | JSON Object |
| `SetError` | §5.3 (lines 2060–2190), §5.4 (lines 2191–2338) | JSON Object |
| `CapabilityKind` | §9.4 | JSON String (URI) |
| `FilterOperator` | §5.5 (lines 2339–2638) | JSON String ("AND"/"OR"/"NOT") |
