# Architecture Options Analysis

Cross-platform JMAP (RFC 8620) client library in Nim with C ABI exports.

## Foundational Decisions

Five architectural decisions that constrain all subsequent choices:

1. **C ABI strategy: Approach A (rich Nim internals, thin C wrapper).** Build an
   idiomatic Nim library first. Add a separate C ABI layer that exposes opaque handles
   and accessor functions. The Nim API is the "real" API; the C ABI is a lossy
   projection of it.

2. **Decomposition: bottom-up by layer.** Each layer depends only on layers below it.
   Fully testable in isolation before the next layer is built.

3. **Definition of done: all 6 standard method patterns work with result references.**
   `/get`, `/set`, `/changes`, `/query`, `/queryChanges`, `/copy` — all functional,
   with result reference support for chaining method calls within a single request.

4. **No external dependencies.** All imports are from Nim's standard library
   (`std/options`, `std/json`, `std/tables`, `std/httpclient`, etc.). Optional
   values use `Option[T]` from `std/options`.

5. **Five-layer decomposition.** Each layer boundary corresponds to a genuine
   change in the nature of the code: pure algebraic data types (Layer 1), JSON
   parsing (Layer 2), protocol logic (Layer 3), IO (Layer 4), FFI (Layer 5).
   See "Why 5 Layers" below.

## Design Principles

The library follows these principles throughout:

- **Functional Core, Imperative Shell** — domain logic (Layers 1–3) does not
  perform I/O or mutate global state by convention. IO confined to a narrow
  boundary at the transport layer (Layer 4). Purity maintained by convention
  and code review, not by compiler enforcement.
- **Exception-based error handling** — smart constructors raise `ValidationError`
  on invalid input. Transport failures raise `ClientError`. Layer 5 (C ABI)
  catches all `CatchableError` exceptions and converts them to C error codes.
  Method errors (`MethodError`) and set errors (`SetError`) are data within
  successful responses, not exceptions.
- **Immutability by default** — `let` bindings everywhere. `var` is permitted
  in three patterns: (a) mutable accumulators in Layer 4/5; (b) local variable
  inside a `proc` when building a return value from stdlib containers whose
  APIs require mutation (e.g., `Table`); (c) `var` parameter for builder
  accumulation.
- **Parse, don't validate** — deserialisation produces well-typed values or
  raises structured errors. Invariants enforced at parse time, not checked later.
- **Make illegal states unrepresentable** — variant types, distinct types, and
  smart constructors encode domain invariants in the type system where the type
  system permits. Some invariants (e.g., `Invocation.arguments` must be a JSON
  object, not an array) are enforced at construction time by Layer 2 parsing
  and Layer 3 builders rather than by the Layer 1 type definition, because
  `JsonNode` is an opaque stdlib type that cannot be further constrained
  without a wrapper.
- **Dual validation strictness** — accept server-generated data leniently
  (tolerating minor RFC deviations such as non-base64url ID characters),
  construct client-generated data strictly. Both paths raise `ValidationError`
  on truly invalid input — neither silently accepts garbage. Strict
  constructors are used when the client creates values; lenient constructors
  are used during JSON deserialisation of server responses.

## Compiler Configuration

### Flags

| Setting | Reason |
|---------|--------|
| `mm:arc` | Required for FFI shared library — deterministic destruction, no GC |
| `strictDefs` | Forces explicit initialisation of all variables |
| `threads:on` | Threading support |
| `panics:on` | Defects (programmer errors) abort the process immediately |
| `floatChecks:on` | Float overflow/underflow detection |
| `overflowChecks:on` | Integer overflow detection |
| `styleCheck:error` | Naming consistency enforcement |
| `warningAsError` (extensive) | All on-by-default warnings promoted to errors; plus `BareExcept`, `AnyEnumConv`, `StdPrefix` explicitly enabled |
| `hintAsError: DuplicateModuleImport` | Import hygiene |
| Explicit runtime checks | `boundChecks`, `objChecks`, `rangeChecks`, `fieldChecks`, `assertions` all on |

### Intentionally omitted

| Flag | Reason |
|------|--------|
| `strictFuncs` | Nim's stdlib operations (JSON iteration, `seq.add`, `JsonNode` mutation) trigger side-effect violations; would require dozens of `{.cast(noSideEffect).}` blocks |
| `strictNotNil` | Generic/template instantiation from stdlib (`Option[T]`, `seq`, `Table`) fires inside user modules; unfixable in Nim 2.2 |
| `strictCaseObjects` | Adds compile-time field access validation but requires compile-time literal discriminators for construction, forcing verbose workarounds for runtime-dispatched case objects |
| `{.push raises: [].}` on L1–L4 | Would force all error handling through `Result[T, E]` types, making stdlib JSON operations (`node["key"]`, `parseJson`) unusable without manual wrapping; applied only on Layer 5 |

### Practical consequence

Standard Nim protects case objects at runtime: discriminator reassignment to a
different branch is a compile error, and accessing the wrong branch raises
`FieldDefect`. Combined with `strictDefs`, `panics:on`, and the extensive
`warningAsError` configuration, the compiler catches most classes of bugs
without the experimental flags.

## Layer Architecture

```
Layer 1: Domain Types + Errors (types, smart constructors, exceptions)
Layer 2: Serialisation (JSON parsing boundary — "parse, don't validate")
Layer 3: Protocol Logic (builders, dispatch, result references, method framework)
Layer 4: Transport + Session Discovery (imperative shell — HTTP IO)
Layer 5: C ABI Wrapper (FFI projection — exception → error code boundary)
```

**Governing principle: types, errors, and their construction algebra as a
single layer.** Layer 1 contains every domain data type — structs, enums,
variant objects — and the smart constructors that enforce their construction
invariants. The type and its construction algebra are a unit. Layer 1 can be
defined without importing anything above it. No serialisation logic, no
protocol logic, no IO. Layers 2–5 contain the downstream logic that operates
on Layer 1 types.

**`JsonNode` as a Layer 1 data type.** `PatchObject` (§1.5.3), `Invocation`
arguments, and error `extras` fields use `JsonNode` from `std/json`. This is
`JsonNode` as a *data structure* (a tree of values), not as a serialisation
concern. The L1/L2 boundary prohibits serialisation *logic* — `parseJson`,
`to[T]`, camelCase conversion, `#`-prefix handling — not the tree type
itself. Layer 1 modules use selective import (`from std/json import JsonNode,
JsonNodeKind`) to bring only the data types into unqualified scope.

**Exception boundary at Layer 5.** Layers 1–4 use idiomatic Nim exceptions.
Only Layer 5 (`src/jmap_client.nim`) has `{.push raises: [].}` — every
exported C ABI proc catches `CatchableError` via `try/except` and converts
to C error codes. The compiler enforces that no exception escapes.

Each layer depends only on layers below it. Each is fully testable without the
layers above.

Dependency graph:

```
L1 (types+errors) ← L2 (serialisation) ← L3 (protocol logic) ← L4 (transport) ← L5 (C ABI)
```

A strict linear chain. No branching, no cycles.

### Why 5 Layers

Three merges were made from the original 8-layer decomposition, each justified
by the nature of the code:

**Merge 1: Core Types + Error Types → Layer 1.** Error types are data
definitions — case objects, enums, type aliases. Both value and error types
are algebraic data types in the domain core.

**Merge 2: Envelope Logic + Methods + Result References → Layer 3.** The
request builder must know method shapes. Result reference construction is a
feature of the builder. These share the same dependencies and dependents.

**What would go wrong if adjacent layers were merged:**

| Boundary | What breaks if merged |
|----------|----------------------|
| L1 / L2 | Testing smart constructors would require JSON fixtures. Wire format knowledge would leak into type definitions. |
| L2 / L3 | Serialisation is stateless infrastructure. Protocol logic uses accumulation patterns that differ structurally. Mixing them prevents swapping JSON libraries without touching builder logic. |
| L3 / L4 | Protocol logic has no I/O; transport does. Merging them makes the protocol layer untestable without network access. This is the functional core / imperative shell boundary. |
| L4 / L5 | Transport returns rich Nim types; the C ABI projects them into opaque handles and error codes. Different audiences, different type systems. |

### Layer 1 Internal File Organisation

```
src/jmap_client/
  validation.nim      — ValidationError, borrow templates, charset constants
  primitives.nim      — Id, UnsignedInt, JmapInt, Date, UTCDate
  identifiers.nim     — AccountId, JmapState, MethodCallId, CreationId
  capabilities.nim    — CapabilityKind, CoreCapabilities, ServerCapability
  session.nim         — Account, AccountCapabilityEntry, UriTemplate, Session
  envelope.nim        — Invocation, Request, Response, ResultReference, Referencable[T]
  framework.nim       — PropertyName, FilterOperator, Filter[C], Comparator, PatchObject, AddedItem
  errors.nim          — TransportError, RequestError, ClientError, MethodError, SetError
  types.nim           — Re-exports all of the above
```

Internal import DAG:

| Module | Imports from (within Layer 1) |
|--------|------------------------------|
| `validation` | *(none)* |
| `primitives` | `validation` |
| `identifiers` | `validation` |
| `capabilities` | `primitives` |
| `framework` | `validation`, `primitives` |
| `errors` | `primitives` |
| `session` | `validation`, `identifiers`, `capabilities` |
| `envelope` | `identifiers`, `primitives` |
| `types` | all of the above (re-export hub) |

No cycles. Each file is independently testable.

### Layer 2 Internal File Organisation

```
src/jmap_client/
  serde.nim              — Shared helpers (checkJsonKind, parseError,
                           collectExtras), primitive/identifier ser/de
  serde_session.nim      — CoreCapabilities, ServerCapability,
                           AccountCapabilityEntry, Account, Session
  serde_envelope.nim     — Invocation, Request, Response,
                           ResultReference, Referencable[T] helpers
  serde_framework.nim    — FilterOperator, Filter[C], Comparator,
                           PatchObject, AddedItem
  serde_errors.nim       — RequestError, MethodError, SetError
  serialisation.nim      — Re-exports all of the above (Layer 2 hub)
```

No cycles. All domain serde modules depend on `serde` for shared helpers.

---

## Layer 1: Domain Types + Errors

### 1.1 Primitive Identifiers

The RFC defines `Id` (1-255 octets, base64url chars), plus various semantically
distinct identifiers.

#### Option 1.1A: Full distinct types for every identifier kind

`AccountId`, `JmapState`, `MethodCallId`, `CreationId` as separate
`distinct string` types. Every operation explicitly borrowed or defined.

- **Pros:** Maximum compile-time safety. Cannot pass a `BlobId` where an
  `AccountId` is expected. Follows "make illegal states unrepresentable."
- **Cons:** Boilerplate. Each distinct type needs ~3 lines of `{.borrow.}`.

#### Decision: 1.1A

The boilerplate cost is real but small (~3 lines per type via
`defineStringDistinctOps`). The distinct types needed for RFC 8620 Core are:
`Id` (entity identifiers per §1.2), `AccountId` (§2), `JmapState`,
`MethodCallId` (§3.2), and `CreationId` (§3.3). Smart constructors
enforce domain constraints at construction time and raise `ValidationError`
on invalid input.

### 1.2 Capability Modelling

#### Option 1.2A: Variant object with known-variant enum and open-world fallback

```nim
CapabilityKind = enum
  ckMail, ckCore, ckSubmission, ..., ckUnknown

ServerCapability = object
  rawUri: string  ## always populated — lossless round-trip
  case kind: CapabilityKind
  of ckCore: core: CoreCapabilities
  else: rawData: JsonNode
```

#### Decision: 1.2A

The case object with known-variant enum and open-world fallback forces every
consumer to handle each capability kind explicitly. Unknown capabilities are
preserved via the `else` branch. `ckMail` is placed before `ckCore` in the
enum so the default discriminator selects the `else` branch (whose
`rawData: JsonNode` is nil-safe), avoiding issues with `seq` operations
that default-construct elements.

**CRITICAL:** `CapabilityKind` must NOT be used as a `Table` key. Multiple
vendor extensions would all map to `ckUnknown`, causing key collisions. All
capability-keyed maps use raw URI strings as keys.

### 1.3 Result Reference Representation

#### Option 1.3B: Variant type (discriminated union)

```nim
ReferencableKind = enum rkDirect, rkReference

Referencable[T] = object
  case kind: ReferencableKind
  of rkDirect: value: T
  of rkReference: reference: ResultReference
```

#### Decision: 1.3B

Variant type (`Referencable[T]`). The illegal state "both direct value and
reference" is unrepresentable. Isomorphic to Haskell's `Either T
ResultReference`. The serialisation format (`#`-prefixed keys) is handled
in Layer 2.

### 1.4 Envelope Types

The RFC §3.2-3.4 defines three pure data structures:

- **Invocation** — a tuple of (method name, arguments object, method call ID).
  Serialised as a 3-element JSON array, not a JSON object.
- **Request** — a `using` capability list, a sequence of Invocations, and an
  optional `createdIds` map.
- **Response** — a sequence of Invocation responses, an optional `createdIds`
  map, and a `sessionState` token.

### 1.5 Generic Method Framework Types

#### 1.5.1 Filter and FilterOperator

```nim
FilterOperator = enum
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"

Filter[C] = object
  case kind: FilterKind
  of fkCondition: condition: C
  of fkOperator:
    operator: FilterOperator
    conditions: seq[Filter[C]]
```

A recursive algebraic data type parameterised by condition type `C`.
`seq[Filter[C]]` provides heap-allocated indirection for recursion without
`ref`.

#### 1.5.2 Comparator

```nim
PropertyName = distinct string  ## Non-empty; validated at construction time

Comparator = object
  property: PropertyName
  isAscending: bool          ## true = ascending (RFC default)
  collation: Option[string]  ## RFC 4790 collation algorithm identifier
```

Entity-specific property validation is deferred to Layer 3 typed sort builders.

#### 1.5.3 PatchObject

#### Decision: 1.5B — Opaque distinct type with smart constructors

```nim
PatchObject = distinct Table[string, JsonNode]
```

Only `len` is borrowed. All mutating `Table` operations are excluded. Smart
constructors (`setProp`, `deleteProp`) are the only write path.

#### 1.5.4 AddedItem

```nim
AddedItem = object
  id: Id
  index: UnsignedInt
```

### 1.6 Error Architecture

The library handles errors at four granularities, composing into a three-level
exception hierarchy plus one data-level pattern:

0. **Construction errors** — invalid values rejected by smart constructors
   (`ValidationError`, a `CatchableError` subtype). Raised at construction
   time.
1. **Transport/request errors** — network failures, TLS errors, timeouts,
   HTTP 4xx/5xx with RFC 7807 problem details. Both become `ClientError`
   (a `CatchableError` subtype wrapping `TransportError` or `RequestError`).
2. **Method-level errors** — invocation errors (`MethodError`). These are
   **data within a successful response**, not exceptions. The HTTP request
   succeeded; individual method calls within it carry their own outcomes.
3. **Set-item outcomes** — per-object results within a successful `/set`
   response (`SetError`). Also data, not exceptions.

#### Decision: 1.6C — Three-level exception hierarchy + data-level errors

```
Level 0 (construction): ValidationError (CatchableError)
  Raised by smart constructors on invalid input.

Level 1 (transport): ClientError (CatchableError)
  Wraps TransportError | RequestError.
  Raised when no valid JMAP response is received.

Level 2 (per-invocation): MethodError (plain object)
  Data within a successful Response. Not an exception.

Per-item: SetError (plain object)
  Data within a successful SetResponse. Not an exception.
```

This separation is essential because a single JMAP response can contain both
successes and failures across method calls. Conflating method errors with
transport failures in a single exception type would lose successful results
from a partially-failed multi-method request.

**Layer 5 boundary:** All `CatchableError` exceptions (ValidationError,
ClientError) are caught at the C ABI boundary and converted to error codes.
`Defect` subclasses (`IndexDefect`, `NilAccessDefect`, etc.) are not tracked
by `{.raises: [].}` — with `--panics:on` they abort the process. Exported
procs validate inputs defensively to avoid triggering Defects.

### 1.7 Error Type Granularity

#### Decision: 1.7C — Enum with string backing + lossless round-trip

Every RFC-specified error type as an enum variant, plus an `unknown` catch-all.
Raw string always preserved alongside the parsed enum:

```nim
MethodError = object
  errorType: MethodErrorType    ## parsed enum variant
  rawType: string               ## always populated, lossless round-trip
  description: Option[string]
  extras: Option[JsonNode]      ## non-standard fields, lossless preservation
```

The same pattern applies to `SetErrorType`, `RequestErrorType`. The lossless
principle extends to `extras: Option[JsonNode]` on error types, preserving
additional server-sent fields not modelled as typed fields.

### 1.8 Concrete Error Types

#### TransportError

```nim
TransportErrorKind = enum
  tekNetwork, tekTls, tekTimeout, tekHttpStatus

TransportError = object of CatchableError
  case kind: TransportErrorKind
  of tekHttpStatus:
    httpStatus: int
  of tekNetwork, tekTls, tekTimeout:
    discard
```

#### RequestError (RFC 7807 Problem Details)

```nim
RequestErrorType = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

RequestError = object of CatchableError
  errorType: RequestErrorType
  rawType: string
  status: Option[int]
  title: Option[string]
  detail: Option[string]
  limit: Option[string]
  extras: Option[JsonNode]
```

#### ClientError (outer exception type)

```nim
ClientErrorKind = enum
  cekTransport, cekRequest

ClientError = object of CatchableError
  case kind: ClientErrorKind
  of cekTransport: transport: TransportError
  of cekRequest: request: RequestError
```

#### SetError (per-item error data within /set responses)

```nim
SetError = object
  rawType: string
  description: Option[string]
  extras: Option[JsonNode]
  case errorType: SetErrorType
  of setInvalidProperties:
    properties: seq[string]
  of setAlreadyExists:
    existingId: Id
  else: discard
```

SetError is a case object because the RFC mandates variant-specific fields on
two error types: `invalidProperties` carries `properties: String[]` (§5.3),
`alreadyExists` carries `existingId: Id` (§5.4). When variant-specific data
is absent from the server response, the deserialiser falls back to the generic
constructor (mapping to `setUnknown`) rather than constructing a variant-specific
branch with empty/bogus values.

---

## Layer 2: Serialisation

### 2.1 JSON Library

#### Decision: 2.1A — `std/json` with manual serialisation/deserialisation

Manual `toJson`/`fromJson` procs for each type. Types with custom wire formats
(Invocation as 3-element array, `#`-prefixed reference keys, recursive
`Filter[C]`, `PatchObject` with null-as-delete semantics) require manual
serialisation regardless. The remaining types follow a consistent pattern:

1. Guard on JSON kind via `checkJsonKind` (raises `ValidationError`)
2. Extract fields with `node{"key"}` (safe nil-returning accessor) + kind checks
3. Delegate to Layer 1 smart constructors for domain validation
4. Construct the typed value

`node.to(T)` from `std/json` is not used because it bypasses smart constructor
validation (distinct types are unwrapped to base type with no validation),
silently defaults missing required fields, drops extra fields (breaking
lossless `extras` preservation), and provides generic error messages with no
domain context.

### 2.2 camelCase Handling

#### Decision: 2.2A — camelCase in Nim source

Since Nim treats `accountId` and `account_id` as the same identifier, write
`accountId` in type definitions. Zero conversion. Leverages Nim's style
insensitivity.

### 2.3 Result Reference Serialisation

`Referencable[T]` (Decision 1.3B) requires custom serialisation. The wire
format uses the JSON key name as the discriminator: `rkDirect` uses the normal
key, `rkReference` prefixes the key with `#`. Custom `toJson`/`fromJson`
procedures handle this dispatch.

---

## Layer 3: Protocol Logic

### 3.2 Method Call ID Generation

#### Decision: 3.2A — Auto-incrementing counter

`"c0"`, `"c1"`, `"c2"`. Simple, deterministic, unique within a request.

### 3.3 Request Builder Design

#### Decision: 3.3B — Builder with method-specific sub-builders

Builder accumulates method calls via `var` parameter. `.build()` is a pure
projection of the accumulated state — a deterministic function from builder
state to `Request`.

### 3.4 Response Processing

#### Decision: 3.4C — Phantom-typed response handles

```nim
ResponseHandle[T] = distinct MethodCallId  # T is phantom

let queryHandle: ResponseHandle[QueryResponse[Mailbox]] = builder.addQuery(...)
func get[T](resp: Response, handle: ResponseHandle[T]): T  # raises on error
```

Compile-time response type safety via the phantom parameter. JSON-to-type
deserialisation happens inside `get[T]`, which raises `ValidationError` on
parse failure or returns the method error if the invocation was an error
response.

**Cross-request safety gap.** Call IDs repeat across requests — a handle from
Request A used with Response B would silently match the wrong invocation.
Process response handles immediately within the scope where the request was
built.

### 3.5 Entity Type Framework

#### Decision: 3.5B — Plain overloaded procs + compile-time registration

Each entity type provides overloaded `typedesc` procs (`methodNamespace`,
`capabilityUri`, and optionally `filterType`). Two registration templates
verify at the entity definition site that all required overloads exist:

- `registerJmapEntity(T)` — checks `methodNamespace` and `capabilityUri`
- `registerQueryableEntity(T)` — checks `filterType`

Both use `when not compiles()` + `{.error:}` to produce domain-specific
error messages.

### 3.6 The Six Standard Methods

| Method          | Takes                                                        | Returns                                                                     |
|-----------------|--------------------------------------------------------------|-----------------------------------------------------------------------------|
| `/get`          | accountId, ids/idsRef, properties                            | state, list, notFound                                                       |
| `/set`          | accountId, ifInState, create/update/destroy                  | oldState, newState, created/updated/destroyed, notCreated/notUpdated/notDestroyed |
| `/query`        | accountId, filter, sort, position/anchor, limit              | queryState, canCalculateChanges, position, ids, total                       |
| `/changes`      | accountId, sinceState, maxChanges                            | oldState, newState, hasMoreChanges, created/updated/destroyed               |
| `/queryChanges` | accountId, filter, sort, sinceQueryState, maxChanges         | oldQueryState, newQueryState, removed, added                                |
| `/copy`         | fromAccountId, accountId, ifFromInState, ifInState, create   | oldState, newState, created, notCreated                                     |

### 3.7 Associated Type Resolution for Filters and Sorts

#### Decision: 3.7B — Overloaded type-level templates

```nim
template filterType(T: typedesc[Mailbox]): typedesc = MailboxFilter
```

Single type parameter on `QueryRequest[T]`, with `filterType(T)` resolved at
compile time. If template-based resolution proves fragile, fall back to
explicit two-parameter types with convenience aliases.

### 3.9 SetResponse Modelling

#### Decision: 3.9B internally, 3.9A on the wire

Deserialise from the RFC format (parallel maps). The user-facing type uses
per-item outcomes — each item has exactly one result. Deserialisation merges
the parallel maps into unified result maps.

### 3.10 Result Reference Construction

#### Decision: 3.10A with constants

Provide constants for all standard paths (`/ids`, `/list/*/id`,
`/added/*/id`, `/created`, `/updated`, `/updatedProperties`). Allow arbitrary
string paths for extensibility. The server validates; the client provides
convenience.

---

## Layer 4: Transport + Session Discovery

### 4.1 HTTP Client

#### Decision: 4.1A — `std/httpclient`

Built-in, synchronous. No dependencies. Sufficient for session discovery and
API requests. Swappable later without affecting other layers.

`std/httpclient`'s request functions have no `{.raises.}` annotations. The
transport `proc` catches `CatchableError` from stdlib and classifies the
exception into `TransportError` (timeout, TLS, network, HTTP status) or
wraps RFC 7807 problem details into `RequestError`.

### 4.2 Session Discovery

Direct URL and `.well-known/jmap`. DNS SRV skipped (no reference implementation
does it).

### 4.3 Transport Layer Boundary

The transport layer is the imperative shell. Every function is `proc` with
I/O side effects:

```nim
proc send(client: var JmapClient, request: Request): Response
  ## Raises ClientError on transport/request failure.
  ## Raises ValidationError on malformed response.
```

### 4.4 Authentication

Bearer tokens. The `JmapClient` stores a bearer token, attached as
`Authorization: Bearer <token>` on every HTTP request. Provided at construction
time, updatable via setter.

### 4.5 Push Mechanisms (Out of Scope)

Out of scope for initial implementation. No Layer 1–3 changes needed when added.

### 4.6 Binary Data (Out of Scope)

Out of scope for initial implementation. Session URL templates already modelled.

---

## Layer 5: C ABI Wrapper

### 5.1 Principle

The C ABI is a lossy projection of the Nim API. The Nim API has phantom types,
distinct identifiers, variant objects, exceptions. The C API has opaque
pointers, error codes, and thread-local error state. All domain correctness
lives in the Nim layer.

### 5.2 Handle Types

```c
typedef struct JmapClient_s* JmapClient;
typedef struct JmapSession_s* JmapSession;
typedef struct JmapRequest_s* JmapRequest;
typedef struct JmapResponse_s* JmapResponse;
```

### 5.3 Memory Ownership

#### Decision: 5.3A — Per-object free functions

Standard C pattern. Each object type has `_create` and `_destroy` functions.
Uses `create(T)` / `dealloc` for opaque handles (not `new(T)`) — zero-
initialised, untracked by ARC. Must call `=destroy(p[])` before `dealloc`
to run Nim destructors on managed fields.

### 5.4 ABI Stability

Pre-1.0: no ABI stability guarantees. Opaque handles insulate C consumers from
internal struct layout changes. Raw Nim enums are not exposed through the C
ABI — use `cint` constants or `cint`-returning accessor functions.

### 5.5 Error Projection

Layer 5 is the **only** module with `{.push raises: [].}`. Every exported proc
has four pragmas: `exportc: "jmap_name"`, `dynlib`, `cdecl`, `raises: []`.
The pattern:

```nim
proc jmapDoSomething*(...): cint
    {.exportc: "jmap_do_something", dynlib, cdecl, raises: [].} =
  clearLastError()
  try:
    let result = internalOperation(...)
    return JMAP_OK
  except TransportError as e:
    return setLastError(e)
  except RequestError as e:
    return setLastError(e)
  except CatchableError as e:
    lastErrorMsg = e.msg
    return JMAP_ERR_INTERNAL
```

Thread-local error state (`{.threadvar.}`) stores the last error message,
category, and HTTP status. Per-invocation method errors are data within the
response handle, not return codes.

---

## Summary of Decisions

| Layer | Decision | Rationale |
|-------|----------|-----------|
| Global | No external dependencies; `std/options` for optional values | Zero dependency management; `Option[T]` for optional fields |
| Global | Exception-based error handling; `{.push raises: [].}` only on Layer 5 | Idiomatic Nim; stdlib integration; Layer 5 catches all exceptions |
| Global | `proc` throughout; purity by convention in L1–L3 | Avoids `strictFuncs` workarounds; stdlib JSON operations are side-effectful |
| 1. Types+Errors | Full distinct types for all identifiers (1.1A) | Make illegal states unrepresentable |
| 1. Types+Errors | Case object capabilities with known-variant enum and open-world fallback (1.2A) | Known variants exhaustively matched; unknown preserved via `else` |
| 1. Types+Errors | `Referencable[T]` variant type (1.3B) | Illegal state (both direct + ref) unrepresentable |
| 1. Types+Errors | Opaque PatchObject distinct type (1.5B) | Distinct from arbitrary tables; only `len` borrowed; mutating ops excluded |
| 1. Types+Errors | `PropertyName = distinct string` for Comparator.property (§1.5.2) | Non-empty validation via smart constructor |
| 1. Types+Errors | Three-level exception hierarchy + data-level errors (1.6C) | Construction, transport, per-invocation separation; method/set errors are response data |
| 1. Types+Errors | Full enum + rawType for lossless round-trip (1.7C) | Parse, don't validate; preserve original |
| 1. Types+Errors | SetError as case object with variant-specific fields (1.8.1) | invalidProperties/alreadyExists carry typed data |
| 2. Serialisation | `std/json` manual ser/de, no external deps (2.1A) | Manual parsing required for custom wire formats; `to(T)` bypasses validation |
| 2. Serialisation | camelCase in Nim source (2.2A) | Zero conversion, leverages style insensitivity |
| 3. Protocol | Auto-incrementing call IDs (3.2A) | Simple, no safety implications |
| 3. Protocol | Builder produces immutable Request (3.3B) | `var` parameter accumulation; `.build()` pure projection |
| 3. Protocol | Phantom-typed ResponseHandle (3.4C) | Compile-time response type safety |
| 3. Protocol | Plain overloaded procs + registration templates (3.5B) | Catches missing overloads at definition site with domain-specific errors |
| 3. Protocol | Associated type resolution via templates (3.7B) | Single type parameter for query types |
| 3. Protocol | Entity-specific typed patch builders (3.8A) | Type-safe construction per entity |
| 3. Protocol | SetResponse as unified result maps (3.9B) | Per-item outcome pattern within successful method response |
| 3. Protocol | String paths with constants, no validation (3.10A) | Server validates; client provides convenience |
| 4. Transport | `std/httpclient`, synchronous (4.1A) | No deps, swappable later |
| 4. Transport | Single-threaded: handles not thread-safe (§4.3) | Matches `std/httpclient`; simplifies design |
| 4. Transport | Bearer token auth on JmapClient (§4.4) | RFC 8620 §1.1 requires auth; minimal surface for v1 |
| 4. Transport | Push/EventSource out of scope (§4.5) | Layer 4 concern when added |
| 4. Transport | Binary data out of scope (§4.6) | Session URL templates already modelled |
| 4. Transport | Direct URL + .well-known, no DNS SRV | Matches all reference implementations |
| 5. C ABI | Lossy projection, opaque handles, per-object free (5.3A) | Standard C pattern |
| 5. C ABI | No ABI stability pre-1.0; no raw enum exposure (§5.4) | Opaque handles insulate |
| 5. C ABI | Exception → error code boundary with thread-local state (§5.5) | Only module with `{.push raises: [].}` |

## Testability per Layer

- **Layer 1 (Types + Errors):** Unit test smart constructors (valid input
  returns typed value, invalid input raises `ValidationError`). Test distinct
  type operations, case object construction, error type construction.
- **Layer 2 (Serialisation):** Round-trip serialisation against RFC JSON
  examples. Verify Invocation serialises as 3-element array. Verify
  `Referencable[T]` serialises correctly for both branches. Verify lossless
  `extras` preservation.
- **Layer 3 (Protocol Logic):** Test request builder: call ID generation,
  phantom-typed handle creation, correct immutable Request values. Test
  entity registration templates. Verify associated-type resolution.
- **Layer 4 (Transport):** Integration test against a real or mock JMAP server.
- **Layer 5 (C ABI):** Integration test from C code linking the shared library.
  Verify exception-to-error-code conversion. Verify thread-local error state.
