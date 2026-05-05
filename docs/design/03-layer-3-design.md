# Layer 3: Protocol Logic — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, serialisation pair, and
entity framework registration mechanism for Layer 3 of the jmap-client
library. It builds upon the decisions made in `00-architecture.md`, the
types defined in `01-layer-1-design.md`, and the serialisation
infrastructure established in `02-layer-2-design.md`.

**Scope.** Layer 3 covers: typed method names (`MethodName`,
`MethodEntity`, `RefPath` enums), the entity type framework (per-verb
resolvers, registration templates, `mixin` resolution), all six
standard method request/response types (RFC 8620 §5.1–5.6),
serialisation (`toJson`/`fromJson`) for all Layer 3–defined types, the
immutable request builder (`RequestBuilder` with `add*` functions and
call ID generation), response dispatch (`ResponseHandle[T]`,
`NameBoundHandle[T]`, `CompoundHandles[A, B]`, `ChainedHandles[A, B]`,
and `get[T]` extraction), result reference construction, and optional
pipeline combinators (`convenience.nim`). Transport (Layer 4), the C
ABI (Layer 5), binary data (§6), and push (§7) are out of scope. Layer
3 is the uppermost layer of the pure core — no I/O, no global state
mutation.

**Layer 3 modules.** `methods_enum.nim` (typed method names, entity
tags, reference paths), `entity.nim` (entity registration framework),
`methods.nim` (request and response types with serialisation),
`builder.nim` (immutable `RequestBuilder` with `add*` functions),
`dispatch.nim` (`ResponseHandle[T]`, `NameBoundHandle[T]`, compound and
chained handle pairs, `get[T]` and `getBoth` extraction),
`protocol.nim` (re-export hub), and `convenience.nim` (optional
pipeline combinators).

Layer 3 operates on Layer 1 types: `Invocation`, `Request`, `Response`,
`ResultReference`, `Referencable[T]`, `Filter[C]`, `Comparator`,
`AddedItem`, `QueryParams`, all identifier types (`Id`, `AccountId`,
`JmapState`, `MethodCallId`, `CreationId`), `MaxChanges`, and all error
types (`MethodError`, `SetError`, `ValidationError`, `ClientError`).
It imports Layer 2's serialisation infrastructure: `JsonPath`,
`SerdeViolation`, `expectKind`, `fieldJString`, `fieldJArray`,
`fieldJBool`, `fieldJInt`, `optJsonField`, `wrapInner`,
`toValidationError`, `parseIdArrayField`, `parseOptIdArray`,
`referencableKey`, `fromJsonField`, and all primitive/identifier
`toJson`/`fromJson` pairs.

**Design principles.** Every decision follows:

- **Three-railway error model** — see below.
- **Compiler-enforced purity and totality** — `{.push raises: [],
  noSideEffect.}` on every Layer 3 source module. `{.experimental:
  "strictCaseObjects".}` immediately after, enforcing exhaustive case
  matching at compile time. `func` is mandatory throughout L1–L3; no
  `proc` is permitted. Callback parameters take `{.noSideEffect,
  raises: [].}` on the proc type so they compose freely with `func`s.
- **Immutable builder** — `RequestBuilder` is a value type. Each
  `add*` returns a `(RequestBuilder, ResponseHandle[T])` tuple
  containing a fresh builder plus the typed handle. No `var`
  parameters; no mutation observable to the caller.
- **Parse, don't validate** — `fromJson` functions produce well-typed
  `Result[T, SerdeViolation]` values by composing Layer 2's typed
  field accessors with Layer 1 smart constructors via `wrapInner`.
  Invalid input flows through `SerdeViolation` to the dispatch
  boundary where it is translated to `MethodError`.
- **Make illegal states unrepresentable** — entity registration via
  `registerJmapEntity`/`registerQueryableEntity`/`registerSettableEntity`
  catches missing overloads at definition time with domain-specific
  error messages. `Referencable[T]` encodes the direct/reference
  distinction in the type system. `ResponseHandle[T]` and
  `NameBoundHandle[T]` tie call IDs to response types at compile time.
  `CopyDestroyMode` makes the "state-guard supplied with no implicit
  destroy" combination structurally unrepresentable. Per-verb method
  resolvers (`getMethodName`, `setMethodName`, etc.) make invalid
  entity/verb combinations a compile error.
- **Typed wire vocabulary** — `MethodName`, `MethodEntity`, and
  `RefPath` are string-backed enums (Layer 1). `$mn == "Mailbox/get"`
  round-trips identity-functional with the wire format. The catch-all
  `mnUnknown` exists for forward-compatible receive-side parsing
  (Postel's law); it is never emitted because builders only handle
  typed entities whose method names are known statically.

### Error Model: Three Railways

JMAP has four distinct failure modes that occur at different points in
the request lifecycle. The library models these as three error
railways, each with its own mechanism chosen to match the failure's
semantics:

```
  ┌───────────────────────────┬─────────────────────────────────────┬──────────────────────────────────────────────┐
  │          Railway          │              Mechanism              │                     Why                      │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Construction (Track 0)    │ Result[T, ValidationError]          │ Fails fast on bad input                      │
  ├───────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Serde     (Track 0a)      │ Result[T, SerdeViolation]           │ Structured wire-shape errors with JsonPath   │
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
programming error or malformed server data.

**Track 0a — Serde railway.** All Layer 3 `fromJson` functions return
`Result[T, SerdeViolation]`. `SerdeViolation` is a Layer 2 case object
carrying a `JsonPath` (RFC 6901 with JMAP `*` wildcards) plus a kind-
specific payload (`svkWrongKind`, `svkMissingField`, `svkFieldParserFailed`,
`svkEmptyRequired`, `svkConflictingFields`, etc.). Construction-rail
errors from smart constructors are bridged into the serde rail via
`wrapInner` (Layer 2), which wraps a `ValidationError` inside
`svkFieldParserFailed` while preserving the path suffix — the inner
diagnostic is round-trippable back to a `ValidationError` via
`toValidationError`.

**Track 1 — Transport/request railway.** `JmapResult[T]` (alias for
`Result[T, ClientError]`) wraps `TransportError` or `RequestError` when
the HTTP request itself fails — network error, TLS failure, timeout,
non-200 status, or a JMAP request-level error (RFC 7807 problem
details like `urn:ietf:params:jmap:error:notRequest`). This is a Layer
4 concern; Layer 3 defines the error types but does not produce them.

**Track 2 — Per-invocation method errors.** `MethodError` is a plain
`object` returned as data within a successful `Response`. The HTTP
request succeeded (200 OK), the JMAP envelope parsed correctly, but
one or more individual method calls within the batch failed. The
server signals this by returning `["error", {"type": "..."}, "callId"]`
instead of `["Foo/get", {...}, "callId"]`. `MethodError` is detected
by the dispatch function (`get[T]`, §6) by checking
`inv.rawName == "error"`. Because the response is structurally valid,
returning an error via `Result` is more appropriate than an exception
— other method calls in the same batch may have succeeded.

**Per-item errors (within Track 2).** `SetError` is also a plain
`object`, not an exception. Within a successful `/set` or `/copy`
response, individual create/update/destroy operations may fail while
others succeed. These appear in the `notCreated`, `notUpdated`, and
`notDestroyed` wire maps. Again, the response is structurally valid
and other operations in the same call succeeded.

**Railway conversion at boundaries.**

- **Track 0 → Track 0a (smart-constructor bridge).** `wrapInner`
  (Layer 2) converts `Result[T, ValidationError]` from a smart
  constructor into `Result[T, SerdeViolation]` carrying the inner
  error inside `svkFieldParserFailed`. Path suffix is appended; no
  diagnostic is lost.
- **Track 0a → Track 2 (dispatch boundary).** The dispatch function
  (`get[T]`, §6) calls `T.fromJson` and receives `err(SerdeViolation)`.
  The `serdeToMethodError(rootType)` translator builds a `MethodError`
  with type `serverFail`: it converts the `SerdeViolation` to a
  `ValidationError` via `toValidationError` (preserving root context),
  then packs `typeName` and `value` as structured JSON in
  `MethodError.extras`. Lossless conversion.
- **Track 0 + Track 1 → C error codes (Layer 5 boundary).** Layer 5
  pattern-matches on `Result` values and maps them to C-compatible
  integer error codes with thread-local error state.
- **Track 2 stays as data.** `MethodError` and `SetError` are never
  converted to exceptions. They flow through as `Result` error values
  or as fields in response objects, inspected by the caller via normal
  field access or `Result` combinators.

**Why `Result[T, E]` for all railways.** All railways use `Result[T,
E]` from nim-results. `{.push raises: [].}` on every module enforces
that no `CatchableError` can escape any function. The `?` operator
provides ergonomic early-return propagation. Track 2 uses `Result[T,
MethodError]` rather than exceptions because method errors are
partial failure within a batch — the response envelope is valid,
other method calls may have succeeded, and the caller needs to inspect
each result individually.

**Decision D3.1: Layer 3 owns serialisation of Layer 3–defined types.**
`toJson`/`fromJson` for standard method request/response types live in
Layer 3's `methods.nim`, not Layer 2. Rationale: the types are generic
over entity type `T` (and over create-value `C`, update algebra `U`,
copy-item `CopyItem`, sort element `SortT`, filter condition `C`);
their serialisation depends on entity-specific resolution
(`getMethodName(T)`, `capabilityUri(T)`, `filterType(T)`,
`createType(T)`, etc.) that only Layer 3 has. Layer 3 imports Layer
2's infrastructure (`expectKind`, `fieldJ*`, `optJsonField`,
`wrapInner`, primitive `toJson`/`fromJson` pairs) but defines its own
type-specific serialisation.

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

`{.push raises: [], noSideEffect.}` on every Layer 3 source module —
the compiler enforces both totality and purity. `{.experimental:
"strictCaseObjects".}` immediately after — every variant-field read
must occur in a `case` arm that matches the field's declared branch.

---

## Standard Library Utilisation

Layer 3 maximises use of the Nim standard library.

### Modules used in Layer 3

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/json` | `newJObject`, `newJArray`, `%`, `%*`, `{}` accessor, `[]` accessor, `getStr`, `getBiggestInt`, `getBool`, `getElems`, `pairs`, `JsonNodeKind`, `newJNull` | `{}` is the nil-safe accessor (returns nil, no `KeyError`). `[]=` is used only on local `var` `JsonNode`s during serialisation. |
| `std/tables` | `Table`, `initTable`, `pairs`, `[]=`, `len` | `SetResponse` merging, `SetRequest`/`CopyRequest` create maps |
| `std/hashes` | `Hash`, `hash`, `!&`, `!$` | `ResponseHandle[T]` / `NameBoundHandle[T]` hash delegation |

**nim-results** (external dependency) provides `Result[T, E]`,
`Opt[T]`, and the `?` operator. `Opt[T]` is used for all optional
fields — not `std/options`. `Opt[T]` is `Result[T, void]`, sharing the
full Result API (`?`, `valueOr:`, `map`, `flatMap`, iterators).

### Modules evaluated and rejected

| Module | Reason not used in Layer 3 |
|--------|---------------------------|
| `std/options` | Replaced by nim-results `Opt[T]`. `Opt[T]` shares the `Result` API (`?` operator, `valueOr:`, iterators), avoiding a parallel API surface. |
| `std/sugar` | `collect` is used in Layer 1/Layer 2 but not needed in Layer 3 source modules. Explicit `for` loops are clearer for the accumulation patterns in `fromJson` and merging helpers. |
| `std/sequtils` | `allIt`/`anyIt` not needed — Layer 3 does not require predicate checks over collections. |
| `std/jsonutils` | Uses exceptions internally. Same rejection as Layer 2. |
| `std/atomics` | No concurrency requirement in Layer 3. |

---

## 1. Method Name Vocabulary (`methods_enum.nim`)

**RFC reference:** §3.2 (lines 865–881) for method names; §3.7 for
result reference paths.

The library models JMAP method names as a string-backed enum with 1:1
wire round-trip. Per-verb resolver overloads keyed on entity typedesc
make invalid entity/verb combinations a compile error.

### 1.1 `MethodName` Enum

```nim
type MethodName* = enum
  ## Every JMAP method the library emits on the wire, plus a catch-all
  ## ``mnUnknown`` for receive-side forward compatibility.
  mnUnknown
  mnCoreEcho = "Core/echo"
  mnThreadGet = "Thread/get"
  mnThreadChanges = "Thread/changes"
  mnIdentityGet = "Identity/get"
  mnIdentityChanges = "Identity/changes"
  mnIdentitySet = "Identity/set"
  mnMailboxGet = "Mailbox/get"
  mnMailboxChanges = "Mailbox/changes"
  mnMailboxSet = "Mailbox/set"
  mnMailboxQuery = "Mailbox/query"
  mnMailboxQueryChanges = "Mailbox/queryChanges"
  mnEmailGet = "Email/get"
  mnEmailChanges = "Email/changes"
  mnEmailSet = "Email/set"
  mnEmailQuery = "Email/query"
  mnEmailQueryChanges = "Email/queryChanges"
  mnEmailCopy = "Email/copy"
  mnEmailParse = "Email/parse"
  mnEmailImport = "Email/import"
  mnVacationResponseGet = "VacationResponse/get"
  mnVacationResponseSet = "VacationResponse/set"
  mnEmailSubmissionGet = "EmailSubmission/get"
  mnEmailSubmissionChanges = "EmailSubmission/changes"
  mnEmailSubmissionSet = "EmailSubmission/set"
  mnEmailSubmissionQuery = "EmailSubmission/query"
  mnEmailSubmissionQueryChanges = "EmailSubmission/queryChanges"
  mnSearchSnippetGet = "SearchSnippet/get"
```

`$mnUnknown` falls back to the symbol name; the catch-all has no
backing string and is never emitted because builders are always
parametrised on a concrete entity whose method name is statically
known. The verbatim wire string is preserved on
`Invocation.rawName` for lossless round-trip.

`parseMethodName(raw: string): MethodName` is total — returns
`mnUnknown` for any wire string that doesn't match a backing literal.
Used on the receive path (`serde_envelope.fromJson`) to tag known
methods without rejecting forward-compatible server extensions.

### 1.2 `MethodEntity` Enum

```nim
type MethodEntity* = enum
  ## Entity category tag returned by ``methodEntity[T]``. The compile-
  ## time existence check inside ``registerJmapEntity`` keys off this
  ## function — a type without a ``methodEntity`` overload fails the
  ## register step before reaching the builder.
  meCore
  meThread
  meIdentity
  meMailbox
  meEmail
  meVacationResponse
  meSearchSnippet
  meEmailSubmission
  meTest      # sentinel for test-only fixture entities
```

### 1.3 `RefPath` Enum

```nim
type RefPath* = enum
  ## RFC 8620 §3.7 result-reference paths — JSON Pointer fragments a
  ## chained method call reads out of a prior invocation's response.
  rpIds = "/ids"
  rpListIds = "/list/*/id"
  rpAddedIds = "/added/*/id"
  rpCreated = "/created"
  rpUpdated = "/updated"
  rpUpdatedProperties = "/updatedProperties"
  rpListThreadId = "/list/*/threadId"
  rpListEmailIds = "/list/*/emailIds"
```

`rpListThreadId` and `rpListEmailIds` participate in the RFC 8621 §4.10
first-login workflow (Email/get → Thread/get → Email/get).

**Module:** `methods_enum.nim`

---

## 2. Call ID Generation

**Architecture decision:** 3.2A (auto-incrementing counter)

**RFC reference:** §3.2 (lines 865–881) — the method call id is "an
arbitrary string from the client to be echoed back with the responses
emitted by that method call".

The counter is a field on `RequestBuilder`. Format: `"c0"`, `"c1"`,
`"c2"`, …. The `"c"` prefix guarantees the string is non-empty and free
of control characters, satisfying `MethodCallId` invariants without
requiring validation.

**Decision D3.9:** `MethodCallId(s)` uses the distinct constructor
directly (bypassing `parseMethodCallId`) because the generated format
is provably valid: the builder controls the format entirely, the `"c"`
prefix ensures non-empty, and `$int` produces only ASCII digit
characters.

---

## 3. RequestBuilder Type

**Architecture decision:** 3.3B (immutable builder with method-
specific `add*` functions returning fresh builder + handle pairs).

**RFC reference:** §3.3 (lines 882–945) — the Request object with
`using`, `methodCalls`, and optional `createdIds`.

### 3.1 Type Definition

```nim
type RequestBuilder* = object
  ## Immutable accumulator for constructing a JMAP Request (RFC 8620
  ## §3.3). All fields are private — the builder is the sole construction
  ## path. Each ``add*`` returns a new ``(RequestBuilder, ResponseHandle[T])``
  ## tuple; the original builder is unchanged.
  nextCallId: int                 ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation]    ## accumulated method calls
  capabilityUris: seq[string]     ## deduplicated capability URIs
```

Fields are private (no `*` export marker). The builder is the sole
construction path — callers cannot bypass it to construct malformed
requests.

### 3.2 Constructor

```nim
func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations, and
  ## ``urn:ietf:params:jmap:core`` pre-declared in ``using``.
  RequestBuilder(
    nextCallId: 0,
    invocations: @[],
    capabilityUris: @["urn:ietf:params:jmap:core"]
  )
```

The Core capability is pre-declared because RFC 8620 §3.2 obliges
clients to declare every capability they need to use. Lenient servers
(Stalwart 0.15.5) accept requests with `core` omitted; strict servers
(Apache James 3.9) reject them with `unknownMethod (Missing
capability(ies): urn:ietf:params:jmap:core)`. Pre-declaring it makes
the client portable across both.

### 3.3 Read-Only Accessors

```nim
func methodCallCount*(b: RequestBuilder): int
  ## Number of method calls accumulated so far.

func isEmpty*(b: RequestBuilder): bool
  ## True if no method calls have been added.

func capabilities*(b: RequestBuilder): seq[string]
  ## Snapshot of the deduplicated capability URIs registered so far.
```

### 3.4 Build

```nim
func build*(b: RequestBuilder): Request =
  ## Snapshot of the current builder state. The builder may continue to
  ## accumulate invocations after a call to ``build()`` — a subsequent
  ## ``build()`` will capture the updated state. ``createdIds`` is
  ## always none — proxy splitting is a Layer 4 concern.
  Request(
    `using`: b.capabilityUris,
    methodCalls: b.invocations,
    createdIds: Opt.none(Table[CreationId, Id])
  )
```

### 3.5 Capability Deduplication

```nim
func withCapability(caps: seq[string], cap: string): seq[string] =
  ## Returns a new capability list with ``cap`` added if not already present.
  if cap in caps: caps else: caps & @[cap]
```

### 3.6 Invocation Helper

```nim
func addInvocation*(
    b: RequestBuilder,
    name: MethodName,
    args: JsonNode,
    capability: string,
): (RequestBuilder, MethodCallId) =
  ## Constructs an Invocation from the given typed method name and
  ## arguments and returns a new builder with it accumulated. ``name``
  ## is typed — empty wire names are structurally unrepresentable.
  let callId = b.nextId()
  let inv = initInvocation(name, args, callId)
  (
    RequestBuilder(
      nextCallId: b.nextCallId + 1,
      invocations: b.invocations & @[inv],
      capabilityUris: withCapability(b.capabilityUris, capability),
    ),
    callId,
  )
```

`initInvocation` is the typed Layer 1 constructor. `MethodName` is a
string-backed enum so the wire name is `$name` — empty is structurally
unrepresentable. There is no separate "unchecked" variant.

`addInvocation` is exported because Layer 4 mail-method builders
(`mail/mail_methods.nim` for `Email/parse`, `Email/import`,
`SearchSnippet/get`, `VacationResponse/get`/`set`) reuse it directly to
emit invocations whose request shape is too entity-specific to flow
through the generic `addGet` / `addSet` / `addQuery` family.

The internal `nextId` helper (private) computes the next call ID from
the counter without mutation, bypassing `parseMethodCallId` because the
generated `"c<int>"` format is provably valid (Decision D3.9).

### 3.7 DRY Template

```nim
template addMethodImpl(
    b: RequestBuilder,
    T: typedesc,
    methodNameResolver: untyped,
    req: typed,
    RespType: typedesc,
): untyped =
  ## Shared boilerplate for non-query add* functions: per-verb resolver
  ## mixin, toJson serialisation, invocation accumulation, handle wrapping.
  ## ``methodNameResolver`` is the per-verb resolver (e.g. ``getMethodName``),
  ## resolved via ``mixin`` at the caller's scope. Passing the wrong verb
  ## for an entity (e.g. ``setMethodName`` on Thread) is a compile error.
  mixin methodNameResolver, capabilityUri
  let args = req.toJson()
  let (newBuilder, callId) =
    addInvocation(b, methodNameResolver(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[RespType](callId))
```

### 3.8 The `add*` Function Signatures

All `add*` functions return `(RequestBuilder, ResponseHandle[ResponseType])`.
Required RFC fields are positional; optional fields are keyword-defaulted
with `Opt.none(T)` or the RFC-specified default value. Each non-query
function exposes an `extras: seq[(string, JsonNode)] = @[]` parameter for
entity-specific extension keys (e.g. `Email/get`'s body-fetch options,
`Mailbox/set`'s `onDestroyRemoveEmails`); extras are appended to the
generated args after the standard frame, preserving insertion order.

**`func` throughout.** All `add*` functions are `func` — totality and
purity are compiler-enforced via `{.push raises: [], noSideEffect.}`
on the module. Filter and sort serialisation flow through `mixin
toJson` resolution rather than callback parameters, so no `proc`
escape hatch is needed.

**3.8.1 addEcho**

```nim
func addEcho*(b: RequestBuilder, args: JsonNode):
    (RequestBuilder, ResponseHandle[JsonNode]) =
  ## Adds a Core/echo invocation (RFC 8620 §4). The server echoes the
  ## arguments back unchanged. Capability: "urn:ietf:params:jmap:core".
  let (newBuilder, callId) =
    b.addInvocation(mnCoreEcho, args, "urn:ietf:params:jmap:core")
  (newBuilder, ResponseHandle[JsonNode](callId))
```

**3.8.2 addGet**

```nim
func addGet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[GetResponse[T]]) =
  mixin getMethodName, capabilityUri
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  var args = req.toJson()
  for (k, v) in extras: args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, getMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[GetResponse[T]](callId))
```

**3.8.3 addChanges**

`addChanges` takes a second type parameter `RespT` for the concrete
response type. Standard entities use `ChangesResponse[T]`; entities
with extended responses (`Mailbox` carries the RFC 8621 §2.2
`updatedProperties` field via `MailboxChangesResponse`) supply a
distinct `RespT`. Request wire shape is unchanged across entities.

```nim
func addChanges*[T, RespT](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[RespT]) =
  let req = ChangesRequest[T](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges)
  addMethodImpl(b, T, changesMethodName, req, RespT)

template addChanges*[T](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): untyped =
  ## Single-type-parameter alias. Resolves ``changesResponseType(T)`` at
  ## the call site.
  addChanges[T, changesResponseType(T)](b, accountId, sinceState, maxChanges)
```

**3.8.4 addSet**

`addSet` takes four type parameters: `T` (entity), `C` (typed
create-value), `U` (whole-container update algebra), `R` (response
type). `C.toJson` and `U.toJson` resolve at instantiation via `mixin`.

```nim
func addSet*[T, C, U, R](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, C]] = Opt.none(Table[CreationId, C]),
    update: Opt[U] = Opt.none(U),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[R]) =
  mixin setMethodName, capabilityUri, toJson
  let req = SetRequest[T, C, U](
    accountId: accountId, ifInState: ifInState,
    create: create, update: update, destroy: destroy,
  )
  var args = req.toJson()
  for (k, v) in extras: args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, setMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[R](callId))

template addSet*[T](b: RequestBuilder, accountId: AccountId): untyped =
  ## Single-type-parameter alias. Resolves ``createType(T)``,
  ## ``updateType(T)``, and ``setResponseType(T)`` via template expansion.
  ## For calls supplying ``create`` / ``update`` / ``destroy`` / ``extras``,
  ## invoke the four-parameter form directly.
  addSet[T, createType(T), updateType(T), setResponseType(T)](b, accountId)
```

**3.8.5 addCopy**

```nim
func addCopy*[T, CopyItem, R](
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, CopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    destroyMode: CopyDestroyMode = keepOriginals(),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[R]) =
  mixin copyMethodName, capabilityUri, toJson
  let req = CopyRequest[T, CopyItem](
    fromAccountId: fromAccountId, ifFromInState: ifFromInState,
    accountId: accountId, ifInState: ifInState, create: create,
    destroyMode: destroyMode,
  )
  var args = req.toJson()
  for (k, v) in extras: args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, copyMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[R](callId))

template addCopy*[T](
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: untyped,
): untyped =
  ## Single-type-parameter alias. Resolves ``copyItemType(T)`` and
  ## ``copyResponseType(T)`` at the call site.
  addCopy[T, copyItemType(T), copyResponseType(T)](
    b, fromAccountId, accountId, create)
```

`destroyMode` defaults to `keepOriginals()`. Pass `destroyAfterSuccess(...)`
for RFC 8620 §5.4 compound copy-and-destroy.

**3.8.6 addQuery**

`addQuery` takes three type parameters: `T` (entity), `C` (filter
condition), `SortT` (sort element). `C.toJson` resolves at instantiation
via `mixin` through the `serializeOptFilter` → `Filter[C].toJson`
cascade. `SortT.toJson` resolves through `serializeOptSort` — works for
both protocol-level `Comparator` and entity-specific sort element
types (e.g. `EmailComparator`).

```nim
func addQuery*[T, C, SortT](
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[C]] = default(Opt[Filter[C]]),
    sort: Opt[seq[SortT]] = default(Opt[seq[SortT]]),
    queryParams: QueryParams = QueryParams(),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  mixin queryMethodName, capabilityUri, toJson
  var args = assembleQueryArgs(
    accountId,
    serializeOptFilter(filter),
    serializeOptSort(sort),
    queryParams,
  )
  for (k, v) in extras: args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, queryMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryResponse[T]](callId))

template addQuery*[T](
    b: RequestBuilder, accountId: AccountId,
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Single-type-parameter alias. Resolves ``filterType(T)`` at the call
  ## site; uses protocol-level ``Comparator`` for sort. For entity-typed
  ## sort, invoke the three-parameter form directly.
  addQuery[T, filterType(T), Comparator](b, accountId)
```

**3.8.7 addQueryChanges**

```nim
func addQueryChanges*[T, C, SortT](
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[C]] = default(Opt[Filter[C]]),
    sort: Opt[seq[SortT]] = default(Opt[seq[SortT]]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  mixin queryChangesMethodName, capabilityUri, toJson
  var args = assembleQueryChangesArgs(
    accountId, sinceQueryState,
    serializeOptFilter(filter), serializeOptSort(sort),
    maxChanges, upToId, calculateTotal,
  )
  for (k, v) in extras: args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, queryChangesMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryChangesResponse[T]](callId))

template addQueryChanges*[T](
    b: RequestBuilder, accountId: AccountId, sinceQueryState: JmapState,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  addQueryChanges[T, filterType(T), Comparator](b, accountId, sinceQueryState)
```

`/queryChanges` takes `calculateTotal` directly — RFC 8620 §5.6 defines
no window fields beyond `maxChanges` / `upToId`.

**Decision D3.2:** `add*` parameters match RFC request fields. Required
RFC fields are positional; optional fields are keyword-defaulted with
`Opt.none(T)` or the RFC-specified default value.

### 3.9 Argument Construction Helpers

```nim
func directIds*(ids: openArray[Id]): Opt[Referencable[seq[Id]]] =
  ## Wraps: Opt.some(direct(@ids))
  Opt.some(direct(@ids))

func initCreates*(
    pairs: openArray[(CreationId, JsonNode)]
): Opt[Table[CreationId, JsonNode]] =
  ## Builds an Opt-wrapped raw create table. Used by callers passing
  ## ``JsonNode`` to the four-parameter ``addSet[T, JsonNode, ...]``;
  ## typed-create entities pass ``Opt[Table[CreationId, MailboxCreate]]``
  ## (etc.) directly without this helper.
```

There is no `initUpdates` helper because `update` is a typed
whole-container algebra (`U` in `SetRequest[T, C, U]`), not a
`Table[Id, PatchObject]`.

**Module:** `builder.nim`

---

## 4. Response Dispatch

**Architecture decision:** 3.4C (phantom-typed response handles)

**RFC reference:** §3.4 (lines 975–1035) — the Response object with
`methodResponses`, `createdIds`, and `sessionState`. §3.7 — back-
reference chains. §5.4 — compound methods.

Response dispatch covers four dispatch shapes:

1. **`ResponseHandle[T]`** — single typed handle, one call ID.
2. **`NameBoundHandle[T]`** — handle whose call ID is shared with a
   sibling invocation (RFC 8620 §5.4 compound overloads).
3. **`CompoundHandles[A, B]`** — paired handles for an RFC §5.4
   compound (primary + implicit-call follow-up sharing the call ID).
4. **`ChainedHandles[A, B]`** — paired handles for an RFC §3.7 back-
   reference chain (distinct call IDs, no name filter needed).

### 4.1 ResponseHandle[T]

```nim
type ResponseHandle*[T] = distinct MethodCallId
  ## Phantom-typed handle tying a method call ID to its expected response
  ## type ``T``. ``T`` is unused at runtime — it exists solely to enforce
  ## type-safe extraction at compile time.
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

### 4.2 NameBoundHandle[T]

```nim
type NameBoundHandle*[T] = object
  ## Response handle whose wire invocation shares its call-id with a
  ## sibling invocation (RFC 8620 §5.4 compound overloads). The method-
  ## name fact travels with the handle — set once at the builder
  ## construction site, never at the extraction site.
  callId*: MethodCallId
  methodName*: MethodName
```

Used for the implicit follow-up response in an RFC §5.4 compound (e.g.
the `Email/set` destroy response that accompanies `Email/copy` with
`onSuccessDestroyOriginal=true`). Dispatch resolves via call-id +
method-name simultaneously, so `resp.get(h)` needs no filter argument.

### 4.3 Two-Level Railway Composition

```
Track 1 (Outer): JmapResult[Response] = Result[Response, ClientError]
                 (transport/request errors — Layer 4)
                   ↓
Track 2 (Inner): Result[T, MethodError]
                 (per-invocation errors — dispatch boundary)
```

These railways are **intentionally separate** — transport failures and
method errors require fundamentally different recovery actions.

### 4.4 Track 0a → Track 2 Bridge

```nim
func serdeToMethodError*(
    rootType: string
): proc(sv: SerdeViolation): MethodError {.noSideEffect, raises: [].} =
  ## Returns a closure that translates a ``SerdeViolation`` into a
  ## ``MethodError`` via the canonical ``toValidationError`` translator
  ## (with ``rootType`` as the type-name root context), then packs the
  ## resulting shape into a ``serverFail`` method error. Preserves
  ## ``typeName`` and ``value`` in ``extras`` so no diagnostic is lost.
```

The dispatch path uses `mapErr(serdeToMethodError($T))` to convert
serde failures to method errors with the response type name as the
root diagnostic context.

### 4.5 Extraction Functions

**4.5.0 Internal `extractInvocation` helper.** Shared scanning + error
detection logic. Both `get[T]` overloads delegate.

```nim
func findInvocation(resp: Response, targetId: MethodCallId): Opt[Invocation]
func extractInvocation(resp: Response, targetId: MethodCallId
): Result[Invocation, MethodError]
  ## Algorithm:
  ## 1. Scan methodResponses for invocation matching targetId.
  ## 2. Not found → err(serverFail).
  ## 3. If rawName == "error" → parse as MethodError, return err.
  ##    Malformed error → err(serverFail).
  ## 4. Otherwise → return ok(invocation).
```

The error-name check uses `inv.rawName == "error"`. The typed `inv.name`
accessor returns `MethodName` (with `mnUnknown` for the literal
`"error"`); the verbatim `rawName` is what the RFC mandates.

**4.5.1 Default extraction via `mixin fromJson`**

```nim
func get*[T](resp: Response, handle: ResponseHandle[T]
): Result[T, MethodError] =
  mixin fromJson
  let inv = ?extractInvocation(resp, callId(handle))
  T.fromJson(inv.arguments).mapErr(serdeToMethodError($T))
```

**4.5.2 Callback overload (escape hatch)**

```nim
func get*[T](resp: Response, handle: ResponseHandle[T],
    fromArgs: proc(node: JsonNode): Result[T, SerdeViolation]
        {.noSideEffect, raises: [].},
): Result[T, MethodError] =
  let inv = ?extractInvocation(resp, callId(handle))
  fromArgs(inv.arguments).mapErr(serdeToMethodError($T))
```

For custom parsing where `T.fromJson` is not discoverable via `mixin`
(e.g. entity-specific extractors or `JsonNode` for `Core/echo`).

**4.5.3 Name-bound handle overload**

```nim
func get*[T](resp: Response, h: NameBoundHandle[T]
): Result[T, MethodError] =
  mixin fromJson
  let inv = ?extractInvocationByName(resp, h.callId, h.methodName)
  T.fromJson(inv.arguments).mapErr(serdeToMethodError($T))
```

Internally `findInvocationByName` scans `methodResponses` for the
first invocation matching BOTH call-id AND method-name — used when
multiple invocations share a call-id (RFC §5.4).

**Decision D3.3:** The extraction function returns `Result[T, MethodError]`.
Method errors are data within a successful HTTP response — per-invocation,
not per-request. The outer railway (`JmapResult` / `ClientError`) is
reserved for transport and request-level failures at the Layer 4
boundary.

**Cross-request safety gap.** Call IDs repeat across requests (`"c0"`
in every request). A handle from Request A used with Response B
silently extracts the wrong invocation. No type-level mitigation is
possible in Nim without encoding the request identity in the type
system (which would add complexity disproportionate to the risk).
Convention: use handles immediately within the scope where the
request was built. This gap is documented in the `ResponseHandle` doc
comment.

### 4.6 Compound Method Dispatch (RFC 8620 §5.4)

`CompoundHandles[A, B]` pairs a primary handle (typed `A`) with a
NameBoundHandle for the implicit follow-up (typed `B`).

```nim
type CompoundHandles*[A, B] = object
  primary*: ResponseHandle[A]
  implicit*: NameBoundHandle[B]

type CompoundResults*[A, B] = object
  primary*: A
  implicit*: B

func getBoth*[A, B](resp: Response, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], MethodError] =
  ## Extracts both responses; first error short-circuits via ``?``.
  mixin fromJson
  let primary = ?resp.get(handles.primary)
  let implicit = ?resp.get(handles.implicit)
  ok(CompoundResults[A, B](primary: primary, implicit: implicit))

template registerCompoundMethod*(Primary, Implicit: typedesc) =
  ## Compile-checks ``Primary`` parametrises ``ResponseHandle`` and
  ## ``Implicit`` parametrises ``NameBoundHandle``. Call at module
  ## scope per compound participant.
```

Canonical participants (registered in `mail/mail_entities.nim`):

- `CopyResponse[EmailCreatedItem]` (primary) +
  `SetResponse[EmailCreatedItem]` (implicit) — `Email/copy` with
  `onSuccessDestroyOriginal=true`.
- `EmailSubmissionSetResponse` (primary) +
  `SetResponse[EmailCreatedItem]` (implicit) — `EmailSubmission/set`
  with `onSuccessUpdateEmail` / `onSuccessDestroyEmail`.

### 4.7 Chained Method Dispatch (RFC 8620 §3.7)

`ChainedHandles[A, B]` pairs two handles whose call IDs are distinct —
no method-name filter is needed.

```nim
type ChainedHandles*[A, B] = object
  first*: ResponseHandle[A]
  second*: ResponseHandle[B]

type ChainedResults*[A, B] = object
  first*: A
  second*: B

func getBoth*[A, B](resp: Response, handles: ChainedHandles[A, B]
): Result[ChainedResults[A, B], MethodError]

template registerChainableMethod*(Primary: typedesc) =
  ## Compile-checks ``Primary`` parametrises ``ResponseHandle``.
```

Canonical participants:

- `QueryResponse[Email]` → chain into `Email/get` (RFC 8621 §4.5
  query-then-get pipeline).
- `GetResponse[Email]` → chain into `Thread/get` via `rpListThreadId`.
- `GetResponse[Thread]` → chain into `Email/get` via `rpListEmailIds`.

`getBoth` is overloaded on `CompoundHandles` and `ChainedHandles`; the
compiler selects by argument type.

### 4.8 End-to-End Example

Self-contained walkthrough using a minimal `Widget` entity. Covers
entity registration, request building, `build()`, response dispatch,
and error handling across the railways.

```nim
## --- Entity definition (widget.nim) ---
type Widget* = object

func methodEntity*(T: typedesc[Widget]): MethodEntity = meTest
func getMethodName*(T: typedesc[Widget]): MethodName = mnUnknown
  # placeholder — real entities use real ``MethodName`` variants
func capabilityUri*(T: typedesc[Widget]): string = "urn:example:widgets"
registerJmapEntity(Widget)  # compile error if overloads missing

## --- Request building ---
let accountId = parseAccountId("acc1").get()  # invariant: literal valid

let b0 = initRequestBuilder()
let (b1, gh) = b0.addGet[Widget](accountId)              # Widget/get
let (b2, sh) = b1.addSet[Widget](accountId,              # Widget/set
    destroy = directIds(@[parseId("id7").get()]))
let req = b2.build()
## req.using == @["urn:ietf:params:jmap:core", "urn:example:widgets"]
## req.methodCalls.len == 2

## --- Response dispatch (after Layer 4 transport, out of scope) ---
let getResult = resp.get(gh)            # Result[GetResponse[Widget], MethodError]
let setResult = resp.get(sh)            # Result[SetResponse[Widget], MethodError]
```

**Key points illustrated:**

- **Entity registration** (§5): `methodEntity` + per-verb `getMethodName`,
  `capabilityUri`, `registerJmapEntity`.
- **Builder** (§3): immutable; each `add*` returns a fresh builder
  alongside the typed handle.
- **Response dispatch** (§4): `get[T]` via `mixin fromJson`, returning
  `Result[T, MethodError]` on Track 2.
- **Three railways in action**:
  - `parseAccountId` and `parseId` return `Result[T, ValidationError]`
    (Track 0) if input is invalid — caller never reaches the builder.
  - Layer 4 transport (not shown) returns `JmapResult[Response]` (Track 1).
  - `get[T]` returns `Result[T, MethodError]` (Track 2).
  - `SetResponse.destroyResults` contains `Result[void, SetError]`
    (within Track 2) — partial failure within a successful `/set`.

**Module:** `dispatch.nim`

---

## 5. Entity Type Framework

**Architecture decisions:** 3.5B (plain overloads, no concepts), 3.7B
(overloaded type-level templates for associated types).

**Decision D3.4:** No concepts; plain overloaded `typedesc` `func`s
with three registration templates instead. Concepts are avoided due
to: experimental status, known compiler bugs (byref #16897, block
scope, implicit generic breakage), generic type checking
unimplemented, and minimal stdlib adoption. Plain overloaded `func`s
provide equivalent compile-time safety via registration templates that
verify all required overloads exist.

### 5.1 Entity Interface — Required Overloads

Each entity type provides the following `typedesc` overloads. Required
for every entity:

```nim
func methodEntity*(T: typedesc[Mailbox]): MethodEntity = meMailbox
  ## Returns the typed entity tag. The registration check keys off
  ## this overload.

func capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
  ## Returns the capability URI for the ``using`` array.
```

Per-verb method-name resolvers — one per supported verb. Unsupported
verbs simply omit the overload; calls to e.g. `setMethodName(typedesc[Thread])`
fail at the call site with an undeclared-identifier error that names
the offending `(entity, verb)` pair, more precise than a generic
registration check could be.

```nim
func getMethodName*(T: typedesc[E]): MethodName
func changesMethodName*(T: typedesc[E]): MethodName
func setMethodName*(T: typedesc[E]): MethodName
func queryMethodName*(T: typedesc[E]): MethodName
func queryChangesMethodName*(T: typedesc[E]): MethodName
func copyMethodName*(T: typedesc[E]): MethodName
```

Associated type templates (queryable / settable / compound):

```nim
template filterType*(T: typedesc[E]): typedesc
  ## Maps entity to its filter condition type for /query.
template createType*(T: typedesc[E]): typedesc
  ## Maps entity to its typed create-value for /set.
template updateType*(T: typedesc[E]): typedesc
  ## Maps entity to its whole-container update algebra for /set.
template setResponseType*(T: typedesc[E]): typedesc
  ## Maps entity to its /set response type (typically SetResponse[CreatedItem]).
template changesResponseType*(T: typedesc[E]): typedesc
  ## Maps entity to its /changes response type (ChangesResponse[E] or
  ## an extended composition like MailboxChangesResponse).
template copyItemType*(T: typedesc[E]): typedesc
  ## Maps entity to its typed copy-item value for /copy.
template copyResponseType*(T: typedesc[E]): typedesc
  ## Maps entity to its /copy response type.
```

Templates (not `func`s) are used for associated-type maps so that
`createType(T)`, `updateType(T)`, etc. can appear in type positions
(e.g. as the type parameter of a generic call). `mixin` resolves them
at the caller's instantiation site.

### 5.2 Compile-Time Registration Templates

Three registration templates verify required overloads exist at
definition time. Missing overloads produce domain-specific compile
errors at the entity registration site, not cryptic "undeclared
identifier" errors at distant `add*` call sites.

```nim
template registerJmapEntity*(T: typedesc) =
  ## Verifies T provides the base framework overloads
  ## (``methodEntity`` and ``capabilityUri``). Call at module scope.
  ## Does not check per-verb method-name resolvers — those fail at
  ## their call site with an error naming the offending (entity, verb)
  ## pair, more precise than a generic check.
  static:
    when not compiles(methodEntity(T)):
      {.error: "registerJmapEntity: " & $T & " is missing `func methodEntity*(...)`.}
    when not compiles(capabilityUri(T)):
      {.error: "registerJmapEntity: " & $T & " is missing `func capabilityUri*(...)`.}
```

```nim
template registerQueryableEntity*(T: typedesc) =
  ## Verifies ``filterType`` and ``toJson`` on the filter condition
  ## type. Call after ``registerJmapEntity`` for queryable entities.
```

```nim
template registerSettableEntity*(T: typedesc) =
  ## Verifies the four /set-related overloads:
  ## ``setMethodName``, ``createType``, ``updateType``, ``setResponseType``.
  ## Call after ``registerJmapEntity`` for settable entities.
```

The dispatch module additionally exposes:

```nim
template registerCompoundMethod*(Primary, Implicit: typedesc)
  ## Compile-checks Primary parametrises ResponseHandle and Implicit
  ## parametrises NameBoundHandle. Call at module scope per RFC §5.4
  ## compound participant.

template registerChainableMethod*(Primary: typedesc)
  ## Compile-checks Primary parametrises ResponseHandle. Call at module
  ## scope per RFC §3.7 chain participant.
```

### 5.3 Generic `add*` Functions — Unconstrained `T`

```nim
func addGet*[T](b: RequestBuilder, ...): (RequestBuilder, ResponseHandle[GetResponse[T]])
```

No `: JmapEntity` constraint on `T`. If `T` lacks the per-verb resolver
or `capabilityUri`, the error appears when the `add*` body calls
`getMethodName(T)`. The `registerJmapEntity` template catches the base
overloads earlier. Per-verb resolvers fail with a message naming
exactly which `(entity, verb)` overload is missing.

### 5.4 `mixin` for Overload Resolution in Generic Bodies

```nim
func addGet*[T](...) =
  mixin getMethodName, capabilityUri
  ...
```

`mixin` ensures the compiler searches the **caller's scope** for
`getMethodName` / `capabilityUri` overloads, not just `builder.nim`'s.
Without `mixin`, the compiler would only see overloads imported into
`builder.nim`, requiring `builder.nim` to import every entity module —
breaking the import DAG and preventing entity modules from being added
independently.

### 5.5 Entity Module Checklist

Every entity module provides:

1. The entity type definition (e.g. `type Mailbox* = object`).
2. `func methodEntity*(T: typedesc[Entity]): MethodEntity`.
3. `func capabilityUri*(T: typedesc[Entity]): string`.
4. Per-verb method-name resolvers for every supported verb.
5. `template filterType*(T: typedesc[Entity]): typedesc` (if `/query`).
6. `func toJson*(c: filterType(Entity)): JsonNode` (if `/query`).
7. `template createType*(T: typedesc[Entity]): typedesc`,
   `template updateType*(T: typedesc[Entity]): typedesc`, and
   `template setResponseType*(T: typedesc[Entity]): typedesc` (if `/set`).
8. `template changesResponseType*(T: typedesc[Entity]): typedesc`
   (if `/changes`).
9. `template copyItemType*(T: typedesc[Entity]): typedesc` and
   `template copyResponseType*(T: typedesc[Entity]): typedesc`
   (if `/copy`).
10. `registerJmapEntity(Entity)` at module scope.
11. `registerQueryableEntity(Entity)` (if `/query`).
12. `registerSettableEntity(Entity)` (if `/set`).
13. `registerCompoundMethod(...)` per compound participation.
14. `registerChainableMethod(...)` per chain participation.
15. `toJson` / `fromJson` for the entity type itself, plus its
    create-value / update-algebra / copy-item / created-item types as
    needed.

Items 1–14 are Layer 3 framework concerns. Item 15 is entity-specific.

**Module:** `entity.nim`

---

## 6. Standard Method Request Types

**RFC reference:** §5.1–5.6 (lines 1587–2819)

Each request type carries `##` doc comments on every field citing the
RFC section. Each type receives a `toJson` `func` (Pattern L3-A,
§7.1). No `fromJson` is provided — request types are serialised by
the client, never parsed (Decision D3.7).

### 6.1 GetRequest[T]

**RFC reference:** §5.1 (lines 1587–1612)

```nim
type GetRequest*[T] = object
  ## Request arguments for Foo/get (RFC 8620 §5.1).
  accountId*: AccountId
  ids*: Opt[Referencable[seq[Id]]]
    ## Identifiers to return; if none, all records (subject to
    ## maxObjectsInGet). Referencable: direct seq or result reference.
  properties*: Opt[seq[string]]
    ## If supplied, only these properties are returned. ``id`` is
    ## always returned.
```

### 6.2 ChangesRequest[T]

**RFC reference:** §5.2 (lines 1667–1703)

```nim
type ChangesRequest*[T] = object
  ## Request arguments for Foo/changes (RFC 8620 §5.2).
  accountId*: AccountId
  sinceState*: JmapState
  maxChanges*: Opt[MaxChanges]
    ## Must be > 0 per RFC (enforced by the MaxChanges smart constructor).
```

### 6.3 SetRequest[T, C, U]

**RFC reference:** §5.3 (lines 1855–1945)

```nim
type SetRequest*[T, C, U] = object
  ## Request arguments for Foo/set (RFC 8620 §5.3). ``T`` = entity,
  ## ``C`` = typed create-entry value, ``U`` = whole-container update
  ## algebra. Both ``C.toJson`` and ``U.toJson`` resolve at instantiation
  ## via ``mixin``.
  accountId*: AccountId
  ifInState*: Opt[JmapState]
  create*: Opt[Table[CreationId, C]]
    ## Map of creation IDs to typed creation-model values.
    ## ``C.toJson`` is resolved at instantiation site.
  update*: Opt[U]
    ## Typed whole-container update algebra. ``Opt.none`` omits the
    ## ``update`` key; ``Opt.some(u)`` emits ``u.toJson()`` verbatim
    ## as the wire ``"update"`` value.
  destroy*: Opt[Referencable[seq[Id]]]
```

The whole-container update type (`U`) names the algebra used to
describe a coherent set of patches across multiple entities. Concrete
types (`NonEmptyMailboxUpdates`, `NonEmptyEmailUpdates`,
`NonEmptyIdentityUpdates`) live in entity modules; each provides
`toJson(u: U): JsonNode` returning the wire `"update"` value.

### 6.4 CopyDestroyMode (case object)

```nim
type CopyDestroyModeKind* = enum
  cdmKeep
  cdmDestroyAfterSuccess

type CopyDestroyMode* = object
  ## Typed post-copy disposition for ``CopyRequest`` (RFC 8620 §5.4).
  ## A case object instead of two flat fields
  ## (``onSuccessDestroyOriginal: bool`` + ``destroyFromIfInState:
  ## Opt[JmapState]``): with flat fields, ``destroyFromIfInState =
  ## Opt.some(...)`` alongside ``onSuccessDestroyOriginal = false`` is
  ## structurally expressible but semantically meaningless because no
  ## implicit destroy is issued. The case object makes that combination
  ## unrepresentable.
  case kind*: CopyDestroyModeKind
  of cdmKeep:
    discard
  of cdmDestroyAfterSuccess:
    destroyIfInState*: Opt[JmapState]

func keepOriginals*(): CopyDestroyMode
  ## Constructs the cdmKeep variant. CopyRequest.toJson omits
  ## onSuccessDestroyOriginal entirely (RFC default).

func destroyAfterSuccess*(
    ifInState: Opt[JmapState] = Opt.none(JmapState)
): CopyDestroyMode
  ## Constructs the cdmDestroyAfterSuccess variant.
```

### 6.5 CopyRequest[T, CopyItem]

**RFC reference:** §5.4 (lines 2191–2268)

```nim
type CopyRequest*[T, CopyItem] = object
  ## Request arguments for Foo/copy (RFC 8620 §5.4). ``T`` = entity;
  ## ``CopyItem`` = typed create-entry value (e.g. ``EmailCopyItem``).
  ## ``CopyItem.toJson`` resolves at instantiation via ``mixin``.
  fromAccountId*: AccountId
  ifFromInState*: Opt[JmapState]
  accountId*: AccountId
  ifInState*: Opt[JmapState]
  create*: Table[CreationId, CopyItem]
    ## Required (not optional). Each copy item carries an ``id`` referencing
    ## the record in the from-account.
  destroyMode*: CopyDestroyMode
    ## Post-copy disposition. Case object — illegal combination
    ## "state-guard supplied with no implicit destroy" is unrepresentable.
```

### 6.6 Query / QueryChanges Argument Assembly

`/query` and `/queryChanges` use a serialise-then-assemble pattern
rather than dedicated request types. The intermediate `SerializedSort`
and `SerializedFilter` distinct types pre-serialise their inputs;
`assembleQueryArgs` and `assembleQueryChangesArgs` produce the wire
arguments.

```nim
type
  SerializedSort* = distinct JsonNode
    ## Pre-serialised sort array. Wraps a JArray.
  SerializedFilter* = distinct JsonNode
    ## Pre-serialised filter tree. Wraps a JObject/JArray.

func toJsonNode*(s: SerializedSort): JsonNode
func toJsonNode*(f: SerializedFilter): JsonNode

func serializeOptSort*[S](sort: Opt[seq[S]]): Opt[SerializedSort]
  ## Pre-serialise an optional sort array. Generic over sort element
  ## type — works for both ``Comparator`` and entity-specific sort
  ## types (e.g. ``EmailComparator``). Resolves ``S.toJson`` via mixin.

func serializeOptFilter*[C](filter: Opt[Filter[C]]): Opt[SerializedFilter]
  ## Pre-serialise an optional filter tree. ``Filter[C].toJson``
  ## resolves the leaf condition's ``C.toJson`` via mixin.

func serializeFilter*[C](filter: Filter[C]): SerializedFilter
  ## Non-Opt variant for builders requiring a mandatory filter
  ## (e.g. SearchSnippet/get).

func assembleQueryArgs*(
    accountId: AccountId,
    filter: Opt[SerializedFilter],
    sort: Opt[SerializedSort],
    queryParams: QueryParams,
): JsonNode
  ## Build standard Foo/query args from pre-serialised parts. Single
  ## source of truth for the query protocol frame. Window fields come
  ## from QueryParams (Layer 1 framework type) which carries the RFC
  ## 8620 §5.5 zero-init defaults.

func assembleQueryChangesArgs*(
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[SerializedFilter],
    sort: Opt[SerializedSort],
    maxChanges: Opt[MaxChanges],
    upToId: Opt[Id],
    calculateTotal: bool,
): JsonNode
```

`anchorOffset` is emitted only when `anchor` is present. Apache James
3.9 rejects `anchorOffset` alongside an absent anchor with
`invalidArguments`; tying emission to anchor presence keeps the wire
request RFC-conformant against both Stalwart and James.

### 6.7 Decisions

**Decision D3.5: Referencable fields.** Only `GetRequest.ids` and
`SetRequest.destroy` receive `Referencable[T]` wrapping. These are the
canonical result-reference targets: `/ids` from a preceding query and
`/list/*/id` or `/updated` from a preceding get or changes call. All
other fields are direct values. Wrapping all fields in `Referencable`
is verbose and rarely used.

**Decision D3.6: Typed create/update/copy values, JsonNode for raw
slots.** Create entries (`SetRequest.create`, `CopyRequest.create`)
are typed: `MailboxCreate`, `EmailBlueprint`, `EmailCopyItem`, etc.
Each provides its own `toJson`. The whole-container update algebra
`U` is typed similarly. Response list slots remain `seq[JsonNode]` in
`GetResponse`, where entity-specific parsing happens at the caller.
The wire `"updated"[id]` server-set delta in `SetResponse.updateResults`
remains `Opt[JsonNode]` because update payloads are open-ended partial
entities — the entity-specific partial type is out of scope at this
layer; consumers parse it themselves.

**Module:** `methods.nim`

---

## 7. Serialisation Patterns

Layer 3 reuses Layer 2's serialisation infrastructure but defines its
own type-specific patterns.

**Decision D3.7:** Unidirectional serialisation: request types receive
`toJson` only; response types receive `fromJson` only. The client
builds requests (serialises) and parses responses (deserialises) —
never the reverse. `SetResponse[T]` and `CopyResponse[T]` additionally
expose `toJson` for round-trip testing of the wire-shape projection
(splitting merged Result tables back to parallel maps); production
code does not call these.

### 7.1 Pattern L3-A: Request `toJson` (Object Construction)

Build a `JsonNode` object. Omit keys for `none` fields. Use
`referencableKey` for `Referencable[T]` fields.

Canonical example — `GetRequest[T].toJson`:

```nim
func toJson*[T](req: GetRequest[T]): JsonNode =
  var node = newJObject()
  node["accountId"] = req.accountId.toJson()
  for idsVal in req.ids:
    let idsKey = referencableKey("ids", idsVal)
    case idsVal.kind
    of rkDirect:
      var arr = newJArray()
      for id in idsVal.value: arr.add(id.toJson())
      node[idsKey] = arr
    of rkReference:
      node[idsKey] = idsVal.reference.toJson()
  for props in req.properties:
    var arr = newJArray()
    for p in props: arr.add(%p)
    node["properties"] = arr
  return node
```

**Pattern L3-A invariants:**

- Required fields are always emitted.
- `none` fields are omitted (key absent). Uses `for val in opt:` for
  conditional consumption.
- `Referencable[T]` fields emit `"fieldName"` for `rkDirect` and
  `"#fieldName"` for `rkReference` via `referencableKey`. On the parse
  side, `fromJsonField` (Layer 2) rejects requests containing both
  forms (RFC §3.7 conflict detection).
- Boolean fields with RFC defaults (`false`) are emitted (current
  builder always materialises them to remove ambiguity).

### 7.2 Pattern L3-B: Response `fromJson` (Object Extraction)

`expectKind(node, JObject, path)` validates the root. Field extraction
uses Layer 2's typed accessors (`fieldJString`, `fieldJArray`,
`fieldJBool`, `fieldJInt`, `optJsonField`). Smart-constructor failures
bridge into the serde rail via `wrapInner(parser(...), path / "field")`.

Canonical example — `GetResponse[T].fromJson`:

```nim
func fromJson*[T](
    R: typedesc[GetResponse[T]],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[GetResponse[T], SerdeViolation] =
  discard $R   # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let stateNode = ?fieldJString(node, "state", path)
  let state = ?wrapInner(parseJmapState(stateNode.getStr("")), path / "state")
  let listNode = ?fieldJArray(node, "list", path)
  let list = listNode.getElems(@[])
  let notFound = ?parseOptIdArray(node{"notFound"}, path / "notFound")
  ok(GetResponse[T](
    accountId: accountId, state: state, list: list, notFound: notFound))
```

**Pattern L3-B invariants:**

- Root check: `?expectKind(node, JObject, path)`.
- Required fields: extract via `fieldJ*` (`svkMissingField` /
  `svkWrongKind` on failure), then bridge through `wrapInner` for
  smart-constructor validation.
- Server-assigned identifiers: use lenient constructors
  (`parseIdFromServer`, `parseAccountId`).
- Required `seq[Id]` fields: `parseIdArrayField` (strict — wrong kind
  is `svkWrongKind`).
- Supplementary `seq[Id]` fields (e.g. `notFound`): `parseOptIdArray`
  (lenient — absent/null/wrong-kind produces empty seq).
- Optional `Opt[T]` fields: lenient (absent/null/wrong-kind produces
  none) via the `optState`/`optUnsignedInt` helpers.
- Return type: `Result[T, SerdeViolation]`. Errors propagated via `?`.
- `discard $R` at the start consumes the type parameter for nimalyzer's
  `params` rule.

### 7.3 Pattern L3-C: SetResponse Merging (Parallel Maps to Unified Result Tables)

The wire format (RFC 8620 §5.3) uses parallel maps (`created`/`notCreated`,
`updated`/`notUpdated`, `destroyed`/`notDestroyed`). The internal
representation merges these into unified `Result` tables (Decision
3.9B), where each key maps to either a success value (`Result.ok`) or
a `SetError` (`Result.err`).

The merging algorithm is shared between `SetResponse` and
`CopyResponse` via `mergeCreateResults`. See §9.

### 7.4 Lenient Optional Helpers

```nim
func optState*(node: JsonNode, key: string): Opt[JmapState]
  ## Lenient: absent, null, wrong kind, or invalid content all → none.

func optUnsignedInt*(node: JsonNode, key: string): Opt[UnsignedInt]
  ## Lenient: same policy.
```

These bridge `optJsonField` (returns `Opt[JsonNode]`) and the smart
constructor's `Result` to `Opt[T]` via `.optValue`.

### 7.5 Expected JSON Kinds per Response Type

The table below lists the expected JSON kind for each field. Two
distinct validation mechanisms are used:

- **Strict via `expectKind` / `fieldJ*`:** wrong kind returns
  `err(svkWrongKind)`. Used for structurally critical fields.
- **Smart-constructor delegation through `wrapInner`:** `.getStr("")`
  feeds a smart constructor, which returns `err(ValidationError)` on
  empty/invalid input, bridged into `svkFieldParserFailed`.
- **Lenient (`optState` / `optUnsignedInt` / `parseOptIdArray`):**
  absent, null, or wrong kind produces `none` or empty default.

| Response Type | Root | Field-level expected kinds |
|---------------|------|--------------------------|
| `GetResponse[T]` | `JObject` | `accountId`, `state`: `JString` (smart-ctor); `list`: `JArray` (strict); `notFound`: lenient |
| `ChangesResponse[T]` | `JObject` | `accountId`, `oldState`, `newState`: `JString` (smart-ctor); `hasMoreChanges`: `JBool` (strict); `created`/`updated`/`destroyed`: `JArray` (strict) |
| `SetResponse[T]` | `JObject` | `accountId`: `JString` (smart-ctor); `oldState`/`newState`: lenient `Opt[JmapState]`; parallel maps: lenient (null/absent treated as empty) |
| `CopyResponse[T]` | `JObject` | Same shape as `SetResponse` for `created`/`notCreated` |
| `QueryResponse[T]` | `JObject` | `accountId`, `queryState`: smart-ctor; `canCalculateChanges`: `JBool`; `position`: `JInt` (smart-ctor); `ids`: `JArray`; `total`/`limit`: lenient |
| `QueryChangesResponse[T]` | `JObject` | `accountId`, `oldQueryState`/`newQueryState`: smart-ctor; `removed`: `JArray`; `added`: `JArray` (each elem via `AddedItem.fromJson`); `total`: lenient |

### 7.6 Opt[T] Leniency Policy

Layer 3 generalises Layer 2's lenient policy to all `Opt[T]` fields
because Layer 3 response types contain only simple scalar or
identifier `Opt` fields — no complex container `Opt`s.

For optional fields (`Opt[T]`): absent key, null value, or wrong JSON
kind all produce `Opt.none(T)`. For required fields, wrong kind
returns `err(SerdeViolation)`.

`SetResponse.newState` is `Opt[JmapState]` even though RFC 8620 §5.3
mandates the field. Stalwart 0.15.5 empirically omits `newState` for
/set responses with only failure rails populated; the library is
lenient on receive per Postel's law. Consumers needing the post-call
state fall back to `oldState` or to a fresh `Foo/get`. Same applies
to `CopyResponse.newState`.

**Exception — structurally critical required fields:** Required
fields that are structurally critical (e.g. `list: seq[JsonNode]` in
`GetResponse`) use strict `fieldJArray` — wrong kind returns
`err(svkWrongKind)`. A response without a `list` array is not a valid
`/get` response.

### 7.7 Layer 2 Infrastructure Imports

Layer 3's `methods.nim` imports the following from Layer 2 via the
`serialisation` re-export hub:

| Import | Source | Used for |
|--------|--------|----------|
| `JsonPath`, `emptyJsonPath`, `/` | `serde.nim` | Path tracking through nested fromJson |
| `expectKind` | `serde.nim` | Root JObject validation |
| `fieldJString`, `fieldJArray`, `fieldJBool`, `fieldJInt` | `serde.nim` | Required typed-field accessors |
| `optJsonField` | `serde.nim` | Lenient optional field access |
| `wrapInner` | `serde.nim` | Bridges ValidationError into SerdeViolation |
| `parseIdArrayField` | `serde.nim` | Strict `seq[Id]` extraction |
| `parseOptIdArray` | `serde.nim` | Lenient supplementary `seq[Id]` extraction |
| `toValidationError`, `serdeToMethodError` | `serde.nim` / `dispatch.nim` | Track conversion at boundaries |
| `toJson`/`fromJson` (primitives, identifiers) | `serde.nim` | Layer 1 serde |
| `referencableKey`, `fromJsonField` | `serde_envelope.nim` | Referencable[T] key dispatch |
| `toJson`/`fromJson` (envelope types) | `serde_envelope.nim` | Invocation, ResultReference, Request, Response |
| `MethodError.fromJson`, `SetError.fromJson` | `serde_errors.nim` | Dispatch error detection and merging |

**Module:** `methods.nim`

---

## 8. Per-Method Errors and Behavioural Semantics

Each standard method can return method-level errors. These are defined
as `MethodErrorType` variants in Layer 1 `errors.nim`. `MethodError`
is a plain object — it is data within a successful JMAP response.

### 8.1 General Method-Level Errors

**RFC reference:** §3.6.2 (lines 1137–1219)

The following general errors may be returned for **any** method call.
They are defined as `MethodErrorType` variants in Layer 1.

| Error | `MethodErrorType` variant | RFC reference |
|-------|--------------------------|---------------|
| `serverUnavailable` | `metServerUnavailable` | §3.6.2 (lines 1165–1167) |
| `serverFail` | `metServerFail` | §3.6.2 (lines 1169–1174) |
| `serverPartialFail` | `metServerPartialFail` | §3.6.2 (lines 1183–1185) |
| `unknownMethod` | `metUnknownMethod` | §3.6.2 (line 1187) |
| `invalidArguments` | `metInvalidArguments` | §3.6.2 (lines 1189–1193) |
| `invalidResultReference` | `metInvalidResultReference` | §3.6.2 (lines 1195–1196) |
| `forbidden` | `metForbidden` | §3.6.2 (lines 1198–1200) |
| `accountNotFound` | `metAccountNotFound` | §3.6.2 (lines 1202–1203) |
| `accountNotSupportedByMethod` | `metAccountNotSupportedByMethod` | §3.6.2 (lines 1205–1207) |
| `accountReadOnly` | `metAccountReadOnly` | §3.6.2 (lines 1209–1211) |

**Unknown error handling (§3.6.2 line 1217):** If the client receives
an error type it does not understand, it MUST treat it the same as
`serverFail`. `parseMethodErrorType` (Layer 1) maps unknown type
strings to `metUnknown`; `rawType` preserves the original string for
diagnostic purposes (lossless round-trip, Decision 1.7C).

### 8.2 Per-Method Additional Errors

**RFC reference:** §5.1–5.6.

| Method | Method-Level Error | Trigger |
|--------|-------------------|---------|
| /get | `requestTooLarge` | `ids` count exceeds server maximum |
| /changes | `cannotCalculateChanges` | server cannot compute delta |
| /set | `requestTooLarge` | total ops exceed server maximum |
| /set | `stateMismatch` | `ifInState` mismatch |
| /copy | `fromAccountNotFound` | invalid `fromAccountId` |
| /copy | `fromAccountNotSupportedByMethod` | from-account doesn't support type |
| /copy | `stateMismatch` | `ifInState` / `ifFromInState` mismatch |
| /query | `anchorNotFound` | anchor not in results |
| /query | `unsupportedSort` | unsupported property/collation |
| /query | `unsupportedFilter` | filter the server cannot process |
| /queryChanges | `tooManyChanges` | exceeds `maxChanges` |
| /queryChanges | `cannotCalculateChanges` | server cannot compute delta |

### 8.3 SetError Types (Per-Item Errors)

**RFC reference:** §5.3 (lines 2084–2164); §5.4 (lines 2317–2323) for
`alreadyExists`.

Per-item errors appear in `/set` and `/copy` responses within the
`notCreated`, `notUpdated`, and `notDestroyed` maps. Defined as
`SetErrorType` variants in Layer 1.

| SetError | Applies to | Variant-specific field |
|----------|------------|----------------------|
| `forbidden` | create, update, destroy | – |
| `overQuota` | create, update | – |
| `tooLarge` | create, update | – |
| `rateLimit` | create | – |
| `notFound` | update, destroy | – |
| `invalidPatch` | update | – |
| `willDestroy` | update | – |
| `invalidProperties` | create, update | `properties: seq[string]` |
| `singleton` | create, destroy | – |
| `alreadyExists` | copy | `existingId: Id` |

The Layer 1 `SetError` is a case object with variant-specific fields
for `invalidProperties` and `alreadyExists`; other variants use `else:
discard`. The `rawType` field is always populated for lossless round-
trip; `extras` preserves non-standard server fields. Constructors:
`setError(rawType, ...)` defensively maps `invalidProperties`/
`alreadyExists` to `setUnknown` when variant data is absent;
`setErrorInvalidProperties(...)` and `setErrorAlreadyExists(...)`
build the typed variants.

### 8.4 Behavioural Semantics

The following behavioural rules constrain client-side expectations and
are tested via the compliance suite.

**§3.5 Omitting Arguments.** An argument with a default value may be
omitted; the server treats omission as default.

**§3.3 Concurrency.** Method calls within a single request are
processed sequentially in order. The builder's sequential `add*` order
maps directly to server execution order.

**§5.1 /get.** `id` always returned even if not in `properties`.
Duplicate `ids` produce a single result. If `ids` is null, all records
are returned (subject to `maxObjectsInGet`). `requestTooLarge` when
exceeding the server maximum.

**§5.2 /changes.** A record created AND updated since the old state
SHOULD appear only in `created`. A record created AND destroyed SHOULD
be omitted entirely. `maxChanges` caps the total count across all
three arrays; the server may return intermediate states with
`hasMoreChanges: true`.

**§5.3 /set.** Each create/update/destroy is atomic; the `/set` as a
whole is NOT atomic. Creation IDs use `#` prefix for forward
references; the `createdIds` map spans the whole request. Errors are
recorded per-operation and processing continues.

**§5.4 /copy.** `destroyMode = destroyAfterSuccess(...)` triggers an
implicit `Foo/set` after successful copies. Dispatch via
`CompoundHandles[CopyResponse[T], SetResponse[T]]` (§4.6). `/copy` is
NOT atomic with the implicit `/set`. `alreadyExists` `SetError`
carries `existingId`.

**§5.5 /query.** If `anchor` is supplied, `position` is IGNORED.
`anchorOffset` is added to the anchor's index, clamped to 0. Negative
`position` is added to total, clamped to 0. If position >= total,
`ids` is empty. Negative `limit` produces `invalidArguments`.

**§5.6 /queryChanges.** `upToId` only optimises when both sort and
filter are on immutable properties. The splice algorithm: remove
`removed` IDs, insert `added` items by index (lowest first), truncate/
extend to new total.

**Module:** `methods.nim`

---

## 9. Standard Method Response Types

**RFC reference:** §5.1–5.6.

Each response type carries `##` doc comments on every field citing the
RFC section. Each receives a `fromJson` `func` (Pattern L3-B, §7.2)
returning `Result[T, SerdeViolation]`.

### 9.1 GetResponse[T]

**RFC reference:** §5.1 (lines 1613–1658)

```nim
type GetResponse*[T] = object
  accountId*: AccountId
  state*: JmapState
  list*: seq[JsonNode]
    ## Raw JsonNode entities; entity-specific parsing is the caller's
    ## responsibility (Decision D3.6).
  notFound*: seq[Id]
```

### 9.2 ChangesResponse[T]

**RFC reference:** §5.2 (lines 1704–1764)

```nim
type ChangesResponse*[T] = object
  accountId*: AccountId
  oldState*: JmapState
  newState*: JmapState
  hasMoreChanges*: bool
  created*: seq[Id]
  updated*: seq[Id]
  destroyed*: seq[Id]
```

`Mailbox` uses an extended composition `MailboxChangesResponse` (in
`mail/mailbox_changes_response.nim`) that adds the RFC 8621 §2.2
`updatedProperties` field. The two-parameter `addChanges[T, RespT]`
dispatches by entity through `changesResponseType(T)`.

### 9.3 SetResponse[T]

**RFC reference:** §5.3 (lines 2009–2082)

```nim
type SetResponse*[T] = object
  ## Wire format uses parallel maps; internal representation merges
  ## into unified Result maps (Decision 3.9B).
  ##
  ## ``T`` is the typed ``created`` entry payload. ``T.fromJson``
  ## resolves at instantiation via mixin to parse wire ``created[cid]``
  ## into ``T``.
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]
    ## Server state after the call. ``Opt.none`` when the server omits
    ## the field — Stalwart 0.15.5 empirically omits ``newState`` for
    ## /set responses with only failure rails populated.
  createResults*: Table[CreationId, Result[T, SetError]]
    ## Wire ``created`` entries become ``Result.ok(entity)`` via
    ## ``T.fromJson``; wire ``notCreated`` entries become
    ## ``Result.err(setError)``. Last-writer-wins on duplicate keys.
  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
    ## Wire ``updated`` entries with null value become
    ## ``ok(Opt.none(JsonNode))``; non-null become ``ok(Opt.some(...))``.
    ## Wire ``notUpdated`` become ``err(setError)``. Update payloads
    ## are open-ended partial entities — the entity-specific PatchObject
    ## shape is unknown at this layer; consumers parse it themselves.
  destroyResults*: Table[Id, Result[void, SetError]]
```

The typed-`T` semantics is materialised by entity modules: e.g.
`SetResponse[MailboxCreatedItem]`, `SetResponse[EmailCreatedItem]`,
`SetResponse[IdentityCreatedItem]`. Each `*CreatedItem` type carries
the RFC 8620 §5.3 server-set subset (`id` plus server-set fields like
`mayDelete`, `myRights`, count fields) and provides its own
`fromJson` resolved through `mixin` inside `mergeCreateResults`.

**Decision 3.9B: Unified Result maps.** The wire's parallel maps are
merged into unified `Table[K, Result[V, SetError]]`. Each key maps to
either success or failure. Single point of lookup per identifier;
composes naturally with nim-results combinators.

### 9.4 CopyResponse[T]

**RFC reference:** §5.4 (lines 2273–2323)

```nim
type CopyResponse*[T] = object
  fromAccountId*: AccountId
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]
  createResults*: Table[CreationId, Result[T, SetError]]
```

Shares the typed-`T` semantics of `SetResponse[T]`.
`CopyResponse[EmailCreatedItem]` is the canonical instantiation.

### 9.5 QueryResponse[T]

**RFC reference:** §5.5 (lines 2541–2614)

```nim
type QueryResponse*[T] = object
  accountId*: AccountId
  queryState*: JmapState
  canCalculateChanges*: bool
  position*: UnsignedInt
  ids*: seq[Id]
  total*: Opt[UnsignedInt]
  limit*: Opt[UnsignedInt]
```

### 9.6 QueryChangesResponse[T]

**RFC reference:** §5.6 (lines 2695–2796)

```nim
type QueryChangesResponse*[T] = object
  accountId*: AccountId
  oldQueryState*: JmapState
  newQueryState*: JmapState
  total*: Opt[UnsignedInt]
  removed*: seq[Id]
  added*: seq[AddedItem]
```

**Module:** `methods.nim`

---

## 10. SetResponse Merging Algorithm

**RFC reference:** §5.3 (lines 2009–2082) — wire format uses six
parallel maps. Internal representation merges these into unified
`Result` tables (Decision 3.9B).

### 10.1 Create Merging

```nim
func mergeCreateResults*[T](
    node: JsonNode, path: JsonPath
): Result[Table[CreationId, Result[T, SetError]], SerdeViolation] =
  ## Used by both SetResponse and CopyResponse. ``T.fromJson`` resolves
  ## at instantiation via mixin — every T appearing in
  ## SetResponse[T]/CopyResponse[T] MUST define
  ## ``fromJson(_: typedesc[T], JsonNode, JsonPath): Result[T, SerdeViolation]``.
  mixin fromJson
  var tbl = initTable[CreationId, Result[T, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "created" / k)
      let entity = ?T.fromJson(v, path / "created" / k)
      tbl[cid] = Result[T, SetError].ok(entity)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "notCreated" / k)
      let se = ?SetError.fromJson(v, path / "notCreated" / k)
      tbl[cid] = Result[T, SetError].err(se)
  ok(tbl)
```

### 10.2 Update Merging

```nim
func mergeUpdateResults(
    node: JsonNode, path: JsonPath
): Result[Table[Id, Result[Opt[JsonNode], SetError]], SerdeViolation]
```

Null value in `updated` maps to `ok(Opt.none(JsonNode))` (server made
no changes the client doesn't already know); non-null maps to
`ok(Opt.some(v))` verbatim. The library passes the raw node through
because the entity-specific `PatchObject` shape is unknown at this
layer; consumers parse it themselves. `notUpdated` entries go through
`SetError.fromJson` and are strict.

### 10.3 Destroy Merging

```nim
func mergeDestroyResults(
    node: JsonNode, path: JsonPath
): Result[Table[Id, Result[void, SetError]], SerdeViolation]
```

`destroyed` is a flat array on the wire; each ID becomes `Result.ok()`.

### 10.4 Wire Round-Trip Helpers

`SetResponse[T]` and `CopyResponse[T]` additionally expose `toJson`
that splits the merged Result tables back to the parallel wire shape:

```nim
func toJson*[T](resp: SetResponse[T]): JsonNode
func toJson*[T](resp: CopyResponse[T]): JsonNode
```

Internal helpers:

- `emitSplitCreateResults` — splits `createResults` into `created` and
  `notCreated`. `T.toJson` resolves via mixin.
- `emitSplitUpdateResults` — splits `updateResults` into `updated` and
  `notUpdated`. `Opt.none` projects to JSON null.
- `emitSplitDestroyResults` — splits `destroyResults` into `destroyed`
  and `notDestroyed`. Empty buckets omit their key.

These are used primarily by serde tests and fixtures. Production code
consumes responses, never emits them — but the round-trip is load-
bearing for serde test infrastructure.

### 10.5 Invariants

- **Completeness.** Every identifier from both success and failure
  wire maps appears in the output table. No entries dropped.
- **Last-writer-wins.** If an identifier appears in both maps (server
  bug), the failure map wins. Failure maps are processed second; the
  `tbl[key] =` assignment overwrites any previous success entry.
- **SetError fidelity.** `SetError.fromJson` preserves `rawType` and
  `extras` for lossless round-trip. Unknown error types map to
  `setUnknown` with `rawType` preservation.
- **CopyResponse reuse.** `CopyResponse.fromJson` uses the identical
  `mergeCreateResults` helper. Only the create branch is needed.
- **Error propagation.** `parseCreationId`, `parseIdFromServer`,
  `T.fromJson`, and `SetError.fromJson` failures propagate via `?` —
  a malformed key or SetError aborts the entire parse.

**Module:** `methods.nim` (inside `SetResponse.fromJson` and
`CopyResponse.fromJson`).

---

## 11. Core/echo Method

**RFC reference:** §4 (lines 1540–1561)

The `Core/echo` method returns the same arguments as given. Used for
testing connectivity to the JMAP API endpoint.

```json
Request:  [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
Response: [["Core/echo", {"hello": true, "high": 5}, "b3ff"]]
```

`addEcho` (§3.8.1) returns `(RequestBuilder, ResponseHandle[JsonNode])`.
Extraction uses the callback overload of `get[T]` (§4.5.2) with a
`fromArgs` that wraps the raw `JsonNode` in `Result.ok`.

---

## 12. Result Reference Construction

**Architecture decision:** 3.10A (typed paths via `RefPath` enum, no
runtime validation).

**RFC reference:** §3.7 (lines 1220–1493) — result references allow a
method call to refer to the output of a previous call's response
within the same request.

### 12.1 Path Constants

`RefPath` enum (Layer 1, §1.3) provides:

| Variant | Backing string | Source |
|---------|----------------|--------|
| `rpIds` | `"/ids"` | IDs from /query result |
| `rpListIds` | `"/list/*/id"` | IDs from /get result |
| `rpAddedIds` | `"/added/*/id"` | IDs from /queryChanges result |
| `rpCreated` | `"/created"` | Created IDs from /changes |
| `rpUpdated` | `"/updated"` | Updated IDs from /changes |
| `rpUpdatedProperties` | `"/updatedProperties"` | Mailbox/changes (RFC 8621 §2.2) |
| `rpListThreadId` | `"/list/*/threadId"` | Thread IDs from /get (RFC 8621 §4.10) |
| `rpListEmailIds` | `"/list/*/emailIds"` | Email IDs from Thread/get (RFC 8621 §4.10) |

### 12.2 Generic Reference Function

```nim
func reference*[T](
    handle: ResponseHandle[T],
    name: MethodName,
    path: RefPath,
): ResultReference =
  ## Constructs a ResultReference (RFC 8620 §3.7). Both ``name`` and
  ## ``path`` are typed enums; the wire form uses their backing strings.
  initResultReference(resultOf = callId(handle), name = name, path = path)
```

### 12.3 Type-Safe Reference Convenience Functions

These constrain the `ResponseHandle` type parameter to specific
response types, making illegal states unrepresentable. Each auto-
derives the response method name from the per-verb resolver via
`mixin`.

```nim
func idsRef*[T](handle: ResponseHandle[QueryResponse[T]]): Referencable[seq[Id]]
  ## /ids from a /query response. Resolves queryMethodName(T) via mixin.

func listIdsRef*[T](handle: ResponseHandle[GetResponse[T]]): Referencable[seq[Id]]
  ## /list/*/id from a /get response.

func addedIdsRef*[T](
    handle: ResponseHandle[QueryChangesResponse[T]]
): Referencable[seq[Id]]
  ## /added/*/id from a /queryChanges response.

func createdRef*[T](
    handle: ResponseHandle[ChangesResponse[T]]
): Referencable[seq[Id]]
  ## /created from a /changes response.

func updatedRef*[T](
    handle: ResponseHandle[ChangesResponse[T]]
): Referencable[seq[Id]]
  ## /updated from a /changes response.
```

**Decision D3.10:** The generic `reference()` takes an explicit `name`
parameter. Convenience functions auto-derive the name from the per-
verb resolver because each is constrained to a specific response type
where the verb is known. Different methods produce different response
names — the generic function does not assume.

**Module:** `dispatch.nim`

---

## 13. Pipeline Combinators (`convenience.nim`)

**Module:** `convenience.nim` — **NOT** re-exported by `protocol.nim`.
Users who want pipeline combinators must explicitly
`import jmap_client/convenience`. This physical separation keeps the
core API surface in `builder.nim` and `dispatch.nim` frozen while
providing opt-in ergonomics.

### 13.1 Query-then-Get Pipeline

```nim
type QueryGetHandles*[T] = object
  query*: ResponseHandle[QueryResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

template addQueryThenGet*[T](b: RequestBuilder, accountId: AccountId
): (RequestBuilder, QueryGetHandles[T]) =
  ## Adds Foo/query + Foo/get with automatic /ids result reference wiring.
  ##
  ## Implicit decisions:
  ## - Reference path is always /ids (rpIds)
  ## - Both calls use the same accountId
  ## - No filter, sort, or properties constraints applied
  ## - Response method name derived from queryMethodName(T)
  block:
    let (b1, qh) = addQuery[T](b, accountId)
    let (b2, gh) = addGet[T](b1, accountId, ids = Opt.some(qh.idsRef()))
    (b2, QueryGetHandles[T](query: qh, get: gh))
```

### 13.2 Changes-then-Get Pipeline

```nim
type ChangesGetHandles*[T] = object
  changes*: ResponseHandle[ChangesResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

func addChangesToGet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ChangesGetHandles[T]) =
  ## Adds Foo/changes + Foo/get with automatic /created result reference.
  ## Uses the standard ChangesResponse[T] directly rather than
  ## changesResponseType(T) because createdRef is defined only over
  ## ResponseHandle[ChangesResponse[T]] — its contract is the RFC 8620
  ## §5.2 /created field, not any entity-specific extension.
  ##
  ## Implicit decisions:
  ## - Reference path is /created (rpCreated) — fetches newly created IDs
  ##   only. For updated IDs, use the core API with updatedRef.
  ## - Both calls use the same accountId
  let (b1, ch) = addChanges[T, ChangesResponse[T]](
    b, accountId, sinceState, maxChanges)
  let (b2, gh) = addGet[T](
    b1, accountId, ids = Opt.some(ch.createdRef()), properties = properties)
  (b2, ChangesGetHandles[T](changes: ch, get: gh))
```

### 13.3 Paired Extraction

```nim
type QueryGetResults*[T] = object
  query*: QueryResponse[T]
  get*: GetResponse[T]

func getBoth*[T](resp: Response, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], MethodError]
  ## Extracts both query and get responses, failing on the first error.

type ChangesGetResults*[T] = object
  changes*: ChangesResponse[T]
  get*: GetResponse[T]

func getBoth*[T](resp: Response, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], MethodError]
```

These `getBoth` overloads are distinct from the `dispatch.nim`
overloads on `CompoundHandles[A, B]` and `ChainedHandles[A, B]`; the
compiler selects by argument type.

---

## 14. Round-Trip Invariants

Layer 3's serialisation is unidirectional for request types and
bidirectional for the merged-Result response types (`SetResponse`,
`CopyResponse`); `GetResponse`/`ChangesResponse`/`QueryResponse`/
`QueryChangesResponse` are `fromJson`-only. The following invariants
hold:

1. **Builder identity.** `builder.build().toJson()` produces valid
   JMAP request JSON. Parsing it back via `Request.fromJson` (Layer
   2) recovers the envelope structure — method calls, capabilities,
   and creation IDs all round-trip.

2. **Response identity.** For any valid server response JSON `j`,
   `GetResponse[T].fromJson(j)` produces an `ok` value whose fields
   match the JSON content. Invalid JSON returns `err(SerdeViolation)`.
   Same applies to all six response types.

3. **SetResponse round-trip.** `SetResponse[T].toJson(SetResponse[T].fromJson(j).get())`
   produces JSON structurally equal to the original wire shape after
   merging-and-splitting. Same for `CopyResponse[T]`.

4. **SetResponse losslessness.** Merging preserves ALL success AND
   failure entries in unified `Result` tables. Success entries
   correspond to wire `created`/`updated`/`destroyed`; failure entries
   correspond to wire `notCreated`/`notUpdated`/`notDestroyed`.

5. **Opt omission symmetry.** `none` produces no key in `toJson`;
   absent key produces `none` in `fromJson` (lenient policy, §7.6).

6. **Referencable dispatch.** `rkDirect` serialises without `#`
   prefix; `rkReference` serialises with `#` prefix. `fromJsonField`
   rejects input where both `"foo"` and `"#foo"` are present.

7. **Method error preservation.** `MethodError.fromJson(errorJson)`
   preserves `rawType` (lossless, same as Layer 1/Layer 2 error
   types).

---

## 15. Opt[T] Field Handling Convention

All `Opt[T]` fields in Layer 3 types follow the policy defined in
§7.6. Request types (`toJson`): omit key when `none`, using `for val
in opt:` for conditional consumption. Response types (`fromJson`):
absent, null, or wrong kind produces `none` (lenient).

The complete list of `Opt` fields is derivable from the type
definitions in §6 (request types) and §9 (response types).

---

## 16. Module File Layout

### 16.1 Source Files

```
src/jmap_client/
  methods_enum.nim — MethodName, MethodEntity, RefPath enums and
                     parseMethodName
  entity.nim       — registerJmapEntity, registerQueryableEntity,
                     registerSettableEntity templates with when-not-
                     compiles domain-specific error messages
  methods.nim      — 4 request types (GetRequest[T]/ChangesRequest[T]/
                     SetRequest[T,C,U]/CopyRequest[T,CopyItem]) +
                     CopyDestroyModeKind enum + CopyDestroyMode case
                     object + ``keepOriginals`` / ``destroyAfterSuccess``
                     smart constructors;
                     6 response types (GetResponse[T]/ChangesResponse[T]/
                     SetResponse[T]/CopyResponse[T]/QueryResponse[T]/
                     QueryChangesResponse[T]);
                     SerializedSort/SerializedFilter pre-serialised
                     distinct wrappers + ``toJsonNode`` accessors;
                     ``serializeOptSort``/``serializeOptFilter``/
                     ``serializeFilter``; ``assembleQueryArgs``/
                     ``assembleQueryChangesArgs``;
                     ``toJson`` for the 4 request types + ``SetResponse``
                     + ``CopyResponse``;
                     ``fromJson`` for all 6 response types;
                     ``mergeCreateResults`` (exported, generic over T) +
                     internal ``mergeUpdateResults``/``mergeDestroyResults``;
                     internal ``emitSplitCreateResults``/
                     ``emitSplitUpdateResults``/``emitSplitDestroyResults``;
                     lenient ``optState``/``optUnsignedInt`` exports.
                     ``/query`` and ``/queryChanges`` use the serialise-
                     then-assemble pattern (Decision D3.14) — no
                     dedicated request types.
  builder.nim      — Immutable RequestBuilder, initRequestBuilder
                     (pre-declares core capability), build, nextId,
                     withCapability, addInvocation (typed MethodName),
                     addMethodImpl template, addEcho, addGet, addChanges
                     (proc + template), addSet (proc + template),
                     addCopy (proc + template), addQuery (proc + template),
                     addQueryChanges (proc + template),
                     directIds, initCreates
  dispatch.nim     — ResponseHandle[T] + (==, $, hash, callId);
                     NameBoundHandle[T] + (==, $, hash);
                     serdeToMethodError closure factory;
                     findInvocation/extractInvocation;
                     findInvocationByName/extractInvocationByName;
                     get[T] (mixin + callback + NameBoundHandle overloads);
                     CompoundHandles[A,B] + CompoundResults[A,B] +
                     getBoth + registerCompoundMethod;
                     ChainedHandles[A,B] + ChainedResults[A,B] +
                     getBoth + registerChainableMethod;
                     reference; idsRef, listIdsRef, addedIdsRef,
                     createdRef, updatedRef
  protocol.nim     — Re-export hub: imports and re-exports entity,
                     methods, dispatch, builder. methods_enum is
                     transitively exported via types.nim.
  convenience.nim  — Optional pipeline combinators (NOT re-exported
                     by protocol.nim): QueryGetHandles, addQueryThenGet,
                     ChangesGetHandles, addChangesToGet, QueryGetResults,
                     ChangesGetResults, getBoth (two overloads)
```

### 16.2 Import DAG

```
types.nim (L1 hub) ←── serialisation.nim (L2 hub)
                            ^         ^         ^         ^
                            |         |         |         |
                         entity   methods   builder   dispatch
                            |         ^         ^         ^
                            |         |         |         |
                            └─────────┴─────────┴─────────┘
                                          |
                                     protocol.nim
                                          ^
                                          |
                                    convenience.nim
```

- `methods_enum.nim` is a Layer 1 module re-exported by `types.nim`.
- `entity.nim` imports nothing (pure templates).
- `methods.nim` imports: `std/json`, `std/tables`, `types`,
  `serialisation`.
- `dispatch.nim` imports: `std/hashes`, `std/json`, `types`,
  `serialisation`, `methods`.
- `builder.nim` imports: `std/json`, `std/tables`, `types`,
  `serialisation`, `methods`, `dispatch`.
- `protocol.nim` imports and re-exports: `entity`, `methods`,
  `dispatch`, `builder`.
- `convenience.nim` imports: `types`, `methods`, `dispatch`,
  `builder`.

No cycles. Each module independently testable.

### 16.3 Test Files

```
tests/
  mtest_entity.nim — Shared mock entity (TestWidget) with filter
                     condition type (TestWidgetFilter), all framework
                     overloads (methodEntity, capabilityUri, per-verb
                     resolvers, filterType, filter toJson),
                     registerJmapEntity + registerQueryableEntity, and
                     toJson/fromJson. Reference implementation of the
                     entity module checklist.

tests/protocol/
  tentity.nim      — Mock entity satisfies framework requirements;
                     registerJmapEntity / registerQueryableEntity /
                     registerSettableEntity compile-time checks;
                     missing overload detection
  tmethods.nim     — Request toJson for all types; response fromJson
                     for all 6 types; SetResponse/CopyResponse merging;
                     pre-serialise + assembly helpers
  tbuilder.nim     — Builder construction, immutability, call ID
                     generation, pre-declared core capability,
                     capability deduplication, all add* functions
                     including extras parameter, single-type-parameter
                     templates, argument construction helpers
  tdispatch.nim    — ResponseHandle / NameBoundHandle extraction;
                     mixin and callback get[T] overloads;
                     CompoundHandles + ChainedHandles getBoth;
                     error detection; serdeToMethodError; reference
                     construction; type-safe convenience functions
  tconvenience.nim — Pipeline combinator tests: addQueryThenGet,
                     addChangesToGet, getBoth extraction
```

### 16.4 Module Boilerplate

Every Layer 3 source module:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}
```

`{.push raises: [], noSideEffect.}` enforces that no `CatchableError`
escapes any function and no observable side effect occurs.
`{.experimental: "strictCaseObjects".}` makes case-object discriminator
mismatches a compile-time error.

Every `func` must have a `##` docstring (nimalyzer `hasDoc` rule).
Comments and docstrings use British English spelling. Variable names
and code identifiers use US English spelling.

---

## 17. Test Fixtures

### 17.1 Golden Test 1: Query to Get with Result Reference

Builder constructs `Mailbox/query` followed by `Mailbox/get` where
`ids` references `/ids` from the query response.

```json
{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/query", {
      "accountId": "A13824",
      "position": 0,
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

- `req.using == @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"]`
  (core pre-declared; mail registered by the first `add*`).
- `req.methodCalls.len == 2`.
- `req.methodCalls[0].rawName == "Mailbox/query"`,
  `req.methodCalls[0].name == mnMailboxQuery`.
- `req.methodCalls[0].methodCallId == MethodCallId("c0")`.
- `req.methodCalls[1].arguments{"#ids"}` contains a `ResultReference`
  with `resultOf == "c0"`, `name == mnMailboxQuery`, `path == rpIds`.
- `anchorOffset` is omitted because no anchor was supplied.

### 17.2 Golden Test 2: Set with Create/Update/Destroy

Builder constructs `Mailbox/set` with all three operations using
typed creates (`MailboxCreate`) and the whole-container update algebra
(`NonEmptyMailboxUpdates`).

```json
{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/set", {
      "accountId": "A13824",
      "ifInState": "abc123",
      "create": {
        "k1": {"name": "New Item"}
      },
      "destroy": ["id2", "id3"],
      "update": {
        "id1": {"name": "Updated"}
      }
    }, "c0"]
  ]
}
```

The wire-key order matches `SetRequest[T, C, U].toJson`: `accountId`,
`ifInState`, `create`, `destroy`, `update`.

### 17.3 Golden Test 3: SetResponse Merging

Wire-format JSON with mixed success and failure entries, parsed as
`SetResponse[MailboxCreatedItem]`:

```json
{
  "accountId": "A13824",
  "oldState": "state1",
  "newState": "state2",
  "created": {
    "k1": {"id": "id-new-1", "totalEmails": 0}
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

- `createResults[k1]` is `Result.ok(MailboxCreatedItem(...))`,
  `createResults[k2]` is `Result.err(SetError(setForbidden, ...))`.
- `updateResults[id1]` is `Result.ok(Opt.none(JsonNode))`,
  `updateResults[id2]` is `Result.ok(Opt.some(JsonNode))`,
  `updateResults[id3]` is `Result.err(SetError(setNotFound, ...))`.
- `destroyResults[id4]` is `Result.ok()`,
  `destroyResults[id5]` is `Result.err(SetError(setForbidden, ...))`.
- `oldState.isSome` and `oldState.get == JmapState("state1")`,
  `newState.isSome` and `newState.get == JmapState("state2")`.

When the server omits `newState` (Stalwart 0.15.5 with all-failure
rails), `newState.isNone`.

### 17.4 Edge Cases

| Component | Input | Expected | Reason |
|-----------|-------|----------|--------|
| **GetResponse** | Valid JSON with all fields | `ok(GetResponse)` | Happy path |
| GetResponse | Missing `state` | `err(svkMissingField)` | Required field |
| GetResponse | `state` is JInt | `err(svkWrongKind)` | `fieldJString` rejects |
| GetResponse | `list` is JString | `err(svkWrongKind)` | `fieldJArray` rejects |
| GetResponse | `notFound` absent | `ok` with empty `notFound` | Supplementary, lenient |
| GetResponse | `accountId` empty string | `err(svkFieldParserFailed)` | `parseAccountId` rejects via `wrapInner` |
| **ChangesResponse** | `hasMoreChanges` is JString | `err(svkWrongKind)` | Required `JBool` |
| ChangesResponse | `hasMoreChanges` absent | `err(svkMissingField)` | Required field |
| **SetResponse** | Both `created` and `notCreated` null | Empty `createResults` | Both treated as absent |
| SetResponse | Same id in `created` and `notCreated` | Last-writer-wins (failure) | Defensive — server bug |
| SetResponse | `oldState` absent | `oldState.isNone` | Server doesn't know |
| SetResponse | `newState` absent | `newState.isNone` | Stalwart compatibility |
| SetResponse | `notCreated` value missing `type` | `err` from `SetError.fromJson` | `SetError` requires type |
| SetResponse | `notCreated` value unknown type | `createResults` entry with `err(setUnknown)` | `rawType` preserved |
| **CopyResponse** | `notCreated` `alreadyExists` with `existingId` | `err(setAlreadyExists, existingId: ...)` | Variant-typed |
| CopyResponse | `alreadyExists` with malformed `existingId` | `err(setUnknown)`, `rawType="alreadyExists"` | Graceful degradation |
| **QueryResponse** | `total` absent | `total.isNone` | `calculateTotal` false |
| QueryResponse | `position` is JString | `err(svkWrongKind)` | `fieldJInt` rejects |
| QueryResponse | `canCalculateChanges` missing | `err(svkMissingField)` | Required field |
| **QueryChangesResponse** | `added` with invalid `index` | `err(svkFieldParserFailed)` | Propagated from `AddedItem.fromJson` |
| **Request toJson** | `GetRequest` with all none | `{"accountId": "..."}` only | Opt omission |
| `assembleQueryArgs` | `QueryParams` with `anchor` set | Includes `anchorOffset` alongside `anchor` | RFC §5.5 |
| `assembleQueryArgs` | `QueryParams` without `anchor` | Omits `anchorOffset` | James 3.9 strict-mode |
| Request toJson | `CopyRequest` with `keepOriginals()` | Omits `onSuccessDestroyOriginal` | RFC default |
| Request toJson | `CopyRequest` with `destroyAfterSuccess(none)` | Emits `onSuccessDestroyOriginal: true`, omits `destroyFromIfInState` | Optional state-guard |

---

## 18. Design Decisions Summary

| ID | Decision | Alternative considered | Rationale |
|----|----------|----------------------|-----------|
| D3.1 | Layer 3 owns serialisation of Layer 3–defined types | Add new Layer 2 modules | Layer 3 types are generic over `T`/`C`/`U`/etc.; their serde depends on entity-specific resolution that only Layer 3 has. |
| D3.2 | `add*` params match RFC request fields; required positional, optional defaulted; `extras` for entity-specific extension keys | Single generic `addMethod(name, argsJson)` | Type-safe per-method discoverable interface; `extras` keeps the door open for entity-specific keys without bloating the framework. |
| D3.3 | Response dispatch returns `Result[T, MethodError]` | Unified `ClientError` for all failures | Method errors are data within a successful HTTP 200 response. Per-invocation, not per-request. |
| D3.4 | No concepts; plain overloaded `typedesc` `func`s + `registerJmapEntity` / `registerQueryableEntity` / `registerSettableEntity` compile-time checks; per-verb resolver overloads (`getMethodName`, `setMethodName`, …) | Concepts | Plain overloads + static registration give earlier error detection than concepts with zero compiler risk. Per-verb resolvers make invalid `(entity, verb)` combinations a compile error. |
| D3.5 | Only `GetRequest.ids` and `SetRequest.destroy` get `Referencable[T]` | All fields `Referencable` | Wrapping all fields is verbose and rarely used. Two wrapped fields cover canonical patterns. |
| D3.6 | Typed `C`, `U`, `CopyItem` create/update/copy values; `seq[JsonNode]` for `GetResponse.list`; `Opt[JsonNode]` for `SetResponse.updateResults` | Either fully typed or fully `JsonNode` | Typed creates close the illegal-state hole at the boundary; raw `JsonNode` for response lists preserves entity-agnostic layering; raw `JsonNode` for update payloads matches RFC's open-ended PatchObject shape. |
| D3.7 | Unidirectional serde for request types (`toJson` only) and response types (`fromJson` only); bidirectional for `SetResponse`/`CopyResponse` to support round-trip serde tests | Full bidirectional serde for all types | Client builds requests and parses responses — never the reverse. The `SetResponse`/`CopyResponse` `toJson` exists exclusively for fixture round-trip. |
| D3.8 | Immutable `RequestBuilder`; each `add*` returns `(RequestBuilder, ResponseHandle[T])` | `var RequestBuilder` mutation | Pure functional composition; no observable side effects; trivially threads through `for`-comprehensions and pipelines. |
| D3.9 | `nextId` uses `MethodCallId(s)` directly (bypassing validation); `initInvocation` is the typed (infallible) constructor | Validating constructors at every step | The builder controls the format entirely; typed `MethodName` makes empty wire names unrepresentable. |
| D3.10 | `reference()` takes `(MethodName, RefPath)` typed enums; convenience functions auto-derive `MethodName` from per-verb resolver | String-typed name/path | Typed enums prevent typos and enforce 1:1 wire round-trip; the catch-all `mnUnknown` is never emitted because builders are statically typed. |
| D3.11 | `MaxChanges` distinct type (Layer 1) for `maxChanges` fields | `Opt[UnsignedInt]` with runtime/server rejection | RFC §5.2 requires > 0. Distinct type makes illegal state unrepresentable. |
| D3.12 | `SetRequest[T, C, U]` with three generic parameters | Single `T` with `JsonNode` create/update | Typed creates and update algebra are validated at the boundary; `mixin` resolves `C.toJson`/`U.toJson` at instantiation. |
| D3.13 | `CopyRequest[T, CopyItem]` + `CopyDestroyMode` case object | Flat `onSuccessDestroyOriginal: bool` + `destroyFromIfInState: Opt[JmapState]` | The case object makes unrepresentable a state-guard alongside no-implicit-destroy, which is structurally expressible under flat fields but semantically meaningless. |
| D3.14 | Query/QueryChanges built via serialise-then-assemble (`SerializedSort`/`SerializedFilter` + `assembleQueryArgs`) instead of dedicated `QueryRequest` types | A `QueryRequest[T, C]` type with full serde | The pre-serialise step lets the builder decouple sort element type from filter condition type; entity-specific sort variants (e.g. `EmailComparator`) compose without a new request type. |
| D3.15 | Pre-declare `urn:ietf:params:jmap:core` in `initRequestBuilder` | Leave `using` empty | Apache James 3.9 rejects requests omitting `core`; Stalwart accepts both. Pre-declaring keeps the client portable. |
| D3.16 | Layer 3 `fromJson` returns `Result[T, SerdeViolation]`; dispatch translates to `MethodError` via `serdeToMethodError($T)` | Direct `Result[T, MethodError]` from fromJson | `SerdeViolation` carries `JsonPath` and structured cause; the translation site is the natural point to add the response type as root context. |
| 3.9B | Unified `Result` maps for SetResponse/CopyResponse | Separate success/failure tables | Single point of lookup per identifier. Composes with nim-results combinators. Last-writer-wins on duplicates. |

### Deferred Decisions

| ID | Topic | Disposition | Rationale |
|----|-------|-------------|-----------|
| R4 | `GetRequest.properties` as `Referencable` | Deferred | The `#properties` / `updatedProperties` pattern is real and canonical for Mailbox sync, but Mailbox-specific. |
| R7 | Convenience overloads for `addGet` / `addSet` beyond the single-T templates | Deferred to post-implementation | Technically sound but additive. |

### MaxChanges Type (Layer 1)

The `maxChanges` fields in `ChangesRequest[T]` (§6.2) and `addQueryChanges`
(§3.8.7) must be "a positive integer greater than 0" per RFC §5.2.
A `MaxChanges` distinct type with a smart constructor closes this gap:

```nim
type MaxChanges* = distinct UnsignedInt
  ## A positive count used for maxChanges fields in Foo/changes and
  ## Foo/queryChanges requests. RFC 8620 §5.2 requires > 0.

defineIntDistinctOps(MaxChanges)

func parseMaxChanges*(raw: UnsignedInt): Result[MaxChanges, ValidationError]
```
