# Layer 1: Domain Types + Errors — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, smart constructor, and validation
rule for Layer 1 of the jmap-client library. It builds upon the decisions made in
`00-architecture.md`.

**Scope.** Layer 1 covers: primitive data types (RFC 8620 §1.2–1.4), domain
identifiers, the Session object and everything it contains (§2), the
Request/Response envelope (§3.2–3.4, §3.7), the generic method framework
types (§5.5 Filter/Comparator, §5.6 AddedItem), and all
error types (TransportError, RequestError, ClientError as outer railway
plain objects; MethodError and SetError as inner railway response data).
All error types are plain objects for Railway-Oriented Programming via
nim-results. Serialisation (Layer 2), protocol
logic (Layer 3), and transport (Layer 4) are out of scope. Binary data (§6)
and push (§7) are deferred; see `00-architecture.md` §4.5–4.6.

**Relationship to architecture documents.** `00-architecture.md` records
broad decisions across all 5 layers. This document specifies Layer 1
in detail and tracks the implementation in `src/jmap_client/`.

**Design principles.** Every decision follows:

- **Railway-Oriented Programming** — smart constructors return
  `Result[T, ValidationError]` on success/failure. `ValidationError` is a
  plain object (not an exception), carried on the error rail. The `?`
  operator provides early-return error propagation. Transport/request
  failures use `Result[T, ClientError]` (`JmapResult[T]` alias). All error
  types are plain objects for use with nim-results.
- **Functional Core, Imperative Shell** — Layers 1–3 do not perform I/O or
  mutate global state. Purity is enforced by the compiler: `func` is used
  for all pure functions (Layers 1–3), `proc` only for I/O (Layer 4) or
  functions taking `proc` callback parameters.
  `{.push raises: [], noSideEffect.}` is mandatory on every Layer 1
  source module — both totality and purity enforced at compile time.
- **Immutability by default** — `let` bindings. No mutable state in Layer 1.
  Local `var` inside `func` is permitted when building return values from
  stdlib containers whose APIs require mutation (e.g. accumulating tables
  in `partitionCore`, building parts in `parseUriTemplate`).
- **Total functions** — every function has a defined output for every input.
  The MUST-level invariants the RFC places on `Session` (e.g. presence of
  the core capability) are enforced by the type itself rather than by a
  runtime panic in an accessor: `Session` stores the core capability as a
  typed `rawCore: CoreCapabilities` field, so `coreCapabilities` is total
  by construction with no `raiseAssert` path.
- **Parse, don't validate** — smart constructors produce well-typed Result
  values or return structured errors. Invariants enforced at construction
  time.
- **Make illegal states unrepresentable** — distinct types, case objects,
  smart constructors, and sealed construction (module-private fields) encode
  domain invariants in the type system where the type system permits. Some
  invariants (e.g., `Invocation.arguments` must be a JSON object, not an
  array) are enforced at construction time by Layer 2 parsing and Layer 3
  builders rather than by the Layer 1 type definition, because `JsonNode` is
  an opaque stdlib type that cannot be further constrained without a wrapper.
  Several types use **Pattern A** (sealed construction via module-private
  fields) to prevent direct construction that would bypass validation — see
  `CollationAlgorithm` (§4.4), `Session` (§5.3), `UriTemplate` (§5.2),
  `Invocation` (§6.1), `ResultReference` (§6.4), `Comparator` (§7.4),
  `AddedItem` (§7.5), `RequestError` (§8.4), and `MethodError` (§8.8).
  `SetError` (§8.10) deliberately keeps `errorType*` public — strict case
  object flow analysis (`{.experimental: "strictCaseObjects".}`) requires
  direct discriminator access for external `case se.errorType of setX:
  se.variantField` consumption to type-check.
- **Dual validation strictness** — accept server-generated data leniently
  (tolerating minor RFC deviations such as non-base64url ID characters),
  construct client-generated data strictly. Both paths return `err` on truly
  invalid input — neither silently accepts garbage. Strict constructors are
  used when the client creates values; lenient constructors are used during
  JSON deserialisation of server responses. This principle appears concretely
  in `Id` (§2.1: `parseId` vs `parseIdFromServer`), `AccountId` (§3.1),
  `BlobId` (§3.5), and `Session` cross-reference validation (§5.3).
- **Sum-type ADTs for internal classification** — Multi-step validation
  (date/time, URI templates, session structure, collation, token shape)
  uses module-private `*Violation` ADT enums plus a single
  `toValidationError` translator per ADT. Detection emits the typed
  failure shape; a single function maps the ADT to the wire
  `ValidationError`. Adding a violation variant forces a compile error
  at exactly the translator, not at every detector site.

**Compiler flags.** These constrain every type definition (from
`config.nims` and `jmap_client.nimble`):

```
--mm:arc
--panics:on
--threads:on
--experimental:strictDefs
--experimental:strictEffects
--styleCheck:error
```

Warnings promoted to errors include `CStringConv`, `EnumConv`,
`HoleEnumConv`, `AnyEnumConv`, `BareExcept`, `Uninit`, `UnsafeSetLen`,
`ProveInit`, `StrictNotNil`, `ObservableStores`, and many more. See
`config.nims` for the full list.

**Per-module experimental pragma.** Every `.nim` file under `src/`
includes `{.experimental: "strictCaseObjects".}` immediately after its
`{.push raises: ..., noSideEffect.}` push pragma. Strict case objects
replace the `FieldDefect` runtime check with a compile-time proof
obligation: every variant-field read must occur in a `case` branch that
provably matches the field's declaration. This drives several
encoding choices in this document:

- `SetError.errorType*` is public (not module-private) so external
  consumers can `case se.errorType of setX: se.variantField` —
  strict's flow analysis cannot trace through accessor `func` bodies.
- `Conflict`-style ADTs use combined `of A, B:` arms when their
  declarations combine those variants, and split with inner
  `if v.kind == X` rather than split-of-arms (Rule 2 of the strict
  case object rules).
- `CollationAlgorithm.==` performs a nested `case` on both operands
  rather than relying on the `a.rawKind != b.rawKind` short-circuit
  to traverse branches.

**Notable compiler flags NOT used:**

- `strictFuncs` — not needed; `func` plus
  `{.push raises: [], noSideEffect.}` provides equivalent purity
  enforcement.
- `strictNotNil` — fires inside stdlib generics in Nim 2.2.
  `StrictNotNil` is promoted to a warning-as-error from
  `config.nims` rather than being globally enabled.

---

## Standard Library Utilisation

Layer 1 maximises use of the Nim standard library. Every adoption and rejection
has a concrete reason tied to the compiler constraints.

### Modules used in Layer 1

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/hashes` | `Hash` type, `hash` borrowing for distinct types | `hash(distinctVal)` auto-delegates to base type via `{.borrow.}` |
| `std/tables` | `Table[AccountId, T]`, `Table[string, T]` | For `Session.accounts`, `Session.primaryAccounts`, `Request.createdIds` |
| `std/sets` | `HashSet[CollationAlgorithm]`, `HashSet[string]` | For `CoreCapabilities.collationAlgorithms` (typed) and `UriTemplate.rawVariables` (O(1) `hasVariable`) |
| `std/strutils` | `parseEnum[T](s, default)`, `contains`, `toLowerAscii`, `toHex`, `isAlphaNumeric` | `parseEnum` is total, no exceptions — drives `parseCapabilityKind`, `parseRequestErrorType`, `parseMethodErrorType`, `parseSetErrorType`, `parseCollationAlgorithm` |
| `std/parseutils` | `parseUntil` | For tokenising RFC 6570 Level 1 templates in `parseUriTemplate` |
| `std/json` | `JsonNode` | For untyped capability data (`ServerCapability`, `AccountCapabilityEntry`), `Invocation.arguments`, lossless `extras` preservation in error types |
| `results` (nim-results) | `Result[T, E]`, `Opt[T]`, `ok`, `err`, `?` operator, `valueOr`, `isOkOr` | For Railway-Oriented Programming. `Result` for smart constructors. `Opt[T]` for optional fields (replaces `std/options`). Re-exported via `validation.nim` and `types.nim` |
| `std/sequtils` | `allIt`, `anyIt` | Predicate templates that expand inline — work inside `func` for charset validation in token detectors |
| `std/net` | `TimeoutError`, `SslError` (when `defined(ssl)`) | For `classifyException` in `errors.nim` — exception classification |
| built-in `set[char]` | Charset validation constants | `Base64UrlChars` (`{'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}`) for strict `Id` validation; ad-hoc sets for newline / control character checks |

### Modules evaluated and rejected

| Module | Reason not used in Layer 1 |
|--------|---------------------------|
| `std/options` | Replaced by `Opt[T]` from nim-results. `Opt[T]` integrates with the `?` operator and Railway-Oriented Programming. |
| `std/times` | `times.parse` is `proc` with side effects. A convenience `toDateTime` converter may be provided in a separate utility module. |
| `std/uri` | `parseUri` raises `UriParseError`. `apiUrl` is passed directly to the HTTP client — no need to decompose. |
| `std/enumutils` | `parseEnum` from `strutils` covers parsing. `symbolName` returns the symbolic name (vs `$` which returns the backing string), but symbolic names are not needed in Layer 1. |
| `std/httpcore` | `HttpCode` is relevant to Layer 4 (transport errors), not Layer 1. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `hash` auto-borrows for distinct types | No manual `hash` implementation needed — `{.borrow.}` suffices |
| `$` for string-backed enums returns the **backing string**, not the symbolic name; `symbolName` from `std/enumutils` returns the symbolic name | `$ckCore` returns `"urn:ietf:params:jmap:core"`. However `$ckUnknown` returns `"ckUnknown"` (no backing string), requiring custom `func capabilityUri(kind): Opt[string]` to force callers to handle `ckUnknown` |
| `parseEnum[T](s, default)` is total (no exceptions) | Can be called freely — returns the default on any unrecognised input |
| `parseEnum` matches against **both** symbolic names and string backing values | Negligible risk: JMAP servers send URIs, not Nim identifiers |
| `RangeDefect` bypasses `{.push raises: [].}` (Defect, not CatchableError) | Range types crash instead of raising — not suitable for expected runtime failures |
| `allIt` is a template that expands inline | Works for charset validation in `func` smart constructors |
| `allIt` on empty seq returns `true` (vacuous truth) | Callers must guard `allIt` predicate checks with a non-empty check when an empty input requires a different error |
| Defects (RangeDefect, FieldDefect, AssertionDefect) are fatal | With `--panics:on`, they abort via `rawQuit(1)` — not suitable for expected runtime failures |

---

## 1. Validation Infrastructure

### 1.1 ValidationError

RFC reference: not applicable (library-internal type).

`ValidationError` is the error type for Layer 1 smart constructors. It is a
plain object (not an exception) carried on the `Result` error rail, with enough
context to produce a useful error message without requiring the caller to know
which constructor failed.

```nim
type ValidationError* = object
  ## Structured error carrying the type name, failure reason, and raw input.
  ## Returned on the error rail by all smart constructors on invalid input.
  typeName*: string   ## which type failed ("Id", "UnsignedInt", etc.)
  message*: string    ## the failure reason
  value*: string      ## the raw input that failed validation
```

Constructor helper:

```nim
func validationError*(typeName, message, value: string): ValidationError =
  ValidationError(typeName: typeName, message: message, value: value)
```

`validationError` returns a value (not a ref) because it is used with
`Result[T, ValidationError]`, not raised as an exception. Smart constructors
call `return err(validationError(...))` on invalid input.

`ValidationError` is the error type for smart constructor failures (Layer 1
construction-time validation). `ClientError` (§8.6) is a separate concern
for runtime transport/request failures (Layer 4). These are different error
categories and are not unified into a single type.

**Module:** `src/jmap_client/validation.nim`

### 1.2 Smart Constructor Pattern

Every type with construction-time invariants has a smart constructor following
this pattern:

```nim
func parseFoo*(raw: InputType): Result[Foo, ValidationError] =
  detect<...>(raw).isOkOr:
    return err(toValidationError(error, "Foo", raw))
  return ok(Foo(raw))
```

- Always a `func` — compiler-enforced purity via the module-level
  `{.push raises: [], noSideEffect.}` pragma.
- Returns `Result[T, ValidationError]`: `err(...)` on invalid input,
  `ok(...)` on success. Never raises exceptions.
- The `?` operator provides early-return error propagation; `isOkOr:`
  is its complement (binds `error` for handler-side branching).
- Validation typically delegates to a typed *detector* (see §1.4) and
  routes the violation through a single `toValidationError` translator
  per ADT (Pattern 5 in `nim-functional-core.md`).
- No `doAssert` postconditions on the success path. The detection
  function defines what valid input looks like; a redundant postcondition
  check duplicates that contract and adds a panic path the type system
  cannot reason about.
- For distinct types (e.g. `Id`, `UnsignedInt`, `Date`), the raw constructor
  is the base type conversion (`string(x)` or `int64(x)`), which is not
  accessible outside the defining module without explicit borrowing. Only
  the smart constructor is public.
- For non-distinct object types with invariants, **Pattern A** (sealed
  construction via module-private fields) prevents direct construction
  from outside the defining module. The `ruleOff: "objects"` pragma is
  applied to silence nimalyzer's "all fields must be public" check.
  External code cannot construct `T(...)` directly because the field
  names are invisible outside the defining module. Public read access is
  provided by UFCS accessor functions; `s.field` syntax keeps working at
  call sites unchanged.
- The Layer 1 sealed types are: `CollationAlgorithm` (§4.4),
  `UriTemplate` (§5.2), `Session` (§5.3), `Invocation` (§6.1),
  `ResultReference` (§6.4), `Comparator` (§7.4), `AddedItem` (§7.5),
  `RequestError` (§8.4), `MethodError` (§8.8).
- `SetError` (§8.10) is *not* sealed — its `errorType*` discriminator is
  public so external `case se.errorType of setX: se.variantField` reads
  type-check under `strictCaseObjects`. Variant-bearing construction is
  still gated by the `setErrorXyz` smart constructors; the generic
  `setError` defensively maps payload-bearing rawType strings without
  wire data to `setUnknown` (§8.10).
- For types with no invariants beyond their constituent types, the raw
  constructor may be exported directly (e.g. `Account`,
  `AccountCapabilityEntry`, `Filter[C]`, `Referencable[T]`).

### 1.3 Borrow Templates

The validation module defines four templates that borrow standard
operations from the underlying base type. Each module that defines
distinct types invokes one or more of these templates.

```nim
import std/hashes

template defineStringDistinctOps*(T: typedesc) =
  ## Borrows ==, $, hash, len for a distinct string type.
  func `==`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}
  func len*(a: T): int {.borrow.}

template defineIntDistinctOps*(T: typedesc) =
  ## Borrows ==, <, <=, $, hash for a distinct int type.
  func `==`*(a, b: T): bool {.borrow.}
  func `<`*(a, b: T): bool {.borrow.}
  func `<=`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}

template defineHashSetDistinctOps*(T: typedesc, E: typedesc) =
  ## Read-only ops for a distinct HashSet (no mutation, no `==`, no `hash`).
  ## `len`, `contains`, `card` only — these are immutable read models that
  ## are constructed once and queried, never compared as whole sets or
  ## used as table keys.
  func len*(s: T): int {.borrow.}
  func contains*(s: T, e: E): bool   ## explicit body — see below
  func card*(s: T): int {.borrow.}

template defineNonEmptyHashSetDistinctOps*(T, E: typedesc) =
  ## Composes defineHashSetDistinctOps and adds ==, $, items, pairs for
  ## creation-context types that carry a non-empty invariant (e.g.
  ## NonEmptyKeywordSet, NonEmptyMailboxIdSet in the mail layer).
  ## `hash` deliberately omitted — stdlib HashSet.hash reads `result`
  ## before initialising it under `{.borrow.}`, which fails strictDefs.
```

`contains` cannot use `{.borrow.}` because Nim unwraps both distinct
types, causing a type mismatch when `E` is itself distinct (e.g.
`Keyword = distinct string`). The template provides an explicit body
that calls `sets.contains(HashSet[E](s), e)`.

The validation module also exports:

- `ruleOff` / `ruleOn` pragma templates for suppressing nimalyzer rules.
- `validateUniqueByIt` template — accumulating uniqueness validator that
  returns `seq[ValidationError]`; takes a sequence and a key expression
  expanding inline (`it`-style template). Backed by a private
  `duplicatesByIt` template that returns the repeated keys in
  first-repeat order.
- `Base64UrlChars*: set[char]` — `{'A'..'Z','a'..'z','0'..'9','-','_'}`,
  the RFC 8620 §1.2 strict identifier alphabet.
- `import results; export results` — every other module that needs
  `Result`/`Opt` re-exports through here.

**Module:** `src/jmap_client/validation.nim`

### 1.4 Detector ADTs

Multi-step validation in Layer 1 is structured around *detector*
functions that return `Result[void, V]` for an internal violation type
`V`, plus a single `toValidationError` translator that maps `V` to the
public `ValidationError`. The smart constructor composes one or more
detectors with `?` and translates at the boundary.

Two detector ADTs live in `validation.nim` because they are shared
across multiple modules:

**`TokenViolation`** — the universal vocabulary for token-shaped
identifier parsers (`Id`, `AccountId`, `JmapState`, `MethodCallId`,
`CreationId`, `BlobId`, plus `Keyword` and `MailboxRole` in the mail
layer):

```nim
type TokenViolation* = enum
  tvEmpty
  tvLengthOutOfRange
  tvControlChars
  tvNonPrintableAscii
  tvForbiddenChar
  tvNotBase64Url
  tvCreationIdPrefix

func toValidationError*(
    v: TokenViolation, typeName, raw: string
): ValidationError
```

`typeName` is caller-supplied so each parser brands its own outer type
name while sharing the message vocabulary.

**Atomic detectors** — single-rule predicates returning
`Result[void, TokenViolation]`:

| Detector | Rule | Violation |
|----------|------|-----------|
| `detectNonEmpty` | `raw.len > 0` | `tvEmpty` |
| `detectLengthInRange(raw, minLen, maxLen)` | length within range | `tvLengthOutOfRange` |
| `detectNoControlChars` | bytes ≥ 0x20, not 0x7F | `tvControlChars` |
| `detectPrintableAscii` | bytes 0x21..0x7E | `tvNonPrintableAscii` |
| `detectNoForbiddenChar(raw, forbidden)` | no byte in `forbidden` | `tvForbiddenChar` |
| `detectBase64UrlAlphabet` | bytes in `Base64UrlChars` | `tvNotBase64Url` |
| `detectNoCreationIdPrefix` | does not start with `'#'` | `tvCreationIdPrefix` |

**Composite detectors** — name the per-parser policies:

| Detector | Composition | Used by |
|----------|-------------|---------|
| `detectLenientToken` | length 1..255, no control chars | `parseIdFromServer`, `parseAccountId`, `parseBlobId`, `parseKeywordFromServer` |
| `detectNonControlString` | non-empty, no control chars | `parseJmapState`, `parseMailboxRole` |
| `detectStrictBase64UrlToken` | length 1..255, base64url alphabet | `parseId` |
| `detectStrictPrintableToken(raw, forbidden)` | length 1..255, printable ASCII, no `forbidden` bytes | `parseKeyword` |
| `detectNonEmptyNoPrefix` | non-empty, no `'#'` prefix | `parseCreationId` |

The single-atomic parser `parseMethodCallId` consumes
`detectNonEmpty` directly without a composite wrapper.

The `Date`, `UriTemplate`, `Session`, and `CollationAlgorithm` parsers
each define their own private `*Violation` ADT in their respective
modules — see §2.4, §5.2, §5.3, §4.4.

### 1.5 `Idx` — Sealed Non-negative Index

```nim
type Idx* = distinct int
defineIntDistinctOps(Idx)
```

`Idx` replaces `Natural` at the domain layer. The project rule
(`nim-type-safety.md`) prohibits `range[T]` for domain constraints
because `RangeDefect` is fatal under `--panics:on`. `Idx` is a sealed
non-negative integer with two construction paths:

```nim
template idx*(i: static[int]): Idx
  ## Compile-time. Negative literals rejected via `{.error.}` —
  ## a pragma, not a runtime check. No panic path emitted.

func parseIdx*(raw: int): Result[Idx, ValidationError]
  ## Runtime. Negativity flows through the Result error rail.
```

Operations defined on `Idx`:

| Op | Signature | Purpose |
|----|-----------|---------|
| `toInt` | `Idx -> int` | unwrap to raw `int`; total, zero-cost |
| `toNatural` | `Idx -> Natural` | bridge for stdlib APIs that still take `Natural` |
| `+` | `(Idx, Idx) -> Idx` | invariant-preserving sum |
| `succ` | `Idx -> Idx` | equivalent to `i + idx(1)` |
| `+=` | `(var Idx, Idx)` | compound addition |
| `<`, `<=`, `>=`, `>`, `==` | `(Idx, int) -> bool` | one-way mixed comparison |

There is deliberately no `Idx - Idx` (could underflow) and no
`Idx + int` (right operand unsafe). Callers needing those route through
`parseIdx` and take the error-rail hit.

`Idx` is consumed by `primitives.allDigits`,
`primitives.offsetStart`, `primitives.isValidNumericOffset`, and the
`NonEmptySeq[T].[]` accessor (§2.7).

**Module:** `src/jmap_client/validation.nim`

---

## 2. Primitive Types

### 2.1 Id

**RFC reference:** §1.2 (lines 287–318).

A `String` of 1–255 octets containing only characters from the URL and Filename
Safe base64 alphabet (RFC 4648 §5), excluding the pad character `=`. Allowed
characters: `A-Za-z0-9`, `-`, `_`.

All record IDs are server-assigned and immutable.

**Type definition:**

```nim
type Id* = distinct string
defineStringDistinctOps(Id)
```

**Charset constant (built-in `set[char]`):**

```nim
const Base64UrlChars* = {'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}
```

**Smart constructors:**

Two constructors following the dual validation strictness principle (see
Design principles). Both delegate to composite token detectors in
`validation.nim`:

```nim
func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  detectStrictBase64UrlToken(raw).isOkOr:
    return err(toValidationError(error, "Id", raw))
  return ok(Id(raw))

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters (including DEL).
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "Id", raw))
  return ok(Id(raw))
```

**Rationale for dual constructors.** The RFC MUST constraint is 1–255 octets
and base64url charset. In practice, some servers send IDs with characters
outside this set. Refusing to parse the entire server response because of an
ID charset violation makes the library unusable with those servers. Both
constructors return `err` on truly invalid input (empty strings, control
characters) — neither silently accepts garbage. The strict constructor is used
when the client constructs IDs; the lenient constructor is used during JSON
deserialisation of server responses.

**Control character handling.** Both lenient constructors (`parseIdFromServer`,
`parseAccountId`, `parseJmapState`) reject the DEL character (`\x7F`) in
addition to C0 control characters (`< ' '`). DEL is a control character
(ASCII 127) that has no valid use in identifiers.

**Module:** `src/jmap_client/primitives.nim`

### 2.2 UnsignedInt

**RFC reference:** §1.3 (lines 326–327).

An `Int` in the range `0 <= value <= 2^53-1`.

**Type definition:**

```nim
type UnsignedInt* = distinct int64
defineIntDistinctOps(UnsignedInt)
```

**Range constant:**

```nim
const MaxUnsignedInt*: int64 = 9_007_199_254_740_991'i64  ## 2^53 - 1
```

**Smart constructor:**

```nim
func parseUnsignedInt*(value: int64): Result[UnsignedInt, ValidationError] =
  if value < 0:
    return err(validationError("UnsignedInt", "must be non-negative", $value))
  if value > MaxUnsignedInt:
    return err(validationError("UnsignedInt", "exceeds 2^53-1", $value))
  return ok(UnsignedInt(value))
```

**Decision D1 rationale.** `range[0'i64..9007199254740991'i64]` was rejected
because violations raise `RangeDefect` (a `Defect`, fatal). This crashes the
process instead of raising a structured error. A JMAP client must not crash
because a server sent a malformed integer.

**Module:** `src/jmap_client/primitives.nim`

### 2.3 JmapInt

**RFC reference:** §1.3 (lines 322–324).

An integer in the range `-2^53+1 <= value <= 2^53-1`. The safe range for
integers stored in a floating-point double.

**Type definition:**

```nim
type JmapInt* = distinct int64
defineIntDistinctOps(JmapInt)
proc `-`*(a: JmapInt): JmapInt {.borrow.}  ## unary negation
```

**Range constants:**

```nim
const
  MinJmapInt*: int64 = -9_007_199_254_740_991'i64  ## -(2^53 - 1)
  MaxJmapInt*: int64 =  9_007_199_254_740_991'i64  ##   2^53 - 1
```

**Smart constructor:**

```nim
func parseJmapInt*(value: int64): Result[JmapInt, ValidationError] =
  if value < MinJmapInt or value > MaxJmapInt:
    return err(validationError("JmapInt", "outside JSON-safe integer range", $value))
  return ok(JmapInt(value))
```

**Note.** `JmapInt` (not `Int`) avoids shadowing Nim's built-in `int`. The type
is defined in Layer 1 because §1.3 defines it as a primitive RFC data type. Its
primary use is in Layer 3 (`/query` request `position` and `anchorOffset`
arguments).

**Module:** `src/jmap_client/primitives.nim`

### 2.4 Date

**RFC reference:** §1.4 (lines 343–349).

A string in RFC 3339 `date-time` format with normalisation constraints:
- `time-secfrac` MUST be omitted if zero.
- All letters (e.g., `T`, `Z`) MUST be uppercase.

Example: `"2014-10-30T14:12:00+08:00"`.

**Type definition:**

```nim
type Date* = distinct string
defineStringDistinctOps(Date)
```

**Smart constructor:**

Validation uses a module-private ADT (`DateViolation`) plus a single
`toValidationError` translator. Detector composition flows through the
`?` operator; the public parsers translate violations to
`ValidationError` at the wire boundary, with caller-supplied
`typeName` so `parseDate` and `parseUtcDate` can share `detectDate`
while each surfacing its own outer type name in the error.

```nim
const AsciiDigits = {'0'..'9'}

func allDigits(raw: string, first, last: Idx): bool
  ## Range digit predicate. ``Idx`` makes non-negativity a type-level
  ## invariant — callers prove ``0 <= first <= last`` at construction
  ## (compile-time via ``idx(...)`` or runtime via ``parseIdx``).

type DateViolation = enum
  dvTooShort
  dvBadDatePortion
  dvLowercaseT
  dvBadTimePortion
  dvLowercaseTOrZ
  dvEmptyFraction
  dvZeroFraction
  dvMissingOffset
  dvTrailingAfterZ
  dvBadNumericOffset
  dvRequiresZ

func detectDatePortion(raw: string): Result[void, DateViolation]
  ## YYYY-MM-DD at positions 0..9.
func detectTimePortion(raw: string): Result[void, DateViolation]
  ## HH:MM:SS at positions 11..18 with uppercase 'T' separator at 10
  ## and no lowercase 't' / 'z' anywhere in the string.
func detectFractionalSeconds(raw: string): Result[void, DateViolation]
  ## If a '.' follows position 19, digits must follow and not all be zero.
func offsetStart(raw: string): Idx
  ## Position where the timezone offset begins (after fractional seconds).
func isValidNumericOffset(raw: string, pos: Idx): bool
  ## Checks raw[pos..pos+5] matches +HH:MM or -HH:MM structurally.
func detectTimezoneOffset(raw: string): Result[void, DateViolation]
  ## Validates 'Z' or '+HH:MM' or '-HH:MM' suffix.

func detectDate(raw: string): Result[void, DateViolation] =
  if raw.len < 20:
    return err(dvTooShort)
  ?detectDatePortion(raw)
  ?detectTimePortion(raw)
  ?detectFractionalSeconds(raw)
  ?detectTimezoneOffset(raw)
  return ok()

func detectUtcDate(raw: string): Result[void, DateViolation] =
  ## Composes detectDate with the UTCDate-specific Z narrowing.
  ?detectDate(raw)
  if raw[^1] != 'Z':
    return err(dvRequiresZ)
  return ok()

func toValidationError(
    v: DateViolation, typeName, raw: string
): ValidationError
  ## Sole domain-to-wire translator. Adding a DateViolation variant
  ## forces a compile error here.

func parseDate*(raw: string): Result[Date, ValidationError] =
  detectDate(raw).isOkOr:
    return err(toValidationError(error, "Date", raw))
  return ok(Date(raw))
```

Detection does NOT perform calendar validation (e.g., February 30) —
purely structural.

**Decision D3 rationale.** `std/times.DateTime` was evaluated but
rejected for Layer 1 because `distinct string` preserves the exact
server representation for lossless round-trip. A convenience converter
`proc toDateTime*(d: Date): DateTime` may be provided in a separate
utility module outside the pure core.

**Module:** `src/jmap_client/primitives.nim`

### 2.5 UTCDate

**RFC reference:** §1.4 (lines 351–353).

A `Date` where the `time-offset` component MUST be `Z` (UTC time).

Example: `"2014-10-30T06:12:00Z"`.

**Type definition:**

```nim
type UTCDate* = distinct string
defineStringDistinctOps(UTCDate)
```

**Smart constructor:**

```nim
func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## Shares detectDate with parseDate via the translator's caller-
  ## supplied typeName, so UTCDate failures surface as
  ## ``typeName="UTCDate"``, not ``"Date"``.
  detectUtcDate(raw).isOkOr:
    return err(toValidationError(error, "UTCDate", raw))
  return ok(UTCDate(raw))
```

**Module:** `src/jmap_client/primitives.nim`

### 2.6 MaxChanges

**RFC reference:** §5.2 (lines 1694–1702).

A positive `UnsignedInt` for `maxChanges` fields in `Foo/changes` and
`Foo/queryChanges` requests. The RFC requires the value to be greater than 0.

**Type definition:**

```nim
type MaxChanges* = distinct UnsignedInt
defineIntDistinctOps(MaxChanges)
```

**Smart constructor:**

```nim
func parseMaxChanges*(raw: UnsignedInt): Result[MaxChanges, ValidationError] =
  ## Rejects 0, which the RFC forbids.
  if int64(raw) == 0:
    return err(validationError("MaxChanges", "must be greater than 0", $int64(raw)))
  return ok(MaxChanges(raw))
```

**Module:** `src/jmap_client/primitives.nim`

### 2.7 NonEmptySeq[T]

**RFC reference:** Not in RFC (library-internal type).

A sequence guaranteed to contain at least one element. Construction is
gated by `parseNonEmptySeq`; mutating operations (`add`, `setLen`,
`del`) are deliberately not borrowed to preserve the non-empty
invariant at the type level.

**Type definition:**

```nim
type NonEmptySeq*[T] = distinct seq[T]

template defineNonEmptySeqOps*(T: typedesc) =
  ## Borrows the read-only operations legitimate for NonEmptySeq[T].
  func `==`*(a, b: NonEmptySeq[T]): bool {.borrow.}
  func `$`*(a: NonEmptySeq[T]): string {.borrow.}
  func hash*(a: NonEmptySeq[T]): Hash {.borrow.}
  func len*(a: NonEmptySeq[T]): int {.borrow.}
  func `[]`*(a: NonEmptySeq[T], i: Idx): lent T   ## explicit body
  func contains*(a: NonEmptySeq[T], x: T): bool   ## explicit body
  iterator items*(a: NonEmptySeq[T]): T
  iterator pairs*(a: NonEmptySeq[T]): (int, T)
```

`[]` takes `Idx` (not raw `int`), making non-negativity a compile-time
invariant; upper-bound violations still panic via the underlying
`seq[T].IndexDefect`. `contains` cannot use `{.borrow.}` because Nim
unwraps both distinct types — when `T` is itself distinct (e.g.
`Date`), the borrow's `x` collapses to the underlying type and the
call no longer matches `seq[T].contains`. The same pattern applies to
`defineHashSetDistinctOps`'s `contains`.

**Smart constructor:**

```nim
func parseNonEmptySeq*[T](
    s: seq[T]
): Result[NonEmptySeq[T], ValidationError] =
  ## Strict: rejects empty input. typeName is "NonEmptySeq" (not
  ## parametrised on T) per the codebase convention.
  if s.len == 0:
    return err(validationError("NonEmptySeq", "must not be empty", ""))
  return ok(NonEmptySeq[T](s))

func head*[T](a: NonEmptySeq[T]): lent T =
  ## First element — guaranteed present by the non-empty invariant.
  seq[T](a)[0]
```

`NonEmptySeq[T]` is consumed by mail-layer creation models and update
handles (e.g. non-empty set targets). It is not directly used by RFC
8620 envelope or session types but is part of the Layer 1 vocabulary.

**Module:** `src/jmap_client/primitives.nim`

---

## 3. Domain Identifiers

All domain identifiers are `distinct string` types with borrowed string
operations. They exist to prevent passing one kind of identifier where another
is expected — a common source of silent bugs in JMAP clients.

### 3.1 AccountId

**RFC reference:** §1.6.2, §2 (Session.accounts keys are `Id[Account]`).

Account identifiers. Server-assigned. Used as keys in `Session.accounts` and as
the `accountId` argument in most method calls.

```nim
type AccountId* = distinct string
defineStringDistinctOps(AccountId)
```

**Smart constructor:**

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "AccountId", raw))
  return ok(AccountId(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.2 JmapState

**RFC reference:** §2 (Session.state), §5.1 (/get response `state`), §5.2
(/changes `sinceState`).

An opaque state token generated by the server. Changes when the data it
represents changes. Used for change detection and delta synchronisation.

```nim
type JmapState* = distinct string
func `==`*(a, b: JmapState): bool {.borrow.}
func `$`*(a: JmapState): string {.borrow.}
func hash*(a: JmapState): Hash {.borrow.}
```

`len` is not borrowed — the length of a state token is not meaningful to
consumers.

**Smart constructor:**

```nim
func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "JmapState", raw))
  return ok(JmapState(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.3 MethodCallId

**RFC reference:** §3.2 (Invocation, element 3).

An arbitrary string from the client, echoed back in the response. Used to
correlate responses to method calls.

```nim
type MethodCallId* = distinct string
func `==`*(a, b: MethodCallId): bool {.borrow.}
func `$`*(a: MethodCallId): string {.borrow.}
func hash*(a: MethodCallId): Hash {.borrow.}
```

`len` is not borrowed — method call IDs are opaque correlation tokens whose
length is not meaningful to consumers (same rationale as `JmapState`, §3.2).

**Smart constructor:**

```nim
func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  detectNonEmpty(raw).isOkOr:
    return err(toValidationError(error, "MethodCallId", raw))
  return ok(MethodCallId(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.4 CreationId

**RFC reference:** §3.3 (Request.createdIds), §5.3 (/set `create` argument).

A client-generated identifier for a record being created. On the wire, creation
IDs are prefixed with `#` when used as forward references. The stored value does
NOT include the `#` prefix — that is a serialisation concern (Layer 2).

```nim
type CreationId* = distinct string
func `==`*(a, b: CreationId): bool {.borrow.}
func `$`*(a: CreationId): string {.borrow.}
func hash*(a: CreationId): Hash {.borrow.}
```

`len` is not borrowed — creation IDs are opaque client-generated identifiers
whose length is not meaningful to consumers.

**Smart constructor:**

```nim
func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  detectNonEmptyNoPrefix(raw).isOkOr:
    return err(toValidationError(error, "CreationId", raw))
  return ok(CreationId(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.5 BlobId

**RFC reference:** §3.2 (blob references in `Email/import`,
`Mailbox/get` `download`/`upload` flows, `Blob/copy`, etc.).

A server-assigned opaque blob identifier. Distinct from `Id` because
the JMAP server is free to use a different identifier space for blobs
than for record IDs (RFC 8620 §6.2). Follows the opaque-token borrow
convention shared with `JmapState`, `MethodCallId`, and `CreationId`:
only `==`, `$`, `hash` are borrowed — no `len` borrow — forcing
`string(blobId).len` at any call site that needs length and making
opacity explicit.

```nim
type BlobId* = distinct string
func `==`*(a, b: BlobId): bool {.borrow.}
func `$`*(a: BlobId): string {.borrow.}
func hash*(a: BlobId): Hash {.borrow.}
```

**Smart constructor:**

```nim
func parseBlobId*(raw: string): Result[BlobId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## Server-assigned — same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "BlobId", raw))
  return ok(BlobId(raw))
```

`BlobId` is consumed by `errors.SetError.notFound` (the `setBlobNotFound`
variant in §8.10) and by RFC 8621 mail layer types.

**Module:** `src/jmap_client/identifiers.nim`

---

## 4. Capability Types

### 4.1 CapabilityKind

**RFC reference:** §2 (Session.capabilities keys), §9.4 (JMAP Capabilities
Registry).

A string-backed enum covering all IANA-registered JMAP capability URIs, with a
`ckUnknown` catch-all for vendor extensions.

**Type definition:**

```nim
type CapabilityKind* = enum
  ckMail = "urn:ietf:params:jmap:mail"
  ckCore = "urn:ietf:params:jmap:core"
  ckSubmission = "urn:ietf:params:jmap:submission"
  ckVacationResponse = "urn:ietf:params:jmap:vacationresponse"
  ckWebsocket = "urn:ietf:params:jmap:websocket"
  ckMdn = "urn:ietf:params:jmap:mdn"
  ckSmimeVerify = "urn:ietf:params:jmap:smimeverify"
  ckBlob = "urn:ietf:params:jmap:blob"
  ckQuota = "urn:ietf:params:jmap:quota"
  ckContacts = "urn:ietf:params:jmap:contacts"
  ckCalendars = "urn:ietf:params:jmap:calendars"
  ckSieve = "urn:ietf:params:jmap:sieve"
  ckUnknown
```

`ckUnknown` has no string backing — it is the catch-all for vendor-specific
extension URIs.

**Decision D5a: `ckMail` before `ckCore`.** Nim's first enum value is the
default. `ServerCapability` is a case object discriminated by `CapabilityKind`;
its `ckCore` branch contains `CoreCapabilities`, whose `UnsignedInt` fields
cannot be default-constructed meaningfully. `seq` operations (`setLen`, `reset`)
must default-construct elements, so the default `CapabilityKind` must select the
`else` branch — whose `rawData: JsonNode` is nil-safe. Placing `ckMail` first
satisfies this constraint.

**Parsing (stdlib `parseEnum`):**

```nim
import std/strutils

func parseCapabilityKind*(uri: string): CapabilityKind =
  ## Maps a capability URI string to an enum value.
  ## Total function: always succeeds. Unknown URIs map to ckUnknown.
  ## Uses strutils.parseEnum which matches against the string backing values.
  strutils.parseEnum[CapabilityKind](uri, ckUnknown)
```

This is a single line, total, no exceptions. `parseEnum` with a `default`
parameter never raises — it returns the default on any unrecognised input.

**Serialisation (reverse direction):**

`$ckCore` returns `"urn:ietf:params:jmap:core"` (the backing string).
However, `$ckUnknown` returns `"ckUnknown"` (no backing string assigned),
which is not a valid capability URI. A function returning `Opt[string]`
forces callers to handle `ckUnknown` explicitly:

```nim
func capabilityUri*(kind: CapabilityKind): Opt[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns none for ckUnknown — callers must use rawUri from ServerCapability.
  ## Uses ``$`` on the string-backed enum, which returns the backing string.
  if kind == ckUnknown:
    return Opt.none(string)
  return Opt.some($kind)
```

**CRITICAL:** `CapabilityKind` must NOT be used as a `Table` key. Multiple
vendor extensions would all map to `ckUnknown`, causing key collisions. All
capability-keyed maps use raw URI strings as keys. The enum is used for pattern
matching inside individual entries, not for keying collections.

**Module:** `src/jmap_client/capabilities.nim`

### 4.2 CoreCapabilities

**RFC reference:** §2 (lines 511–572). Part of
`capabilities["urn:ietf:params:jmap:core"]`.

Eight fields, all required. Seven `UnsignedInt` fields for server limits, plus
a set of collation algorithm identifiers.

**Type definition:**

```nim
import std/sets

type CoreCapabilities* = object
  maxSizeUpload*: UnsignedInt         ## Max file size in octets for single upload
  maxConcurrentUpload*: UnsignedInt   ## Max concurrent requests to upload endpoint
  maxSizeRequest*: UnsignedInt        ## Max request size in octets for API endpoint
  maxConcurrentRequests*: UnsignedInt ## Max concurrent requests to API endpoint
  maxCallsInRequest*: UnsignedInt     ## Max method calls per single API request
  maxObjectsInGet*: UnsignedInt       ## Max objects per single /get call
  maxObjectsInSet*: UnsignedInt       ## Max combined create/update/destroy per /set call
  collationAlgorithms*: HashSet[CollationAlgorithm]
    ## Collation algorithm identifiers (RFC 4790 / RFC 5051)
```

**No smart constructor.** The `UnsignedInt` fields enforce their own invariants
via their smart constructors. Construction happens exclusively during JSON
deserialisation (Layer 2), which validates each field individually.

**Decision D6.** `HashSet[CollationAlgorithm]` (not `HashSet[string]`).
The wire identifier is parsed once at deserialisation time into a sealed
sum type with four IANA-registered branches plus a `caOther` escape
hatch (§4.4) — membership testing then operates on the typed value, not
on raw strings.

**Helper:**

```nim
func hasCollation*(caps: CoreCapabilities, algorithm: CollationAlgorithm): bool =
  algorithm in caps.collationAlgorithms
```

**Module:** `src/jmap_client/capabilities.nim`

### 4.3 ServerCapability

**RFC reference:** §2 (Session.capabilities values).

A case object discriminated by `CapabilityKind`. Only `ckCore` has a typed
representation in RFC 8620. All other capabilities store raw JSON data.

**Type definition:**

```nim
import std/json

type ServerCapability* = object
  rawUri*: string  ## always populated — lossless round-trip
  case kind*: CapabilityKind
  of ckCore:
    core*: CoreCapabilities
  else:
    rawData*: JsonNode
```

`rawUri` is always populated, even for known capabilities. For `ckCore`,
`rawUri` is `"urn:ietf:params:jmap:core"`. For `ckUnknown`, `rawUri` is the
vendor-specific URI that the enum could not represent.

The `else` branch covers all non-core capabilities. When RFC 8621 support is
added, `ckMail` gains its own branch with typed `MailCapabilities`; the `else`
branch then covers the remaining kinds.

**Module:** `src/jmap_client/capabilities.nim`

### 4.4 CollationAlgorithm

**RFC reference:** §5.1.3 (collation), RFC 4790 / RFC 5051.

A sealed sum type covering the four IANA-registered collation
algorithms named by JMAP plus a `caOther` escape-hatch for vendor
extensions with lossless round-trip.

**Type definitions:**

```nim
type CollationAlgorithmKind* = enum
  caAsciiCasemap = "i;ascii-casemap"
  caOctet = "i;octet"
  caAsciiNumeric = "i;ascii-numeric"
  caUnicodeCasemap = "i;unicode-casemap"
  caOther

type CollationAlgorithm* {.ruleOff: "objects".} = object
  ## Sealed: rawKind and rawIdentifier are module-private. Use
  ## parseCollationAlgorithm or the named constants.
  case rawKind: CollationAlgorithmKind
  of caOther:
    rawIdentifier: string ## wire identifier for vendor extensions
  of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
    discard
```

**Accessors:**

```nim
func kind*(c: CollationAlgorithm): CollationAlgorithmKind
  ## Returns the discriminator.
func identifier*(c: CollationAlgorithm): string
  ## Wire identifier — backing string for the four known kinds, or
  ## the captured vendor extension for caOther.
func `$`*(c: CollationAlgorithm): string
  ## Equivalent to identifier — wire-form string.
func `==`*(a, b: CollationAlgorithm): bool
  ## Structural equality. Nested `case` on both operands so strict
  ## case object flow analysis can prove b's discriminator before
  ## reading b.rawIdentifier.
func hash*(c: CollationAlgorithm): Hash
  ## Mixes the kind ordinal with the raw identifier for caOther.
```

**Smart constructor:**

```nim
type CollationViolationKind = enum
  cavEmpty
  cavNonPrintable

type CollationViolation = object
  case kind: CollationViolationKind
  of cavEmpty: discard
  of cavNonPrintable:
    raw: string
    offender: char

func detectCollation(raw: string): Result[void, CollationViolation]
  ## RFC 4790 §3.1: collation identifiers are printable US-ASCII;
  ## JMAP wire format adds a non-empty precondition.

func toValidationError(v: CollationViolation): ValidationError
  ## Sole domain-to-wire translator. Reports the offending byte in
  ## hex (e.g. "contains non-printable byte 0x7F").

func parseCollationAlgorithm*(
    raw: string
): Result[CollationAlgorithm, ValidationError]
  ## Validates and constructs a CollationAlgorithm. Lossless round-trip:
  ## ``$(parseCollationAlgorithm(x).get) == x`` for every x that
  ## survives detection.
```

**Named constants:**

```nim
const
  CollationAsciiCasemap* = CollationAlgorithm(rawKind: caAsciiCasemap)
  CollationOctet* = CollationAlgorithm(rawKind: caOctet)
  CollationAsciiNumeric* = CollationAlgorithm(rawKind: caAsciiNumeric)
  CollationUnicodeCasemap* = CollationAlgorithm(rawKind: caUnicodeCasemap)
```

The four named constants exist because the `CollationAlgorithm` object
is sealed — external code cannot construct a known-kind value
directly. `parseCollationAlgorithm` produces these constants for the
four known wire identifiers and falls back to
`CollationAlgorithm(rawKind: caOther, rawIdentifier: raw)` for vendor
extensions.

`capabilities.nim` re-exports `collation` so consumers of
`CoreCapabilities.collationAlgorithms` see the type without a separate
import. `framework.nim` likewise re-exports it (Comparator's
`collation` field uses `CollationAlgorithm`).

**Module:** `src/jmap_client/collation.nim`

---

## 5. Session Infrastructure

### 5.1 Account

**RFC reference:** §2 (lines 583–643).

An account the user has access to. Contains a user-friendly name, access flags,
and per-account capability information.

**AccountCapabilityEntry:**

```nim
type AccountCapabilityEntry* = object
  kind*: CapabilityKind  ## parsed from URI
  rawUri*: string        ## original URI string — lossless
  data*: JsonNode        ## capability-specific properties
```

A flat object (not a case object) because all account capabilities store raw
JSON in the Core-only implementation. When specific RFCs are added, this may
evolve to a case object with typed branches.

**Account:**

```nim
type Account* = object
  name*: string                               ## user-friendly display name
  isPersonal*: bool                           ## true if belongs to authenticated user
  isReadOnly*: bool                           ## true if entire account is read-only
  accountCapabilities*: seq[AccountCapabilityEntry]  ## per-account capability data
```

`accountCapabilities` is `seq` (not `Table`) because multiple `ckUnknown`
entries (different vendor URIs) would collide in a table keyed by
`CapabilityKind`.

**Helpers:**

```nim
func findCapability*(account: Account, kind: CapabilityKind): Opt[AccountCapabilityEntry] =
  for _, entry in account.accountCapabilities:
    if entry.kind == kind:
      return Opt.some(entry)
  Opt.none(AccountCapabilityEntry)

func findCapabilityByUri*(account: Account, uri: string): Opt[AccountCapabilityEntry] =
  ## Looks up an account capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to
  ## ckUnknown and would be ambiguous via findCapability).
  for _, entry in account.accountCapabilities:
    if entry.rawUri == uri:
      return Opt.some(entry)
  Opt.none(AccountCapabilityEntry)

func hasCapability*(account: Account, kind: CapabilityKind): bool =
  account.findCapability(kind).isSome
```

**`findCapability` note.** `findCapability(account, ckUnknown)` returns the
first entry with `kind == ckUnknown`. When multiple vendor extensions are
present, use `findCapabilityByUri` instead.

**No standalone smart constructor.** Accounts are validated as part of Session
parsing.

**Module:** `src/jmap_client/session.nim`

### 5.2 UriTemplate

**RFC reference:** §2 (Session.downloadUrl, uploadUrl, eventSourceUrl
are URI Templates per RFC 6570 Level 1).

`UriTemplate` is a sealed object that holds the parsed token
sequence, the set of variables it references, and the original
source text for lossless `$` round-trip. Variable-presence checking
is an O(1) HashSet membership test against `rawVariables`; malformed
templates (unmatched braces, empty `{}`, non-RFC-6570-Level-1
variable names) are surfaced at construction.

**Type definitions:**

```nim
type UriPartKind* = enum
  upLiteral
  upVariable

type UriPart* {.ruleOff: "objects".} = object
  case kind*: UriPartKind
  of upLiteral:
    text*: string
  of upVariable:
    name*: string         ## variable name without braces

type UriTemplate* {.ruleOff: "objects".} = object
  ## Sealed: rawParts, rawVariables, rawSource are module-private.
  rawParts: seq[UriPart]
  rawVariables: HashSet[string]
  rawSource: string
```

**Accessors:**

```nim
func parts*(t: UriTemplate): seq[UriPart]
  ## Parsed token sequence — alternates upLiteral and upVariable arms
  ## in source order.
func variables*(t: UriTemplate): HashSet[string]
  ## Set of variable names referenced by the template.
func `$`*(t: UriTemplate): string
  ## Byte-for-byte round-trip with the input string.
func hash*(t: UriTemplate): Hash
  ## Derived from rawSource; consistent with ==.
func `==`*(a, b: UriTemplate): bool
  ## Structural equality via raw source comparison.
```

**Smart constructor:**

```nim
type UriTemplateViolationKind = enum
  utkEmpty
  utkUnmatchedOpenBrace
  utkEmptyVariable
  utkInvalidVariableChar

type UriTemplateViolation = object
  case kind: UriTemplateViolationKind
  of utkEmpty:
    discard
  of utkUnmatchedOpenBrace, utkEmptyVariable:
    position: int
  of utkInvalidVariableChar:
    invalidPosition: int
    badChar: char

func toValidationError(v: UriTemplateViolation, raw: string): ValidationError
  ## Sole domain-to-wire translator. Use-site case mirrors the
  ## declaration's combined `of utkUnmatchedOpenBrace, utkEmptyVariable`
  ## arm and disambiguates with an inner `if v.kind == ...` (strict
  ## case object Rule 2).

func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError]
  ## Parses an RFC 6570 Level 1 URI template into a token sequence.
  ## Rejects empty input, unmatched `{`, empty `{}` variables, and
  ## variable names containing disallowed characters. Stray `}` not
  ## preceded by `{` is treated as a literal byte.
```

The conservative RFC 6570 §2.3 varname charset is implemented as
`isAlphaNumeric or '_'` — every JMAP-required variable
(`accountId`, `blobId`, `type`, `name`, `types`, `closeafter`,
`ping`) qualifies; percent-encoded varnames are not used by JMAP
templates.

**Variable presence check:**

```nim
func hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## O(1) membership test against the pre-built variable set.
  return name in tmpl.rawVariables
```

**Template expansion:**

```nim
func expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string
  ## Folds the parsed parts into a string. Variables not found in
  ## ``variables`` are emitted unexpanded as ``{name}``. Caller is
  ## responsible for percent-encoding values that require it
  ## (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
```

**Module:** `src/jmap_client/session.nim`

### 5.3 Session

**RFC reference:** §2 (lines 477–721).

The JMAP Session resource. Contains server capabilities, user accounts, API
endpoint URLs, and session state.

**Type definition:**

```nim
import std/tables

const CoreCapabilityUri* = "urn:ietf:params:jmap:core"
  ## RFC 8620 §2 canonical URI for the core capability. Session
  ## synthesises a ServerCapability with this URI on every accessor
  ## call — the core arm is stored once as a typed CoreCapabilities
  ## field, not as a case-object entry in the additional list.

type Session* {.ruleOff: "objects".} = object
  ## Fields are module-private; external access via UFCS accessor funcs.
  rawCore: CoreCapabilities
  rawAdditional: seq[ServerCapability]
  rawAccounts: Table[AccountId, Account]
  rawPrimaryAccounts: Table[string, AccountId]
  rawUsername: string
  rawApiUrl: string
  rawDownloadUrl: UriTemplate
  rawUploadUrl: UriTemplate
  rawEventSourceUrl: UriTemplate
  rawState: JmapState
```

All fields are module-private, enforcing construction exclusively via
`parseSession`. This is the sealed construction pattern: no external
code can bypass validation by constructing `Session(...)` directly,
because the field names are invisible outside the defining module.

**Storage decision: `rawCore` + `rawAdditional`.** The RFC 8620 §2
MUST-level invariant ("the capability list MUST include
`urn:ietf:params:jmap:core`") is enforced by the type itself rather
than by a runtime panic in an accessor: the core capability is stored
as a typed `rawCore: CoreCapabilities` field at Session construction
time. `parseSession` extracts it from the input capability list via
`partitionCore`. As a consequence, `coreCapabilities` (§5.3 accessor)
is total — no `raiseAssert` path, no `AssertionDefect`. The
`capabilities` accessor synthesises the core entry on demand for API
symmetry and byte-identical wire serialisation.

Public read access is provided by UFCS accessor functions:

```nim
func capabilities*(s: Session): seq[ServerCapability] =
  ## Synthesises the core entry from rawCore and prepends it to rawAdditional
  ## so the list is RFC-conformant and byte-identical to the wire format.
  result = @[ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: s.rawCore)]
  for cap in s.rawAdditional: result.add(cap)

func accounts*(s: Session): Table[AccountId, Account]
func primaryAccounts*(s: Session): Table[string, AccountId]
func username*(s: Session): string
func apiUrl*(s: Session): string
func downloadUrl*(s: Session): UriTemplate
func uploadUrl*(s: Session): UriTemplate
func eventSourceUrl*(s: Session): UriTemplate
func state*(s: Session): JmapState
```

`accounts` uses `AccountId` keys — `AccountId` has borrowed `==`, `$`,
and `hash`, making it a valid `Table` key. `primaryAccounts` uses raw
`string` keys (not `CapabilityKind`) to avoid the `ckUnknown` key
collision problem (see §4.1 CRITICAL note).

**Design note: `seq` vs `Table` for capability collections.**
`rawAdditional` and `accountCapabilities` use `seq` rather than
`Table` for two reasons: (1) `CapabilityKind` cannot be a table key
because multiple vendor extensions map to `ckUnknown`, causing
collisions; (2) `Table[string, ServerCapability]` or `Table[string,
AccountCapabilityEntry]` would duplicate the URI string (once as the
table key, once inside the entry's `rawUri` field). With `seq`, the
URI lives in one place per entry. The trade-off is that
`findCapability` performs a linear scan, but capability lists are
small (typically fewer than 10 entries). `primaryAccounts` uses
`Table[string, AccountId]` because its values (`AccountId`) do not
contain the URI — no duplication — and its primary access pattern is
O(1) key lookup ("which account is primary for this capability
URI?").

`apiUrl` is plain `string` rather than a distinct type because it is
a concrete URL with no RFC 6570 template variables — `UriTemplate`
does not apply, and the only Layer 1 invariants (non-empty, no
newlines) are enforced by `parseSession`.

**Smart constructor — internal structure:**

```nim
type UriRole = enum
  ## Tags the three URI templates advertised by Session. Backing string
  ## matches the field name used in the wire error message.
  urDownload = "downloadUrl"
  urUpload = "uploadUrl"
  urEventSource = "eventSourceUrl"

type SessionViolationKind = enum
  svMissingCoreCapability
  svEmptyApiUrl
  svApiUrlControlChar
  svUriMissingVariable

type SessionViolation = object
  case kind: SessionViolationKind
  of svMissingCoreCapability, svEmptyApiUrl: discard
  of svApiUrlControlChar:
    apiUrl: string
  of svUriMissingVariable:
    role: UriRole
    variable: string
    rawUri: string

func requiredVariables(role: UriRole): seq[string]
  ## Single source of truth for required URI variables per template
  ## role. Iteration order is the message-reporting order
  ## (first-missing wins).

type CorePartition = object
  ## Internal helper: the core capability extracted from the input list,
  ## plus the remainder. Constructed only via partitionCore; consumed
  ## only by parseSession.
  core: CoreCapabilities
  additional: seq[ServerCapability]

func partitionCore(
    caps: openArray[ServerCapability]
): Result[CorePartition, SessionViolation]
  ## Splits caps into the unique core arm plus everything else.
  ## RFC 8620 §2 says the capability list MUST include core; absence
  ## returns svMissingCoreCapability. Duplicate ckCore entries — which
  ## the RFC does not contemplate — retain the first-seen core arm and
  ## silently drop the rest.

func detectApiUrl(apiUrl: string): Result[void, SessionViolation]
  ## Non-empty + no \r/\n (which would break HTTP request-line framing).

func detectUriVariables(
    role: UriRole, tmpl: UriTemplate
): Result[void, SessionViolation]
  ## Short-circuits on the first required variable missing from tmpl.

func detectSession(
    capabilities: openArray[ServerCapability],
    apiUrl: string,
    downloadUrl, uploadUrl, eventSourceUrl: UriTemplate,
): Result[CorePartition, SessionViolation]
  ## Composes the five sub-detectors with `?` short-circuit, returning
  ## the extracted core partition so parseSession can feed rawCore /
  ## rawAdditional without a second traversal.

func toValidationError(v: SessionViolation): ValidationError
  ## Sole domain-to-wire translator.
```

**Smart constructor:**

```nim
func parseSession*(
    capabilities: seq[ServerCapability],
    accounts: Table[AccountId, Account],
    primaryAccounts: Table[string, AccountId],
    username: string,
    apiUrl: string,
    downloadUrl: UriTemplate,
    uploadUrl: UriTemplate,
    eventSourceUrl: UriTemplate,
    state: JmapState,
): Result[Session, ValidationError] =
  ## Validates structural invariants:
  ## 1. capabilities includes ckCore (RFC section 2: MUST)
  ## 2. apiUrl is non-empty and free of newlines
  ## 3. downloadUrl contains {accountId}, {blobId}, {type}, {name}
  ## 4. uploadUrl contains {accountId}
  ## 5. eventSourceUrl contains {types}, {closeafter}, {ping}
  ## Deliberately omits cross-reference validation (Decision D7).
  let partition = detectSession(
    capabilities, apiUrl, downloadUrl, uploadUrl, eventSourceUrl
  ).valueOr:
    return err(toValidationError(error))
  ok(Session(
    rawCore: partition.core,
    rawAdditional: partition.additional,
    rawAccounts: accounts,
    rawPrimaryAccounts: primaryAccounts,
    rawUsername: username,
    rawApiUrl: apiUrl,
    rawDownloadUrl: downloadUrl,
    rawUploadUrl: uploadUrl,
    rawEventSourceUrl: eventSourceUrl,
    rawState: state,
  ))
```

**Decision D7 rationale (cross-reference leniency).** `parseSession`
deliberately does not validate two RFC cross-reference constraints:

1. **`primaryAccounts` values reference valid `accounts` keys.** The RFC does
   not explicitly constrain values to reference valid `accounts` keys.
   Rejecting the Session for a mismatch would break compatibility with
   servers that send inconsistent data.

2. **Account `accountCapabilities` keys present in `Session.capabilities`.**
   RFC §2 states these MUST match, but in practice servers may include
   per-account capabilities not yet in the top-level object.

This follows the dual validation strictness principle: accept server data
leniently, construct own data strictly.

**Accessor helpers:**

```nim
func coreCapabilities*(session: Session): CoreCapabilities =
  ## Total function: rawCore is stored as a typed field at Session
  ## construction time, so the RFC 8620 §2 MUST invariant is enforced
  ## by the type — no panic path, no runtime assertion.
  return session.rawCore

func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  ## ckCore short-circuits to the synthesised core arm.
  if kind == ckCore:
    return Opt.some(
      ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: session.rawCore))
  for _, cap in session.rawAdditional:
    if cap.kind == kind: return Opt.some(cap)
  return Opt.none(ServerCapability)

func findCapabilityByUri*(session: Session, uri: string): Opt[ServerCapability] =
  ## Looks up a capability by its raw URI string. The CoreCapabilityUri
  ## short-circuits to the synthesised core arm.
  if uri == CoreCapabilityUri:
    return Opt.some(
      ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: session.rawCore))
  for _, cap in session.rawAdditional:
    if cap.rawUri == uri: return Opt.some(cap)
  return Opt.none(ServerCapability)

func primaryAccount*(session: Session, kind: CapabilityKind): Opt[AccountId] =
  ## Returns the primary account for a known capability kind.
  ## Returns none if kind == ckUnknown (no canonical URI) or no primary designated.
  let uri = ?capabilityUri(kind)
  for key, val in session.rawPrimaryAccounts:
    if key == uri: return Opt.some(val)
  return Opt.none(AccountId)

func findAccount*(session: Session, id: AccountId): Opt[Account]
```

`primaryAccount` uses the `?` operator on `capabilityUri(kind)`. If
`kind == ckUnknown`, `capabilityUri` returns `Opt.none(string)`, and `?`
causes `primaryAccount` to return `Opt.none(AccountId)` immediately.

**`primaryAccount` failure modes.** Returns `none` in two cases:
(1) `kind == ckUnknown` (no canonical URI to look up — use
`session.primaryAccounts` directly with the raw URI string), or
(2) no primary account is designated for this capability. For vendor
extensions, access `session.primaryAccounts` directly with the raw URI
string.

**Module:** `src/jmap_client/session.nim`

---

## 6. Request/Response Envelope

### 6.1 Invocation

**RFC reference:** §3.2 (lines 865–880).

A tuple of three elements: method name, arguments object, method call ID.

**JSON serialisation quirk:** Invocations are serialised as 3-element JSON
arrays `["name", {args}, "callId"]`, NOT as JSON objects. This is a Layer 2
concern — the type definition here is the Nim representation.

```nim
import std/json

type Invocation* {.ruleOff: "objects".} = object
  ## Construction sealed: rawName and rawMethodCallId are module-private,
  ## so construction flows through initInvocation (typed, infallible)
  ## or parseInvocation (string-taking, fallible at the wire).
  arguments*: JsonNode    ## named arguments — always a JObject at the wire level
  rawMethodCallId: string ## module-private; always a validated MethodCallId
  rawName: string         ## module-private; always a non-empty wire-format name
```

`arguments` is `JsonNode` at the envelope level. Typed extraction into
concrete method response types happens in Layer 3.

**Accessors:**

```nim
func methodCallId*(inv: Invocation): MethodCallId =
  ## Returns the validated method call ID.
  return MethodCallId(inv.rawMethodCallId)

func name*(inv: Invocation): MethodName =
  ## Typed method-name accessor. Returns mnUnknown for wire names the
  ## library doesn't recognise (forward compatibility — rawName preserves
  ## the verbatim string for lossless round-trip).
  return parseMethodName(inv.rawName)

func rawName*(inv: Invocation): string =
  ## Verbatim wire name. Always non-empty (enforced at construction).
  ## Prefer ``name`` for comparison against a known variant; use
  ## ``rawName`` for wire emission and for forward-compatible inspection
  ## of unknown method names (e.g. the literal ``"error"`` response tag).
  return inv.rawName
```

**Constructors:**

```nim
func initInvocation*(
    name: MethodName, arguments: JsonNode, methodCallId: MethodCallId
): Invocation =
  ## Total, typed constructor. MethodName is a string-backed enum;
  ## the wire name is $name — empty is structurally unrepresentable.
  ## Stores the backing string verbatim in rawName so round-trip is
  ## identity-functional.
  return Invocation(
    arguments: arguments, rawMethodCallId: string(methodCallId), rawName: $name
  )

func parseInvocation*(
    rawName: string, arguments: JsonNode, methodCallId: MethodCallId
): Result[Invocation, ValidationError] =
  ## Wire-boundary constructor: accepts any non-empty string so unknown
  ## method names round-trip losslessly (Postel's law). Used only by
  ## serde_envelope.fromJson.
  if rawName.len == 0:
    return err(validationError("Invocation", "name must not be empty", rawName))
  return ok(Invocation(
    arguments: arguments, rawMethodCallId: string(methodCallId), rawName: rawName
  ))
```

**Constructor split.** Two construction paths reflect the two call
sites: builders use `initInvocation` (producing well-typed wire names
from the `MethodName` enum, total and infallible), while serde uses
`parseInvocation` to round-trip arbitrary names from the wire (Postel's
law — unknown method names round-trip losslessly via `rawName`).

**Module:** `src/jmap_client/envelope.nim`

### 6.2 Request

**RFC reference:** §3.3 (lines 882–943).

```nim
import std/tables

type Request* = object
  `using`*: seq[string]            ## capability URIs the client wishes to use
  methodCalls*: seq[Invocation]    ## processed sequentially by server
  createdIds*: Opt[Table[CreationId, Id]]  ## optional; enables proxy splitting
```

`using` is `seq[string]` (raw URIs, not `seq[CapabilityKind]`) because vendor
extension URIs would collide at `ckUnknown`.

`createdIds` is `Opt` because the RFC specifies it as optional.

**No smart constructor.** Built by the Layer 3 request builder.

**Module:** `src/jmap_client/envelope.nim`

### 6.3 Response

**RFC reference:** §3.4 (lines 975–1003).

```nim
type Response* = object
  methodResponses*: seq[Invocation]            ## same format as methodCalls
  createdIds*: Opt[Table[CreationId, Id]]      ## only present if given in request
  sessionState*: JmapState
    ## Current Session.state value. After every response, compare with
    ## Session.state; if they differ, the session is stale and should
    ## be re-fetched (RFC 8620 §3.4).
```

**Module:** `src/jmap_client/envelope.nim`

### 6.4 ResultReference

**RFC reference:** §3.7 (lines 1220–1261).

Allows an argument to one method call to be taken from the result of a previous
method call in the same request.

```nim
type ResultReference* {.ruleOff: "objects".} = object
  ## Construction sealed: rawName and rawPath are module-private, so
  ## construction flows through initResultReference (typed, infallible)
  ## or parseResultReference (string-taking, fallible at the wire).
  resultOf*: MethodCallId ## method call ID of the previous call
  rawName: string         ## module-private; expected response name (non-empty)
  rawPath: string         ## module-private; JSON Pointer (RFC 6901) with JMAP '*'
```

**Accessors:**

```nim
func name*(rr: ResultReference): MethodName =
  ## Typed response-name accessor. Returns mnUnknown for forward-compat
  ## wire names — rawName preserves the verbatim string.
  return parseMethodName(rr.rawName)

func rawName*(rr: ResultReference): string =
  ## Verbatim wire name of the referenced response.
  return rr.rawName

func path*(rr: ResultReference): RefPath =
  ## Typed result-reference path. Unknown paths fall back to rpIds —
  ## but this never fires in practice because the server only echoes
  ## paths we sent, which are always drawn from the enum.
  for p in RefPath:
    if $p == rr.rawPath: return p
  return rpIds

func rawPath*(rr: ResultReference): string =
  ## Verbatim wire path — e.g. ``"/ids"`` or ``"/list/*/id"``.
  return rr.rawPath
```

**Constructors:**

```nim
func initResultReference*(
    resultOf: MethodCallId, name: MethodName, path: RefPath
): ResultReference =
  ## Total, typed constructor. Both enum parameters are string-backed;
  ## stored verbatim as $name / $path for lossless wire emission.
  return ResultReference(resultOf: resultOf, rawName: $name, rawPath: $path)

func parseResultReference*(
    resultOf: MethodCallId, name: string, path: string
): Result[ResultReference, ValidationError] =
  ## Wire-boundary constructor. Accepts any non-empty strings so forward-
  ## compatible references (unknown method names, unknown paths) round-trip
  ## losslessly. Used only by serde_envelope.fromJson.
  if name.len == 0:
    return err(validationError("ResultReference", "name must not be empty", name))
  if path.len == 0:
    return err(validationError("ResultReference", "path must not be empty", path))
  return ok(ResultReference(resultOf: resultOf, rawName: name, rawPath: path))
```

**Path enum.** `initResultReference` consumes the `RefPath` enum
defined in `methods_enum.nim` (§9) directly; `parseResultReference`
accepts arbitrary strings, and the `path` accessor falls back to
`rpIds` for unknown wire paths (a path the library did not emit and
should never see in a server response).

**Module:** `src/jmap_client/envelope.nim`

### 6.5 Referencable[T]

A variant type encoding the mutual exclusion between a direct value and a result
reference. Makes the illegal state "both direct value and reference"
unrepresentable.

```nim
type
  ReferencableKind* = enum
    rkDirect
    rkReference

  Referencable*[T] = object
    case kind*: ReferencableKind
    of rkDirect:
      value*: T
    of rkReference:
      reference*: ResultReference
```

**Constructor helpers:**

```nim
func direct*[T](value: T): Referencable[T] =
  Referencable[T](kind: rkDirect, value: value)

func referenceTo*[T](reference: ResultReference): Referencable[T] =
  Referencable[T](kind: rkReference, reference: reference)
```

**Module:** `src/jmap_client/envelope.nim`

---

## 7. Generic Method Framework Types

### 7.1 FilterOperator

**RFC reference:** §5.5.

A string-backed enum covering the three RFC-defined filter composition operators.

**Type definition:**

```nim
type FilterOperator* = enum
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"
```

No smart constructor — total by construction.

**Module:** `src/jmap_client/framework.nim`

### 7.2 Filter[C]

**RFC reference:** §5.5.

A recursive algebraic data type parameterised by condition type `C`.

**Type definition:**

```nim
type
  FilterKind* = enum
    fkCondition
    fkOperator

  Filter*[C] = object
    case kind*: FilterKind
    of fkCondition:
      condition*: C
    of fkOperator:
      operator*: FilterOperator
      conditions*: seq[Filter[C]]
```

`seq[Filter[C]]` provides heap-allocated indirection for the recursion without
`ref`.

**Constructor helpers:**

```nim
func filterCondition*[C](cond: C): Filter[C] =
  Filter[C](kind: fkCondition, condition: cond)

func filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =
  Filter[C](kind: fkOperator, operator: op, conditions: conditions)
```

Total constructors. No validation needed — all inputs produce valid filters.

**Module:** `src/jmap_client/framework.nim`

### 7.3 PropertyName

**RFC reference:** §5.5 (property names in Comparator, referenced throughout).

A property name is a non-empty string identifying a field on an entity type.

**Type definition:**

```nim
type PropertyName* = distinct string
defineStringDistinctOps(PropertyName)
```

**Smart constructor:**

```nim
func parsePropertyName*(raw: string): Result[PropertyName, ValidationError] =
  if raw.len == 0:
    return err(validationError("PropertyName", "must not be empty", raw))
  ok(PropertyName(raw))
```

**Module:** `src/jmap_client/framework.nim`

### 7.4 Comparator

**RFC reference:** §5.5. Determines the sort order for a `/query` request.

**Type definition:**

```nim
type Comparator* = object
  ## Construction sealed via Pattern A: rawProperty is module-private,
  ## blocking direct construction from outside this module. Use
  ## parseComparator to construct.
  rawProperty: string                  ## module-private; validated PropertyName
  isAscending*: bool                   ## true = ascending (RFC default)
  collation*: Opt[CollationAlgorithm]  ## RFC 4790 / RFC 5051 algorithm
```

**Accessor:**

```nim
func property*(c: Comparator): PropertyName =
  ## Returns the validated property name for this comparator.
  return PropertyName(c.rawProperty)
```

`isAscending` defaults to `true` per RFC §5.5. The constructor mirrors
this default for convenience.

**Constructor:**

```nim
func parseComparator*(
    property: PropertyName,
    isAscending: bool = true,
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): Comparator =
  ## Constructs a Comparator. Infallible given a valid PropertyName.
  return Comparator(
    rawProperty: string(property), isAscending: isAscending, collation: collation
  )
```

The non-empty property invariant is enforced by `PropertyName`'s smart
constructor. `collation` is `Opt[CollationAlgorithm]` (not
`Opt[string]`) — the wire identifier is parsed once into the typed sum
type at deserialisation. `framework.nim` re-exports `collation`.

**Module:** `src/jmap_client/framework.nim`

### 7.5 AddedItem

**RFC reference:** §5.6. An element of the `added` array in a `/queryChanges`
response.

**Type definition:**

```nim
type AddedItem* = object
  ## Construction sealed via Pattern A (architecture Limitation 5/6a):
  ## rawId is module-private, blocking direct construction from outside
  ## this module. Use initAddedItem to construct.
  rawId: string          ## module-private; validated Id
  index*: UnsignedInt    ## the position index
```

**Accessor:**

```nim
func id*(item: AddedItem): Id =
  ## Returns the validated item identifier.
  Id(item.rawId)
```

**Constructor:**

```nim
func initAddedItem*(id: Id, index: UnsignedInt): AddedItem =
  ## Constructs an AddedItem. Infallible given validated Id and UnsignedInt.
  return AddedItem(rawId: string(id), index: index)
```

**Module:** `src/jmap_client/framework.nim`

### 7.6 QueryParams

**RFC reference:** §5.5 (lines 1860–1995). The standard window
parameters shared by every `/query` method call.

```nim
type QueryParams* = object
  ## Standard query window parameters shared by all /query methods.
  ## All defaults match RFC specification via Nim zero-initialisation:
  ## QueryParams() produces correct RFC defaults.
  position*: JmapInt          ## default 0
  anchor*: Opt[Id]            ## default: absent
  anchorOffset*: JmapInt      ## default 0
  limit*: Opt[UnsignedInt]    ## default: absent
  calculateTotal*: bool       ## default false
```

No smart constructor — every field's type already enforces its own
invariants, and the zero-initialised value is the RFC default.
Higher-layer query builders accept `QueryParams` directly as a single
parameter to avoid keyword-argument fan-out at every call site.

**Module:** `src/jmap_client/framework.nim`

---

## 8. Error Types

Error types implement a three-railway error hierarchy. All error types are
**plain objects** (not exceptions) for use with Railway-Oriented Programming
via nim-results. The outer railway (`TransportError`, `RequestError`,
`ClientError`) handles transport/request failures — these are carried on the
`Result` error rail via `Result[T, ClientError]` (`JmapResult[T]` alias).
The inner railway (`MethodError`, `SetError`) handles per-invocation and
per-item errors within successful JMAP responses — these are data within
successful `Response` values.

All error constructors are `func` and return values directly. Error types
represent received data or classified exceptions; they cannot fail
construction.

All error types that carry a `type` string follow the lossless round-trip
pattern: a parsed enum (`errorType`) alongside a preserved raw string
(`rawType`). Serialisation always uses `rawType`, never `$errorType`.
`RequestError.errorType` and `MethodError.errorType` are sealed
(module-private) with public accessor functions, enforcing the
"errorType derived from rawType" consistency invariant.
`SetError.errorType*` is the exception — its discriminator is public
because strict case object flow analysis cannot trace through accessor
funcs (see §8.10 for the discussion).

### 8.1 TransportErrorKind

**RFC reference:** Not in RFC (library-internal type).

**Purpose:** Discriminator enum for `TransportError`. Four variants covering
transport failure modes below the JMAP protocol level.

```nim
type TransportErrorKind* = enum
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus
```

No string backing values — these are library-internal classifications, not
RFC-defined wire strings.

**Module:** `src/jmap_client/errors.nim`

### 8.2 TransportError

**RFC reference:** Not in RFC (library-internal type).

**Purpose:** Plain object carrying a human-readable message and
variant-specific data for transport failures. Carried on the `Result` error
rail as part of `ClientError`.

```nim
type TransportError* = object
  message*: string  ## human-readable error description
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard
```

**Design decisions:**

1. **Plain object (not `CatchableError`).** Transport errors are carried on
   the `Result` error rail via `ClientError`, not raised as exceptions.

2. **`httpStatus` is `int`, not `UnsignedInt`.** HTTP status codes are standard
   integers (100–599). Using `UnsignedInt` would add unnecessary ceremony.

3. **`tekHttpStatus` scope.** For HTTP responses that fail at the HTTP level and
   do not carry a valid RFC 7807 problem details body. If the response has a
   valid problem details JSON body, it becomes a `RequestError` instead.

**Constructor helpers:**

```nim
func transportError*(kind: TransportErrorKind, message: string): TransportError =
  ## For non-HTTP-status transport errors.
  TransportError(kind: kind, message: message)

func httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  TransportError(kind: tekHttpStatus, message: message, httpStatus: status)
```

**Module:** `src/jmap_client/errors.nim`

### 8.3 RequestErrorType

**RFC reference:** §3.6.1 (request-level errors). RFC 7807 Problem Details.

```nim
type RequestErrorType* = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown
```

**Parsing function:**

```nim
func parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  strutils.parseEnum[RequestErrorType](raw, retUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.4 RequestError

**RFC reference:** §3.6.1, RFC 7807.

**Purpose:** Plain object representing a request-level error — an HTTP
response with `Content-Type: application/problem+json`. Carried on the
`Result` error rail as part of `ClientError`.

```nim
type RequestError* = object
  ## errorType is module-private — always derived from rawType via
  ## parseRequestErrorType. This seals the consistency invariant:
  ## errorType and rawType cannot diverge.
  errorType: RequestErrorType    ## module-private; derived from rawType
  rawType*: string               ## always populated — lossless round-trip
  status*: Opt[int]              ## RFC 7807 "status" field
  title*: Opt[string]            ## RFC 7807 "title" field
  detail*: Opt[string]           ## RFC 7807 "detail" field
  limit*: Opt[string]            ## which limit was exceeded (retLimit only)
  extras*: Opt[JsonNode]         ## non-standard fields, lossless preservation
```

No `message` field — the human-readable message is derived from the RFC 7807
fields via the `message` accessor function, avoiding duplication.

**Accessors:**

```nim
func errorType*(re: RequestError): RequestErrorType =
  ## Returns the parsed error type variant.
  re.errorType

func message*(re: RequestError): string =
  ## Human-readable message via cascade: detail > title > rawType.
  re.detail.valueOr:
    re.title.valueOr:
      re.rawType
```

`message` prefers `detail` over `title` over `rawType` (following RFC 7807
guidance). Uses `valueOr` from nim-results for ergonomic fallback chains on
`Opt[T]`.

**Constructor helper:**

```nim
func requestError*(
    rawType: string,
    status: Opt[int] = Opt.none(int),
    title: Opt[string] = Opt.none(string),
    detail: Opt[string] = Opt.none(string),
    limit: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): RequestError =
  ## Auto-parses rawType string to the corresponding enum variant via
  ## parseRequestErrorType.
  return RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )
```

**Module:** `src/jmap_client/errors.nim`

### 8.5 ClientErrorKind

**RFC reference:** Not in RFC (library-internal).

```nim
type ClientErrorKind* = enum
  cekTransport
  cekRequest
```

**Module:** `src/jmap_client/errors.nim`

### 8.6 ClientError

**RFC reference:** Not in RFC (library-internal).

**Purpose:** The outer railway error type. Wraps either a `TransportError`
or a `RequestError`. Carried on the `Result` error rail as
`Result[T, ClientError]` (`JmapResult[T]` alias). When present on the error
rail, no method responses exist — the entire request failed at the transport
or protocol level.

```nim
type ClientError* = object
  ## Outer railway error: either a transport failure or a JMAP request rejection.
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError
```

No `message` field — the human-readable message is derived from the variant's
data via the `message` accessor function, avoiding duplication.

**Constructor helpers:**

```nim
func clientError*(transport: TransportError): ClientError =
  ## Lifts a transport failure into the outer railway.
  ClientError(kind: cekTransport, transport: transport)

func clientError*(request: RequestError): ClientError =
  ## Lifts a request rejection into the outer railway.
  ClientError(kind: cekRequest, request: request)
```

**Accessor helper:**

```nim
func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport: err.transport.message
  of cekRequest: err.request.message
```

For `cekRequest`, delegates to `RequestError.message` (which applies the
cascade: `detail` > `title` > `rawType`).

**Bridge helpers (construction railway → outer railway):**

```nim
func validationToClientError*(ve: ValidationError): ClientError =
  ## Bridges the construction railway (ValidationError) to the outer railway
  ## (ClientError). For use with ``mapErr`` when a Layer 1 validation failure
  ## must be surfaced as a transport error.
  clientError(transportError(tekNetwork, ve.message))

func validationToClientErrorCtx*(ve: ValidationError, context: string): ClientError =
  ## Bridges with a context prefix prepended to the error message.
  clientError(transportError(tekNetwork, context & ve.message))
```

These are used in Layer 2/4 when a deserialization failure (which produces
`ValidationError`) must be surfaced on the outer railway (`ClientError`).

### 8.6a Exception Classification

**Purpose:** Maps `std/httpclient` exceptions to `ClientError` values for the
outer railway. Pure function with no IO.

```nim
func classifyException*(e: ref CatchableError): ClientError =
  ## Maps std/httpclient exceptions to ClientError(cekTransport).
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
```

Exception type mapping:
- `TimeoutError` → `tekTimeout`
- `SslError` (when `defined(ssl)`) → `tekTls`
- `OSError` with TLS-related message → `tekTls` (heuristic)
- `OSError` → `tekNetwork`
- `IOError` → `tekNetwork`
- `ValueError` → `tekNetwork` (protocol error)
- Other → `tekNetwork` (unexpected error)

### 8.6b Request Context and Size Enforcement

**Purpose:** Shared utilities for request/response size enforcement.

```nim
type RequestContext* = enum
  ## Identifies the JMAP endpoint being processed.
  rcSession = "session"
  rcApi = "api"

func sizeLimitExceeded*(
    context: RequestContext, what: string, actual, limit: int
): ClientError =
  ## Constructs a ClientError for a size-limit violation.

func enforceBodySizeLimit*(
    maxResponseBytes: int, body: string, context: RequestContext
): Result[void, ClientError] =
  ## Phase 2 body size enforcement: post-read rejection via actual body
  ## length. No-op when maxResponseBytes == 0 (no limit). Pure.
```

**Module:** `src/jmap_client/errors.nim`

### 8.7 MethodErrorType

**RFC reference:** §3.6.2 (method-level errors), plus §5.1–5.6 (method-specific
error types).

**Purpose:** String-backed enum covering all 19 RFC-defined method-level error
types, plus `metUnknown`.

```nim
type MethodErrorType* = enum
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
  metTooManyChanges = "tooManyChanges"
  metRequestTooLarge = "requestTooLarge"
  metStateMismatch = "stateMismatch"
  metFromAccountNotFound = "fromAccountNotFound"
  metFromAccountNotSupportedByMethod = "fromAccountNotSupportedByMethod"
  metUnknown
```

**Parsing function:**

```nim
func parseMethodErrorType*(raw: string): MethodErrorType =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  strutils.parseEnum[MethodErrorType](raw, metUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.8 MethodError

**RFC reference:** §3.6.2.

**Purpose:** Per-invocation error within a JMAP response. This is response
data, NOT an exception — the HTTP request succeeded, but individual method
calls report errors.

```nim
type MethodError* = object
  ## errorType is module-private — always derived from rawType via
  ## parseMethodErrorType. This seals the consistency invariant.
  errorType: MethodErrorType     ## module-private; derived from rawType
  rawType*: string               ## always populated — lossless round-trip
  description*: Opt[string]      ## RFC "description" field
  extras*: Opt[JsonNode]         ## non-standard fields, lossless preservation
```

**Accessor:**

```nim
func errorType*(me: MethodError): MethodErrorType =
  ## Returns the parsed error type variant.
  me.errorType
```

**Constructor helper:**

```nim
func methodError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  ## Auto-parses rawType string to the corresponding enum variant via
  ## parseMethodErrorType.
  return MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )
```

**Module:** `src/jmap_client/errors.nim`

### 8.9 SetErrorType

**RFC reference:** §5.3 (/set errors), §5.4 (/copy errors), plus
RFC 8621 §2.3 (Mailbox/set), §4.6 (Email/set), §6 (Identity/set),
§7.5 (EmailSubmission/set).

The enum covers RFC 8620 core variants and RFC 8621 mail-specific
variants. The `"forbiddenFrom"` wire string is shared between
`Identity/set` (§6) and `EmailSubmission/set` (§7.5); a single enum
variant `setForbiddenFrom` covers both contexts — the calling method
determines which SHOULD-semantic applies.

```nim
type SetErrorType* = enum
  # RFC 8620 §5.3 / §5.4 — core
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
  # RFC 8621 §2.3 — Mailbox/set
  setMailboxHasChild = "mailboxHasChild"
  setMailboxHasEmail = "mailboxHasEmail"
  # RFC 8621 §4.6 — Email/set
  setBlobNotFound = "blobNotFound"
  setTooManyKeywords = "tooManyKeywords"
  setTooManyMailboxes = "tooManyMailboxes"
  # RFC 8621 §7.5 — EmailSubmission/set (and §6 Identity/set)
  setInvalidEmail = "invalidEmail"
  setTooManyRecipients = "tooManyRecipients"
  setNoRecipients = "noRecipients"
  setInvalidRecipients = "invalidRecipients"
  setForbiddenMailFrom = "forbiddenMailFrom"
  setForbiddenFrom = "forbiddenFrom"
  setForbiddenToSend = "forbiddenToSend"
  setCannotUnsend = "cannotUnsend"
  setUnknown
```

**Parsing function:**

```nim
func parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  return strutils.parseEnum[SetErrorType](raw, setUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.10 SetError

**RFC reference:** §5.3, §5.4, RFC 8621 §2.3 / §4.6 / §6 / §7.5.

**Purpose:** Per-item error within `/set` and `/copy` responses.
Response data, NOT an exception. A case object because the RFC mandates
variant-specific fields on six error types.

```nim
type SetError* = object
  rawType*: string                ## always populated — lossless round-trip
  description*: Opt[string]       ## optional human-readable description
  extras*: Opt[JsonNode]          ## non-standard fields, lossless preservation
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string]      ## RFC 8620 §5.3 SHOULD: invalid property names
  of setAlreadyExists:
    existingId*: Id               ## RFC 8620 §5.4 MUST: existing record's ID
  of setBlobNotFound:
    notFound*: seq[BlobId]        ## RFC 8621 §4.6 MUST: unresolved blob IDs
  of setInvalidEmail:
    invalidEmailPropertyNames*: seq[string]
                                  ## RFC 8621 §7.5 SHOULD: invalid Email property names
  of setTooManyRecipients:
    maxRecipientCount*: UnsignedInt
                                  ## RFC 8621 §7.5 MUST: server's recipient cap
  of setInvalidRecipients:
    invalidRecipients*: seq[string]
                                  ## RFC 8621 §7.5 MUST: addresses that failed validation
  of setTooLarge:
    maxSizeOctets*: Opt[UnsignedInt]
                                  ## RFC 8621 §7.5 SHOULD: size cap (octets)
  else:
    discard
```

**Public discriminator decision.** `errorType*` is exposed as a public
field rather than gated behind an accessor func because strict case
object flow analysis (`{.experimental: "strictCaseObjects".}`) cannot
trace through `func` bodies to prove which variant a given access
matches (Rule 3 in `nim-type-safety.md`). External consumers needing
to read variant-specific fields write `case se.errorType of setX:
se.variantField`, which strict only accepts when the discriminator is
a direct field access. The variant-specific smart constructors remain
the preferred construction path; the generic `setError` is reserved
for payload-less variants and defensively maps payload-bearing
`rawType` strings without wire data to `setUnknown`.

The variant-specific field names use long suffixes
(`invalidEmailPropertyNames`, `maxRecipientCount`, `maxSizeOctets`)
to avoid collision with mail-layer accessor names that share the
same concepts but live on entity types
(`invalidEmailProperties`, `maxRecipients`, `maxSize`).

**Constructor template helper:**

```nim
template seFieldsPlain(lit: untyped): SetError =
  ## Builds a payload-less SetError with a literal discriminator.
  ## Expanded inline at each `of X: seFieldsPlain(X)` call site in
  ## setError below — the literal substitution satisfies Nim's
  ## case-object construction rule (Pattern 4 in
  ## nim-functional-core.md: no runtime discriminator allowed).
  SetError(errorType: lit, rawType: rawType, description: description, extras: extras)
```

**Constructor helpers:**

```nim
func setError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError
  ## For non-variant-specific set errors. Defensively maps the six
  ## required-payload variants (invalidProperties, alreadyExists,
  ## blobNotFound, invalidEmail, tooManyRecipients, invalidRecipients)
  ## to setUnknown when variant-specific data is absent — use the
  ## setErrorXyz smart constructors to supply the payload. setTooLarge
  ## admits an absent maxSize (RFC 8621 §7.5 SHOULD, not MUST), so it
  ## is constructed with Opt.none here.

func setErrorInvalidProperties*(
    rawType: string, properties: seq[string], ...): SetError
  ## RFC 8620 §5.3 — invalid property names.

func setErrorAlreadyExists*(
    rawType: string, existingId: Id, ...): SetError
  ## RFC 8620 §5.4 — the existing record's ID.

func setErrorBlobNotFound*(
    rawType: string, notFound: seq[BlobId], ...): SetError
  ## RFC 8621 §4.6 — unresolved blob IDs.

func setErrorInvalidEmail*(
    rawType: string, propertyNames: seq[string], ...): SetError
  ## RFC 8621 §7.5 — invalid Email property names.

func setErrorTooManyRecipients*(
    rawType: string, cap: UnsignedInt, ...): SetError
  ## RFC 8621 §7.5 — server's recipient cap.

func setErrorInvalidRecipients*(
    rawType: string, addresses: seq[string], ...): SetError
  ## RFC 8621 §7.5 — recipient addresses that failed validation.

func setErrorTooLarge*(
    rawType: string,
    maxSize: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    ...): SetError
  ## RFC 8621 §7.5 (with optional maxSize). maxSize defaults to Opt.none
  ## so the RFC 8620 §5.3 core use of tooLarge without a cap is expressible.
```

**Design decision for `setError` defensive fallback:** If the server
sends a payload-bearing variant rawType without its required wire data,
the generic `setError` constructor falls back to `setUnknown`
(preserving `rawType`) rather than constructing the variant-specific
branch with empty/default values. Layer 2 calls the variant-specific
`setErrorXyz` constructors only when the JSON contains the required
fields; otherwise it calls `setError`, which maps the rawType to
`setUnknown`. `setTooLarge` is the exception — its `maxSizeOctets`
is `Opt[UnsignedInt]`, so absence is expressible.

**Module:** `src/jmap_client/errors.nim`

---

## 9. Method Names and Reference Paths

The `methods_enum.nim` module holds three enums that drive typed
construction of `Invocation` (§6.1) and `ResultReference` (§6.4).
Backing strings round-trip 1:1 with the wire format
(`$mnMailboxGet == "Mailbox/get"`), making serialisation
identity-functional.

### 9.1 MethodName

```nim
type MethodName* = enum
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

`mnUnknown` is the receive-side catch-all for forward-compatible
server method names (Postel's law). It has no backing string —
`$mnUnknown` falls back to the symbol name; it is never emitted
because only server replies populate it, and the verbatim wire
string is preserved on `Invocation.rawName` for lossless round-trip.

```nim
func parseMethodName*(raw: string): MethodName =
  ## Total — returns mnUnknown for any wire string that doesn't match
  ## a known backing literal. Used on the receive path
  ## (serde_envelope fromJson) to tag known methods without rejecting
  ## forward-compatible server extensions.
```

### 9.2 MethodEntity

```nim
type MethodEntity* = enum
  meCore
  meThread
  meIdentity
  meMailbox
  meEmail
  meVacationResponse
  meSearchSnippet
  meEmailSubmission
  meTest
```

The category tag returned by a `methodEntity[T]` overload (defined
per entity in higher layers). Used by `registerJmapEntity` as the
compile-time existence check — a type without a `methodEntity`
overload fails the register step before ever reaching the builder.
`meTest` is a sentinel for test-only fixture entities; production
dispatch never observes it because real builders are statically
typed to concrete entity types.

### 9.3 RefPath

```nim
type RefPath* = enum
  rpIds = "/ids"
  rpListIds = "/list/*/id"
  rpAddedIds = "/added/*/id"
  rpCreated = "/created"
  rpUpdated = "/updated"
  rpUpdatedProperties = "/updatedProperties"
  rpListThreadId = "/list/*/threadId"
  rpListEmailIds = "/list/*/emailIds"
```

The eight variants cover every JSON Pointer path the library emits in
result references. `rpListThreadId` and `rpListEmailIds` are
specialisations used by the mail-layer builders for chained references
(e.g. `Email/get → Thread/get`).

`initResultReference` (§6.4) consumes `RefPath` directly;
`parseResultReference` accepts arbitrary strings, and the
`ResultReference.path` accessor falls back to `rpIds` for unknown
wire paths (a path that the library did not emit and therefore should
never see in a server response).

**Module:** `src/jmap_client/methods_enum.nim`

---

## 10. Borrowed Operations Summary

| Type | `==` | `$` | `hash` | `len` | `<` | `<=` | unary `-` | mixed-int |
|------|:----:|:---:|:------:|:-----:|:---:|:----:|:---------:|:---------:|
| `Id` | Y | Y | Y | Y | | | | |
| `UnsignedInt` | Y | Y | Y | | Y | Y | | |
| `JmapInt` | Y | Y | Y | | Y | Y | Y | |
| `Date` | Y | Y | Y | Y | | | | |
| `UTCDate` | Y | Y | Y | Y | | | | |
| `MaxChanges` | Y | Y | Y | | Y | Y | | |
| `Idx` | Y | Y | Y | | Y | Y | | Y |
| `AccountId` | Y | Y | Y | Y | | | | |
| `JmapState` | Y | Y | Y | | | | | |
| `MethodCallId` | Y | Y | Y | | | | | |
| `CreationId` | Y | Y | Y | | | | | |
| `BlobId` | Y | Y | Y | | | | | |
| `PropertyName` | Y | Y | Y | Y | | | | |

`Idx` (§1.5) borrows int ops AND defines mixed-int comparison
operators (`Idx vs int` for `<`, `<=`, `>=`, `>`, `==`) to bridge
to stdlib APIs that still take raw `int`. It also defines `+`,
`succ`, `+=`.

`UriTemplate` is **not** in this table — it is a sealed object
(§5.2), not a `distinct string`. Its `==`, `$`, `hash` are explicit
funcs that compare against `rawSource`.

`CollationAlgorithm` (§4.4) is also not in this table — it is a
sealed case object. Its `==`, `$`, `hash` are explicit funcs that
dispatch on `rawKind`.

`NonEmptySeq[T]` (§2.7) borrows `==`, `$`, `hash`, `len` per
instantiation via `defineNonEmptySeqOps`; `[]` and `contains` are
explicit funcs.

All borrowed operations are `func`.

---

## 11. Smart Constructor Summary

| Type | Constructor | Validation | Behaviour |
|------|------------|-----------|-----------|
| `Id` | `parseId` | Strict: 1-255 octets, base64url charset | `Result[Id, ValidationError]` |
| `Id` | `parseIdFromServer` | Lenient: 1-255 octets, no control chars | `Result[Id, ValidationError]` |
| `UnsignedInt` | `parseUnsignedInt` | `0 <= value <= 2^53-1` | `Result[UnsignedInt, ValidationError]` |
| `JmapInt` | `parseJmapInt` | `-2^53+1 <= value <= 2^53-1` | `Result[JmapInt, ValidationError]` |
| `MaxChanges` | `parseMaxChanges` | Must be > 0 | `Result[MaxChanges, ValidationError]` |
| `Date` | `parseDate` | Structural RFC 3339 + timezone offset | `Result[Date, ValidationError]` |
| `UTCDate` | `parseUtcDate` | Date rules + ends with Z | `Result[UTCDate, ValidationError]` |
| `Idx` | `idx` | Compile-time non-negative literal | returns `Idx` (template) |
| `Idx` | `parseIdx` | Runtime non-negative | `Result[Idx, ValidationError]` |
| `NonEmptySeq[T]` | `parseNonEmptySeq` | `s.len > 0` | `Result[NonEmptySeq[T], ValidationError]` |
| `AccountId` | `parseAccountId` | Lenient: 1-255 octets, no control chars | `Result[AccountId, ValidationError]` |
| `JmapState` | `parseJmapState` | Non-empty, no control chars | `Result[JmapState, ValidationError]` |
| `MethodCallId` | `parseMethodCallId` | Non-empty | `Result[MethodCallId, ValidationError]` |
| `CreationId` | `parseCreationId` | Non-empty, no `#` prefix | `Result[CreationId, ValidationError]` |
| `BlobId` | `parseBlobId` | Lenient: 1-255 octets, no control chars | `Result[BlobId, ValidationError]` |
| `UriTemplate` | `parseUriTemplate` | Non-empty + RFC 6570 Level 1 structural | `Result[UriTemplate, ValidationError]` |
| `CapabilityKind` | `parseCapabilityKind` | Total (always succeeds) | returns `CapabilityKind` |
| `CollationAlgorithm` | `parseCollationAlgorithm` | Non-empty + printable ASCII | `Result[CollationAlgorithm, ValidationError]` |
| `Session` | `parseSession` | Core cap present, URLs valid, templates have variables, no newlines in apiUrl | `Result[Session, ValidationError]` |
| `Invocation` | `initInvocation` | Infallible — takes `MethodName` | returns `Invocation` |
| `Invocation` | `parseInvocation` | Non-empty rawName | `Result[Invocation, ValidationError]` |
| `ResultReference` | `initResultReference` | Infallible — takes `MethodName` and `RefPath` | returns `ResultReference` |
| `ResultReference` | `parseResultReference` | Non-empty rawName and rawPath | `Result[ResultReference, ValidationError]` |
| `PropertyName` | `parsePropertyName` | Non-empty | `Result[PropertyName, ValidationError]` |
| `Comparator` | `parseComparator` | Infallible (PropertyName enforces non-empty) | returns `Comparator` |
| `AddedItem` | `initAddedItem` | Infallible (Id and UnsignedInt pre-validated) | returns `AddedItem` |
| `MethodName` | `parseMethodName` | Total (always succeeds) | returns `MethodName` |
| `RequestErrorType` | `parseRequestErrorType` | Total (always succeeds) | returns `RequestErrorType` |
| `MethodErrorType` | `parseMethodErrorType` | Total (always succeeds) | returns `MethodErrorType` |
| `SetErrorType` | `parseSetErrorType` | Total (always succeeds) | returns `SetErrorType` |
| `TransportError` | `transportError` | None (total) | returns `TransportError` |
| `TransportError` | `httpStatusError` | None (total) | returns `TransportError` |
| `RequestError` | `requestError` | None (lossless round-trip) | returns `RequestError` |
| `ClientError` | `clientError` (2 overloads) | None (total) | returns `ClientError` |
| `ClientError` | `classifyException` | None (total) | returns `ClientError` |
| `ClientError` | `validationToClientError` | None (bridges ValidationError → ClientError) | returns `ClientError` |
| `ClientError` | `validationToClientErrorCtx` | None (bridges with context prefix) | returns `ClientError` |
| `MethodError` | `methodError` | None (lossless round-trip) | returns `MethodError` |
| `SetError` | `setError` | None (lossless + defensive fallback for 6 payload-bearing variants) | returns `SetError` |
| `SetError` | `setErrorInvalidProperties` | None (total) | returns `SetError` |
| `SetError` | `setErrorAlreadyExists` | None (total) | returns `SetError` |
| `SetError` | `setErrorBlobNotFound` | None (total) | returns `SetError` |
| `SetError` | `setErrorInvalidEmail` | None (total) | returns `SetError` |
| `SetError` | `setErrorTooManyRecipients` | None (total) | returns `SetError` |
| `SetError` | `setErrorInvalidRecipients` | None (total) | returns `SetError` |
| `SetError` | `setErrorTooLarge` | None (total) | returns `SetError` |

All domain type constructors are `func`. Smart constructors that validate
return `Result[T, ValidationError]`. Error type constructors return values
directly — error types cannot fail construction.

---

## 12. Module File Layout

```
src/jmap_client/
  validation.nim      <- ValidationError, borrow templates,
                         Idx (sealed non-negative index), TokenViolation
                         and atomic/composite token detectors,
                         validateUniqueByIt, Base64UrlChars,
                         nim-results re-export
  primitives.nim      <- Id, UnsignedInt, JmapInt, Date, UTCDate,
                         MaxChanges, NonEmptySeq[T] + DateViolation ADT
  identifiers.nim     <- AccountId, JmapState, MethodCallId, CreationId, BlobId
  collation.nim       <- CollationAlgorithmKind, CollationAlgorithm
                         (sealed sum type), 4 named constants,
                         CollationViolation ADT, parseCollationAlgorithm
  capabilities.nim    <- CapabilityKind, CoreCapabilities, ServerCapability
                         (re-exports collation)
  methods_enum.nim    <- MethodName, MethodEntity, RefPath, parseMethodName
  session.nim         <- Account, AccountCapabilityEntry, UriPart, UriTemplate
                         (sealed parsed object), Session (rawCore +
                         rawAdditional), expandUriTemplate, UriRole +
                         UriTemplateViolation + SessionViolation + CorePartition
  envelope.nim        <- Invocation, Request, Response,
                         ResultReference, Referencable[T]
                         (consumes MethodName / RefPath from methods_enum)
  framework.nim       <- PropertyName, FilterOperator, FilterKind, Filter[C],
                         Comparator, AddedItem, QueryParams
                         (re-exports collation)
  errors.nim          <- TransportErrorKind, TransportError,
                         RequestErrorType, RequestError,
                         ClientErrorKind, ClientError,
                         validationToClientError, validationToClientErrorCtx,
                         RequestContext, classifyException, sizeLimitExceeded,
                         enforceBodySizeLimit, isTlsRelatedMsg,
                         MethodErrorType, MethodError,
                         SetErrorType, SetError (RFC 8620 + RFC 8621 variants)
  types.nim           <- Re-exports all of the above + results (nim-results),
                         defines JmapResult[T] alias
```

### Import Graph

```
                  validation.nim                    (std/hashes, std/sequtils,
                  ^   ^    ^                         std/sets, results)
                  |   |    |
        primitives|   |    identifiers              (each: std/hashes; primitives
            ^     |   |        ^                     also std/sequtils)
            |     |   |        |
            |     |   |     collation               (std/hashes, std/strutils)
            |     |   |        ^
            |     |   |        |
            |     +---+--- capabilities             (std/strutils, std/sets,
            |     |            ^   ^                 std/json, results)
            |     |            |   |
            |     |            |   methods_enum     (no deps)
            |     |            |       ^
            |     |            |       |
            |     |    framework       |            (std/hashes; uses collation)
            |     |       ^            |
            |     |       |            |
            |     +---- session        |            (std/hashes, std/parseutils,
            |             ^            |             std/sets, std/strutils,
            |             |            |             std/tables, std/json)
            |             |            |
            +-- errors    +-- envelope ----+         (envelope: std/tables,
                                                       std/json, results)
                                                     (errors: std/strutils,
                                                       std/json, results, std/net)
                          |
                       types.nim                    (re-exports all + results)
```

All arrows point upward — no cycles. `validation.nim` is the root dependency.

- `primitives.nim` depends on `validation.nim` (for `Idx`,
  `defineStringDistinctOps`, `defineIntDistinctOps`, the
  token detectors, `ValidationError`, `Base64UrlChars`).
- `identifiers.nim` depends on `validation.nim` only.
- `collation.nim` depends on `validation.nim`.
- `capabilities.nim` depends on `primitives.nim` (for `UnsignedInt`)
  and `collation.nim`; re-exports `collation`.
- `methods_enum.nim` has no dependencies (pure enum module).
- `session.nim` depends on `validation.nim`, `identifiers.nim`,
  and `capabilities.nim` (for `CapabilityKind`, `ServerCapability`,
  `CoreCapabilities`).
- `envelope.nim` depends on `identifiers.nim`, `primitives.nim`,
  `methods_enum.nim`, and `validation.nim`.
- `framework.nim` depends on `validation.nim`, `primitives.nim`,
  and `collation.nim`; re-exports `collation`.
- `errors.nim` depends on `validation.nim` (for `ValidationError`),
  `primitives.nim` (for `Id`), `identifiers.nim` (for `BlobId`),
  and `results`.

**Re-export policy.** Individual modules generally do not re-export
their Layer 1 dependencies. The two exceptions are `capabilities.nim`
and `framework.nim`, which re-export `collation` because their
`CoreCapabilities.collationAlgorithms` and `Comparator.collation`
fields use `CollationAlgorithm` and consumers should not need a
separate import. Downstream code (Layer 2+, tests) should import
`types` for the full public API.

`types.nim` re-exports everything plus `results`:

```nim
import results

import ./validation
import ./primitives
import ./identifiers
import ./collation
import ./capabilities
import ./methods_enum
import ./session
import ./envelope
import ./framework
import ./errors

export results
export validation
export primitives
export identifiers
export collation
export capabilities
export methods_enum
export session
export envelope
export framework
export errors

type JmapResult*[T] = Result[T, ClientError]
  ## Outer railway: transport/request failure or typed success.
```

---

## 13. Test Fixtures

### 13.1 RFC §2.1 Session Example (Golden Test)

The complete Session JSON from RFC §2.1 (lines 742–816):

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
        "urn:ietf:params:jmap:mail": { },
        "urn:ietf:params:jmap:contacts": { }
      }
    },
    "A97813": {
      "name": "jane@example.com",
      "isPersonal": false,
      "isReadOnly": true,
      "accountCapabilities": {
        "urn:ietf:params:jmap:mail": { }
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

**Expected parsed values:**

- `session.capabilities` has 4 entries:
  - `kind: ckCore`, `rawUri: "urn:ietf:params:jmap:core"`, `core.maxSizeUpload == UnsignedInt(50000000)`
  - `kind: ckMail`, `rawUri: "urn:ietf:params:jmap:mail"`, `rawData: {}`
  - `kind: ckContacts`, `rawUri: "urn:ietf:params:jmap:contacts"`, `rawData: {}`
  - `kind: ckUnknown`, `rawUri: "https://example.com/apis/foobar"`, `rawData: {"maxFoosFinangled": 42}`
- `session.accounts` has 2 entries keyed by `AccountId("A13824")` and `AccountId("A97813")`
- `session.accounts["A13824"].isPersonal == true`
- `session.accounts["A13824"].accountCapabilities` has 2 entries (ckMail, ckContacts)
- `session.primaryAccounts["urn:ietf:params:jmap:mail"] == AccountId("A13824")`
- `session.username == "john@example.com"`
- `session.state == JmapState("75128aab4b1b")`
- `session.coreCapabilities.collationAlgorithms` contains `"i;ascii-numeric"`, `"i;ascii-casemap"`, `"i;unicode-casemap"`

**Note:** The RFC example has a typo: `"maxConcurrentRequest"` (singular)
instead of `"maxConcurrentRequests"` (plural, per the field definition in §2).
The deserialiser should accept both forms.

### 13.2 RFC §3.3.1 Request Example

```json
{
  "using": [ "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail" ],
  "methodCalls": [
    [ "method1", { "arg1": "arg1data", "arg2": "arg2data" }, "c1" ],
    [ "method2", { "arg1": "arg1data" }, "c2" ],
    [ "method3", {}, "c3" ]
  ]
}
```

- `request.using == @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"]`
- `request.methodCalls.len == 3`
- `request.methodCalls[0].rawName == "method1"` (verbatim wire string preserved; `.name` returns `mnUnknown`)
- `request.methodCalls[0].methodCallId == MethodCallId("c1")`
- `request.createdIds.isNone`

### 13.3 RFC §3.4.1 Response Example

```json
{
  "methodResponses": [
    [ "method1", { "arg1": 3, "arg2": "foo" }, "c1" ],
    [ "method2", { "isBlah": true }, "c2" ],
    [ "anotherResponseFromMethod2", { "data": 10, "yetmoredata": "Hello" }, "c2"],
    [ "error", { "type":"unknownMethod" }, "c3" ]
  ],
  "sessionState": "75128aab4b1b"
}
```

- `response.methodResponses.len == 4`
- `response.methodResponses[2].methodCallId == MethodCallId("c2")` (same as index 1 — multiple responses from one call)
- `response.methodResponses[3].rawName == "error"` (method-level error; `.name` returns `mnUnknown` because `"error"` is not a JMAP method name)
- `response.sessionState == JmapState("75128aab4b1b")`
- `response.createdIds.isNone`

### 13.4 Edge Cases per Type

| Type | Input | Expected | Reason |
|------|-------|----------|--------|
| `Id` (strict) | `""` | `err` | empty |
| `Id` (strict) | `"a" * 256` | `err` | exceeds 255 octets |
| `Id` (strict) | `"a" * 255` | `Id` | maximum valid length |
| `Id` (strict) | `"abc123-_XYZ"` | `Id` | all base64url chars |
| `Id` (strict) | `"abc=def"` | `err` | pad character not allowed |
| `Id` (strict) | `"abc def"` | `err` | space not allowed |
| `Id` (lenient) | `"abc+def"` | `Id` | lenient allows non-base64url |
| `Id` (lenient) | `"abc\x00def"` | `err` | control characters rejected |
| `Id` (lenient) | `"abc\x7Fdef"` | `err` | DEL rejected |
| `UnsignedInt` | `0` | `UnsignedInt` | minimum valid |
| `UnsignedInt` | `9007199254740991` | `UnsignedInt` | 2^53-1, maximum valid |
| `UnsignedInt` | `-1` | `err` | negative |
| `UnsignedInt` | `9007199254740992` | `err` | 2^53, exceeds maximum |
| `MaxChanges` | `UnsignedInt(1)` | `MaxChanges` | minimum valid |
| `MaxChanges` | `UnsignedInt(0)` | `err` | must be > 0 |
| `JmapInt` | `-9007199254740991` | `JmapInt` | -(2^53-1), minimum valid |
| `JmapInt` | `9007199254740991` | `JmapInt` | 2^53-1, maximum valid |
| `Date` | `"2014-10-30T14:12:00+08:00"` | `Date` | RFC example |
| `Date` | `"2014-10-30T14:12:00.123Z"` | `Date` | non-zero fractional seconds |
| `Date` | `"2014-10-30t14:12:00Z"` | `err` | lowercase 't' |
| `Date` | `"2014-10-30T14:12:00.000Z"` | `err` | zero frac must be omitted |
| `Date` | `"2014-10-30T14:12:00.Z"` | `err` | empty fractional part (no digits after dot) |
| `Date` | `"2014-10-30T14:12:00.0Z"` | `err` | zero fractional seconds must be omitted |
| `Date` | `"2014-10-30T14:12:00.100Z"` | `Date` | non-zero fractional (trailing zero is fine) |
| `Date` | `"2014-10-30T14:12:00z"` | `err` | lowercase 'z' |
| `Date` | `"2014-10-30"` | `err` | too short, missing time |
| `Date` | `"2014-10-30T14:12:00"` | `err` | missing timezone offset |
| `UTCDate` | `"2014-10-30T06:12:00Z"` | `UTCDate` | RFC example |
| `UTCDate` | `"2014-10-30T06:12:00+00:00"` | `err` | must be Z, not +00:00 |
| `CapabilityKind` | `"urn:ietf:params:jmap:core"` | `ckCore` | known URI |
| `CapabilityKind` | `"urn:ietf:params:jmap:mail"` | `ckMail` | known URI |
| `CapabilityKind` | `"https://vendor.example/ext"` | `ckUnknown` | vendor URI |
| `CapabilityKind` | `""` | `ckUnknown` | empty string |
| `CreationId` | `"#abc"` | `err` | must not include # prefix |
| `CreationId` | `"abc"` | `CreationId` | valid creation ID |
| `AccountId` | `""` | `err` | empty |
| `AccountId` | `"A13824"` | `AccountId` | valid (RFC §2.1 example) |
| `AccountId` | `"a" * 256` | `err` | exceeds 255 octets |
| `AccountId` | `"a" * 255` | `AccountId` | maximum valid length |
| `AccountId` | `"abc\x00def"` | `err` | control characters rejected |
| `AccountId` | `"abc\x7Fdef"` | `err` | DEL rejected |
| `JmapState` | `""` | `err` | empty |
| `JmapState` | `"75128aab4b1b"` | `JmapState` | valid (RFC §2.1 example) |
| `JmapState` | `"abc\x00def"` | `err` | control characters rejected |
| `JmapState` | `"abc\x7Fdef"` | `err` | DEL rejected |
| `Session` | missing core capability | `err` | RFC MUST constraint |
| `Session` | downloadUrl without `{blobId}` | `err` | RFC MUST constraint |
| `Session` | apiUrl with newline | `err` | newline characters rejected |
| `Session` | valid RFC §2.1 example | `Session` | golden test |
| `Session` | constructed directly without `ckCore` | impossible — `rawCore` is module-private and required at construction | invariant lifted into the type (no `AssertionDefect` path) |
| `coreCapabilities` (Session) | any `Session` produced by `parseSession` | total — returns `rawCore` | typed-field guarantee |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "urn:ietf:params:jmap:core")` | `some(...)` with `kind == ckCore` | core entry synthesised from `rawCore` |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "https://example.com/apis/foobar")` | `some(...)` with `kind == ckUnknown` | vendor extension lookup |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "urn:nonexistent")` | `none` | unknown URI |
| `findCapabilityByUri` (Account) | `findCapabilityByUri(account, "urn:ietf:params:jmap:mail")` | `some(...)` with `kind == ckMail` | known capability lookup |
| `primaryAccount` | `primaryAccount(session, ckMail)` | `some(AccountId("A13824"))` | known capability with primary account |
| `primaryAccount` | `primaryAccount(session, ckUnknown)` | `none` | ckUnknown has no canonical URI |
| `primaryAccount` | `primaryAccount(session, ckBlob)` | `none` | known capability without primary account |
| `UriTemplate` | `""` | `err` | empty input |
| `UriTemplate` | `"foo{"` | `err` | unmatched `{` |
| `UriTemplate` | `"foo{}"` | `err` | empty `{}` variable |
| `UriTemplate` | `"foo{a-b}"` | `err` | invalid character `-` in variable |
| `UriTemplate` | `"foo{a}/b/{c}"` | `UriTemplate` | two variables, two literals |
| `UriTemplate` | `"foo}bar"` | `UriTemplate` | stray `}` treated as literal |
| `PropertyName` | `""` | `err` | empty property name |
| `PropertyName` | `"name"` | `PropertyName` | valid property name |
| `Comparator` | `property: parsePropertyName("")` | `err` | empty property (PropertyName rejects) |
| `Comparator` | `property: parsePropertyName("name")` | `Comparator` | minimal valid |
| `Comparator` | `property: parsePropertyName("name"), collation: Opt.some(CollationUnicodeCasemap)` | `Comparator` | with collation |
| `CollationAlgorithm` | `""` | `err` | empty input |
| `CollationAlgorithm` | `"\x01illegal"` | `err` | non-printable byte |
| `CollationAlgorithm` | `"i;ascii-casemap"` | `CollationAsciiCasemap` | known IANA kind |
| `CollationAlgorithm` | `"i;vendor-custom"` | `CollationAlgorithm(rawKind: caOther, rawIdentifier: "i;vendor-custom")` | vendor extension with lossless round-trip |
| `Idx` | `idx(0)` | `Idx(0)` | compile-time non-negative literal |
| `Idx` | `idx(-1)` | compile error via `{.error.}` pragma | negative literal rejected at compile time |
| `Idx` | `parseIdx(0)` | `Idx(0)` | runtime minimum valid |
| `Idx` | `parseIdx(-5)` | `err` | runtime negative rejected on Result rail |
| `NonEmptySeq[int]` | `parseNonEmptySeq(@[])` | `err` | empty rejected |
| `NonEmptySeq[int]` | `parseNonEmptySeq(@[1])` | `NonEmptySeq[int](@[1])` | minimum valid |
| `BlobId` | `""` | `err` | empty |
| `BlobId` | `"BLOB-1234"` | `BlobId` | valid lenient token |
| `BlobId` | `"abc\x7Fdef"` | `err` | DEL rejected |
| `RequestErrorType` | `"urn:ietf:params:jmap:error:unknownCapability"` | `retUnknownCapability` | known URI |
| `RequestErrorType` | `"urn:ietf:params:jmap:error:notJSON"` | `retNotJson` | known URI |
| `RequestErrorType` | `"urn:vendor:custom:error"` | `retUnknown` | unknown URI |
| `RequestErrorType` | `""` | `retUnknown` | empty string |
| `MethodErrorType` | `"serverFail"` | `metServerFail` | known type |
| `MethodErrorType` | `"invalidArguments"` | `metInvalidArguments` | known type |
| `MethodErrorType` | `"customError"` | `metUnknown` | unknown type |
| `MethodErrorType` | `"fromAccountNotFound"` | `metFromAccountNotFound` | /copy method error |
| `MethodErrorType` | `"fromAccountNotSupportedByMethod"` | `metFromAccountNotSupportedByMethod` | /copy method error |
| `MethodErrorType` | `"tooManyChanges"` | `metTooManyChanges` | /queryChanges method error |
| `SetErrorType` | `"invalidProperties"` | `setInvalidProperties` | RFC 8620 §5.3 |
| `SetErrorType` | `"alreadyExists"` | `setAlreadyExists` | RFC 8620 §5.4 |
| `SetErrorType` | `"mailboxHasChild"` | `setMailboxHasChild` | RFC 8621 §2.3 |
| `SetErrorType` | `"blobNotFound"` | `setBlobNotFound` | RFC 8621 §4.6 |
| `SetErrorType` | `"tooManyRecipients"` | `setTooManyRecipients` | RFC 8621 §7.5 |
| `SetErrorType` | `"forbiddenFrom"` | `setForbiddenFrom` | shared §6 / §7.5 |
| `SetErrorType` | `"vendorSpecific"` | `setUnknown` | unknown type |
| `TransportError` | `transportError(tekTimeout, "timed out")` | valid, `kind == tekTimeout` | convenience constructor |
| `TransportError` | `httpStatusError(502, "Bad Gateway")` | valid, `httpStatus == 502` | HTTP status variant |
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest"))` | `errorType == retLimit`, rawType preserved | lossless round-trip |
| `RequestError` | `requestError("urn:vendor:custom")` | `errorType == retUnknown`, rawType preserved | unknown type preserved |
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest"), extras = Opt.some(%*{"requestId": "abc"}))` | extras preserved | lossless round-trip for extension members |
| `ClientError` | `clientError(transportError(tekNetwork, "refused"))` | `kind == cekTransport` | wrapping transport |
| `ClientError` | `clientError(requestError("...notJSON"))` | `kind == cekRequest` | wrapping request |
| `MethodError` | `methodError("unknownMethod")` | `errorType == metUnknownMethod` | lossless round-trip |
| `MethodError` | `methodError("custom", extras = Opt.some(%*{"hint": "retry"}))` | `errorType == metUnknown`, extras preserved | unknown with extras |
| `SetError` | `setError("forbidden")` | `errorType == setForbidden` | non-variant-specific |
| `SetError` | `setErrorInvalidProperties("invalidProperties", @["name"])` | `errorType == setInvalidProperties`, properties == @["name"] | RFC 8620 §5.3 variant |
| `SetError` | `setErrorAlreadyExists("alreadyExists", someId)` | `errorType == setAlreadyExists`, existingId == someId | RFC 8620 §5.4 variant |
| `SetError` | `setErrorBlobNotFound("blobNotFound", @[someBlobId])` | `errorType == setBlobNotFound`, notFound == @[someBlobId] | RFC 8621 §4.6 variant |
| `SetError` | `setErrorInvalidEmail("invalidEmail", @["from"])` | `errorType == setInvalidEmail`, invalidEmailPropertyNames == @["from"] | RFC 8621 §7.5 variant |
| `SetError` | `setErrorTooManyRecipients("tooManyRecipients", UnsignedInt(50))` | `errorType == setTooManyRecipients`, maxRecipientCount == 50 | RFC 8621 §7.5 variant |
| `SetError` | `setErrorInvalidRecipients("invalidRecipients", @["bad@x"])` | `errorType == setInvalidRecipients`, invalidRecipients == @["bad@x"] | RFC 8621 §7.5 variant |
| `SetError` | `setErrorTooLarge("tooLarge", maxSize = Opt.some(UnsignedInt(1024)))` | `errorType == setTooLarge`, maxSizeOctets == some(1024) | RFC 8621 §7.5 variant |
| `SetError` | `setErrorTooLarge("tooLarge")` | `errorType == setTooLarge`, maxSizeOctets == none | RFC 8620 §5.3 core (no cap) |
| `SetError` | `setError("invalidProperties")` (no properties) | `errorType == setUnknown`, rawType preserved | defensive fallback for missing payload |
| `SetError` | `setError("blobNotFound")` (no notFound) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("invalidEmail")` (no propertyNames) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("tooManyRecipients")` (no cap) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("invalidRecipients")` (no addresses) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("alreadyExists")` (no existingId) | `errorType == setUnknown`, rawType preserved | defensive fallback for alreadyExists |
| `SetError` | `setError("tooLarge")` | `errorType == setTooLarge`, maxSizeOctets == none | RFC 8621 §7.5 SHOULD (cap optional) — no fallback |

---

## Appendix: RFC Section Cross-Reference

| Type | RFC Section |
|------|-------------|
| `Id` | RFC 8620 §1.2 |
| `Int` / `JmapInt` | RFC 8620 §1.3 |
| `UnsignedInt` | RFC 8620 §1.3 |
| `MaxChanges` | RFC 8620 §5.2 |
| `Date` | RFC 8620 §1.4 |
| `UTCDate` | RFC 8620 §1.4 |
| `Idx` | Not in RFC (library-internal sealed non-negative index) |
| `NonEmptySeq[T]` | Not in RFC (library-internal non-empty sequence) |
| `Session` | RFC 8620 §2 |
| `Account` | RFC 8620 §2 (nested in Session.accounts) |
| `AccountCapabilityEntry` | RFC 8620 §2 (Account.accountCapabilities entries) |
| `CoreCapabilities` | RFC 8620 §2 (nested in Session.capabilities["urn:ietf:params:jmap:core"]) |
| `Invocation` | RFC 8620 §3.2 |
| `Request` | RFC 8620 §3.3 |
| `Response` | RFC 8620 §3.4 |
| `ResultReference` | RFC 8620 §3.7 |
| `CapabilityKind` (registry) | RFC 8620 §9.4 |
| `CollationAlgorithm` | RFC 8620 §5.1.3, RFC 4790 / RFC 5051 |
| `MethodName` | RFC 8620 §3.2 (Invocation element 1), RFC 8621 method registry |
| `MethodEntity` | Not in RFC (library-internal entity-category tag) |
| `RefPath` | RFC 8620 §3.7 (JSON Pointer paths emitted in result references) |
| `MethodCallId` | RFC 8620 §3.2 (element 3 of Invocation) |
| `CreationId` | RFC 8620 §3.3 (Request.createdIds), §5.3 (/set create) |
| `BlobId` | RFC 8620 §3.2 (blob references in download / upload / Email/import) |
| `AccountId` | RFC 8620 §1.6.2, §2 (Session.accounts keys) |
| `JmapState` | RFC 8620 §2 (Session.state), §3.4 (Response.sessionState), §5.1 (/get state) |
| `UriPart` / `UriTemplate` | RFC 8620 §2 (downloadUrl, uploadUrl, eventSourceUrl per RFC 6570 Level 1) |
| `Referencable[T]` | RFC 8620 §3.7 (back-reference mechanism) |
| `FilterOperator` | RFC 8620 §5.5 |
| `Filter[C]` | RFC 8620 §5.5 |
| `PropertyName` | RFC 8620 §5.5 (property name in Comparator) |
| `Comparator` | RFC 8620 §5.5 |
| `QueryParams` | RFC 8620 §5.5 (standard /query window parameters) |
| `AddedItem` | RFC 8620 §5.6 |
| `RequestErrorType` | RFC 8620 §3.6.1 |
| `RequestError` | RFC 8620 §3.6.1, RFC 7807 |
| `MethodErrorType` | RFC 8620 §3.6.2, §5.1–5.6 |
| `MethodError` | RFC 8620 §3.6.2 |
| `SetErrorType` | RFC 8620 §5.3 / §5.4 + RFC 8621 §2.3 / §4.6 / §6 / §7.5 |
| `SetError` | RFC 8620 §5.3 / §5.4 + RFC 8621 §2.3 / §4.6 / §6 / §7.5 |
| `TransportErrorKind` | Not in RFC (library-internal) |
| `TransportError` | Not in RFC (library-internal) |
| `ClientErrorKind` | Not in RFC (library-internal) |
| `ClientError` | Not in RFC (library-internal) |
| `RequestContext` | Not in RFC (library-internal endpoint tag) |
| `UploadResponse` | §6.1 (deferred — see architecture.md §4.6) |
| `Blob/copy` types | §6.3 (deferred — Layer 3 method types) |
