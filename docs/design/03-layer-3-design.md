# Layer 3: Protocol Logic — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, builder function, dispatch
mechanism, and serialisation pair for Layer 3 of the jmap-client library.
It builds upon the decisions made in `00-architecture.md`, the types
defined in `01-layer-1-design.md`, and the serialisation infrastructure
established in `02-layer-2-design.md` so that implementation is mechanical.

**Scope.** Layer 3 covers: call ID generation, request building
(`RequestBuilder`), response dispatch (`ResponseHandle[T]`), the entity
type framework (registration, associated types, `mixin` resolution), all
six standard method request/response types (RFC 8620 §5.1–5.6), the
`Core/echo` method (§4), result reference construction (§3.7),
`SetResponse` merging (parallel wire maps to unified `Result` maps), and
serialisation (`toJson`/`fromJson`) for all Layer 3–defined types.
Transport (Layer 4), the C ABI (Layer 5), binary data (§6), and push (§7)
are out of scope. Layer 3 is the uppermost layer of the pure functional
core — no `proc`, no I/O, no exception handling.

**Relationship to prior documents.** `00-architecture.md` records broad
decisions across all 5 layers. This document is the detailed specification
for Layer 3 only. Decisions here resolve — and are consistent with — the
architecture document's choices 3.2A (auto-incrementing call IDs), 3.3B
(builder with method-specific sub-builders), 3.4C (phantom-typed response
handles), 3.5B (plain overloaded procs, no concepts — deviates from
architecture's 3.5A; see §4), 3.7B (overloaded
type-level templates for associated types), 3.9B (unified Result maps
internally, parallel maps on the wire),
and 3.10A (string paths with constants, no validation). Decision 3.8A
(typed patch builders per entity) is deferred — Layer 3 Core has no
concrete entity types; typed patch builders are an entity-module concern
implemented when adding RFC 8621.

Layer 3 operates on Layer 1 types: `Invocation`, `Request`, `Response`,
`ResultReference`, `Referencable[T]`, `Filter[C]`, `Comparator`,
`PatchObject`, `AddedItem`, all identifier types (`Id`, `AccountId`,
`JmapState`, `MethodCallId`, `CreationId`), and all error types
(`MethodError`, `SetError`, `ValidationError`, `ClientError`). It imports
Layer 2's serialisation infrastructure: `parseError`, `checkJsonKind`,
`collectExtras`, `initResultErr` (centralised in `serde.nim` and
exported), `referencableKey`, `fromJsonField`, and all primitive/identifier
`toJson`/`fromJson` pairs.

**ARC note.** Layer 2's `serde_session.nim` deep-copies `JsonNode` via
`ownData`/`data.copy()` for case objects with `ref` fields in `else`
branches (ARC branch tracking corruption). Layer 3 response types are
plain objects (not case objects), so shared `JsonNode` refs from
`getElems()` are ARC ref-counted and safe. No deep-copy is needed for
Layer 3 types.

**Design principles.** Every decision follows:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `?`
  for early return. Builder functions return typed handles; dispatch
  functions return `Result[T, MethodError]` (inner railway). Smart
  constructors return `Result[T, ValidationError]` (construction railway).
  Layer 4 lifts to `JmapResult[T]` (outer railway) at the IO boundary.
- **Functional Core, Imperative Shell** — **Layer 3 is entirely `func`.**
  No `proc` definitions, no exception handling, no `try/except`. Every
  function is a pure transform. Builder accumulation uses owned `var`
  parameters — `strictFuncs` permits mutation of owned `var` parameters
  (Decision 3.3B); only mutation through immutable parameters' `ref`/`ptr`
  chains is forbidden.
- **Immutability by default** — `let` bindings. Local `var` only when
  building `JsonNode` trees (same as Layer 2) or accumulating builder
  state via owned `var` parameter. `strictFuncs` enforces that mutation
  does not escape.
- **Total functions** — `{.push raises: [].}` on every module. Every
  `fromJson` validates `JsonNodeKind` before extraction. Every function
  has a defined output for every input.
- **Parse, don't validate** — `fromJson` functions produce well-typed
  values by calling Layer 1 smart constructors, or structured
  `ValidationError`. Response dispatch converts `ValidationError` to
  `MethodError` at the railway boundary.
- **Make illegal states unrepresentable** — `ResponseHandle[T]` is a
  phantom distinct type that ensures type-safe extraction. Entity
  registration via `registerJmapEntity` catches missing overloads at
  definition time. `Referencable[T]` encodes the direct/reference
  distinction in the type system.

**L3-specific constraint: builder accumulation via owned `var` mutation
under `strictFuncs`.** All `add*` functions take `b: var RequestBuilder`
and mutate the builder's `seq` and counter fields. This is the owned `var`
pattern (c) from the architecture conventions — `strictFuncs` permits
mutation of owned `var` parameters because the mutation is through the
parameter itself, not through an immutable parameter's `ref`/`ptr` chain.

**`{.cast(noSideEffect).}:` pattern.** All `func` bodies that build
`JsonNode` trees, call `$` on `int`, or store `JsonNode` values into
containers wrap those sections in `{.cast(noSideEffect).}:`. This is safe
because the mutation is local (building a return value), not escaping
through `ref` indirection. Same pattern as Layer 2 §2 Pattern A — used
~20 times in existing serde code.

**Decision D3.1: Layer 3 owns serialisation of Layer 3–defined types.**
`toJson`/`fromJson` for standard method request/response types live in
Layer 3 modules, not Layer 2. Rationale: the types are generic over entity
type `T`; their serialisation depends on entity-specific resolution (e.g.,
`methodNamespace(T)`, `capabilityUri(T)`, `filterType(T)`) that only
Layer 3 has. Layer 3 imports Layer 2's infrastructure (`parseError`,
`checkJsonKind`, `collectExtras`, `initResultErr`, primitive `toJson`/
`fromJson` pairs) but defines its own type-specific serialisation.

**Compiler flags.** These constrain every type and function definition
(from `jmap_client.nimble`):

```
--mm:arc
--experimental:strictDefs
--experimental:strictNotNil
--experimental:strictFuncs
--experimental:strictCaseObjects
--styleCheck:error
{.push raises: [].}  (per-module)
{.experimental: "strictCaseObjects".}  (per src/ module)
```

---

## Standard Library Utilisation

Layer 3 maximises use of the Nim standard library. Every adoption and
rejection has a concrete reason tied to the strict compiler constraints.

### Modules used in Layer 3

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/json` | `newJObject`, `newJArray`, `%`, `%*`, `{}` accessor, `getStr`, `getBiggestInt`, `getBool`, `getFloat`, `getElems`, `pairs`, `hasKey`, `JsonNodeKind` | Same set as Layer 2. `{}` is the nil-safe accessor (returns nil, no `KeyError`). `[]` is NEVER used for field extraction. |
| `std/tables` | `Table`, `initTable`, `pairs`, `[]=`, `hasKey`, `len` | `SetResponse` merging, `SetRequest`/`CopyRequest` create maps, builder invocation accumulation |
| `std/sugar` | `collect` | Building seqs from iterators (Layer 2+ convention) |
| `std/sequtils` | `allIt`, `anyIt` | Predicate templates (same as Layer 1/Layer 2) |

### Modules evaluated and rejected

| Module | Reason not used in Layer 3 |
|--------|---------------------------|
| `std/strformat` | `fmt` is `proc`, not `func`. `$` + `&` suffice for call ID strings under `{.cast(noSideEffect).}:`. |
| `std/jsonutils` | Uses exceptions internally. Same rejection as Layer 2. |
| `std/atomics` | Call ID counter is builder-local, not shared. No concurrency requirement. |

### Critical Nim findings that constrain the design

| Finding | Impact | Evidence |
|---------|--------|----------|
| `$` on `int` is `proc {.raises: [].}`, not `func` | Call ID generation (`"c" & $n`) requires `{.cast(noSideEffect).}:` inside `func` | `dollars.nim:18` |
| Local `var Table` mutation in `func`: works for non-ref values | `SetResponse` merging with `Result[void, SetError]` needs no cast; with `Result[JsonNode, SetError]` needs cast | `serde_session.nim:248` (no cast), `serde.nim:43` (cast for `JsonNode`) |
| `template` returning `typedesc` works in generic object field types | `Filter[filterType(T)]` works — template expands to concrete type, then generic instantiation proceeds | `t5540.nim:17` |
| Concepts avoided (see `docs/design/notes/nim-concepts.md`) | Use plain overloaded `typedesc` procs + `registerJmapEntity` template + `mixin` instead | Known bugs (byref #16897, block scope issues), experimental status, no `.noSideEffect` enforcement in concept body, generic type checking unimplemented |
| `{.noSideEffect, raises: [].}` on `proc` type params enforced | Callback in `get[T]` correctly constrains callers | `manual.md:5356–5415` |
| `requiresInit` types in `Result` error branch | Use `initResultErr` workaround — centralised and exported from `serde.nim` (no longer duplicated per-module) | `serde.nim:37` |

---

## 1. Call ID Generation

**Architecture decision:** 3.2A (auto-incrementing counter)

**RFC reference:** §3.2 (lines 865–881) — the method call id is "an
arbitrary string from the client to be echoed back with the responses
emitted by that method call".

The counter is a field on `RequestBuilder`. Format: `"c0"`, `"c1"`, etc.
The `"c"` prefix guarantees the string is non-empty and free of control
characters, satisfying `MethodCallId` invariants without requiring
validation.

```nim
func nextId(b: var RequestBuilder): MethodCallId =
  ## Generates the next call ID and increments the counter.
  ## Format: "c0", "c1", ... — always valid MethodCallIds
  ## (non-empty, no control characters).
  var s = "c"
  {.cast(noSideEffect).}:
    s.add($b.nextCallId)
  inc b.nextCallId
  MethodCallId(s)
```

**Decision D3.9:** `MethodCallId(s)` uses the distinct constructor
directly (bypassing `parseMethodCallId`) because the generated format is
provably valid: the builder controls the format entirely, the `"c"` prefix
ensures non-empty, and `$int` produces only ASCII digit characters. This
bypass is safe and documented.

**Why `{.cast(noSideEffect).}:` is needed.** The `$` overload for `int`
is declared as `proc`, not `func`, in the Nim standard library
(`system/dollars.nim:18`). Although it has `{.raises: [].}` and performs
no observable side effects (it merely converts an integer to its string
representation), the missing `{.noSideEffect.}` annotation makes it
incompatible with `func` under `strictFuncs`. The cast is safe: the
conversion is deterministic and referentially transparent.

**Counter reset semantics.** The counter is scoped to a single
`RequestBuilder` instance. Each call to `initRequestBuilder()` produces a
fresh builder with `nextCallId: 0`. Call IDs therefore repeat across
requests — `"c0"` appears in every request. This is by design: the RFC
specifies call IDs as opaque correlation tokens scoped to a single
request/response pair (§3.2 line 876). See Section 3 for the cross-request
safety gap this creates.

**Module:** `builder.nim`

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
  ## Request (RFC 8620 §3.3). Fields are private — builder is the sole
  ## construction path. The counter is builder-local; call IDs are scoped
  ## to a single request.
  nextCallId: int                ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation]   ## accumulated method calls
  capabilities: seq[string]      ## deduplicated capability URIs
```

Fields are private (no `*` export marker). The builder is the sole
construction path — callers cannot bypass the builder to construct
malformed requests.

### 2.2 Constructor

```nim
func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations,
  ## and no capabilities.
  RequestBuilder(nextCallId: 0, invocations: @[], capabilities: @[])
```

### 2.3 Build

```nim
func build*(b: RequestBuilder): Request =
  ## Pure projection from builder state to Request. Does not mutate the
  ## builder — safely reusable after build(). The builder's capabilities
  ## become the Request's ``using`` array. The builder's invocations
  ## become the Request's ``methodCalls``. createdIds is Opt.none —
  ## proxy splitting is a Layer 4 concern.
  ##
  ## RFC reference: §3.3 (lines 882–945)
  Request(using: b.capabilities, methodCalls: b.invocations,
          createdIds: Opt.none(Table[CreationId, Id]))
```

Non-`var` parameter — pure projection. The builder is not consumed;
calling `build()` twice on the same builder yields the same `Request`.

### 2.4 Capability Deduplication

```nim
func addCapability(b: var RequestBuilder, cap: string) =
  ## Adds a capability URI to the builder if not already present.
  ## Manual check (not addUnique) — consistent with existing codebase
  ## patterns and avoids reliance on procs without explicit
  ## ``raises: []`` annotation.
  if cap notin b.capabilities:
    b.capabilities.add(cap)
```

### 2.5 Internal Invocation Helper

```nim
func addInvocation(b: var RequestBuilder, name: string,
    args: JsonNode, capability: string): MethodCallId =
  ## Constructs an Invocation from the given method name and arguments,
  ## adds it to the builder, registers the capability, and returns the
  ## generated call ID.
  let callId = b.nextId()
  let inv = Invocation(name: name, arguments: args, methodCallId: callId)
  b.invocations.add(inv)
  b.addCapability(capability)
  callId
```

### 2.6 The `add*` Method Signatures

The six standard method `add*` functions (§2.6.2–2.6.7) follow an
identical algorithmic pattern:

1. Construct arguments `JsonNode` via the request type's `toJson` inside
   `{.cast(noSideEffect).}:`.
2. Call `addInvocation` with `methodNamespace(T) & "/suffix"` and
   `capabilityUri(T)`.
3. Return `ResponseHandle[ResponseType](callId)`.

`addEcho` (§2.6.1) is a special case: it takes a raw `JsonNode`
argument, uses literal strings for method name and capability, is not
generic over `T`, and returns `ResponseHandle[JsonNode]`.

**Decision D3.2:** `add*` parameters match RFC request fields. Required
RFC fields are positional; optional fields are keyword-defaulted with
`Opt.none` or the RFC-specified default value.

**`var` parameter semantics.** All `add*` functions take
`b: var RequestBuilder`. Under `strictFuncs`, mutation of an owned `var`
parameter is permitted because the parameter is owned by the caller — the
mutation is through the parameter itself, not through an immutable
parameter's `ref`/`ptr` chain. This is pattern (c) from the architecture
conventions. The builder's `seq[Invocation]` and `seq[string]` fields are
value types — `.add()` on them is permitted under `strictFuncs` when the
parameter is `var`.

**Return type.** Each `add*` returns `ResponseHandle[ResponseType]` where
`ResponseType` is the method's response type (e.g., `GetResponse[T]` for
`addGet`). The handle wraps the generated `MethodCallId` and carries the
response type as a phantom parameter. The caller uses this handle with
`get[T]` (Section 3) to extract the typed response from the `Response`
envelope.

**2.6.1 addEcho**

```nim
func addEcho*(b: var RequestBuilder, args: JsonNode): ResponseHandle[JsonNode] =
  ## Adds a Core/echo invocation (RFC 8620 §4, lines 1540–1561).
  ## Returns a handle for extracting the echo response.
  ## Capability: "urn:ietf:params:jmap:core".
  ##
  ## RFC reference: §4 (lines 1540–1561)
  {.cast(noSideEffect).}:
    let callId = b.addInvocation("Core/echo", args, "urn:ietf:params:jmap:core")
  ResponseHandle[JsonNode](callId)
```

**2.6.2 addGet**

```nim
func addGet*[T](b: var RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string])
): ResponseHandle[GetResponse[T]] =
  ## Adds a Foo/get invocation (RFC 8620 §5.1, lines 1587–1665).
  ## ``ids``: Referencable — may be a direct seq or a result reference.
  ## ``properties``: if none, server returns all properties.
  ##
  ## RFC reference: §5.1 (lines 1587–1665)
  mixin methodNamespace, capabilityUri
  let name = methodNamespace(T) & "/get"
  let cap = capabilityUri(T)
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[GetResponse[T]](callId)
```

**2.6.3 addChanges**

```nim
func addChanges*[T](b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[UnsignedInt] = Opt.none(UnsignedInt)
): ResponseHandle[ChangesResponse[T]] =
  ## Adds a Foo/changes invocation (RFC 8620 §5.2, lines 1667–1838).
  ## ``sinceState``: the state string from a previous Foo/get response.
  ## ``maxChanges``: server may return fewer but must not return more.
  ##
  ## RFC reference: §5.2 (lines 1667–1838)
  mixin methodNamespace, capabilityUri
  let name = methodNamespace(T) & "/changes"
  let cap = capabilityUri(T)
  let req = ChangesRequest[T](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[ChangesResponse[T]](callId)
```

**2.6.4 addSet**

```nim
func addSet*[T](b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, JsonNode]] = Opt.none(Table[CreationId, JsonNode]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]])
): ResponseHandle[SetResponse[T]] =
  ## Adds a Foo/set invocation (RFC 8620 §5.3, lines 1855–2175).
  ## ``ifInState``: if supplied, must match current state or stateMismatch.
  ## ``create``: creation id to entity data map.
  ## ``update``: id to PatchObject map.
  ## ``destroy``: Referencable — may be a direct seq or a result reference.
  ##
  ## RFC reference: §5.3 (lines 1855–2175)
  mixin methodNamespace, capabilityUri
  let name = methodNamespace(T) & "/set"
  let cap = capabilityUri(T)
  let req = SetRequest[T](
    accountId: accountId, ifInState: ifInState,
    create: create, update: update, destroy: destroy)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[SetResponse[T]](callId)
```

**2.6.5 addCopy**

```nim
func addCopy*[T](b: var RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, JsonNode],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    onSuccessDestroyOriginal: bool = false,
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState)
): ResponseHandle[CopyResponse[T]] =
  ## Adds a Foo/copy invocation (RFC 8620 §5.4, lines 2191–2338).
  ## ``fromAccountId``: source account.
  ## ``accountId``: destination account (must differ from fromAccountId).
  ## ``create``: creation id to entity data map (required, not optional).
  ## ``onSuccessDestroyOriginal``: if true, server destroys originals
  ## after successful copy via an implicit Foo/set call.
  ##
  ## RFC reference: §5.4 (lines 2191–2338)
  mixin methodNamespace, capabilityUri
  let name = methodNamespace(T) & "/copy"
  let cap = capabilityUri(T)
  let req = CopyRequest[T](
    fromAccountId: fromAccountId, accountId: accountId,
    create: create, ifFromInState: ifFromInState, ifInState: ifInState,
    onSuccessDestroyOriginal: onSuccessDestroyOriginal,
    destroyFromIfInState: destroyFromIfInState)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[CopyResponse[T]](callId)
```

**2.6.6 addQuery**

```nim
func addQuery*[T](b: var RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[filterType(T)]] = Opt.none(Filter[filterType(T)]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    position: JmapInt = JmapInt(0),
    anchor: Opt[Id] = Opt.none(Id),
    anchorOffset: JmapInt = JmapInt(0),
    limit: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    calculateTotal: bool = false
): ResponseHandle[QueryResponse[T]] =
  ## Adds a Foo/query invocation (RFC 8620 §5.5, lines 2339–2638).
  ## ``filter``: generic over filterType(T) — entity-specific condition.
  ## ``anchor``: if supplied, ``position`` is ignored by the server.
  ## ``anchorOffset``: relative offset from the anchor's index.
  ## ``calculateTotal``: expensive — only request when needed.
  ##
  ## RFC reference: §5.5 (lines 2339–2638)
  mixin methodNamespace, capabilityUri, filterType
  let name = methodNamespace(T) & "/query"
  let cap = capabilityUri(T)
  let req = QueryRequest[T](
    accountId: accountId, filter: filter, sort: sort,
    position: position, anchor: anchor, anchorOffset: anchorOffset,
    limit: limit, calculateTotal: calculateTotal)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[QueryResponse[T]](callId)
```

**2.6.7 addQueryChanges**

```nim
func addQueryChanges*[T](b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[filterType(T)]] = Opt.none(Filter[filterType(T)]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false
): ResponseHandle[QueryChangesResponse[T]] =
  ## Adds a Foo/queryChanges invocation (RFC 8620 §5.6, lines 2639–2819).
  ## ``sinceQueryState``: the queryState string from a previous Foo/query.
  ## ``upToId``: optimisation when sort/filter are on immutable properties.
  ##
  ## RFC reference: §5.6 (lines 2639–2819)
  mixin methodNamespace, capabilityUri, filterType
  let name = methodNamespace(T) & "/queryChanges"
  let cap = capabilityUri(T)
  let req = QueryChangesRequest[T](
    accountId: accountId, sinceQueryState: sinceQueryState,
    filter: filter, sort: sort, maxChanges: maxChanges,
    upToId: upToId, calculateTotal: calculateTotal)
  {.cast(noSideEffect).}:
    let args = req.toJson()
    let callId = b.addInvocation(name, args, cap)
  ResponseHandle[QueryChangesResponse[T]](callId)
```

**Decision D3.5:** Only `GetRequest.ids` and `SetRequest.destroy` receive
`Referencable[T]` wrapping — these are the canonical result reference
targets (`/ids` from query, `/list/*/id` from get, `/updated` from
changes). All other fields are direct values.

**Decision D3.6:** Entity data is represented as `JsonNode` in create maps
and response lists. Layer 3 Core cannot know `T`'s serialisation format;
entity-specific modules (e.g., RFC 8621 mail types) will provide concrete
`fromJson` implementations to convert raw `JsonNode` instances into typed
entity values.

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
  ##
  ## Borrowed ops: ``==``, ``$``, ``hash`` from MethodCallId.
```

`T` is phantom. The handle carries no runtime representation of the
response type — it is a `MethodCallId` at runtime and a typed token at
compile time. This is proven to compile by
`.nim-reference/tests/distinct/tdistinct_issues.nim:14–27`.

Borrowed operations:

```nim
func `==`*(a, b: ResponseHandle): bool {.borrow.}
func `$`*(a: ResponseHandle): string {.borrow.}
func hash*(a: ResponseHandle): Hash {.borrow.}
```

### 3.2 Extraction Function

```nim
func get*[T](resp: Response, handle: ResponseHandle[T],
    fromArgs: proc(node: JsonNode): Result[T, ValidationError]
        {.noSideEffect, raises: [].}
): Result[T, MethodError] =
  ## Extracts a typed response from the Response envelope using the
  ## handle's call ID. Detects method-level errors and converts
  ## ValidationError to MethodError at the railway boundary.
  ##
  ## Algorithm:
  ## 1. Scan resp.methodResponses for invocation where
  ##    methodCallId == MethodCallId(handle).
  ## 2. If not found: err(methodError("serverFail", ...)).
  ## 3. If invocation name is "error": parse as MethodError via
  ##    MethodError.fromJson(invocation.arguments), return err.
  ## 4. Otherwise: call fromArgs(invocation.arguments).
  ##    On ok(v): return ok(v).
  ##    On err(validErr): return err(methodError("serverFail", ...)).
  ##
  ## RFC reference: §3.4 (lines 975–1035), §3.6.2 (lines 1137–1219)
  ...
```

**Railway conversion (Track 0 to Track 2).** The `fromArgs` callback
returns `Result[T, ValidationError]` (construction railway, Track 0).
`get[T]` returns `Result[T, MethodError]` (inner railway, Track 2). The
conversion wraps `ValidationError.message` into `MethodError.description`
— this is the `mapErr` semantic at the railway boundary. If
`MethodError.fromJson` itself fails on a malformed error response (step
3), the same `serverFail` fallback applies.

**Full algorithm:**

```nim
func get*[T](resp: Response, handle: ResponseHandle[T],
    fromArgs: proc(node: JsonNode): Result[T, ValidationError]
        {.noSideEffect, raises: [].}
): Result[T, MethodError] =
  let targetId = MethodCallId(handle)
  var found = false
  var matchedInv: Invocation
  for inv in resp.methodResponses:
    if inv.methodCallId == targetId:
      found = true
      matchedInv = inv
      break
  if not found:
    return err(methodError("serverFail",
      description = Opt.some("no response for call ID " & $handle)))
  # Detect method-level error response (RFC §3.6.2)
  if matchedInv.name == "error":
    let meResult = MethodError.fromJson(matchedInv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    else:
      return err(methodError("serverFail",
        description = Opt.some("malformed error response")))
  # Parse the response arguments via the caller-supplied callback
  let parseResult = fromArgs(matchedInv.arguments)
  if parseResult.isOk:
    ok(parseResult.get())
  else:
    err(methodError("serverFail",
      description = Opt.some(parseResult.error.message)))
```

**Decision D3.3:** Returns `Result[T, MethodError]` (inner railway), not
`Result[T, ClientError]`. Method errors are data within a successful HTTP
response. The outer railway (`ClientError`) is reserved for transport and
request-level failures at the Layer 4 boundary.

**Error detection heuristic (step 3).** The RFC specifies that method-level
errors use the response name `"error"` (§3.6.2 lines 1148–1154):
`["error", {"type": "unknownMethod"}, "call-id"]`. The dispatch function
checks `matchedInv.name == "error"` rather than inspecting the arguments
for a `"type"` key. Rationale: the RFC mandates the `"error"` name for
all method-level errors. Checking the name is both simpler and more
reliable than heuristic argument inspection. A response named `"error"`
that does not parse as `MethodError` is treated as `serverFail` — this
handles malformed error responses without losing the error signal.

**`fromArgs` callback design.** The callback type
`proc(node: JsonNode): Result[T, ValidationError] {.noSideEffect,
raises: [].}` is deliberately a `proc` parameter with explicit effect
annotations rather than a `func` parameter. In Nim, `func` is syntactic
sugar for `proc {.noSideEffect.}`; in type positions, the long form is
required. The `{.raises: [].}` annotation is mandatory because the
module-level `{.push raises: [].}` requires callable parameters to prove
they cannot raise. Callers pass entity-specific `fromJson` functions as
callbacks.

**`strictDefs` interaction.** The `var matchedInv: Invocation` declaration
requires initialisation under `strictDefs`. Since `Invocation` is a plain
object (no `{.requiresInit.}` fields), the default zero-initialisation is
sufficient — `matchedInv` is assigned before use inside the loop. The
`found` flag guards all subsequent access.

**Cross-request safety gap.** Call IDs repeat across requests (`"c0"` in
every request). A handle from Request A used with Response B silently
extracts the wrong invocation. No type-level mitigation is possible in Nim
without encoding the request identity in the type system (which would add
complexity disproportionate to the risk). Convention: use handles
immediately within the scope where the request was built. This gap is
documented in the `ResponseHandle` doc comment.

**Module:** `dispatch.nim`

---

## 4. Entity Type Framework

**Architecture decisions:** 3.5B (plain overloads, no concepts), 3.7B
(overloaded type-level templates for associated types)

**Decision D3.4:** No concepts; plain overloaded `typedesc` procs with a
`registerJmapEntity` compile-time check template instead.

> **Deviation from architecture:** Decision 3.5A specified Nim concepts
> for the entity type interface. Per `docs/design/notes/nim-concepts.md`
> and explicit direction, concepts are avoided due to: experimental
> status, known compiler bugs (byref #16897, block scope issues, implicit
> generic breakage), `func` in concept body not enforcing
> `.noSideEffect`, generic type checking unimplemented, and minimal
> stdlib adoption (2 files). Fallback 3.5B (plain overloaded procs) is
> used instead, providing equivalent compile-time safety via a
> registration template that verifies all required overloads exist.

### 4.1 Entity Interface — Required Overloads

Each entity type must provide these `typedesc` overloads:

```nim
## Required overloads for any JMAP entity type:

func methodNamespace*(T: typedesc[Mailbox]): string = "Mailbox"
  ## Returns the entity name for method name construction.
  ## "Mailbox" produces "Mailbox/get", "Mailbox/set", etc.
  ## RFC 8620 §5 (lines 1575–1586): "Foo/get", "Foo/set" naming convention.

func capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
  ## Returns the capability URI for the ``using`` array.
  ## RFC 8620 §3.3 (lines 886–894): "The set of capabilities the client
  ## wishes to use."
```

### 4.2 Compile-Time Registration Template

The `registerJmapEntity` template verifies all required overloads exist at
the registration site (not at distant generic instantiation time). Missing
overloads produce compile errors at the entity definition, not at `add*`
call sites.

```nim
template registerJmapEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides the required framework
  ## overloads (``methodNamespace`` and ``capabilityUri``). Call this
  ## once per entity type at module scope. Missing framework overloads
  ## produce compile errors HERE, not at distant add* call sites.
  ## Does not check conditional overloads (``filterType``) — those are
  ## caught at ``addQuery``/``addQueryChanges`` call sites via ``mixin``.
  static:
    discard methodNamespace(T)
    discard capabilityUri(T)
```

Usage:

```nim
type Mailbox* = object
  ## RFC 8621 Mailbox entity type.

func methodNamespace*(T: typedesc[Mailbox]): string = "Mailbox"
func capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
registerJmapEntity(Mailbox)  # compile error if any overload is missing
```

### 4.3 Generic `add*` Functions — Unconstrained `T`

```nim
func addGet*[T](b: var RequestBuilder, ...): ResponseHandle[GetResponse[T]]
```

No `: JmapEntity` constraint on `T`. If `T` lacks `methodNamespace` or
`capabilityUri`, the error appears when the `add*` body calls
`methodNamespace(T)`. The `registerJmapEntity` template catches this
earlier — at entity definition time rather than at call site.

**Why no concept constraint.** Concepts in Nim are experimental and have
known issues documented in `docs/design/notes/nim-concepts.md`:

1. `func` in a concept body does NOT enforce `.noSideEffect` — the
   concept match succeeds even if the matched proc is side-effectful.
2. Generic type checking for concepts is unimplemented — the compiler
   does not verify concept satisfaction at generic definition time.
3. Known compiler bugs: byref semantics (#16897), block scope issues,
   implicit generic breakage.
4. Minimal stdlib adoption (only 2 files use concepts).

The unconstrained `T` approach provides equivalent safety in practice:
`registerJmapEntity(T)` catches errors at entity definition time, and
`mixin` + overload resolution catches them at generic instantiation time.

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

**How `mixin` works.** In Nim's generic resolution, symbols are resolved
in two phases: (1) at definition time (the module where `addGet` is
defined), and (2) at instantiation time (the call site where `T` is
bound). By default, overloaded proc names found at definition time are
bound early. `mixin` forces the named symbols to be resolved at
instantiation time instead, searching the caller's scope. This is
critical for the entity type framework: `methodNamespace(Mailbox)` is
defined in the mailbox entity module, not in `builder.nim`.

### 4.5 Associated Type Templates

Proven by `.nim-reference/tests/misc/t5540.nim:17`: a `template`
returning `typedesc` can be used in generic object field type positions.

```nim
template filterType*(T: typedesc[Mailbox]): typedesc = MailboxFilterCondition
  ## Maps entity type to its filter condition type.
  ## Used in ``QueryRequest[T]`` and ``QueryChangesRequest[T]`` where
  ## the filter field type is ``Filter[filterType(T)]``.
```

Each entity module provides its own `filterType` overload. Core RFC 8620
defines no concrete entity types — only the framework. The `mixin
filterType` declaration in `addQuery` and `addQueryChanges` ensures the
caller's overload is found.

**Why `template` returning `typedesc` works.** The mechanism is proven by
`.nim-reference/tests/misc/t5540.nim:17`: a `template` that returns a
`typedesc` can be used in positions where a type is expected, including
generic object field types. When the compiler encounters
`Filter[filterType(T)]`, it first expands `filterType(T)` (which is a
`template` call producing a concrete `typedesc`), then instantiates
`Filter` with the resulting type. This is a compile-time expansion, not
a runtime operation.

**Entity module checklist.** Every entity module must provide:

1. The entity type definition (e.g., `type Mailbox* = object`).
2. `func methodNamespace*(T: typedesc[Entity]): string`.
3. `func capabilityUri*(T: typedesc[Entity]): string`.
4. `template filterType*(T: typedesc[Entity]): typedesc` (if the entity
   supports `/query`).
5. `registerJmapEntity(Entity)` at module scope.
6. `toJson`/`fromJson` for the entity type itself (for create maps and
   response lists).

Items 1–5 are Layer 3 concerns. Item 6 is entity-specific and lives in
the entity module alongside the type definition.

**Module:** `entity.nim`

---

## 5a. Serialisation Infrastructure for Layer 3 Types

Layer 3 reuses Layer 2's serialisation infrastructure but must document
its own patterns. Layer 3 types are generic over entity type `T`; their
serialisation involves entity-specific resolution that only Layer 3 has.

**Decision D3.7:** Unidirectional serialisation — request types get
`toJson` only, response types get `fromJson` only. The client builds
requests (serialises to JSON) and parses responses (deserialises from
JSON). This halves the serialisation surface and avoids the need for
response `toJson` or request `fromJson` in production code.

### 5a.1 Pattern L3-A: Request `toJson` (Object Construction)

Build a `JsonNode` object inside `{.cast(noSideEffect).}:`. Omit keys
for `Opt.none` fields. Use `referencableKey` for `Referencable[T]`
fields. Use `Filter[C].toJson(condCallback)` for filter fields.

Canonical example — `GetRequest[T].toJson`:

```nim
func toJson*[T](req: GetRequest[T]): JsonNode =
  ## Serialise GetRequest to JSON arguments object (RFC 8620 §5.1).
  ## Omits ``ids`` and ``properties`` when Opt.none.
  ## Dispatches Referencable ids via referencableKey.
  ##
  ## RFC reference: §5.1 (lines 1587–1612)
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    if req.ids.isSome:
      let idsVal = req.ids.get()
      let idsKey = referencableKey("ids", idsVal)
      case idsVal.kind
      of rkDirect:
        var arr = newJArray()
        for id in idsVal.value:
          arr.add(id.toJson())
        result[idsKey] = arr
      of rkReference:
        result[idsKey] = idsVal.reference.toJson()
    if req.properties.isSome:
      var arr = newJArray()
      for p in req.properties.get():
        arr.add(%p)
      result["properties"] = arr
```

**Pattern L3-A invariants:**

- Every `toJson` wraps the entire body in `{.cast(noSideEffect).}:`.
- Required fields are always emitted.
- `Opt.none` fields are omitted (key absent from the JSON object).
- `Referencable[T]` fields emit `"fieldName"` for `rkDirect` and
  `"#fieldName"` for `rkReference`, using `referencableKey` from
  Layer 2's `serde_envelope.nim`.
- Boolean fields with RFC defaults (`false`) are always emitted — the
  server treats absence as the default, but explicit emission is clearer
  and avoids ambiguity.

### 5a.2 Pattern L3-B: Response `fromJson` (Object Extraction)

Check `node.kind == JObject` via `checkJsonKind`. Extract each field via
`{}` accessor (nil-safe). Call Layer 1 smart constructors for identifier
fields. Use `?` for early return on error. Use `initResultErr` when the
return type contains `{.requiresInit.}` fields.

Canonical example — `GetResponse[T].fromJson`:

```nim
func fromJson*[T](
    R: typedesc[GetResponse[T]], node: JsonNode
): Result[GetResponse[T], ValidationError] =
  ## Deserialise JSON arguments to GetResponse (RFC 8620 §5.1).
  ## Uses lenient constructors for server-assigned identifiers.
  ## list contains raw JsonNode entities — entity-specific parsing
  ## is the caller's responsibility.
  ##
  ## RFC reference: §5.1 (lines 1613–1665)
  checkJsonKind(node, JObject, "GetResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let state = ?parseJmapState(node{"state"}.getStr(""))
  let listNode = node{"list"}
  checkJsonKind(listNode, JArray, "GetResponse", "list must be array")
  var list: seq[JsonNode]
  {.cast(noSideEffect).}:
    list = listNode.getElems()
  var notFound: seq[Id]
  let nfNode = node{"notFound"}
  if not nfNode.isNil and nfNode.kind == JArray:
    for elem in nfNode.getElems():
      let id = ?parseIdFromServer(elem.getStr(""))
      notFound.add(id)
  ok(GetResponse[T](accountId: accountId, state: state,
                     list: list, notFound: notFound))
```

**Pattern L3-B invariants:**

- Root check: `checkJsonKind(node, JObject, typeName)`.
- Required fields: extract via `{}`, validate kind, call smart constructor
  with `?` for early return.
- Server-assigned identifiers: use lenient constructors
  (`parseIdFromServer`, `parseAccountId`).
- `seq` fields: check `JArray` kind, iterate `getElems()`, validate and
  accumulate each element.
- Optional fields (`Opt[T]`): absent, null, or wrong kind produces
  `Opt.none(T)` (lenient, per §5a.4).
- `initResultErr` workaround: used when `Result[T, ValidationError]`
  contains `T` with `{.requiresInit.}` fields (e.g., `JmapState`).

### 5a.3 Pattern L3-C: SetResponse Merging (Parallel Maps to Result Maps)

The wire format (RFC 8620 §5.3, lines 2009–2082) uses parallel maps
(`created`/`notCreated`, `updated`/`notUpdated`, `destroyed`/
`notDestroyed`). The internal representation merges these into unified
`Result` maps per Decision 3.9B. Full algorithm specified in Section 8
(below).

The merging pattern is used by both `SetResponse[T].fromJson` and
`CopyResponse[T].fromJson`. The create-merging algorithm is shared; only
the response field names differ.

**Merging type signatures:**

```nim
## Create: wire created (Id[Foo]|null) + notCreated (Id[SetError]|null)
##   → Table[CreationId, Result[JsonNode, SetError]]
## Update: wire updated (Id[Foo|null]|null) + notUpdated (Id[SetError]|null)
##   → Table[Id, Result[Opt[JsonNode], SetError]]
## Destroy: wire destroyed (Id[]|null) + notDestroyed (Id[SetError]|null)
##   → Table[Id, Result[void, SetError]]
```

**Cast requirement.** The create and update merging tables contain
`Result[JsonNode, SetError]` and `Result[Opt[JsonNode], SetError]`
respectively — both contain `JsonNode` (a `ref` type). Under
`strictFuncs`, mutation of a `var Table` containing `ref` values inside
a `func` requires `{.cast(noSideEffect).}:`. The destroy merging table
contains `Result[void, SetError]` (no `ref` values) and does NOT require
a cast.

### 5a.4 Expected JSON Kinds per Response Type

The table below lists the expected JSON kind for each field. Three
distinct validation mechanisms are used (see §5a.5 for details):

- **Strict `checkJsonKind`:** explicit kind gate — wrong kind returns
  `err(parseError(...))`. Used for structurally critical fields (e.g.,
  `list: JArray`).
- **Smart constructor delegation:** `.getStr("")` feeds a smart
  constructor (e.g., `parseAccountId`) which rejects empty/invalid input
  with a `ValidationError`. Used for required identifier fields (e.g.,
  `accountId`, `state`).
- **Lenient:** absent, null, or wrong kind produces `Opt.none` or an
  empty default. Used for optional and supplementary fields.

| Response Type | Root check | Field-level expected kinds |
|---------------|------------|--------------------------|
| `GetResponse[T]` | `JObject` | `accountId`: `JString`; `state`: `JString`; `list`: `JArray`; `notFound`: `JArray` (lenient — absent treated as empty) |
| `ChangesResponse[T]` | `JObject` | `accountId`: `JString`; `oldState`/`newState`: `JString`; `hasMoreChanges`: `JBool`; `created`/`updated`/`destroyed`: `JArray` |
| `SetResponse[T]` | `JObject` | `accountId`: `JString`; `newState`: `JString`; `oldState`: lenient (absent/wrong kind produces `Opt.none`); parallel maps: `JObject` (lenient — null treated as empty) |
| `CopyResponse[T]` | `JObject` | Same structure as `SetResponse` for `created`/`notCreated` fields |
| `QueryResponse[T]` | `JObject` | `accountId`: `JString`; `queryState`: `JString`; `canCalculateChanges`: `JBool`; `position`: `JInt`; `ids`: `JArray`; `total`/`limit`: lenient (absent produces `Opt.none`) |
| `QueryChangesResponse[T]` | `JObject` | `accountId`: `JString`; `oldQueryState`/`newQueryState`: `JString`; `removed`: `JArray`; `added`: `JArray` |

### 5a.5 Opt[T] Leniency Policy

Based on Layer 2 §1.4b. Layer 2 scopes the lenient policy to simple
scalar `Opt` fields, with complex container `Opt` types (e.g.,
`Opt[Table[CreationId, Id]]`) retaining strict handling. Layer 3
generalises the lenient policy to all `Opt[T]` fields because Layer 3
response types contain only simple scalar or identifier `Opt` fields —
no complex container `Opt` types.

Client library parses server data — Postel's law applies. For optional
fields (`Opt[T]`), absent key, null value, or wrong JSON kind all produce
`Opt.none(T)`. For required fields, wrong kind produces
`err(parseError(...))`.

Rationale:

1. `Opt` fields are already optional — callers handle absence via
   `.isSome`/`.isNone`.
2. Strictness on supplementary fields (like `description` on errors) risks
   losing the critical primary field.
3. "Absent" and "malformed" are equivalent for optional data from a server.

**Exception — structurally critical required fields:** Required fields
that are structurally critical to the response (e.g., `list: seq[JsonNode]`
in `GetResponse`) use strict `checkJsonKind` — wrong kind returns
`err(parseError(...))`. A response without a `list` array is not a valid
`/get` response. Supplementary required fields (e.g.,
`notFound: seq[Id]` in `GetResponse`) are treated leniently — absent or
wrong kind produces an empty default (e.g., empty `seq`) rather than an
error. The distinction: structurally critical fields define the response's
primary payload; supplementary fields provide additional context that
callers can safely default.

**Required identifier fields** (e.g., `accountId`, `state`) delegate kind
validation to their smart constructors via `.getStr("")` — wrong kind
produces an empty string which the constructor rejects with a
`ValidationError`. This is functionally equivalent to `checkJsonKind` but
produces a domain-level error rather than a kind-mismatch error.

### 5a.6 Serialisation Pair Inventory

Every Layer 3 type and its serialisation direction. The `{.cast.}` column
indicates whether `{.cast(noSideEffect).}:` is needed in the
implementation body.

| Type | Direction | `{.cast.}` needed | Notes |
|------|-----------|-------------------|-------|
| `GetRequest[T]` | `toJson` only | Yes (builds `JsonNode`) | `Referencable` ids uses `referencableKey` |
| `GetResponse[T]` | `fromJson` only | Yes (list contains `JsonNode`) | `initResultErr` for `JmapState` |
| `ChangesRequest[T]` | `toJson` only | Yes | Simplest request — only 3 fields |
| `ChangesResponse[T]` | `fromJson` only | No (no ref values in result) | `initResultErr` for `JmapState` |
| `SetRequest[T]` | `toJson` only | Yes | `Referencable` destroy uses `referencableKey` |
| `SetResponse[T]` | `fromJson` only | Yes (`Result` maps with `JsonNode`) | Merging algorithm Pattern L3-C |
| `CopyRequest[T]` | `toJson` only | Yes | Required `create` map (not `Opt`) |
| `CopyResponse[T]` | `fromJson` only | Yes (`Result` maps with `JsonNode`) | Same merging as `SetResponse` (create branch only) |
| `QueryRequest[T]` | `toJson` only | Yes | Generic `Filter[C]` uses callback |
| `QueryResponse[T]` | `fromJson` only | No (ids are value types) | `total`/`limit` lenient |
| `QueryChangesRequest[T]` | `toJson` only | Yes | `Filter[C]` callback same as `QueryRequest` |
| `QueryChangesResponse[T]` | `fromJson` only | No (`AddedItem` has value-type fields) | `total` lenient |
| `echoFromJson` | `fromJson` callback | No (returns input node) | Validates `JObject` kind only; §9 |

### 5a.7 Layer 2 Infrastructure Imports

Layer 3 modules import the following from Layer 2's `serde.nim` and
`serde_envelope.nim`:

| Import | Source | Used for |
|--------|--------|----------|
| `parseError` | `serde.nim:16` | Constructing `ValidationError` in `fromJson` |
| `checkJsonKind` | `serde.nim:21` | Kind validation template (returns `err` on mismatch) |
| `initResultErr` | `serde.nim:37` | Workaround for `requiresInit` + `Result` limitation |
| `collectExtras` | `serde.nim:51` | Gathering non-standard fields into `Opt[JsonNode]` |
| `toJson` (all primitive/id types) | `serde.nim:67–197` | Serialising `AccountId`, `Id`, `JmapState`, etc. in request `toJson` |
| `fromJson` (all primitive/id types) | `serde.nim:128–197` | Deserialising server-assigned identifiers in response `fromJson` |
| `referencableKey` | `serde_envelope.nim:194` | Determining JSON key for `Referencable[T]` fields (`"foo"` vs `"#foo"`) |
| `toJson` (envelope types) | `serde_envelope.nim:22–26` | `Invocation.toJson`, `ResultReference.toJson` |
| `fromJson` (envelope types) | `serde_envelope.nim:28–46` | `MethodError.fromJson` for error detection in dispatch |

**Module:** `methods.nim`

---

## 5b. Per-Method Errors and Behavioural Semantics

Each standard method can return method-level errors (via the inner railway
`Result[T, MethodError]`). These are already defined as
`MethodErrorType` variants in Layer 1 `errors.nim`
(`src/jmap_client/errors.nim`). This section documents WHICH errors apply
to WHICH methods. The `get[T]` dispatch function (Section 3) detects
error responses and returns them as `MethodError`.

### 5b.1 General Method-Level Errors

**RFC reference:** §3.6.2 (lines 1137–1219)

The following general errors may be returned for **any** method call. They
are defined as `MethodErrorType` variants in Layer 1 `errors.nim` and
detected by the `get[T]` dispatch function (Section 3.2).

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

**Extension mechanism (§5.3 lines 2162–2164).** Other possible SetError
types MAY be given in specific method descriptions. The `setUnknown`
variant and `rawType` preservation handle server extensions gracefully.

### 5b.4 Behavioural Semantics

The following behavioural rules are documented as `##` doc comments on
the relevant request/response types. They constrain client-side
expectations and are tested via the compliance test suite.

**§3.5 Omitting Arguments (lines 1037–1048).** An argument with a default
value may be omitted by the client. The server treats omitted arguments
the same as if the default value had been specified. `null` is the default
for any argument where allowed by the type signature, unless otherwise
specified.

**§3.10 Concurrency (lines 903–906).** Method calls within a single
request are processed sequentially, in order. Concurrent requests may
interleave. The builder's sequential `add*` order maps directly to server
execution order. This is critical for result references: a reference to
call `"c0"` from call `"c1"` is valid because `"c0"` is processed first.

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
RFC section and line numbers. Each type receives a `toJson` function
following Pattern L3-A (Section 5a.1). No `fromJson` is provided —
request types are serialised by the client, never parsed (Decision D3.7).

### 6.1 GetRequest[T]

**RFC reference:** §5.1 (lines 1587–1612)

```nim
type GetRequest*[T] = object
  ## Request arguments for Foo/get (RFC 8620 §5.1, lines 1587–1612).
  ## Fetches objects of type T by their identifiers, optionally returning
  ## only a subset of properties.

  accountId*: AccountId
    ## The identifier of the account to use.
    ## RFC §5.1 (line 1593): "accountId: Id"

  ids*: Opt[Referencable[seq[Id]]]
    ## The identifiers of the Foo objects to return. If none, all records
    ## of the data type are returned (subject to maxObjectsInGet).
    ## Referencable: may be a direct seq or a result reference to a
    ## previous call's output (e.g., /query ids).
    ## RFC §5.1 (lines 1597–1602): "ids: Id[]|null"

  properties*: Opt[seq[string]]
    ## If supplied, only the listed properties are returned for each
    ## object. If none, all properties are returned. The "id" property
    ## is always returned even if not explicitly requested (line 1608).
    ## RFC §5.1 (lines 1604–1611): "properties: String[]|null"
```

**`toJson` signature:**

```nim
func toJson*[T](req: GetRequest[T]): JsonNode =
  ## Serialises GetRequest to JSON arguments object (RFC 8620 §5.1).
  ## Omits ``ids`` and ``properties`` when Opt.none.
  ## Dispatches Referencable ids via referencableKey.
  ## Pattern L3-A (§5a.1).
  ...
```

### 6.2 ChangesRequest[T]

**RFC reference:** §5.2 (lines 1667–1703)

```nim
type ChangesRequest*[T] = object
  ## Request arguments for Foo/changes (RFC 8620 §5.2, lines 1667–1703).
  ## Retrieves the list of identifiers for records that have changed
  ## (created, updated, or destroyed) since a given state.

  accountId*: AccountId
    ## The identifier of the account to use.
    ## RFC §5.2 (line 1676): "accountId: Id"

  sinceState*: JmapState
    ## The current state of the client, as returned in a previous
    ## Foo/get response. The server returns changes since this state.
    ## RFC §5.2 (lines 1687–1693): "sinceState: String"

  maxChanges*: Opt[UnsignedInt]
    ## The maximum number of identifiers to return. The server MAY
    ## return fewer but MUST NOT return more. If not given, the server
    ## chooses. The RFC requires this value to be greater than 0
    ## (lines 1694–1702); ``UnsignedInt`` permits 0 but servers reject
    ## 0 with ``invalidArguments`` (known representability gap — see §15).
    ## RFC §5.2 (lines 1694–1702): "maxChanges: UnsignedInt|null"
```

**`toJson` signature:**

```nim
func toJson*[T](req: ChangesRequest[T]): JsonNode =
  ## Serialises ChangesRequest to JSON arguments object (RFC 8620 §5.2).
  ## Omits ``maxChanges`` when Opt.none.
  ## Pattern L3-A (§5a.1).
  ...
```

### 6.3 SetRequest[T]

**RFC reference:** §5.3 (lines 1855–1945)

```nim
type SetRequest*[T] = object
  ## Request arguments for Foo/set (RFC 8620 §5.3, lines 1855–1945).
  ## Creates, updates, and/or destroys records of type T in a single
  ## method call. Each operation is an atomic unit; the method as a
  ## whole is NOT atomic (lines 1947–1952).

  accountId*: AccountId
    ## The identifier of the account to use.
    ## RFC §5.3 (line 1866): "accountId: Id"

  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state; otherwise the method
    ## is aborted with a "stateMismatch" error (lines 2173–2174).
    ## If none, changes apply to the current state.
    ## RFC §5.3 (lines 1870–1877): "ifInState: String|null"

  create*: Opt[Table[CreationId, JsonNode]]
    ## A map of creation identifiers (temporary client-assigned) to
    ## entity data objects, or none if no objects are to be created.
    ## Entity data is JsonNode because Layer 3 Core cannot know T's
    ## serialisation format (Decision D3.6).
    ## RFC §5.3 (lines 1879–1888): "create: Id[Foo]|null"

  update*: Opt[Table[Id, PatchObject]]
    ## A map of record identifiers to PatchObject values representing
    ## the changes to apply, or none if no objects are to be updated.
    ## RFC §5.3 (lines 1890–1940): "update: Id[PatchObject]|null"

  destroy*: Opt[Referencable[seq[Id]]]
    ## A list of identifiers for records to permanently delete, or none
    ## if no objects are to be destroyed. Referencable: may be a direct
    ## seq or a result reference (e.g., ids from a previous /query).
    ## RFC §5.3 (lines 1942–1945): "destroy: Id[]|null"
```

**`toJson` signature:**

```nim
func toJson*[T](req: SetRequest[T]): JsonNode =
  ## Serialises SetRequest to JSON arguments object (RFC 8620 §5.3).
  ## Omits ``ifInState``, ``create``, ``update``, ``destroy`` when
  ## Opt.none. Dispatches Referencable destroy via referencableKey.
  ## Pattern L3-A (§5a.1).
  ...
```

### 6.4 CopyRequest[T]

**RFC reference:** §5.4 (lines 2191–2268)

```nim
type CopyRequest*[T] = object
  ## Request arguments for Foo/copy (RFC 8620 §5.4, lines 2191–2268).
  ## Copies records from one account to another. The only way to move
  ## records between accounts (lines 2191–2194).

  fromAccountId*: AccountId
    ## The identifier of the account to copy records from.
    ## RFC §5.4 (lines 2213–2214): "fromAccountId: Id"

  ifFromInState*: Opt[JmapState]
    ## If supplied, must match the current state of the from-account
    ## when reading data; otherwise "stateMismatch" (lines 2217–2224).
    ## RFC §5.4 (lines 2217–2224): "ifFromInState: String|null"

  accountId*: AccountId
    ## The identifier of the account to copy records to. Must differ
    ## from fromAccountId (line 2229).
    ## RFC §5.4 (lines 2226–2229): "accountId: Id"

  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state of the destination
    ## account; otherwise "stateMismatch" (lines 2231–2237).
    ## RFC §5.4 (lines 2231–2237): "ifInState: String|null"

  create*: Table[CreationId, JsonNode]
    ## A map of creation identifiers to entity data objects. Required
    ## (not optional). Each Foo object MUST contain an "id" property
    ## referencing the record in the from-account (lines 2247–2253).
    ## RFC §5.4 (lines 2247–2253): "create: Id[Foo]"

  onSuccessDestroyOriginal*: bool
    ## If true, the server attempts to destroy the originals after
    ## successful copies via an implicit Foo/set call (lines 2255–2262).
    ## The copy and destroy are NOT atomic (lines 2196–2199).
    ## RFC §5.4 (lines 2255–2262): "onSuccessDestroyOriginal: Boolean"

  destroyFromIfInState*: Opt[JmapState]
    ## Passed as "ifInState" to the implicit Foo/set call when
    ## onSuccessDestroyOriginal is true (lines 2264–2268).
    ## RFC §5.4 (lines 2264–2268): "destroyFromIfInState: String|null"
```

**`toJson` signature:**

```nim
func toJson*[T](req: CopyRequest[T]): JsonNode =
  ## Serialises CopyRequest to JSON arguments object (RFC 8620 §5.4).
  ## ``create`` is required (always emitted). Omits optional fields
  ## when Opt.none. ``onSuccessDestroyOriginal`` always emitted.
  ## Pattern L3-A (§5a.1).
  ...
```

### 6.5 QueryRequest[T]

**RFC reference:** §5.5 (lines 2339–2516)

```nim
type QueryRequest*[T] = object
  ## Request arguments for Foo/query (RFC 8620 §5.5, lines 2339–2516).
  ## Searches, sorts, and windows the data type on the server, returning
  ## a list of identifiers matching the criteria.

  accountId*: AccountId
    ## The identifier of the account to use.
    ## RFC §5.5 (lines 2363–2364): "accountId: Id"

  filter*: Opt[Filter[filterType(T)]]
    ## Determines the set of Foos returned. If none, all objects of
    ## this type in the account are included. Generic over
    ## filterType(T) — the associated filter condition type for entity T.
    ## RFC §5.5 (lines 2368–2394): "filter: FilterOperator|FilterCondition|null"

  sort*: Opt[seq[Comparator]]
    ## Sort criteria. If none or empty, sort order is server-dependent
    ## but must be stable between calls (lines 2402–2404).
    ## RFC §5.5 (lines 2396–2462): "sort: Comparator[]|null"

  position*: JmapInt
    ## The zero-based index of the first identifier in the full results
    ## to return. Default: 0. Negative values are offset from the end,
    ## clamped to 0 (lines 2476–2480). Ignored if anchor is supplied
    ## (lines 2534–2536).
    ## RFC §5.5 (lines 2471–2484): "position: Int"

  anchor*: Opt[Id]
    ## A Foo identifier. If supplied, position is ignored (lines 2534–2536).
    ## The index of this identifier in the results, combined with
    ## anchorOffset, determines the first result to return.
    ## RFC §5.5 (lines 2486–2491): "anchor: Id|null"

  anchorOffset*: JmapInt
    ## The index of the first result relative to the anchor's index.
    ## May be negative. Default: 0. Ignored if no anchor is supplied
    ## (lines 2535–2536).
    ## RFC §5.5 (lines 2493–2499): "anchorOffset: Int"

  limit*: Opt[UnsignedInt]
    ## The maximum number of results to return. If none, no limit
    ## presumed. The server may enforce its own maximum (lines 2504–2506).
    ## Note: the RFC specifies ``invalidArguments`` for negative values
    ## (lines 2507–2509), but this library's ``UnsignedInt`` type
    ## prevents negative construction.
    ## RFC §5.5 (lines 2501–2509): "limit: UnsignedInt|null"

  calculateTotal*: bool
    ## Whether the client wishes to know the total number of results.
    ## May be slow and expensive for servers (lines 2513–2516).
    ## Default: false.
    ## RFC §5.5 (lines 2511–2516): "calculateTotal: Boolean"
```

**`toJson` signature:**

```nim
func toJson*[T](req: QueryRequest[T]): JsonNode =
  ## Serialises QueryRequest to JSON arguments object (RFC 8620 §5.5).
  ## Omits ``filter``, ``sort``, ``anchor``, ``limit`` when Opt.none.
  ## ``position``, ``anchorOffset``, ``calculateTotal`` always emitted.
  ## Filter serialised via callback for generic Filter[C].
  ## Pattern L3-A (§5a.1).
  ...
```

### 6.6 QueryChangesRequest[T]

**RFC reference:** §5.6 (lines 2639–2685)

```nim
type QueryChangesRequest*[T] = object
  ## Request arguments for Foo/queryChanges (RFC 8620 §5.6, lines 2639–2685).
  ## Efficiently updates a cached query to match the new server state.

  accountId*: AccountId
    ## The identifier of the account to use.
    ## RFC §5.6 (lines 2645–2646): "accountId: Id"

  filter*: Opt[Filter[filterType(T)]]
    ## The filter argument that was used with the original Foo/query.
    ## Generic over filterType(T).
    ## RFC §5.6 (lines 2649–2651): "filter: FilterOperator|FilterCondition|null"

  sort*: Opt[seq[Comparator]]
    ## The sort argument that was used with the original Foo/query.
    ## RFC §5.6 (lines 2653–2655): "sort: Comparator[]|null"

  sinceQueryState*: JmapState
    ## The current state of the query in the client, as returned by a
    ## previous Foo/query response with the same sort/filter.
    ## RFC §5.6 (lines 2657–2662): "sinceQueryState: String"

  maxChanges*: Opt[UnsignedInt]
    ## The maximum number of changes to return. Each item in the
    ## removed or added arrays counts as one change (lines 2810–2812).
    ## Same representability gap as ChangesRequest.maxChanges: RFC
    ## requires > 0 but ``UnsignedInt`` permits 0 (see §15).
    ## RFC §5.6 (lines 2664–2667): "maxChanges: UnsignedInt|null"

  upToId*: Opt[Id]
    ## The last (highest-index) identifier the client has cached.
    ## Optimisation: only applies when sort and filter are both on
    ## immutable properties (lines 2674–2678).
    ## RFC §5.6 (lines 2669–2678): "upToId: Id|null"

  calculateTotal*: bool
    ## Whether the client wishes to know the total number of results.
    ## Default: false.
    ## RFC §5.6 (lines 2680–2685): "calculateTotal: Boolean"
```

**`toJson` signature:**

```nim
func toJson*[T](req: QueryChangesRequest[T]): JsonNode =
  ## Serialises QueryChangesRequest to JSON arguments object
  ## (RFC 8620 §5.6). Omits ``filter``, ``sort``, ``maxChanges``,
  ## ``upToId`` when Opt.none. ``calculateTotal`` always emitted.
  ## Filter serialised via callback for generic Filter[C].
  ## Pattern L3-A (§5a.1).
  ...
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
RFC section and line numbers. Each type receives a `fromJson` function
following Pattern L3-B (Section 5a.2). No `toJson` is provided —
response types are parsed by the client, never serialised (Decision D3.7).

### 7.1 GetResponse[T]

**RFC reference:** §5.1 (lines 1613–1658)

```nim
type GetResponse*[T] = object
  ## Response arguments for Foo/get (RFC 8620 §5.1, lines 1613–1658).
  ## Contains the requested objects and any identifiers not found.

  accountId*: AccountId
    ## The identifier of the account used for the call.
    ## RFC §5.1 (lines 1615–1617): "accountId: Id"

  state*: JmapState
    ## A string representing the state on the server for ALL data of
    ## this type in the account (not just the returned objects). If
    ## the data changes, this string MUST change (lines 1632–1637).
    ## RFC §5.1 (lines 1631–1641): "state: String"

  list*: seq[JsonNode]
    ## The Foo objects requested. Raw JsonNode entities — entity-specific
    ## parsing is the caller's responsibility (Decision D3.6). Empty
    ## array if no objects were found or if ids was empty (line 1646).
    ## Results MAY be in a different order to the ids in the request
    ## (lines 1647–1648).
    ## RFC §5.1 (lines 1643–1651): "list: Foo[]"

  notFound*: seq[Id]
    ## Identifiers passed to the method for records that do not exist.
    ## Empty if all requested identifiers were found or if ids was null
    ## or empty (lines 1656–1658).
    ## RFC §5.1 (lines 1653–1658): "notFound: Id[]"
```

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[GetResponse[T]], node: JsonNode
): Result[GetResponse[T], ValidationError] =
  ## Deserialises JSON arguments to GetResponse (RFC 8620 §5.1).
  ## Uses lenient constructors for server-assigned identifiers.
  ## ``list`` contains raw JsonNode entities.
  ## Pattern L3-B (§5a.2).
  ...
```

### 7.2 ChangesResponse[T]

**RFC reference:** §5.2 (lines 1704–1764)

```nim
type ChangesResponse*[T] = object
  ## Response arguments for Foo/changes (RFC 8620 §5.2, lines 1704–1764).
  ## Lists identifiers for records that have been created, updated, or
  ## destroyed since the given state.

  accountId*: AccountId
    ## The identifier of the account used for the call.
    ## RFC §5.2 (lines 1706–1707): "accountId: Id"

  oldState*: JmapState
    ## The "sinceState" argument echoed back — the state from which the
    ## server is returning changes.
    ## RFC §5.2 (lines 1710–1713): "oldState: String"

  newState*: JmapState
    ## The state the client will be in after applying the changes.
    ## RFC §5.2 (lines 1715–1718): "newState: String"

  hasMoreChanges*: bool
    ## If true, the client may call Foo/changes again with newState
    ## to get further updates. If false, newState is current.
    ## RFC §5.2 (lines 1720–1724): "hasMoreChanges: Boolean"

  created*: seq[Id]
    ## Identifiers for records created since the old state.
    ## RFC §5.2 (lines 1726–1729): "created: Id[]"

  updated*: seq[Id]
    ## Identifiers for records updated since the old state.
    ## RFC §5.2 (lines 1731–1734): "updated: Id[]"

  destroyed*: seq[Id]
    ## Identifiers for records destroyed since the old state.
    ## RFC §5.2 (lines 1743–1746): "destroyed: Id[]"
```

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[ChangesResponse[T]], node: JsonNode
): Result[ChangesResponse[T], ValidationError] =
  ## Deserialises JSON arguments to ChangesResponse (RFC 8620 §5.2).
  ## ``initResultErr`` for JmapState ``{.requiresInit.}`` fields.
  ## Pattern L3-B (§5a.2).
  ...
```

### 7.3 SetResponse[T]

**RFC reference:** §5.3 (lines 2009–2082), Decision 3.9B

```nim
type SetResponse*[T] = object
  ## Response arguments for Foo/set (RFC 8620 §5.3, lines 2009–2082).
  ## Wire format uses parallel maps (created/notCreated, etc.); the
  ## internal representation merges these into unified Result maps
  ## (Decision 3.9B). Merging algorithm specified in Section 8.

  accountId*: AccountId
    ## The identifier of the account used for the call.
    ## RFC §5.3 (lines 2011–2013): "accountId: Id"

  oldState*: Opt[JmapState]
    ## The state before making the requested changes, or none if the
    ## server does not know the previous state (lines 2025–2027).
    ## RFC §5.3 (lines 2023–2027): "oldState: String|null"

  newState*: JmapState
    ## The state that will now be returned by Foo/get.
    ## RFC §5.3 (lines 2029–2031): "newState: String"

  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged map of create outcomes. Wire ``created`` entries become
    ## ``Result.ok(entityJson)``; wire ``notCreated`` entries become
    ## ``Result.err(setError)``. Entity data is raw JsonNode
    ## (Decision D3.6). Server-set properties (e.g., "id") are in the
    ## ok value (lines 2035–2039).
    ## RFC §5.3 (lines 2033–2041, 2060–2063): "created" + "notCreated"

  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
    ## Merged map of update outcomes. Wire ``updated`` entries with
    ## null value become ``Result.ok(Opt.none(JsonNode))``; non-null
    ## values become ``Result.ok(Opt.some(entityJson))`` containing
    ## server-changed properties. Wire ``notUpdated`` entries become
    ## ``Result.err(setError)`` (lines 2043–2053).
    ## RFC §5.3 (lines 2043–2053, 2065–2068): "updated" + "notUpdated"

  destroyResults*: Table[Id, Result[void, SetError]]
    ## Merged map of destroy outcomes. Wire ``destroyed`` entries become
    ## ``Result.ok()``; wire ``notDestroyed`` entries become
    ## ``Result.err(setError)`` (lines 2055–2058).
    ## RFC §5.3 (lines 2055–2058, 2079–2082): "destroyed" + "notDestroyed"
```

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[SetResponse[T]], node: JsonNode
): Result[SetResponse[T], ValidationError] =
  ## Deserialises JSON arguments to SetResponse (RFC 8620 §5.3).
  ## Merges parallel wire maps into unified Result maps (§8).
  ## ``{.cast(noSideEffect).}:`` required for create and update
  ## merging (Result maps contain JsonNode, a ref type).
  ## Pattern L3-B (§5a.2) + Pattern L3-C (§5a.3).
  ...
```

### 7.4 CopyResponse[T]

**RFC reference:** §5.4 (lines 2273–2323)

```nim
type CopyResponse*[T] = object
  ## Response arguments for Foo/copy (RFC 8620 §5.4, lines 2273–2323).
  ## Structurally similar to SetResponse but only has create results
  ## (copies are creates in the destination account).

  fromAccountId*: AccountId
    ## The identifier of the account records were copied from.
    ## RFC §5.4 (lines 2275–2277): "fromAccountId: Id"

  accountId*: AccountId
    ## The identifier of the account records were copied to.
    ## RFC §5.4 (lines 2279–2281): "accountId: Id"

  oldState*: Opt[JmapState]
    ## The state of the destination account before the copy, or none
    ## if the server does not know the previous state.
    ## RFC §5.4 (lines 2283–2288): "oldState: String|null"

  newState*: JmapState
    ## The state that will now be returned by Foo/get on the
    ## destination account.
    ## RFC §5.4 (lines 2290–2293): "newState: String"

  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged map of copy outcomes. Wire ``created`` entries become
    ## ``Result.ok(entityJson)``; wire ``notCreated`` entries become
    ## ``Result.err(setError)``. Uses the same merging algorithm as
    ## SetResponse (create branch only, Section 8).
    ## RFC §5.4 (lines 2303–2310, 2312–2315): "created" + "notCreated"
```

**Cross-reference.** `CopyResponse.createResults` merging follows the
identical algorithm as `SetResponse` Section 8 (create branch only). The
`alreadyExists` SetError type with `existingId` field (§5.4 lines
2320–2323) is handled by Layer 1's `setErrorAlreadyExists` constructor.

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[CopyResponse[T]], node: JsonNode
): Result[CopyResponse[T], ValidationError] =
  ## Deserialises JSON arguments to CopyResponse (RFC 8620 §5.4).
  ## Merges created/notCreated wire maps into unified Result map (§8).
  ## ``{.cast(noSideEffect).}:`` required (Result map contains JsonNode).
  ## Pattern L3-B (§5a.2) + Pattern L3-C (§5a.3).
  ...
```

### 7.5 QueryResponse[T]

**RFC reference:** §5.5 (lines 2541–2614)

```nim
type QueryResponse*[T] = object
  ## Response arguments for Foo/query (RFC 8620 §5.5, lines 2541–2614).
  ## Returns a windowed list of identifiers matching the query criteria.

  accountId*: AccountId
    ## The identifier of the account used for the call.
    ## RFC §5.5 (lines 2543–2545): "accountId: Id"

  queryState*: JmapState
    ## A string encoding the current state of the query on the server.
    ## MUST change if the results (matching identifiers and sort order)
    ## have changed (lines 2549–2550). Only meaningful when compared to
    ## future responses with the same type/sort/filter (lines 2556–2563).
    ## RFC §5.5 (lines 2547–2563): "queryState: String"

  canCalculateChanges*: bool
    ## True if the server supports calling Foo/queryChanges with these
    ## filter/sort parameters. Does not guarantee the call will succeed
    ## (lines 2586–2589).
    ## RFC §5.5 (lines 2583–2589): "canCalculateChanges: Boolean"

  position*: UnsignedInt
    ## The zero-based index of the first result in the ids array within
    ## the complete list of query results.
    ## RFC §5.5 (lines 2591–2594): "position: UnsignedInt"

  ids*: seq[Id]
    ## The list of identifiers for each Foo in the query results,
    ## starting at position and continuing until the end of results or
    ## the limit is reached. Empty if position >= total (line 2601).
    ## RFC §5.5 (lines 2596–2602): "ids: Id[]"

  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request (lines 2607–2608).
    ## RFC §5.5 (lines 2604–2608): "total: UnsignedInt"

  limit*: Opt[UnsignedInt]
    ## The limit enforced by the server. Only returned if the server
    ## set a limit or used a different limit than requested
    ## (lines 2612–2614).
    ## RFC §5.5 (lines 2610–2614): "limit: UnsignedInt"
```

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[QueryResponse[T]], node: JsonNode
): Result[QueryResponse[T], ValidationError] =
  ## Deserialises JSON arguments to QueryResponse (RFC 8620 §5.5).
  ## ``total`` and ``limit`` use lenient Opt handling (absent → none).
  ## Pattern L3-B (§5a.2).
  ...
```

### 7.6 QueryChangesResponse[T]

**RFC reference:** §5.6 (lines 2695–2796)

```nim
type QueryChangesResponse*[T] = object
  ## Response arguments for Foo/queryChanges (RFC 8620 §5.6,
  ## lines 2695–2796). Allows a client to update a cached query to
  ## match the new server state via a splice algorithm (lines 2773–2796).

  accountId*: AccountId
    ## The identifier of the account used for the call.
    ## RFC §5.6 (lines 2697–2699): "accountId: Id"

  oldQueryState*: JmapState
    ## The "sinceQueryState" argument echoed back — the state from
    ## which the server is returning changes.
    ## RFC §5.6 (lines 2701–2704): "oldQueryState: String"

  newQueryState*: JmapState
    ## The state the query will be in after applying the changes.
    ## RFC §5.6 (lines 2706–2709): "newQueryState: String"

  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request (lines 2714–2715).
    ## RFC §5.6 (lines 2711–2715): "total: UnsignedInt"

  removed*: seq[Id]
    ## Identifiers for every Foo that was in the query results in the
    ## old state but is not in the new state. The server MAY include
    ## extra identifiers that may have been in old results (lines 2722–2724).
    ## RFC §5.6 (lines 2717–2735): "removed: Id[]"

  added*: seq[AddedItem]
    ## The identifier and index in the new query results for every Foo
    ## that has been added since the old state AND every Foo in the
    ## current results that was included in removed (due to mutable
    ## property changes). Sorted by index, lowest first (line 2764).
    ## RFC §5.6 (lines 2751–2771): "added: AddedItem[]"
```

**`fromJson` signature:**

```nim
func fromJson*[T](
    R: typedesc[QueryChangesResponse[T]], node: JsonNode
): Result[QueryChangesResponse[T], ValidationError] =
  ## Deserialises JSON arguments to QueryChangesResponse (RFC 8620 §5.6).
  ## ``total`` uses lenient Opt handling (absent → none).
  ## ``added`` elements parsed via AddedItem.fromJson (Layer 2).
  ## Pattern L3-B (§5a.2).
  ...
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

**Architecture decision:** 3.9B (unified Result maps internally, parallel
maps on the wire)

**RFC reference:** §5.3 (lines 2009–2082) — the wire format uses six
parallel maps: `created`/`notCreated`, `updated`/`notUpdated`,
`destroyed`/`notDestroyed`. The internal representation merges each pair
into a single `Table[K, Result[V, SetError]]`.

### 8.1 Create Merging

Wire: `created: Id[Foo]|null` + `notCreated: Id[SetError]|null`
Internal: `Table[CreationId, Result[JsonNode, SetError]]`

```nim
## Algorithm (inside {.cast(noSideEffect).}:):
## 1. Parse ``created`` via node{"created"}:
##    - nil or JNull → empty
##    - JObject → iterate pairs: for each (cid, entity):
##      parse CreationId from key; add tbl[cid] = Result.ok(entity)
## 2. Parse ``notCreated`` via node{"notCreated"}:
##    - nil or JNull → empty
##    - JObject → iterate pairs: for each (cid, errNode):
##      parse CreationId from key; parse SetError from errNode;
##      add tbl[cid] = Result.err(setError)
## 3. Return the merged table.
```

### 8.2 Update Merging

Wire: `updated: Id[Foo|null]|null` + `notUpdated: Id[SetError]|null`
Internal: `Table[Id, Result[Opt[JsonNode], SetError]]`

```nim
## Algorithm (inside {.cast(noSideEffect).}:):
## 1. Parse ``updated`` via node{"updated"}:
##    - nil or JNull → empty
##    - JObject → iterate pairs: for each (id, val):
##      parse Id from key;
##      if val is JNull → tbl[id] = Result.ok(Opt.none(JsonNode))
##      else → tbl[id] = Result.ok(Opt.some(val))
## 2. Parse ``notUpdated`` via node{"notUpdated"}:
##    - nil or JNull → empty
##    - JObject → iterate pairs: for each (id, errNode):
##      parse Id from key; parse SetError from errNode;
##      add tbl[id] = Result.err(setError)
## 3. Return the merged table.
```

The `Opt[JsonNode]` in the success branch encodes the RFC semantics:
`null` in the `updated` map means "no server-set properties changed"
(line 2050), while a non-null value contains the properties that changed
in a way not explicitly requested (lines 2048–2051).

### 8.3 Destroy Merging

Wire: `destroyed: Id[]|null` + `notDestroyed: Id[SetError]|null`
Internal: `Table[Id, Result[void, SetError]]`

```nim
## Algorithm (NO cast needed — Result[void, SetError] has no ref values):
## 1. Parse ``destroyed`` via node{"destroyed"}:
##    - nil or JNull → empty
##    - JArray → iterate elements: for each elem:
##      parse Id from elem; add tbl[id] = Result[void, SetError].ok()
## 2. Parse ``notDestroyed`` via node{"notDestroyed"}:
##    - nil or JNull → empty
##    - JObject → iterate pairs: for each (id, errNode):
##      parse Id from key; parse SetError from errNode;
##      add tbl[id] = Result[void, SetError].err(setError)
## 3. Return the merged table.
```

### 8.4 Cast Boundaries

| Merging branch | `{.cast(noSideEffect).}:` needed | Reason |
|---------------|----------------------------------|--------|
| Create | Yes | `Result[JsonNode, SetError]` contains `JsonNode` (ref type) |
| Update | Yes | `Result[Opt[JsonNode], SetError]` contains `JsonNode` (ref type) |
| Destroy | No | `Result[void, SetError]` contains no ref values |

The cast boundary is placed around the `var Table` construction loop.
The mutation is local (building a return value) and does not escape
through `ref` indirection — same safety justification as Layer 2's
Pattern A.

### 8.5 Invariants

- **Completeness:** Every identifier from both success and failure wire
  maps is present in the merged table. No entries are dropped.
- **Last-writer-wins:** If an identifier appears in both the success and
  failure map (a server bug), the last-processed map's entry overwrites
  the first. Failure maps are processed second, so errors take precedence.
  This is defensive — the RFC does not permit duplicates across the
  parallel maps, but robustness demands a defined behaviour.
- **SetError fidelity:** `SetError.fromJson` preserves `rawType` and
  `extras` for lossless round-trip (Decision 1.7C). Unknown error types
  map to `setUnknown` with `rawType` preservation.
- **CopyResponse reuse:** `CopyResponse.fromJson` uses the identical
  create-merging algorithm. Only the create branch is needed; update and
  destroy branches do not apply to /copy responses.

**Module:** `methods.nim` (inside `SetResponse.fromJson` and
`CopyResponse.fromJson`)

---

## 9. Core/echo Method

**RFC reference:** §4 (lines 1540–1561)

The `Core/echo` method returns exactly the same arguments as given. It is
used for testing connectivity to the JMAP API endpoint.

**Builder function:** `addEcho` (Section 2.6.1) adds a `Core/echo`
invocation with capability `"urn:ietf:params:jmap:core"`.

**Response extraction:** `get(resp, handle, echoFromJson)` where
`echoFromJson` validates `node.kind == JObject` and returns `ok(node)`.

```nim
func echoFromJson*(node: JsonNode): Result[JsonNode, ValidationError] =
  ## Callback for Core/echo response extraction (RFC 8620 §4).
  ## Validates that the response is a JSON object, returns it as-is.
  ## Parse-don't-validate exception: echo returns raw JsonNode because
  ## its structure is client-determined.
  checkJsonKind(node, JObject, "Core/echo")
  ok(node)
```

**Parse-don't-validate exception.** Echo returns raw `JsonNode` because
its structure is client-determined. Layer 3 Core cannot define a schema.
Callers must validate the shape themselves using their own parsing logic.

**Wire format example (RFC §4.1):**

```json
Request:  [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
Response: [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
```

**Module:** `addEcho` lives in `builder.nim`; `echoFromJson` lives in
`dispatch.nim` (response-side callback, used with `get[T]`).

---

## 10. Result Reference Construction

**Architecture decision:** 3.10A (string paths with constants, no
validation)

**RFC reference:** §3.7 (lines 1220–1493) — result references allow a
method call to refer to the output of a previous call's response within
the same request. The server resolves the JSON Pointer path against the
referenced response before executing the referencing call.

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

### 10.2 Generic Reference Construction

```nim
func reference*[T](handle: ResponseHandle[T], path: string,
    responseName: string): ResultReference =
  ## Constructs a ResultReference from a response handle, a JSON Pointer
  ## path, and the expected response name. No path validation is
  ## performed (Decision 3.10A) — the server validates the path at
  ## resolution time.
  ##
  ## RFC reference: §3.7 (lines 1220–1260)
  ResultReference(resultOf: MethodCallId(handle),
                  name: responseName, path: path)
```

The `responseName` parameter is explicit rather than auto-derived from
`T` because different methods produce different response names (e.g.,
`"Mailbox/query"` vs `"Mailbox/get"`), and the phantom type `T` encodes
the response type, not the method name (Decision D3.10).

### 10.3 Type-Safe Convenience Functions

```nim
func referenceIds*[T](
    handle: ResponseHandle[QueryResponse[T]]
): ResultReference =
  ## Constructs a reference to /ids from a Foo/query response.
  ## Canonical use: pass query result identifiers to a subsequent Foo/get.
  ##
  ## RFC reference: §3.7, path "/ids"
  mixin methodNamespace
  handle.reference(RefPathIds, methodNamespace(T) & "/query")

func referenceListIds*[T](
    handle: ResponseHandle[GetResponse[T]]
): ResultReference =
  ## Constructs a reference to /list/*/id from a Foo/get response.
  ## Extracts the identifiers of all returned objects.
  ##
  ## RFC reference: §3.7, path "/list/*/id"
  mixin methodNamespace
  handle.reference(RefPathListIds, methodNamespace(T) & "/get")

func referenceAddedIds*[T](
    handle: ResponseHandle[QueryChangesResponse[T]]
): ResultReference =
  ## Constructs a reference to /added/*/id from a Foo/queryChanges response.
  ## Extracts the identifiers of all added items.
  ##
  ## RFC reference: §3.7, path "/added/*/id"
  mixin methodNamespace
  handle.reference(RefPathAddedIds, methodNamespace(T) & "/queryChanges")
```

**Convenience function coverage.** Convenience functions are provided for
the three paths that feed the canonical query-to-get and query-to-set
workflows (Decision D3.5): `referenceIds` (query → get),
`referenceListIds` (get → set), `referenceAddedIds` (queryChanges → get).
The remaining three constants (`RefPathCreated`, `RefPathUpdated`,
`RefPathUpdatedProperties`) are available for use with the generic
`reference()` function (§10.2) when constructing less common reference
patterns via Layer 1 types.

### 10.4 Integration Example

```nim
## Query → Get chain: fetch all Mailbox ids, then retrieve the objects.
var b = initRequestBuilder()
let qh = b.addQuery[Mailbox](accountId)
let idsRef = qh.referenceIds()
let gh = b.addGet[Mailbox](accountId,
    ids = Opt.some(referenceTo[seq[Id]](idsRef)))
let req = b.build()
## req.using == @["urn:ietf:params:jmap:mail"]
## req.methodCalls[0].name == "Mailbox/query"
## req.methodCalls[1].arguments{"#ids"} contains the ResultReference
```

**Module:** `dispatch.nim`

---

## 11. Round-Trip Invariants

Layer 3 has unidirectional serialisation (request `toJson`, response
`fromJson`), so classical round-trip (`fromJson(toJson(x)) == x`) does
not apply per-type. Instead, the following invariants hold:

1. **Request identity.** For any `GetRequest[T]` value `r`, if a
   `fromJson` were added for testing, `GetRequest[T].fromJson(r.toJson()).get() == r`
   must hold. The same applies to all six request types.

2. **Builder identity.** `builder.build().toJson()` produces valid JMAP
   request JSON. Parsing it back via `Request.fromJson` (Layer 2)
   recovers the envelope structure — method calls, capabilities, and
   creation IDs all round-trip.

3. **Response identity.** For any valid server response JSON `j`,
   `GetResponse[T].fromJson(j)` produces an `ok` value whose fields
   match the JSON content. The same applies to all six response types.

4. **SetResponse losslessness.** Merging preserves ALL success AND
   failure entries. No entries are lost. `Result.ok` maps back to
   `created`/`updated`/`destroyed`; `Result.err` maps back to
   `notCreated`/`notUpdated`/`notDestroyed`.

5. **Opt omission symmetry.** `Opt.none` produces no key in `toJson`;
   absent key produces `Opt.none` in `fromJson`.

6. **Referencable dispatch.** `rkDirect` serialises without `#` prefix;
   `rkReference` serialises with `#` prefix. Round-trips preserve the
   variant.

7. **Method error preservation.** `MethodError.fromJson(errorJson)`
   preserves `rawType` (lossless, same as Layer 1/Layer 2 error types).

---

## 12. Opt[T] Field Handling Convention

### 12.1 Leniency Policy

Same policy as §5a.5 — see there for the full statement including the
structurally critical vs supplementary field distinction, the
container-field exception, and the rationale.

**Convention:** Same as Layer 2 §9. `toJson`: omit key when `isNone`.
`fromJson`: absent/wrong-kind produces `Opt.none` (lenient).

### 12.2 Per-Field Table

Every `Opt` field across all twelve Layer 3 types, with its serialisation
handling:

| Type | Field | Direction | Handling |
|------|-------|-----------|----------|
| `GetRequest[T]` | `ids` | `toJson` | Omit key if none |
| `GetRequest[T]` | `properties` | `toJson` | Omit key if none |
| `ChangesRequest[T]` | `maxChanges` | `toJson` | Omit key if none |
| `SetRequest[T]` | `ifInState` | `toJson` | Omit key if none |
| `SetRequest[T]` | `create` | `toJson` | Omit key if none |
| `SetRequest[T]` | `update` | `toJson` | Omit key if none |
| `SetRequest[T]` | `destroy` | `toJson` | Omit key if none |
| `CopyRequest[T]` | `ifFromInState` | `toJson` | Omit key if none |
| `CopyRequest[T]` | `ifInState` | `toJson` | Omit key if none |
| `CopyRequest[T]` | `destroyFromIfInState` | `toJson` | Omit key if none |
| `QueryRequest[T]` | `filter` | `toJson` | Omit key if none |
| `QueryRequest[T]` | `sort` | `toJson` | Omit key if none |
| `QueryRequest[T]` | `anchor` | `toJson` | Omit key if none |
| `QueryRequest[T]` | `limit` | `toJson` | Omit key if none |
| `QueryChangesRequest[T]` | `filter` | `toJson` | Omit key if none |
| `QueryChangesRequest[T]` | `sort` | `toJson` | Omit key if none |
| `QueryChangesRequest[T]` | `maxChanges` | `toJson` | Omit key if none |
| `QueryChangesRequest[T]` | `upToId` | `toJson` | Omit key if none |
| `SetResponse[T]` | `oldState` | `fromJson` | Absent/wrong kind produces `Opt.none` |
| `CopyResponse[T]` | `oldState` | `fromJson` | Absent/wrong kind produces `Opt.none` |
| `QueryResponse[T]` | `total` | `fromJson` | Absent/wrong kind produces `Opt.none` |
| `QueryResponse[T]` | `limit` | `fromJson` | Absent/wrong kind produces `Opt.none` |
| `QueryChangesResponse[T]` | `total` | `fromJson` | Absent/wrong kind produces `Opt.none` |

---

## 13. Module File Layout

**Decision D3.8:** Five source files (4 content + 1 re-export hub),
mirroring the Layer 1/Layer 2 module pattern.

### 13.1 Source Files

```
src/jmap_client/
  entity.nim      — Entity type framework: registerJmapEntity template,
                    methodNamespace/capabilityUri/filterType overload
                    patterns, mixin documentation
  methods.nim     — 12 request/response type definitions, toJson (6 request
                    types), fromJson (6 response types), SetResponse
                    merging algorithm, CopyResponse merging
  builder.nim     — RequestBuilder type, initRequestBuilder, build, nextId,
                    addCapability, addInvocation, addEcho, addGet,
                    addChanges, addSet, addCopy, addQuery, addQueryChanges
  dispatch.nim    — ResponseHandle[T] type, borrowed ops, get[T] extraction,
                    echoFromJson callback, reference construction
                    (reference, referenceIds, referenceListIds,
                    referenceAddedIds)
  protocol.nim    — Re-export hub; imports and re-exports entity, methods,
                    builder, dispatch
```

### 13.2 Import DAG

```
types.nim (L1 hub) ←── serialisation.nim (L2 hub)
                            ^       ^        ^        ^
                            |       |        |        |
                         entity  methods  builder  dispatch
                            ^       ^     /  |     /  |
                            +───>───+   /    |   /    |
                            +──>──────/─>────+/──>────+
                                    +──>─────+──>─────+

protocol.nim re-exports all four
```

- `entity.nim` imports: `types`, `serialisation`
- `methods.nim` imports: `types`, `serialisation`, `entity`
- `builder.nim` imports: `types`, `serialisation`, `entity`, `methods`
- `dispatch.nim` imports: `types`, `serialisation`, `entity`, `methods`.
  Note: `dispatch.nim` uses response types (e.g., `GetResponse[T]`) only
  as phantom type parameters in `ResponseHandle[T]`, and
  `methodNamespace(T)` via `mixin` (resolved at caller scope). The
  `entity` and `methods` imports are included for forward declarations;
  an implementation may find them unnecessary if transitive imports
  suffice.
- `protocol.nim` imports + re-exports: `entity`, `methods`, `builder`,
  `dispatch`

No cycles. Each module independently testable.

### 13.3 Test Files

```
tests/protocol/
  tentity.nim      — Mock entity type satisfies framework requirements;
                     registerJmapEntity compile-time check; missing
                     overload detection
  tmethods.nim     — Request toJson for all 6 types; response fromJson
                     for all 6 types; SetResponse merging; CopyResponse
                     merging; edge cases
  tbuilder.nim     — Builder accumulation; call ID generation; capability
                     deduplication; build() pure projection; all 7 add*
                     functions; multi-entity requests
  tdispatch.nim    — Handle extraction; method error detection; railway
                     conversion; echoFromJson callback; reference
                     construction; type-safe convenience functions
```

### 13.4 Module Boilerplate

Every Layer 3 source module:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}
```

Every Layer 3 `func` must have a `##` docstring (nimalyzer `hasDoc`
rule). Comments and docstrings use British English spelling. Variable
names and code identifiers use US English spelling.

---

## 14. Test Fixtures

### 14.1 Golden Test 1: Query to Get with Result Reference

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

### 14.2 Golden Test 2: Set with Create/Update/Destroy

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

### 14.3 Golden Test 3: Response Dispatch

Parse a response JSON with two invocations and one error. Extract typed
responses using handles.

```json
{
  "methodResponses": [
    ["Mailbox/get", {
      "accountId": "A13824",
      "state": "state1",
      "list": [{"id": "mb1", "name": "Inbox"}],
      "notFound": []
    }, "c0"],
    ["error", {
      "type": "unknownMethod"
    }, "c1"]
  ],
  "sessionState": "75128aab4b1b"
}
```

**Expected behaviour:**

- `get(resp, handle0, callback).isOk` — successful extraction of
  `GetResponse[Mailbox]`
- `get(resp, handle1, callback).isErr` — method error detected via
  `name == "error"`
- Error result has `errorType == metUnknownMethod`
- Missing handle (e.g., `"c2"`) returns `err(serverFail)`

### 14.4 Golden Test 4: SetResponse Merging

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

**Expected parsed values:**

- `createResults` has 2 entries: `k1` is `ok(JsonNode)`, `k2` is
  `err(SetError)` with `setForbidden`
- `updateResults` has 3 entries: `id1` is `ok(Opt.none(JsonNode))`,
  `id2` is `ok(Opt.some(JsonNode))`, `id3` is `err(SetError)` with
  `setNotFound`
- `destroyResults` has 2 entries: `id4` is `ok()`, `id5` is
  `err(SetError)` with `setForbidden`
- `oldState.isSome` and `oldState.get == JmapState("state1")`
- `newState == JmapState("state2")`

### 14.5 Golden Test 5: Core/echo

Build echo request with arbitrary arguments. Parse echo response. Verify
arguments echoed back identically.

```json
{
  "methodResponses": [
    ["Core/echo", {
      "hello": true,
      "high": 5
    }, "c0"]
  ],
  "sessionState": "75128aab4b1b"
}
```

**Expected behaviour:**

- `get(resp, echoHandle, echoFromJson).isOk`
- Extracted `JsonNode` has `{"hello"}.getBool == true`
- Extracted `JsonNode` has `{"high"}.getBiggestInt == 5`

### 14.6 Edge Cases

| Component | Input | Expected | Reason |
|-----------|-------|----------|--------|
| **Builder** | `build()` with no calls | Empty `methodCalls`, empty `using` | Valid empty request |
| Builder | Two `addGet` calls | IDs `"c0"`, `"c1"` | Auto-increment |
| Builder | Same entity twice | Capability added once | Dedup via `notin` check |
| Builder | Two different entities | Both capabilities in `using` | Multi-capability |
| Builder | 100 calls | `"c99"` for last | Unbounded counter |
| Builder | `build()` called twice | Same `Request` both times | Pure projection, no mutation |
| Builder | `addGet` with all defaults | Only `accountId` in JSON | Opt omission |
| Builder | `addGet` with `ids = Opt.some(direct(@[id1, id2]))` | `"ids": ["id1", "id2"]` | Direct Referencable |
| Builder | `addGet` with `ids = Opt.some(referenceTo(ref))` | `"#ids": {"resultOf":..}` | Reference Referencable |
| Builder | `addSet` with create + destroy | Both fields in JSON | Multiple Opt.some |
| **Dispatch** | Response with error invocation | `err(MethodError)` | Error detection via `name == "error"` |
| Dispatch | Missing call ID in response | `err(MethodError)` serverFail | Not found |
| Dispatch | Correct response | `ok(T)` | Happy path |
| Dispatch | Handle from different request | May match wrong invocation | Documented gap |
| Dispatch | `fromArgs` callback returns err | `err(MethodError)` with description from `ValidationError` | Railway conversion |
| Dispatch | Malformed error response | `err(serverFail)` | `MethodError.fromJson` failed |
| **GetResponse** | Valid JSON with all fields | `ok(GetResponse)` | Happy path |
| GetResponse | Missing `state` field | `err` | Required field |
| GetResponse | `state` is JInt not JString | `err` | `checkJsonKind` rejects |
| GetResponse | `list` is JString not JArray | `err` | `checkJsonKind` rejects |
| GetResponse | `notFound` absent | `ok` with empty `notFound` | Supplementary required field — absent treated as empty |
| GetResponse | `list` empty | `ok` with empty `list` | No results (valid) |
| GetResponse | Extra unknown fields | `ok` (ignored) | Postel's law |
| GetResponse | `accountId` empty string | `err` | `parseAccountId` rejects |
| **ChangesResponse** | Valid JSON | `ok` | Happy path |
| ChangesResponse | `hasMoreChanges` = true | `.hasMoreChanges == true` | Partial sync |
| ChangesResponse | Missing `newState` | `err` | Required field |
| ChangesResponse | Empty `created`/`updated`/`destroyed` | `ok` with empty seqs | No changes |
| **SetResponse** | Both `created` and `notCreated` null | Empty `createResults` | Both absent |
| SetResponse | `created` has entries, `notCreated` null | All ok | Success only |
| SetResponse | `created` null, `notCreated` has entries | All err | Failure only |
| SetResponse | Both have entries | Mixed ok/err | Normal case |
| SetResponse | `updated` entry with null value | `ok(Opt.none(JsonNode))` | Server-set only changes |
| SetResponse | `updated` entry with object value | `ok(Opt.some(obj))` | Server property changes |
| SetResponse | `destroyed` empty array | Empty `destroyResults` | No destroys |
| SetResponse | `oldState` absent | `oldState.isNone` | Server does not know |
| SetResponse | `notCreated` value missing `type` | `err` | `SetError` requires type |
| SetResponse | `notCreated` value unknown type | err with `setUnknown` | `rawType` preserved |
| SetResponse | Same id in `created` and `notCreated` | Last writer wins (err) | Defensive — server bug |
| **CopyResponse** | All `notCreated` with `alreadyExists` | All err with `existingId` | Copy error |
| CopyResponse | `created` null, `notCreated` has entries | All err | All copies failed |
| CopyResponse | Valid `created` with server-set `id` | ok with entity JSON | Normal case |
| **QueryResponse** | `total` absent | `total.isNone` | `calculateTotal` false |
| QueryResponse | `limit` absent | `limit.isNone` | Server did not cap |
| QueryResponse | `ids` empty array | `@[]` | `position >= total` |
| QueryResponse | `position` is JString | `err` | `checkJsonKind` rejects |
| QueryResponse | `canCalculateChanges` missing | `err` | Required field |
| **QueryChangesResponse** | Valid with removed + added | `ok` | Happy path |
| QueryChangesResponse | Empty removed, non-empty added | `ok` | Additions only |
| QueryChangesResponse | `total` absent | `total.isNone` | `calculateTotal` false |
| QueryChangesResponse | `added` with invalid `index` | `err` | Propagated from `AddedItem.fromJson` |
| **Echo** | Any JSON object | Same object back | Identity |
| Echo | Nested JSON | Same nested structure back | Deep identity |
| Echo | Non-object JSON | `err` | `checkJsonKind` rejects (must be JObject) |
| **Reference** | `referenceIds` on query handle | `path == "/ids"`, `name == "T/query"` | Correct construction |
| Reference | `referenceListIds` on get handle | `path == "/list/*/id"`, `name == "T/get"` | Correct construction |
| Reference | `referenceAddedIds` on queryChanges handle | `path == "/added/*/id"`, `name == "T/queryChanges"` | Correct construction |
| Reference | Custom path via `reference()` | Arbitrary path preserved | No validation (3.10A) |
| **Request toJson** | `GetRequest` with all none | `{"accountId": "..."}` only | Opt omission |
| Request toJson | `SetRequest` with all operations | All 3 fields present | Full SetRequest |
| Request toJson | `QueryRequest` with filter | Filter serialised via callback | Generic Filter[C] |
| Request toJson | `CopyRequest` with `onSuccessDestroyOriginal = true` | `"onSuccessDestroyOriginal": true` | Boolean always emitted |
| Request toJson | `ChangesRequest` minimal | `accountId` + `sinceState` only | Simplest request |

**Total: 63 enumerated edge case rows.**

---

## 15. Design Decisions Summary

| ID | Decision | Alternative considered | Rationale |
|----|----------|----------------------|-----------|
| D3.1 | Layer 3 owns serialisation of Layer 3–defined types | Add new Layer 2 modules for Layer 3 types | Layer 3 types are generic over entity `T`; their serde depends on entity-specific resolution (`methodNamespace`, `filterType` templates) that only Layer 3 has. Layer 2 would need Layer 3–aware callbacks, creating a circular concern. |
| D3.2 | `add*` params match RFC request fields; required positional, optional defaulted | Single generic `addMethod(name, argsJson)` | Type-safe: compiler enforces correct parameters per method. Discoverable: IDE autocomplete shows available fields. Generic approach loses compile-time safety. |
| D3.3 | `get[T]` returns `Result[T, MethodError]` (inner railway) | `Result[T, ClientError]` (outer railway) | Method errors are data within a successful HTTP 200 response. They are per-invocation, not per-request. The outer railway (`ClientError`) is for transport/request failures at the Layer 4 boundary. Mixing them conflates different failure modes. |
| D3.4 | No concepts; plain overloaded `typedesc` procs + `registerJmapEntity` compile-time check | Concepts (3.5A) | Per `docs/design/notes/nim-concepts.md`: concepts experimental, known bugs (byref #16897, block scope), `func` not enforced in concept body, generic type checking unimplemented. Plain overloads + static registration template gives earlier error detection than concepts (registration site vs instantiation site) with zero compiler risk. |
| D3.5 | Only `GetRequest.ids` and `SetRequest.destroy` get `Referencable[T]` | All fields `Referencable` | Wrapping all fields is extremely verbose and rarely used. The two wrapped fields cover the canonical JMAP patterns (query to get, query to set destroy). Users needing uncommon references can construct `Request` manually via Layer 1 types. |
| D3.6 | Entity data as `JsonNode` in requests/responses | `seq[T]` with entity-specific callback | Layer 3 Core cannot know `T`'s deserialisation. Raw `JsonNode` preserves flexibility; entity-specific convenience functions are deferred to entity modules (RFC 8621). |
| D3.7 | Unidirectional serde: request `toJson`, response `fromJson` | Full round-trip for all types | Client builds requests and parses responses — never the reverse. Halves the serialisation surface. Round-trip testing uses the builder-build-parse chain, not per-type `fromJson(toJson(x))`. |
| D3.8 | 5 source files (4 content + 1 re-export hub) | Single `protocol.nim` or 2 files | Mirrors Layer 1/Layer 2 module pattern. Each file is independently testable with bounded size (~150–300 lines). Acyclic import graph. Single file would exceed 600 lines; 2 files would conflate builder logic with type definitions. |
| D3.9 | `nextId` uses `MethodCallId(s)` directly (bypassing validation) | `parseMethodCallId(s).get()` | The builder controls the format entirely (`"c0"`, `"c1"`, ...). These are provably valid MethodCallIds (non-empty, ASCII digits only). Using `.get()` would add an unnecessary `Defect` path for an impossible error. |
| D3.10 | `reference()` takes explicit `responseName` parameter | Auto-derive from `T` and method suffix | Different methods produce different response names (`"Mailbox/query"` vs `"Mailbox/get"`). Auto-deriving requires the `reference` function to know which method the handle came from, which the phantom type `T` (response type, not method type) does not encode. Explicit is unambiguous. |

### Known Representability Gap

**`maxChanges` permits 0.** The `maxChanges` fields in `ChangesRequest[T]`
(§6.2) and `QueryChangesRequest[T]` (§6.6) are typed as
`Opt[UnsignedInt]`. The RFC requires the value to be "a positive integer
greater than 0" (§5.2 lines 1694–1702), but `UnsignedInt` permits 0.
Servers reject 0 with `invalidArguments`. A future `PositiveInt` distinct
type with a smart constructor enforcing `> 0` could close this gap,
fully honouring the "make illegal states unrepresentable" principle. For
now, the gap is accepted: it is a single edge-case value that the server
rejects clearly, and introducing a new type has downstream cost.

---

## Appendix: RFC Section Cross-Reference

| Type/Function | RFC 8620 Section | Wire Format |
|---------------|-----------------|-------------|
| `RequestBuilder` | §3.3 (lines 882–974) | N/A (internal) |
| `ResponseHandle[T]` | §3.4 (lines 975–1035) | N/A (internal) |
| `registerJmapEntity` | §5 (lines 1575–1586) | N/A (compile-time) |
| `GetRequest[T]` | §5.1 (lines 1587–1612) | JSON Object |
| `GetResponse[T]` | §5.1 (lines 1613–1665) | JSON Object |
| `ChangesRequest[T]` | §5.2 (lines 1667–1703) | JSON Object |
| `ChangesResponse[T]` | §5.2 (lines 1704–1838) | JSON Object |
| `SetRequest[T]` | §5.3 (lines 1855–1945) | JSON Object |
| `SetResponse[T]` | §5.3 (lines 2009–2082) | JSON Object (parallel maps merged) |
| `CopyRequest[T]` | §5.4 (lines 2191–2268) | JSON Object |
| `CopyResponse[T]` | §5.4 (lines 2273–2338) | JSON Object (parallel maps merged) |
| `QueryRequest[T]` | §5.5 (lines 2339–2516) | JSON Object |
| `QueryResponse[T]` | §5.5 (lines 2541–2638) | JSON Object |
| `QueryChangesRequest[T]` | §5.6 (lines 2639–2685) | JSON Object |
| `QueryChangesResponse[T]` | §5.6 (lines 2695–2819) | JSON Object |
| Core/echo | §4 (lines 1540–1561) | JSON Object (arbitrary) |
| Call ID generation | §3.2 (lines 865–881) | `"c0"`, `"c1"`, ... |
| Result reference paths | §3.7 (lines 1220–1493) | JSON Pointer strings |
| SetResponse merging | §5.3 (lines 2009–2082) | Wire: parallel maps; Internal: Result maps |
