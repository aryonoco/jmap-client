# Architecture

Cross-platform JMAP (RFC 8620 Core, RFC 8621 Mail) client library in Nim
with a planned C ABI surface.

This document describes the library as it is implemented under
`src/jmap_client/`. The source tree is the source of truth; this document
mirrors it. Each design section records the option in force and the
options it was chosen against, so the reasoning behind the chosen shape
remains discoverable from the doc itself.

## Foundational Decisions

Five architectural decisions constrain every subsequent choice:

1. **C ABI strategy: Approach A (rich Nim internals, thin C wrapper).** The
   library is an idiomatic Nim API. The C ABI, when built, will be a separate
   layer that exposes opaque handles and accessor functions. The Nim API is
   the canonical API; the C ABI is a lossy projection of it.

2. **Decomposition: bottom-up by layer.** Each layer depends only on layers
   below it and is fully testable in isolation.

3. **Definition of done for the protocol surface: all six standard method
   patterns work with result references.** `/get`, `/set`, `/changes`,
   `/query`, `/queryChanges`, `/copy` are functional with result reference
   support for chaining method calls within a single request.

4. **External dependency: `nim-results`.** The railway (`Result[T, E]`,
   `Opt[T]`, `?`, `map`, `flatMap`, `mapErr`) comes from the `nim-results`
   package (status-im/nim-results), not the standard library. Nim's stdlib
   provides only `Option[T]`, which lacks `?` for early return and `mapErr`
   for error-rail transforms. `nim-results` is the sole external dependency
   for the core library; it is compatible with `--mm:arc` and
   `{.push raises: [].}`.

5. **Five-layer FP-first decomposition for Core; sideways extension for
   RFC 8621.** Each Core layer boundary corresponds to a genuine change in
   the nature of the code: pure algebraic data types (Layer 1), JSON
   parsing (Layer 2), pure protocol logic (Layer 3), IO (Layer 4), FFI
   (Layer 5). The split maps directly to how the same library would be
   structured in Haskell or F# — the boundaries are language-independent
   consequences of the functional programming model. The RFC 8621 mail
   extension (Layer 6, under `mail/`) mirrors the L1/L2/L3 split sideways,
   depending only on the Core types, serialisation, and protocol layers.
   The mail layer never crosses into Layer 4 (transport) or Layer 5 (C ABI).
   See "Why 5 Layers" for the Core split and §6 for the mail-extension
   layout.

## Design Principles

The library follows functional programming principles throughout:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `map`,
  `flatMap`, `mapErr`, and the `?` operator for early return. Each railway
  is two-track (success rail + error rail); the library composes three
  lifecycle railways for construction, transport, and per-invocation
  outcomes, plus a data-level Result pattern for per-item set outcomes
  (§1.6).
- **Functional Core, Imperative Shell** — every Layer 1–3 module sits
  under `{.push raises: [], noSideEffect.}`. Side effects are confined to
  Layer 4 (HTTP transport) and the Layer 5 FFI boundary. Layer 4 modules
  carry only `{.push raises: [].}` because IO procs cannot be `noSideEffect`.
- **Immutability by default** — `let` bindings everywhere. `var` is
  permitted in two pure patterns: (a) as a local variable inside `func`
  when building a return value from stdlib containers whose APIs require
  mutation, and (b) as an owned `var` parameter in `func` for builder
  accumulation. Both patterns are referentially transparent — `strictFuncs`
  enforces that mutation does not escape through `ref`/`ptr` indirection.
- **Total functions** — every function has a defined output for every
  input. `{.push raises: [].}` on every module. No exceptions. No partial
  functions.
- **Parse, don't validate** — deserialisation produces well-typed values or
  structured errors. Invariants enforced at parse time, not checked later.
- **Make illegal states unrepresentable** — variant types, distinct types,
  and smart constructors encode domain invariants in the type system
  where the type system permits. Some invariants are enforced at
  construction time by higher layers rather than by the type definition,
  because stdlib types like `JsonNode` cannot be further constrained
  without a wrapper.

## Nim's FP Ceiling

Before the layer-by-layer analysis, a clear picture of where Nim supports
these principles and where it forces compromises.

### What Nim gives us

- `func` — compiler-enforced purity: no access to global/thread-local
  state, no calling side-effecting procs, no IO. Combined with
  `--experimental:strictFuncs` (enabled in this project), mutation through
  `ref`/`ptr` indirection is also forbidden. Without `strictFuncs`, `func`
  permits mutation reachable through reference parameters — `strictFuncs`
  closes this gap.
- `let` — immutable bindings.
- `{.push raises: [].}` — total functions at the module level. The
  compiler rejects any function that can raise. Combined with
  `Result[T, E]`, this is the Nim equivalent of checked effects.
- `distinct` types — newtypes. `type Id = distinct string` creates a new
  type that is not implicitly convertible. Stronger than a type alias;
  operations must be explicitly borrowed.
- `Result[T, E]` and `Opt[T]` from the `nim-results` package — the sole
  external dependency. Provides `map`, `flatMap`, `mapErr`, `mapConvert`,
  `valueOr`, and the `?` operator for early return (analogous to Rust's
  `?`). `Opt[T]` replaces stdlib's `Option[T]`, integrating with the `?`
  operator and `{.push raises: [].}`. This is the railway.
- Case objects — the closest thing to algebraic data types. Discriminated
  unions with a tag enum.
- UFCS — `x.f(y)` and `f(x, y)` are the same. Enables pipeline-style
  `.map().flatMap().filter()` chaining.
- `collect` macro (`std/sugar`) — comprehension-style collection building.
  Preferred over `mapIt`/`filterIt` for building new collections.
  `allIt`/`anyIt` from `std/sequtils` remain the right choice for boolean
  predicates over sequences. No closures, compatible with `{.raises: [].}`
  and `func`. **Caveat:** nesting `collect` inside the `%*` macro (e.g.,
  to build a JSON array within a JSON object literal) can trigger
  SIGSEGV under `--mm:arc` due to interaction between macro expansion and
  ARC reference tracking inside `{.cast(noSideEffect).}:` blocks. Use a
  manual `newJArray()` loop in those cases instead.

### What strict flags upgrade

These were traditional Nim limitations. With the strict experimental
flags enabled in this project, they are effectively resolved:

1. **Case objects as sum types.** Case objects are discriminated unions.
   In standard Nim, discriminator reassignment is already restricted: the
   compiler rejects assignments that would change the active branch. With
   `let` bindings (used throughout this project), the discriminator is
   fully immutable. `--experimental:strictCaseObjects` (enabled in this
   project) adds compile-time **field access validation**: the compiler
   rejects any `obj.field` access where it cannot prove the discriminator
   matches that field's branch — turning a potential runtime `FieldDefect`
   into a compile error.

   **ARC hazard: `{.cast(uncheckedAssign).}:` on case object discriminators.**
   When a case object's `else` branch contains `ref` fields (e.g.,
   `rawData: JsonNode`), using `{.cast(uncheckedAssign).}:` to reassign
   the discriminator at runtime corrupts ARC's branch tracking. ARC
   erroneously runs the branch destructor on discriminator change even
   when both the old and new values are in the same `else` branch,
   causing double-free on subsequent object destruction (SIGSEGV in
   `nimRawDispose`). Confirmed with Nim 2.2.8 under `--mm:arc`. The
   workaround is to use exhaustive `case` with compile-time literal
   discriminators for each variant. Note: `uncheckedAssign` IS safe when
   the `else` branch has **no `ref` fields** (e.g., `else: discard`) —
   ARC has nothing to mistrack. See Layer 2 design doc §2 Pattern B for
   details.

2. **Exhaustive pattern matching.** `case` statements on `enum` values are
   already exhaustive in standard Nim — missing branches are a compile
   error. `--experimental:strictCaseObjects` upgrades the compiler's
   case-object branch analysis from a warning to an error when field
   access cannot be proven safe. Together, these give case objects strong
   compile-time guarantees.

### What Nim still denies us

1. **No higher-kinded types.** Cannot abstract over `Result[_, E]` vs
   `Opt[_]` vs `seq[_]`. No `Functor`, no `Monad`, no `Applicative`. Each
   result-returning pipeline is concrete.

2. **No typeclass/trait coherence.** Nim's `concept` is structural, not
   nominal. No way to enforce that a type implements a set of operations
   at the definition site. Errors appear at instantiation time.

3. **No monadic do-notation.** Chaining with `flatMap` or `?` for early
   return. The `?` operator is pragmatically close to Rust's and is the
   primary ROP tool.

4. **Immutability is opt-in, not default.** Object fields are mutable
   unless the object is bound with `let`. No way to declare a field as
   read-only in the type definition. Immutability protected through
   module boundaries — do not export setters or mutable fields. The
   workaround is to keep fields private (no `*` export marker) and expose
   read-only accessor `func`s. However, this prevents direct
   `case obj.field` matching, which requires the discriminator field to
   be visible. In practice, `let` bindings and module boundaries are the
   enforcement mechanisms — convention-enforced, not compiler-enforced.
   Discriminator reassignment to a different branch is rejected by the
   compiler in standard Nim. `--experimental:strictCaseObjects` further
   prevents accessing fields from the wrong branch at compile time.

5. **No sealed constructors for object types — mitigated by private
   fields.** `Foo(field: val)` always compiles if fields are public.
   `{.requiresInit.}` prevents implicit default construction
   (`var x: Foo`) but not explicit construction. For distinct types, the
   base constructor is hidden. For non-distinct objects, module
   boundaries and smart constructors provide the seal. **When an object
   has at least one module-private field, direct construction from
   outside the defining module is impossible.** This "private field"
   pattern is used by `Comparator`, `Invocation`, `AddedItem`, `Session`,
   `ResultReference`, the typed `*CreatedItem` mail types, `MethodError`,
   `RequestError`, and others. Functions that depend on smart-constructor
   invariants use `raiseAssert` (a `Defect`) for the unreachable branch —
   this is outside the `Result`/`Opt` railway.

6. **`UnsafeSetLen` interacts with containers.** When a field of `T` is
   `{.requiresInit.}`, Nim's `seqs_v2.shrink` calls `default(T)` in
   lifecycle hooks — a hard error under `--warningAsError:UnsafeSetLen`.
   The implementation avoids `{.requiresInit.}` on fields of objects
   stored in `seq[T]` or `Result[T, E]`. The Pattern A "private
   `rawX: string` with typed accessor" idiom (used by `Comparator`,
   `Invocation`, `AddedItem`, `ResultReference`, `Session`,
   `EmailSubmissionBlueprint`, `EmailBlueprint`, …) keeps the wire
   shape default-constructible for compiler lifecycle hooks while the
   private field blocks user construction.

7. **`config.nims` vs `.nimble` flag enforcement.** The Nim compiler
   reads `config.nims` but NOT `.nimble` files. `just build`/`just test`/
   `just lint` use `nim c`/`testament`/`nim check` directly, so only
   flags in `config.nims` are enforced during the standard `just ci`
   workflow. Flags that fire at generic instantiation sites (e.g.,
   `UnsafeSetLen`, `Uninit`) cannot be enforced via `config.nims` because
   `{.push warning[...]: off.}` only affects the defining module, not
   importing modules. Such flags remain declared in `.nimble` for
   documentation but are intentionally omitted from `config.nims`.

8. **`{.push raises: [].}` does not propagate to callable parameters.**
   Proc-type parameters (callbacks) require explicit `{.raises: [].}`
   annotation even inside modules with `{.push raises: [].}`. The push
   applies to function definitions in the module, not to proc-type
   parameters within those definitions. Both `{.noSideEffect.}` and
   `{.raises: [].}` must be declared on callback parameter types.
   Examples: `Filter[C].fromJson`, `Referencable[T].fromJsonField`,
   the callback overload of `dispatch.get[T]`.

### Practical consequence

Nim allows code that *behaves* like F#/Haskell — total functions, result
types, immutable bindings, pure core — and with the strict experimental
flags enabled in this project, the compiler enforces more than stock Nim.
The enforcement stack:

- `{.push raises: [].}` — total functions (no `CatchableError` escapes)
- `func` + `strictFuncs` — purity (no global state, no IO, no heap
  mutation through references)
- `let` — immutable bindings
- `distinct` types — newtypes
- `strictCaseObjects` — compile-time field access validation for case
  objects
- `strictDefs` — all variables must be explicitly initialised
- `strictNotNil` — nilability tracking via flow analysis

Module boundaries and smart constructors cover the remaining gaps
(principally: no per-field immutability declarations and no higher-kinded
abstractions). `nim-results` provides the railway (`Result[T, E]`,
`Opt[T]`, `?` operator).

## Layer Architecture

```
Layer 1: Domain Types + Errors (pure types and construction algebra)
Layer 2: Serialisation       (JSON parsing boundary — "parse, don't validate")
Layer 3: Protocol Logic      (builders, dispatch, result references, method framework)
Layer 4: Transport + Session (imperative shell — HTTP IO)
Layer 5: C ABI Wrapper       (FFI projection — designed, not yet implemented)
Layer 6: RFC 8621 Mail       (extension; mirrors L1/L2/L3 split under mail/)
```

**Governing principle: types, errors, and their construction algebra as
a single pure layer.** Layer 1 contains every pure data type — structs,
enums, variant objects, railway aliases — and the pure functions that
enforce their construction invariants (smart constructors, validation).
In Haskell, `Data.Map` exports both the type and `singleton`/`fromList`;
in F#, a type module includes its creation functions. The type and its
construction algebra are a unit. Layer 1 can be defined without importing
anything above it. No serialisation logic, no protocol logic, no IO.
Layers 2–5 contain the downstream logic that operates on Layer 1 types.

**`JsonNode` as a Layer 1 data type.** `Invocation.arguments`, the `extras`
field on errors, and the `rawData` branch of `ServerCapability` use
`JsonNode` from `std/json`. This is `JsonNode` as a *data structure* (a
tree of values), not as a serialisation concern. The L1/L2 boundary
prohibits serialisation *logic* — `parseJson`, `to[T]`, camelCase
conversion, `#`-prefix handling — not the tree type itself. Analogous to
Haskell's `Data.Aeson.Value` (importable from `Data.Aeson.Types` without
bringing parsing into scope). Layer 1 modules use selective import
(`from std/json import JsonNode, JsonNodeKind`) to bring only the data
types into unqualified scope. Other `std/json` symbols (`parseJson`,
`%*`, `to`, etc.) remain accessible only via explicit module
qualification (`json.parseJson`), making the L1/L2 boundary enforced by
the import system.

Each layer depends only on layers below it. Each is fully testable
without the layers above.

Dependency graph:

```
L1 (types+errors) ← L2 (serialisation) ← L3 (protocol logic) ← L4 (transport) ← L5 (C ABI)
                                           ↑
                                           └── L6 (RFC 8621 mail; depends on L1, L2, L3 only)
```

The Core chain (L1 → L5) is a strict linear DAG. The RFC 8621 mail
extension is a sideways extension of the Core layers: each `mail/` file
sits in exactly one of L1, L2, or L3 and depends only on Core modules at
that layer or below. The mail layer never depends on Layer 4 (transport)
or Layer 5 (C ABI). The library entry point re-exports both Core and
mail symbols.

### Why 5 Layers

A finer-grained 8-layer split is plausible: separate Core Types from
Error Types, separate Envelope Logic from Methods from Result
References. The 5-layer split collapses those boundaries, each
collapse justified by FP principles:

**Types + Errors → Layer 1.** Error types are pure data definitions —
case objects, enums, type aliases. No FP principle separates "value
ADTs" from "error ADTs"; both are algebraic data types in the
functional core. In Haskell, `data MethodError = ...` lives in the
same module as `data GetResponse = ...`. In F#, error discriminated
unions live alongside domain types. More critically,
`JmapResult[T] = Result[T, ClientError]` — the outer railway alias —
needs both `T` and `ClientError` visible. Splitting them across layers
forces every downstream module to import both, creating an artificial
bridge that every consumer must cross.

**Envelope Logic + Methods + Result References → Layer 3.** The
request builder must know method shapes to provide typed `addGet`,
`addSet`, `addQuery`. Result reference construction
(`handle.reference(...)`) is a feature of the builder, not a separate
concern. These three concerns share the same dependencies (Layer 1
types, Layer 2 serialisation), the same dependents (Layer 4
transport), and cannot be independently tested in a meaningful way.

**What would go wrong if adjacent layers were merged:**

| Boundary | What breaks if merged |
|----------|----------------------|
| L1 / L2 | Layer 1 already imports `std/json` selectively for `JsonNode` as a data type; merging would add dependency on parsing *logic* (`parseJson`, `to[T]`, camelCase conversion, `#`-prefix handling). Testing smart constructors would require JSON fixtures. Wire format knowledge would leak into type definitions. |
| L2 / L3 | Serialisation is stateless, reusable infrastructure. Protocol logic uses accumulation patterns (immutable builder construction, sequential ID generation) that differ structurally from L2's stateless value-to-value transforms. Mixing them conflates different levels of abstraction and prevents swapping JSON libraries without touching builder logic. |
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
  validation.nim      — ValidationError, Idx (sealed non-negative index),
                        TokenViolation (and other internal *Violation
                        ADTs), borrow templates (defineStringDistinctOps,
                        defineIntDistinctOps, defineHashSetDistinctOps,
                        defineNonEmptyHashSetDistinctOps),
                        Base64UrlChars constant, atomic and composite
                        detector combinators (detectNonEmpty,
                        detectLengthInRange, detectNoControlChars,
                        detectPrintableAscii, detectNoForbiddenChar,
                        detectBase64UrlAlphabet, detectNoCreationIdPrefix,
                        detectLenientToken, detectNonControlString,
                        detectStrictBase64UrlToken,
                        detectStrictPrintableToken, detectNonEmptyNoPrefix),
                        validateUniqueByIt template, ruleOff/ruleOn
                        nimalyzer pragma templates.
  primitives.nim      — Id, UnsignedInt, JmapInt, Date, UTCDate,
                        MaxChanges, NonEmptySeq[T], MaxUnsignedInt and
                        JmapInt range constants, AsciiDigits, DateViolation
                        ADT with detector pipeline, defineNonEmptySeqOps
                        template.
  identifiers.nim     — AccountId, JmapState, MethodCallId, CreationId,
                        BlobId. JmapState/MethodCallId/CreationId/BlobId
                        manually borrow only ==, $, hash to keep them
                        opaque to length and slicing operations.
  collation.nim       — CollationAlgorithmKind, CollationAlgorithm
                        (sealed case object), four IANA constants
                        (CollationAsciiCasemap, CollationOctet,
                        CollationAsciiNumeric, CollationUnicodeCasemap),
                        parseCollationAlgorithm.
  capabilities.nim    — CapabilityKind (12 IANA URIs + ckUnknown — see
                        §1.2), CoreCapabilities, ServerCapability,
                        parseCapabilityKind, capabilityUri, hasCollation.
  methods_enum.nim    — MethodName (28 wire methods + mnUnknown),
                        MethodEntity (entity category tag, 9 variants
                        including meTest), RefPath (8 result-reference
                        paths), parseMethodName.
  session.nim         — AccountCapabilityEntry, Account, UriPart,
                        UriPartKind, UriTemplate, Session (sealed Pattern
                        A with 10 private rawX fields and matching public
                        accessor funcs). Public helpers
                        findAccount, primaryAccount, findCapability,
                        findCapabilityByUri, hasCapability on both Account
                        and Session. Defines CoreCapabilityUri constant
                        (the canonical urn:ietf:params:jmap:core URI).
                        parseSession is the smart constructor.
  envelope.nim        — Invocation (sealed), Request, Response,
                        ResultReference (partially sealed — resultOf
                        public, rawName/rawPath private), Referencable[T].
                        Constructors initInvocation/parseInvocation,
                        initResultReference/parseResultReference,
                        direct/referenceTo for Referencable.
  framework.nim       — PropertyName, FilterOperator, FilterKind,
                        Filter[C], Comparator (sealed Pattern A),
                        AddedItem (sealed Pattern A), QueryParams.
  errors.nim          — TransportError, RequestError (private errorType,
                        public rawType + cascade message accessor),
                        ClientError (sum), MethodError (private errorType),
                        SetError (case object with public errorType
                        discriminator — see §1.8), RequestContext,
                        classifyException, sizeLimitExceeded,
                        enforceBodySizeLimit, validationToClientError(Ctx).
                        These last five are pure functions on L1 types
                        serving L4 needs.
  types.nim           — Re-exports all of the above; defines
                        `JmapResult[T] = Result[T, ClientError]`.
```

Internal import DAG (each module imports only what its types reference):

| Module | Imports from (within Layer 1) |
|--------|------------------------------|
| `validation` | *(none)* |
| `primitives` | `validation` |
| `identifiers` | `validation` |
| `collation` | `validation` |
| `capabilities` | `primitives`, `collation` |
| `methods_enum` | *(none)* |
| `framework` | `validation`, `primitives`, `collation` |
| `errors` | `validation`, `primitives`, `identifiers` |
| `session` | `validation`, `identifiers`, `capabilities` |
| `envelope` | `validation`, `identifiers`, `primitives`, `methods_enum` |
| `types` | all of the above (re-export hub) |

No cycles. The graph is a DAG, not a linear chain. `methods_enum`,
`identifiers`, `validation` are leaves. `primitives` depends on
`validation`; `collation` depends on `validation`; `capabilities` merges
`primitives` and `collation`; `framework` and `session` merge multiple
branches; `envelope` imports `methods_enum` so its accessors can return
the typed `MethodName` and `RefPath` enums. Each file is independently
testable.

### Layer 2 Internal File Organisation

Layer 2 decomposes into separate modules by domain concern with no
circular dependencies:

```
src/jmap_client/
  serde.nim              — JsonPath, JsonPathElement, JsonPathElementKind,
                           SerdeViolation (kind-tagged structural error
                           type — see §2.4), shared helpers (expectKind,
                           fieldOfKind, fieldJObject/JString/JArray/
                           JBool/JInt, optField, optJsonField, expectLen,
                           nonEmptyStr, wrapInner, collectExtras,
                           parseIdArray, parseIdArrayField, parseOptIdArray,
                           parseKeyedTable, collapseNullToEmptySeq,
                           optToJsonOrNull, optStringToJsonOrNull,
                           jsonPointerEscape, JsonPath operators),
                           distinct-type ser/de templates
                           (defineDistinctStringToJson/FromJson,
                           defineDistinctIntToJson/FromJson),
                           primitive/identifier serde, toValidationError
                           translator (SerdeViolation → ValidationError).
  serde_session.nim      — CoreCapabilities, ServerCapability,
                           AccountCapabilityEntry, Account, Session.
                           ServerCapability / AccountCapabilityEntry
                           fromJson take (uri, data, path) because the URI
                           is the parent map's key. Non-core capability
                           branches use a deep-copy + literal-discriminator
                           construction pattern (mkNonCoreCap) to avoid
                           ARC double-free hazards on shared JsonNode refs.
                           CoreCapabilities.fromJson accepts both
                           maxConcurrentRequests and singular
                           maxConcurrentRequest as a Postel-on-receive
                           accommodation.
  serde_envelope.nim     — Invocation, Request, Response, ResultReference,
                           and the Referencable[T] wire-format helpers
                           referencableKey and fromJsonField (the latter
                           detects #-prefixed keys, rejects co-presence
                           with svkConflictingFields citing RFC 8620 §3.7,
                           and produces a composite "field or #field"
                           svkMissingField when both are absent).
  serde_framework.nim    — FilterOperator, Filter[C] (depth-bounded by
                           MaxFilterDepth = 128), Comparator, AddedItem.
                           Filter[C].fromJson takes a callback-typed
                           condition deserialiser to thread the entity-
                           specific leaf parser through the recursive
                           operator structure.
  serde_errors.nim       — RequestError, MethodError, SetError. SetError
                           dispatch decomposes the case-object reconstruction
                           into per-variant private helpers to keep
                           nimalyzer's complexity rule satisfied; missing
                           or malformed payload for a payload-bearing
                           rawType falls through to the generic `setError`
                           constructor (which projects onto setUnknown
                           rather than failing the parse).
  serialisation.nim      — Re-exports all of the above (Layer 2 hub).
```

Internal import DAG (each module imports only what it needs):

| Module | Imports from (within Layer 2) |
|--------|------------------------------|
| `serde` | *(none — imports Layer 1 `types` only)* |
| `serde_session` | `serde` |
| `serde_envelope` | `serde` |
| `serde_framework` | `serde` |
| `serde_errors` | `serde` |
| `serialisation` | all of the above (re-export hub) |

No cycles. The graph is flat — every domain serde module depends on
`serde` for shared helpers and on Layer 1 `types` for domain types. No
domain serde module imports another domain serde module. Each file is
independently testable.

### Layer 3 Internal File Organisation

Layer 3 decomposes into modules by concern, with an optional ergonomic
extension:

```
src/jmap_client/
  entity.nim          — Entity registration framework
                        (registerJmapEntity, registerQueryableEntity,
                        registerSettableEntity). Pure compile-time
                        templates with no runtime code, no imports.
  methods.nim         — Standard method request types
                        (GetRequest[T], ChangesRequest[T],
                        SetRequest[T, C, U], CopyRequest[T, CopyItem]) and
                        response types (GetResponse[T], ChangesResponse[T],
                        SetResponse[T], CopyResponse[T], QueryResponse[T],
                        QueryChangesResponse[T]). Defines CopyDestroyMode
                        (case object expressing keep / destroyAfterSuccess),
                        SerializedSort and SerializedFilter (distinct
                        JsonNode wrappers used by the builder),
                        serializeFilter / serializeOptFilter /
                        serializeOptSort, and the assembleQueryArgs /
                        assembleQueryChangesArgs helpers. Request `toJson`
                        and response `fromJson` live alongside the types
                        per Decision D3.7. SetResponse[T] and
                        CopyResponse[T] additionally carry `toJson` (with
                        internal split-emitters) for round-trip fixture
                        helpers used by tests; this is the documented
                        exception to D3.7 (§3.12).
  dispatch.nim        — Phantom-typed ResponseHandle[T];
                        NameBoundHandle[T] (call-id + method-name dispatch
                        for RFC 8620 §5.4 compound overloads such as
                        Email/copy onSuccessDestroyOriginal);
                        CompoundHandles[A, B] / CompoundResults[A, B] and
                        ChainedHandles[A, B] / ChainedResults[A, B] for
                        paired extraction; three get[T] overloads (mixin
                        fromJson, callback escape hatch, NameBoundHandle);
                        getBoth for compound and chained pairs; railway
                        bridge serdeToMethodError (SerdeViolation →
                        MethodError); reference convenience constructors
                        (idsRef, listIdsRef, addedIdsRef, createdRef,
                        updatedRef) and the generic `reference[T]`
                        escape hatch; registerCompoundMethod and
                        registerChainableMethod compile-time templates.
  builder.nim         — RequestBuilder (immutable value type pre-seeded
                        with urn:ietf:params:jmap:core in `using` so that
                        strict servers like Apache James 3.9 do not reject
                        requests for missing the core capability).
                        Pure tuple-returning add* funcs (D3.5; see §3.3):
                        addEcho, addGet, addChanges, addSet, addCopy,
                        addQuery, addQueryChanges. Single-type-parameter
                        template aliases addChanges[T], addQuery[T],
                        addQueryChanges[T], addSet[T], addCopy[T] resolve
                        associated typedesc templates (filterType,
                        changesResponseType, createType, updateType,
                        setResponseType, copyItemType, copyResponseType)
                        at the caller's instantiation site via mixin.
                        Capability auto-collection via withCapability.
                        Argument-construction helpers directIds,
                        initCreates.
  convenience.nim     — Pipeline combinators (opt-in, not re-exported by
                        protocol.nim): addQueryThenGet (template),
                        addChangesToGet (func), paired handle types
                        QueryGetHandles[T] / ChangesGetHandles[T] and
                        result types QueryGetResults[T] /
                        ChangesGetResults[T]; getBoth overloads for the
                        paired handle types.
  protocol.nim        — Re-exports entity, methods, dispatch, builder
                        (Layer 3 hub; excludes convenience.nim).
```

Internal import DAG (each module imports only what it needs):

| Module | Imports from (within Layer 3) |
|--------|------------------------------|
| `entity` | *(none — pure templates with no imports)* |
| `methods` | *(none — imports Layer 1 `types` and Layer 2 `serialisation` only)* |
| `dispatch` | `methods` (also imports L1 `types` and L2 `serialisation` for `SerdeViolation` bridge) |
| `builder` | `methods`, `dispatch` |
| `convenience` | `methods`, `dispatch`, `builder` |
| `protocol` | `entity`, `methods`, `dispatch`, `builder` (re-export hub) |

No cycles. `entity` and `methods` are independent base modules.
`dispatch` depends on `methods` for response types. `builder` depends on
both `methods` and `dispatch`. `convenience` depends on the full stack
but is deliberately excluded from `protocol.nim` — users must import it
explicitly for pipeline ergonomics.

---

## Layer 1: Domain Types + Errors

### 1.1 Primitive Identifiers

The RFC defines `Id` (1-255 octets, base64url chars), plus various
semantically distinct identifiers (account IDs, blob IDs, state strings,
etc.).

#### Option 1.1A: Full distinct types for every identifier kind

`AccountId`, `BlobId`, `JmapState` as separate `distinct string` types.
Every operation (`==`, `$`, hash, serialisation) explicitly borrowed or
defined per type.

- **Pros:**
  - Maximum compile-time safety. Cannot pass a `BlobId` where an
    `AccountId` is expected — a bug that would silently produce
    `"accountNotFound"` at runtime.
  - Follows the "make illegal states unrepresentable" principle.
  - `fromJson` for each distinct type is a validating parser — enforces
    format constraints (Id must be 1-255 bytes, base64url-safe) at parse
    time.
  - Matches how Haskell (`newtype AccountId = AccountId Text`) and F#
    (single-case discriminated unions) model this.
- **Cons:**
  - Boilerplate. Each distinct type needs ~3 lines of `{.borrow.}`
    pragmas.
  - Serialisation: each distinct type needs its own `toJson`/`fromJson`.
- **Mitigation:** The boilerplate is ~3 lines per type. `toJson`/`fromJson`
  for distinct strings is one line each. The serialisation boilerplate
  is the validation boundary.

#### Option 1.1B: Single `Id` distinct type, no further subdivision

One `type Id = distinct string` for all JMAP identifiers. `JmapState` as a
separate distinct type. Dates as distinct strings.

- **Pros:** Less boilerplate while still distinguishing IDs from
  arbitrary strings.
- **Cons:** Can pass an account ID where a blob ID is expected. Misses
  the "make illegal states unrepresentable" goal for a common class of
  bug.

#### Option 1.1C: Plain strings

`string` everywhere, doc comments indicating intent.

- **Pros:** Zero overhead, zero boilerplate.
- **Cons:** Defeats the purpose of strict type safety settings. No
  compiler help. Antithetical to the project's principles.

#### Decision: 1.1A

The boilerplate cost is real but small. The safety benefit catches
plausible bugs. The distinct types defined for RFC 8620 Core are: `Id`
(entity identifiers per §1.2, with base64url/1-255 constraints),
`AccountId` (server-assigned, lenient §1.2 validation), `JmapState`,
`MethodCallId` (§3.2, arbitrary client string — not constrained by §1.2),
`CreationId` (§3.3, client-generated, no `#` prefix — not constrained by
§1.2), and `BlobId` (§6, server-assigned blob identifier under §1.2
lenient rules). `MethodCallId` and `CreationId` are separate from `Id`
because the RFC imposes different constraints: §1.2's base64url charset
and 1-255 octet length rules apply to entity identifiers, not to
protocol-level identifiers. `BlobId` is a separate distinct type because
mixing it with entity `Id` values silently routes blob references to the
wrong code path (`Email/import` and `Email/parse` consume `BlobId`
exclusively). `MaxChanges` (§5.2) is `distinct UnsignedInt` with a smart
constructor that rejects zero — used by `/changes` and `/queryChanges`.

For RFC 8621, no further entity-specific identifier distinct types are
introduced. `MailboxId`, `EmailId`, `ThreadId`, etc. would duplicate the
underlying `Id` constraints; the entity types themselves
(`Mailbox.id: Id`, `Email.id: Id`) carry the discriminator at the type
level.

`JmapState`, `MethodCallId`, `CreationId`, `BlobId` manually borrow only
`==`, `$`, and `hash` (no `len` or other string operations) so the types
remain opaque to length and slicing operations that would imply
substructure they do not actually have.

`{.requiresInit.}` is intentionally not used on these distinct types.
The pragma is incompatible with Nim's `seq` lifecycle hooks under
`--warningAsError:UnsafeSetLen`, and the smart-constructor regime
(every value built through a `parseX` returning `Result[T,
ValidationError]` or through wire-side `parseXFromServer` for
server-controlled origins) provides the construction discipline that
the pragma would otherwise enforce.

### 1.2 Capability Modelling

The Session object's `capabilities` field is a map from URI string to a
capability-specific JSON object. The shape varies per capability URI.

#### Option 1.2A: Variant object (case object) with known-variant enum and open-world fallback

```
CapabilityKind = enum
  ckMail, ckCore, ckSubmission, ..., ckUnknown

ServerCapability = object
  rawUri: string  ## always populated — lossless round-trip
  case kind: CapabilityKind
  of ckCore: core: CoreCapabilities
  else: rawData: JsonNode
```

Consumers match on the `kind` enum (exhaustive in Nim).

- **Pros:**
  - Type-safe, pattern-matchable.
  - Closed-world assumption with an explicit open-world case.
  - Known pattern in OCaml (polymorphic variants with catch-all) and
    Rust (`Other(String)` variant).
  - Adding a new capability means adding an enum variant — compiler
    flags every `case` statement that enumerates variants explicitly.
- **Cons:** Adding a new capability requires recompilation.

#### Option 1.2B: Known fields + raw JSON catch-all

Typed fields for `urn:ietf:params:jmap:core`. Everything else stored as
raw `JsonNode` in a `Table[string, JsonNode]`.

- **Pros:** Only parse what is needed. Unknown capabilities preserved.
- **Cons:** Mixed access patterns — typed for core, untyped for
  everything else. `Table[string, JsonNode]` is stringly-typed.

#### Option 1.2C: Typed core only, ignore rest

Parse `CoreCapabilities` fully. Store everything else as `JsonNode`. Add
typed parsing for other capabilities when implementing their RFCs.

- **Pros:** Pragmatic. Core is the only capability needed for RFC 8620.
- **Cons:** Same mixed access pattern as 1.2B. Consumers must know which
  access pattern to use for which capability.

#### Decision: 1.2A

`CapabilityKind` enumerates 12 IANA-registered URIs plus an `ckUnknown`
catch-all:

```
ckMail, ckCore, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
ckUnknown
```

`ckMail` is intentionally first so that the default-constructed
`CapabilityKind` selects the case-object `else` branch (which carries
`rawData: JsonNode` and accepts a `nil` value), avoiding lifecycle-hook
hazards for `ServerCapability` values stored in `seq` containers. The
case object enforces every consumer to handle each capability kind
explicitly, with unknown URIs preserved verbatim in the `else` branch.

`ServerCapability.rawUri` is always populated, even for known kinds, so
round-trip is byte-identical to the wire. `CapabilityKind` must NOT be
used as a `Table` key — multiple vendor extensions map to `ckUnknown`,
which would collide; key by the raw URI string instead.

For RFC 8620 only `ckCore` has a typed branch. The mail extension keeps
`ckMail` and `ckSubmission` in the `else` branch on purpose — see §6.7
for the rationale.

### 1.3 Result Reference Representation

In JMAP, a method argument can be either a direct value or a reference
to a previous method's result. The type must encode this mutual
exclusion. On the wire, the field name gets a `#` prefix when a
reference is used:

- Normal: `{ "ids": ["id1", "id2"] }`
- Reference: `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

The same logical field appears under two different JSON keys.

#### Option 1.3A: Separate optional fields

```
GetRequest[T] = object
  ids: Opt[seq[Id]]
  idsRef: Opt[ResultReference]
```

Serialisation: if `idsRef.isSome`, emit `"#ids"`; else if `ids.isSome`,
emit `"ids"`.

- **Pros:** Simple types.
- **Cons:** Mutual exclusion not enforced by types. Both fields could be
  `Some` simultaneously — an illegal state that the type permits.

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
  properties: Opt[seq[string]]
```

Note: RFC 8620 §3.7's result reference mechanism is generic — any
argument can use a `#`-prefixed key. However, only the canonical
reference targets (`GetRequest.ids` and `SetRequest.destroy`) receive
`Referencable[T]` wrapping in the builder API. Wrapping all fields is
extremely verbose and rarely used. Users needing uncommon references
(e.g., referencing `/updatedProperties` from RFC 8621's `Mailbox/changes`
into `properties`) construct `Request` manually via Layer 1 types.

- **Pros:**
  - Illegal state (both direct and reference) is unrepresentable.
  - Isomorphic to Haskell's `Either T ResultReference`.
  - The `Opt` wrapper handles the "not specified" case. Inner variant
    handles the "direct value vs. reference" case.
- **Cons:**
  - Custom serialisation needed: `Referencable[seq[Id]]` serialises as
    either `"ids": [...]` or `"#ids": { "resultOf": ..., ... }`.
  - Variant object boilerplate for each referenceable field.
- **Mitigation:** Custom serialisation is already the approach
  (Decision 2.1A). There are only ~4 referenceable fields across the
  standard methods.

#### Option 1.3C: Builder pattern hides representation

Builder provides `.ids(seq[Id])` or `.idsRef(ResultReference)` and
internally tracks which was set.

- **Pros:** Best user experience.
- **Cons:** Runtime enforcement only. The underlying type still needs to
  handle both cases. Correctness lives in the builder, not the types.

#### Decision: 1.3B

Variant type (`Referencable[T]`). Illegal states are unrepresentable in
the type system. Smart constructors `direct(value)` and
`referenceTo(reference)` produce values; the builder (Layer 3) provides
ergonomic construction on top. The serialisation format (`#`-prefixed
keys) is handled in Layer 2 (§2.3). The types are correct regardless of
how values are constructed.

### 1.4 Envelope Types

The RFC §3.2-3.4 defines three pure data structures for the
request/response protocol:

- **Invocation** — a tuple of (method name, arguments object, method
  call ID). On the wire, serialised as a 3-element JSON array, not a
  JSON object.
- **Request** — a `using` capability list, a sequence of Invocations,
  and an optional `createdIds` map.
- **Response** — a sequence of Invocation responses, an optional
  `createdIds` map, and a `sessionState` token.

These depend on Layer 1 primitives (MethodCallId, CreationId, Id,
JmapState, JsonNode) and on `methods_enum` (`MethodName`, `RefPath`).
Request construction logic (builders, call ID generation) is a Layer 3
concern. Serialisation format is a Layer 2 concern.

**Sealed Invocation (Pattern A).** `Invocation`'s identity-bearing
fields `rawName: string` and `rawMethodCallId: string` are
module-private; only `arguments: JsonNode` is public. Two construction
paths are exposed:

- Typed (used by builders and library code): `initInvocation(name:
  MethodName, arguments: JsonNode, methodCallId: MethodCallId)`. Total
  function; the type system rules out illegal names at compile time.
- Wire-boundary (used by Layer 2 serde): `parseInvocation(rawName:
  string, arguments: JsonNode, methodCallId: MethodCallId): Result[Invocation,
  ValidationError]`. Lenient — accepts any non-empty string and preserves
  it verbatim. Unknown method names parse to `mnUnknown`.

Public accessors: `methodCallId`, `name` (returns typed `MethodName`),
`rawName` (verbatim wire string for round-trip).

**Partially sealed ResultReference.** The `resultOf: MethodCallId` field
is public because consumers need it for back-reference inspection;
`rawName` and `rawPath` are module-private. Construction paths:

- Typed: `initResultReference(resultOf: MethodCallId, name: MethodName,
  path: RefPath)`. Stores `$name` and `$path` verbatim.
- Wire-boundary: `parseResultReference(resultOf: MethodCallId, name:
  string, path: string): Result[ResultReference, ValidationError]`.

Accessors: `name` (typed `MethodName`, `mnUnknown` for forward-compat
wire names), `path` (typed `RefPath`, falling back to `rpIds` for
unknown paths — never fires in practice because the server only echoes
paths the client sent), and verbatim `rawName` / `rawPath`.

**Request and Response** are flat objects with public fields
(`using: seq[string]`, `methodCalls: seq[Invocation]`,
`createdIds: Opt[Table[CreationId, Id]]` on Request;
`methodResponses: seq[Invocation]`, `createdIds: Opt[Table[CreationId, Id]]`,
`sessionState: JmapState` on Response).

### 1.5 Generic Method Framework Types

The RFC §5 defines several data types that are generic across all
entity types. These are pure data structures with no upward
dependencies.

#### 1.5.1 Filter and FilterOperator

The RFC §5.5 defines a recursive filter structure. The Core RFC defines
the framework; entity-specific condition types plug in later.

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
Equivalent to Haskell's `data Filter c = Condition c | Operator Op
[Filter c]`. `seq[Filter[C]]` provides heap-allocated indirection for
the recursion without `ref`. Compiles under `--mm:arc` + `strictFuncs` +
`strictCaseObjects` + `strictDefs`. `C` is resolved from the entity
type at the builder boundary (Decision 3.7B). Smart constructors:
`filterCondition[C]` and `filterOperator[C]`.

#### 1.5.2 Comparator

The RFC §5.5 defines the sort order for `/query` requests.

```nim
PropertyName = distinct string  ## Non-empty; validated at construction time

Comparator = object
  rawProperty: string                  ## module-private; validated PropertyName
  isAscending: bool                    ## true = ascending (RFC default)
  collation: Opt[CollationAlgorithm]   ## typed RFC 4790/5051 algorithm

func property(c: Comparator): PropertyName  ## typed accessor
func parseComparator(property: PropertyName,
                     isAscending: bool = true,
                     collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm)
                    ): Comparator
```

`property` is stored internally as `string` (Pattern A) so
`seq[Comparator]` works in `Opt`/`Result` containers without triggering
`UnsafeSetLen`. The module-private field blocks direct object
construction from outside `framework.nim`, making `parseComparator` the
only construction path. The `property*()` accessor returns a validated
`PropertyName` view.

The `collation` field is typed (`CollationAlgorithm` from §1.5.7, not
`string`), so an unparseable algorithm identifier fails at construction
time rather than being deferred to the server.

`isAscending` defaults to `true` per RFC §5.5 (default applied at parse
time in Layer 2). `PropertyName` enforces non-emptiness but not
entity-specific validity; the valid property set varies per entity type
and the RFC permits additional Comparator properties per entity (§5.5),
so a single distinct type at Layer 1 cannot capture entity-specific
constraints. Entity-specific validation is performed by typed sort
builders in the mail layer, which restrict the property names accepted
for each entity (e.g. `EmailComparator`, `EmailSubmissionComparator`).

`PropertyName` is defined in `src/jmap_client/framework.nim`. Borrowed
operations: `==`, `$`, `hash`, `len` (via `defineStringDistinctOps`).

#### 1.5.3 Per-entity update algebras (no PatchObject in Core)

Layer 1 does not define a generic `PatchObject` type. RFC 8620 §5.3's
patch shape is realised on the wire only; in the Nim API, each entity
that supports `/set` provides a closed sum-type ADT of legitimate patch
operations. Each algebra:

- Names every patch operation as a variant — e.g. `EmailUpdate` has
  `euAddKeyword`, `euRemoveKeyword`, `euSetKeywords`, `euAddToMailbox`,
  `euRemoveFromMailbox`, `euSetMailboxIds`, with payload fields per
  variant.
- Provides smart constructors (`addKeyword`, `setMailboxIds`, …) that
  validate before producing the variant.
- Aggregates into a non-empty whole-container update value
  (`NonEmptyEmailUpdates`, `NonEmptyMailboxUpdates`,
  `NonEmptyIdentityUpdates`, `NonEmptyEmailSubmissionUpdates`) so empty
  `update` maps cannot be produced. The whole container additionally
  enforces the RFC 8620 §5.3 "no full-replace alongside sub-path write
  under the same parent" invariant via set-algebra detection (see
  `mail/email_update.nim`).
- Serialises via `toJson` to the wire patch shape
  (`{"path/to/field": value}` pairs); never round-trips back to a typed
  update from JSON, since the client always knows the patch it built.

The closed-sum-type approach catches errors a generic patch-table
cannot: opposing operations on the same path, dotted-path conflicts,
forbidden field combinations. The wire-side JSON Pointer is purely a
serialisation concern.

#### 1.5.4 AddedItem

An element of the `added` array in a `/queryChanges` response (RFC §5.6).
Records that an item was added to the query results at a specific
position.

```nim
AddedItem = object
  rawId: string        ## module-private; validated Id
  index: UnsignedInt

func id(item: AddedItem): Id        ## typed accessor
func initAddedItem(id: Id, index: UnsignedInt): AddedItem
```

Pattern A: `id` stored internally as `string` to allow `seq[AddedItem]`
in `Opt`/`Result` containers without triggering `UnsafeSetLen`. The
module-private `rawId` field blocks direct object construction;
`initAddedItem` is the only construction path. The `id*()` accessor
returns a validated `Id` view.

#### 1.5.5 QueryParams

The RFC §5.5 `/query` request takes four window parameters and a
`calculateTotal` flag. They are bundled into a single Layer 1 aggregate
so that builder signatures stay readable and so the defaults are
written once:

```nim
QueryParams = object
  position: JmapInt          ## default: 0
  anchor: Opt[Id]            ## default: absent
  anchorOffset: JmapInt      ## default: 0
  limit: Opt[UnsignedInt]    ## default: absent
  calculateTotal: bool       ## default: false
```

Public fields, value type, default constructible. `QueryParams()` yields
the RFC defaults; partial overrides use named-field syntax. Used by
`addQuery[T, C, SortT]` and consumed by `assembleQueryArgs` in
`methods.nim`. `/queryChanges` does not use `QueryParams` because
RFC §5.6 defines no window fields for `/queryChanges` — the relevant
arguments (`maxChanges`, `upToId`, `calculateTotal`) are passed
directly.

#### 1.5.6 NonEmptySeq[T]

Generic non-empty-sequence newtype used wherever the RFC mandates
"at least one" semantics (RFC 5321 RCPT lists, identity creation, …).
Defined in `primitives.nim`.

```nim
NonEmptySeq[T] = distinct seq[T]

func parseNonEmptySeq[T](s: seq[T]): Result[NonEmptySeq[T], ValidationError]
func head[T](a: NonEmptySeq[T]): lent T
template defineNonEmptySeqOps(T: typedesc)  ## == $ hash len [] contains items pairs
```

The smart constructor is the only public path; the discriminator
"non-empty" cannot be invalidated through the public API.

#### 1.5.7 CollationAlgorithm (collation.nim)

RFC 8620 §5.5 references RFC 4790 / RFC 5051 collation algorithms by
URI. Layer 1 represents them as a sealed case object so that the four
IANA-registered algorithms get exhaustive matching while vendor
extensions are preserved:

```nim
CollationAlgorithmKind = enum
  caAsciiCasemap     = "i;ascii-casemap"   ## RFC 4790 + RFC 6855
  caOctet            = "i;octet"            ## RFC 4790
  caAsciiNumeric     = "i;ascii-numeric"    ## RFC 4790
  caUnicodeCasemap   = "i;unicode-casemap"  ## RFC 5051
  caOther                                   ## vendor extension

CollationAlgorithm = object
  case rawKind: CollationAlgorithmKind
  of caOther: rawIdentifier: string         ## module-private
  else: discard

func parseCollationAlgorithm(raw: string): Result[CollationAlgorithm, ValidationError]
func kind(c: CollationAlgorithm): CollationAlgorithmKind
func identifier(c: CollationAlgorithm): string
```

Constants for the four IANA algorithms (`CollationAsciiCasemap`,
`CollationOctet`, `CollationAsciiNumeric`, `CollationUnicodeCasemap`)
are public values; user code typically references those rather than
constructing the value directly.

`Comparator.collation` is `Opt[CollationAlgorithm]`; absent means
"server-defined default". `CoreCapabilities.collationAlgorithms` is
`HashSet[CollationAlgorithm]` and `hasCollation(caps, algorithm)`
checks server support before issuing a sort that requires a specific
collation.

#### 1.5.8 MethodName, MethodEntity, RefPath (methods_enum.nim)

Method names, entity tags, and result-reference paths live in a Layer 1
enum module so that `Invocation.name`, `ResultReference.path`, and the
entity-registration templates can use exhaustive matching without
round-tripping through the wire format.

```nim
MethodName = enum
  mnUnknown
  mnCoreEcho                = "Core/echo"
  mnThreadGet               = "Thread/get"
  mnThreadChanges           = "Thread/changes"
  mnIdentityGet             = "Identity/get"
  mnIdentityChanges         = "Identity/changes"
  mnIdentitySet             = "Identity/set"
  mnMailboxGet              = "Mailbox/get"
  mnMailboxChanges          = "Mailbox/changes"
  mnMailboxSet              = "Mailbox/set"
  mnMailboxQuery            = "Mailbox/query"
  mnMailboxQueryChanges     = "Mailbox/queryChanges"
  mnEmailGet                = "Email/get"
  mnEmailChanges            = "Email/changes"
  mnEmailSet                = "Email/set"
  mnEmailQuery              = "Email/query"
  mnEmailQueryChanges       = "Email/queryChanges"
  mnEmailCopy               = "Email/copy"
  mnEmailParse              = "Email/parse"
  mnEmailImport             = "Email/import"
  mnVacationResponseGet     = "VacationResponse/get"
  mnVacationResponseSet     = "VacationResponse/set"
  mnEmailSubmissionGet      = "EmailSubmission/get"
  mnEmailSubmissionChanges  = "EmailSubmission/changes"
  mnEmailSubmissionSet      = "EmailSubmission/set"
  mnEmailSubmissionQuery    = "EmailSubmission/query"
  mnEmailSubmissionQueryChanges = "EmailSubmission/queryChanges"
  mnSearchSnippetGet        = "SearchSnippet/get"

MethodEntity = enum
  meCore, meThread, meIdentity, meMailbox, meEmail,
  meVacationResponse, meSearchSnippet, meEmailSubmission, meTest

RefPath = enum
  rpIds                = "/ids"
  rpListIds            = "/list/*/id"
  rpAddedIds           = "/added/*/id"
  rpCreated            = "/created"
  rpUpdated            = "/updated"
  rpUpdatedProperties  = "/updatedProperties"
  rpListThreadId       = "/list/*/threadId"
  rpListEmailIds       = "/list/*/emailIds"

func parseMethodName(raw: string): MethodName  ## total; mnUnknown for vendor methods
```

`mnUnknown` has no backing string — `$mnUnknown` falls back to the
symbol name, but the variant is never emitted because only server
replies populate it (verbatim wire string is preserved on the
Invocation's `rawName` field for lossless round-trip). `meTest` is a
sentinel for test-only fixture entities; production dispatch never
observes it.

`RefPath` covers the eight standard paths used by reference construction
in the builder. Vendor reference paths can still be expressed because
Layer 2's lenient `parseResultReference` preserves arbitrary path
strings verbatim in `rawPath`.

### 1.6 Error Architecture

The library handles errors at four granularities, which compose into
three lifecycle railways plus one data-level Result pattern. The first
granularity is a library concern; the remaining three are defined by
the RFC (§3.6):

0. **Construction errors** — invalid values rejected by smart
   constructors (`ValidationError`). These fire at value-construction
   time, before any request is built. The construction-time railway:
   `Result[T, ValidationError]`.
1. **Transport/request errors** — network failures, TLS errors, timeouts
   (not in RFC, but reality), plus HTTP 4xx/5xx with RFC 7807 problem
   details (`urn:ietf:params:jmap:error:unknownCapability`, `notJSON`,
   `notRequest`, `limit`). Both become `ClientError` on the outer
   railway.
2. **Method-level errors** — invocation errors (`serverFail`,
   `unknownMethod`, `invalidArguments`, `forbidden`, `accountNotFound`,
   etc.).
3. **Set-item outcomes** — per-object results within a successful `/set`
   response (`SetError` with type like `forbidden`, `overQuota`,
   `invalidProperties`, etc.). These are data within a successful method
   response, not a lifecycle failure — the method invocation succeeded,
   but individual items within it carry their own `Result[T, SetError]`
   outcomes.

#### Option 1.6A: Flat error enum

Single `JmapErrorKind` enum covering all error types across all levels.

- **Pros:** Simple. One error type everywhere.
- **Cons:**
  - Loses the level distinction. A transport timeout and a
    `stateMismatch` method error are fundamentally different — the first
    means the request may or may not have been processed; the second
    means it definitely was not.
  - Callers cannot distinguish error categories without inspecting the
    kind.
  - Mixing transport/protocol/method concerns in one enum violates the
    principle of precise types.

#### Option 1.6B: Layered error types with a top-level sum

Separate types for each level, unified under a top-level `JmapError`
variant.

- **Pros:**
  - Precise. Each level carries appropriate context.
  - Matches the RFC's own layering.
- **Cons:**
  - Conflates method errors with transport failures in the same railway.
  - A JMAP request with 3 method calls can return 2 successes and 1
    method error in the same HTTP 200 response. If method errors are on
    the error rail of the outer `Result`, the 2 successes are lost.

#### Option 1.6C: Three-track railway

```
Track 0 (construction): Can this value be constructed at all?
  Success: Well-typed value (Id, AccountId, Keyword, EmailUpdate, etc.)
  Failure: ValidationError

Track 1 (outer): Did we get a valid JMAP response at all?
  Success: Response envelope with method responses
  Failure: ClientError (TransportError | RequestError)

Track 2 (inner, per-invocation): Did this method call succeed?
  Success: Typed method response
  Failure: MethodError
```

`Result[T, ValidationError]` for the construction railway (Layer 1
smart constructors). `JmapResult[T] = Result[T, ClientError]` for the
outer railway. `Result[MethodResponse, MethodError]` per invocation in
the response.

Per-item Result pattern (data-level, within Track 2 success):

```
Result[T, SetError] per create/update/destroy item.
Not a lifecycle phase — the method invocation succeeded. Individual
items within the SetResponse carry their own Result[T, SetError]
outcomes in parallel.
```

- **Pros:**
  - Matches JMAP's actual semantics. A single response legitimately
    contains both successes and failures.
  - Clean ROP composition. Outer railway for transport/request failures.
    Inner railway for per-method outcomes.
  - Set errors are *response data*, not *railway errors* — the method
    invocation succeeded; individual items within it carry their own
    outcomes. Method errors are the Track 2 error rail.
- **Cons:**
  - Consumers must check two places — the `Result` wrapper and the
    per-invocation results inside the response.
  - More complex mental model than a flat error type.

#### Decision: 1.6C

The three-track railway is the only option consistent with ROP and
JMAP's semantics. Each track corresponds to a distinct temporal phase
with different failure modes: construction (can this value exist?),
transport (did the HTTP round-trip succeed?), and per-invocation (did
this method call succeed?). Within a successful per-invocation result,
SetResponse items carry a data-level `Result[T, SetError]` per item — a
structural use of the Result type for parallel outcomes, not a fourth
lifecycle phase. A flat error type forces handling transport errors and
method errors in the same `case` statement, but these require
fundamentally different recovery actions (retry vs. resync vs. report).
And conflating method errors with transport failures in a single
`Result` loses successful results from a partially-failed multi-method
request.

`JmapResult[T] = Result[T, ClientError]` is defined in `types.nim` (the
Layer 1 re-export hub), so importing the hub brings the outer railway
alias into scope.

### 1.7 Error Type Granularity

For each error level, how to represent the specific error type.

#### Option 1.7A: Full enum per level

Every RFC-specified error type as an enum variant, plus an `unknown`
catch-all.

- **Pros:** Exhaustive matching. Compiler warns on unhandled variants.
- **Cons:** The list grows when adding RFC 8621. Servers may return
  implementation-specific errors.

#### Option 1.7B: String type + known constants

Error type as a string, with constants for known values.

- **Pros:** Extensible without recompilation. Matches wire format.
- **Cons:** No exhaustive matching. String comparison is fragile.

#### Option 1.7C: Enum with string backing + lossless round-trip

Enum for known types with a fallback variant. Raw string always
preserved alongside the parsed enum.

```nim
MethodErrorType = enum
  metServerUnavailable = "serverUnavailable"
  metServerFail = "serverFail"
  ...
  metUnknown

MethodError = object
  errorType: MethodErrorType  # module-private; derived from rawType
  rawType: string             # always populated, even for known types
  description: Opt[string]
  extras: Opt[JsonNode]       # lossless preservation of non-standard fields

func errorType(me: MethodError): MethodErrorType  ## typed accessor
func methodError(rawType: string, ...): MethodError  ## auto-parses rawType
```

`errorType` is module-private — always derived from `rawType` via
`parseMethodErrorType`. This seals the consistency invariant: `errorType`
and `rawType` cannot diverge. `rawType` is always populated.
Serialisation is lossless — round-trip through `MethodError` preserves
the original string.

- **Pros:**
  - Exhaustive matching for known types. Fallback for unknown.
  - Lossless round-trip. Preserves the original string.
  - Total parsing — the deserialiser always succeeds (unknown types map
    to `metUnknown` with the raw string preserved).
- **Cons:** Slightly redundant storage (the enum and the string represent
  the same information for known types). Negligible cost.

#### Decision: 1.7C

Enum with string backing and lossless round-trip. The same pattern
applies to `RequestErrorType` (sealed-derived `errorType`) and to
`SetErrorType`, but `SetError` exposes `errorType` publicly because Nim's
`strictCaseObjects` flow analysis requires direct discriminator access at
external `case se.errorType of setX: …` sites; the case-object
construction rule still prevents payload-bearing variants from being
constructed without their payloads. The lossless principle extends
beyond `rawType`: an `extras: Opt[JsonNode]` field on `RequestError`,
`MethodError`, and `SetError` preserves any additional server-sent fields
not modelled as typed fields. No information is silently dropped during
parsing.

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

Constructors: `transportError(kind, message)` for the three discardable
kinds; `httpStatusError(status, message)` builds the `tekHttpStatus`
variant.

#### RequestError (RFC 7807 Problem Details)

```nim
RequestErrorType = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

RequestError = object
  errorType: RequestErrorType ## module-private; derived from rawType
  rawType*: string            ## always populated — lossless round-trip
  status*: Opt[int]
  title*: Opt[string]
  detail*: Opt[string]
  limit*: Opt[string]
  extras*: Opt[JsonNode]      ## non-standard fields, lossless preservation

func errorType*(re: RequestError): RequestErrorType  ## typed accessor
func message*(re: RequestError): string              ## detail > title > rawType
func requestError(rawType: string, ...): RequestError  ## auto-parses rawType
```

`message` is an accessor `func`, not a stored field — it cascades
`detail` → `title` → `rawType`. `errorType` is module-private; always
derived from `rawType` via `parseRequestErrorType`, sealing the
consistency invariant.

#### ClientError (outer railway error type)

```nim
ClientErrorKind = enum
  cekTransport, cekRequest

ClientError = object
  case kind: ClientErrorKind
  of cekTransport: transport: TransportError
  of cekRequest: request: RequestError

func clientError(transport: TransportError): ClientError
func clientError(request: RequestError): ClientError
func message(err: ClientError): string  ## extracts human-readable message
```

`message` dispatches on the variant kind — for transport errors it
returns `transport.message`; for request errors it cascades through
`RequestError.message`.

`validationToClientError(ve)` and `validationToClientErrorCtx(ve, context)`
project a Layer 1 `ValidationError` into a `ClientError` so the L4 send
path can surface pre-flight failures on the same railway as transport
errors.

#### MethodError (inner railway error type)

```nim
MethodError = object
  errorType: MethodErrorType  ## module-private; derived from rawType
  rawType*: string            ## always populated — lossless round-trip
  description*: Opt[string]
  extras*: Opt[JsonNode]      ## lossless preservation of non-standard fields

func errorType*(me: MethodError): MethodErrorType  ## typed accessor
func methodError(rawType: string, ...): MethodError ## auto-parses rawType
```

`MethodError` is intentionally flat — not a case object. RFC 8620
specifies only `description` as an optional per-type field on method
errors. No variant-specific fields are RFC-mandated. `errorType` is
module-private — always derived from `rawType` via `parseMethodErrorType`.

`extras` preserves any additional fields the server sends that are not
modelled as typed fields (e.g., some servers send `arguments` on
`invalidArguments`). It is a preservation mechanism for debugging and
forward-compatibility; the typed fields (`errorType`, `rawType`,
`description`) remain the primary access path.

`MethodErrorType` enumerates the RFC 8620 method-error names plus
`metUnknown`:

```
metServerUnavailable, metServerFail, metServerPartialFail,
metUnknownMethod, metInvalidArguments, metInvalidResultReference,
metForbidden, metAccountNotFound, metAccountNotSupportedByMethod,
metAccountReadOnly, metAnchorNotFound, metUnsupportedSort,
metUnsupportedFilter, metCannotCalculateChanges, metTooManyChanges,
metRequestTooLarge, metStateMismatch, metFromAccountNotFound,
metFromAccountNotSupportedByMethod, metUnknown
```

#### 1.8.1 SetError (per-item error within /set responses)

`SetError` is a case object because both RFC 8620 §5.3 and RFC 8621
mandate variant-specific fields on multiple error types. The variant
payload set covers the full RFC 8621 mail surface; the underlying
"named-variant + open-world fallback + extras" pattern is unchanged
from the simpler core types.

Variant-bearing types and their payload obligations:

- `setInvalidProperties` carries `properties: seq[string]` (RFC 8620 §5.3).
- `setAlreadyExists` carries `existingId: Id` (RFC 8620 §5.4, for /copy).
- `setBlobNotFound` carries `notFound: seq[BlobId]` (RFC 8621 §4.6 — blob references).
- `setInvalidEmail` carries `invalidEmailPropertyNames: seq[string]` (RFC 8621 §7.5).
- `setTooManyRecipients` carries `maxRecipientCount: UnsignedInt` (RFC 8621 §7.5).
- `setInvalidRecipients` carries `invalidRecipients: seq[string]` (RFC 8621 §7.5).
- `setTooLarge` carries `maxSizeOctets: Opt[UnsignedInt]` (RFC 8621 §7.5 SHOULD).

```nim
SetErrorType = enum
  # RFC 8620 §5.3 / §5.4 — core
  setForbidden            = "forbidden"
  setOverQuota            = "overQuota"
  setTooLarge             = "tooLarge"
  setRateLimit            = "rateLimit"
  setNotFound             = "notFound"
  setInvalidPatch         = "invalidPatch"
  setWillDestroy          = "willDestroy"
  setInvalidProperties    = "invalidProperties"
  setAlreadyExists        = "alreadyExists"
  setSingleton            = "singleton"
  # RFC 8621 §2.3 — Mailbox/set
  setMailboxHasChild      = "mailboxHasChild"
  setMailboxHasEmail      = "mailboxHasEmail"
  # RFC 8621 §4.6 — Email/set
  setBlobNotFound         = "blobNotFound"
  setTooManyKeywords      = "tooManyKeywords"
  setTooManyMailboxes     = "tooManyMailboxes"
  # RFC 8621 §7.5 — EmailSubmission/set (and §6 Identity/set)
  setInvalidEmail         = "invalidEmail"
  setTooManyRecipients    = "tooManyRecipients"
  setNoRecipients         = "noRecipients"
  setInvalidRecipients    = "invalidRecipients"
  setForbiddenMailFrom    = "forbiddenMailFrom"
  setForbiddenFrom        = "forbiddenFrom"
  setForbiddenToSend      = "forbiddenToSend"
  setCannotUnsend         = "cannotUnsend"
  # Open-world fallback
  setUnknown

SetError = object
  rawType*: string
  description*: Opt[string]
  extras*: Opt[JsonNode]
  case errorType*: SetErrorType   ## public discriminator (see §1.7)
  of setInvalidProperties:    properties*: seq[string]
  of setAlreadyExists:        existingId*: Id
  of setBlobNotFound:         notFound*: seq[BlobId]
  of setInvalidEmail:         invalidEmailPropertyNames*: seq[string]
  of setTooManyRecipients:    maxRecipientCount*: UnsignedInt
  of setInvalidRecipients:    invalidRecipients*: seq[string]
  of setTooLarge:             maxSizeOctets*: Opt[UnsignedInt]
  else: discard
```

`"forbiddenFrom"` is shared between `Identity/set` (RFC 8621 §6) and
`EmailSubmission/set` (§7.5); a single enum variant `setForbiddenFrom`
covers both — the calling method determines which SHOULD-semantic
applies.

Construction goes through one of seven variant-specific helpers
(`setErrorInvalidProperties`, `setErrorAlreadyExists`,
`setErrorBlobNotFound`, `setErrorInvalidEmail`,
`setErrorTooManyRecipients`, `setErrorInvalidRecipients`,
`setErrorTooLarge`) plus the generic `setError(rawType, …)` for
non-payload variants. The generic constructor defensively maps
payload-bearing `rawType`s with no payload data to `setUnknown` so the
case-object invariant cannot be violated. Internal field names
`invalidEmailPropertyNames` / `maxRecipientCount` / `maxSizeOctets`
deliberately avoid colliding with the mail-layer accessor names
`invalidEmailProperties` / `maxRecipients` / `maxSize`.

The mail layer adds typed accessors over `SetError` in
`mail/mail_errors.nim` (`notFoundBlobIds`, `maxSize`, `maxRecipients`,
`invalidEmailProperties`, `invalidRecipientAddresses`) so callers do
not need to repeat the case-discrimination at every site.

---

## Layer 2: Serialisation

### 2.1 JSON Library

#### Option 2.1A: `std/json` with manual serialisation/deserialisation

Use the built-in `JsonNode` tree. Write `toJson`/`fromJson` procs
manually for each type.

- **Pros:**
  - Zero dependencies.
  - Full control over camelCase naming, `#` reference handling, every
    serialisation quirk.
  - Compatible with `raises: []` given a boundary catch. `std/json`
    raises `JsonParsingError` (from `parseJson`), `KeyError` (from
    `node[key]`), and `JsonKindError` (from `to[T]`) — all
    `CatchableError` subtypes. The boundary `proc` catches
    `CatchableError` and converts to `Result`. Within `fromJson`
    functions, raises-free accessors are used: `node{key}` (returns
    `nil` on missing key), `getStr`, `getInt`, `getFloat`, `getBool`
    (return defaults). These never raise.
  - Every `fromJson` is a validating parser that either produces a
    well-typed value or a structured error. This is the "parse, don't
    validate" principle.
  - No dependency risk. Third-party libraries may not work with
    `--mm:arc` + `strictFuncs` + `strictNotNil` + `raises: []`.
- **Cons:**
  - Verbose. Every type needs a `toJson` and `fromJson`.
- **Mitigation:** Most follow one of three patterns: simple object
  (field-by-field with camelCase keys, template-able); case object
  (dispatch on discriminator); special format (invocations as 3-element
  JSON arrays, `#`-prefixed reference keys, entity-specific update
  algebras emitted as JSON Pointer–keyed patch maps). A helper template
  handles the first pattern. Manual for the special types.

#### Option 2.1B: `jsony` or `nim-serialization`

Third-party library with hooks for customisation.

- **Pros:** Less boilerplate. Good hook support for custom field names.
- **Cons:**
  - New dependency. Must verify compatibility with the strict compiler
    configuration (`--mm:arc`, `strictFuncs`, `strictNotNil`,
    `raises: []`).
  - `jsony` uses exceptions internally, which conflicts with
    `raises: []`.
  - Implicit parsing means validation cannot be injected at the field
    level without hooks.
  - Less control over the total-parsing guarantee.

#### Option 2.1C: `std/json` + code generation macro

Macro generates `toJson`/`fromJson` from type definitions, handling
camelCase automatically. Manual overrides for special types.

- **Pros:** Less boilerplate than 2.1A, no external dependencies.
- **Cons:** Macros add compile-time complexity. Debugging
  macro-generated code is harder. Must work with strict settings.

#### Decision: 2.1A

`std/json` with manual serialisation. The types with tricky
serialisation (invocations as JSON arrays, `#`-prefixed reference
fields, JSON-Pointer-keyed update patches, filter operators with
recursive structure, three-state `Opt[Opt[T]]` filter fields) require
manual serialisation regardless. The remaining types are
straightforward. Starting manual means understanding every detail of
the wire format, which matters when debugging against a real server.

### 2.2 camelCase Handling

#### Option 2.2A: camelCase in Nim source

Since Nim treats `accountId` and `account_id` as the same identifier,
write `accountId` in type definitions. The field name in Nim is the
field name on the wire. Zero conversion.

- **Pros:** Zero conversion logic. What is written is what goes on the
  wire. `nph` preserves the casing written. `--styleCheck:error`
  requires consistency (use the same casing everywhere), not a specific
  convention.
- **Cons:** Some Nim style guides prefer snake_case. Needs verification
  that `nph` + `--styleCheck:error` cooperate.

#### Option 2.2B: snake_case in Nim, convert at serialisation boundary

Write `account_id` in Nim. Convert to `accountId` during JSON
serialisation.

- **Pros:** Nim-idiomatic naming.
- **Cons:** Conversion logic in every ser/de proc. Unnecessary
  complexity given Nim's style insensitivity.

#### Decision: 2.2A

camelCase in source. Zero conversion. Leverages Nim's style
insensitivity.

### 2.3 Result Reference Serialisation

`Referencable[T]` (Decision 1.3B, §1.3) requires custom serialisation.
The wire format uses the JSON key name as the discriminator:

- `rkDirect`: normal key with the value serialised as `T`.
  `{ "ids": ["id1", "id2"] }`
- `rkReference`: key prefixed with `#`, value is a `ResultReference`
  object.
  `{ "#ids": { "resultOf": "c0", "name": "Foo/query", "path": "/ids" } }`

The same logical field appears under two different JSON keys.
`serde_envelope.nim` exposes two named entry points for this dispatch:

- `referencableKey[T](fieldName: string, r: Referencable[T]): string` —
  emits `fieldName` for `rkDirect`, `"#" & fieldName` for `rkReference`.
- `fromJsonField[T](fieldName: string, node: JsonNode, fromDirect, path)` —
  checks `"#fieldName"` first, then `fieldName`; rejects co-presence
  with an `svkConflictingFields` violation citing RFC 8620 §3.7;
  surfaces missing-both as an `svkMissingField` with composite name
  `"fieldName or #fieldName"`.

There are only ~4 referenceable fields across the standard methods; the
entry points are reused by the per-method `toJson` / `fromJson` blocks
in `methods.nim`.

### 2.4 SerdeViolation: structured error type for the parse railway

`fromJson` functions return `Result[T, SerdeViolation]`. The two-error
split (`ValidationError` for construction, `SerdeViolation` for
parsing) reflects the difference between "is this value well-formed?"
and "is this JSON parseable into a well-formed value, and where did it
fail?". `SerdeViolation` carries information `ValidationError` cannot
express — JSON Pointer paths to the offending node, expected vs. actual
`JsonNodeKind`, conflicting-field rules, depth-exceeded violations.

```nim
JsonPathElementKind = enum jpeKey, jpeIndex
JsonPathElement = object
  case kind: JsonPathElementKind
  of jpeKey:   key: string
  of jpeIndex: idx: int

JsonPath = distinct seq[JsonPathElement]

SerdeViolationKind = enum
  svkWrongKind, svkNilNode, svkMissingField, svkEmptyRequired,
  svkArrayLength, svkFieldParserFailed, svkConflictingFields,
  svkEnumNotRecognised, svkDepthExceeded

SerdeViolation = object
  path: JsonPath
  case kind: SerdeViolationKind
  of svkWrongKind:           expectedKind, actualKind: JsonNodeKind
  of svkNilNode:             expectedKindForNil: JsonNodeKind
  of svkMissingField:        missingFieldName: string
  of svkEmptyRequired:       emptyFieldLabel: string
  of svkArrayLength:         expectedLen, actualLen: int
  of svkFieldParserFailed:   inner: ValidationError
  of svkConflictingFields:   conflictKeyA, conflictKeyB, conflictRule: string
  of svkEnumNotRecognised:   enumTypeLabel, rawValue: string
  of svkDepthExceeded:       maxDepth: int

func toValidationError(v: SerdeViolation, rootType: string): ValidationError
```

`JsonPath` exposes RFC 6901–compliant rendering (`$`, `jsonPointerEscape`,
`/` overloads for key and index extension) so error messages carry the
exact node location (e.g. `"/methodResponses/0/2"`).

Helper `func`s in `serde.nim` build paths, expected-kind violations,
and field accessors that thread paths automatically: `expectKind`,
`fieldOfKind`, `fieldJObject` / `fieldJString` / `fieldJArray` /
`fieldJBool` / `fieldJInt`, `optField`, `optJsonField`, `expectLen`,
`nonEmptyStr`, `wrapInner` (lift a `Result[T, ValidationError]` from a
smart constructor onto the `Result[T, SerdeViolation]` rail with a
`JsonPath`), `collectExtras` (preserve unknown keys for round-trip),
`parseIdArray` / `parseIdArrayField` / `parseOptIdArray` (Id list
variants), `parseKeyedTable`, `collapseNullToEmptySeq`,
`optToJsonOrNull` / `optStringToJsonOrNull` (toJson-side helpers).

Distinct-type ser/de boilerplate is eliminated by four templates:
`defineDistinctStringToJson`, `defineDistinctStringFromJson`,
`defineDistinctIntToJson`, `defineDistinctIntFromJson`. They are
instantiated on `Id`, `AccountId`, `JmapState`, `MethodCallId`,
`CreationId`, `BlobId`, `PropertyName`, `Date`, `UTCDate` (string
variants) and `UnsignedInt`, `JmapInt` (int variants). `UriTemplate`
and `MaxChanges` use bespoke ser/de pairs.

The translator `toValidationError(v, rootType)` is the canonical
boundary translation. Layer 3's `dispatch.serdeToMethodError(rootType)`
returns a closure that runs the translator with the appropriate root
type name and packs the resulting `ValidationError` into a
`serverFail` `MethodError` whose `extras` carry `typeName` and
`value` — so the JSON Pointer path, the expected kind, and the failing
field are all preserved across the railway bridge into Track 2
(per-invocation).

`MaxFilterDepth = 128` (in `serde_framework.nim`) caps `Filter[C]`
recursion at parse time and produces an `svkDepthExceeded` violation,
defending against pathological server payloads that would exhaust the
stack.

---

## Layer 3: Protocol Logic

This layer covers three logical groups that share the same dependencies
(Layer 1 types + errors, Layer 2 serialisation) and the same dependents
(Layer 4 transport):

1. **Envelope logic** — request building, call ID generation, response
   dispatch.
2. **Method framework** — entity type registration, associated type
   resolution, method-specific logic.
3. **Result reference construction** — builder-produced references,
   path constants.

Envelope data types (Invocation, Request, Response) are defined in
Layer 1 (§1.4). Generic method framework types (Filter[C], Comparator,
AddedItem, QueryParams) are defined in Layer 1 (§1.5). This layer
covers the logic that operates on those types.

### 3.1 Invocation Format

Invocations are serialised as 3-element JSON arrays, not JSON objects.
This is handled by custom serialisation in Layer 2.

### 3.2 Method Call ID Generation

#### Option 3.2A: Auto-incrementing counter

`"c0"`, `"c1"`, `"c2"`.

- **Pros:** Simple, deterministic, unique within a request.
- **Cons:** None. IDs are only meaningful within a single
  request/response pair.

#### Option 3.2B: Method-name-based descriptive IDs

`"mailbox-query-0"`, `"email-get-1"`.

- **Pros:** Easier debugging — visible which call produced which
  response.
- **Cons:** More complex generation. Needs uniqueness suffix for
  repeated methods.

#### Decision: 3.2A

Internal plumbing. No safety implications. Keep simple. The builder
maintains a monotonic counter (`nextCallId`) and emits
`"c" & $nextCallId`.

### 3.3 Request Builder Design

#### Option 3.3A: Direct construction

User builds `Request` objects by constructing `Invocation` objects
manually.

- **Pros:** No builder infrastructure.
- **Cons:** Verbose. User must manually track call IDs, construct
  `ResultReference` objects, manage the `using` capability list.
  Error-prone.

#### Option 3.3B: Builder with method-specific sub-builders

Builder accumulates method calls. Each method call returns a
sub-builder for that method's arguments. Call IDs generated
automatically. `using` populated automatically based on which methods
are called.

- **Pros:**
  - Excellent ergonomics.
  - Result references are easy to use — sub-builders return references.
  - Capability management is automatic.
  - Proven pattern from the Rust implementation.
- **Cons:**
  - Substantial infrastructure.

#### Option 3.3C: Builder with generic method calls

One generic `call` proc instead of method-specific sub-builders.

- **Pros:** Less infrastructure than 3.3B.
- **Cons:** Less discoverable. Requires knowing method type names.

#### Decision: 3.3B (D3.5: pure tuple-returning add*)

The builder is a **value type** with private fields (`nextCallId: int`,
`invocations: seq[Invocation]`, `capabilityUris: seq[string]`),
accumulated by **pure functions returning `(RequestBuilder,
ResponseHandle[T])` tuples**. The shape is dictated by three forces:

1. `mixin` resolution inside non-generic `func` bodies depends on the
   symbol being in scope at the *definition* site, not the *instantiation*
   site. Tuple-returning funcs let the builder stay generic and resolve
   per-entity overloads (`setMethodName(T)`, `filterType(T)`, etc.) at
   the caller's instantiation site.
2. `func` purity (under `{.push raises: [], noSideEffect.}`) is enforced
   across the whole protocol layer. Local accumulation that constructs
   new builder values is provably pure; `var` parameters interact
   awkwardly with `strictFuncs` once any field is a `seq` or `Table`.
3. Result extraction via `mixin fromJson` is uniformly `func` in
   `dispatch.nim`; matching the same rule in `builder.nim` keeps the
   layer uniformly `func`.

```nim
let b0 = initRequestBuilder()
let (b1, idsHandle) = b0.addQuery[Mailbox](accountId)
let (b2, getHandle) = b1.addGet[Mailbox](accountId, ids = idsRef(idsHandle))
let request = b2.build()
```

Each `add*` returns a fresh `RequestBuilder` with the next call ID,
the new invocation appended, and the entity's capability URI added
(deduplicated). `build()` is a pure projection that snapshots the
current state into a `Request`. The builder remains usable after
`build()` for sequential requests against the same accumulator.

`initRequestBuilder()` pre-seeds `urn:ietf:params:jmap:core` in the
`using` array. RFC 8620 §3.2 obliges clients to declare every capability
they use; lenient servers (Stalwart 0.15.5) accept requests with `core`
omitted, but strict servers (Apache James 3.9) reject them with
`unknownMethod`. Pre-declaring core makes the client portable across
both.

The accumulation sequence is order-dependent: calling `addGet` twice
produces call IDs `"c0"` and `"c1"`. Functional core preserved; the
effect boundary is Layer 4's `proc send`. Each step is referentially
transparent.

**Nim limitation:** the type system cannot prevent discarding either
branch of the tuple. Convention is to `let (b, h) = …` at every step.

**Implemented `add*` functions** (all `func`, all pure, all
tuple-returning `(RequestBuilder, ResponseHandle[T])`):

- `addEcho(b, args: JsonNode)` — Core/echo (RFC 8620 §4).
  `ResponseHandle[JsonNode]`. Uses the callback overload of `get` for
  extraction because `JsonNode` has no `fromJson`.
- `addGet[T](b, accountId, ids, properties, extras)` — Foo/get (§5.1).
- `addChanges[T, RespT](b, accountId, sinceState, maxChanges)` —
  Foo/changes (§5.2). `RespT` is the response type, allowing entity
  modules to substitute extended responses (e.g.
  `MailboxChangesResponse`) without altering the wire shape. Does not
  take `extras` — `/changes` has no documented entity-specific extension
  surface.
- `addSet[T, C, U, R](b, accountId, ifInState, create, update, destroy,
  extras)` — Foo/set (§5.3). `T` = entity, `C` = typed create-value,
  `U` = whole-container update algebra, `R` = response type.
- `addCopy[T, CopyItem, R](b, fromAccountId, accountId, create,
  ifFromInState, ifInState, destroyMode, extras)` — Foo/copy (§5.4).
- `addQuery[T, C, SortT](b, accountId, filter, sort, queryParams,
  extras)` — Foo/query (§5.5).
- `addQueryChanges[T, C, SortT](b, accountId, sinceQueryState, filter,
  sort, maxChanges, upToId, calculateTotal, extras)` — Foo/queryChanges
  (§5.6).

**Single-type-parameter template aliases.** Five templates resolve
associated types via `mixin` at the call site, so the common case needs
only the entity type (and the minimal arguments — `accountId`,
`sinceState`, etc. — with no `create`/`update`/`destroy`/`filter`/`extras`
overrides). Calls that need richer arguments invoke the multi-parameter
`func` form directly.

- `addChanges[T]` — resolves `changesResponseType(T)`.
- `addQuery[T]` — resolves `filterType(T)` and uses `Comparator` for
  sort.
- `addQueryChanges[T]` — same resolution as `addQuery[T]`.
- `addSet[T]` — resolves `createType(T)`, `updateType(T)`,
  `setResponseType(T)`.
- `addCopy[T]` — resolves `copyItemType(T)`, `copyResponseType(T)`.

**The `extras` parameter** is `seq[(string, JsonNode)]` and appends
entity-specific extension keys to the args after the standard frame,
with insertion order preserved. This is how `Email/get`'s body-fetch
options, `Mailbox/query`'s `sortAsTree` / `filterAsTree`, and other
RFC 8621 extensions are attached without growing the generic builder
signature. `addChanges` does not take `extras` — `/changes` has no
documented per-entity extension keys.

**Argument-construction helpers** in `builder.nim`:

- `directIds(openArray[Id])` — wraps a sequence into
  `Opt[Referencable[seq[Id]]]` for direct (non-reference) use.
- `initCreates(pairs)` — builds an `Opt[Table[CreationId, JsonNode]]`
  from `(CreationId, JsonNode)` pairs.

There is no `initUpdates` helper — updates are entity-specific typed
algebras (`NonEmptyEmailUpdates`, `NonEmptyMailboxUpdates`,
`NonEmptyIdentityUpdates`, `NonEmptyEmailSubmissionUpdates`),
constructed by their own smart constructors. Generic builders accept
the typed value directly.

### 3.4 Response Processing

#### Option 3.4A: Fully typed response dispatch

Each invocation response deserialised into its concrete type based on
method name. Large enum of all response types.

- **Pros:** Type-safe access.
- **Cons:** Complex deserialisation dispatch. Massive response enum.

#### Option 3.4B: Typed wrapper over raw JSON

Deserialise envelope. Keep individual method responses as `JsonNode`.
Typed extraction on demand.

- **Pros:** Simple deserialisation.
- **Cons:** Runtime type errors if extracting wrong type at wrong index.

#### Option 3.4C: Phantom-typed response handles

The request builder returns typed handles. Each handle carries the
expected response type as a phantom parameter:

```
ResponseHandle[T] = distinct MethodCallId  # wraps the call ID; T is phantom

# Builder returns:
let queryHandle: ResponseHandle[QueryResponse[Mailbox]] = builder.addQuery(...)

# Response extraction is type-safe:
func get[T](resp: Response, handle: ResponseHandle[T]): Result[T, MethodError]
```

- **Pros:**
  - Compile-time proof that the correct response type is extracted.
  - Cannot accidentally extract a `SetResponse` from a `GetResponse`
    position.
  - The inner `Result[T, MethodError]` is the per-invocation railway.
  - No massive type enum. JSON parsed into concrete type inside `get()`.
- **Cons:**
  - The connection between "added a query at position 0" and "position 0
    is a query response" is upheld by the builder, not the type system.
  - If the builder has a bug, the phantom type gives false safety.
- **Gap vs. Haskell:** In Haskell, an indexed type (GADT) would make the
  relationship between request and response provable. In Nim, it is
  upheld by builder implementation.

#### Decision: 3.4C

Phantom-typed handles. Compile-time response type safety via the
phantom parameter. The per-invocation `Result[T, MethodError]` is the
inner railway. Strictly better than untyped extraction, even though Nim
cannot prove the relationship as strongly as Haskell.

**Cross-request safety gap.** `ResponseHandle` carries a call ID (e.g.,
`"c0"`, `"c1"`). Call IDs repeat across requests — every request's
first method call is `"c0"`. A handle from Request A, if used to extract
from Response B, will silently match the wrong invocation (whatever was
at position 0 in Request B). Nim has no type-level mechanism equivalent
to Haskell's `ST` monad to scope handles to a single request/response
pair. Recommendation: process response handles immediately within the
scope where the request was built.

`get[T]` is a Layer 3 `func` (not `proc`) operating on the Layer 1
`Response` type directly. The protocol layer is uniformly
`{.push raises: [], noSideEffect.}`; `mixin fromJson` resolution composes
cleanly with `func` because all `fromJson` overloads in this codebase
carry the same purity pragma. `get[T]` locates the `Invocation` by
matching the `ResponseHandle`'s
call ID, then delegates to the appropriate Layer 2 `fromJson` to produce
the typed result.

Three `get` overloads:

- `get[T](resp, handle: ResponseHandle[T])` — default; resolves
  `fromJson(T, args, path)` at the caller via `mixin`.
- `get[T](resp, handle: ResponseHandle[T], fromArgs)` — callback
  overload accepting an explicit `proc(node: JsonNode):
  Result[T, SerdeViolation] {.noSideEffect, raises: [].}`. Used when `T`
  cannot be resolved by `mixin` alone (e.g. `JsonNode` for `Core/echo`).
- `get[T](resp, h: NameBoundHandle[T])` — extraction filtered by both
  call ID *and* method name, used by RFC 8620 §5.4 compound overloads
  where the same call ID has two siblings (e.g. `Email/copy` followed by
  an implicit `Email/set` destroy).

**Railway bridge.** When `fromJson` returns `err(SerdeViolation)`,
`get[T]` converts it losslessly to `err(MethodError)` via
`serdeToMethodError(rootType)` — a closure factory that builds a
translator for a specific root type name. The violation's JSON Pointer
path, expected/actual kinds, and inner `ValidationError` (if any) are
converted via `toValidationError(v, rootType)` and packed into a
`serverFail` `MethodError` with the shape preserved in `extras`. This
bridges the parse railway into the per-invocation railway so callers
need only handle `Result[T, MethodError]`.

**Compound and chained dispatch (RFC 8620 §5.4).**

`NameBoundHandle[T]` carries `(callId, methodName)` together so that
when one builder call produces two wire invocations sharing the same
call ID — the canonical case being `Email/copy` with
`onSuccessDestroyOriginal: true`, which yields an `Email/copy` *and* an
implicit `Email/set` response — extraction can be filtered by method
name without a separate argument at the call site.

Two paired-handle types model the structural shapes:

```nim
CompoundHandles[A, B] = object
  primary: ResponseHandle[A]       ## e.g. CopyResponse[Email]
  implicit: NameBoundHandle[B]     ## e.g. SetResponse[Email] for the implicit destroy

ChainedHandles[A, B] = object
  first: ResponseHandle[A]         ## e.g. ChangesResponse[Email]
  second: ResponseHandle[B]        ## e.g. GetResponse[Email] using /created back-ref
```

`getBoth[A, B]` extracts both responses into the corresponding
`CompoundResults[A, B]` / `ChainedResults[A, B]`, returning early on
the first error. `registerCompoundMethod(Primary, Implicit)` and
`registerChainableMethod(Primary)` are compile-time templates that
verify entity types support these patterns at definition site.

There are four `getBoth` overloads in total: two in `dispatch.nim`
(over `CompoundHandles` and `ChainedHandles`) and two in
`convenience.nim` (over `QueryGetHandles[T]` and
`ChangesGetHandles[T]`).

**Entity data limitation (D3.6).** The phantom type `T` in
`ResponseHandle[T]` controls which response envelope type is extracted
(e.g., `GetResponse[Mailbox]` vs `SetResponse[Mailbox]`), but entity
data inside the *generic* protocol-level response types remains
`JsonNode`:

- `GetResponse[T].list` is `seq[JsonNode]`.
- `SetResponse[T].updateResults` is
  `Table[Id, Result[Opt[JsonNode], SetError]]` — the per-item outcome
  carries `JsonNode` for typed conversion at the call site.
- `SetResponse[T].createResults` is
  `Table[CreationId, Result[T, SetError]]`. RFC 8621 entity modules
  supply specific `T` (e.g. `EmailCreatedItem`, `IdentityCreatedItem`,
  `MailboxCreatedItem`, `EmailSubmissionCreatedItem` — the
  server-set-subset companions to the entity's full type), parsed
  end-to-end through `mixin fromJson`.
- `CopyResponse[T].createResults` is
  `Table[CreationId, Result[T, SetError]]` — typed because `Foo/copy`
  echoes the created object as the entity's server-set-fields shape.

The mixed pattern reflects the RFC: `/get` returns full entity objects
(typed parsing belongs in extension modules), `/set` update outcomes
echo a property subset that is best parsed at the call site
(`updatedProperties`), and `/copy` plus `/set` create outcomes echo
the server-set fields with a shape tight enough to type at the
protocol layer.

### 3.5 Entity Type Framework

The 6 standard methods are generic over entity type. Each entity type
must define: what properties it has, what filter conditions it
supports, what sort comparators it supports, and what method-specific
arguments it has.

#### Option 3.5A: Concept + overloaded procs (most typeclass-like)

Define a concept that entity types must satisfy. Provide overloads as
"instances".

- **Pros:** Closest to a Haskell typeclass or Rust trait.
- **Cons:**
  - Checked structurally at use site, not at definition site.
  - May interact unpredictably with `strictFuncs` and `raises: []`.
  - No associated types.

#### Option 3.5B: Generic procs + overloaded type-specific procs (no concept)

No concept, just generic procs. Type-specific behaviour via overloading.

- **Pros:** Simpler than concepts. Each entity type just provides
  overloads.
- **Cons:** No compile-time enforcement that all required overloads
  exist.

#### Option 3.5C: Template-generated concrete types

A macro/template stamps out concrete types per entity.

- **Pros:** No generics complexity. Each entity gets concrete types.
- **Cons:** Code generation means indirection — harder to read, debug,
  navigate.

#### Decision: 3.5B — plain overloaded funcs + compile-time registration

Concepts (3.5A) are rejected due to known issues documented in
`docs/design/notes/nim-concepts.md`: experimental status, compiler bugs
(byref #16897, block scope issues, implicit generic breakage), `func`
in concept body not enforcing `.noSideEffect`, generic type checking
unimplemented, and minimal stdlib adoption. These risks outweigh the
typeclass-like ergonomics.

Each entity type provides plain overloaded `typedesc` `func`s and
`template`s. The required overload set is `methodEntity` (a typed
`MethodEntity` enum tag) plus per-verb method-name resolvers
(`getMethodName`, `setMethodName`, `changesMethodName`,
`queryMethodName`, `queryChangesMethodName`, `copyMethodName`, plus
`importMethodName` for `Email`) that each return a typed `MethodName`.
Passing the wrong verb (e.g. `setMethodName(typedesc[Thread])` when
Thread does not support `/set`) is a compile error at the call site
rather than a runtime "unknownMethod" from the server.

Three registration templates verify at the entity definition site that
the relevant overload sets exist:

- `registerJmapEntity(T)` — checks `methodEntity(T)` and
  `capabilityUri(T)`. Required for every entity type. Per-verb
  method-name resolvers are not checked here because their absence
  produces a precise "undeclared identifier" error at the matching
  builder call site (e.g. `setMethodName(Thread)`), naming the
  entity-verb pair directly.
- `registerQueryableEntity(T)` — checks `filterType(T)` and
  `toJson(default(filterType(T)))`. Required for entity types
  supporting `/query` and `/queryChanges`.
- `registerSettableEntity(T)` — checks `setMethodName(T)`,
  `createType(T)`, `updateType(T)`, and `setResponseType(T)`. Required
  for entity types supporting `/set`. The resolved associated types
  feed the four-parameter `addSet[T, C, U, R]` via the `addSet[T]`
  template alias.

All three templates use `when not compiles()` + `{.error.}` to produce
domain-specific error messages naming the entity type and the exact
missing overload signature.

Generic `add*` functions use `mixin` to resolve entity-specific
overloads at the caller's scope, so entity modules can be added
independently without modifying builder code.

In addition, two compound-method registration templates live in
`dispatch.nim`:

- `registerCompoundMethod(Primary, Implicit)` — for RFC 8620 §5.4
  compound overloads (e.g. `Email/copy` + implicit `Email/set` destroy).
- `registerChainableMethod(Primary)` — for back-reference chains
  (e.g. `Foo/changes` → `Foo/get` via `/created`).

### 3.6 The Six Standard Methods

| Method          | Takes                                                        | Returns                                                                     |
|-----------------|--------------------------------------------------------------|-----------------------------------------------------------------------------|
| `/get`          | accountId, ids/idsRef, properties                            | state, list, notFound                                                       |
| `/set`          | accountId, ifInState, create/update/destroy                  | oldState, newState, created/updated/destroyed, notCreated/notUpdated/notDestroyed |
| `/query`        | accountId, filter, sort, position/anchor, limit              | queryState, canCalculateChanges, position, ids, total                       |
| `/changes`      | accountId, sinceState, maxChanges                            | oldState, newState, hasMoreChanges, created/updated/destroyed               |
| `/queryChanges` | accountId, filter, sort, sinceQueryState, maxChanges         | oldQueryState, newQueryState, removed, added                                |
| `/copy`         | fromAccountId, accountId, ifFromInState, ifInState, create   | oldState, newState, created, notCreated                                     |

**RFC 8621 mail extension methods.** RFC 8621 adds three methods that
do not fit the six-standard-method shape; they are implemented in
`mail/mail_methods.nim` (and `mail/mail_builders.nim` /
`mail/submission_builders.nim`) as custom builders:

| Method                  | Builder                                              | Notes                                                                    |
|-------------------------|------------------------------------------------------|--------------------------------------------------------------------------|
| `Email/parse`           | `addEmailParse(b, accountId, blobIds, …)`            | Parses a blob as an email without storing it (RFC 8621 §4.9).           |
| `Email/import`          | `addEmailImport(b, accountId, emails)`               | Imports raw RFC 5322 messages from blobs (RFC 8621 §4.8).               |
| `SearchSnippet/get`     | `addSearchSnippetGet(b, accountId, filter, emailIds)`| Highlights search matches; only valid against an existing query result. |

Plus the singleton `VacationResponse/get` and `VacationResponse/set`
(`addVacationResponseGet`, `addVacationResponseSet`), the compound
`Email/queryWithSnippets` helper (`addEmailQueryWithSnippets`) that
wires `Email/query` to a `SearchSnippet/get` via result references,
the chained `addEmailQueryWithThreads` (`Email/query` →
`Email/get(properties=[threadId])` → `Thread/get`), and the compound
`addEmailCopyAndDestroy` (`Email/copy` with onSuccessDestroyOriginal
yielding both `CopyResponse[Email]` and the implicit
`SetResponse[Email]`).

### 3.7 Associated Type Resolution for Filters and Sorts

`Filter[C]` (defined in Layer 1 §1.5) is parameterised by condition
type `C`, which varies per entity. Each entity type defines its own
filter conditions and sort properties. The Rust implementation uses
associated types on traits. Nim lacks associated types. The question is
how to resolve `C` from the entity type.

#### Option 3.7A: Multiple type parameters

```
QueryRequest[T, F, S] = object  # T = entity, F = filter, S = sort
```

- **Pros:** Fully type-safe.
- **Cons:** Three type parameters is unwieldy. Every proc needs all
  three.

#### Option 3.7B: Overloaded type-level templates (simulated associated types)

```
template filterType(T: typedesc[Mailbox]): typedesc = MailboxFilter
template filterType(T: typedesc[Email]): typedesc = EmailFilter
```

Then `QueryRequest[T]` uses `filterType(T)` to resolve the filter type.

- **Pros:** Single type parameter. Type-specific behaviour via
  overloads. Closest to Haskell's type families or Rust's associated
  types. Must be `template` (not `proc`) because `typedesc` return
  values used in type positions require compile-time evaluation.
- **Cons:** Relies on compile-time template resolution in type
  positions. Interactions with deeply nested generics under strict mode
  remain fragile.

#### Option 3.7C: `JsonNode` for filters/sorts

Untyped filters. Typed filter constructors per entity return `JsonNode`.

- **Pros:** No generic filter complexity. Works immediately.
- **Cons:** Loses compile-time enforcement. A `MailboxFilter` could be
  used with `Email/query`. Antithetical to the "make illegal states
  unrepresentable" principle.

#### Decision: 3.7B at the builder level, three-parameter funcs underneath

Typed filters from the start. No `JsonNode` escape hatches in the
user-facing API. The implementation uses a hybrid approach.

**Builder funcs use three parameters.** `addQuery[T, C, SortT]` and
`addQueryChanges[T, C, SortT]` carry filter-condition type `C` and
sort-element type `SortT` as explicit parameters. Using `filterType(T)`
in a generic type position proved fragile under Nim's strict mode with
deeply nested generics; explicit parameters are robust. There are no
separate `QueryRequest[T, C]` / `QueryChangesRequest[T, C]` envelope
types — the request shape is assembled directly into a `JsonNode` by
`assembleQueryArgs` / `assembleQueryChangesArgs` in `methods.nim`.
Both helpers consume `SerializedFilter` (a `distinct JsonNode`) produced
from `Filter[C]` via `serializeOptFilter`, so type discipline holds at
the builder boundary even though the wire shape is unstructured.
`assembleQueryArgs` emits `anchorOffset` only when `anchor.isSome`
(Apache James 3.9 rejects bare `anchorOffset`).

**Builder templates resolve associated types at the call site.**
Single-type-parameter template aliases (`addQuery[T]`,
`addQueryChanges[T]`) call `mixin filterType` and forward to the
three-parameter `func` form, defaulting `SortT` to the protocol-level
`Comparator`:

```nim
template addQuery*[T](b: RequestBuilder, accountId: AccountId
                     ): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  addQuery[T, filterType(T), Comparator](b, accountId)

func addQuery*[T, C, SortT](b: RequestBuilder, accountId: AccountId,
                            filter: Opt[Filter[C]] = …,
                            sort: Opt[seq[SortT]] = …,
                            queryParams: QueryParams = QueryParams(),
                            extras: seq[(string, JsonNode)] = @[]
                           ): (RequestBuilder, ResponseHandle[QueryResponse[T]])
```

For entity-typed sort, callers invoke the three-parameter form
directly (e.g. `addQuery[Email, EmailFilterCondition, EmailComparator](…)`).

Filter serialisation goes through `serializeOptFilter` →
`Filter[C].toJson`, which resolves `C.toJson` via `mixin` at the
caller's instantiation site. `SortT` is similarly the typed sort
element (entity-specific `EmailComparator`, `EmailSubmissionComparator`,
or the protocol-level `Comparator`).

Core defines the generic filter *framework* but no concrete filter
types. Concrete filters live in `mail/mail_filters.nim`
(`MailboxFilterCondition`, `EmailFilterCondition`,
`EmailSubmissionFilterCondition`).

### 3.8 Entity-Specific Update Algebras

Each entity that supports `/set` supplies a typed update sum-type ADT
with smart constructors (rather than a generic `PatchObject` builder):

- `EmailUpdate` (six variants: `euAddKeyword`, `euRemoveKeyword`,
  `euSetKeywords`, `euAddToMailbox`, `euRemoveFromMailbox`,
  `euSetMailboxIds`) plus convenience constructors (`markRead`,
  `markUnread`, `markFlagged`, `markUnflagged`, `moveToMailbox`).
- `MailboxUpdate` (five variants: `muSetName`, `muSetParentId`,
  `muSetRole`, `muSetSortOrder`, `muSetIsSubscribed`).
- `IdentityUpdate` (five variants: `iuSetName`, `iuSetReplyTo`,
  `iuSetBcc`, `iuSetTextSignature`, `iuSetHtmlSignature`).
- `EmailSubmissionUpdate` (single variant
  `esuSetUndoStatusToCanceled`, since the only field RFC 8621 §7
  permits modifying is `undoStatus` and only to `"canceled"`).
- `VacationResponseUpdateSet` (singleton patch shape).

Each algebra aggregates into a `NonEmptyXxxUpdates` value that
guarantees the wire `update` map is non-empty and that the RFC 8620
§5.3 prefix-conflict invariant holds. The aggregate value flows
through the `addSet[T]` template alias as the `U` type parameter.

### 3.9 SetResponse Modelling

A `/set` response contains parallel maps: `created`/`notCreated`,
`updated`/`notUpdated`, `destroyed`/`notDestroyed`. An ID appears in
exactly one map per operation.

#### Option 3.9A: Mirror RFC structure (parallel maps)

```
SetResponse[T] = object
  created: Table[CreationId, T]
  notCreated: Table[CreationId, SetError]
  ...
```

- **Pros:** Direct mapping to/from JSON. No transformation.
- **Cons:** Invariant "each ID in exactly one map" not enforced by
  types.

#### Option 3.9B: Unified result map (per-item Result pattern)

```nim
SetResponse[T] = object
  accountId: AccountId
  oldState: Opt[JmapState]
  newState: Opt[JmapState]
  createResults: Table[CreationId, Result[T, SetError]]
  updateResults: Table[Id, Result[Opt[JsonNode], SetError]]
  destroyResults: Table[Id, Result[void, SetError]]
```

- **Pros:**
  - Per-item Result pattern is explicit. Each item has exactly one
    outcome.
  - Pattern matching on `Result` gives success or error.
  - Impossible to have an ID in both the success and failure maps.
- **Cons:** Requires transformation during deserialisation (merge
  parallel maps). Serialisation must split back out.

#### Decision: 3.9B internally, 3.9A on the wire

Deserialise from the RFC format (parallel maps). Immediately merge into
`Result` maps. The user-facing type is the unified result map. This
gives users the clean per-item Result pattern while respecting the
wire format.

**Type asymmetry between create and update outcomes.** `createResults`
is `Table[CreationId, Result[T, SetError]]` because RFC 8620 §5.3
echoes the server-set fields of the created object, which entity
modules type as `EmailCreatedItem`, `MailboxCreatedItem`,
`IdentityCreatedItem`, `EmailSubmissionCreatedItem` (the server-set
subset of the entity, parsed end-to-end via `mixin fromJson`).
`updateResults` is `Table[Id, Result[Opt[JsonNode], SetError]]` because
the RFC permits the server to echo a property subset under `updated[id]`
whose shape is non-uniform — typed parsing belongs at the call site
rather than the protocol layer. `destroyResults` carries
`Result[void, SetError]` because a successful destroy reports only the
ID.

`CopyResponse[T].createResults` is
`Table[CreationId, Result[T, SetError]]`, mirroring `/set`'s create
pattern (§5.4 echoes the same created-item shape).

### 3.10 Result Reference Construction

For a client library, result reference construction is about **building**
references, not resolving them (the server does that).

Result reference types (`ResultReference`, `Referencable[T]`) are
defined in Layer 1 (§1.4). Serialisation of the `#`-prefixed key format
is handled in Layer 2 (§2.3). This section covers:

1. Builder-produced references: the returned handle can produce
   `ResultReference` values pointing to specific paths in that call's
   response.
2. Path constants for common reference targets.

#### Standard Reference Paths

The eight standard paths are typed as the `RefPath` enum in
`methods_enum.nim` (§1.5.8). Each variant has its wire string as the
backing literal:

| `RefPath` variant      | Wire path             | Source method        |
|------------------------|-----------------------|----------------------|
| `rpIds`                | `/ids`                | `/query`             |
| `rpListIds`            | `/list/*/id`          | `/get`               |
| `rpAddedIds`           | `/added/*/id`         | `/queryChanges`      |
| `rpCreated`            | `/created`            | `/changes` or `/set` |
| `rpUpdated`            | `/updated`            | `/changes`           |
| `rpUpdatedProperties`  | `/updatedProperties`  | `/changes`           |
| `rpListThreadId`       | `/list/*/threadId`    | `/get` (Email)       |
| `rpListEmailIds`       | `/list/*/emailIds`    | `/get` (Thread)      |

Vendor-specific paths can still be expressed because Layer 2's lenient
`parseResultReference` preserves arbitrary path strings verbatim in
`rawPath`, but typed builder helpers only compile for `RefPath` variants.

#### Builder Integration

The phantom-typed handle from §3.4 produces references via the generic
`reference[T]` escape hatch (typed `MethodName` and `RefPath`) or via
constrained convenience constructors:

```nim
let (b1, queryHandle) = b0.addQuery[Mailbox](accountId)
# queryHandle : ResponseHandle[QueryResponse[Mailbox]]

# Generic — accepts any RefPath:
let r: ResultReference =
  queryHandle.reference(name = mnMailboxQuery, path = rpIds)

# Constrained — only compiles on QueryResponse handles:
let ids: Referencable[seq[Id]] = idsRef(queryHandle)

let (b2, getHandle) = b1.addGet[Mailbox](accountId, ids = ids)
```

#### Type-safe convenience constructors

Five constrained helpers compile only on the correct handle type (the
phantom parameter constrains the input):

- `idsRef[T](handle: ResponseHandle[QueryResponse[T]])` →
  `Referencable[seq[Id]]` (`rpIds`).
- `listIdsRef[T](handle: ResponseHandle[GetResponse[T]])` →
  `Referencable[seq[Id]]` (`rpListIds`).
- `addedIdsRef[T](handle: ResponseHandle[QueryChangesResponse[T]])` →
  `Referencable[seq[Id]]` (`rpAddedIds`).
- `createdRef[T](handle: ResponseHandle[ChangesResponse[T]])` →
  `Referencable[seq[Id]]` (`rpCreated`).
- `updatedRef[T](handle: ResponseHandle[ChangesResponse[T]])` →
  `Referencable[seq[Id]]` (`rpUpdated`).

Each helper resolves the source method name via the per-verb method-name
resolvers (`queryMethodName(T)`, `getMethodName(T)`, etc.), eliminating
method-name typos. The phantom-type constraint rejects, e.g., `idsRef`
on a `ResponseHandle[GetResponse[T]]` — making illegal references
unrepresentable. Custom paths and uncommon shapes go through
`reference[T](handle, name, path)`.

**Nim type system gap:** In a dependently-typed language, the path
could carry proof that it resolves to `seq[Id]`. In Nim, the
path-to-result-type relationship is a convention.

### 3.11 Entity Data Representation

RFC 8620 Core defines the six standard methods generically — `Foo/get`,
`Foo/set`, etc. — but defines no concrete entity types. Entity types
(`Mailbox`, `Email`, `Thread`, etc.) come from extension RFCs (primarily
RFC 8621). This raises the question of how entity data is represented
in request and response types.

#### Option 3.11A: Fully typed entity data

`GetResponse[T].list` is `seq[T]`. `SetRequest[T].create` is
`Table[CreationId, T]`. Entity bodies are fully parsed at the protocol
layer.

- **Pros:** Maximum type safety. Entity data is typed end-to-end.
- **Cons:** Requires `T.fromJson` and `T.toJson` to be available at the
  protocol layer. RFC 8620 Core cannot define these — it has no entity
  types. Forces a circular dependency: protocol layer (Layer 3) must
  know entity serialisation. Impractical for a Core-only library.

#### Option 3.11B: Raw `JsonNode` entity data with selectively typed echoes (D3.6)

Entity data in the *generic* protocol-level types is `JsonNode`. The
phantom type parameter `T` controls method dispatch (method name,
capability URI, handle constraints) but does not participate in entity
body parsing for `/get` `list` items.

```
GetResponse[T].list:               seq[JsonNode]
SetRequest[T].create:              Opt[Table[CreationId, JsonNode]]
SetResponse[T].createResults:      Table[CreationId, Result[T, SetError]]   # typed via mixin
SetResponse[T].updateResults:      Table[Id, Result[Opt[JsonNode], SetError]]
CopyResponse[T].createResults:     Table[CreationId, Result[T, SetError]]   # typed via mixin
```

- **Pros:**
  - RFC 8620 Core is self-contained — no entity-specific knowledge
    needed for `/get` `list` items.
  - Extension modules (RFC 8621) can add typed parsing independently for
    `createResults` via the entity's `*CreatedItem` type.
  - Matches the Rust `jmap-client` crate's approach (`serde_json::Value`
    for entity data in generic response types).
  - No data loss — unknown entity properties are preserved.
- **Cons:**
  - Entity data in `GetResponse.list` is untyped at the protocol layer.
    Callers must parse `JsonNode` items themselves.

#### Decision: 3.11B

Raw `JsonNode` for `/get` entity data; typed `T` for create-item echoes
(`/set` and `/copy` `createResults`). RFC 8620 Core genuinely has no
entity types to parse. The phantom type `T` provides substantial value —
method name resolution, capability auto-registration, handle type
constraints, type-safe reference functions, typed create-item echoes —
without requiring entity body parsing for `/get` lists.

**Extension point.** When adding typed entity support, the expected
pattern is:

```nim
type Mailbox = object
  id: Id
  name: string
  parentId: Opt[Id]

func fromJson(T: typedesc[Mailbox], node: JsonNode):
    Result[Mailbox, ValidationError] = ...

func parseEntities[T](resp: GetResponse[T]):
    Result[seq[T], ValidationError] =
  var entities: seq[T] = @[]
  for item in resp.list:
    entities.add(?T.fromJson(item))
  ok(entities)
```

No changes to Layers 1–3 Core code are required. The
`registerJmapEntity` and `registerQueryableEntity` templates already
provide compile-time verification that an entity type implements the
required overloads.

### 3.12 Unidirectional Serialisation

Standard method types have asymmetric serialisation needs: request
types are built by the client and sent to the server; response types
are received from the server and parsed by the client.

#### Decision: D3.7 — Unidirectional serialisation

- **Request types** (`GetRequest[T]`, `SetRequest[T]`, etc.) receive
  only `toJson`. The client never parses its own requests.
- **Response types** (`GetResponse[T]`, `SetResponse[T]`, etc.) receive
  only `fromJson` for the production code path. The client never
  serialises server responses.

This eliminates unused serialisation functions and avoids maintaining
code paths that can never be exercised. Layer 2 types (Invocation,
Session, errors, etc.) retain bidirectional serialisation because they
participate in both directions (e.g., Invocation appears in both
Request and Response).

**Round-trip exception.** `SetResponse[T]` and `CopyResponse[T]` have
`toJson` (with internal split-emitters that explode the unified Result
maps back into the wire's parallel `created`/`notCreated`/… maps) for
fixture round-tripping in tests. These are documented in-source as
test-only and are not consumed by production code.

### 3.13 Pipeline Combinators

Common JMAP patterns chain two method calls with a result reference
between them (e.g., query-then-get, changes-then-get). While the
builder's `add*` functions and result reference construction are
sufficient, the boilerplate is repetitive.

The `convenience.nim` module (not re-exported by `protocol.nim`)
provides pipeline combinators:

```
addQueryThenGet[T](b, accountId, ...)
  → QueryGetHandles[T] = (query: ResponseHandle[QueryResponse[T]],
                           get: ResponseHandle[GetResponse[T]])

addChangesToGet[T](b, accountId, sinceState, ...)
  → ChangesGetHandles[T] = (changes: ResponseHandle[ChangesResponse[T]],
                             get: ResponseHandle[GetResponse[T]])
```

Each combinator adds two method calls to the builder, wires the result
reference automatically, and returns a paired handle type for type-safe
extraction of both responses. Paired `getBoth[T]` extraction funcs
return both results as a named result object (`QueryGetResults[T]`,
`ChangesGetResults[T]`).

These are opt-in ergonomics — users who import only `protocol` get the
full builder API without the convenience layer. `addQueryThenGet` is a
`template` (to ensure `mixin filterType` resolution at the call site
for the underlying `addQuery[T]` call). `addChangesToGet` is a `func`
that hardcodes `addChanges[T, ChangesResponse[T]]` (rather than
resolving `changesResponseType(T)`) because `createdRef` is only
defined over `ResponseHandle[ChangesResponse[T]]`. Paired `getBoth`
extraction is `func` — `mixin fromJson` resolves at the caller's
instantiation site.

---

## Layer 4: Transport + Session Discovery

### 4.1 HTTP Client

#### Option 4.1A: `std/httpclient`

Built-in, synchronous.

- **Pros:** No dependencies. Synchronous is appropriate for a C ABI
  library. Works with `--mm:arc`.
- **Cons:** Limited TLS configuration. No connection pooling. May not
  handle all redirect edge cases.

#### Option 4.1B: libcurl wrapper

- **Pros:** Battle-tested TLS, connection pooling, proxy support.
- **Cons:** C dependency. More complex build.

#### Decision: 4.1A

`std/httpclient` is sufficient for session discovery and API requests.
Swap HTTP backends later without affecting other layers if TLS or
performance becomes an issue.

**`raises` caveat:** `std/httpclient`'s request functions (`get`,
`post`, `request`, etc.) have no `{.raises.}` annotations. The compiler
treats them as potentially raising `Exception`. The transport boundary
`proc` must catch `CatchableError` broadly and convert to
`TransportError`. Known exception types include `ProtocolError`,
`HttpRequestError` (both `IOError` subtypes), `ValueError`, and
`TimeoutError`.

### 4.2 Session Discovery

The RFC specifies DNS SRV lookup, then `.well-known/jmap`, then follow
redirects. In practice, every client library takes a direct URL or does
`.well-known` only. None implement DNS SRV.

Two construction paths:

```nim
proc initJmapClient*(
    sessionUrl: string,
    bearerToken: string,
    authScheme: string = "Bearer",
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[JmapClient, ValidationError]

proc discoverJmapClient*(
    domain: string, ...same ancillary args...
): Result[JmapClient, ValidationError]
```

`initJmapClient` validates `sessionUrl` (non-empty, `https://` or
`http://` scheme, no CR/LF), `bearerToken` (non-empty), `timeout`
(`>= -1`), `maxRedirects` (`>= 0`), and `maxResponseBytes` (`>= 0`,
where `0` disables the cap). `discoverJmapClient` validates `domain`
(non-empty, no whitespace per Nim's `Whitespace` set, no `/`) and
hard-codes `https://{domain}/.well-known/jmap` as the constructed
session URL before delegating to `initJmapClient`. There is no opt-in
to plain HTTP for `.well-known` discovery; `initJmapClient` accepts
both schemes for explicit-URL construction.

Validation is structured through an internal `JmapClientViolation` ADT
(twelve violation kinds) with a single `toValidationError` translator —
the canonical functional-core pattern.

Neither constructor fetches the Session — call `fetchSession()`
explicitly or let `send()` lazy-fetch on first use. DNS SRV is not
implemented.

### 4.3 Transport Layer Boundary

The transport layer is the imperative shell. Every IO function is
`proc` (side effects); read-only accessors are `func`. The boundary is
explicit and narrow:

```
proc initJmapClient(...): Result[JmapClient, ValidationError]
proc discoverJmapClient(...): Result[JmapClient, ValidationError]
proc setBearerToken(client: var JmapClient, token: string): Result[void, ValidationError]
proc close(client: var JmapClient)
proc fetchSession(client: var JmapClient): JmapResult[Session]
proc send(client: var JmapClient, request: Request): JmapResult[Response]
proc send(client: var JmapClient, builder: RequestBuilder): JmapResult[Response]
proc refreshSessionIfStale(client: var JmapClient, response: Response): JmapResult[bool]
proc setSessionForTest(client: var JmapClient, session: Session)         ## test-only
proc sendRawHttpForTesting(client: var JmapClient, body: string): JmapResult[Response]  ## test-only

func session(client: JmapClient): Opt[Session]
func sessionUrl(client: JmapClient): string
func bearerToken(client: JmapClient): string
func authScheme(client: JmapClient): string
func lastRawResponseBody(client: JmapClient): string
func isSessionStale(client: JmapClient, response: Response): bool
```

`JmapClient` is an object with eight module-private fields:
`httpClient: HttpClient`, `sessionUrl: string`, `bearerToken: string`,
`authScheme: string`, `session: Opt[Session]`, `maxResponseBytes: int`,
`userAgent: string`, `lastRawResponseBody: string`. Copying a
`JmapClient` shares the underlying HTTP connection — `close()` on any
copy closes it for all copies.

The IO procs take `var JmapClient` because session caching is a
mutation on the client object. `send()` lazy-fetches the session into
the cached field; `fetchSession()` populates it explicitly;
`refreshSessionIfStale()` may replace it.

The `send(Request)` overload is the core IO boundary. The `send(builder)`
convenience overload calls `builder.build()` and forwards to
`send(Request)`.

**Lazy session fetch.** `send()` auto-fetches the Session if not yet
cached. This triggers IO on first use — callers can also call
`fetchSession()` explicitly before the first `send()`.

**Pre-flight validation.** Before serialising the request, `send()`
runs `validateLimits(request, coreCaps)` (a pure `func` returning
`Result[void, ValidationError]`) which checks `maxCallsInRequest` (total
method-call count) and per-invocation `maxObjectsInGet` (length of an
`/get` `ids` array, skipping `#`-keyed reference inputs) and
`maxObjectsInSet` (combined `create` + `update` + `destroy` count for
`/set`). The `maxSizeRequest` cap is enforced inline in `send()` after
serialisation, because it requires the body length. All four limit
checks are decomposed by an internal `RequestLimitViolation` ADT (four
kinds) with a single `toValidationError` translator. Violations are
projected to `ClientError` via `validationToClientError` and short-
circuited with `?` — failing without touching the network.

**Response body size limits.** `JmapClient` accepts an optional
`maxResponseBytes` configuration. Both `Content-Length` header
(`enforceContentLengthLimit`, applied before the body is read) and
actual body length (`enforceBodySizeLimit`, applied after) are checked,
producing `ClientError` on violation. `maxResponseBytes == 0` disables
both checks.

**HTTP response classification.** The transport layer parses HTTP
responses in stages within `classifyHttpResponse`: read status code →
Content-Length pre-check → read body (captured into the client's
`lastRawResponseBody` buffer for test fixtures regardless of subsequent
classification outcome) → body-length post-check → 4xx/5xx branch
(attempt RFC 7807 problem details when Content-Type starts with
`application/problem+json` or `application/json`; fall back to a
generic `httpStatusError`) → non-2xx-non-4xx-non-5xx guard → 2xx
Content-Type validation (`application/json`) → JSON parse. The
"problem details masquerading as 200 OK" case (object with `type` but
no `methodResponses`) is detected separately inside `send()` and
`sendRawHttpForTesting` after JSON parse, before
`Response.fromJson`.

**API URL resolution.** `send()` resolves the Session's `apiUrl`
against the configured `sessionUrl` via `resolveAgainstSession` (RFC
3986 §5) before POSTing — Cyrus emits relative `/jmap/` paths and this
keeps the client portable.

**Test-only escape hatches.** Three procs/accessors exist for testing
adversarial wire shapes without bypassing the type-safe public API:

- `sendRawHttpForTesting(client: var JmapClient, body: string)` —
  POSTs `body` verbatim, bypassing `Request.toJson` and pre-flight
  `validateLimits`. Re-walks the same response classification
  pipeline as `send()`.
- `setSessionForTest(client: var JmapClient, session: Session)` —
  injects a cached Session without an HTTP fetch. Does not validate
  the session.
- `lastRawResponseBody(client: JmapClient)` — accessor that returns
  the raw bytes of the most recent HTTP response body (captured before
  classification, so it is available even when classification errors).

**Session staleness detection.** Two functions support session refresh
without requiring automatic refresh on every response:

```
func isSessionStale(client: JmapClient, response: Response): bool
proc refreshSessionIfStale(client: var JmapClient, response: Response): JmapResult[bool]
```

`isSessionStale` returns `false` when no session is cached.
`refreshSessionIfStale` calls `fetchSession()` if stale and returns
`ok(true)`/`ok(false)` indicating whether a refresh occurred. `send()`
does not auto-refresh — the caller controls when to check.

All errors become `ClientError` on the error track. Success produces
an immutable `Response` value.

**Exception classification.** `classifyException` (defined in
`errors.nim` as a pure function) maps `std/httpclient` exceptions to
`ClientError`. Order of checks: `TimeoutError` → `tekTimeout`;
`SslError` (when `-d:ssl` is set) → `tekTls`; `OSError` —
`isTlsRelatedMsg(msg)` (substring match for "ssl"/"tls"/"certificate")
selects `tekTls` else `tekNetwork`; `IOError` → `tekNetwork`;
`ValueError` → `tekNetwork` with `"protocol error: "` prefix; catch-all
→ `tekNetwork` with `"unexpected error: "` prefix.

**Threading constraint.** Single-threaded. Handles are not thread-safe;
all calls must be made from a single thread. This matches
`std/httpclient`'s design (which is not thread-safe) and simplifies
the initial implementation. Multi-threaded use requires the consumer
to synchronise externally.

### 4.4 Authentication

RFC 8620 §1.1 requires authentication but does not mandate a mechanism.
Bearer tokens are the dominant pattern in JMAP deployments (Fastmail,
etc.), but other schemes (Basic, etc.) are accommodated by the
`authScheme` constructor parameter (defaults to `"Bearer"`).

The transport layer attaches `Authorization: <authScheme> <token>` on
every HTTP request automatically. The token is provided at
`JmapClient` construction time and can be updated via
`setBearerToken(token)`, which validates the token (non-empty), updates
the stored value, and mutates the underlying `HttpClient.headers`
immediately. Read-only access via the `bearerToken()` and `authScheme()`
accessors.

For non-token authentication schemes (e.g. OAuth2 refresh flows,
custom headers), a header callback escape hatch can be added in a
future release. The architecture does not preclude extension.

The `proc send` signature does not change — the client already carries
connection state. Authentication is part of that state, not a
per-request parameter.

### 4.5 Push Mechanisms (Out of Scope)

RFC 8620 §7 defines push mechanisms: EventSource (§7.3) for server-sent
events and push callbacks (§7.2) for webhook-style notifications. Both
deliver `StateChange` events indicating that server state for specific
data types has changed.

These are out of scope. The architecture accommodates them as a Layer 4
concern — EventSource is a long-lived HTTP connection returning
`StateChange` events. No Layer 1–3 changes are required. `StateChange`
becomes a new Layer 1 type when push is added; the EventSource
connection becomes a new Layer 4 proc.

### 4.6 Binary Data (Out of Scope)

RFC 8620 §6 defines binary data handling: uploading (§6.1), downloading
(§6.2), and Blob/copy (§6.3). Upload and download use the Session URL
templates (`uploadUrl`, `downloadUrl`) already modelled in Layer 1.

These are out of scope. When added:

- `UploadResponse` — a new Layer 1 type (`accountId: AccountId`,
  `blobId: BlobId`, `type: string`, `size: UnsignedInt`). Pure data
  using existing Layer 1 primitives.
- Upload and download — new Layer 4 procs that expand the Session URL
  templates and make authenticated HTTP requests.
- `BlobCopyRequest` / `BlobCopyResponse` — Layer 3 method types.
  Blob/copy is a standalone method (not one of the 6 standard methods).
  Its `fromAccountNotFound` method error is already in
  `MethodErrorType`.
- `BlobId` is implemented as a `distinct string` in `identifiers.nim`
  (§1.1). It is already used by RFC 8621 mail methods that consume
  blobs (`Email/import`, `Email/parse`, `setBlobNotFound` SetError
  variant). Blob/copy and the upload / download HTTP procedures are
  still out of scope.

---

## Layer 6: RFC 8621 Mail Extension

RFC 8621 defines the JMAP Mail data model on top of RFC 8620 Core. The
mail extension lives entirely under `src/jmap_client/mail/`, follows
the same L1/L2/L3 split as the core library, and registers with the
core entity framework via the templates in §3.5.

Six core design decisions govern the mail layer; full per-decision
rationale lives in the dedicated design docs (`05-mail-architecture.md`,
`06-mail-a-design.md` … `13-mail-H1-design.md`). This section records
what is implemented and the structural choices that shape it.

### 6.1 Layer Mapping under `mail/`

| Layer | Files |
|-------|-------|
| L1 (types)   | `addresses`, `body`, `email`, `email_blueprint`, `email_submission`, `email_update`, `headers`, `identity`, `keyword`, `mail_capabilities`, `mail_errors`, `mail_filters`, `mailbox`, `mailbox_changes_response`, `snippet`, `submission_atoms`, `submission_envelope`, `submission_mailbox`, `submission_param`, `submission_status`, `thread`, `vacation` |
| L2 (serde)   | `serde_addresses`, `serde_body`, `serde_email`, `serde_email_blueprint`, `serde_email_submission`, `serde_email_update`, `serde_headers`, `serde_identity`, `serde_identity_update`, `serde_keyword`, `serde_mail_capabilities`, `serde_mail_filters`, `serde_mailbox`, `serde_snippet`, `serde_submission_envelope`, `serde_submission_status`, `serde_thread`, `serde_vacation` |
| L3 (protocol)| `mail_entities`, `mail_methods`, `mail_builders`, `identity_builders`, `submission_builders` |
| Hubs         | `mail/types.nim` (L1 hub), `mail/serialisation.nim` (L2 hub), top-level `mail.nim` (re-exports L1+L2+L3) |

Two structural notes:

- `mail/types.nim` re-exports 19 of the 21 L1 modules.
  `submission_atoms`, `submission_param`, and `submission_mailbox`
  are not re-exported by the L1 hub; they reach consumers transitively
  through `submission_envelope` (and its serde companion). Direct
  consumers needing those grammar primitives import them explicitly.
- `mail/serialisation.nim` re-exports the L1 module
  `mailbox_changes_response` because that file carries both the
  `MailboxChangesResponse` type *and* its `fromJson` (no separate
  serde file exists for it).
- `identity_update.nim` does not exist as a separate L1 file — the
  `IdentityUpdate` ADT lives inside `identity.nim`. There IS a
  separate `serde_identity_update.nim`.
- `EmailParseResponse` and `SearchSnippetGetResponse` types are defined
  inside the L3 builder module `mail_methods.nim` (alongside their
  builders), not in `email.nim` / `snippet.nim`. The placement
  reflects the fact that these types are pure response envelopes for
  the corresponding custom builders rather than first-class entity
  data.

The mail layer is wired into the library entry point: `src/jmap_client.nim`
re-exports `types`, `serialisation`, `protocol`, `client`, and `mail`.
Importing the package brings the full RFC 8620 + RFC 8621 surface into
scope.

### 6.2 Implemented Entities

Five entity types are registered with the core framework via
`registerJmapEntity` and (where applicable) `registerQueryableEntity` /
`registerSettableEntity`:

| Entity                              | Methods                                                                  | Capability URI                                |
|-------------------------------------|--------------------------------------------------------------------------|-----------------------------------------------|
| `Thread` (RFC 8621 §3)             | /get, /changes                                                            | `urn:ietf:params:jmap:mail`                   |
| `Identity` (§6)                    | /get, /changes, /set                                                      | `urn:ietf:params:jmap:submission`             |
| `Mailbox` (§2)                     | /get, /changes, /set, /query, /queryChanges                               | `urn:ietf:params:jmap:mail`                  |
| `Email` (§4)                       | /get, /changes, /set, /query, /queryChanges, /copy, /parse, /import       | `urn:ietf:params:jmap:mail`                  |
| `EmailSubmission` (§7)             | /get, /changes, /set, /query, /queryChanges                               | `urn:ietf:params:jmap:submission`            |

`EmailSubmission` registration keys on the existential wrapper
`AnyEmailSubmission` rather than the generic `EmailSubmission[S: static
UndoStatus]`, because Nim cannot pass a generic as a bare `typedesc`.

Two non-entity types use custom builders without entity registration
(Decision A7): `VacationResponse` (singleton; /get and /set only, no
`id` field on the Nim type because RFC §7 mandates the singleton ID
`"singleton"`) and `SearchSnippet` (search-match data carrier; /get
only, only valid against an existing query result).

Mail-layer compound and chainable participation gates are registered in
`mail_entities.nim`:

- `registerCompoundMethod(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])`
  — for `Email/copy onSuccessDestroyOriginal`.
- `registerCompoundMethod(EmailSubmissionSetResponse, SetResponse[EmailCreatedItem])`
  — for `EmailSubmission/set` with `onSuccessUpdateEmail`.
- `registerChainableMethod(QueryResponse[Email])` — `Email/query` →
  downstream `Email/get` via `/ids`.
- `registerChainableMethod(GetResponse[Email])` — `Email/get` →
  `Thread/get` via `/list/*/threadId`.
- `registerChainableMethod(GetResponse[Thread])` — `Thread/get` →
  `Email/get` via `/list/*/emailIds`.

### 6.3 RFC 8621 Read vs. Create vs. Update Models

Each entity that supports `/set` carries three (sometimes four) distinct
types along the read/create/update axis. The split is mandatory because
the wire shape differs: `/get` returns the full server-projected
object; `/set` create takes only client-supplied fields and echoes back
only server-set fields; `/set` update is a closed sum type of legitimate
patches.

| Read model | Create model        | Created-item model              | Update algebra                             |
|------------|---------------------|---------------------------------|--------------------------------------------|
| `Mailbox`  | `MailboxCreate`     | `MailboxCreatedItem`            | `MailboxUpdate` / `NonEmptyMailboxUpdates` |
| `Email`    | `EmailBlueprint`    | `EmailCreatedItem`              | `EmailUpdate` / `NonEmptyEmailUpdates`     |
| `Identity` | `IdentityCreate`    | `IdentityCreatedItem`           | `IdentityUpdate` / `NonEmptyIdentityUpdates` |
| `EmailSubmission` (`AnyEmailSubmission` + `EmailSubmission[S]`) | `EmailSubmissionBlueprint` | `EmailSubmissionCreatedItem` | `EmailSubmissionUpdate` / `NonEmptyEmailSubmissionUpdates` |

The `*CreatedItem` types deliberately use `Opt[T]` for fields the RFC
permits servers to omit — Stalwart 0.15.5 omits several server-set
fields the spec does not technically mandate, and the *CreatedItem*
types accept that gracefully.

### 6.4 Notable Domain Models

**`MailboxRights` — clustered booleans (Decision B6).** Nine RFC 8621
§2 ACL flags (`mayReadItems`, `mayAddItems`, `mayRemoveItems`,
`maySetSeen`, `maySetKeywords`, `mayCreateChild`, `mayRename`,
`mayDelete`, `maySubmit`). Each flag is independent and all
combinations are legitimate; the named-two-case-enum rule from
`nim-functional-core.md` does not apply. This is the canonical
exception, recorded on the type and in the rule.

**`MailboxRole` — discriminated enum + raw fallback.** `MailboxRoleKind`
has eleven variants: ten well-known roles (`mrInbox`, `mrDrafts`,
`mrSent`, `mrTrash`, `mrJunk`, `mrArchive`, `mrImportant`, `mrAll`,
`mrFlagged`, `mrSubscriptions`) plus `mrOther`, the vendor catch-all.
`MailboxRole` is a sealed case object: the `mrOther` branch carries a
module-private `rawIdentifier: string`. Constants for the ten well-known
roles are exported.

**`Keyword` — IMAP-flag-validated `distinct string`.** Strict parser
for client-constructed values; lenient parser for server-received
values (Postel's law). `KeywordSet` is a `distinct HashSet[Keyword]`
with all-membership-only borrowed operations (immutable hash set).
Eight IANA constants exported.

**`MailboxIdSet` and `NonEmptyMailboxIdSet`.** Two flavours of mailbox
ID set: the general form may be empty (used in update payloads where
"no mailbox" is meaningful), the non-empty form is required at create
time (RFC 8621 §4.1 requires every Email to belong to at least one
mailbox).

**`EmailUpdate` — closed sum-type ADT.** Six patch variants
(`euAddKeyword`, `euRemoveKeyword`, `euSetKeywords`, `euAddToMailbox`,
`euRemoveFromMailbox`, `euSetMailboxIds`) plus five convenience
constructors (`markRead`, `markUnread`, `markFlagged`, `markUnflagged`,
`moveToMailbox`). The whole-container `NonEmptyEmailUpdates` enforces
the RFC 8620 §5.3 prefix-conflict invariant by set algebra (see
`mail/email_update.nim` — the canonical example of pattern 2 in
`nim-functional-core.md`).

**`EmailBlueprint` — accumulating-error smart constructor.** Body-shape
case object; `parseEmailBlueprint` collects all field violations into a
single `ValidationError` rather than failing fast. Sealed Pattern A
(`EmailBlueprintErrors` carries the accumulated violations).

**`EmailSubmission[S: static UndoStatus]` — phantom-indexed GADT.**
Lifts the RFC 8621 §7 "only pending submissions may be cancelled"
invariant into the type system. `S` is `usPending`, `usFinal`, or
`usCanceled`. `AnyEmailSubmission` is the existential wrapper for
storage paths that don't know the static state in advance, with
`asPending` / `asFinal` / `asCanceled` discriminator-based accessors
returning `Opt[EmailSubmission[S]]`. `cancelUpdate(EmailSubmission[usPending])`
is the type-gated cancel operation.

`EmailSubmissionCreatedItem` is the `*CreatedItem` projection (server-
set subset of an EmailSubmission).
`EmailSubmissionSetResponse = SetResponse[EmailSubmissionCreatedItem]`
is the typed response alias.

**RFC 5321 atoms (`submission_atoms.nim`,
`submission_mailbox.nim`).** `RFC5321Keyword` is a case-insensitive
ESMTP extension keyword (uppercase canonicalisation, case-insensitive
equality and hash). `OrcptAddrType` is a byte-equal RFC 3461 DSN
address-type. `RFC5321Mailbox` carries the full §4.1.3 address-literal
grammar (IPv4, four IPv6 forms — full, mixed, compressed, mixed
compressed — and General-address-literal).

**`SubmissionParam` — typed SMTP-parameter algebra.** Twelve variants
(eleven well-known parameter names — `BODY`, `SMTPUTF8`, `SIZE`,
`ENVID`, `RET`, `NOTIFY`, `ORCPT`, `HOLDFOR`, `HOLDUNTIL`, `BY`,
`MT-PRIORITY` — plus `spkExtension`) with payload smart constructors
(`BodyEncoding`, `DsnRetType`, `DsnNotifyFlag` set, `DeliveryByMode`,
`HoldForSeconds` (distinct UnsignedInt), `MtPriority` (range -9..9),
etc.). `SubmissionParams` is a `distinct OrderedTable[SubmissionParamKey,
SubmissionParam]` — duplicate-free bag keyed by parameter identity,
preserving wire order.

**Filter conditions — `MailboxFilterCondition`, `EmailFilterCondition`,
`EmailSubmissionFilterCondition` (toJson-only filter conditions,
Decision B7).** RFC 8621 query filters; `Opt[Opt[T]]` encodes RFC
null-vs-absent three-state semantics. `EmailHeaderFilter` (header
name/value pair) is the per-header filter. The server never echoes
filter conditions back to the client, so these types are toJson-only.

**`EmailComparator` and `EmailSubmissionComparator` — typed sort
properties.** Discriminate parameterless properties (e.g. `receivedAt`)
from `hasKeyword`-style sort properties that take a `Keyword`
argument. Replace string-typed sort properties at the entity level
(complementing the protocol-level `Comparator`).

### 6.5 Custom Builders

Standard six methods on registered entities go through the generic core
builder (`addGet[T]`, `addSet[T]`, …) — see §3.6. Extension methods,
chained-pipeline ergonomics, and entity-specific helpers live in
mail-specific builder modules:

- `mail/identity_builders.nim` — `addIdentityGet`,
  `addIdentityChanges`, `addIdentitySet`.
- `mail/submission_builders.nim` — `addEmailSubmissionGet`,
  `addEmailSubmissionChanges`, `addEmailSubmissionQuery`,
  `addEmailSubmissionQueryChanges`, `addEmailSubmissionSet`, plus
  `addEmailSubmissionAndEmailSet` (compound EmailSubmission/set +
  Email/set with onSuccess references; the typed wrappers
  `NonEmptyOnSuccessUpdateEmail` / `NonEmptyOnSuccessDestroyEmail`
  carry the §7.5 ¶3 compound extras with empty-/dup-free invariants).
- `mail/mail_builders.nim` — `addMailboxChanges`, `addMailboxQuery`,
  `addMailboxQueryChanges`, `addMailboxSet`, `addEmailGet`,
  `addEmailGetByRef`, `addThreadGetByRef`, `addEmailQuery`,
  `addEmailQueryChanges`, `addEmailSet`, `addEmailCopy`,
  `addEmailCopyAndDestroy` (with `EmailCopyHandles` /
  `EmailCopyResults` aliases over `dispatch.CompoundHandles`),
  `addEmailQueryWithThreads` (with `EmailQueryThreadChain` /
  `EmailQueryThreadResults` aliases and a `getAll` extractor), and the
  `DefaultDisplayProperties` constant. `Mailbox/get` goes through
  generic `addGet[Mailbox]` rather than a custom builder.
- `mail/mail_methods.nim` — `addVacationResponseGet`,
  `addVacationResponseSet`, the `EmailParseResponse` and
  `SearchSnippetGetResponse` types and their `fromJson`s,
  `addEmailParse`, `addSearchSnippetGet`, `addSearchSnippetGetByRef`,
  `EmailQuerySnippetChain` alias, `addEmailQueryWithSnippets`,
  `addEmailImport` (consuming a `NonEmptyEmailImportMap`).

The `*ByRef` and `*With*` variants are the chained-handle and
compound-handle helpers wired through `dispatch.ChainedHandles` /
`dispatch.CompoundHandles`. They produce paired handles extracted via
`getBoth` (or `getAll`, for the three-way thread chain).

### 6.6 Mail-Specific Errors

`mail/mail_errors.nim` defines typed accessors over the shared
`SetError` ADT (defined in core `errors.nim`, see §1.8.1). The RFC
8621 SetError variants live in core because the type must be
exhaustive at the parse site.

Public typed accessors:

- `notFoundBlobIds(SetError) -> Opt[seq[BlobId]]`
- `maxSize(SetError) -> Opt[UnsignedInt]`
- `maxRecipients(SetError) -> Opt[UnsignedInt]`
- `invalidEmailProperties(SetError) -> Opt[seq[string]]`
- `invalidRecipientAddresses(SetError) -> Opt[seq[string]]`

These give callers one-line discriminated access to the
variant-specific payload without repeating the case match.

### 6.7 Capability Modelling

`mail/mail_capabilities.nim` adds two server-advertised capability
shapes:

- `MailCapabilities` (limits for `urn:ietf:params:jmap:mail` —
  `maxMailboxesPerEmail: Opt[UnsignedInt]`,
  `maxMailboxDepth: Opt[UnsignedInt]`,
  `maxSizeMailboxName: Opt[UnsignedInt]` (Cyrus 3.12.2 omits this
  field; the Postel-receive parser surfaces absence as `Opt.none`
  rather than synthesising a default),
  `maxSizeAttachmentsPerEmail: UnsignedInt`,
  `emailQuerySortOptions: HashSet[string]`, `mayCreateTopLevelMailbox:
  bool`).
- `SubmissionCapabilities`
  (`maxDelayedSend: UnsignedInt`,
  `submissionExtensions: SubmissionExtensionMap`, where
  `SubmissionExtensionMap = distinct OrderedTable[RFC5321Keyword,
  seq[string]]` — case-insensitive ESMTP-keyword keyed and wire-order
  preserving).

These types do not graduate `CapabilityKind` from the core open-world
`else` branch to typed branches automatically — the core
`ServerCapability` keeps `ckMail` and `ckSubmission` in
`else: rawData: JsonNode`. Mail callers use `findCapabilityByUri` and
parse the `SubmissionCapabilities` / `MailCapabilities` shape themselves
where the typed view is needed.

This is a deliberate trade-off: graduating `CapabilityKind` variants
forces a rebuild of every `case` site in core and ties the core layer
to the mail layer's evolution. Keeping them in `else: rawData` lets
mail provide typed parsing without a core-layer dependency on
mail-specific types.

### 6.8 Wire-Layer Lessons

The mail layer encountered structural Nim/wire-shape interactions that
core did not. Two are worth recording:

**Stalwart 0.15.5 server-set field omissions.** Several JMAP servers
omit fields the RFC says they "must" return, especially on `/set`
create-item echoes. The library mitigates this by typing the relevant
fields as `Opt[T]` on the *CreatedItem* models. This is documented per
field in entity modules.

**Apache James strictness vs. Stalwart leniency.** Apache James 3.9
rejects requests that omit `urn:ietf:params:jmap:core` from `using`;
Stalwart 0.15.5 accepts them. The core builder always includes core in
`using` (see `initRequestBuilder`) precisely because of this.
Mail-specific capabilities are added to `using` on first use of any
method that requires them, via the `capabilityUri(T)` overload during
`add*`.

---

## Layer 5: C ABI Wrapper

### 5.1 Principle

The C ABI is a lossy projection of the Nim API. The Nim API has phantom
types, result types, distinct identifiers, variant objects. The C API
has opaque pointers and error codes. The C layer is not the API
designed for — it is a mechanical translation. All FP correctness lives
in the Nim layer.

The mental model: the Nim API is the "real" API. The C ABI is an FFI
binding, as Haskell's FFI exports C-callable wrappers around Haskell
functions.

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

Each object type has `_new` and `_free` functions. Accessor functions
return borrowed pointers.

- **Pros:** Standard C pattern. Familiar. Each object has clear lifetime.
- **Cons:** Easy to leak. Easy to use-after-free.

#### Option 5.3B: Arena/context allocator

One context object. All allocations scoped to it. Single `_free` call
releases everything.

- **Pros:** One free call. Simpler for C consumers.
- **Cons:** Coarser lifetime management. Objects cannot outlive their
  context.

#### Decision: 5.3A

Per-object free functions. Standard C pattern. Arena support can be
added later as a convenience layer on top.

### 5.4 ABI Stability

Pre-1.0: no ABI stability guarantees. C consumers must recompile when
upgrading the library. Opaque handles (§5.2) already insulate C
consumers from internal struct layout changes — field reordering, type
changes, and new fields do not break the C interface. However, changes
to function signatures, handle semantics, or error codes require
recompilation.

Raw Nim enums should not be exposed through the C ABI. Use `cint`
constants or `cint`-returning accessor functions instead. Enum layout
(size, backing type, variant ordering) is a Nim compiler implementation
detail that may change between Nim versions.

### 5.5 Implementation Status

**Layer 5 is architecturally designed but not yet implemented.** The
entry point (`src/jmap_client.nim`) currently serves as a re-export hub
for the Nim API:

```nim
import jmap_client/types
import jmap_client/serialisation
import jmap_client/protocol
import jmap_client/client
import jmap_client/mail

export types          # Layer 1
export serialisation  # Layer 2
export protocol       # Layer 3
export client         # Layer 4
export mail           # RFC 8621 mail extension (Layer 6)
```

No `{.exportc.}` procs, `{.dynlib.}` pragmas, opaque handles, error
codes, or memory management pairs exist yet. The FFI contract is fully
documented in `.claude/rules/nim-ffi-boundary.md` and
`docs/background/nim-c-abi-guide.md`, covering type mapping, string
handling, enum sizing, error codes, thread-local state, ARC ownership,
and library initialisation. Implementation will follow the patterns
described in §5.1–5.4 when the C ABI boundary is built.

Layers 1–4 plus the RFC 8621 mail extension (Layer 6) are implemented
and tested.

---

## Summary of Decisions

Option IDs use section-based numbering: the prefix identifies the
document section where the option is defined (e.g., 1.3B is the second
option in §1.3).

| Layer | Decision | Rationale |
|-------|----------|-----------|
| 1. Types+Errors | Full distinct types for all identifiers (1.1A) | Make illegal states unrepresentable; smart constructors enforce the construction discipline that `requiresInit` would otherwise add (and which is incompatible with seq lifecycle hooks under UnsafeSetLen). |
| 1. Types+Errors | Case object capabilities with known-variant enum and open-world fallback (1.2A) | 12 IANA URIs + ckUnknown; ckMail listed first so that the default kind selects the else branch (lifecycle-hook safety). |
| 1. Types+Errors | `Referencable[T]` variant type (1.3B) | Illegal state (both direct + ref) unrepresentable. |
| 1. Types+Errors | Per-entity typed update algebras instead of a generic PatchObject (§1.5.3, §3.8) | Closed sum types per entity catch operation conflicts; JSON Pointer remains only at the wire layer. |
| 1. Types+Errors | `PropertyName = distinct string` for `Comparator.property` (§1.5.2) | Non-empty validation via smart constructor; stored as private `rawProperty: string` with typed accessor (Pattern A — UnsafeSetLen safety). |
| 1. Types+Errors | Three lifecycle railways + data-level Result pattern: ValidationError, ClientError, MethodError; per-item Result[T, SetError] (1.6C) | Construction, transport, per-invocation separation; per-item outcomes as data within successful SetResponse. |
| 1. Types+Errors | Full enum + rawType for lossless round-trip (1.7C); errorType private on `RequestError` and `MethodError`, public discriminator on `SetError` because `strictCaseObjects` flow analysis requires it. | Parse, don't validate; preserve original; consistency invariant between errorType and rawType. |
| 1. Types+Errors | `message` accessor (cascade detail → title → rawType) on `RequestError` and `ClientError` (§1.8) | Human-readable error description without storing a redundant string. |
| 1. Types+Errors | SetError as case object with public discriminator and seven typed payload arms (§1.8.1) | RFC 8620 + RFC 8621 SetError variants carry typed payloads (`properties`, `existingId`, `notFound`, `invalidEmailPropertyNames`, `maxRecipientCount`, `invalidRecipients`, `maxSizeOctets`); seven typed constructor helpers. |
| 1. Types+Errors | L4 support functions in errors.nim: `classifyException`, `enforceBodySizeLimit`, `sizeLimitExceeded`, `RequestContext`, `validationToClientError(Ctx)` (§1.8) | Pure functions on L1 types serving L4 needs; no upward dependency. |
| 1. Types+Errors | `collation.nim`: typed `CollationAlgorithm` case object (§1.5.7) | Replaces opaque collation strings; four IANA constants + `caOther` open-world fallback. |
| 1. Types+Errors | `methods_enum.nim`: `MethodName`, `MethodEntity`, `RefPath` enums (§1.5.8) | Typed wire identifiers; `Invocation.name` returns `MethodName`, `ResultReference.path` returns `RefPath`; `mnUnknown` open-world variant. |
| 1. Types+Errors | Sealed `Invocation` and partially-sealed `ResultReference` (§1.4) | Pattern A private fields with typed `init*` and lenient `parse*` boundaries; lossless `rawName` / `rawPath` round-trip; `ResultReference.resultOf` public for inspection. |
| 1. Types+Errors | `QueryParams` aggregate (§1.5.5) | Window + calculateTotal in one value type; default-constructible to RFC defaults. |
| 1. Types+Errors | `NonEmptySeq[T]` newtype in primitives (§1.5.6) | Used wherever RFC mandates "at least one" semantics. |
| 1. Types+Errors | `JmapResult[T] = Result[T, ClientError]` defined in `types.nim` (Layer 1 hub) | Outer railway alias; importing the hub brings it into scope. |
| 2. Serialisation | `std/json` manual ser/de, no external deps (2.1A) | Total parsing, `raises: []` via boundary catch. |
| 2. Serialisation | camelCase in Nim source (2.2A) | Zero conversion, leverages style insensitivity. |
| 2. Serialisation | `SerdeViolation` structured error type with 9 variant kinds (§2.4) | JSON Pointer paths and rich kind discriminator; bridged to `ValidationError` via `toValidationError(v, rootType)`; bridged to `MethodError` via `serdeToMethodError` closure factory. |
| 2. Serialisation | `MaxFilterDepth = 128` cap on `Filter[C]` recursion (§2.4) | Defends against pathological server payloads. |
| 2. Serialisation | Distinct-type ser/de templates (`defineDistinctStringToJson/FromJson`, `defineDistinctIntToJson/FromJson`) instantiated for nine string and two integer distinct types (§2.4) | Eliminates per-type boilerplate while keeping the primitive serde co-located with `serde.nim`. |
| 2. Serialisation | Per-variant decomposition of `SetError.fromJson` (§2.4) | Keeps nimalyzer complexity rule satisfied and isolates per-variant defensive parsing. |
| 3. Protocol | Auto-incrementing call IDs (3.2A) | Simple, no safety implications. |
| 3. Protocol | Builder is value type with pure tuple-returning add* (3.3B / D3.5) | Each `add*` returns `(RequestBuilder, ResponseHandle[T])`; preserves `mixin` resolution at the caller's instantiation site; uniform `func` purity across L3. `initRequestBuilder` pre-seeds `urn:ietf:params:jmap:core` for portability across strict/lenient servers. |
| 3. Protocol | Phantom-typed ResponseHandle + NameBoundHandle for compound dispatch (3.4C) | Compile-time response type safety; method-name disambiguation for RFC 8620 §5.4 compound overloads. |
| 3. Protocol | `CompoundHandles[A, B]` and `ChainedHandles[A, B]` paired-handle types (§3.4) | Typed extraction via `getBoth` for compound and back-reference-chain patterns; four `getBoth` overloads in total (two in `dispatch.nim`, two in `convenience.nim`). |
| 3. Protocol | Plain overloaded `func`s + three registration templates: `registerJmapEntity`, `registerQueryableEntity`, `registerSettableEntity` (3.5B) | `methodEntity` + per-verb `MethodName` resolvers replace string-based dispatch; missing overloads produce domain-specific compile errors. `Email` adds `importMethodName`. |
| 3. Protocol | Three-parameter `addQuery[T, C, SortT]` builders + single-type-parameter template aliases (3.7B) | `filterType(T)` resolved at call site via `mixin` for `addQuery[T]`; explicit form available for entity-typed sort. |
| 3. Protocol | Entity-specific typed update algebras (§3.8) | Sum-type ADT per entity replaces a generic patch builder; whole-container `NonEmptyXxxUpdates` enforces non-emptiness and prefix-conflict invariants. |
| 3. Protocol | SetResponse as unified Result maps with mixed typing (3.9B) | `createResults: Result[T, SetError]` (typed via mixin fromJson on entity created-item types); `updateResults: Result[Opt[JsonNode], SetError]` (post-update echo shape varies by server); `destroyResults: Result[void, SetError]`. |
| 3. Protocol | Typed `RefPath` enum + constrained convenience constructors (§3.10) | `idsRef`, `listIdsRef`, `addedIdsRef`, `createdRef`, `updatedRef` only compile on the correct phantom handle; lenient parser preserves vendor paths verbatim. |
| 3. Protocol | Mixed entity-data typing (3.11B / D3.6) | `GetResponse[T].list` is `seq[JsonNode]`; `SetResponse[T].createResults` and `CopyResponse[T].createResults` are `Result[T, SetError]` (typed); `updateResults` keeps `JsonNode` for variable per-server echo shapes. |
| 3. Protocol | Unidirectional serialisation: request `toJson` only, response `fromJson` only, with documented `SetResponse`/`CopyResponse` round-trip exception (D3.7) | Eliminates unused code paths; L2 types retain bidirectional serialisation; round-trip exception serves test fixtures. |
| 3. Protocol | Pipeline combinators in opt-in `convenience.nim` (§3.13) | Reduces result-reference wiring boilerplate; not re-exported by `protocol.nim`. |
| 3. Protocol | `assembleQueryArgs` emits `anchorOffset` only when `anchor.isSome` (§3.7) | Apache James 3.9 rejects bare `anchorOffset`; this preserves portability. |
| 4. Transport | `std/httpclient`, synchronous (4.1A) | No deps, swappable later. |
| 4. Transport | Single-threaded: handles not thread-safe (§4.3) | Simplifies design; matches `std/httpclient` constraint. |
| 4. Transport | `authScheme`-parameterised authentication on JmapClient; header callback later (§4.4) | Defaults to Bearer; accommodates Basic and other schemes via the constructor parameter. |
| 4. Transport | Push/EventSource out of scope for initial release (§4.5) | No Layer 1–3 changes needed; Layer 4 concern when added. |
| 4. Transport | Binary data (upload/download/Blob copy) out of scope for initial release (§4.6) | `BlobId` already implemented for RFC 8621 use; upload / download / Blob/copy procs deferred. |
| 4. Transport | Direct URL (`initJmapClient`) + .well-known (`discoverJmapClient`, hard-coded HTTPS), no DNS SRV (§4.2) | Two construction paths; both return `Result[JmapClient, ValidationError]`. |
| 4. Transport | Lazy session fetch in `send()`; explicit `fetchSession()` also available (§4.3) | First `send()` auto-fetches if no cached Session; caller can pre-fetch. |
| 4. Transport | Pre-flight `validateLimits` checks `maxCallsInRequest`, `maxObjectsInGet`, `maxObjectsInSet`; `maxSizeRequest` enforced inline in `send()` after serialisation (§4.3) | Three limits checkable from the typed Request; the size limit needs the serialised body. Both routes project `ValidationError` to `ClientError` via `validationToClientError`. |
| 4. Transport | Two-phase response body size enforcement (Content-Length pre-check + body-length post-check) (§4.3) | `maxResponseBytes == 0` disables both. |
| 4. Transport | Session staleness detection: `isSessionStale` (pure func) + `refreshSessionIfStale` (proc) (§4.3) | Caller controls refresh; `send()` does not auto-refresh. |
| 4. Transport | `send(builder)` convenience overload (§4.3) | Calls `builder.build()` then `send(request)`. |
| 4. Transport | Test-only escape hatches: `sendRawHttpForTesting`, `setSessionForTest`, `lastRawResponseBody` (§4.3) | Adversarial wire fixtures and session injection without exposing private fields. |
| 4. Transport | `resolveAgainstSession` for relative `apiUrl` (§4.3) | RFC 3986 §5 resolution against the session URL; required for Cyrus's relative `/jmap/` paths. |
| 4. Transport | `classifyException` order: Timeout → SslError → OSError-with-TLS-msg → IOError → ValueError → catch-all (§4.3) | Maps every `std/httpclient` failure mode to a precise `TransportErrorKind`. |
| 5. C ABI | Lossy projection, opaque handles, per-object free (5.3A) | Standard C pattern. |
| 5. C ABI | No ABI stability pre-1.0; C consumers must recompile (§5.4) | Opaque handles insulate; no raw enum exposure through C ABI. |
| 5. C ABI | Not yet implemented; Layers 1–4 + Layer 6 complete (§5.5) | Entry point is Nim re-export hub including `mail`; FFI contract documented. |
| 6. Mail | Five entities registered: Thread, Identity, Mailbox, Email, EmailSubmission (§6.2) | Each registered via `registerJmapEntity` + `registerQueryableEntity` / `registerSettableEntity` as appropriate; `EmailSubmission` keys on `AnyEmailSubmission` because Nim cannot pass a generic as a bare typedesc. |
| 6. Mail | Two non-entity types use custom builders: VacationResponse (singleton), SearchSnippet (search-match data) — Decision A7 (§6.2) | Custom builders avoid forcing degenerate entity registration for singleton/non-CRUD shapes. |
| 6. Mail | Per-entity Read / Create / Created-item / Update split (§6.3) | Wire shape differs by direction; `*CreatedItem.field: Opt[T]` accommodates Stalwart 0.15.5 server-set field omissions. |
| 6. Mail | Phantom-indexed `EmailSubmission[S: static UndoStatus]` + `AnyEmailSubmission` existential + `EmailSubmissionCreatedItem` (§6.4) | Lifts RFC 8621 §7 "only pending submissions may be cancelled" invariant into the type system; existential wrapper for storage paths; created-item is a separate server-set-subset type. |
| 6. Mail | `MailboxRights` clustered booleans (§6.4, Decision B6) | Nine independent ACL flags; canonical exception to the named-two-case-enum rule. |
| 6. Mail | Filter conditions are toJson-only (§6.4, Decision B7) | `MailboxFilterCondition`, `EmailFilterCondition`, `EmailSubmissionFilterCondition` flow client → server only. |
| 6. Mail | RFC 5321 `Mailbox` and SubmissionParam algebra in `submission_*.nim` (§6.4) | Full address-literal support (IPv4, IPv6, General); typed twelve-variant `SubmissionParam` with duplicate-free wire-order-preserving bag. |
| 6. Mail | Mail capabilities stay in core `else: rawData` branch (§6.7) | Avoids forcing core-layer rebuild on mail evolution; mail callers parse `MailCapabilities` / `SubmissionCapabilities` from the raw entry on demand. |
| 6. Mail | `submission_atoms`, `submission_param`, `submission_mailbox` not re-exported by `mail/types.nim` (§6.1) | Reach consumers transitively via `submission_envelope`; direct callers import explicitly. |
| 6. Mail | `EmailParseResponse` and `SearchSnippetGetResponse` defined in `mail_methods.nim` alongside their builders (§6.1) | Pure response envelopes for custom builders rather than first-class entity data. |

## Testability per Layer

Each layer is testable without the layers above it:

- **Layer 1 (Types + Errors):** Unit test type construction, distinct
  type operations, smart constructors. Construct Invocation, Request,
  Response values. Construct ResultReference and Referencable[T] in
  both branches. Construct Filter[C] recursive structures, Comparator,
  AddedItem, QueryParams, CollationAlgorithm. Unit test error
  construction, kind discrimination, round-trip preservation of rawType,
  and the seven typed SetError variant constructors.
- **Layer 2 (Serialisation):** Unit test round-trip serialisation
  against RFC JSON examples. Verify Invocation serialises as 3-element
  JSON array. Verify Referencable[T] serialises correctly for both
  branches (including the `referencableKey` / `fromJsonField` named
  entry points). Verify `SerdeViolation` carries the correct JSON
  Pointer path on every parse failure path; verify `MaxFilterDepth` is
  enforced.
- **Layer 3 (Protocol Logic):** Unit test request builder logic: call
  ID generation, phantom-typed handle creation, builder produces
  correct immutable Request values from chained tuple-returning `add*`
  calls. Unit test entity type registration via `registerJmapEntity` /
  `registerQueryableEntity` / `registerSettableEntity` (3.5B). Unit
  test method request/response construction, including unidirectional
  serialisation (D3.7) and the documented `SetResponse`/`CopyResponse`
  round-trip exception. Verify associated-type template resolution for
  `addQuery[T]`, `addQueryChanges[T]`, `addSet[T]`, `addCopy[T]`,
  `addChanges[T]` (3.7B). Verify unified Result maps with mixed
  entity-data typing in SetResponse (3.9B). Unit test that the builder
  produces correct ResultReference values from phantom-typed handles,
  including the typed `RefPath` enum and type-safe convenience
  references. Unit test `NameBoundHandle` / `CompoundHandles` /
  `ChainedHandles` extraction via `getBoth`. Unit test pipeline
  combinators (§3.13).
- **Layer 4 (Transport):** Integration test against a real or mock
  JMAP server. Unit test client constructors, accessors, mutators,
  bearer-token validation, session discovery, request size enforcement,
  error classification, the `apiUrl` resolution, and the test-only
  escape hatches.
- **Layer 5 (C ABI):** Integration test from C code linking the shared
  library. (Not yet implemented — see §5.5.)
- **Layer 6 (RFC 8621 Mail):** Unit test entity-specific smart
  constructors (Keyword, EmailBlueprint, EmailUpdate, MailboxCreate,
  IdentityCreate, EmailSubmissionBlueprint, RFC5321Mailbox,
  SubmissionParam). Unit test whole-container update algebras
  (`NonEmptyEmailUpdates` prefix-conflict detection,
  `NonEmptyMailboxUpdates`, `NonEmptyIdentityUpdates`,
  `NonEmptyEmailSubmissionUpdates`). Round-trip mail serde against
  captured server fixtures (Stalwart and Apache James). Property-test
  phantom-indexed `EmailSubmission[S]` state transitions. Unit test
  mail-specific builders and compound/chained patterns
  (`addEmailQueryWithSnippets`, `addEmailQueryWithThreads`,
  `addEmailCopyAndDestroy`, `addEmailSubmissionAndEmailSet`).

The RFC includes JSON examples for almost every type. These serve as
test fixtures for Layers 1 and 2.

### Implemented Test Organisation

Tests are organised by category under `tests/`:

```
tests/
  unit/           — Layer 1 types, session invariants, client constructors,
                    entity-specific smart constructors and update algebras
  serde/          — Layer 2 round-trip serialisation, adversarial inputs,
                    captured-server fixtures (Stalwart, Apache James)
  protocol/       — Layer 3 builder, dispatch, entity registration,
                    methods, convenience combinators
  property/       — Property-based tests across all layers
  integration/    — Multi-method request-response pipeline flows
                    against live JMAP servers
  compliance/     — RFC 8620 / RFC 8621 compliance scenarios, regression tests
  stress/         — Stress and adversarial scenarios
  compile/        — Compile-time tests (e.g. registration template error
                    messages, phantom-handle constraints)
```

Shared test infrastructure: `mfixtures.nim` (test fixtures),
`mproperty.nim` (property test utilities), `massertions.nim` (custom
assertions), `mtest_entity.nim` (mock entity registration),
`mserde_fixtures.nim` (serialisation test data).
