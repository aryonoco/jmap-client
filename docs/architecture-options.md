# Architecture Options Analysis

Cross-platform JMAP (RFC 8620) client library in Nim with C ABI exports.

## Foundational Decisions

Three architectural decisions that constrain all subsequent choices:

1. **C ABI strategy: Approach A (rich Nim internals, thin C wrapper).** Build an
   idiomatic Nim library first. Add a separate C ABI layer that exposes opaque handles
   and accessor functions. The Nim API is the "real" API; the C ABI is a lossy
   projection of it.

2. **Decomposition: bottom-up by layer.** Each layer depends only on layers below it.
   Fully testable in isolation before the next layer is built.

3. **Definition of done: all 6 standard method patterns work with result references.**
   `/get`, `/set`, `/changes`, `/query`, `/queryChanges`, `/copy` — all functional,
   with result reference support for chaining method calls within a single request.

## Design Principles

The library follows functional programming principles throughout:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `map`, `flatMap`,
  `mapErr`, and the `?` operator for early return. Two-track error handling: success
  rail and error rail compose through bind.
- **Functional Core, Imperative Shell** — all domain logic in `func` (pure, no side
  effects). IO confined to a narrow `proc` boundary at the transport layer.
- **Immutability by default** — `let` bindings everywhere. `var` only when building
  mutable accumulators (builders) inside the imperative shell.
- **Total functions** — every function has a defined output for every input.
  `{.push raises: [].}` on every module. No exceptions. No partial functions.
- **Parse, don't validate** — deserialisation produces well-typed values or structured
  errors. Invariants enforced at parse time, not checked later.
- **Make illegal states unrepresentable** — variant types, distinct types, and smart
  constructors encode domain invariants in the type system.

## Nim's FP Ceiling

Before the layer-by-layer analysis, a clear picture of where Nim supports these
principles and where it forces compromises.

### What Nim gives us

- `func` — compiler-enforced purity (no side effects, no global mutation, no IO).
  The functional core is enforceable.
- `let` — immutable bindings.
- `{.push raises: [].}` — total functions at the module level. The compiler rejects
  any function that can raise. Combined with `Result[T, E]`, this is the Nim
  equivalent of checked effects.
- `distinct` types — newtypes. `type Id = distinct string` creates a new type that
  is not implicitly convertible. Stronger than a type alias; operations must be
  explicitly borrowed.
- `Result[T, E]` from the `results` library — has `map`, `flatMap`, `mapErr`,
  `mapConvert`, `valueOr`, and the `?` operator for early return (analogous to
  Rust's `?`). This is the railway.
- Case objects — the closest thing to algebraic data types. Discriminated unions with
  a tag enum.
- UFCS — `x.f(y)` and `f(x, y)` are the same. Enables pipeline-style
  `.map().flatMap().filter()` chaining.

### What Nim denies us

1. **Case objects as sum types (largely solved).** Case objects are discriminated
   unions. Under `--experimental:strictCaseObjects` (enabled in this project),
   the discriminator cannot be changed after construction — the compiler rejects
   any attempt to reassign it. This makes case objects behave like sealed
   discriminated unions in practice. Smart constructors remain useful for
   enforcing construction-time invariants, but are not needed to prevent
   discriminator mutation.

2. **Exhaustive pattern matching (with strictCaseObjects).** Under
   `--experimental:strictCaseObjects`, `case obj.kind` with missing branches
   is a compile error, not merely a warning. This gives case objects the same
   exhaustiveness guarantee as matching on bare `enum` values.

3. **No higher-kinded types.** Cannot abstract over `Result[_, E]` vs `Opt[_]` vs
   `seq[_]`. No `Functor`, no `Monad`, no `Applicative`. Each result-returning
   pipeline is concrete.

4. **No typeclass/trait coherence.** Nim's `concept` is structural, not nominal.
   No way to enforce that a type implements a set of operations at the definition
   site. Errors appear at instantiation time.

5. **No monadic do-notation.** Chaining with `flatMap` or `?` for early return.
   The `?` operator is pragmatically close to Rust's and is the primary ROP tool.

6. **Immutability is opt-in, not default.** Object fields are mutable unless the
   object is bound with `let`. No way to declare a field as read-only in the type
   definition. Immutability protected through module boundaries — do not export
   setters or mutable fields. Note: the most dangerous mutation — changing a case
   object discriminator after construction — is prevented by
   `--experimental:strictCaseObjects`.

### Practical consequence

Nim allows code that *behaves* like F#/Haskell — total functions, result types,
immutable bindings, pure core — and with the strict experimental flags enabled in
this project, the compiler enforces more than stock Nim. `{.push raises: [].}`,
`func`, `let`, `distinct`, `strictCaseObjects`, `strictDefs`, `strictNotNil`, and
`strictFuncs` are the enforcement tools. Module boundaries and smart constructors
cover the remaining gaps (principally: no per-field immutability declarations and
no higher-kinded abstractions).

## Layer Architecture

```
Layer 1: Core Types
Layer 2: Error Types
Layer 3: Serialisation
Layer 4: Request/Response Envelope
Layer 5: Standard Method Framework
Layer 6: Result References
Layer 7: Transport + Session Discovery
Layer 8: C ABI Wrapper
```

Each layer depends only on layers below it. Each is fully testable without the
layers above.

Dependency graph:

```
L1 (types) ← L2 (errors) ← L3 (serialisation) ← L4 (envelope) ← L5 (methods) ← L6 (references)
                                                                                        ↓
                                                                   L7 (transport) ← L8 (C ABI)
```

---

## Layer 1: Core Types

### 1.1 Primitive Identifiers

The RFC defines `Id` (1-255 octets, base64url chars), plus various semantically
distinct identifiers (account IDs, blob IDs, state strings, etc.).

#### Option 1A: Full distinct types for every identifier kind

`AccountId`, `BlobId`, `JmapState` as separate `distinct string` types. Every
operation (`==`, `$`, hash, serialisation) explicitly borrowed or defined per type.

- **Pros:**
  - Maximum compile-time safety. Cannot pass a `BlobId` where an `AccountId` is
    expected — a bug that would silently produce `"accountNotFound"` at runtime.
  - Follows the "make illegal states unrepresentable" principle.
  - `fromJson` for each distinct type is a validating parser — enforces format
    constraints (Id must be 1-255 bytes, base64url-safe) at parse time.
  - Matches how Haskell (`newtype AccountId = AccountId Text`) and F#
    (single-case discriminated unions) model this.
- **Cons:**
  - Boilerplate. Each distinct type needs ~3 lines of `{.borrow.}` pragmas.
  - Serialisation: each distinct type needs its own `toJson`/`fromJson`.
- **Mitigation:** The boilerplate is ~3 lines per type. `toJson`/`fromJson` for
  distinct strings is one line each. The serialisation boilerplate is actually a
  feature — it is the validation boundary.

#### Option 1B: Single `Id` distinct type, no further subdivision

One `type Id = distinct string` for all JMAP identifiers. `JmapState` as a
separate distinct type. Dates as distinct strings.

- **Pros:**
  - Less boilerplate while still distinguishing IDs from arbitrary strings.
  - What every reference implementation does — none distinguish `AccountId` from
    `BlobId` at the type level.
- **Cons:**
  - Can pass an account ID where a blob ID is expected.
  - Misses the "make illegal states unrepresentable" goal for a common class of bug.

#### Option 1C: Plain strings

`string` everywhere, doc comments indicating intent.

- **Pros:** Zero overhead, zero boilerplate.
- **Cons:** Defeats the purpose of strict type safety settings. No compiler help.
  Antithetical to the project's principles.

#### Decision: 1A

The boilerplate cost is real but small (~3 lines per type). The safety benefit is
real and catches plausible bugs. For RFC 8620 Core specifically, the distinct
types needed are: `AccountId`, `JmapState`, and a generic `Id` (for method call
IDs and creation IDs that are not entity-specific). When adding RFC 8621 later:
`MailboxId`, `EmailId`, `ThreadId`, etc.

### 1.2 Capability Modelling

The Session object's `capabilities` field is a map from URI string to a
capability-specific JSON object. The shape varies per capability URI.

#### Option 1D: Variant object (case object) with exhaustive enum

```
CapabilityKind = enum
  ckCore, ckMail, ckSubmission, ..., ckUnknown

Capability = object
  case kind: CapabilityKind
  of ckCore: core: CoreCapabilities
  of ckMail: mail: MailCapabilities
  ...
  of ckUnknown: rawJson: JsonNode
```

Consumers match on the `kind` enum (exhaustive in Nim).

- **Pros:**
  - Type-safe, pattern-matchable.
  - Closed-world assumption with an explicit open-world case (`ckUnknown`).
  - Known pattern in OCaml (polymorphic variants with catch-all) and Rust
    (`Other(String)` variant).
  - Adding a new capability means adding an enum variant — compiler flags every
    `case` statement that does not handle it.
- **Cons:**
  - Adding a new capability requires recompilation.
- **Note on mutability:** Under `--experimental:strictCaseObjects`, the
  discriminator is immutable after construction — the compiler rejects
  reassignment. Smart constructors
  (`func coreCapability(c: CoreCapabilities): Capability`) remain useful for
  enforcing construction-time validation, but are not needed to prevent
  discriminator mutation.

#### Option 1E: Known fields + raw JSON catch-all

Typed fields for `urn:ietf:params:jmap:core`. Everything else stored as raw
`JsonNode` in a `Table[string, JsonNode]`.

- **Pros:** Only parse what is needed. Unknown capabilities preserved.
- **Cons:** Mixed access patterns — typed for core, untyped for everything else.
  `Table[string, JsonNode]` is stringly-typed.

#### Option 1F: Typed core only, ignore rest for now

Parse `CoreCapabilities` fully. Store everything else as `JsonNode`. Add typed
parsing for other capabilities when implementing their RFCs.

- **Pros:** Pragmatic. Core is the only capability needed for RFC 8620.
- **Cons:** Same mixed access pattern as 1E. Consumers must know which access
  pattern to use for which capability.

#### Decision: 1D

The case object with exhaustive enum is the correct encoding. It forces every
consumer to handle each capability kind explicitly (enforced as a compile error
by `strictCaseObjects`). Unknown capabilities are preserved via the `ckUnknown`
variant, not silently dropped. Smart constructors enforce construction-time
validation; discriminator immutability is guaranteed by the compiler.

### 1.3 Entity Type Framework

The 6 standard methods are generic over entity type. Each entity type must
define: what properties it has, what filter conditions it supports, what sort
comparators it supports, and what method-specific arguments it has.

#### Option 1G: Concept + overloaded procs (most typeclass-like)

Define a concept that entity types must satisfy. Provide overloads as "instances":

```
type JmapEntity = concept T
  methodNamespace(type T) is string
  requiresAccountId(type T) is bool

proc methodNamespace(T: typedesc[Mailbox]): string = "Mailbox"
proc requiresAccountId(T: typedesc[Mailbox]): bool = true
```

- **Pros:**
  - Closest to a Haskell typeclass or Rust trait.
  - The concept defines the interface; overloads provide instances.
  - Generic procs constrained by `JmapEntity` fail at instantiation if overloads
    are missing.
- **Cons:**
  - Checked structurally at use site, not at definition site. Missing overloads
    produce errors at instantiation, not at declaration.
  - May interact unpredictably with `strictFuncs` and `raises: []`.
  - No associated types. Filter and sort types need separate encoding.
- **Gap vs. Haskell/Rust:** No orphan instance checking, no associated types,
  errors at instantiation not declaration.

#### Option 1H: Generic procs + overloaded type-specific procs (no concept)

No concept, just generic procs. Type-specific behaviour via overloading:

```
proc methodNamespace(T: typedesc[Mailbox]): string = "Mailbox"
proc methodNamespace(T: typedesc[Email]): string = "Email"
```

- **Pros:**
  - Simpler than concepts. Each entity type just provides overloads.
  - Works well with Nim's UFCS and overload resolution.
- **Cons:**
  - No compile-time enforcement that all required overloads exist.
  - Errors at instantiation time, not at definition time. Same as 1G in practice.

#### Option 1I: Template-generated concrete types

A macro/template stamps out concrete types per entity:

```
defineJmapEntity(Mailbox, "Mailbox", requiresAccountId = true)
# Generates: MailboxGetRequest, MailboxGetResponse, MailboxSetRequest, etc.
```

- **Pros:**
  - No generics complexity. Each entity gets concrete types.
  - Clear C ABI story (every type is concrete, no monomorphisation surprises).
- **Cons:**
  - Code generation means indirection — harder to read, debug, navigate.
  - Changes to the template affect all entity types simultaneously.

#### Decision: 1G — concepts for simple interfaces

Concepts are the primary choice for encoding the "entity types must satisfy an
interface" constraint. Simple, non-recursive, non-deeply-chained concepts work
well under the strict compiler settings. The caveat is complexity depth: deeply
nested concept hierarchies or concepts that chain through multiple layers of
generic constraints are fragile and should be avoided. For those cases, fall back
to 1H (plain overloaded procs). Document the required interface explicitly in
either case — this is the moral equivalent of the typeclass definition that Nim
cannot enforce as strongly as Haskell.

Keep 1I as a reserve option for Layer 5, where the number of concrete types per
entity may make templates worthwhile.

---

## Layer 2: Error Types

### 2.1 Error Architecture

The RFC defines errors at four levels:

1. **Transport errors** — network failures, TLS errors, timeouts (not in RFC,
   but reality).
2. **Request-level errors** — HTTP 4xx/5xx with RFC 7807 problem details
   (`urn:ietf:params:jmap:error:unknownCapability`, `notJSON`, `notRequest`,
   `limit`).
3. **Method-level errors** — invocation errors (`serverFail`, `unknownMethod`,
   `invalidArguments`, `forbidden`, `accountNotFound`, etc.).
4. **Set-item errors** — per-object errors within a `/set` response (`SetError`
   with type like `forbidden`, `overQuota`, `invalidProperties`, etc.).

#### Option 2A: Flat error enum

Single `JmapErrorKind` enum covering all error types across all levels.

- **Pros:** Simple. One error type everywhere.
- **Cons:**
  - Loses the level distinction. A transport timeout and a `stateMismatch` method
    error are fundamentally different — the first means the request may or may not
    have been processed; the second means it definitely was not.
  - Callers cannot distinguish error categories without inspecting the kind.
  - Mixing transport/protocol/method concerns in one enum violates the principle
    of precise types.

#### Option 2B: Layered error types with a top-level sum

Separate types for each level, unified under a top-level `JmapError` variant:

```
ClientError = TransportError | RequestError
MethodError = variant with errorType enum
SetError = variant with errorType enum
JmapError = ClientError | MethodError | SetError
```

- **Pros:**
  - Precise. Each level carries appropriate context.
  - Matches the RFC's own layering.
  - What the Rust implementation does.
- **Cons:**
  - Conflates method errors with transport failures in the same railway.
  - A JMAP request with 3 method calls can return 2 successes and 1 method error
    in the same HTTP 200 response. If method errors are on the error rail of the
    outer `Result`, the 2 successes are lost.

#### Option 2C: Two-level railway

```
Track 1 (outer): Did we get a valid JMAP response at all?
  Success: Response envelope with method responses
  Failure: ClientError (TransportError | RequestError)

Track 2 (inner, per-invocation): Did this method call succeed?
  Success: Typed method response
  Failure: MethodError
```

`JmapResult[T] = Result[T, ClientError]` for the outer railway.
`Result[MethodResponse, MethodError]` per invocation in the response.
SetErrors are data within successful SetResponse values (per-item results).

- **Pros:**
  - Matches JMAP's actual semantics. A single response legitimately contains both
    successes and failures.
  - Clean ROP composition. Outer railway for transport/request failures. Inner
    railway for per-method outcomes.
  - Method errors and set errors are *response data*, not *railway errors*. This
    is correct — the server successfully processed the request; some methods
    within it failed.
- **Cons:**
  - Consumers must check two places — the `Result` wrapper and the per-invocation
    results inside the response.
  - More complex mental model than a flat error type.

#### Decision: 2C

The two-level railway is the only option consistent with ROP and JMAP's
semantics. A flat error type forces handling transport errors and method errors
in the same `case` statement, but these require fundamentally different recovery
actions (retry vs. resync vs. report). And conflating method errors with transport
failures in a single `Result` loses successful results from a partially-failed
multi-method request.

### 2.2 Error Type Granularity

For each error level, how to represent the specific error type.

#### Option 2D: Full enum per level

Every RFC-specified error type as an enum variant, plus an `unknown` catch-all.

- **Pros:** Exhaustive matching. Compiler warns on unhandled variants.
- **Cons:** The list grows when adding RFC 8621. Servers may return
  implementation-specific errors.

#### Option 2E: String type + known constants

Error type as a string, with constants for known values.

- **Pros:** Extensible without recompilation. Matches wire format.
- **Cons:** No exhaustive matching. String comparison is fragile.

#### Option 2F: Enum with string backing + lossless round-trip

Enum for known types with a fallback variant. Raw string always preserved
alongside the parsed enum:

```
MethodErrorType = enum
  metServerUnavailable = "serverUnavailable"
  metServerFail = "serverFail"
  metServerPartialFail = "serverPartialFail"
  metUnknownMethod = "unknownMethod"
  metInvalidArguments = "invalidArguments"
  metInvalidResultReference = "invalidResultReference"
  metForbidden = "forbidden"
  metAccountNotFound = "accountNotFound"
  metAccountNotSupportedByMethod = "accountNotSupportedByMethod"
  metAccountReadOnly = "accountReadOnly"
  metAnchorNotFound = "anchorNotFound"
  metUnsupportedSort = "unsupportedSort"
  metUnsupportedFilter = "unsupportedFilter"
  metCannotCalculateChanges = "cannotCalculateChanges"
  metRequestTooLarge = "requestTooLarge"
  metStateMismatch = "stateMismatch"
  metUnknown

MethodError = object
  errorType: MethodErrorType
  rawType: string          # always populated, even for known types
  description: Opt[string]
```

`rawType` is always populated. Serialisation is lossless — can always round-trip
through `MethodError` without losing the original string.

- **Pros:**
  - Exhaustive matching for known types. Fallback for unknown.
  - Lossless round-trip. Preserves the original string.
  - Total parsing — the deserialiser always succeeds (unknown types map to
    `metUnknown` with the raw string preserved).
  - Exceeds every reference implementation: Python does not store rawType
    alongside the parsed enum; Rust has no lossless round-trip for unknown types.
- **Cons:** Slightly redundant storage (the enum and the string represent the
  same information for known types). Negligible cost.

#### Decision: 2F

Enum with string backing and lossless round-trip. The same pattern applies to
`SetErrorType` and `RequestErrorType`.

### 2.3 Concrete Error Types

#### TransportError

Not in the RFC. The library's own error type for failures below the JMAP
protocol level:

```
TransportErrorKind = enum
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus

TransportError = object
  kind: TransportErrorKind
  message: string
  httpStatus: Opt[int]      # only for tekHttpStatus
```

#### RequestError (RFC 7807 Problem Details)

```
RequestErrorType = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

RequestError = object
  errorType: RequestErrorType
  rawType: string
  status: Opt[int]
  title: Opt[string]
  detail: Opt[string]
  limit: Opt[string]
```

#### ClientError (outer railway error type)

```
ClientErrorKind = enum
  cekTransport, cekRequest

ClientError = object
  case kind: ClientErrorKind
  of cekTransport: transport: TransportError
  of cekRequest: request: RequestError
```

#### MethodError (inner railway error type)

```
MethodError = object
  errorType: MethodErrorType
  rawType: string
  description: Opt[string]
```

#### SetError (per-item error within /set responses)

```
SetErrorType = enum
  setForbidden = "forbidden"
  setOverQuota = "overQuota"
  setTooLarge = "tooLarge"
  setRateLimit = "rateLimit"
  setNotFound = "notFound"
  setInvalidPatch = "invalidPatch"
  setWillDestroy = "willDestroy"
  setInvalidProperties = "invalidProperties"
  setSingleton = "singleton"
  setUnknown

SetError = object
  errorType: SetErrorType
  rawType: string
  description: Opt[string]
  properties: Opt[seq[string]]  # only for setInvalidProperties
```

---

## Layer 3: Serialisation

### 3.1 JSON Library

#### Option 3A: `std/json` with manual serialisation/deserialisation

Use the built-in `JsonNode` tree. Write `toJson`/`fromJson` procs manually for
each type.

- **Pros:**
  - Zero dependencies.
  - Full control over camelCase naming, `#` reference handling, every
    serialisation quirk.
  - Easy to make `raises: []` compliant — catch `JsonParsingError` at the
    boundary.
  - Every `fromJson` is a validating parser that either produces a well-typed
    value or a structured error. This is the "parse, don't validate" principle.
  - No dependency risk. Third-party libraries may not work with `--mm:arc` +
    `strictFuncs` + `strictNotNil` + `raises: []`.
- **Cons:**
  - Verbose. Every type needs a `toJson` and `fromJson`.
  - ~15-20 pairs across all layers.
- **Mitigation:** Most follow one of three patterns: simple object (field-by-field
  with camelCase keys, template-able); case object (dispatch on discriminator);
  special format (invocations, result references, PatchObject). A helper template
  can handle the first pattern. Manual for the ~4-5 special types.

#### Option 3B: `jsony` or `nim-serialization`

Third-party library with hooks for customisation.

- **Pros:** Less boilerplate. Good hook support for custom field names.
- **Cons:**
  - New dependency. Must verify compatibility with the strict compiler
    configuration (`--mm:arc`, `strictFuncs`, `strictNotNil`, `raises: []`).
  - `jsony` uses exceptions internally, which conflicts with `raises: []`.
  - Implicit parsing means validation cannot be injected at the field level
    without hooks.
  - Less control over the total-parsing guarantee.

#### Option 3C: `std/json` + code generation macro

Macro generates `toJson`/`fromJson` from type definitions, handling camelCase
automatically. Manual overrides for special types.

- **Pros:** Less boilerplate than 3A, no external dependencies.
- **Cons:** Macros add compile-time complexity. Debugging macro-generated code is
  harder. Must work with strict settings.

#### Decision: 3A, potentially evolving to 3C

Start manual. The types with tricky serialisation (invocations as JSON arrays,
`#`-prefixed reference fields, PatchObject with JSON Pointer keys, filter
operators with recursive structure) require manual serialisation regardless. The
remaining types are straightforward. Starting manual means understanding every
detail of the wire format, which matters when debugging against a real server. If
boilerplate becomes painful, introduce a macro for the simple-object pattern.

### 3.2 camelCase Handling

#### Option 3D: camelCase in Nim source

Since Nim treats `accountId` and `account_id` as the same identifier, write
`accountId` in type definitions. The field name in Nim is the field name on the
wire. Zero conversion.

- **Pros:** Zero conversion logic. What is written is what goes on the wire.
  `nph` preserves the casing written. `--styleCheck:error` requires consistency
  (use the same casing everywhere), not a specific convention.
- **Cons:** Some Nim style guides prefer snake_case. Needs verification that
  `nph` + `--styleCheck:error` cooperate.

#### Option 3E: snake_case in Nim, convert at serialisation boundary

Write `account_id` in Nim. Convert to `accountId` during JSON serialisation.

- **Pros:** Nim-idiomatic naming.
- **Cons:** Conversion logic in every ser/de proc. Unnecessary complexity given
  Nim's style insensitivity.

#### Decision: 3D

camelCase in source. Zero conversion. Leverages Nim's style insensitivity.

### 3.3 Result Reference Serialisation

In JMAP, when a result reference is used, the field name gets a `#` prefix:

- Normal: `{ "ids": ["id1", "id2"] }`
- Reference: `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

The same logical field appears under two different JSON keys depending on usage.

#### Option 3F: Separate optional fields

```
GetRequest[T] = object
  ids: Opt[seq[Id]]
  idsRef: Opt[ResultReference]
```

Serialisation: if `idsRef.isSome`, emit `"#ids"`; else if `ids.isSome`, emit
`"ids"`.

- **Pros:** Simple types.
- **Cons:** Mutual exclusion not enforced by types. Both fields could be `Some`
  simultaneously — an illegal state that the type permits.

#### Option 3G: Variant type (discriminated union)

```
ReferencableKind = enum rkDirect, rkReference

Referencable[T] = object
  case kind: ReferencableKind
  of rkDirect: value: T
  of rkReference: reference: ResultReference
```

Usage:

```
GetRequest[T] = object
  accountId: AccountId
  ids: Opt[Referencable[seq[Id]]]
  properties: Opt[Referencable[seq[string]]]
```

- **Pros:**
  - Illegal state (both direct and reference) is unrepresentable.
  - Isomorphic to Haskell's `Either T ResultReference`.
  - The `Opt` wrapper handles the "not specified" case. Inner variant handles the
    "direct value vs. reference" case.
- **Cons:**
  - Custom serialisation needed: `Referencable[seq[Id]]` serialises as either
    `"ids": [...]` or `"#ids": { "resultOf": ..., ... }`.
  - Variant object boilerplate for each referenceable field.
- **Mitigation:** Custom serialisation is already the approach (Decision 3A).
  There are only ~4 referenceable fields across the standard methods.

#### Option 3H: Builder pattern hides representation

Builder provides `.ids(seq[Id])` or `.idsRef(ResultReference)` and internally
tracks which was set.

- **Pros:** Best user experience.
- **Cons:** Runtime enforcement only. The underlying type still needs to handle
  both cases. Correctness lives in the builder, not the types.

#### Decision: 3G

Variant type (`Referencable[T]`). Illegal states are unrepresentable in the type
system. The builder (Layer 4-5) provides ergonomic construction on top, but the
types are correct regardless of how values are constructed.

---

## Layer 4: Request/Response Envelope

### 4.1 Invocation Format

The wire format is a JSON array: `["methodName", {arguments}, "callId"]`. This is
modelled as an object with custom serialisation that emits/parses as a 3-element
array. Mechanical; all implementations do this identically.

### 4.2 Method Call ID Generation

#### Option 4A: Auto-incrementing counter

`"c0"`, `"c1"`, `"c2"`. What the Rust implementation does.

- **Pros:** Simple, deterministic, unique within a request.
- **Cons:** None. IDs are only meaningful within a single request/response pair.

#### Option 4B: Method-name-based descriptive IDs

`"mailbox-query-0"`, `"email-get-1"`.

- **Pros:** Easier debugging — visible which call produced which response.
- **Cons:** More complex generation. Needs uniqueness suffix for repeated methods.

#### Decision: 4A

Internal plumbing. No safety implications. Keep simple.

### 4.3 Request Builder Design

#### Option 4C: Direct construction

User builds `Request` objects by constructing `Invocation` objects manually.

- **Pros:** No builder infrastructure.
- **Cons:** Verbose. User must manually track call IDs, construct
  `ResultReference` objects, manage the `using` capability list. Error-prone.
  Antithetical to the goal of making misuse difficult.

#### Option 4D: Builder with method-specific sub-builders

Builder accumulates method calls. Each method call returns a sub-builder for that
method's arguments. Call IDs generated automatically. `using` populated
automatically based on which methods are called.

- **Pros:**
  - Excellent ergonomics.
  - Result references are easy to use — sub-builders return references.
  - Capability management is automatic.
  - Proven pattern from the Rust implementation.
- **Cons:**
  - Substantial infrastructure.
  - In Nim without a borrow checker, reference semantics of sub-builders must be
    managed carefully.

#### Option 4E: Builder with generic method calls

One generic `call` proc instead of method-specific sub-builders.

- **Pros:** Less infrastructure than 4D.
- **Cons:** Less discoverable. Requires knowing method type names.

#### Decision: 4D

The builder must produce an **immutable** request value. The builder is mutable
during construction (imperative shell). Once built, the `Request` is immutable
(functional core). The boundary is the `.build()` call:

```
# Imperative shell: building the request (var builder)
# Functional core: immutable Request value from .build()
```

This is the builder pattern as used in Rust — mutable accumulation, frozen
immutable value after `.build()`.

**Nim limitation:** Cannot enforce "consumed by build" at the type level. In
Rust, `build(self)` takes ownership. In Nim, the builder remains accessible.
Mitigate by clearing builder state in `build()`.

### 4.4 Response Processing

#### Option 4F: Fully typed response dispatch

Each invocation response deserialised into its concrete type based on method name.
Large enum of all response types.

- **Pros:** Type-safe access.
- **Cons:** Complex deserialisation dispatch. Massive response enum.

#### Option 4G: Typed wrapper over raw JSON

Deserialise envelope. Keep individual method responses as `JsonNode`. Typed
extraction on demand.

- **Pros:** Simple deserialisation.
- **Cons:** Runtime type errors if extracting wrong type at wrong index.

#### Option 4H: Phantom-typed response handles

The request builder returns typed handles. Each handle carries the expected
response type as a phantom parameter:

```
ResponseHandle[T] = distinct string  # wraps the call ID; T is phantom

# Builder returns:
let queryHandle: ResponseHandle[QueryResponse[Mailbox]] = builder.addQuery(...)

# Response extraction is type-safe:
func get[T](resp: JmapResponse, handle: ResponseHandle[T]): Result[T, MethodError]
```

- **Pros:**
  - Compile-time proof that the correct response type is extracted.
  - Cannot accidentally extract a `SetResponse` from a `GetResponse` position.
  - The inner `Result[T, MethodError]` is the per-invocation railway.
  - No massive type enum. JSON parsed into concrete type inside `get()`.
- **Cons:**
  - The connection between "added a query at position 0" and "position 0 is a
    query response" is upheld by the builder, not the type system.
  - If the builder has a bug, the phantom type gives false safety.
- **Gap vs. Haskell:** In Haskell, an indexed type (GADT) would make the
  relationship between request and response provable. In Nim, it is upheld by
  builder implementation.

#### Decision: 4H

Phantom-typed handles. Compile-time response type safety via the phantom
parameter. The per-invocation `Result[T, MethodError]` is the inner railway.
Strictly better than untyped extraction, even though Nim cannot prove the
relationship as strongly as Haskell.

---

## Layer 5: Standard Method Framework

### 5.1 The Six Standard Methods

| Method          | Takes                                                        | Returns                                                                     |
|-----------------|--------------------------------------------------------------|-----------------------------------------------------------------------------|
| `/get`          | accountId, ids/idsRef, properties                            | state, list, notFound                                                       |
| `/set`          | accountId, ifInState, create/update/destroy                  | oldState, newState, created/updated/destroyed, notCreated/notUpdated/notDestroyed |
| `/query`        | accountId, filter, sort, position/anchor, limit              | queryState, canCalculateChanges, position, ids, total                       |
| `/changes`      | accountId, sinceState, maxChanges                            | oldState, newState, hasMoreChanges, created/updated/destroyed               |
| `/queryChanges` | accountId, filter, sort, sinceQueryState, maxChanges         | oldQueryState, newQueryState, removed, added                                |
| `/copy`         | fromAccountId, accountId, ifFromInState, ifInState, create   | oldState, newState, created, notCreated                                     |

### 5.2 Filter and Sort Typing

Each entity type defines its own filter conditions and sort properties. The Rust
implementation uses associated types on traits. Nim lacks associated types.

#### Option 5A: Multiple type parameters

```
QueryRequest[T, F, S] = object  # T = entity, F = filter, S = sort
```

- **Pros:** Fully type-safe.
- **Cons:** Three type parameters is unwieldy. Every proc needs all three.

#### Option 5B: Overloaded type-level functions (simulated associated types)

```
proc filterType(T: typedesc[Mailbox]): typedesc = MailboxFilter
proc filterType(T: typedesc[Email]): typedesc = EmailFilter
```

Then `QueryRequest[T]` uses `filterType(T)` to resolve the filter type.

- **Pros:** Single type parameter. Type-specific behaviour via overloads.
  Closest to Haskell's type families or Rust's associated types.
- **Cons:** Relies on compile-time type function resolution, which may interact
  unpredictably with strict mode. Needs verification.

#### Option 5C: `JsonNode` for filters/sorts

Untyped filters. Typed filter constructors per entity return `JsonNode`.

- **Pros:** No generic filter complexity. Works immediately.
- **Cons:** Loses compile-time enforcement. A `MailboxFilter` could be used with
  `Email/query`. Runtime errors only from the server. Antithetical to the
  "make illegal states unrepresentable" principle.

#### Decision: 5B from the start, not 5C

Typed filters from the start. No `JsonNode` escape hatches in the user-facing API.

For RFC 8620 Core specifically: Core defines the generic filter *framework* but
no concrete filter types. Concrete filters come from RFC 8621 and other
extensions. So the Core implementation defines:

```
FilterOperator = enum
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"

FilterKind = enum fkCondition, fkOperator

Filter[C] = object  # C = condition type, defined per entity
  case kind: FilterKind
  of fkCondition: condition: C
  of fkOperator:
    operator: FilterOperator
    conditions: seq[Filter[C]]
```

This is a recursive algebraic data type parameterised by condition type.
Equivalent to Haskell's `data Filter c = Condition c | Operator Op [Filter c]`.
Defined in Core; entity-specific condition types plugged in later.

#### Fallback if 5B fails

If `filterType(T)` does not work in a type position under strict mode, use
explicit two-parameter types with convenience aliases:

```
QueryRequest[T, F] = object
  filter: Opt[Referencable[Filter[F]]]
  ...

type MailboxQueryRequest = QueryRequest[Mailbox, MailboxFilterCondition]
```

More verbose but achievable. The alias hides the second parameter.

### 5.3 PatchObject for /set Updates

The RFC's PatchObject uses JSON Pointer paths as keys. Inherently dynamic.

#### Option 5D: `Table[string, JsonNode]`

Simple key-value map.

- **Pros:** Direct, no abstraction needed.
- **Cons:** No validation. No distinction from arbitrary tables.

#### Option 5E: Opaque distinct type with smart constructors

```
PatchObject = distinct Table[string, JsonNode]

func setProp(patch: var PatchObject, path: string, value: JsonNode): PatchObject
func deleteProp(patch: var PatchObject, path: string): PatchObject
```

- **Pros:**
  - `distinct` prevents treating as a regular table.
  - Smart constructors can validate JSON Pointer paths.
  - Type communicates intent: "this is a JMAP patch, not a bag of key-values."
- **Cons:** Path is still a string. Cannot statically validate against entity
  properties.

#### Option 5F: Typed patch builder per entity

Entity-specific builder that produces `PatchObject` values.

- **Pros:** Type-safe, discoverable.
- **Cons:** Requires a builder per entity type.

#### Decision: 5E for Core, 5F when adding entity types

Core defines the PatchObject format but has no concrete entity types. Use the
opaque distinct type with smart constructors. When adding RFC 8621, add typed
patch builders per entity that produce `PatchObject` values.

### 5.4 SetResponse Modelling

A `/set` response contains parallel maps: `created`/`notCreated`,
`updated`/`notUpdated`, `destroyed`/`notDestroyed`. An ID appears in exactly
one map per operation.

#### Option 5G: Mirror RFC structure (parallel maps)

```
SetResponse[T] = object
  created: Table[Id, T]
  notCreated: Table[Id, SetError]
  ...
```

- **Pros:** Direct mapping to/from JSON. No transformation.
- **Cons:** Invariant "each ID in exactly one map" not enforced by types.

#### Option 5H: Unified result map (per-item railway)

```
SetResponse[T] = object
  createResults: Table[Id, Result[T, SetError]]
  updateResults: Table[Id, Result[Opt[T], SetError]]
  destroyResults: Table[Id, Result[void, SetError]]
  oldState: Opt[JmapState]
  newState: JmapState
```

- **Pros:**
  - Per-item railway is explicit. Each item has exactly one outcome.
  - Pattern matching on `Result` gives success or error.
  - Impossible to have an ID in both the success and failure maps.
- **Cons:** Requires transformation during deserialisation (merge parallel maps).
  Serialisation must split back out.

#### Decision: 5H internally, 5G on the wire

Deserialise from the RFC format (parallel maps). Immediately merge into `Result`
maps. The user-facing type is the unified result map. This gives users the clean
per-item railway model while respecting the wire format.

---

## Layer 6: Result References

For a client library, this layer is about **constructing** result references, not
resolving them (the server does that).

### Requirements

1. A `ResultReference` type: `{resultOf: string, name: string, path: string}`.
2. Builder-produced references: when adding a method call, the returned handle
   can produce `ResultReference` values pointing to specific paths in that call's
   response.
3. Serialisation: `Referencable[T]` (from Layer 3) emits `"#fieldName"` when the
   reference branch is active.
4. Path constants for common reference targets.

### Standard Reference Paths

From the RFC and reference implementations:

```
/ids                 — IDs from /query result
/list/*/id           — IDs from /get result
/added/*/id          — IDs from /queryChanges result
/created             — created IDs from /set result
/updated             — updated IDs from /changes result
/updatedProperties   — changed properties from /changes result
```

### Builder Integration

The phantom-typed handle from Layer 4 produces references:

```
let queryHandle = builder.addQuery(Mailbox, filter = ...)
# queryHandle : ResponseHandle[QueryResponse[Mailbox]]

let idsRef: ResultReference = queryHandle.reference("/ids")

builder.addGet(Mailbox, ids = referencable(idsRef))
# ids : Referencable[seq[Id]] = rkReference branch
```

### Path Validation

#### Option 6A: No validation

String path, library provides constants for common paths. Server returns
`invalidResultReference` if wrong.

- **Pros:** Simple.
- **Cons:** No compile-time feedback for incorrect paths.

#### Option 6B: Validated paths

Constants only. No arbitrary string paths:

```
func idsPath(): string = "/ids"
func listIdsPath(): string = "/list/*/id"
```

- **Pros:** Typo-proof. Discoverable.
- **Cons:** Cannot reference custom paths. Some server extensions may use
  non-standard paths.

#### Decision: 6A with constants

Provide constants for all standard paths. Allow arbitrary string paths for
extensibility. The server validates; the client provides convenience.

**Nim type system gap:** In a dependently-typed language (Idris, Agda), the path
could carry proof that it resolves to `seq[Id]`. In Nim (and Rust, Haskell
without advanced extensions), the relationship between path and result type is
a runtime assumption documented by convention.

---

## Layer 7: Transport + Session Discovery

### 7.1 HTTP Client

#### Option 7A: `std/httpclient`

Built-in, synchronous.

- **Pros:**
  - No dependencies. Synchronous is appropriate for a C ABI library.
  - Works with `--mm:arc`.
- **Cons:** Limited TLS configuration. No connection pooling. May not handle all
  redirect edge cases.

#### Option 7B: libcurl wrapper

- **Pros:** Battle-tested TLS, connection pooling, proxy support.
- **Cons:** C dependency. More complex build.

#### Decision: 7A

Swap HTTP backends later without affecting other layers. `std/httpclient` is
sufficient for session discovery and API requests. Upgrade to libcurl if TLS or
performance becomes an issue.

### 7.2 Session Discovery

The RFC specifies DNS SRV lookup, then `.well-known/jmap`, then follow redirects.
In practice, every client library takes a direct URL or does `.well-known` only.
None implement DNS SRV.

Implement: direct URL and `.well-known/jmap`. Skip DNS SRV.

### 7.3 Transport Layer Boundary

The transport layer is the imperative shell. Every function is `proc` (side
effects: IO). Everything below is `func` (pure). The boundary is explicit and
narrow:

```
proc send(client: JmapClient, request: Request): JmapResult[JmapResponse]
```

All errors become `ClientError` on the error track. Success produces an immutable
`JmapResponse` value.

---

## Layer 8: C ABI Wrapper

### 8.1 Principle

The C ABI is a lossy projection of the Nim API. The Nim API has phantom types,
result types, distinct identifiers, variant objects. The C API has opaque pointers
and error codes. The C layer is not the API designed for — it is a mechanical
translation. All FP correctness lives in the Nim layer.

The mental model: the Nim API is the "real" API. The C ABI is an FFI binding, as
Haskell's FFI exports C-callable wrappers around Haskell functions.

### 8.2 Handle Types

```c
typedef struct JmapClient_s* JmapClient;
typedef struct JmapSession_s* JmapSession;
typedef struct JmapRequest_s* JmapRequest;
typedef struct JmapResponse_s* JmapResponse;
```

Opaque pointers. C consumers never see Nim type internals.

### 8.3 Memory Ownership

#### Option 8A: Per-object free functions

Each object type has `_new` and `_free` functions. Accessor functions return
borrowed pointers.

- **Pros:** Standard C pattern. Familiar. Each object has clear lifetime.
- **Cons:** Easy to leak. Easy to use-after-free.

#### Option 8B: Arena/context allocator

One context object. All allocations scoped to it. Single `_free` call releases
everything.

- **Pros:** One free call. Simpler for C consumers.
- **Cons:** Coarser lifetime management. Objects cannot outlive their context.
  Less familiar pattern.

#### Decision: 8A

Per-object free functions. Standard C pattern. Arena support can be added later
as a convenience layer on top.

---

## Summary of Decisions

| Layer | Decision | Rationale |
|-------|----------|-----------|
| 1. Types | Full distinct types for all identifiers (1A) | Make illegal states unrepresentable |
| 1. Types | Case object capabilities with exhaustive enum (1D) | Closed world with explicit unknown case |
| 1. Types | Concepts for simple interfaces (1G, fallback 1H for deep chains) | Closest to typeclasses; avoid deeply nested concepts |
| 2. Errors | Two-level railway: ClientError outer, MethodError inner (2C) | ROP: separate transport failure from protocol results |
| 2. Errors | Full enum + rawType for lossless round-trip (2F) | Parse, don't validate; preserve original |
| 2. Errors | SetResponse as unified Result maps (5H) | Per-item railway, illegal dual-presence unrepresentable |
| 3. Serial. | `std/json` manual ser/de, no external deps (3A) | Total parsing, `raises: []` compatible, full control |
| 3. Serial. | camelCase in Nim source (3D) | Zero conversion, leverages style insensitivity |
| 3. Serial. | `Referencable[T]` variant type (3G) | Illegal state (both direct + ref) unrepresentable |
| 4. Envelope | Auto-incrementing call IDs (4A) | Simple, no safety implications |
| 4. Envelope | Builder produces immutable Request (4D) | Functional core / imperative shell boundary |
| 4. Envelope | Phantom-typed ResponseHandle (4H) | Compile-time response type safety |
| 5. Methods | Typed Filter[C] recursive ADT from the start (5B) | No JsonNode escape hatches in user-facing API |
| 5. Methods | Opaque PatchObject with smart constructors (5E) | Distinct from arbitrary tables, validates paths |
| 6. Refs | Referencable[T] + builder-produced references (3G + 4H) | Type-safe construction, server resolves |
| 6. Refs | String paths with constants, no validation (6A) | Server validates; client provides convenience |
| 7. Transport | `std/httpclient`, synchronous (7A) | No deps, swappable later |
| 7. Transport | Direct URL + .well-known, no DNS SRV | Matches all reference implementations |
| 8. C ABI | Lossy projection, opaque handles | C gets correctness; Nim gets type safety |
| 8. C ABI | Per-object free functions (8A) | Standard C pattern |

## Testability per Layer

Each layer is testable without the layers above it:

- **Layer 1:** Unit test type construction, distinct type operations, smart
  constructors.
- **Layer 2:** Unit test error construction, kind discrimination, round-trip
  preservation of rawType.
- **Layer 3:** Unit test round-trip serialisation against RFC JSON examples.
  Verify `Referencable[T]` serialises correctly for both branches.
- **Layer 4:** Unit test request/response envelope ser/de against RFC Section 3
  examples. Verify phantom-typed handle extraction.
- **Layer 5:** Unit test method request/response construction and ser/de.
  Verify `Filter[C]` recursive structure. Verify unified `Result` maps in
  SetResponse.
- **Layer 6:** Unit test that result reference fields serialise with `#` prefix.
  Verify builder produces correct `ResultReference` values.
- **Layer 7:** Integration test against a real or mock JMAP server.
- **Layer 8:** Integration test from C code linking the shared library.

The RFC includes JSON examples for almost every type. These serve as test
fixtures for Layers 3-6.
