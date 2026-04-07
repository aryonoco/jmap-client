# Layer 3: Protocol Logic — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, serialisation pair, and
entity framework registration mechanism for Layer 3 of the jmap-client
library. It builds upon the decisions made in `00-architecture.md`, the
types defined in `01-layer-1-design.md`, and the serialisation
infrastructure established in `02-layer-2-design.md` so that
implementation is mechanical.

**Scope.** Layer 3 covers: the entity type framework (registration,
associated types, `mixin` resolution), all six standard method
request/response types (RFC 8620 §5.1–5.6), serialisation
(`toJson`/`fromJson`) for all Layer 3–defined types, the request builder
(`RequestBuilder` with `add*` methods and call ID generation), response
dispatch (`ResponseHandle[T]` phantom type and `get[T]` extraction),
result reference construction, and optional pipeline combinators
(`convenience.nim`). Transport (Layer 4), the C ABI (Layer 5), binary
data (§6), and push (§7) are out of scope. Layer 3 is the uppermost
layer of the pure core — no I/O, no global state mutation.

**Relationship to prior documents.** `00-architecture.md` records broad
decisions across all 5 layers. `04-architecture-revision.md` specifies
the migration from strict FP Nim to idiomatic Nim. This document is the
detailed specification for all Layer 3 components: `entity.nim` (entity
registration framework), `methods.nim` (request and response types with
serialisation), `builder.nim` (request builder with `add*` methods),
`dispatch.nim` (`ResponseHandle[T]` and `get[T]` extraction),
`protocol.nim` (re-export hub), and `convenience.nim` (optional pipeline
combinators).

Layer 3 operates on Layer 1 types: `Invocation`, `Request`, `Response`,
`ResultReference`, `Referencable[T]`, `Filter[C]`, `Comparator`,
`PatchObject`, `AddedItem`, all identifier types (`Id`, `AccountId`,
`JmapState`, `MethodCallId`, `CreationId`), `MaxChanges`, and all error
types (`MethodError`, `SetError`, `ValidationError`, `ClientError`). It
imports Layer 2's serialisation infrastructure: `parseError`,
`checkJsonKind`, `collectExtras`, `referencableKey`, `fromJsonField`,
and all primitive/identifier `toJson`/`fromJson` pairs.

**ARC note.** Layer 2's `serde_session.nim` deep-copies `JsonNode` via
`ownData`/`data.copy()` for case objects with `ref` fields in `else`
branches (ARC branch tracking corruption). Layer 3 response types are
plain objects (not case objects), so shared `JsonNode` refs from
`getElems()` are ARC ref-counted and safe. No deep-copy is needed for
Layer 3 types.

**Design principles.** Every decision follows:

- **Three-railway error model** — See below.
- **Compiler-enforced purity** — Layer 3 uses `func` for all pure
  functions. `proc` is used only for functions taking `proc` callback
  parameters (hidden pointer indirection prevents `func`). Purity is
  enforced by the compiler, not by convention.
- **Compiler-enforced effect safety** — `{.push raises: [].}` on every
  source module. All error handling uses `Result[T, E]` from nim-results
  with the `?` operator for early-return propagation. No exceptions
  escape any function.
- **Immutability by default** — `let` bindings. Local `var` only when
  building `JsonNode` trees or accumulating collections.
- **Parse, don't validate** — `fromJson` functions produce well-typed
  `Result` values by calling Layer 1 smart constructors. Invalid input
  returns `err(ValidationError)`.
- **Make illegal states unrepresentable** — Entity registration via
  `registerJmapEntity`/`registerQueryableEntity` catches missing
  overloads at definition time with domain-specific error messages.
  `Referencable[T]` encodes the direct/reference distinction in the
  type system. `ResponseHandle[T]` ties call IDs to response types at
  compile time.

### Error Model: Three Railways

JMAP has four distinct failure modes that occur at different points in
the request lifecycle. The library models these as three error railways,
each with its own mechanism chosen to match the failure's semantics:

```
  ┌───────────────────────────┬─────────────────────────────────────┬──────────────────────────────────────────────┐
  │          Railway          │              Mechanism              │                     Why                      │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Construction (Track 0)    │ Result[T, ValidationError]          │ Fails fast on bad input                      │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Transport (Track 1)       │ JmapResult[T] = Result[T, ClientError] │ No response to return                    │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Per-invocation (Track 2)  │ Result[T, MethodError]              │ Response succeeded; individual method failed │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Per-item (within Track 2) │ Result[T, SetError] as data         │ Method succeeded; individual item failed     │
  └───────────────────────────┴─────────────────────────────────────┴──────────────────────────────────────────────┘
```

**Track 0 — Construction railway.** Smart constructors (`parseId`,
`parseAccountId`, `parseJmapState`, etc.) return
`Result[T, ValidationError]` when given invalid input. This is a
programming error or malformed server data. `fromJson` functions
propagate these via the `?` operator — a `GetResponse.fromJson` that
encounters an invalid `accountId` returns `err` immediately. Track 0
errors abort the current parse.

**Track 1 — Transport/request railway.** `JmapResult[T]` (alias for
`Result[T, ClientError]`) wraps `TransportError` or `RequestError` when
the HTTP request itself fails — network error, TLS failure, timeout,
non-200 status, or a JMAP request-level error (RFC 7807 problem details
like `urn:ietf:params:jmap:error:notRequest`). There is no `Response` to
inspect. This is a Layer 4 concern; Layer 3 defines the error types but
does not produce them.

**Track 2 — Per-invocation method errors.** `MethodError` is a plain
`object` returned as data within a successful `Response`. The HTTP
request succeeded (200 OK), the JMAP envelope parsed correctly, but one
or more individual method calls within the batch failed. The server
signals this by returning `["error", {"type": "..."}, "callId"]` instead
of `["Foo/get", {...}, "callId"]`. `MethodError` is detected by the
dispatch function (`get[T]`, §3) by checking
`invocation.name == "error"`. Because the response is structurally valid,
returning an error via `Result` is more appropriate than an exception —
other method calls in the same batch may have succeeded.

**Per-item errors (within Track 2).** `SetError` is also a plain
`object`, not an exception. Within a successful `/set` or `/copy`
response, individual create/update/destroy operations may fail while
others succeed. These appear in the `notCreated`, `notUpdated`, and
`notDestroyed` wire maps. Again, the response is structurally valid and
other operations in the same call succeeded.

**Railway conversion at boundaries.**

- **Track 0 → Track 2 (dispatch boundary).** When the dispatch function
  (`get[T]`, §3) calls `T.fromJson` and receives
  `err(ValidationError)`, it converts it to `err(MethodError)` with type
  `serverFail` via `validationToMethodError`. The full `ValidationError`
  structure (`typeName`, `value`) is preserved in `MethodError.extras`
  for diagnostics. This conversion is lossless.
- **Track 0 + Track 1 → C error codes (Layer 5 boundary).** Layer 5
  pattern-matches on `Result` values and maps them to C-compatible
  integer error codes with thread-local error state.
- **Track 2 stays as data.** `MethodError` and `SetError` are never
  converted to exceptions. They flow through as `Result` error values
  or as fields in response objects, inspected by the caller via normal
  field access or `Result` combinators.

**Why `Result[T, E]` for all railways.** All three railways use
`Result[T, E]` from nim-results. `{.push raises: [].}` on every module
enforces that no `CatchableError` can escape any function. The `?`
operator provides ergonomic early-return propagation. Track 2 uses
`Result[T, MethodError]` rather than exceptions because method errors
are partial failure within a batch — the response envelope is valid,
other method calls may have succeeded, and the caller needs to inspect
each result individually.

**Decision D3.1: Layer 3 owns serialisation of Layer 3–defined types.**
`toJson`/`fromJson` for standard method request/response types live in
Layer 3's `methods.nim`, not Layer 2. Rationale: the types are generic
over entity type `T`; their serialisation depends on entity-specific
resolution (e.g., `methodNamespace(T)`, `capabilityUri(T)`,
`filterType(T)`) that only Layer 3 has. Layer 3 imports Layer 2's
infrastructure (`parseError`, `checkJsonKind`, `collectExtras`,
primitive `toJson`/`fromJson` pairs) but defines its own type-specific
serialisation.

**Compiler flags.** These constrain every type and function definition
(from `jmap_client.nimble` and `config.nims`):

```
--mm:arc
--experimental:strictDefs
--panics:on
--styleCheck:error
--floatChecks:on
--overflowChecks:on
```

`{.push raises: [].}` on every Layer 3 source module — the compiler
enforces that no `CatchableError` can escape any function.

---

## Standard Library Utilisation

Layer 3 maximises use of the Nim standard library.

### Modules used in Layer 3

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/json` | `newJObject`, `newJArray`, `%`, `%*`, `{}` accessor, `[]` accessor, `getStr`, `getBiggestInt`, `getBool`, `getFloat`, `getElems`, `pairs`, `hasKey`, `JsonNodeKind` | Same set as Layer 2. `{}` is the nil-safe accessor (returns nil, no `KeyError`). `[]` used for required fields where `KeyError` on absence is acceptable. |
| `std/tables` | `Table`, `initTable`, `pairs`, `[]=`, `hasKey`, `len`, `del` | `SetResponse` merging, `SetRequest`/`CopyRequest` create maps |
| `std/hashes` | `Hash`, `hash` | `ResponseHandle[T]` hash delegation |

**nim-results** (external dependency) provides `Result[T, E]`, `Opt[T]`,
and the `?` operator. `Opt[T]` is used for all optional fields — not
`std/options`. `Opt[T]` is `Result[T, void]`, sharing the full Result
API (`?`, `valueOr:`, `map`, `flatMap`, iterators).

### Modules evaluated and rejected

| Module | Reason not used in Layer 3 |
|--------|---------------------------|
| `std/options` | Replaced by nim-results `Opt[T]`. `Opt[T]` shares the `Result` API (`?` operator, `valueOr:`, iterators), avoiding a parallel API surface. |
| `std/sugar` | `collect` is used in Layer 1/Layer 2 but not needed in Layer 3. Explicit `for` loops are clearer for the accumulation patterns in `fromJson` and merging helpers. |
| `std/sequtils` | `allIt`/`anyIt` not needed — Layer 3 does not require predicate checks over collections. |
| `std/jsonutils` | Uses exceptions internally. Same rejection as Layer 2. |
| `std/atomics` | No concurrency requirement in Layer 3. |

---

## 1. Call ID Generation

**Architecture decision:** 3.2A (auto-incrementing counter)

**RFC reference:** §3.2 (lines 865–881) — the method call id is "an
arbitrary string from the client to be echoed back with the responses
emitted by that method call".

The counter is a field on `RequestBuilder`. Format: `"c0"`, `"c1"`,
etc. The `"c"` prefix guarantees the string is non-empty and free of
control characters, satisfying `MethodCallId` invariants without
requiring validation.

**Decision D3.9:** `MethodCallId(s)` uses the distinct constructor
directly (bypassing `parseMethodCallId`) because the generated format is
provably valid: the builder controls the format entirely, the `"c"` prefix
ensures non-empty, and `$int` produces only ASCII digit characters.

---

## 2. RequestBuilder Type

**Architecture decision:** 3.3B (builder with method-specific
sub-builders)

**RFC reference:** §3.3 (lines 882–945) — the Request object with
`using`, `methodCalls`, and optional `createdIds`.

### 2.1 Type Definition

```nim
type RequestBuilder* = object
  ## Accumulates method calls and capabilities for constructing a JMAP
  ## Request (RFC 8620 §3.3). All fields are private — the builder is the
  ## sole construction and mutation path. The counter is builder-local;
  ## call IDs are scoped to a single request.
  nextCallId: int                 ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation]    ## accumulated method calls
  capabilityUris: seq[string]     ## deduplicated capability URIs
```

Fields are private (no `*` export marker). The builder is the sole
construction path — callers cannot bypass the builder to construct
malformed requests.

### 2.2 Constructor

```nim
func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations,
  ## and no capabilities.
  RequestBuilder(nextCallId: 0, invocations: @[], capabilityUris: @[])
```

### 2.3 Read-Only Accessors

```nim
func methodCallCount*(b: RequestBuilder): int =
  ## Number of method calls accumulated so far.

func isEmpty*(b: RequestBuilder): bool =
  ## True if no method calls have been added.

func capabilities*(b: RequestBuilder): seq[string] =
  ## Snapshot of the deduplicated capability URIs registered so far.
```

### 2.4 Build

```nim
func build*(b: RequestBuilder): Request =
  ## Pure snapshot of the current builder state as a Request. Does not
  ## mutate the builder — the builder may continue to accumulate
  ## invocations via ``add*`` after a call to ``build()``, and a
  ## subsequent ``build()`` will capture the updated state. The builder's
  ## capabilityUris become the Request's ``using`` array. The builder's
  ## invocations become the Request's ``methodCalls``. createdIds is
  ## none — proxy splitting is a Layer 4 concern.
  ##
  ## RFC reference: §3.3 (lines 882–945)
  Request(using: b.capabilityUris, methodCalls: b.invocations,
          createdIds: Opt.none(Table[CreationId, Id]))
```

### 2.5 Capability Deduplication

```nim
func addCapability(b: var RequestBuilder, cap: string) =
  ## Adds a capability URI to the builder if not already present.
  if cap notin b.capabilityUris:
    b.capabilityUris.add(cap)
```

### 2.6 Internal Invocation Helper

```nim
func addInvocation(b: var RequestBuilder, name: string,
    args: JsonNode, capability: string): MethodCallId =
  ## Constructs an Invocation from the given method name and arguments,
  ## adds it to the builder, registers the capability, and returns the
  ## generated call ID. Uses ``initInvocationUnchecked`` because
  ## builder-generated method names (``methodNamespace(T) & "/get"``)
  ## and auto-generated call IDs (``"c0"``, ``"c1"``) are provably
  ## valid — the builder controls both entirely, so validation would
  ## be redundant.
  let callId = b.nextId()
  let inv = initInvocationUnchecked(name, args, callId)
  b.invocations.add(inv)
  b.addCapability(capability)
  callId
```

### 2.7 DRY Template

```nim
template addMethodImpl(b: var RequestBuilder, T: typedesc, suffix: string,
                      req: typed, RespType: typedesc): untyped =
  ## Shared boilerplate for non-query add* functions: mixin resolution,
  ## toJson serialisation, invocation accumulation, handle wrapping.
  mixin methodNamespace, capabilityUri
  let args = req.toJson()
  let callId =
    addInvocation(b, methodNamespace(T) & "/" & suffix, args, capabilityUri(T))
  ResponseHandle[RespType](callId)
```

All non-query `add*` functions delegate to `addMethodImpl`, which
handles `mixin` resolution, serialisation, invocation accumulation, and
`ResponseHandle` wrapping in a single template expansion.

### 2.8 The `add*` Method Signatures

The six standard method `add*` functions (§2.8.2–2.8.7) follow an
identical algorithmic pattern:

1. Construct arguments `JsonNode` via the request type's `toJson`.
2. Call `addInvocation` with `methodNamespace(T) & "/suffix"` and
   `capabilityUri(T)`.
3. Return `ResponseHandle[ResponseType](callId)`.

`addEcho` (§2.8.1) is a special case: it takes a raw `JsonNode`
argument, uses literal strings for method name and capability, is not
generic over `T`, and returns `ResponseHandle[JsonNode]`.

**Decision D3.2:** `add*` parameters match RFC request fields. Required
RFC fields are positional; optional fields are keyword-defaulted with
`Opt.none(T)` or the RFC-specified default value.

**`var` parameter semantics.** All `add*` functions take
`b: var RequestBuilder`. The builder's `seq[Invocation]` and
`seq[string]` fields are value types — `.add()` on them is permitted
when the parameter is `var`.

**`func` vs `proc`.** Non-query `add*` functions use `func` (pure,
no side effects). Query methods (`addQuery`, `addQueryChanges`) must
use `proc` because they accept a `proc` callback parameter — hidden
pointer indirection prevents `func`.

**Return type.** Each `add*` returns `ResponseHandle[ResponseType]` where
`ResponseType` is the method's response type (e.g., `GetResponse[T]` for
`addGet`). The handle wraps the generated `MethodCallId` and carries the
response type as a phantom parameter.

**2.8.1 addEcho**

```nim
func addEcho*(b: var RequestBuilder, args: JsonNode): ResponseHandle[JsonNode] =
  ## Adds a Core/echo invocation (RFC 8620 §4, lines 1540–1561).
  ## Returns a handle for extracting the echo response.
  ## Capability: "urn:ietf:params:jmap:core".
  let callId = b.addInvocation("Core/echo", args, "urn:ietf:params:jmap:core")
  ResponseHandle[JsonNode](callId)
```

**2.8.2 addGet**

```nim
func addGet*[T](b: var RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): ResponseHandle[GetResponse[T]] =
  ## Adds a Foo/get invocation.
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  addMethodImpl(b, T, "get", req, GetResponse[T])
```

**2.8.3 addChanges**

```nim
func addChanges*[T](b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): ResponseHandle[ChangesResponse[T]] =
  let req = ChangesRequest[T](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges)
  addMethodImpl(b, T, "changes", req, ChangesResponse[T])
```

**2.8.4 addSet**

```nim
func addSet*[T](b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, JsonNode]] = Opt.none(Table[CreationId, JsonNode]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): ResponseHandle[SetResponse[T]] =
  let req = SetRequest[T](accountId: accountId, ifInState: ifInState,
    create: create, update: update, destroy: destroy)
  addMethodImpl(b, T, "set", req, SetResponse[T])
```

**2.8.5 addCopy**

```nim
func addCopy*[T](b: var RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, JsonNode],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    onSuccessDestroyOriginal: bool = false,
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState),
): ResponseHandle[CopyResponse[T]] =
  let req = CopyRequest[T](fromAccountId: fromAccountId,
    ifFromInState: ifFromInState, accountId: accountId,
    ifInState: ifInState, create: create,
    onSuccessDestroyOriginal: onSuccessDestroyOriginal,
    destroyFromIfInState: destroyFromIfInState)
  addMethodImpl(b, T, "copy", req, CopyResponse[T])
```

**2.8.6 addQuery**

```nim
proc addQuery*[T, C](b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson: proc(c: C): JsonNode
        {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    position: JmapInt = JmapInt(0),
    anchor: Opt[Id] = Opt.none(Id),
    anchorOffset: JmapInt = JmapInt(0),
    limit: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    calculateTotal: bool = false,
): ResponseHandle[QueryResponse[T]] =
  ## Must be ``proc`` (not ``func``) because ``filterConditionToJson``
  ## is a ``proc`` callback parameter.
  mixin methodNamespace, capabilityUri
  let req = QueryRequest[T, C](accountId: accountId, filter: filter,
    sort: sort, position: position, anchor: anchor,
    anchorOffset: anchorOffset, limit: limit,
    calculateTotal: calculateTotal)
  let args = req.toJson(filterConditionToJson)
  let callId = addInvocation(b, methodNamespace(T) & "/query", args,
    capabilityUri(T))
  ResponseHandle[QueryResponse[T]](callId)
```

**2.8.7 addQueryChanges**

```nim
proc addQueryChanges*[T, C](b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson: proc(c: C): JsonNode
        {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): ResponseHandle[QueryChangesResponse[T]] =
  mixin methodNamespace, capabilityUri
  let req = QueryChangesRequest[T, C](accountId: accountId, filter: filter,
    sort: sort, sinceQueryState: sinceQueryState, maxChanges: maxChanges,
    upToId: upToId, calculateTotal: calculateTotal)
  let args = req.toJson(filterConditionToJson)
  let callId = addInvocation(b, methodNamespace(T) & "/queryChanges", args,
    capabilityUri(T))
  ResponseHandle[QueryChangesResponse[T]](callId)
```

**Decision D3.5:** See §6.7 for the full statement and rationale
(Referencable field selection).

**Decision D3.6:** See §6.7 for the full statement and rationale
(JsonNode entity data).

### 2.9 Single-Type-Parameter Query Overloads

The two-parameter `addQuery[T, C]` proc allows `C != filterType(T)`,
which compiles but produces semantically wrong JSON. Template overloads
resolve this at the call site:

```nim
template addQuery*[T](b: var RequestBuilder, accountId: AccountId,
): ResponseHandle[QueryResponse[T]] =
  ## Resolves filter type and callback via template expansion at call site.
  ## Calls two-parameter addQuery[T, C] with:
  ##   C = filterType(T)
  ##   callback = filterConditionToJson(c: filterType(T)): JsonNode
  ## Makes the illegal state unrepresentable: C must == filterType(T).
  addQuery[T, filterType(T)](b, accountId,
    proc(c: filterType(T)): JsonNode {.noSideEffect, raises: [].} =
      filterConditionToJson(c))

template addQueryChanges*[T](b: var RequestBuilder, accountId: AccountId,
    sinceQueryState: JmapState,
): ResponseHandle[QueryChangesResponse[T]] =
  ## Same resolution pattern as addQuery[T].
  addQueryChanges[T, filterType(T)](b, accountId, sinceQueryState,
    proc(c: filterType(T)): JsonNode {.noSideEffect, raises: [].} =
      filterConditionToJson(c))
```

These are templates (not procs) because `filterType(T)` must appear in
type positions resolved at the call site. Nim's `mixin` only affects
the function body, not the parameter signature. Templates expand at the
call site where `filterType` is visible, avoiding this limitation.

### 2.10 Argument Construction Helpers

Convenience functions reduce `Opt.some`/`direct` nesting at call sites:

```nim
func directIds*(ids: openArray[Id]): Opt[Referencable[seq[Id]]] =
  ## Wraps: Opt.some(direct(@ids))
  ## Before: addGet[T](b, acctId, ids = Opt.some(direct(@[id1, id2])))
  ## After:  addGet[T](b, acctId, ids = directIds(@[id1, id2]))
  Opt.some(direct(@ids))

func initCreates*(pairs: openArray[(CreationId, JsonNode)]
): Opt[Table[CreationId, JsonNode]] =
  ## Builds Opt-wrapped create table from CreationId/JsonNode pairs.

func initUpdates*(pairs: openArray[(Id, PatchObject)]
): Opt[Table[Id, PatchObject]] =
  ## Builds Opt-wrapped update table from Id/PatchObject pairs.
```

**Module:** `builder.nim`

---

## 3. ResponseHandle[T] and Response Dispatch

**Architecture decision:** 3.4C (phantom-typed response handles)

**RFC reference:** §3.4 (lines 975–1035) — the Response object with
`methodResponses`, `createdIds`, and `sessionState`.

### 3.1 Type Definition

```nim
type ResponseHandle*[T] = distinct MethodCallId
  ## Phantom-typed handle tying a method call ID to its expected response
  ## type ``T`` (RFC 8620 §3.2, §3.4). The type parameter ``T`` is unused
  ## at runtime (phantom) — it exists solely to enforce type-safe
  ## extraction at compile time.
```

`T` is phantom. The handle carries no runtime representation of the
response type — it is a `MethodCallId` at runtime and a typed token at
compile time.

Operations (explicitly defined, not borrowed, due to phantom type):

```nim
func `==`*[T](a, b: ResponseHandle[T]): bool
func `$`*[T](a: ResponseHandle[T]): string
func hash*[T](a: ResponseHandle[T]): Hash
func callId*[T](handle: ResponseHandle[T]): MethodCallId
```

### 3.2 Two-Level Railway Composition

```
Track 1 (Outer): JmapResult[Response] = Result[Response, ClientError]
                 (transport/request errors)
                   ↓
Track 2 (Inner): Result[T, MethodError]
                 (per-invocation errors)
```

These railways are **intentionally separate** — transport failures and
method errors require fundamentally different recovery actions.

### 3.3 Track 0 → Track 2 Bridge

```nim
func validationToMethodError*(ve: ValidationError): MethodError =
  ## Lossless conversion from the construction railway (Track 0) to the
  ## per-invocation railway (Track 2). Preserves the full ValidationError
  ## structure in MethodError.extras as structured JSON so no diagnostic
  ## information is lost.
  let extras = %*{"typeName": ve.typeName, "value": ve.value}
  methodError(rawType = "serverFail",
    description = Opt.some(ve.message),
    extras = Opt.some(extras))
```

### 3.4 Extraction Functions

**3.4.0 Internal `extractInvocation` helper**

The shared extraction logic — scanning `methodResponses`, detecting
missing invocations, and detecting method errors — is factored into an
internal helper. Both `get[T]` overloads delegate to it, keeping the
public API as two-line functions that compose `extractInvocation` with
type-specific parsing.

```nim
func extractInvocation(resp: Response, targetId: MethodCallId
): Result[Invocation, MethodError] =
  ## Finds and validates an invocation: returns the invocation for normal
  ## responses, or an appropriate MethodError for missing/error responses.
  ##
  ## Algorithm:
  ## 1. Scan methodResponses for invocation matching targetId.
  ## 2. Not found → err(serverFail).
  ## 3. If name == "error" → parse as MethodError, return err.
  ##    Malformed error → err(serverFail).
  ## 4. Otherwise → return ok(invocation).
  let matchOpt = findInvocation(resp, targetId)
  if matchOpt.isNone:
    return err(methodError(rawType = "serverFail",
      description = Opt.some("no response for call ID " & $targetId)))
  let inv = matchOpt.get()
  if inv.name == "error":
    let meResult = MethodError.fromJson(inv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    return err(methodError(rawType = "serverFail",
      description = Opt.some("malformed error response for call ID " & $targetId)))
  ok(inv)
```

**3.4.1 Default extraction via `mixin fromJson`**

```nim
proc get*[T](resp: Response, handle: ResponseHandle[T]
): Result[T, MethodError] =
  ## Extracts a typed response from the Response envelope using ``mixin
  ## fromJson`` to resolve ``T.fromJson`` at the caller's scope.
  ## Delegates to ``extractInvocation`` for scanning and error detection,
  ## then applies ``T.fromJson`` to the arguments. Validation failures
  ## are converted to MethodError via ``mapErr(validationToMethodError)``.
  mixin fromJson
  let inv = ?extractInvocation(resp, callId(handle))
  T.fromJson(inv.arguments).mapErr(validationToMethodError)
```

**3.4.2 Callback overload (escape hatch)**

```nim
proc get*[T](resp: Response, handle: ResponseHandle[T],
    fromArgs: proc(node: JsonNode): Result[T, ValidationError]
        {.noSideEffect, raises: [].},
): Result[T, MethodError] =
  ## Same structure but uses caller-supplied callback instead of mixin.
  ## For custom parsing where T.fromJson is not discoverable via mixin
  ## (e.g., entity-specific extractors, JsonNode for Core/echo).
  let inv = ?extractInvocation(resp, callId(handle))
  fromArgs(inv.arguments).mapErr(validationToMethodError)
```

Both overloads share the same structure: delegate to `extractInvocation`
for invocation lookup and error detection, then apply a parsing function
to the arguments. The `mapErr(validationToMethodError)` combinator
converts Track 0 (`ValidationError`) to Track 2 (`MethodError`)
idiomatically without explicit `isOk`/`isErr` branching.

**Decision D3.3:** The extraction function returns `Result[T, MethodError]`.
Method errors are data within a successful HTTP response — per-invocation,
not per-request. The outer railway (`JmapResult` / `ClientError`) is
reserved for transport and request-level failures at the Layer 4 boundary.

**Error detection heuristic (step 3).** The RFC specifies that method-
level errors use the response name `"error"` (§3.6.2 lines 1148–1154):
`["error", {"type": "unknownMethod"}, "call-id"]`. The dispatch function
checks `matchedInv.name == "error"` rather than inspecting the arguments
for a `"type"` key. Rationale: the RFC mandates the `"error"` name for
all method-level errors. Checking the name is both simpler and more
reliable than heuristic argument inspection. A response named `"error"`
that does not parse as `MethodError` is treated as `serverFail` — this
handles malformed error responses without losing the error signal.

**Railway conversion (Track 0 → Track 2).** When `T.fromJson` returns
`err(ValidationError)`, `get[T]` converts it to `err(MethodError)` via
`validationToMethodError`. The conversion is lossless — the full
`ValidationError` structure (including `typeName` and `value`) is
preserved as structured JSON in `MethodError.extras`, not flattened to a
description string.

**Cross-request safety gap.** Call IDs repeat across requests (`"c0"` in
every request). A handle from Request A used with Response B silently
extracts the wrong invocation. No type-level mitigation is possible in
Nim without encoding the request identity in the type system (which would
add complexity disproportionate to the risk). Convention: use handles
immediately within the scope where the request was built. This gap is
documented in the `ResponseHandle` doc comment.

**Known limitation: implicit responses.** RFC 8620 §3.2 (line 878)
states that a method "may return 1 or more responses" with the same
call ID. The canonical case is `/copy` with
`onSuccessDestroyOriginal = true`, which emits both a `Foo/copy`
response and an implicit `Foo/set` response. The current
`findInvocation` returns only the first match — the implicit `/set`
response is not extractable. A `getImplicitSet[T]` function
(deferred decision R8) will address this when RFC 8621 entity modules
are implemented.

### 3.5 End-to-End Example

Self-contained walkthrough using a minimal `Widget` entity. Covers entity
registration, request building, `build()`, response dispatch, and error
handling across the railways.

```nim
## --- Entity definition (widget.nim) ---
type Widget* = object
  ## Minimal entity for illustration. Real entities live in RFC 8621 modules.

proc methodNamespace*(T: typedesc[Widget]): string = "Widget"
proc capabilityUri*(T: typedesc[Widget]): string = "urn:example:widgets"
registerJmapEntity(Widget)  # compile error if overloads are missing

## --- Request building ---
let accountId = parseAccountId("acc1").get()  # Result — .get() for brevity

var b = initRequestBuilder()
let gh = b.addGet[Widget](accountId)                        # Widget/get
let sh = b.addSet[Widget](accountId,                        # Widget/set
    destroy = Opt.some(direct(@[parseId("id7").get()])))
let req = b.build()
## req.using == @["urn:example:widgets"]
## req.methodCalls.len == 2
## req.methodCalls[0].name == "Widget/get"
## req.methodCalls[1].name == "Widget/set"

## --- Response dispatch (after Layer 4 transport, out of scope) ---
## Assume ``resp`` is a parsed Response from the server.

let getResult = resp.get(gh)            # Result[GetResponse[Widget], MethodError]
if getResult.isOk:
  let getVal = getResult.get()
  ## getVal.state, getVal.list, getVal.notFound are available.
  ## Individual Widget objects in getVal.list are raw JsonNode —
  ## entity-specific parsing is the caller's responsibility (D3.6).
  discard
else:
  let getErr = getResult.error()
  ## getErr.errorType: MethodErrorType (e.g., metUnknownMethod, metServerFail)
  ## getErr.description: Opt[string]
  discard

let setResult = resp.get(sh)            # Result[SetResponse[Widget], MethodError]
if setResult.isOk:
  let setVal = setResult.get()
  ## setVal.destroyResults: Table[Id, Result[void, SetError]]
  for id, res in setVal.destroyResults:
    if res.isErr:
      discard res.error()  # SetError with errorType, description
else:
  let setErr = setResult.error()
  ## setErr: MethodError — the entire /set call failed
  discard
```

**Key points illustrated:**

- **Entity registration** (§4): two `proc` overloads + `registerJmapEntity`.
- **Builder** (§2): `initRequestBuilder`, `addGet`, `addSet`, `build`.
- **Response dispatch** (§3): `get[T]` via `mixin fromJson`, returning
  `Result[T, MethodError]` on Track 2.
- **Three railways in action**:
  - `parseAccountId` and `parseId` return `Result[T, ValidationError]`
    (Track 0) if the input is invalid — caller never reaches the builder.
  - Layer 4 transport (not shown) returns `JmapResult[Response]`
    (Track 1) if the HTTP request fails — no `Response` to inspect.
  - `get[T]` returns `Result[T, MethodError]` (Track 2) if the server
    reported a per-invocation error — other calls in the batch are
    unaffected.
  - `SetResponse.destroyResults` contains `Result[void, SetError]`
    (within Track 2) — the `/set` call succeeded overall, but individual
    items may have failed.
- **Entity data as `JsonNode`** (Decision D3.6): `GetResponse.list`
  contains raw JSON; entity-specific parsing is a separate step.

**Module:** `dispatch.nim`

---

## 4. Entity Type Framework

**Architecture decisions:** 3.5B (plain overloads, no concepts), 3.7B
(overloaded type-level templates for associated types)

**Decision D3.4:** No concepts; plain overloaded `typedesc` procs with a
`registerJmapEntity` compile-time check template instead. Consistent with
architecture Decision 3.5B. Concepts are avoided due to: experimental
status, known compiler bugs (byref #16897, block scope issues, implicit
generic breakage), generic type checking unimplemented, and minimal
stdlib adoption (2 files). See `docs/design/notes/nim-concepts.md`.
Plain overloaded procs provide equivalent compile-time safety via a
registration template that verifies all required overloads exist.

### 4.1 Entity Interface — Required Overloads

Each entity type must provide these `typedesc` overloads:

```nim
## Required overloads for any JMAP entity type:

proc methodNamespace*(T: typedesc[Mailbox]): string = "Mailbox"
  ## Returns the entity name for method name construction.
  ## "Mailbox" produces "Mailbox/get", "Mailbox/set", etc.

proc capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
  ## Returns the capability URI for the ``using`` array.
```

### 4.2 Compile-Time Registration Template

The `registerJmapEntity` template verifies all required overloads exist at
the registration site (not at distant generic instantiation time). Missing
overloads produce domain-specific compile errors at the entity definition,
not cryptic "undeclared identifier" errors at `add*` call sites. The
template uses `when not compiles()` + `{.error:}` to name the entity type
and the exact missing overload signature in the error message.

```nim
template registerJmapEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides the required framework
  ## overloads (``methodNamespace`` and ``capabilityUri``). Call this
  ## once per entity type at module scope.
  static:
    when not compiles(methodNamespace(T)):
      {.error: "registerJmapEntity: " & $T &
        " is missing `proc methodNamespace*(T: typedesc[" & $T &
        "]): string`".}
    when not compiles(capabilityUri(T)):
      {.error: "registerJmapEntity: " & $T &
        " is missing `proc capabilityUri*(T: typedesc[" & $T &
        "]): string`".}
```

Usage:

```nim
type Mailbox* = object
  ## RFC 8621 Mailbox entity type.

proc methodNamespace*(T: typedesc[Mailbox]): string = "Mailbox"
proc capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
registerJmapEntity(Mailbox)  # compile error if any overload is missing
```

### 4.3 Generic `add*` Functions — Unconstrained `T`

```nim
func addGet*[T](b: var RequestBuilder, ...): ResponseHandle[GetResponse[T]]
```

No `: JmapEntity` constraint on `T`. If `T` lacks `methodNamespace` or
`capabilityUri`, the error appears when the `add*` body calls
`methodNamespace(T)`. The `registerJmapEntity` template catches this
earlier — at entity definition time rather than at call site — and
produces a domain-specific error message naming the missing overload.

### 4.4 `mixin` for Overload Resolution in Generic Bodies

```nim
func addGet*[T](b: var RequestBuilder, accountId: AccountId,
    ...): ResponseHandle[GetResponse[T]] =
  mixin methodNamespace, capabilityUri
  let name = methodNamespace(T) & "/get"
  let cap = capabilityUri(T)
  ...
```

`mixin` ensures the compiler searches the **caller's scope** for
`methodNamespace`/`capabilityUri` overloads, not just the module where
`addGet` is defined. Without `mixin`, the compiler would only see
overloads imported into `builder.nim`, which would require `builder.nim`
to import every entity module — breaking the import DAG and preventing
entity modules from being added independently.

### 4.5 Associated Type Templates

```nim
template filterType*(T: typedesc[Mailbox]): typedesc = MailboxFilterCondition
  ## Maps entity type to its filter condition type.
  ## Used in ``QueryRequest[T, C]`` and ``QueryChangesRequest[T, C]``
  ## where the filter field type is ``Filter[C]``.
```

Each entity module provides its own `filterType` overload. Core RFC 8620
defines no concrete entity types — only the framework. The `mixin
filterType` declaration in `addQuery` and `addQueryChanges` ensures the
caller's overload is found.

### 4.6 Queryable Entity Registration

`registerJmapEntity` does not check `filterType` because it is a
conditional overload — not all entity types support `/query`. For
queryable entities, a companion template provides the same
`when not compiles` + `{.error.}` pattern for both `filterType` and
`filterConditionToJson`:

```nim
template registerQueryableEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides ``filterType`` and
  ## ``filterConditionToJson`` in addition to the base framework overloads.
  ## Call after ``registerJmapEntity`` for entity types that support /query
  ## and /queryChanges. Produces domain-specific errors if either is missing.
  static:
    when not compiles(filterType(T)):
      {.error: "registerQueryableEntity: " & $T &
        " is missing `template filterType*(T: typedesc[" & $T &
        "]): typedesc`".}
    when not compiles(filterConditionToJson(default(filterType(T)))):
      {.error: "registerQueryableEntity: " & $T &
        " is missing `func filterConditionToJson*(c: " & $filterType(T) &
        "): JsonNode`".}
```

`filterConditionToJson` is the standardised name for the filter
serialisation callback. The single-type-parameter `addQuery[T]` overload
resolves it via `mixin`, eliminating the need to pass the callback
explicitly at every call site.

**Entity module checklist.** Every entity module must provide:

1. The entity type definition (e.g., `type Mailbox* = object`).
2. `proc methodNamespace*(T: typedesc[Entity]): string`.
3. `proc capabilityUri*(T: typedesc[Entity]): string`.
4. `template filterType*(T: typedesc[Entity]): typedesc` (if the entity
   supports `/query`).
5. `func filterConditionToJson*(c: filterType(Entity)): JsonNode` (if the
   entity supports `/query`). Must use this exact name for `mixin`
   resolution in `addQuery[T]`/`addQueryChanges[T]`.
6. `registerJmapEntity(Entity)` at module scope.
7. `registerQueryableEntity(Entity)` at module scope (if the entity
   supports `/query`).
8. `toJson`/`fromJson` for the entity type itself (for create maps and
   response lists).

Items 1–7 are Layer 3 concerns. Item 8 is entity-specific and lives in
the entity module alongside the type definition.

**Module:** `entity.nim`

---

## 5a. Serialisation Infrastructure for Layer 3 Types

Layer 3 reuses Layer 2's serialisation infrastructure but must document
its own patterns. Layer 3 types are generic over entity type `T`; their
serialisation involves entity-specific resolution that only Layer 3 has.

**Decision D3.7:** See §7.7 for the full statement and rationale
(unidirectional serialisation — request `toJson`, response `fromJson`).

### 5a.1 Pattern L3-A: Request `toJson` (Object Construction)

Build a `JsonNode` object. Omit keys for `none` fields. Use
`referencableKey` for `Referencable[T]` fields. Use
`Filter[C].toJson(filterConditionToJson)` for filter fields (callback
forwarded from the caller — see `addQuery`/`addQueryChanges` §2.8.6–
2.8.7).

Canonical example — `GetRequest[T].toJson`:

```nim
func toJson*[T](req: GetRequest[T]): JsonNode =
  ## Serialise GetRequest to JSON arguments object (RFC 8620 §5.1).
  ## Omits ``ids`` and ``properties`` when none.
  ## Dispatches Referencable ids via referencableKey.
  result = newJObject()
  result["accountId"] = req.accountId.toJson()
  for idsVal in req.ids:
    let idsKey = referencableKey("ids", idsVal)
    case idsVal.kind
    of rkDirect:
      var arr = newJArray()
      for id in idsVal.value:
        arr.add(id.toJson())
      result[idsKey] = arr
    of rkReference:
      result[idsKey] = idsVal.reference.toJson()
  for props in req.properties:
    var arr = newJArray()
    for p in props:
      arr.add(%p)
    result["properties"] = arr
```

**Pattern L3-A invariants:**

- Required fields are always emitted.
- `none` fields are omitted (key absent from the JSON object). Uses
  `for val in opt:` idiom for conditional consumption of `Opt[T]`.
- `Referencable[T]` fields emit `"fieldName"` for `rkDirect` and
  `"#fieldName"` for `rkReference`, using `referencableKey` from
  Layer 2's `serde_envelope.nim`. On the parse side, `fromJsonField`
  rejects requests containing both direct and referenced forms of the
  same field (RFC §3.7 conflict detection).
- Boolean fields with RFC defaults (`false`) are always emitted — the
  server treats absence as the default, but explicit emission is clearer
  and avoids ambiguity.

### 5a.2 Pattern L3-B: Response `fromJson` (Object Extraction)

Check `node.kind == JObject` via `checkJsonKind`. Extract each field via
`{}` accessor (nil-safe). Call Layer 1 smart constructors for identifier
fields — these return `Result[T, ValidationError]`, propagated via `?`.
Use `checkJsonKind` for structural validation of required fields (returns
`err(ValidationError)` on kind mismatch).

Canonical example — `GetResponse[T].fromJson`:

```nim
func fromJson*[T](R: typedesc[GetResponse[T]], node: JsonNode
): Result[GetResponse[T], ValidationError] =
  ## Deserialise JSON arguments to GetResponse (RFC 8620 §5.1).
  ## Uses lenient constructors for server-assigned identifiers.
  ## list contains raw JsonNode entities — entity-specific parsing
  ## is the caller's responsibility.
  discard $R
  ?checkJsonKind(node, JObject, "GetResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let state = ?parseJmapState(node{"state"}.getStr(""))
  let listNode = node{"list"}
  ?checkJsonKind(listNode, JArray, "GetResponse", "list must be array")
  let list = listNode.getElems(@[])
  let notFound = ?parseOptIdArray(node{"notFound"})
  ok(GetResponse[T](accountId: accountId, state: state, list: list,
                     notFound: notFound))
```

**Pattern L3-B invariants:**

- Root check: `?checkJsonKind(node, JObject, typeName)`.
- Required fields: extract via `{}`, validate kind, call smart
  constructor (returns `err` on invalid input, propagated via `?`).
- Server-assigned identifiers: use lenient constructors
  (`parseIdFromServer`, `parseAccountId`).
- Required `seq` fields: use `parseIdArray` (strict — checks `JArray`
  kind, iterates `getElems()`, validates each element via `?`).
- Supplementary `seq` fields (e.g., `notFound`): use `parseOptIdArray`
  (lenient — absent, null, or wrong kind produces empty `seq`).
- Optional fields (`Opt[T]`): absent, null, or wrong kind produces
  `Opt.none(T)` (lenient, per §5a.4).
- Return type: `Result[T, ValidationError]`. Error propagation via `?`.
- `discard $R` at the start forces generic instantiation (ensures the
  type parameter `T` is bound).

### 5a.3 Pattern L3-C: SetResponse Merging (Parallel Maps to Unified Result Tables)

The wire format (RFC 8620 §5.3, lines 2009–2082) uses parallel maps
(`created`/`notCreated`, `updated`/`notUpdated`, `destroyed`/
`notDestroyed`). The internal representation merges these into unified
`Result` tables (Decision 3.9B), where each key maps to either a success
value (`Result.ok`) or a `SetError` (`Result.err`).

The merging pattern is used by both `SetResponse[T].fromJson` and
`CopyResponse[T].fromJson`. The create-merging algorithm is shared via
`mergeCreateResults`.

**Merging type signatures:**

```nim
## Create: wire created (Id[Foo]|null) + notCreated (Id[SetError]|null)
##   → Result[Table[CreationId, Result[JsonNode, SetError]], ValidationError]
## Update: wire updated (Id[Foo|null]|null) + notUpdated (Id[SetError]|null)
##   → Result[Table[Id, Result[Opt[JsonNode], SetError]], ValidationError]
## Destroy: wire destroyed (Id[]|null) + notDestroyed (Id[SetError]|null)
##   → Result[Table[Id, Result[void, SetError]], ValidationError]
```

### 5a.4 Expected JSON Kinds per Response Type

The table below lists the expected JSON kind for each field. Two
distinct validation mechanisms are used (see §5a.5 for details):

- **Strict `checkJsonKind`:** explicit kind gate — wrong kind returns
  `err(ValidationError)`. Used for structurally critical fields (e.g.,
  `list: JArray`).
- **Smart constructor delegation:** `.getStr("")` feeds a smart
  constructor (e.g., `parseAccountId`) which returns
  `err(ValidationError)` on empty/invalid input. Used for required
  identifier fields (e.g., `accountId`, `state`).
- **Lenient:** absent, null, or wrong kind produces `none` or an
  empty default. Used for optional and supplementary fields.

| Response Type | Root check | Field-level expected kinds |
|---------------|------------|--------------------------|
| `GetResponse[T]` | `JObject` | `accountId`: `JString`; `state`: `JString`; `list`: `JArray`; `notFound`: `JArray` (lenient — absent treated as empty) |
| `ChangesResponse[T]` | `JObject` | `accountId`: `JString`; `oldState`/`newState`: `JString`; `hasMoreChanges`: `JBool`; `created`/`updated`/`destroyed`: `JArray` |
| `SetResponse[T]` | `JObject` | `accountId`: `JString`; `newState`: `JString`; `oldState`: lenient (absent/wrong kind produces `none`); parallel maps: `JObject` (lenient — null treated as empty) |
| `CopyResponse[T]` | `JObject` | Same structure as `SetResponse` for `created`/`notCreated` fields |
| `QueryResponse[T]` | `JObject` | `accountId`: `JString`; `queryState`: `JString`; `canCalculateChanges`: `JBool`; `position`: `JInt`; `ids`: `JArray`; `total`/`limit`: lenient (absent produces `none`) |
| `QueryChangesResponse[T]` | `JObject` | `accountId`: `JString`; `oldQueryState`/`newQueryState`: `JString`; `removed`: `JArray`; `added`: `JArray` |

### 5a.5 Opt[T] Leniency Policy

Based on Layer 2 §1.4b. Layer 2 scopes the lenient policy to simple
scalar `Opt` fields, with complex container `Opt` types (e.g.,
`Opt[Table[CreationId, Id]]`) retaining strict handling. Layer 3
generalises the lenient policy to all `Opt[T]` fields because Layer 3
response types contain only simple scalar or identifier `Opt` fields —
no complex container `Opt` types.

Client library parses server data — Postel's law applies. For optional
fields (`Opt[T]`), absent key, null value, or wrong JSON kind all
produce `Opt.none(T)`. For required fields, wrong kind returns
`err(ValidationError)`.

Rationale:

1. `Opt` fields are already optional — callers handle absence via
   `.isSome`/`.isNone` or `for val in opt:`.
2. Strictness on supplementary fields (like `description` on errors)
   risks losing the critical primary field.
3. "Absent" and "malformed" are equivalent for optional data from a
   server.

**Lenient optional helpers.** Layer 3 provides internal helpers for
lenient extraction of optional fields:

```nim
func optState*(node: JsonNode, key: string): Opt[JmapState] =
  ## Lenient optional JmapState extraction.
  ## Absent, null, wrong kind, or invalid content all produce none.
  ## Uses ? on optJsonField and .optValue to bridge Result → Opt.
  parseJmapState((?optJsonField(node, key, JString)).getStr("")).optValue

func optUnsignedInt*(node: JsonNode, key: string): Opt[UnsignedInt] =
  ## Lenient optional UnsignedInt extraction.
  ## Absent, null, wrong kind, or invalid content all produce none.
  parseUnsignedInt((?optJsonField(node, key, JInt)).getBiggestInt(0)).optValue
```

These helpers use `?` on `optJsonField` (which returns `Opt[JsonNode]`)
for absent/null/wrong-kind, then `.optValue` on the smart constructor's
`Result` to convert validation failures to `none` — implementing the
lenient policy without exceptions.

**Exception — structurally critical required fields:** Required fields
that are structurally critical to the response (e.g., `list: seq[JsonNode]`
in `GetResponse`) use strict `checkJsonKind` — wrong kind returns
`err(ValidationError)`. A response without a `list` array is not a valid
`/get` response. Supplementary required fields (e.g.,
`notFound: seq[Id]` in `GetResponse`) are treated leniently — absent or
wrong kind produces an empty default (e.g., empty `seq`) rather than
returning an error.

### 5a.6 Serialisation Pair Inventory

Every Layer 3 type and its serialisation direction.

| Type | Direction | Notes |
|------|-----------|-------|
| `GetRequest[T]` | `toJson` only | `Referencable` ids uses `referencableKey` |
| `GetResponse[T]` | `fromJson` only | Returns `Result[GetResponse[T], ValidationError]` |
| `ChangesRequest[T]` | `toJson` only | Simplest request — only 3 fields |
| `ChangesResponse[T]` | `fromJson` only | Returns `Result[ChangesResponse[T], ValidationError]` |
| `SetRequest[T]` | `toJson` only | `Referencable` destroy uses `referencableKey` |
| `SetResponse[T]` | `fromJson` only | Merging algorithm Pattern L3-C |
| `CopyRequest[T]` | `toJson` only | Required `create` map (not `Opt`) |
| `CopyResponse[T]` | `fromJson` only | Same merging as `SetResponse` (create branch only) |
| `QueryRequest[T, C]` | `toJson` only | Generic `Filter[C]` uses `filterConditionToJson` callback |
| `QueryResponse[T]` | `fromJson` only | `total`/`limit` lenient |
| `QueryChangesRequest[T, C]` | `toJson` only | `Filter[C]` `filterConditionToJson` callback same as `QueryRequest` |
| `QueryChangesResponse[T]` | `fromJson` only | `total` lenient |

### 5a.7 Layer 2 Infrastructure Imports

Layer 3's `methods.nim` imports the following from Layer 2 via the
`serialisation` re-export hub:

| Import | Source | Used for |
|--------|--------|----------|
| `parseError` | `serde.nim` | Constructing `ValidationError` in `fromJson` |
| `checkJsonKind` | `serde.nim` | Kind validation — returns `err(ValidationError)` on mismatch |
| `optJsonField` | `serde.nim` | Lenient extraction of optional JSON fields |
| `parseIdArray` | `serde.nim` | Strict extraction of required `seq[Id]` fields (e.g., `ChangesResponse.created`) |
| `parseOptIdArray` | `serde.nim` | Lenient extraction of supplementary `seq[Id]` fields (e.g., `GetResponse.notFound` — absent/null/wrong-kind produces empty seq) |
| `collectExtras` (transitive) | `serde.nim` | Called internally by `SetError.fromJson` and `MethodError.fromJson` (Layer 2 error parsers) during SetResponse merging and dispatch error detection |
| `toJson` (all primitive/id types) | `serde.nim` | Serialising `AccountId`, `Id`, `JmapState`, etc. in request `toJson` |
| `fromJson` (all primitive/id types) | `serde.nim` | Deserialising server-assigned identifiers in response `fromJson` |
| `referencableKey` | `serde_envelope.nim` | Determining JSON key for `Referencable[T]` fields (`"foo"` vs `"#foo"`) |
| `fromJsonField` | `serde_envelope.nim` | Parsing `Referencable[T]` fields from JSON with `#`-prefix dispatch and RFC §3.7 conflict detection |
| `toJson` (envelope types) | `serde_envelope.nim` | `Invocation.toJson`, `ResultReference.toJson` |
| `fromJson` (envelope types) | `serde_envelope.nim` | `MethodError.fromJson` for error detection in dispatch |

**Module:** `methods.nim`

---

## 5b. Per-Method Errors and Behavioural Semantics

Each standard method can return method-level errors. These are already
defined as `MethodErrorType` variants in Layer 1 `errors.nim`
(`src/jmap_client/errors.nim`). `MethodError` is a plain object (not an
exception) — it is data within a successful JMAP response.

### 5b.1 General Method-Level Errors

**RFC reference:** §3.6.2 (lines 1137–1219)

The following general errors may be returned for **any** method call.
They are defined as `MethodErrorType` variants in Layer 1 `errors.nim`.

| Error | `MethodErrorType` variant | Description | RFC reference |
|-------|--------------------------|-------------|---------------|
| `serverUnavailable` | `metServerUnavailable` | Internal resource temporarily unavailable | §3.6.2 (lines 1165–1167) |
| `serverFail` | `metServerFail` | Unexpected error; no state changes made | §3.6.2 (lines 1169–1174) |
| `serverPartialFail` | `metServerPartialFail` | Partial changes; client must resync | §3.6.2 (lines 1183–1185) |
| `unknownMethod` | `metUnknownMethod` | Server does not recognise the method name | §3.6.2 (line 1187) |
| `invalidArguments` | `metInvalidArguments` | Wrong type or missing required argument | §3.6.2 (lines 1189–1193) |
| `invalidResultReference` | `metInvalidResultReference` | Result reference failed to resolve | §3.6.2 (lines 1195–1196) |
| `forbidden` | `metForbidden` | ACL or permissions violation | §3.6.2 (lines 1198–1200) |
| `accountNotFound` | `metAccountNotFound` | accountId does not correspond to valid account | §3.6.2 (lines 1202–1203) |
| `accountNotSupportedByMethod` | `metAccountNotSupportedByMethod` | Account valid but does not support this method/type | §3.6.2 (lines 1205–1207) |
| `accountReadOnly` | `metAccountReadOnly` | Account is read-only | §3.6.2 (lines 1209–1211) |

**Unknown error handling (§3.6.2 line 1217):** If the client receives an
error type it does not understand, it MUST treat it the same as
`serverFail`. This is already handled by Layer 1's `parseMethodErrorType`
which maps unknown type strings to `metUnknown`, and the `rawType` field
preserves the original string for diagnostic purposes (lossless
round-trip, Decision 1.7C).

### 5b.2 Per-Method Additional Errors

**RFC reference:** §5.1–5.6 — per-method additional errors.

The following table lists method-specific errors beyond the general set.

| Method | Method-Level Error | Trigger | RFC reference |
|--------|-------------------|---------|---------------|
| /get | `requestTooLarge` | Number of ids exceeds server maximum | §5.1 (lines 1660–1665) |
| /changes | `cannotCalculateChanges` | Server cannot compute delta from given state | §5.2 (lines 1826–1831) |
| /set | `requestTooLarge` | Total create+update+destroy exceeds server maximum | §5.3 (lines 2169–2171) |
| /set | `stateMismatch` | `ifInState` supplied and does not match current state | §5.3 (lines 2173–2174) |
| /copy | `fromAccountNotFound` | `fromAccountId` does not correspond to a valid account | §5.4 (lines 2328–2329) |
| /copy | `fromAccountNotSupportedByMethod` | `fromAccountId` valid but does not support this data type | §5.4 (lines 2331–2332) |
| /copy | `stateMismatch` | `ifInState` or `ifFromInState` does not match | §5.4 (lines 2335–2337) |
| /query | `anchorNotFound` | `anchor` supplied but not found in results | §5.5 (lines 2619–2620) |
| /query | `unsupportedSort` | Sort includes unsupported property or collation | §5.5 (lines 2622–2624) |
| /query | `unsupportedFilter` | Filter syntactically valid but server cannot process | §5.5 (lines 2626–2629) |
| /queryChanges | `tooManyChanges` | More changes than `maxChanges` argument | §5.6 (lines 2810–2813) |
| /queryChanges | `cannotCalculateChanges` | Server cannot compute delta from given queryState | §5.6 (lines 2815–2818) |

### 5b.3 SetError Types (Per-Item Errors)

**RFC reference:** §5.3 (lines 2084–2164) — SetError object and defined
types; §5.4 (lines 2317–2323) — additional `alreadyExists` for /copy.

Per-item errors appear in `/set` and `/copy` responses within the
`notCreated`, `notUpdated`, and `notDestroyed` maps. These are already
defined as `SetErrorType` variants in Layer 1 `errors.nim`.

| SetError | Applies to | Variant-specific field | RFC reference |
|----------|------------|----------------------|---------------|
| `forbidden` | create, update, destroy | -- | §5.3 (line 2099) |
| `overQuota` | create, update | -- | §5.3 (lines 2102–2103) |
| `tooLarge` | create, update | -- | §5.3 (lines 2105–2107) |
| `rateLimit` | create | -- | §5.3 (lines 2109–2111) |
| `notFound` | update, destroy | -- | §5.3 (lines 2113–2114) |
| `invalidPatch` | update | -- | §5.3 (lines 2116–2117) |
| `willDestroy` | update | -- | §5.3 (lines 2119–2121) |
| `invalidProperties` | create, update | `properties: seq[string]` | §5.3 (lines 2135–2157) |
| `singleton` | create, destroy | -- | §5.3 (lines 2159–2160) |
| `alreadyExists` | copy | `existingId: Id` | §5.4 (lines 2320–2323) |

**Variant-specific fields in Layer 1.** The `SetError` type in
`src/jmap_client/errors.nim` is a case object with variant-specific fields
for `invalidProperties` (`properties: seq[string]`) and `alreadyExists`
(`existingId: Id`). All other variants use the `else: discard` branch.
The `rawType` field is always populated for lossless round-trip (Decision
1.7C), and the `extras` field preserves non-standard server fields.

**SetError constructors.** Layer 1 provides three constructors:

- `setError(rawType, ...)` — for non-variant-specific errors. Defensively
  maps `invalidProperties`/`alreadyExists` to `setUnknown` when
  variant-specific data is absent.
- `setErrorInvalidProperties(rawType, properties, ...)` — for the
  `invalidProperties` variant.
- `setErrorAlreadyExists(rawType, existingId, ...)` — for the
  `alreadyExists` variant.

### 5b.4 Behavioural Semantics

The following behavioural rules are documented as `##` doc comments on
the relevant request/response types. They constrain client-side
expectations and are tested via the compliance test suite.

**§3.5 Omitting Arguments (lines 1037–1048).** An argument with a default
value may be omitted by the client. The server treats omitted arguments
the same as if the default value had been specified. `null` is the default
for any argument where allowed by the type signature, unless otherwise
specified.

**§3.3 Concurrency (lines 903–906).** Method calls within a single
request are processed sequentially, in order. Concurrent requests may
interleave. The builder's sequential `add*` order maps directly to server
execution order.

**§5.1 /get (lines 1587–1665).**

- The `id` property is always returned even if not in `properties`
  (line 1608).
- Duplicate `ids` produce a single result — the server MUST only include
  an id once in either `list` or `notFound` (lines 1649–1651).
- If `ids` is null, all records of the type are returned (subject to
  `maxObjectsInGet` limit) (lines 1599–1602).
- `requestTooLarge` error when the number of ids exceeds the server's
  maximum (lines 1660–1665).

**§5.2 /changes (lines 1667–1838).**

- If a record has been created AND updated since the old state, the server
  SHOULD return the id only in `created` (lines 1748–1750).
- If a record has been created AND destroyed since the old state, the
  server SHOULD remove the id entirely (lines 1756–1759).
- `cannotCalculateChanges` error when the server cannot compute the delta
  (lines 1826–1831).
- `maxChanges` caps the total count across `created`, `updated`, and
  `destroyed` (lines 1761–1764). The server may return intermediate
  states with `hasMoreChanges: true`.

**§5.3 /set (lines 1855–2175).**

- Each create/update/destroy is atomic; the `/set` as a whole is NOT
  atomic (lines 1947–1952). The server MAY commit changes to some objects
  but not others.
- If a create, update, or destroy is rejected, the appropriate error is
  added to `notCreated`/`notUpdated`/`notDestroyed` and the server
  continues to the next operation (lines 1973–1976).
- Creation IDs use `#` prefix for forward references within the same
  request (lines 1984–1998). The `createdIds` map spans the entire
  request (not scoped by type) (lines 2000–2001).
- `requestTooLarge` when total operations exceed server maximum
  (lines 2169–2171).
- `stateMismatch` when `ifInState` does not match current state
  (lines 2173–2174).

**§5.4 /copy (lines 2191–2338).**

- `onSuccessDestroyOriginal = true` triggers an implicit `Foo/set` call
  after successful copies (lines 2257–2262). The implicit set response
  appears as a separate invocation in `methodResponses`. This is NOT
  atomic with the copy — the copy may succeed but the destroy may fail
  (lines 2196–2199).
- `destroyFromIfInState` is passed as `ifInState` to the implicit
  `Foo/set` call (lines 2264–2268).
- `fromAccountNotFound` when `fromAccountId` is invalid (line 2329).
- `fromAccountNotSupportedByMethod` when `fromAccountId` is valid but
  does not support this data type (lines 2331–2332).
- `alreadyExists` SetError with `existingId` field when the server
  forbids duplicates (lines 2320–2323).

**§5.5 /query (lines 2339–2638).**

- If `anchor` is supplied, `position` is IGNORED (lines 2534–2536).
- `anchorOffset` is added to the anchor's index; if the result is
  negative, it is clamped to 0 (lines 2528–2531).
- Negative `position` is added to total, clamped to 0
  (lines 2476–2479).
- If position >= total, `ids` is empty (not an error) (lines 2482–2484).
- Negative `limit` produces `invalidArguments` error (lines 2507–2509).
- `anchorNotFound` when anchor is not in results (lines 2619–2620).
- `unsupportedSort` when sort includes unsupported property or collation
  (lines 2622–2624).
- `unsupportedFilter` when the filter is syntactically valid but the
  server cannot process it (lines 2626–2629).

**§5.6 /queryChanges (lines 2639–2819).**

- `upToId` optimisation only applies when BOTH sort and filter are on
  immutable properties (lines 2674–2678). When sort/filter include
  mutable properties, the server MUST include all records whose mutable
  properties may have changed in the `removed` array, with their new
  positions in `added` (lines 2731–2735).
- Server applies changes via the splice algorithm: remove `removed` IDs,
  insert `added` items by index (lowest first), truncate/extend to new
  total (lines 2773–2796).
- `tooManyChanges` when changes exceed `maxChanges` (lines 2810–2813).
- `cannotCalculateChanges` when the server cannot compute the delta
  (lines 2815–2818).

**Module:** `methods.nim`

---

## 6. Standard Method Request Types

**RFC reference:** §5.1–5.6 (lines 1587–2819)

All six standard method request types are generic over entity type `T`.
Each type definition carries `##` doc comments on every field citing the
RFC section and line numbers. Each type receives a `toJson` func
following Pattern L3-A (Section 5a.1). No `fromJson` is provided —
request types are serialised by the client, never parsed (Decision D3.7).

### 6.1 GetRequest[T]

**RFC reference:** §5.1 (lines 1587–1612)

```nim
type GetRequest*[T] = object
  ## Request arguments for Foo/get (RFC 8620 §5.1).
  ## Fetches objects of type T by their identifiers, optionally returning
  ## only a subset of properties.

  accountId*: AccountId
    ## The identifier of the account to use.

  ids*: Opt[Referencable[seq[Id]]]
    ## The identifiers of the Foo objects to return. If none, all records
    ## of the data type are returned (subject to maxObjectsInGet).
    ## Referencable: may be a direct seq or a result reference to a
    ## previous call's output (e.g., /query ids).

  properties*: Opt[seq[string]]
    ## If supplied, only the listed properties are returned for each
    ## object. If none, all properties are returned. The "id" property
    ## is always returned even if not explicitly requested (line 1608).
```

### 6.2 ChangesRequest[T]

**RFC reference:** §5.2 (lines 1667–1703)

```nim
type ChangesRequest*[T] = object
  ## Request arguments for Foo/changes (RFC 8620 §5.2).
  ## Retrieves the list of identifiers for records that have changed
  ## (created, updated, or destroyed) since a given state.

  accountId*: AccountId
    ## The identifier of the account to use.

  sinceState*: JmapState
    ## The current state of the client, as returned in a previous
    ## Foo/get response.

  maxChanges*: Opt[MaxChanges]
    ## The maximum number of identifiers to return. Must be > 0 per RFC
    ## (enforced by the MaxChanges smart constructor).
```

### 6.3 SetRequest[T]

**RFC reference:** §5.3 (lines 1855–1945)

```nim
type SetRequest*[T] = object
  ## Request arguments for Foo/set (RFC 8620 §5.3).
  ## Creates, updates, and/or destroys records of type T in a single
  ## method call. Each operation is atomic; the method as a whole is
  ## NOT atomic (lines 1947–1952).

  accountId*: AccountId
    ## The identifier of the account to use.

  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state; otherwise the method
    ## is aborted with a "stateMismatch" error.

  create*: Opt[Table[CreationId, JsonNode]]
    ## A map of creation identifiers to entity data objects. Entity data
    ## is JsonNode because Layer 3 Core cannot know T's serialisation
    ## format (Decision D3.6).

  update*: Opt[Table[Id, PatchObject]]
    ## A map of record identifiers to PatchObject values representing
    ## the changes to apply.

  destroy*: Opt[Referencable[seq[Id]]]
    ## A list of identifiers for records to permanently delete.
    ## Referencable: may be a direct seq or a result reference.
```

### 6.4 CopyRequest[T]

**RFC reference:** §5.4 (lines 2191–2268)

```nim
type CopyRequest*[T] = object
  ## Request arguments for Foo/copy (RFC 8620 §5.4).
  ## Copies records from one account to another.

  fromAccountId*: AccountId
    ## The identifier of the account to copy records from.

  ifFromInState*: Opt[JmapState]
    ## If supplied, must match the current state of the from-account.

  accountId*: AccountId
    ## The identifier of the account to copy records to. Must differ
    ## from fromAccountId.

  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state of the destination
    ## account.

  create*: Table[CreationId, JsonNode]
    ## A map of creation identifiers to entity data objects. Required
    ## (not optional). Each Foo object MUST contain an "id" property
    ## referencing the record in the from-account.

  onSuccessDestroyOriginal*: bool
    ## If true, the server attempts to destroy the originals after
    ## successful copies via an implicit Foo/set call. The copy and
    ## destroy are NOT atomic.

  destroyFromIfInState*: Opt[JmapState]
    ## Passed as "ifInState" to the implicit Foo/set call when
    ## onSuccessDestroyOriginal is true.
```

### 6.5 QueryRequest[T, C]

**RFC reference:** §5.5 (lines 2339–2516)

```nim
type QueryRequest*[T, C] = object
  ## Request arguments for Foo/query (RFC 8620 §5.5).
  ## Searches, sorts, and windows the data type on the server, returning
  ## a list of identifiers matching the criteria. ``C`` is the filter
  ## condition type, resolved from ``filterType(T)`` by the builder.

  accountId*: AccountId
    ## The identifier of the account to use.

  filter*: Opt[Filter[C]]
    ## Determines the set of Foos returned. Generic over the filter
    ## condition type C (resolved from filterType(T) at the call site).

  sort*: Opt[seq[Comparator]]
    ## Sort criteria. If none or empty, sort order is server-dependent
    ## but must be stable between calls.

  position*: JmapInt
    ## The zero-based index of the first identifier to return. Default: 0.
    ## Negative values offset from the end. Ignored if anchor supplied.

  anchor*: Opt[Id]
    ## A Foo identifier. If supplied, position is ignored.

  anchorOffset*: JmapInt
    ## The index of the first result relative to the anchor's index.
    ## May be negative. Default: 0.

  limit*: Opt[UnsignedInt]
    ## The maximum number of results to return.

  calculateTotal*: bool
    ## Whether the client wishes to know the total number of results.
```

**Note on two generic parameters.** `QueryRequest[T, C]` takes two
type parameters: `T` (the entity type) and `C` (the filter condition
type). The original design used `Filter[filterType(T)]` with a single
parameter, but the implementation uses an explicit second parameter for
clarity and simpler generic instantiation. The builder resolves `C` from
`filterType(T)` (see §2.9 single-type-parameter overloads).

### 6.6 QueryChangesRequest[T, C]

**RFC reference:** §5.6 (lines 2639–2685)

```nim
type QueryChangesRequest*[T, C] = object
  ## Request arguments for Foo/queryChanges (RFC 8620 §5.6).
  ## Efficiently updates a cached query to match the new server state.
  ## ``C`` is the filter condition type, resolved from ``filterType(T)``
  ## by the builder.

  accountId*: AccountId
    ## The identifier of the account to use.

  filter*: Opt[Filter[C]]
    ## The filter argument that was used with the original Foo/query.

  sort*: Opt[seq[Comparator]]
    ## The sort argument that was used with the original Foo/query.

  sinceQueryState*: JmapState
    ## The current state of the query in the client.

  maxChanges*: Opt[MaxChanges]
    ## The maximum number of changes to return.

  upToId*: Opt[Id]
    ## The last (highest-index) identifier the client has cached.

  calculateTotal*: bool
    ## Whether the client wishes to know the total number of results.
```

### 6.7 Decisions

**Decision D3.5: Referencable fields.** Only `GetRequest.ids` and
`SetRequest.destroy` receive `Referencable[T]` wrapping. These are the
canonical result reference targets: `/ids` from a preceding query and
`/list/*/id` or `/updated` from a preceding get or changes call. All
other fields are direct values. Rationale: wrapping all fields in
`Referencable` is extremely verbose and rarely used. Users needing
uncommon references can construct `Request` manually via Layer 1 types.

**Decision D3.6: JsonNode entity data.** Entity data is represented as
`JsonNode` in create maps (`SetRequest.create`, `CopyRequest.create`) and
in response lists (`GetResponse.list`, `SetResponse.createResults`).
Layer 3 Core cannot know `T`'s serialisation format; entity-specific
modules (e.g., RFC 8621 mail types) provide concrete `fromJson`
implementations to convert raw `JsonNode` instances into typed entity
values, completing the parse-don't-validate pipeline.

**Module:** `methods.nim`

---

## 7. Standard Method Response Types

**RFC reference:** §5.1–5.6 (lines 1613–2819)

All six standard method response types are generic over entity type `T`.
Each type definition carries `##` doc comments on every field citing the
RFC section and line numbers. Each type receives a `fromJson` func
following Pattern L3-B (Section 5a.2). `fromJson` returns
`Result[T, ValidationError]`. No `toJson` is provided — response types
are parsed by the client, never serialised (Decision D3.7).

### 7.1 GetResponse[T]

**RFC reference:** §5.1 (lines 1613–1658)

```nim
type GetResponse*[T] = object
  ## Response arguments for Foo/get (RFC 8620 §5.1).
  ## Contains the requested objects and any identifiers not found.

  accountId*: AccountId
    ## The identifier of the account used for the call.

  state*: JmapState
    ## A string representing the state on the server for ALL data of
    ## this type in the account.

  list*: seq[JsonNode]
    ## The Foo objects requested. Raw JsonNode entities — entity-specific
    ## parsing is the caller's responsibility (Decision D3.6).

  notFound*: seq[Id]
    ## Identifiers passed to the method for records that do not exist.
```

### 7.2 ChangesResponse[T]

**RFC reference:** §5.2 (lines 1704–1764)

```nim
type ChangesResponse*[T] = object
  ## Response arguments for Foo/changes (RFC 8620 §5.2).
  ## Lists identifiers for records that have been created, updated, or
  ## destroyed since the given state.

  accountId*: AccountId
    ## The identifier of the account used for the call.

  oldState*: JmapState
    ## The "sinceState" argument echoed back.

  newState*: JmapState
    ## The state the client will be in after applying the changes.

  hasMoreChanges*: bool
    ## If true, the client may call Foo/changes again with newState
    ## to get further updates.

  created*: seq[Id]
    ## Identifiers for records created since the old state.

  updated*: seq[Id]
    ## Identifiers for records updated since the old state.

  destroyed*: seq[Id]
    ## Identifiers for records destroyed since the old state.
```

### 7.3 SetResponse[T]

**RFC reference:** §5.3 (lines 2009–2082)

```nim
type SetResponse*[T] = object
  ## Response arguments for Foo/set (RFC 8620 §5.3).
  ## Wire format uses parallel maps (created/notCreated, etc.); the
  ## internal representation merges these into unified Result maps
  ## (Decision 3.9B).

  accountId*: AccountId
    ## The identifier of the account used for the call.

  oldState*: Opt[JmapState]
    ## The state before making the requested changes, or none if the
    ## server does not know the previous state.

  newState*: JmapState
    ## The state that will now be returned by Foo/get.

  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged create outcomes. Wire ``created`` entries become
    ## ``Result.ok(entityJson)``; wire ``notCreated`` entries become
    ## ``Result.err(setError)``. Last-writer-wins on duplicate keys.

  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
    ## Merged update outcomes. Wire ``updated`` entries with null value
    ## become ``ok(Opt.none(JsonNode))``; non-null values become
    ## ``ok(Opt.some(entityJson))``. Wire ``notUpdated`` entries become
    ## ``Result.err(setError)``.

  destroyResults*: Table[Id, Result[void, SetError]]
    ## Merged destroy outcomes. Wire ``destroyed`` entries become
    ## ``Result.ok()``; wire ``notDestroyed`` entries become
    ## ``Result.err(setError)``.
```

**Decision 3.9B: Unified Result maps.** The wire format's parallel maps
(`created`/`notCreated`, etc.) are merged into unified
`Table[K, Result[V, SetError]]` maps. Each key maps to either a success
value (`Result.ok`) or a `SetError` (`Result.err`). This provides a
single point of lookup per identifier and composes naturally with
nim-results' `Result` combinators. The merging algorithm is described in
§8.

### 7.4 CopyResponse[T]

**RFC reference:** §5.4 (lines 2273–2323)

```nim
type CopyResponse*[T] = object
  ## Response arguments for Foo/copy (RFC 8620 §5.4).
  ## Structurally similar to SetResponse but only has create results.
  ## Uses unified Result maps (Decision 3.9B).

  fromAccountId*: AccountId
    ## The identifier of the account records were copied from.

  accountId*: AccountId
    ## The identifier of the account records were copied to.

  oldState*: Opt[JmapState]
    ## The state of the destination account before the copy.

  newState*: JmapState
    ## The state that will now be returned by Foo/get on the
    ## destination account.

  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged copy outcomes. Same merging semantics as SetResponse
    ## create branch (Decision 3.9B).
```

### 7.5 QueryResponse[T]

**RFC reference:** §5.5 (lines 2541–2614)

```nim
type QueryResponse*[T] = object
  ## Response arguments for Foo/query (RFC 8620 §5.5).
  ## Returns a windowed list of identifiers matching the query criteria.

  accountId*: AccountId
    ## The identifier of the account used for the call.

  queryState*: JmapState
    ## A string encoding the current state of the query on the server.

  canCalculateChanges*: bool
    ## True if the server supports calling Foo/queryChanges with these
    ## filter/sort parameters.

  position*: UnsignedInt
    ## The zero-based index of the first result in the ids array within
    ## the complete list of query results.

  ids*: seq[Id]
    ## The list of identifiers for each Foo in the query results.

  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request.

  limit*: Opt[UnsignedInt]
    ## The limit enforced by the server. Only returned if the server
    ## set a limit or used a different limit than requested.
```

### 7.6 QueryChangesResponse[T]

**RFC reference:** §5.6 (lines 2695–2796)

```nim
type QueryChangesResponse*[T] = object
  ## Response arguments for Foo/queryChanges (RFC 8620 §5.6).
  ## Allows a client to update a cached query to match the new server
  ## state via a splice algorithm.

  accountId*: AccountId
    ## The identifier of the account used for the call.

  oldQueryState*: JmapState
    ## The "sinceQueryState" argument echoed back.

  newQueryState*: JmapState
    ## The state the query will be in after applying the changes.

  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request.

  removed*: seq[Id]
    ## Identifiers for every Foo that was in the query results in the
    ## old state but is not in the new state.

  added*: seq[AddedItem]
    ## The identifier and index in the new query results for every Foo
    ## that has been added since the old state AND every Foo in the
    ## current results that was included in removed.
```

### 7.7 Decision

**Decision D3.7: Unidirectional serialisation.** Request types receive
`toJson` only; response types receive `fromJson` only. The client builds
requests (serialises to JSON) and parses responses (deserialises from
JSON) — never the reverse. This halves the serialisation surface and
avoids dead code. Round-trip testing uses the builder-build-parse chain
(build a request via the builder, serialise it, parse the server response),
not per-type `fromJson(toJson(x))`.

**Module:** `methods.nim`

---

## 8. SetResponse Merging Algorithm

**RFC reference:** §5.3 (lines 2009–2082) — the wire format uses six
parallel maps: `created`/`notCreated`, `updated`/`notUpdated`,
`destroyed`/`notDestroyed`. The internal representation merges these
into unified `Result` tables (Decision 3.9B).

### 8.1 Create Merging

Wire: `created: Id[Foo]|null` + `notCreated: Id[SetError]|null`
Internal: `Result[Table[CreationId, Result[JsonNode, SetError]], ValidationError]`

```nim
func mergeCreateResults(
    node: JsonNode
): Result[Table[CreationId, Result[JsonNode, SetError]], ValidationError] =
  ## Merge wire ``created``/``notCreated`` maps into a unified Result table
  ## (Decision 3.9B). Used by both SetResponse and CopyResponse.
  ## Last-writer-wins: if a key appears in both maps, the notCreated
  ## entry wins (failure map processed second, overwrites success entry).
  var tbl = initTable[CreationId, Result[JsonNode, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?parseCreationId(k)
      tbl[cid] = Result[JsonNode, SetError].ok(v)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?parseCreationId(k)
      let se = ?SetError.fromJson(v)
      tbl[cid] = Result[JsonNode, SetError].err(se)
  ok(tbl)
```

### 8.2 Update Merging

Wire: `updated: Id[Foo|null]|null` + `notUpdated: Id[SetError]|null`
Internal: `Result[Table[Id, Result[Opt[JsonNode], SetError]], ValidationError]`

```nim
func mergeUpdateResults(
    node: JsonNode
): Result[Table[Id, Result[Opt[JsonNode], SetError]], ValidationError] =
  ## Merge wire ``updated``/``notUpdated`` maps into a unified Result table
  ## (Decision 3.9B). Null value in ``updated`` means no server-set
  ## properties changed; non-null contains changed properties.
  var tbl = initTable[Id, Result[Opt[JsonNode], SetError]]()
  let updatedNode = node{"updated"}
  if not updatedNode.isNil and updatedNode.kind == JObject:
    for k, v in updatedNode.pairs:
      let id = ?parseIdFromServer(k)
      if v.isNil or v.kind == JNull:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.none(JsonNode))
      else:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.some(v))
  let notUpdatedNode = node{"notUpdated"}
  if not notUpdatedNode.isNil and notUpdatedNode.kind == JObject:
    for k, v in notUpdatedNode.pairs:
      let id = ?parseIdFromServer(k)
      let se = ?SetError.fromJson(v)
      tbl[id] = Result[Opt[JsonNode], SetError].err(se)
  ok(tbl)
```

The `Opt[JsonNode]` in the success branch encodes the RFC semantics:
`null` in the `updated` map means "no server-set properties changed"
(line 2050), while a non-null value contains the properties that changed
in a way not explicitly requested (lines 2048–2051).

### 8.3 Destroy Merging

Wire: `destroyed: Id[]|null` + `notDestroyed: Id[SetError]|null`
Internal: `Result[Table[Id, Result[void, SetError]], ValidationError]`

```nim
func mergeDestroyResults(
    node: JsonNode
): Result[Table[Id, Result[void, SetError]], ValidationError] =
  ## Merge wire ``destroyed``/``notDestroyed`` into a unified Result table
  ## (Decision 3.9B). ``destroyed`` is a flat array on the wire; each ID
  ## becomes ``Result.ok()``. ``notDestroyed`` entries become
  ## ``Result.err(setError)``. Last-writer-wins on duplicate keys.
  var tbl = initTable[Id, Result[void, SetError]]()
  let destroyedNode = node{"destroyed"}
  if not destroyedNode.isNil and destroyedNode.kind == JArray:
    for _, elem in destroyedNode.getElems(@[]):
      let id = ?parseIdFromServer(elem.getStr(""))
      tbl[id] = Result[void, SetError].ok()
  let notDestroyedNode = node{"notDestroyed"}
  if not notDestroyedNode.isNil and notDestroyedNode.kind == JObject:
    for k, v in notDestroyedNode.pairs:
      let id = ?parseIdFromServer(k)
      let se = ?SetError.fromJson(v)
      tbl[id] = Result[void, SetError].err(se)
  ok(tbl)
```

### 8.4 Invariants

- **Completeness:** Every identifier from both success and failure wire
  maps is present in the output table. No entries are dropped.
- **Last-writer-wins:** If an identifier appears in both the success and
  failure map (a server bug), the failure map's entry takes precedence.
  Failure maps are processed second; the `tbl[key] =` assignment
  overwrites any previous success entry. This is defensive — the
  RFC does not permit duplicates across the parallel maps, but robustness
  demands a defined behaviour.
- **SetError fidelity:** `SetError.fromJson` preserves `rawType` and
  `extras` for lossless round-trip (Decision 1.7C). Unknown error types
  map to `setUnknown` with `rawType` preservation.
- **CopyResponse reuse:** `CopyResponse.fromJson` uses the identical
  `mergeCreateResults` helper. Only the create branch is needed; update
  and destroy branches do not apply to /copy responses.
- **Error propagation:** The merging helpers return
  `Result[Table[...], ValidationError]`. `parseCreationId`,
  `parseIdFromServer`, and `SetError.fromJson` failures are propagated
  via `?` — a malformed key or SetError aborts the entire parse.

**Module:** `methods.nim` (inside `SetResponse.fromJson` and
`CopyResponse.fromJson`)

---

## 9. Core/echo Method

**RFC reference:** §4 (lines 1540–1561)

The `Core/echo` method returns exactly the same arguments as given. It is
used for testing connectivity to the JMAP API endpoint.

**Wire format example (RFC §4.1):**

```json
Request:  [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
Response: [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
```

The builder's `addEcho` (§2.8.1) returns `ResponseHandle[JsonNode]`.
Extraction uses the callback overload of `get[T]` (§3.4.2) with
a `fromArgs` that wraps the raw `JsonNode` in `Result.ok`.

---

## 10. Result Reference Construction

**Architecture decision:** 3.10A (string paths with constants, no
validation)

**RFC reference:** §3.7 (lines 1220–1493) — result references allow a
method call to refer to the output of a previous call's response within
the same request.

### 10.1 Path Constants

Already defined in Layer 1 `envelope.nim`:

| Constant | Value | Source |
|----------|-------|--------|
| `RefPathIds` | `"/ids"` | IDs from /query result |
| `RefPathListIds` | `"/list/*/id"` | IDs from /get result |
| `RefPathAddedIds` | `"/added/*/id"` | IDs from /queryChanges result |
| `RefPathCreated` | `"/created"` | Created IDs (array) from /changes or created map (object) from /set |
| `RefPathUpdated` | `"/updated"` | Updated IDs (array) from /changes or updated map (object) from /set |
| `RefPathUpdatedProperties` | `"/updatedProperties"` | From Mailbox/changes (RFC 8621 §2.2) |

### 10.2 Generic Reference Function

```nim
func reference*[T](handle: ResponseHandle[T], name: string, path: string
): ResultReference =
  ## Constructs a ResultReference from a handle (RFC 8620 §3.7).
  ## ``name`` is the expected response method name (Decision D3.10:
  ## explicit, not auto-derived from T). ``path`` is a JSON Pointer
  ## string with optional JMAP '*' wildcard.
  initResultReference(resultOf = callId(handle), name = name, path = path)
```

### 10.3 Type-Safe Reference Convenience Functions

These functions constrain the `ResponseHandle` type parameter to specific
response types, making illegal states unrepresentable. The compiler
rejects mismatched handles at compile time. Each auto-derives the
response method name from `methodNamespace(T)` via `mixin`.

```nim
func idsRef*[T](handle: ResponseHandle[QueryResponse[T]]
): Referencable[seq[Id]] =
  ## Reference to /ids from a /query response.

func listIdsRef*[T](handle: ResponseHandle[GetResponse[T]]
): Referencable[seq[Id]] =
  ## Reference to /list/*/id from a /get response.

func addedIdsRef*[T](handle: ResponseHandle[QueryChangesResponse[T]]
): Referencable[seq[Id]] =
  ## Reference to /added/*/id from a /queryChanges response.

func createdRef*[T](handle: ResponseHandle[ChangesResponse[T]]
): Referencable[seq[Id]] =
  ## Reference to /created from a /changes response.

func updatedRef*[T](handle: ResponseHandle[ChangesResponse[T]]
): Referencable[seq[Id]] =
  ## Reference to /updated from a /changes response.
```

**Decision D3.10:** The generic `reference()` function takes an explicit
`name` parameter. The convenience functions auto-derive the name from
`methodNamespace(T)` because each is constrained to a specific response
type where the method suffix is known. Different methods produce
different response names — the generic function does not assume.

**Module:** `dispatch.nim`

---

## 11. Pipeline Combinators (convenience.nim)

**Module:** `convenience.nim` — **NOT** re-exported by `protocol.nim`.
Users who want pipeline combinators must explicitly
`import jmap_client/convenience`. This physical separation keeps the
core API surface in `builder.nim` and `dispatch.nim` frozen while
providing opt-in ergonomics.

### 11.1 Query-then-Get Pipeline

The most common JMAP pattern: query for IDs, then fetch full objects.

```nim
type QueryGetHandles*[T] = object
  ## Paired phantom-typed handles from a query-then-get pipeline.
  query*: ResponseHandle[QueryResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

template addQueryThenGet*[T](b: var RequestBuilder, accountId: AccountId
): QueryGetHandles[T] =
  ## Adds Foo/query + Foo/get with automatic result reference wiring.
  ## The get's ``ids`` parameter references the query's ``/ids`` path.
  ##
  ## Implicit decisions:
  ## - Reference path is always /ids (RefPathIds)
  ## - Both calls use the same accountId (no cross-account)
  ## - No filter, sort, or properties constraints applied
  ## - Response method name derived from methodNamespace(T)
```

### 11.2 Changes-then-Get Pipeline

Sync pattern: fetch changed IDs, then get newly created records.

```nim
type ChangesGetHandles*[T] = object
  ## Paired phantom-typed handles from a changes-then-get pipeline.
  changes*: ResponseHandle[ChangesResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

func addChangesToGet*[T](b: var RequestBuilder,
    accountId: AccountId, sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): ChangesGetHandles[T] =
  ## Adds Foo/changes + Foo/get with automatic result reference from
  ## /created. The get fetches newly created records.
  ##
  ## Implicit decisions:
  ## - Reference path is /created (RefPathCreated) — only newly created
  ##   IDs are fetched. For updated IDs, use the core API with updatedRef.
  ## - Both calls use the same accountId
```

### 11.3 Paired Extraction

```nim
type QueryGetResults*[T] = object
  query*: QueryResponse[T]
  get*: GetResponse[T]

proc getBoth*[T](resp: Response, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], MethodError] =
  ## Extracts both query and get responses, failing on the first error.
  ## Composes with the ? operator for early return.

type ChangesGetResults*[T] = object
  changes*: ChangesResponse[T]
  get*: GetResponse[T]

proc getBoth*[T](resp: Response, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], MethodError] =
  ## Extracts both changes and get responses, failing on the first error.
```

---

## 12. Round-Trip Invariants

Layer 3 has unidirectional serialisation (request `toJson`, response
`fromJson`), so classical round-trip (`fromJson(toJson(x)) == x`) does
not apply per-type. Instead, the following invariants hold:

1. **Request identity.** For any `GetRequest[T]` value `r`, if a
   `fromJson` were added for testing, `GetRequest[T].fromJson(r.toJson()) == r`
   must hold. The same applies to all six request types.

2. **Builder identity.** `builder.build().toJson()` produces valid JMAP
   request JSON. Parsing it back via `Request.fromJson` (Layer 2)
   recovers the envelope structure — method calls, capabilities, and
   creation IDs all round-trip.

3. **Response identity.** For any valid server response JSON `j`,
   `GetResponse[T].fromJson(j)` produces an `ok` value whose fields
   match the JSON content. Invalid JSON returns `err(ValidationError)`.
   The same applies to all six response types.

4. **SetResponse losslessness.** Merging preserves ALL success AND
   failure entries in unified `Result` tables. No entries are lost.
   Success entries (`Result.ok`) correspond to wire
   `created`/`updated`/`destroyed`; failure entries (`Result.err`)
   correspond to wire `notCreated`/`notUpdated`/`notDestroyed`.

5. **Opt omission symmetry.** `none` produces no key in `toJson`;
   absent key produces `none` in `fromJson`.

6. **Referencable dispatch.** `rkDirect` serialises without `#` prefix;
   `rkReference` serialises with `#` prefix. Round-trips preserve the
   variant. `fromJsonField` rejects input where both `"foo"` and `"#foo"`
   are present (RFC §3.7 conflict detection).

7. **Method error preservation.** `MethodError.fromJson(errorJson)`
   preserves `rawType` (lossless, same as Layer 1/Layer 2 error types).

---

## 13. Opt[T] Field Handling Convention

All `Opt[T]` fields in Layer 3 types follow the policy defined in
§5a.5. Request types (`toJson`): omit key when `none`, using
`for val in opt:` for conditional consumption. Response types
(`fromJson`): absent, null, or wrong kind produces `none` (lenient).
See §5a.4 for the expected JSON kinds table and §5a.5 for the full
leniency policy including the structurally critical vs supplementary
field distinction.

The complete list of `Opt` fields and their handling is derivable from
the type definitions in §6 (request types) and §7 (response types).

---

## 14. Module File Layout

### 14.1 Source Files

```
src/jmap_client/
  entity.nim      — Entity type framework: registerJmapEntity and
                    registerQueryableEntity templates (with
                    when-not-compiles domain-specific error messages),
                    methodNamespace/capabilityUri/filterType/
                    filterConditionToJson overload patterns
  methods.nim     — 12 request/response type definitions, toJson (6 request
                    types), fromJson (6 response types), SetResponse
                    merging algorithm, CopyResponse merging, lenient
                    Opt helpers (optState, optUnsignedInt)
  builder.nim     — RequestBuilder type, initRequestBuilder, build, nextId,
                    addCapability, addInvocation, addMethodImpl template,
                    addEcho, addGet, addChanges, addSet, addCopy,
                    addQuery (proc + template), addQueryChanges
                    (proc + template), directIds, initCreates, initUpdates
  dispatch.nim    — ResponseHandle[T] type, ops (==, $, hash, callId),
                    validationToMethodError, extractInvocation (internal),
                    get[T] (mixin + callback overloads), reference,
                    idsRef, listIdsRef, addedIdsRef, createdRef, updatedRef
  protocol.nim    — Re-export hub; imports and re-exports entity, methods,
                    builder, dispatch
  convenience.nim — Optional pipeline combinators (NOT re-exported by
                    protocol.nim): QueryGetHandles, addQueryThenGet,
                    ChangesGetHandles, addChangesToGet, QueryGetResults,
                    ChangesGetResults, getBoth (two overloads)
```

### 14.2 Import DAG

```
types.nim (L1 hub) ←── serialisation.nim (L2 hub)
                            ^       ^        ^        ^
                            |       |        |        |
                         entity  methods  builder  dispatch
                                    ^        ^        ^
                                    |        |        |
                                    └────────┴────────┘
                                          |
                                     protocol.nim
                                          ^
                                          |
                                    convenience.nim
```

- `entity.nim` imports: nothing (pure templates, no type imports needed)
- `methods.nim` imports: `types`, `serialisation`
- `dispatch.nim` imports: `std/hashes`, `std/json`, `types`,
  `serialisation`, `methods`
- `builder.nim` imports: `std/json`, `std/tables`, `types`,
  `serialisation`, `methods`, `dispatch`
- `protocol.nim` imports and re-exports: `entity`, `methods`, `dispatch`,
  `builder`
- `convenience.nim` imports: `types`, `methods`, `dispatch`, `builder`

No cycles. Each module independently testable.

### 14.3 Test Files

```
tests/
  mtest_entity.nim — Shared mock entity (TestWidget) with filter condition
                     type (TestWidgetFilter), all framework overloads
                     (methodNamespace, capabilityUri, filterType,
                     filterConditionToJson), registration, and
                     toJson/fromJson. Reference implementation of the
                     entity module checklist (§4.6). Imported by all
                     protocol test modules.

tests/protocol/
  tentity.nim      — Mock entity type satisfies framework requirements;
                     registerJmapEntity compile-time check;
                     registerQueryableEntity compile-time check;
                     missing overload detection; domain-specific error
                     messages via when-not-compiles guards
  tmethods.nim     — Request toJson for all 6 types; response fromJson
                     for all 6 types; SetResponse merging; CopyResponse
                     merging; edge cases
  tbuilder.nim     — Builder construction, call ID generation, capability
                     deduplication, add* functions, addMethodImpl template,
                     single-type-parameter query overloads, argument
                     construction helpers
  tdispatch.nim    — ResponseHandle extraction, mixin and callback
                     overloads, error detection, validationToMethodError,
                     reference construction, type-safe reference
                     convenience functions
  tconvenience.nim — Pipeline combinator tests: addQueryThenGet,
                     addChangesToGet, getBoth extraction
```

### 14.4 Module Boilerplate

Every Layer 3 source module:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
```

`{.push raises: [].}` is on every source module — the compiler enforces
that no `CatchableError` can escape any function.

Every `func`/`proc` must have a `##` docstring (nimalyzer `hasDoc` rule).
Comments and docstrings use British English spelling. Variable names and
code identifiers use US English spelling.

---

## 15. Test Fixtures

### 15.1 Golden Test 1: Query to Get with Result Reference

Builder constructs `Mailbox/query` followed by `Mailbox/get` where `ids`
references `/ids` from the query response.

```json
{
  "using": ["urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/query", {
      "accountId": "A13824",
      "position": 0,
      "anchorOffset": 0,
      "calculateTotal": false
    }, "c0"],
    ["Mailbox/get", {
      "accountId": "A13824",
      "#ids": {
        "resultOf": "c0",
        "name": "Mailbox/query",
        "path": "/ids"
      }
    }, "c1"]
  ]
}
```

**Expected parsed values:**

- `req.using == @["urn:ietf:params:jmap:mail"]` (single capability,
  deduplicated)
- `req.methodCalls.len == 2`
- `req.methodCalls[0].name == "Mailbox/query"`
- `req.methodCalls[0].methodCallId == MethodCallId("c0")`
- `req.methodCalls[1].name == "Mailbox/get"`
- `req.methodCalls[1].arguments{"#ids"}` contains a `ResultReference`
  with `resultOf == "c0"`, `name == "Mailbox/query"`, `path == "/ids"`

### 15.2 Golden Test 2: Set with Create/Update/Destroy

Builder constructs `Foo/set` with all three operations.

```json
{
  "using": ["urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Foo/set", {
      "accountId": "A13824",
      "ifInState": "abc123",
      "create": {
        "k1": {"name": "New Item"}
      },
      "update": {
        "id1": {"name": "Updated"}
      },
      "destroy": ["id2", "id3"]
    }, "c0"]
  ]
}
```

**Expected parsed values:**

- Single method call with name `"Foo/set"`
- `arguments{"ifInState"}.getStr == "abc123"`
- `arguments{"create"}` is JObject with key `"k1"`
- `arguments{"update"}` is JObject with key `"id1"`
- `arguments{"destroy"}` is JArray with 2 elements

### 15.3 Golden Test 3: SetResponse Merging

Wire-format JSON with mixed success and failure entries:

```json
{
  "accountId": "A13824",
  "oldState": "state1",
  "newState": "state2",
  "created": {
    "k1": {"id": "id-new-1", "name": "Created Item"}
  },
  "notCreated": {
    "k2": {"type": "forbidden"}
  },
  "updated": {
    "id1": null,
    "id2": {"serverprop": "changed"}
  },
  "notUpdated": {
    "id3": {"type": "notFound"}
  },
  "destroyed": ["id4"],
  "notDestroyed": {
    "id5": {"type": "forbidden"}
  }
}
```

**Expected parsed values (unified Result maps):**

- `createResults` table has 2 entries: `k1` is `Result.ok(JsonNode)`,
  `k2` is `Result.err(SetError)` with `setForbidden`
- `updateResults` table has 3 entries: `id1` is
  `Result.ok(Opt.none(JsonNode))`, `id2` is
  `Result.ok(Opt.some(JsonNode))`, `id3` is
  `Result.err(SetError)` with `setNotFound`
- `destroyResults` table has 2 entries: `id4` is `Result.ok()`,
  `id5` is `Result.err(SetError)` with `setForbidden`
- `oldState.isSome` and `oldState.get == JmapState("state1")`
- `newState == JmapState("state2")`

### 15.4 Edge Cases

| Component | Input | Expected | Reason |
|-----------|-------|----------|--------|
| **GetResponse** | Valid JSON with all fields | `ok(GetResponse)` | Happy path |
| GetResponse | Missing `state` field | `err(ValidationError)` | Required field |
| GetResponse | `state` is JInt not JString | `err(ValidationError)` | `parseJmapState` rejects empty string from `.getStr("")` |
| GetResponse | `list` is JString not JArray | `err(ValidationError)` | `checkJsonKind` rejects |
| GetResponse | `notFound` absent | `ok` with empty `notFound` | Supplementary required field — absent treated as empty |
| GetResponse | `list` empty | `ok` with empty `list` | No results (valid) |
| GetResponse | Extra unknown fields | `ok` (ignored) | Postel's law |
| GetResponse | `accountId` empty string | `err(ValidationError)` | `parseAccountId` rejects |
| **ChangesResponse** | Valid JSON | `ok` | Happy path |
| ChangesResponse | `hasMoreChanges` = true | `.hasMoreChanges == true` | Partial sync |
| ChangesResponse | `hasMoreChanges` is JString | `err(ValidationError)` | `checkJsonKind` rejects — required `JBool` |
| ChangesResponse | `hasMoreChanges` absent | `err(ValidationError)` | `checkJsonKind` rejects — required field |
| ChangesResponse | Missing `newState` | `err(ValidationError)` | Required field |
| ChangesResponse | Empty `created`/`updated`/`destroyed` | `ok` with empty seqs | No changes |
| **SetResponse** | Both `created` and `notCreated` null | Empty `createResults` | Both absent |
| SetResponse | `created` has entries, `notCreated` null | `createResults` entries are all `ok` | Success only |
| SetResponse | `created` null, `notCreated` has entries | `createResults` entries are all `err` | Failure only |
| SetResponse | Both have entries | `createResults` has both `ok` and `err` entries | Normal case |
| SetResponse | `updated` entry with null value | `updateResults[id]` is `ok(Opt.none(JsonNode))` | Server-set only changes |
| SetResponse | `updated` entry with object value | `updateResults[id]` is `ok(Opt.some(obj))` | Server property changes |
| SetResponse | `destroyed` empty array | Empty `destroyResults` | No destroys |
| SetResponse | `oldState` absent | `oldState.isNone` | Server does not know |
| SetResponse | `notCreated` value missing `type` | `err(ValidationError)` | `SetError` requires type |
| SetResponse | `notCreated` value unknown type | `createResults` entry with `err(setUnknown)` | `rawType` preserved |
| SetResponse | Same id in `created` and `notCreated` | Last writer wins (failure) | Defensive — server bug |
| **CopyResponse** | All `notCreated` with `alreadyExists` | All in `createResults` with `err` + `existingId` | Copy error |
| CopyResponse | `notCreated` `alreadyExists` with malformed `existingId` | `createResults` entry with `err(setUnknown)`, `rawType` = `"alreadyExists"` | Graceful degradation |
| CopyResponse | `created` null, `notCreated` has entries | `createResults` entries are all `err` | All copies failed |
| CopyResponse | Valid `created` with server-set `id` | `createResults` entries are `ok` with entity JSON | Normal case |
| **QueryResponse** | `total` absent | `total.isNone` | `calculateTotal` false |
| QueryResponse | `limit` absent | `limit.isNone` | Server did not cap |
| QueryResponse | `ids` empty array | `@[]` | `position >= total` |
| QueryResponse | `position` is JString | `err(ValidationError)` | `checkJsonKind` rejects |
| QueryResponse | `canCalculateChanges` missing | `err(ValidationError)` | Required field |
| QueryResponse | `canCalculateChanges` is JInt | `err(ValidationError)` | `checkJsonKind` rejects — required `JBool` |
| **QueryChangesResponse** | Valid with removed + added | `ok` | Happy path |
| QueryChangesResponse | Empty removed, non-empty added | `ok` | Additions only |
| QueryChangesResponse | `total` absent | `total.isNone` | `calculateTotal` false |
| QueryChangesResponse | `added` with invalid `index` | `err(ValidationError)` | Propagated from `AddedItem.fromJson` |
| **Request toJson** | `GetRequest` with all none | `{"accountId": "..."}` only | Opt omission |
| Request toJson | `SetRequest` with all operations | All 3 fields present | Full SetRequest |
| Request toJson | `QueryRequest` with filter | Filter serialised via callback | Generic Filter[C] |
| Request toJson | `CopyRequest` with `onSuccessDestroyOriginal = true` | `"onSuccessDestroyOriginal": true` | Boolean always emitted |
| Request toJson | `ChangesRequest` minimal | `accountId` + `sinceState` only | Simplest request |

---

## 16. Design Decisions Summary

| ID | Decision | Alternative considered | Rationale |
|----|----------|----------------------|-----------|
| D3.1 | Layer 3 owns serialisation of Layer 3–defined types | Add new Layer 2 modules for Layer 3 types | Layer 3 types are generic over entity `T`; their serde depends on entity-specific resolution (`methodNamespace`, `filterType` templates) that only Layer 3 has. |
| D3.2 | `add*` params match RFC request fields; required positional, optional defaulted | Single generic `addMethod(name, argsJson)` | Type-safe: compiler enforces correct parameters per method. Discoverable: IDE autocomplete shows available fields. |
| D3.3 | Response dispatch returns `Result[T, MethodError]` | Unified `ClientError` for all failures | Method errors are data within a successful HTTP 200 response. They are per-invocation, not per-request. The outer railway (`JmapResult` / `ClientError`) is for transport/request failures at the Layer 4 boundary. |
| D3.4 | No concepts; plain overloaded `typedesc` procs + `registerJmapEntity`/`registerQueryableEntity` compile-time checks | Concepts (3.5A, rejected at architecture level) | Plain overloads + static registration templates give earlier error detection than concepts with zero compiler risk. |
| D3.5 | Only `GetRequest.ids` and `SetRequest.destroy` get `Referencable[T]` | All fields `Referencable` | Wrapping all fields is extremely verbose and rarely used. The two wrapped fields cover the canonical JMAP patterns. |
| D3.6 | Entity data as `JsonNode` in requests/responses | `seq[T]` with entity-specific callback | Layer 3 Core cannot know `T`'s deserialisation. Raw `JsonNode` preserves flexibility. |
| D3.7 | Unidirectional serde: request `toJson`, response `fromJson` | Full round-trip for all types | Client builds requests and parses responses — never the reverse. Halves the serialisation surface. |
| D3.9 | `nextId` uses `MethodCallId(s)` directly (bypassing validation) | `parseMethodCallId(s)` | The builder controls the format entirely. Generated IDs are provably valid. |
| D3.10 | `reference()` takes explicit `name` parameter; convenience functions auto-derive from T | Auto-derive from `T` and method suffix in all cases | Different methods produce different response names. Generic function is explicit; convenience functions are safe because they constrain the handle type. |
| D3.11 | `MaxChanges` distinct type (Layer 1) for `maxChanges` fields | `Opt[UnsignedInt]` with runtime/server rejection | RFC §5.2 requires > 0. Distinct type makes illegal state unrepresentable. |
| D3.12 | `QueryRequest[T, C]` with two generic parameters | Single `T` with `filterType(T)` in field types | Explicit second parameter is clearer. Single-type-parameter template overloads (§2.9) ensure `C == filterType(T)`. |
| 3.9B | Unified `Result` maps for SetResponse/CopyResponse | Separate success/failure tables | Single point of lookup per identifier. Composes with nim-results `Result` combinators. Last-writer-wins on duplicates. |

### Deferred Decisions

| ID | Topic | Disposition | Rationale |
|----|-------|-------------|-----------|
| R4 | `GetRequest.properties` as `Referencable` | Deferred to RFC 8621 | The `#properties` / `updatedProperties` pattern is real and canonical for Mailbox sync, but Mailbox-specific. |
| R7 | Convenience overloads for `addGet`/`addSet` | Deferred to post-implementation | Technically sound but zero users exist. Conveniences are additive. |
| R8 | `getImplicitSet[T]` for implicit `/set` responses from `/copy` | Deferred to RFC 8621 entity implementation | RFC 8620 §3.2 allows multiple responses per call ID. Current `findInvocation` will return the first match only. |

### MaxChanges Type (Layer 1 Addition)

The `maxChanges` fields in `ChangesRequest[T]` (§6.2) and
`QueryChangesRequest[T, C]` (§6.6) must be "a positive integer greater
than 0" per RFC §5.2 (lines 1694–1702). A `MaxChanges` distinct type with
a smart constructor closes this gap:

```nim
type MaxChanges* = distinct UnsignedInt
  ## A positive count used for maxChanges fields in Foo/changes and
  ## Foo/queryChanges requests. RFC 8620 §5.2 (lines 1694–1702)
  ## requires the value to be greater than 0.

defineIntDistinctOps(MaxChanges)

func parseMaxChanges*(raw: UnsignedInt): Result[MaxChanges, ValidationError] =
  ## Smart constructor: returns err if 0.
  if uint64(raw) == 0:
    return err(validationError("MaxChanges", "must be greater than 0", $uint64(raw)))
  ok(MaxChanges(raw))
```
