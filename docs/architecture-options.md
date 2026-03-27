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

4. **External dependency: `nim-results`.** The railway (`Result[T, E]`, `Opt[T]`,
   `?` operator, `map`, `flatMap`, `mapErr`) comes from the `nim-results` package
   (status-im/nim-results), not the standard library. Nim's stdlib provides only
   `Option[T]` (from `std/options`), which lacks the `?` operator for early return
   and `mapErr` for error-rail transforms. `nim-results` is the sole external
   dependency for the core library. It is compatible with `--mm:arc` and
   `{.push raises: [].}`.

5. **Five-layer FP-first decomposition.** Each layer boundary corresponds to a
   genuine change in the nature of the code: pure algebraic data types (Layer 1),
   JSON parsing (Layer 2), pure protocol logic (Layer 3), IO (Layer 4), FFI
   (Layer 5). This maps directly to how the same library would be structured in
   Haskell or F# — the boundaries are language-independent consequences of the
   functional programming model. See "Why 5 Layers" below.

## Design Principles

The library follows functional programming principles throughout:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `map`, `flatMap`,
  `mapErr`, and the `?` operator for early return. Two-track error handling: success
  rail and error rail compose through bind.
- **Functional Core, Imperative Shell** — all domain logic in `func` (pure, no side
  effects). IO confined to a narrow `proc` boundary at the transport layer.
- **Immutability by default** — `let` bindings everywhere. `var` only when building
  mutable accumulators (builders) inside the imperative shell, or as a local
  variable inside `func` when building a return value from stdlib containers
  whose APIs require mutation (the local-`var`-inside-`func` pattern is
  referentially transparent — `strictFuncs` enforces the mutation does not
  escape).
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

- `func` — compiler-enforced purity: no access to global/thread-local state, no
  calling side-effecting procs, no IO. Combined with `--experimental:strictFuncs`
  (enabled in this project), mutation through `ref`/`ptr` indirection is also
  forbidden. Without `strictFuncs`, `func` permits mutation reachable through
  reference parameters — `strictFuncs` closes this gap.
- `let` — immutable bindings.
- `{.push raises: [].}` — total functions at the module level. The compiler rejects
  any function that can raise. Combined with `Result[T, E]`, this is the Nim
  equivalent of checked effects.
- `distinct` types — newtypes. `type Id = distinct string` creates a new type that
  is not implicitly convertible. Stronger than a type alias; operations must be
  explicitly borrowed.
- `Result[T, E]` and `Opt[T]` from the `nim-results` package
  (status-im/nim-results) — the sole external dependency. Provides `map`,
  `flatMap`, `mapErr`, `mapConvert`, `valueOr`, and the `?` operator for early
  return (analogous to Rust's `?`). `Opt[T]` replaces stdlib's `Option[T]`,
  integrating with the `?` operator and `{.push raises: [].}`. This is the
  railway.
- Case objects — the closest thing to algebraic data types. Discriminated unions with
  a tag enum.
- UFCS — `x.f(y)` and `f(x, y)` are the same. Enables pipeline-style
  `.map().flatMap().filter()` chaining.
- `collect` macro (`std/sugar`) — comprehension-style collection building.
  Preferred over `mapIt`/`filterIt` for building new collections. `allIt`/`anyIt`
  from `std/sequtils` remain the right choice for boolean predicates over
  sequences. No closures, compatible with `{.raises: [].}` and `func`.

### What strict flags upgrade (historical gaps, now largely closed)

These were traditional Nim limitations. With the strict experimental flags
enabled in this project, they are effectively resolved:

1. **Case objects as sum types.** Case objects are discriminated unions. In
   standard Nim, discriminator reassignment is already restricted: the compiler
   rejects assignments that would change the active branch. With `let` bindings
   (used throughout this project), the discriminator is fully immutable.
   `--experimental:strictCaseObjects` (enabled in this project) adds compile-time
   **field access validation**: the compiler rejects any `obj.field` access where
   it cannot prove the discriminator matches that field's branch — turning a
   potential runtime `FieldDefect` into a compile error. Smart constructors
   remain useful for enforcing construction-time invariants.

2. **Exhaustive pattern matching.** `case` statements on `enum` values are
   already exhaustive in standard Nim — missing branches are a compile error.
   `--experimental:strictCaseObjects` upgrades the compiler's case-object branch
   analysis from a warning to an error when field access cannot be proven safe.
   Together, these give case objects strong compile-time guarantees.

### What Nim still denies us

1. **No higher-kinded types.** Cannot abstract over `Result[_, E]` vs `Opt[_]` vs
   `seq[_]`. No `Functor`, no `Monad`, no `Applicative`. Each result-returning
   pipeline is concrete.

2. **No typeclass/trait coherence.** Nim's `concept` is structural, not nominal.
   No way to enforce that a type implements a set of operations at the definition
   site. Errors appear at instantiation time.

3. **No monadic do-notation.** Chaining with `flatMap` or `?` for early return.
   The `?` operator is pragmatically close to Rust's and is the primary ROP tool.

4. **Immutability is opt-in, not default.** Object fields are mutable unless the
   object is bound with `let`. No way to declare a field as read-only in the type
   definition. Immutability protected through module boundaries — do not export
   setters or mutable fields. The workaround is to keep fields private (no `*`
   export marker) and expose read-only accessor `func`s. However, this prevents
   direct `case obj.field` matching, which requires the discriminator field to be
   visible. In practice, `let` bindings and module boundaries are the enforcement
   mechanisms — convention-enforced, not compiler-enforced. Note: discriminator
   reassignment to a different branch is rejected by the compiler in standard
   Nim. `--experimental:strictCaseObjects` further prevents accessing fields from
   the wrong branch at compile time.

### Practical consequence

Nim allows code that *behaves* like F#/Haskell — total functions, result types,
immutable bindings, pure core — and with the strict experimental flags enabled in
this project, the compiler enforces more than stock Nim. The enforcement stack:

- `{.push raises: [].}` — total functions (no `CatchableError` escapes)
- `func` + `strictFuncs` — purity (no global state, no IO, no heap mutation
  through references)
- `let` — immutable bindings
- `distinct` + `{.requiresInit.}` — newtypes that cannot be default-constructed
- `strictCaseObjects` — compile-time field access validation for case objects
- `strictDefs` — all variables must be explicitly initialised
- `strictNotNil` — nilability tracking via flow analysis

Module boundaries and smart constructors cover the remaining gaps (principally:
no per-field immutability declarations and no higher-kinded abstractions).
`nim-results` provides the railway (`Result[T, E]`, `Opt[T]`, `?` operator).

## Layer Architecture

```
Layer 1: Domain Types + Errors (pure types and construction algebra)
Layer 2: Serialisation (JSON parsing boundary — "parse, don't validate")
Layer 3: Protocol Logic (builders, dispatch, result references, method framework)
Layer 4: Transport + Session Discovery (imperative shell — HTTP IO)
Layer 5: C ABI Wrapper (FFI projection)
```

**Governing principle: types, errors, and their construction algebra as a
single pure layer.** Layer 1 contains every pure data type — structs, enums,
variant objects, railway aliases — and the pure functions that enforce their
construction invariants (smart constructors, validation). In Haskell,
`Data.Map` exports both the type and `singleton`/`fromList`; in F#, a type
module includes its creation functions. The type and its construction
algebra are a unit. Layer 1 can be defined without importing anything above
it. No serialisation logic, no protocol logic, no IO. Layers 2–5 contain
the downstream logic (serialisation, builders, dispatch, transport) that
operates on Layer 1 types.

**`JsonNode` as a Layer 1 data type.** `PatchObject` (§1.5.3), `Invocation`
arguments, and error `extras` fields use `JsonNode` from `std/json`. This is
`JsonNode` as a *data structure* (a tree of values), not as a serialisation
concern. The L1/L2 boundary prohibits serialisation *logic* — `parseJson`,
`to[T]`, camelCase conversion, `#`-prefix handling — not the tree type
itself. Analogous to Haskell's `Data.Aeson.Value`, which is a pure ADT that
happens to represent JSON structure. Importing `std/json` for the `JsonNode`
type does not create a dependency on JSON parsing behaviour.

Each layer depends only on layers below it. Each is fully testable without the
layers above.

Dependency graph:

```
L1 (types+errors) ← L2 (serialisation) ← L3 (protocol logic) ← L4 (transport) ← L5 (C ABI)
```

A strict linear chain. No branching, no cycles.

### Why 5 Layers

The current architecture consolidates the original 8-layer design into 5 layers.
Three merges were made, each justified by FP principles:

**Merge 1: Old Layer 1 (Core Types) + Old Layer 2 (Error Types) → Layer 1.**
Error types are pure data definitions — case objects, enums, type aliases. No
FP principle separates "value ADTs" from "error ADTs"; both are algebraic data
types in the functional core. In Haskell, `data MethodError = ...` lives in
the same module as `data GetResponse = ...`. In F#, error discriminated unions
live alongside domain types. More critically, `JmapResult[T] = Result[T,
ClientError]` — the outer railway alias — needs both `T` and `ClientError`
visible. Splitting them across layers forces every downstream module to import
both, creating an artificial bridge that every consumer must cross.

**Merge 2: Old Layer 4 (Envelope Logic) + Old Layer 5 (Methods) + Old Layer 6
(Result References) → Layer 3.** The request builder must know method shapes
to provide typed `addGet`, `addSet`, `addQuery` methods. Result reference
construction (`handle.reference("/ids")`) is a feature of the builder, not a
separate concern. These three old layers share the same dependencies
(Layer 1 types, Layer 2 serialisation), the same dependents (Layer 4
transport), and cannot be independently tested in a meaningful way.

**What would go wrong if adjacent layers were merged:**

| Boundary | What breaks if merged |
|----------|----------------------|
| L1 / L2 | Type definitions would depend on `std/json` parsing functions. Testing smart constructors would require JSON fixtures. Wire format knowledge (camelCase, `#` prefix, array invocations) would leak into type definitions. |
| L2 / L3 | Serialisation is stateless, reusable infrastructure. Protocol logic has mutable builders and stateful ID generation. Mixing them conflates different levels of abstraction and prevents swapping JSON libraries without touching builder logic. |
| L3 / L4 | Protocol logic is pure (`func`); transport is impure (`proc` with IO). Merging them makes the entire protocol layer untestable without network access or mocks. This is the functional core / imperative shell boundary — the most important boundary in the project. |
| L4 / L5 | Transport returns rich Nim types (`JmapResult[Response]`); the C ABI projects them into opaque handles and error codes. Different audiences, different constraints, different type systems. |

**Haskell module analogy:**

| Layer | Haskell equivalent | F# equivalent |
|-------|--------------------|---------------|
| 1. Domain Types + Errors | `JMAP.Types` (all ADTs, newtypes, smart constructors, error types) | `Domain.Types` |
| 2. Serialisation | `JMAP.JSON` (`FromJSON`/`ToJSON` instances) | `Domain.Serialisation` |
| 3. Protocol Logic | `JMAP.Protocol` (request builder, response dispatch, method framework) | `Protocol.fs` |
| 4. Transport | `JMAP.Client` (`IO` monad: HTTP transport, session discovery) | `Client.fs` |
| 5. C ABI | `JMAP.FFI` (`Foreign.C` exports) | N/A (not typical in F#) |

### Layer 1 Internal File Organisation

Layer 1 is the largest layer. It decomposes into files with no circular
dependencies:

```
src/jmap_client/
  validation.nim      — ValidationError, borrow templates, charset constants
  primitives.nim      — Id, UnsignedInt, JmapInt, Date, UTCDate
  identifiers.nim     — AccountId, JmapState, MethodCallId, CreationId
  capabilities.nim    — CapabilityKind, CoreCapabilities, ServerCapability
  session.nim         — Account, AccountCapabilityEntry, UriTemplate, Session
  envelope.nim        — Invocation, Request, Response, ResultReference, Referencable[T]
  framework.nim       — FilterOperator, Filter[C], Comparator, PatchObject, AddedItem
  errors.nim          — TransportError, RequestError, ClientError, MethodError, SetError
  types.nim           — Re-exports all of the above; defines JmapResult[T] alias
```

Internal import DAG (each module imports only what its types reference):

| Module | Imports from (within Layer 1) |
|--------|------------------------------|
| `validation` | *(none)* |
| `primitives` | `validation` |
| `identifiers` | `primitives` |
| `capabilities` | `primitives` |
| `framework` | `primitives` |
| `errors` | `primitives` |
| `session` | `identifiers`, `capabilities` |
| `envelope` | `identifiers`, `primitives` |
| `types` | all of the above (re-export hub) |

No cycles. The graph is a DAG, not a linear chain — `identifiers`,
`capabilities`, `framework`, and `errors` are parallel dependents of
`primitives`; `session` merges the `identifiers` and `capabilities`
branches. Each file is independently testable.

---

## Layer 1: Domain Types + Errors

### 1.1 Primitive Identifiers

The RFC defines `Id` (1-255 octets, base64url chars), plus various semantically
distinct identifiers (account IDs, blob IDs, state strings, etc.).

#### Option 1.1A: Full distinct types for every identifier kind

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

#### Option 1.1B: Single `Id` distinct type, no further subdivision

One `type Id = distinct string` for all JMAP identifiers. `JmapState` as a
separate distinct type. Dates as distinct strings.

- **Pros:**
  - Less boilerplate while still distinguishing IDs from arbitrary strings.
  - What every reference implementation does — none distinguish `AccountId` from
    `BlobId` at the type level.
- **Cons:**
  - Can pass an account ID where a blob ID is expected.
  - Misses the "make illegal states unrepresentable" goal for a common class of bug.

#### Option 1.1C: Plain strings

`string` everywhere, doc comments indicating intent.

- **Pros:** Zero overhead, zero boilerplate.
- **Cons:** Defeats the purpose of strict type safety settings. No compiler help.
  Antithetical to the project's principles.

#### Decision: 1.1A

The boilerplate cost is real but small (~3 lines per type). The safety benefit is
real and catches plausible bugs. For RFC 8620 Core specifically, the distinct
types needed are: `Id` (entity identifiers per §1.2, with base64url/1-255
constraints), `AccountId` (§2, `Id[Account]` — server-assigned, uses lenient
§1.2 validation: 1-255 octets, no control characters), `JmapState`,
`MethodCallId` (§3.2, arbitrary client string — not constrained by §1.2),
and `CreationId` (§3.3, client-generated, no `#` prefix — also not
constrained by §1.2). `MethodCallId` and `CreationId` are separate from `Id`
because the RFC imposes different constraints: §1.2's base64url charset and
1-255 octet length rules apply to entity identifiers, not to protocol-level
identifiers. When adding RFC 8621 later: `MailboxId`,
`EmailId`, `ThreadId`, etc.

All distinct identifier types use the `{.requiresInit.}` pragma to prevent
default construction. Without it, `var x: AccountId` silently creates an empty
(invalid) identifier. With it, the compiler requires explicit initialisation via
a smart constructor or direct construction, turning a class of runtime bugs
into compile errors. This pragma is stable (not experimental) and uses control
flow analysis to verify initialisation across branches.

### 1.2 Capability Modelling

The Session object's `capabilities` field is a map from URI string to a
capability-specific JSON object. The shape varies per capability URI.

#### Option 1.2A: Variant object (case object) with exhaustive enum

```
CapabilityKind = enum
  ckCore, ckMail, ckSubmission, ..., ckUnknown

# Initial (RFC 8620 only — ckCore is the only typed branch):
ServerCapability = object
  rawUri: string  ## always populated — lossless round-trip
  case kind: CapabilityKind
  of ckCore: core: CoreCapabilities
  else: rawData: JsonNode

# When adding RFC 8621, ckMail graduates from `else` to an explicit branch:
#   of ckCore: core: CoreCapabilities
#   of ckMail: mail: MailCapabilities
#   else: rawData: JsonNode
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


#### Option 1.2B: Known fields + raw JSON catch-all

Typed fields for `urn:ietf:params:jmap:core`. Everything else stored as raw
`JsonNode` in a `Table[string, JsonNode]`.

- **Pros:** Only parse what is needed. Unknown capabilities preserved.
- **Cons:** Mixed access patterns — typed for core, untyped for everything else.
  `Table[string, JsonNode]` is stringly-typed.

#### Option 1.2C: Typed core only, ignore rest for now

Parse `CoreCapabilities` fully. Store everything else as `JsonNode`. Add typed
parsing for other capabilities when implementing their RFCs.

- **Pros:** Pragmatic. Core is the only capability needed for RFC 8620.
- **Cons:** Same mixed access pattern as 1.2B. Consumers must know which access
  pattern to use for which capability.

#### Decision: 1.2A

The case object with exhaustive enum is the correct encoding. It forces every
consumer to handle each capability kind explicitly. Unknown capabilities are preserved via the `ckUnknown`
variant, not silently dropped. Smart constructors enforce construction-time
validation; discriminator branch changes are rejected by the compiler, and
`strictCaseObjects` ensures field access is branch-safe at compile time.

**Progressive branching.** For RFC 8620, only `ckCore` has a typed
representation. All other capability kinds use an `else` branch with
`rawData: JsonNode`, preserving the original JSON losslessly. As typed
representations are added (e.g., `MailCapabilities` for RFC 8621), they
graduate from `else` to explicit branches. The `else` branch always
remains as the open-world catch-all.

### 1.3 Result Reference Representation

In JMAP, a method argument can be either a direct value or a reference to a
previous method's result. The type must encode this mutual exclusion. On the
wire, the field name gets a `#` prefix when a reference is used:

- Normal: `{ "ids": ["id1", "id2"] }`
- Reference: `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

The same logical field appears under two different JSON keys depending on usage.

#### Option 1.3A: Separate optional fields

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

#### Option 1.3B: Variant type (discriminated union)

```nim
ReferencableKind = enum rkDirect, rkReference

Referencable[T] = object
  case kind: ReferencableKind
  of rkDirect: value: T
  of rkReference: reference: ResultReference
```

Usage:

```nim
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
- **Mitigation:** Custom serialisation is already the approach (Decision 2.1A).
  There are only ~4 referenceable fields across the standard methods.

#### Option 1.3C: Builder pattern hides representation

Builder provides `.ids(seq[Id])` or `.idsRef(ResultReference)` and internally
tracks which was set.

- **Pros:** Best user experience.
- **Cons:** Runtime enforcement only. The underlying type still needs to handle
  both cases. Correctness lives in the builder, not the types.

#### Decision: 1.3B

Variant type (`Referencable[T]`). Illegal states are unrepresentable in the type
system. The builder (Layer 3) provides ergonomic construction on top. The
serialisation format (`#`-prefixed keys) is handled in Layer 2. The types are
correct regardless of how values are constructed.

### 1.4 Envelope Types

The RFC §3.2-3.4 defines three pure data structures for the request/response
protocol:

- **Invocation** — a tuple of (method name, arguments object, method call ID).
  On the wire, serialised as a 3-element JSON array, not a JSON object.
- **Request** — a `using` capability list, a sequence of Invocations, and an
  optional `createdIds` map.
- **Response** — a sequence of Invocation responses, an optional `createdIds`
  map, and a `sessionState` token.

These depend only on Layer 1 primitives (MethodCallId, CreationId, Id,
JmapState, JsonNode). Request construction logic (builders, call ID generation)
is a Layer 3 concern. Serialisation format is a Layer 2 concern.

### 1.5 Generic Method Framework Types

The RFC §5 defines several data types that are generic across all entity
types. These are pure data structures with no upward dependencies.

#### 1.5.1 Filter and FilterOperator

The RFC §5.5 defines a recursive filter structure. The Core RFC defines the
framework; entity-specific condition types plug in later.

```nim
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

A recursive algebraic data type parameterised by condition type `C`.
Equivalent to Haskell's `data Filter c = Condition c | Operator Op [Filter c]`.
`seq[Filter[C]]` provides heap-allocated indirection for the recursion without
`ref`. How to resolve `C` from the entity type is a Layer 3 concern
(Decision 3.7B).

#### 1.5.2 Comparator

The RFC §5.5 defines the sort order for `/query` requests.

```nim
Comparator = object
  property: string         ## property name to sort by
  isAscending: bool        ## true = ascending (RFC default)
  collation: Opt[string]   ## RFC 4790 collation algorithm identifier
```

`property` names are entity-specific. `isAscending` defaults to `true` per
RFC §5.5 (default applied at parse time in Layer 2).

#### 1.5.3 PatchObject

The RFC's PatchObject (§5.3) uses JSON Pointer paths as keys. Inherently
dynamic.

##### Option 1.5A: `Table[string, JsonNode]`

Simple key-value map.

- **Pros:** Direct, no abstraction needed.
- **Cons:** No validation. No distinction from arbitrary tables.

##### Option 1.5B: Opaque distinct type with smart constructors

```
PatchObject = distinct Table[string, JsonNode]

func setProp(patch: PatchObject, path: string, value: JsonNode): Result[PatchObject, ValidationError]
func deleteProp(patch: PatchObject, path: string): Result[PatchObject, ValidationError]
```

- **Pros:**
  - `distinct` prevents treating as a regular table.
  - Smart constructors validate JSON Pointer paths (non-empty) at construction
    time, returning `Result` per the ROP principle.
  - Type communicates intent: "this is a JMAP patch, not a bag of key-values."
- **Cons:** Path is still a string. Cannot statically validate against entity
  properties.

##### Decision: 1.5B

Core defines the PatchObject format but has no concrete entity types. Use the
opaque distinct type with smart constructors. Entity-specific typed patch
builders (Option 3.8A) are a Layer 3 concern.

#### 1.5.4 AddedItem

An element of the `added` array in a `/queryChanges` response (RFC §5.6).
Records that an item was added to the query results at a specific position.

```nim
AddedItem = object
  id: Id
  index: UnsignedInt
```

Both fields enforce their own invariants via their respective smart
constructors.

### 1.6 Error Architecture

The library handles errors at five levels. The first is a library concern;
the remaining four are defined by the RFC:

0. **Construction errors** — invalid values rejected by smart constructors
   (`ValidationError`). These fire at value-construction time, before any
   request is built. The construction-time railway:
   `Result[T, ValidationError]`.
1. **Transport errors** — network failures, TLS errors, timeouts (not in RFC,
   but reality).
2. **Request-level errors** — HTTP 4xx/5xx with RFC 7807 problem details
   (`urn:ietf:params:jmap:error:unknownCapability`, `notJSON`, `notRequest`,
   `limit`).
3. **Method-level errors** — invocation errors (`serverFail`, `unknownMethod`,
   `invalidArguments`, `forbidden`, `accountNotFound`, etc.).
4. **Set-item errors** — per-object errors within a `/set` response (`SetError`
   with type like `forbidden`, `overQuota`, `invalidProperties`, etc.).

#### Option 1.6A: Flat error enum

Single `JmapErrorKind` enum covering all error types across all levels.

- **Pros:** Simple. One error type everywhere.
- **Cons:**
  - Loses the level distinction. A transport timeout and a `stateMismatch` method
    error are fundamentally different — the first means the request may or may not
    have been processed; the second means it definitely was not.
  - Callers cannot distinguish error categories without inspecting the kind.
  - Mixing transport/protocol/method concerns in one enum violates the principle
    of precise types.

#### Option 1.6B: Layered error types with a top-level sum

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

#### Option 1.6C: Three-track railway

```
Track 0 (construction): Can this value be constructed at all?
  Success: Well-typed value (Id, AccountId, PatchObject, etc.)
  Failure: ValidationError

Track 1 (outer): Did we get a valid JMAP response at all?
  Success: Response envelope with method responses
  Failure: ClientError (TransportError | RequestError)

Track 2 (inner, per-invocation): Did this method call succeed?
  Success: Typed method response
  Failure: MethodError
```

`Result[T, ValidationError]` for the construction railway (Layer 1 smart
constructors). `JmapResult[T] = Result[T, ClientError]` for the outer
railway. `Result[MethodResponse, MethodError]` per invocation in the
response. SetErrors are data within successful SetResponse values (per-item
results).

- **Pros:**
  - Matches JMAP's actual semantics. A single response legitimately contains both
    successes and failures.
  - Clean ROP composition. Outer railway for transport/request failures. Inner
    railway for per-method outcomes.
  - Method errors and set errors are *response data*, not *railway errors*. The server successfully processed the request; some methods
    within it failed.
- **Cons:**
  - Consumers must check two places — the `Result` wrapper and the per-invocation
    results inside the response.
  - More complex mental model than a flat error type.

#### Decision: 1.6C

The three-track railway is the only option consistent with ROP and JMAP's
semantics. Each track corresponds to a distinct temporal phase with different
failure modes: construction (can this value exist?), transport (did the
HTTP round-trip succeed?), and per-invocation (did this method call
succeed?). A flat error type forces handling transport errors and method
errors in the same `case` statement, but these require fundamentally
different recovery actions (retry vs. resync vs. report). And conflating
method errors with transport failures in a single `Result` loses successful
results from a partially-failed multi-method request.

### 1.7 Error Type Granularity

For each error level, how to represent the specific error type.

#### Option 1.7A: Full enum per level

Every RFC-specified error type as an enum variant, plus an `unknown` catch-all.

- **Pros:** Exhaustive matching. Compiler warns on unhandled variants.
- **Cons:** The list grows when adding RFC 8621. Servers may return
  implementation-specific errors.

#### Option 1.7B: String type + known constants

Error type as a string, with constants for known values.

- **Pros:** Extensible without recompilation. Matches wire format.
- **Cons:** No exhaustive matching. String comparison is fragile.

#### Option 1.7C: Enum with string backing + lossless round-trip

Enum for known types with a fallback variant. Raw string always preserved
alongside the parsed enum:

```nim
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

#### Decision: 1.7C

Enum with string backing and lossless round-trip. The same pattern applies to
`SetErrorType` and `RequestErrorType`. The lossless principle extends beyond
`rawType`: an `extras: Opt[JsonNode]` field on `MethodError` and `SetError`
preserves any additional server-sent fields not modeled as typed fields. This
ensures no information is silently dropped during parsing.

### 1.8 Concrete Error Types

#### TransportError

Not in the RFC. The library's own error type for failures below the JMAP
protocol level:

```nim
TransportErrorKind = enum
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus

TransportError = object
  message: string
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

RequestError = object
  errorType: RequestErrorType
  rawType: string
  status: Opt[int]
  title: Opt[string]
  detail: Opt[string]
  limit: Opt[string]
```

#### ClientError (outer railway error type)

```nim
ClientErrorKind = enum
  cekTransport, cekRequest

ClientError = object
  case kind: ClientErrorKind
  of cekTransport: transport: TransportError
  of cekRequest: request: RequestError
```

#### MethodError (inner railway error type)

```nim
MethodError = object
  errorType: MethodErrorType
  rawType: string
  description: Opt[string]
  extras: Opt[JsonNode]       # lossless preservation of non-standard fields
```

MethodError is intentionally flat — not a case object. RFC 8620 specifies only
`description` as an optional per-type field on method errors. All method error
types share the same shape. No variant-specific fields are RFC-mandated.

`extras` preserves any additional fields the server sends that are not modeled
as typed fields (e.g., some servers send `arguments` on `invalidArguments`).
This is not a user-facing escape hatch like filters — it is a preservation
mechanism for debugging and forward-compatibility. The typed fields (`errorType`,
`rawType`, `description`) remain the primary access path.

#### SetError (per-item error within /set responses)

SetError is a case object because the RFC mandates variant-specific fields on
two error types:
- `invalidProperties` SHOULD carry `properties: String[]` (Section 5.3)
- `alreadyExists` MUST carry `existingId: Id` (Section 5.4, for /copy)

Making these typed and variant-specific means `existingId` cannot be accessed
without matching `setAlreadyExists`.
Shared fields (`rawType`, `description`, `extras`) are always accessible
regardless of variant.

```nim
SetErrorType = enum
  setForbidden = "forbidden"
  setOverQuota = "overQuota"
  setTooLarge = "tooLarge"
  setRateLimit = "rateLimit"
  setNotFound = "notFound"
  setInvalidPatch = "invalidPatch"
  setWillDestroy = "willDestroy"
  setInvalidProperties = "invalidProperties"
  setAlreadyExists = "alreadyExists"
  setSingleton = "singleton"
  setUnknown

SetError = object
  rawType: string
  description: Opt[string]
  extras: Opt[JsonNode]
  case errorType: SetErrorType
  of setInvalidProperties:
    properties: seq[string]
  of setAlreadyExists:
    existingId: Id
  else: discard
```

`SetError` is the per-item error type used by `SetResponse` (§5.4).

---

## Layer 2: Serialisation

### 2.1 JSON Library

#### Option 2.1A: `std/json` with manual serialisation/deserialisation

Use the built-in `JsonNode` tree. Write `toJson`/`fromJson` procs manually for
each type.

- **Pros:**
  - Zero dependencies.
  - Full control over camelCase naming, `#` reference handling, every
    serialisation quirk.
  - Compatible with `raises: []` given a boundary catch. `std/json` raises
    `JsonParsingError` (from `parseJson`), `KeyError` (from `node[key]`), and
    `JsonKindError` (from `to[T]`) — all `CatchableError` subtypes. The
    boundary `proc` catches `CatchableError` and converts to `Result`. Within
    `fromJson` functions, use the raises-free accessors: `node{key}` (returns
    `nil` on missing key), `getStr`, `getInt`, `getFloat`, `getBool` (return
    defaults). These never raise.
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

#### Option 2.1B: `jsony` or `nim-serialization`

Third-party library with hooks for customisation.

- **Pros:** Less boilerplate. Good hook support for custom field names.
- **Cons:**
  - New dependency. Must verify compatibility with the strict compiler
    configuration (`--mm:arc`, `strictFuncs`, `strictNotNil`, `raises: []`).
  - `jsony` uses exceptions internally, which conflicts with `raises: []`.
  - Implicit parsing means validation cannot be injected at the field level
    without hooks.
  - Less control over the total-parsing guarantee.

#### Option 2.1C: `std/json` + code generation macro

Macro generates `toJson`/`fromJson` from type definitions, handling camelCase
automatically. Manual overrides for special types.

- **Pros:** Less boilerplate than 2.1A, no external dependencies.
- **Cons:** Macros add compile-time complexity. Debugging macro-generated code is
  harder. Must work with strict settings.

#### Decision: 2.1A, potentially evolving to 2.1C

Start manual. The types with tricky serialisation (invocations as JSON arrays,
`#`-prefixed reference fields, PatchObject with JSON Pointer keys, filter
operators with recursive structure) require manual serialisation regardless. The
remaining types are straightforward. Starting manual means understanding every
detail of the wire format, which matters when debugging against a real server. If
boilerplate becomes painful, introduce a macro for the simple-object pattern.

### 2.2 camelCase Handling

#### Option 2.2A: camelCase in Nim source

Since Nim treats `accountId` and `account_id` as the same identifier, write
`accountId` in type definitions. The field name in Nim is the field name on the
wire. Zero conversion.

- **Pros:** Zero conversion logic. What is written is what goes on the wire.
  `nph` preserves the casing written. `--styleCheck:error` requires consistency
  (use the same casing everywhere), not a specific convention.
- **Cons:** Some Nim style guides prefer snake_case. Needs verification that
  `nph` + `--styleCheck:error` cooperate.

#### Option 2.2B: snake_case in Nim, convert at serialisation boundary

Write `account_id` in Nim. Convert to `accountId` during JSON serialisation.

- **Pros:** Nim-idiomatic naming.
- **Cons:** Conversion logic in every ser/de proc. Unnecessary complexity given
  Nim's style insensitivity.

#### Decision: 2.2A

camelCase in source. Zero conversion. Leverages Nim's style insensitivity.

### 2.3 Result Reference Serialisation

`Referencable[T]` (Decision 1.3B, §1.3) requires custom
serialisation. The wire format uses the JSON key name as the discriminator:

- `rkDirect`: normal key with the value serialised as `T`.
  `{ "ids": ["id1", "id2"] }`
- `rkReference`: key prefixed with `#`, value is a `ResultReference` object.
  `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

The same logical field appears under two different JSON keys. Custom `toJson`
and `fromJson` procedures handle this dispatch. There are only ~4
referenceable fields across the standard methods.

---

## Layer 3: Protocol Logic

This layer covers three logical groups that share the same dependencies
(Layer 1 types + errors, Layer 2 serialisation) and the same dependents
(Layer 4 transport):

1. **Envelope logic** — request building, call ID generation, response dispatch.
2. **Method framework** — entity type registration, associated type resolution,
   method-specific logic.
3. **Result reference construction** — builder-produced references, path constants.

Envelope data types (Invocation, Request, Response) are defined in Layer 1
(§1.4). Generic method framework types (Filter[C], Comparator, PatchObject,
AddedItem) are defined in Layer 1 (§1.5). This layer covers the logic that
operates on those types.

### 3.1 Invocation Format

Invocations are serialised as 3-element JSON arrays, not JSON objects. This is
handled by custom serialisation in Layer 2.

### 3.2 Method Call ID Generation

#### Option 3.2A: Auto-incrementing counter

`"c0"`, `"c1"`, `"c2"`. What the Rust implementation does.

- **Pros:** Simple, deterministic, unique within a request.
- **Cons:** None. IDs are only meaningful within a single request/response pair.

#### Option 3.2B: Method-name-based descriptive IDs

`"mailbox-query-0"`, `"email-get-1"`.

- **Pros:** Easier debugging — visible which call produced which response.
- **Cons:** More complex generation. Needs uniqueness suffix for repeated methods.

#### Decision: 3.2A

Internal plumbing. No safety implications. Keep simple.

### 3.3 Request Builder Design

#### Option 3.3A: Direct construction

User builds `Request` objects by constructing `Invocation` objects manually.

- **Pros:** No builder infrastructure.
- **Cons:** Verbose. User must manually track call IDs, construct
  `ResultReference` objects, manage the `using` capability list. Error-prone.
  Antithetical to the goal of making misuse difficult.

#### Option 3.3B: Builder with method-specific sub-builders

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

#### Option 3.3C: Builder with generic method calls

One generic `call` proc instead of method-specific sub-builders.

- **Pros:** Less infrastructure than 3.3B.
- **Cons:** Less discoverable. Requires knowing method type names.

#### Decision: 3.3B

The builder must produce an **immutable** request value. The builder uses
owned mutation (`var` parameter under `strictFuncs`) — the Nim equivalent of
a `State` computation. The compiler enforces that mutation does not escape the
owned parameter: no IO, no global state, no heap mutation through references.
This is referentially transparent at the API boundary — same inputs produce
the same `Request`. `.build()` is the point where accumulation ends and the
immutable value is produced, not a purity boundary. The builder is functional
core, not imperative shell; the effect boundary is at Layer 4 (`proc send`).

```
# Functional core: builder accumulates via owned var (func, no IO)
# Functional core: immutable Request value from .build()
# Imperative shell boundary: Layer 4's proc send()
```

This is the builder pattern as used in Rust — `&mut self` accumulation, frozen
immutable value after `.build()`. Both sides are pure; only `send()` is
effectful.

**Nim limitation:** Cannot enforce "consumed by build" at the type level. In
Rust, `build(self)` takes ownership. In Nim, the builder remains accessible.
Mitigate by clearing builder state in `build()`.

### 3.4 Response Processing

#### Option 3.4A: Fully typed response dispatch

Each invocation response deserialised into its concrete type based on method name.
Large enum of all response types.

- **Pros:** Type-safe access.
- **Cons:** Complex deserialisation dispatch. Massive response enum.

#### Option 3.4B: Typed wrapper over raw JSON

Deserialise envelope. Keep individual method responses as `JsonNode`. Typed
extraction on demand.

- **Pros:** Simple deserialisation.
- **Cons:** Runtime type errors if extracting wrong type at wrong index.

#### Option 3.4C: Phantom-typed response handles

The request builder returns typed handles. Each handle carries the expected
response type as a phantom parameter:

```
ResponseHandle[T] = distinct string  # wraps the call ID; T is phantom

# Builder returns:
let queryHandle: ResponseHandle[QueryResponse[Mailbox]] = builder.addQuery(...)

# Response extraction is type-safe:
func get[T](resp: Response, handle: ResponseHandle[T]): Result[T, MethodError]
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

#### Decision: 3.4C

Phantom-typed handles. Compile-time response type safety via the phantom
parameter. The per-invocation `Result[T, MethodError]` is the inner railway.
Strictly better than untyped extraction, even though Nim cannot prove the
relationship as strongly as Haskell.

`get[T]` is a Layer 3 function that operates on the Layer 1 `Response` type
directly — no separate wrapper type is needed. JSON-to-type deserialisation
(Layer 2's `fromJson` functions) is a pure tree transform (`JsonNode` → `T`,
no IO), compatible with `func`. `get[T]` locates the `Invocation` by matching
the `ResponseHandle`'s call ID, then delegates to the appropriate Layer 2
`fromJson` to produce the typed result.

### 3.5 Entity Type Framework

The 6 standard methods are generic over entity type. Each entity type must
define: what properties it has, what filter conditions it supports, what sort
comparators it supports, and what method-specific arguments it has.

#### Option 3.5A: Concept + overloaded procs (most typeclass-like)

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

#### Option 3.5B: Generic procs + overloaded type-specific procs (no concept)

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
  - Errors at instantiation time, not at definition time. Same as 3.5A in practice.

#### Option 3.5C: Template-generated concrete types

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

#### Decision: 3.5A — concepts for simple interfaces

Concepts are the primary choice for encoding the "entity types must satisfy an
interface" constraint. Simple, non-recursive, non-deeply-chained concepts work
well under the strict compiler settings. The caveat is complexity depth: deeply
nested concept hierarchies or concepts that chain through multiple layers of
generic constraints are fragile and should be avoided. For those cases, fall back
to 3.5B (plain overloaded procs). Document the required interface explicitly in
either case — this is the moral equivalent of the typeclass definition that Nim
cannot enforce as strongly as Haskell.

Keep 3.5C as a reserve option where the number of concrete types per entity may
make templates worthwhile.

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

`Filter[C]` (defined in Layer 1 §1.5) is parameterised by condition type `C`,
which varies per entity. Each entity type defines its own filter conditions
and sort properties. The Rust implementation uses associated types on traits.
Nim lacks associated types. The question is how to resolve `C` from the entity
type.

#### Option 3.7A: Multiple type parameters

```
QueryRequest[T, F, S] = object  # T = entity, F = filter, S = sort
```

- **Pros:** Fully type-safe.
- **Cons:** Three type parameters is unwieldy. Every proc needs all three.

#### Option 3.7B: Overloaded type-level templates (simulated associated types)

```
template filterType(T: typedesc[Mailbox]): typedesc = MailboxFilter
template filterType(T: typedesc[Email]): typedesc = EmailFilter
```

Then `QueryRequest[T]` uses `filterType(T)` to resolve the filter type.

- **Pros:** Single type parameter. Type-specific behaviour via overloads.
  Closest to Haskell's type families or Rust's associated types. Must be
  `template` (not `proc`) because `typedesc` return values used in type
  positions require compile-time evaluation.
- **Cons:** Relies on compile-time template resolution in type positions. Verified
  to work (Nim test suite: `t5540.nim`, `tuninstantiatedgenericcalls.nim`), but
  interactions with deeply nested generics under strict mode remain a risk.

#### Option 3.7C: `JsonNode` for filters/sorts

Untyped filters. Typed filter constructors per entity return `JsonNode`.

- **Pros:** No generic filter complexity. Works immediately.
- **Cons:** Loses compile-time enforcement. A `MailboxFilter` could be used with
  `Email/query`. Runtime errors only from the server. Antithetical to the
  "make illegal states unrepresentable" principle.

#### Decision: 3.7B, with 3.7B-fallback as the safe default

Typed filters from the start. No `JsonNode` escape hatches in the user-facing
API. Use type-level `template`s (not `proc`s) for associated type resolution.
If template-based resolution proves fragile under strict mode, fall back to
explicit two-parameter types with convenience aliases (see below).

Core defines the generic filter *framework* but no concrete filter types.
Concrete filters come from RFC 8621 and other extensions.

#### Fallback if 3.7B fails

If `filterType(T)` does not work in a type position under strict mode, use
explicit two-parameter types with convenience aliases:

```
QueryRequest[T, F] = object
  filter: Opt[Referencable[Filter[F]]]
  ...

type MailboxQueryRequest = QueryRequest[Mailbox, MailboxFilterCondition]
```

More verbose but achievable. The alias hides the second parameter.

### 3.8 Entity-Specific Patch Builders

`PatchObject` (defined in Layer 1 §1.5, Decision 1.5B) is the opaque distinct
type for update patches. When adding entity types, typed builders produce
`PatchObject` values with property validation.

#### Option 3.8A: Typed patch builder per entity

Entity-specific builder that produces `PatchObject` values.

- **Pros:** Type-safe, discoverable.
- **Cons:** Requires a builder per entity type.

#### Decision: 3.8A when adding entity types

Core has no concrete entity types. When adding RFC 8621, add typed patch
builders per entity that produce `PatchObject` values. Each builder validates
property names and types at compile time.

### 3.9 SetResponse Modelling

A `/set` response contains parallel maps: `created`/`notCreated`,
`updated`/`notUpdated`, `destroyed`/`notDestroyed`. An ID appears in exactly
one map per operation.

#### Option 3.9A: Mirror RFC structure (parallel maps)

```
SetResponse[T] = object
  created: Table[Id, T]
  notCreated: Table[Id, SetError]
  ...
```

- **Pros:** Direct mapping to/from JSON. No transformation.
- **Cons:** Invariant "each ID in exactly one map" not enforced by types.

#### Option 3.9B: Unified result map (per-item railway)

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

#### Decision: 3.9B internally, 3.9A on the wire

Deserialise from the RFC format (parallel maps). Immediately merge into `Result`
maps. The user-facing type is the unified result map. This gives users the clean
per-item railway model while respecting the wire format.

### 3.10 Result Reference Construction

For a client library, result reference construction is about **building**
references, not resolving them (the server does that).

Result reference types (ResultReference, Referencable[T]) are defined in
Layer 1 (§1.3). Serialisation of the `#`-prefixed key format is handled in
Layer 2 (§2.3). This section covers:

1. Builder-produced references: the returned handle can produce
   `ResultReference` values pointing to specific paths in that call's response.
2. Path constants for common reference targets.

#### Standard Reference Paths

From the RFC and reference implementations:

```
/ids                 — IDs from /query result
/list/*/id           — IDs from /get result
/added/*/id          — IDs from /queryChanges result
/created             — created IDs from /set result
/updated             — updated IDs from /changes result
/updatedProperties   — changed properties from /changes result
```

#### Builder Integration

The phantom-typed handle from §3.4 produces references:

```
let queryHandle = builder.addQuery(Mailbox, filter = ...)
# queryHandle : ResponseHandle[QueryResponse[Mailbox]]

let idsRef: ResultReference = queryHandle.reference("/ids")

builder.addGet(Mailbox, ids = referenceTo(idsRef))
# ids : Referencable[seq[Id]] = rkReference branch
```

#### Path Validation

##### Option 3.10A: No validation

String path, library provides constants for common paths. Server returns
`invalidResultReference` if wrong.

- **Pros:** Simple.
- **Cons:** No compile-time feedback for incorrect paths.

##### Option 3.10B: Validated paths

Constants only. No arbitrary string paths:

```
func idsPath(): string = "/ids"
func listIdsPath(): string = "/list/*/id"
```

- **Pros:** Typo-proof. Discoverable.
- **Cons:** Cannot reference custom paths. Some server extensions may use
  non-standard paths.

##### Decision: 3.10A with constants

Provide constants for all standard paths. Allow arbitrary string paths for
extensibility. The server validates; the client provides convenience.

**Nim type system gap:** In a dependently-typed language (Idris, Agda), the path
could carry proof that it resolves to `seq[Id]`. In Nim (and Rust, Haskell
without advanced extensions), the relationship between path and result type is
a runtime assumption documented by convention.

---

## Layer 4: Transport + Session Discovery

### 4.1 HTTP Client

#### Option 4.1A: `std/httpclient`

Built-in, synchronous.

- **Pros:**
  - No dependencies. Synchronous is appropriate for a C ABI library.
  - Works with `--mm:arc`.
- **Cons:** Limited TLS configuration. No connection pooling. May not handle all
  redirect edge cases.

#### Option 4.1B: libcurl wrapper

- **Pros:** Battle-tested TLS, connection pooling, proxy support.
- **Cons:** C dependency. More complex build.

#### Decision: 4.1A

Swap HTTP backends later without affecting other layers. `std/httpclient` is
sufficient for session discovery and API requests. Upgrade to libcurl if TLS or
performance becomes an issue.

**`raises` caveat:** `std/httpclient`'s request functions (`get`, `post`,
`request`, etc.) have no `{.raises.}` annotations. The compiler treats them as
potentially raising `Exception`. The transport boundary `proc` must catch
`CatchableError` broadly and convert to `TransportError`. Known exception types
include `ProtocolError`, `HttpRequestError` (both `IOError` subtypes),
`ValueError`, and `TimeoutError`.

### 4.2 Session Discovery

The RFC specifies DNS SRV lookup, then `.well-known/jmap`, then follow redirects.
In practice, every client library takes a direct URL or does `.well-known` only.
None implement DNS SRV.

Implement: direct URL and `.well-known/jmap`. Skip DNS SRV.

### 4.3 Transport Layer Boundary

The transport layer is the imperative shell. Every function is `proc` (side
effects: IO). Everything below is `func` (pure). The boundary is explicit and
narrow:

```
proc send(client: JmapClient, request: Request): JmapResult[Response]
```

All errors become `ClientError` on the error track. Success produces an immutable
`Response` value.

---

## Layer 5: C ABI Wrapper

### 5.1 Principle

The C ABI is a lossy projection of the Nim API. The Nim API has phantom types,
result types, distinct identifiers, variant objects. The C API has opaque pointers
and error codes. The C layer is not the API designed for — it is a mechanical
translation. All FP correctness lives in the Nim layer.

The mental model: the Nim API is the "real" API. The C ABI is an FFI binding, as
Haskell's FFI exports C-callable wrappers around Haskell functions.

### 5.2 Handle Types

```c
typedef struct JmapClient_s* JmapClient;
typedef struct JmapSession_s* JmapSession;
typedef struct JmapRequest_s* JmapRequest;
typedef struct JmapResponse_s* JmapResponse;
```

Opaque pointers. C consumers never see Nim type internals.

### 5.3 Memory Ownership

#### Option 5.3A: Per-object free functions

Each object type has `_new` and `_free` functions. Accessor functions return
borrowed pointers.

- **Pros:** Standard C pattern. Familiar. Each object has clear lifetime.
- **Cons:** Easy to leak. Easy to use-after-free.

#### Option 5.3B: Arena/context allocator

One context object. All allocations scoped to it. Single `_free` call releases
everything.

- **Pros:** One free call. Simpler for C consumers.
- **Cons:** Coarser lifetime management. Objects cannot outlive their context.
  Less familiar pattern.

#### Decision: 5.3A

Per-object free functions. Standard C pattern. Arena support can be added later
as a convenience layer on top.

---

## Summary of Decisions

Option IDs use section-based numbering: the prefix identifies the document
section where the option is defined (e.g., 1.3B is the second option in §1.3).

| Layer | Decision | Rationale |
|-------|----------|-----------|
| 1. Types+Errors | Full distinct types + `{.requiresInit.}` for all identifiers (1.1A) | Make illegal states unrepresentable; prevent default construction |
| 1. Types+Errors | Case object capabilities with exhaustive enum (1.2A) | Closed world with explicit unknown case |
| 1. Types+Errors | `Referencable[T]` variant type (1.3B) | Illegal state (both direct + ref) unrepresentable |
| 1. Types+Errors | Opaque PatchObject distinct type (1.5B) | Distinct from arbitrary tables |
| 1. Types+Errors | Three-track railway: ValidationError, ClientError, MethodError (1.6C) | Construction, transport, and per-invocation error separation |
| 1. Types+Errors | Full enum + rawType for lossless round-trip (1.7C) | Parse, don't validate; preserve original |
| 1. Types+Errors | SetError as case object with variant-specific fields | invalidProperties/alreadyExists carry typed data |
| 2. Serialisation | `std/json` manual ser/de, no external deps (2.1A) | Total parsing, `raises: []` via boundary catch |
| 2. Serialisation | camelCase in Nim source (2.2A) | Zero conversion, leverages style insensitivity |
| 3. Protocol | Auto-incrementing call IDs (3.2A) | Simple, no safety implications |
| 3. Protocol | Builder produces immutable Request (3.3B) | Owned mutation under strictFuncs; effect boundary at Layer 4 |
| 3. Protocol | Phantom-typed ResponseHandle (3.4C) | Compile-time response type safety |
| 3. Protocol | Entity type concept (3.5A, fallback 3.5B) | Closest to typeclasses |
| 3. Protocol | Associated type resolution via templates (3.7B) | No JsonNode escape hatches in user-facing API |
| 3. Protocol | Entity-specific typed patch builders (3.8A) | Type-safe construction per entity |
| 3. Protocol | SetResponse as unified Result maps (3.9B) | Per-item railway |
| 3. Protocol | String paths with constants, no validation (3.10A) | Server validates; client provides convenience |
| 4. Transport | `std/httpclient`, synchronous (4.1A) | No deps, swappable later |
| 4. Transport | Direct URL + .well-known, no DNS SRV | Matches all reference implementations |
| 5. C ABI | Lossy projection, opaque handles, per-object free (5.3A) | Standard C pattern |

## Testability per Layer

Each layer is testable without the layers above it:

- **Layer 1 (Types + Errors):** Unit test type construction, distinct type
  operations, smart constructors. Construct Invocation, Request, Response values.
  Construct ResultReference and Referencable[T] in both branches. Construct
  Filter[C] recursive structures, Comparator, PatchObject, AddedItem. Unit test
  error construction, kind discrimination, round-trip preservation of rawType.
- **Layer 2 (Serialisation):** Unit test round-trip serialisation against RFC
  JSON examples. Verify Invocation serialises as 3-element JSON array. Verify
  Referencable[T] serialises correctly for both branches.
- **Layer 3 (Protocol Logic):** Unit test request builder logic: call ID
  generation, phantom-typed handle creation, builder produces correct immutable
  Request values. Unit test entity type concept satisfaction (3.5A). Unit test
  method request/response construction. Verify associated-type template
  resolution (3.7B). Verify unified Result maps in SetResponse (3.9B). Unit test
  that builder produces correct ResultReference values from phantom-typed
  handles. Verify path constants.
- **Layer 4 (Transport):** Integration test against a real or mock JMAP server.
- **Layer 5 (C ABI):** Integration test from C code linking the shared library.

The RFC includes JSON examples for almost every type. These serve as test
fixtures for Layers 1 and 2.
