# Layer 1: Domain Types + Errors — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, smart constructor, and validation
rule for Layer 1 of the jmap-client library. It builds upon the decisions made in
`architecture-options.md` and resolves all deferred concrete choices so that
implementation is mechanical.

**Scope.** Layer 1 covers: primitive data types (RFC 8620 §1.2–1.4), domain
identifiers, the Session object and everything it contains (§2), the
Request/Response envelope (§3.2–3.4, §3.7), the generic method framework
types (§5.3 PatchObject, §5.5 Filter/Comparator, §5.6 AddedItem), and all
error types (TransportError, RequestError, ClientError, MethodError, SetError,
and the `JmapResult[T]` railway alias). Serialisation (Layer 2), protocol
logic (Layer 3), and transport (Layer 4) are out of scope. Binary data (§6)
and push (§7) are deferred; see architecture.md §4.5–4.6.

**Relationship to architecture-options.md.** That document records broad
decisions across all 5 layers. This document is the detailed specification for
Layer 1 only. Decisions here are consistent with — and build upon — the
architecture document's choices 1.1A, 1.2A, 1.6C, 1.7C, 1.3B, 3.2A, 3.3B, 3.4C, 3.7B, and 1.5B.

**Design principles.** Every decision follows:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `?` for
  early return. Smart constructors return `Result`, never raise.
- **Functional Core, Imperative Shell** — all Layer 1 code is `func` (pure, no
  side effects). `proc` appears only at the transport boundary (Layer 4).
- **Immutability by default** — `let` bindings. No mutable state in Layer 1.
  Local `var` inside `func` is permitted when building return values from
  stdlib containers whose APIs require mutation (e.g., `Table` in
  `PatchObject.setProp`). `strictFuncs` enforces the mutation does not escape.
- **Total functions** — `{.push raises: [].}` on every module. Every function
  has a defined output for every input. Functions that rely on
  constructor-guaranteed invariants (e.g., `coreCapabilities` depends on
  `parseSession` having validated `ckCore` presence) are total over the image
  of their smart constructor. If the invariant is violated by direct
  construction bypassing the smart constructor, `AssertionDefect` (a `Defect`,
  not `CatchableError`) terminates the process — this is deliberate: it
  signals a programming error, not a recoverable runtime condition. `Defect`s
  are outside the `Result`/`Opt` railway; they are Nim's equivalent of
  Haskell's `error` — a bottom value that should never be reachable in correct
  code.
- **Parse, don't validate** — smart constructors produce well-typed values or
  structured errors. Invariants enforced at construction time.
- **Make illegal states unrepresentable** — distinct types, case objects, and
  smart constructors encode domain invariants in the type system where the
  type system permits. Some invariants (e.g., `Invocation.arguments` must be
  a JSON object, not an array) are enforced at construction time by Layer 2
  parsing and Layer 3 builders rather than by the Layer 1 type definition,
  because `JsonNode` is an opaque stdlib type that cannot be further
  constrained without a wrapper. The principle guides type design; it does not
  guarantee that every conceivable illegal state is statically prevented.
- **Dual validation strictness** — accept server-generated data leniently
  (tolerating minor RFC deviations such as non-base64url ID characters),
  construct client-generated data strictly. Both paths return `Result` —
  neither silently accepts garbage. Strict constructors are used when the
  client creates values; lenient constructors are used during JSON
  deserialisation of server responses. This principle appears concretely in
  `Id` (§2.1: `parseId` vs `parseIdFromServer`), `AccountId` (§3.1), and
  `Session` cross-reference validation (§5.3).

**Compiler flags.** These constrain every type definition (from `jmap_client.nimble`):

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

Layer 1 maximises use of the Nim standard library. Every adoption and rejection
has a concrete reason tied to the strict compiler constraints.

### Modules used in Layer 1

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/hashes` | `Hash` type, `hash` borrowing for distinct types | Confirmed: `hash(distinctVal)` auto-delegates to base type via `{.borrow.}` |
| `std/tables` | `Table[AccountId, T]`, `Table[string, T]` | For `Session.accounts`, `Session.primaryAccounts`, `Request.createdIds`, `PatchObject` base type |
| `std/sets` | `HashSet[string]` | For `CoreCapabilities.collationAlgorithms` — proper set semantics (no duplicates, O(1) lookup) |
| `std/strutils` | `parseEnum[T](s, default)` | `func`, total, no exceptions — replaces manual `CapabilityKind` case statement |
| `std/json` | `JsonNode`, `JsonNodeKind` | For untyped capability data (`ServerCapability`), `Invocation.arguments` |
| `std/sequtils` | `allIt`, `anyIt` | Predicate templates that expand inline — work inside `func`. Architecture convention: prefer `collect` from `std/sugar` over `mapIt`/`filterIt` for collection building in Layers 2+. Layer 1 has no collection-building operations. |
| built-in `set[char]` | Charset validation constants | `{'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}` for `Id` validation |

### Modules evaluated and rejected

| Module | Reason not used in Layer 1 |
|--------|---------------------------|
| `std/times` | `times.parse` is `proc` not `func` (line 2245 of times.nim). Calling it from Layer 1 violates functional core purity. A convenience `toDateTime` converter may be provided in a separate utility module outside the pure core. |
| `std/parseutils` | `skipWhile` is `proc` not `func` (line 325 of parseutils.nim). Cannot call from smart constructors under `strictFuncs`. Pattern replicated using `allIt` template from sequtils. |
| `std/uri` | `parseUri` raises `UriParseError`. `apiUrl` is passed directly to the HTTP client — no need to decompose. |
| `std/options` | Project convention: `Opt[T]` from `nim-results` package (status-im/nim-results). `Opt[T]` is `Result[T, void]`, sharing the `?` operator with `Result[T, E]` for uniform ROP composition. stdlib `Option[T]` has `map`/`flatMap` but no `?` integration. |
| `std/enumutils` | `parseEnum` from `strutils` covers parsing. `symbolName` returns the symbolic name (vs `$` which returns the backing string), but symbolic names are not needed in Layer 1. |
| `std/httpcore` | `HttpCode` is relevant to Layer 4 (transport errors), not Layer 1. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `{.requiresInit.}` works on distinct types (verified in system.nim) | Enforced on all distinct types — prevents default construction |
| `hash` auto-borrows for distinct types (verified in hashes.nim) | No manual `hash` implementation needed — `{.borrow.}` suffices |
| `$` for string-backed enums returns the **backing string**, not the symbolic name; `symbolName` from `std/enumutils` returns the symbolic name | `$ckCore` returns `"urn:ietf:params:jmap:core"`. However `$ckUnknown` returns `"ckUnknown"` (no backing string), requiring custom `func capabilityUri(kind): Opt[string]` to force callers to handle `ckUnknown` |
| `parseEnum[T](s, default)` is a `func` (strutils.nim line 1326) | Total, no exceptions — can be called from pure code |
| `parseEnum` matches against **both** symbolic names and string backing values | Negligible risk: JMAP servers send URIs, not Nim identifiers |
| `RangeDefect` bypasses `{.push raises: [].}` (Defect, not CatchableError) | Range types are technically `raises: []` compatible but crash instead of returning `Result` |
| `allIt` is a template (sequtils.nim line 811) | Expands inline — works inside `func` for charset validation |
| `allIt` on empty seq returns `true` (vacuous truth) | Callers must guard `allIt` predicate checks with a non-empty check when an empty input requires a different error. Date parser guards `allIt(it == '0')` with `dotEnd == 20` check |
| Defects (RangeDefect, FieldDefect, AssertionDefect) are fatal | They bypass raises tracking — not suitable for expected runtime failures |

---

## 1. Validation Infrastructure

### 1.1 ValidationError

RFC reference: not applicable (library-internal type).

`ValidationError` is the error type for Layer 1 smart constructors. It carries
enough context to produce a useful error message without requiring the caller to
know which constructor failed.

```nim
type ValidationError* = object
  typeName*: string   ## which type failed ("Id", "UnsignedInt", etc.)
  message*: string    ## what went wrong ("length must be 1-255")
  value*: string      ## the raw input that failed validation
```

Constructor helper:

```nim
func validationError*(typeName, message, value: string): ValidationError =
  ValidationError(typeName: typeName, message: message, value: value)
```

`ValidationError` has no smart constructor — it is always valid by construction.
`ValidationError` is the error type for smart constructor failures (Layer 1
construction-time validation). `ClientError` (Section 8.6) is a separate
concern for runtime transport/request failures (Layer 4). These are different
railways and are not unified into a single sum type (Decision 1.6C).

**Module:** `src/jmap_client/validation.nim`

### 1.2 Smart Constructor Pattern

Every type with construction-time invariants has a smart constructor following
this pattern:

```nim
func parseFoo*(raw: InputType): Result[Foo, ValidationError]
```

- Always a `func` (pure, no side effects).
- Always returns `Result` (total, never raises).
- For distinct types (e.g., `Id`, `UnsignedInt`, `Date`), the raw constructor
  is the base type conversion (`string(x)` or `int64(x)`), which is not
  accessible outside the defining module without explicit borrowing. Only the
  smart constructor is public.
- For non-distinct object types (e.g., `Session`, `Comparator`), Nim cannot
  prevent direct construction via `Session(field1: val1, ...)` when fields are
  public — `{.requiresInit.}` prevents implicit default construction but not
  explicit construction. The smart constructor enforces invariants that direct
  construction does not. Functions that depend on these invariants (e.g.,
  `coreCapabilities`) use `raiseAssert` for the unreachable branch (see the
  "Total functions" scoping clause in Design principles).
- For types with no invariants beyond their constituent types, the raw
  constructor may be exported directly.

### 1.3 Borrow Templates

To reduce boilerplate, two templates define the standard borrowed operations for
distinct types. Uses `std/hashes` for the `Hash` type.

```nim
import std/hashes

template defineStringDistinctOps*(T: typedesc) =
  func `==`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}
  func len*(a: T): int {.borrow.}

template defineIntDistinctOps*(T: typedesc) =
  func `==`*(a, b: T): bool {.borrow.}
  func `<`*(a, b: T): bool {.borrow.}
  func `<=`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}
```

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
type Id* {.requiresInit.} = distinct string
defineStringDistinctOps(Id)
```

**Charset constant (built-in `set[char]`):**

```nim
const Base64UrlChars* = {'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}
```

**Smart constructors:**

Two constructors following the dual validation strictness principle (see
Design principles):

```nim
func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("Id", "length must be 1-255 octets", raw))
  if not raw.allIt(it in Base64UrlChars):
    return err(validationError("Id", "contains characters outside base64url alphabet", raw))
  ok(Id(raw))

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("Id", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("Id", "contains control characters", raw))
  ok(Id(raw))
```

**Rationale for dual constructors.** The RFC MUST constraint is 1–255 octets
and base64url charset. In practice, some servers send IDs with characters
outside this set. Refusing to parse the entire server response because of an
ID charset violation makes the library unusable with those servers. Both
constructors return `Result` — neither silently accepts garbage (empty strings,
control characters). The strict constructor is used when the client constructs
IDs; the lenient constructor is used during JSON deserialisation of server
responses.

**Module:** `src/jmap_client/primitives.nim`

### 2.2 UnsignedInt

**RFC reference:** §1.3 (lines 326–327).

An `Int` in the range `0 <= value <= 2^53-1`.

**Type definition:**

```nim
type UnsignedInt* {.requiresInit.} = distinct int64
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
  ok(UnsignedInt(value))
```

**Decision D1 rationale.** `range[0'i64..9007199254740991'i64]` was rejected
because violations raise `RangeDefect` (a `Defect`, fatal, uncatchable). This
crashes the process instead of returning a structured error. While `RangeDefect`
bypasses `{.push raises: [].}` tracking (the compiler permits it), it violates
the principle of graceful error handling via `Result`. A JMAP client must not
crash because a server sent a malformed integer.

**Module:** `src/jmap_client/primitives.nim`

### 2.3 JmapInt

**RFC reference:** §1.3 (lines 322–324).

An integer in the range `-2^53+1 <= value <= 2^53-1`. The safe range for
integers stored in a floating-point double.

**Type definition:**

```nim
type JmapInt* {.requiresInit.} = distinct int64
defineIntDistinctOps(JmapInt)
func `-`*(a: JmapInt): JmapInt {.borrow.}  ## unary negation
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
  ok(JmapInt(value))
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
type Date* {.requiresInit.} = distinct string
defineStringDistinctOps(Date)
```

**Smart constructor:**

Validation is decomposed into three private helpers returning
`Result[void, ValidationError]`, composed in `parseDate` via the `?` operator
for early-return on first failure.

```nim
const AsciiDigits = {'0'..'9'}

func validateDatePortion(raw: string): Result[void, ValidationError] =
  ## YYYY-MM-DD at positions 0..9.
  if not (
    raw[0 .. 3].allIt(it in AsciiDigits) and raw[4] == '-' and
    raw[5 .. 6].allIt(it in AsciiDigits) and raw[7] == '-' and
    raw[8 .. 9].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid date portion", raw))
  ok()

func validateTimePortion(raw: string): Result[void, ValidationError] =
  ## HH:MM:SS at positions 11..18, with uppercase 'T' separator at 10.
  if raw[10] != 'T':
    return err(validationError("Date", "'T' separator must be uppercase", raw))
  if not (
    raw[11 .. 12].allIt(it in AsciiDigits) and raw[13] == ':' and
    raw[14 .. 15].allIt(it in AsciiDigits) and raw[16] == ':' and
    raw[17 .. 18].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid time portion", raw))
  if raw.anyIt(it in {'t', 'z'}):
    return err(validationError("Date", "'T' and 'Z' must be uppercase (RFC 3339)", raw))
  ok()

func validateFractionalSeconds(raw: string): Result[void, ValidationError] =
  ## If a '.' follows position 19, digits must follow and not all be zero.
  if raw.len > 19 and raw[19] == '.':
    let dotEnd = block:
      var i = 20
      while i < raw.len and raw[i] in AsciiDigits:
        inc i
      i
    if dotEnd == 20:
      return err(
        validationError(
          "Date", "fractional seconds must contain at least one digit", raw
        )
      )
    if raw[20 ..< dotEnd].allIt(it == '0'):
      return
        err(validationError("Date", "zero fractional seconds must be omitted", raw))
  ok()

func parseDate*(raw: string): Result[Date, ValidationError] =
  ## Structural validation of an RFC 3339 date-time string.
  ## Does NOT perform calendar validation (e.g., February 30) or
  ## validate timezone offset format beyond uppercase checks.
  if raw.len < 20:
    return err(validationError("Date", "too short for RFC 3339 date-time", raw))
  ?validateDatePortion(raw)
  ?validateTimePortion(raw)
  ?validateFractionalSeconds(raw)
  ok(Date(raw))
```

**Decision D3 rationale.** `std/times.DateTime` was evaluated but rejected for
Layer 1 because `times.parse` is a `proc` (not `func`), violating functional
core purity. Additionally, `distinct string` preserves the exact server
representation for lossless round-trip. A convenience converter
`func toDateTime*(d: Date): DateTime` may be provided in a separate utility
module that imports `std/times`, outside the pure Layer 1 core.

**Module:** `src/jmap_client/primitives.nim`

### 2.5 UTCDate

**RFC reference:** §1.4 (lines 351–353).

A `Date` where the `time-offset` component MUST be `Z` (UTC time).

Example: `"2014-10-30T06:12:00Z"`.

**Type definition:**

```nim
type UTCDate* {.requiresInit.} = distinct string
defineStringDistinctOps(UTCDate)
```

**Smart constructor:**

```nim
func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## All Date validation rules, plus: must end with 'Z'.
  let dateResult = parseDate(raw)
  if dateResult.isErr:
    return err(dateResult.error)
  if raw[^1] != 'Z':
    return err(validationError("UTCDate", "time-offset must be 'Z'", raw))
  ok(UTCDate(raw))
```

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
type AccountId* {.requiresInit.} = distinct string
defineStringDistinctOps(AccountId)
```

**Smart constructor:**

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("AccountId", "contains control characters", raw))
  ok(AccountId(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.2 JmapState

**RFC reference:** §2 (Session.state), §5.1 (/get response `state`), §5.2
(/changes `sinceState`).

An opaque state token generated by the server. Changes when the data it
represents changes. Used for change detection and delta synchronisation.

```nim
type JmapState* {.requiresInit.} = distinct string
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
  if raw.len == 0:
    return err(validationError("JmapState", "must not be empty", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("JmapState", "contains control characters", raw))
  ok(JmapState(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.3 MethodCallId

**RFC reference:** §3.2 (Invocation, element 3).

An arbitrary string from the client, echoed back in the response. Used to
correlate responses to method calls.

```nim
type MethodCallId* {.requiresInit.} = distinct string
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
  if raw.len == 0:
    return err(validationError("MethodCallId", "must not be empty", raw))
  ok(MethodCallId(raw))
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.4 CreationId

**RFC reference:** §3.3 (Request.createdIds), §5.3 (/set `create` argument).

A client-generated identifier for a record being created. On the wire, creation
IDs are prefixed with `#` when used as forward references. The stored value does
NOT include the `#` prefix — that is a serialisation concern (Layer 2).

```nim
type CreationId* {.requiresInit.} = distinct string
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
  if raw.len == 0:
    return err(validationError("CreationId", "must not be empty", raw))
  if raw[0] == '#':
    return err(validationError("CreationId", "must not include '#' prefix", raw))
  ok(CreationId(raw))
```

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
carry `{.requiresInit.}` and cannot be default-constructed. `seq` operations
(`setLen`, `reset`) must default-construct elements, so the default
`CapabilityKind` must select the `else` branch — whose `rawData: JsonNode` is
nil-safe. Placing `ckMail` first satisfies this constraint.

**Parsing (stdlib `parseEnum`):**

```nim
import std/strutils

func parseCapabilityKind*(uri: string): CapabilityKind =
  ## Maps a capability URI string to an enum value.
  ## Total function: always succeeds. Unknown URIs map to ckUnknown.
  ## Uses strutils.parseEnum which matches against the string backing values.
  strutils.parseEnum[CapabilityKind](uri, ckUnknown)
```

This is a single line, total, `func`, no exceptions. `parseEnum` with a
`default` parameter never raises — it returns the default on any unrecognised
input. It matches against both the symbolic names and the string backing values
of the enum (style-insensitive, first character case-sensitive). Since JMAP
servers send URIs (e.g., `"urn:ietf:params:jmap:core"`) and never Nim symbolic
names, the dual matching is not a practical concern.

**Serialisation (reverse direction):**

`$ckCore` returns `"urn:ietf:params:jmap:core"` (the backing string).
However, `$ckUnknown` returns `"ckUnknown"` (no backing string assigned),
which is not a valid capability URI. A function returning `Opt[string]`
forces callers to handle `ckUnknown` explicitly rather than silently
using an invalid lookup key. `Opt` composes with the `?` operator,
avoiding sentinel values like `""`:

```nim
func capabilityUri*(kind: CapabilityKind): Opt[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns err() for ckUnknown — callers must use rawUri from ServerCapability.
  case kind
  of ckCore: ok("urn:ietf:params:jmap:core")
  of ckMail: ok("urn:ietf:params:jmap:mail")
  of ckSubmission: ok("urn:ietf:params:jmap:submission")
  of ckVacationResponse: ok("urn:ietf:params:jmap:vacationresponse")
  of ckWebsocket: ok("urn:ietf:params:jmap:websocket")
  of ckMdn: ok("urn:ietf:params:jmap:mdn")
  of ckSmimeVerify: ok("urn:ietf:params:jmap:smimeverify")
  of ckBlob: ok("urn:ietf:params:jmap:blob")
  of ckQuota: ok("urn:ietf:params:jmap:quota")
  of ckContacts: ok("urn:ietf:params:jmap:contacts")
  of ckCalendars: ok("urn:ietf:params:jmap:calendars")
  of ckSieve: ok("urn:ietf:params:jmap:sieve")
  of ckUnknown: err()
```

**Decision D5 rationale.** Comprehensive enum (all IANA-registered URIs) rather
than minimal (`ckCore`, `ckUnknown`). Real servers return `urn:ietf:params:jmap:mail`
etc. in Session responses. With a minimal enum, these lose structured identity
(all become `ckUnknown`). The IANA JMAP Capabilities Registry grows slowly
(~1–2 entries per year); the enum is stable.

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
  collationAlgorithms*: HashSet[string]  ## Collation algorithm identifiers (RFC 4790)
```

**No smart constructor.** The `UnsignedInt` fields enforce their own invariants
via their smart constructors. Construction happens exclusively during JSON
deserialisation (Layer 2), which validates each field individually.

**Decision D6.** `HashSet[string]` from `std/sets` for `collationAlgorithms`
instead of `seq[string]`. The RFC defines this as a list of identifiers for
membership testing ("does the server support this collation?"). `HashSet`
provides: no duplicates, O(1) lookup via `in`, proper set semantics. Layer 2
deserialises the JSON array into a `HashSet`.

**Helper:**

```nim
func hasCollation*(caps: CoreCapabilities, algorithm: string): bool =
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

**Asymmetry with `ServerCapability`.** `ServerCapability` (§4.3) is a case
object with a typed `ckCore` branch because RFC 8620 §2 defines 8 specific
fields for server-level core capabilities. `AccountCapabilityEntry` is a flat
object storing all account-level capability data as raw `JsonNode` because
RFC 8620 defines no typed fields for account-level capabilities — the
structure is entirely capability-specific. This asymmetry is intentional and
RFC-driven. When typed account-level capabilities are added (e.g., RFC 8621
mail capabilities include `maxMailboxDepth`, `maxMailboxesPerEmail`, etc.),
`AccountCapabilityEntry` may evolve to a case object with typed branches,
mirroring `ServerCapability`'s progressive branching pattern.

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
  for entry in account.accountCapabilities:
    if entry.kind == kind:
      return ok(entry)
  err()

func findCapabilityByUri*(account: Account, uri: string): Opt[AccountCapabilityEntry] =
  ## Looks up an account capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to
  ## ckUnknown and would be ambiguous via findCapability).
  for entry in account.accountCapabilities:
    if entry.rawUri == uri:
      return ok(entry)
  err()

func hasCapability*(account: Account, kind: CapabilityKind): bool =
  account.accountCapabilities.anyIt(it.kind == kind)
```

**`findCapability` note.** `findCapability(account, ckUnknown)` returns the
first entry with `kind == ckUnknown`. When multiple vendor extensions are
present, use `findCapabilityByUri` instead.

**No standalone smart constructor.** Accounts are validated as part of Session
parsing.

**Module:** `src/jmap_client/session.nim`

### 5.2 UriTemplate

**RFC reference:** §2 (Session.downloadUrl, uploadUrl, eventSourceUrl are URI
Templates per RFC 6570 Level 1).

```nim
type UriTemplate* {.requiresInit.} = distinct string
defineStringDistinctOps(UriTemplate)
```

**Smart constructor:**

```nim
func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError] =
  ## Non-empty. No RFC 6570 parsing — template expansion is Layer 4 (IO).
  if raw.len == 0:
    return err(validationError("UriTemplate", "must not be empty", raw))
  ok(UriTemplate(raw))
```

**Variable presence check:**

```nim
func hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## Checks if the template contains {name}. Simple string search.
  let target = "{" & name & "}"
  target in string(tmpl)
```

Used by the Session smart constructor to verify required template variables.

**Decision D11 rationale.** `std/uri.parseUri` raises `UriParseError` — not
suitable for the functional core. Template expansion (substituting `{accountId}`
etc.) is an IO concern belonging to Layer 4 (transport). Layer 1 stores the
template as a validated string and provides structural checks.

**Module:** `src/jmap_client/session.nim`

### 5.3 Session

**RFC reference:** §2 (lines 477–721).

The JMAP Session resource. Contains server capabilities, user accounts, API
endpoint URLs, and session state.

**Type definition:**

```nim
import std/tables

type Session* = object
  capabilities*: seq[ServerCapability]         ## server-level capabilities
  accounts*: Table[AccountId, Account]            ## keyed by AccountId
  primaryAccounts*: Table[string, AccountId]   ## keyed by raw capability URI
  username*: string                            ## or empty string if none
  apiUrl*: string                              ## URL for JMAP API requests
  downloadUrl*: UriTemplate                    ## RFC 6570 Level 1 template
  uploadUrl*: UriTemplate                      ## RFC 6570 Level 1 template
  eventSourceUrl*: UriTemplate                 ## RFC 6570 Level 1 template
  state*: JmapState                            ## session state token
```

All fields are required per the RFC. `accounts` uses `AccountId` keys —
`AccountId` has borrowed `==`, `$`, and `hash`, making it a valid `Table`
key with no collision risk. `primaryAccounts` uses raw `string` keys (not
`CapabilityKind`) to avoid the `ckUnknown` key collision problem (see §4.1
CRITICAL note).

**Design note: `seq` vs `Table` for capability collections.**
`capabilities` and `accountCapabilities` use `seq` rather than `Table` for
two reasons: (1) `CapabilityKind` cannot be a table key because multiple
vendor extensions map to `ckUnknown`, causing collisions; (2) `Table[string,
ServerCapability]` or `Table[string, AccountCapabilityEntry]` would duplicate
the URI string (once as the table key, once inside the entry's `rawUri`
field). With `seq`, the URI lives in one place per entry. The trade-off is
that `findCapability` performs a linear scan, but capability lists are small
(typically fewer than 10 entries). `primaryAccounts` uses `Table[string,
AccountId]` because its values (`AccountId`) do not contain the URI — no
duplication — and its primary access pattern is O(1) key lookup ("which
account is primary for this capability URI?").

`apiUrl` is plain `string` rather than a distinct type because it is a
concrete URL with no RFC 6570 template variables — `UriTemplate` does not
apply, and the only Layer 1 invariant (non-empty) is enforced by
`parseSession`.

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
  ## 1. capabilities includes ckCore (RFC §2: MUST)
  ## 2. apiUrl is non-empty
  ## 3. downloadUrl contains {accountId}, {blobId}, {type}, {name} (RFC §2)
  ## 4. uploadUrl contains {accountId} (RFC §2)
  ## 5. eventSourceUrl contains {types}, {closeafter}, {ping} (RFC §2)
  if not capabilities.anyIt(it.kind == ckCore):
    return err(validationError("Session", "capabilities must include urn:ietf:params:jmap:core", ""))
  if apiUrl.len == 0:
    return err(validationError("Session", "apiUrl must not be empty", ""))
  for variable in ["accountId", "blobId", "type", "name"]:
    if not downloadUrl.hasVariable(variable):
      return err(validationError("Session", "downloadUrl missing {" & variable & "}", string(downloadUrl)))
  if not uploadUrl.hasVariable("accountId"):
    return err(validationError("Session", "uploadUrl missing {accountId}", string(uploadUrl)))
  for variable in ["types", "closeafter", "ping"]:
    if not eventSourceUrl.hasVariable(variable):
      return err(validationError("Session", "eventSourceUrl missing {" & variable & "}", string(eventSourceUrl)))
  ok(Session(
    capabilities: capabilities,
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: username,
    apiUrl: apiUrl,
    downloadUrl: downloadUrl,
    uploadUrl: uploadUrl,
    eventSourceUrl: eventSourceUrl,
    state: state,
  ))
```

**Decision D7 rationale (cross-reference leniency).** `parseSession`
deliberately does not validate two RFC cross-reference constraints:

1. **`primaryAccounts` values reference valid `accounts` keys.** RFC §2
   defines `primaryAccounts` as a map of capability URIs to account IDs
   (there MAY be no entry for a particular URI). The RFC does not
   explicitly constrain values to reference valid `accounts` keys.
   Rejecting the Session for a mismatch would break compatibility with
   servers that send inconsistent data.

2. **Account `accountCapabilities` keys present in `Session.capabilities`.**
   RFC §2 states these MUST match, but in practice servers may include
   per-account capabilities not yet in the top-level object (e.g., during
   rolling deployments or with vendor extensions).

This follows the dual validation strictness principle (see Design principles): accept server data leniently,
construct own data strictly. If stricter validation is later desired, provide
an opt-in `func validateSessionRefs*(session: Session): Result[void,
ValidationError]` rather than baking it into `parseSession`.

**Accessor helpers:**

```nim
func coreCapabilities*(session: Session): CoreCapabilities =
  ## Returns the core capabilities. Total function (no Result) because
  ## parseSession guarantees ckCore is present.
  for cap in session.capabilities:
    if cap.kind == ckCore:
      return cap.core
  # Unreachable if Session was constructed via parseSession.
  # AssertionDefect is a Defect (not CatchableError) — compatible with {.push raises: [].}.
  raiseAssert "Session missing ckCore: violated parseSession invariant"
```

**Invariant note.** `coreCapabilities` is total over Sessions constructed
via `parseSession`, which guarantees `ckCore` is present. Nim cannot prevent
direct construction of `Session` with public fields (see the "Total
functions" scoping clause in Design principles above). If `Session` is
constructed directly without `ckCore`, `coreCapabilities` raises
`AssertionDefect` — a `Defect` (fatal, not `CatchableError`), compatible
with `{.push raises: [].}`. This follows the same contract as Haskell's
`fromJust` or OCaml's `Option.get`: total over the smart constructor's
image, bottom otherwise. The re-export policy (§11) and module boundaries
are the practical enforcement mechanism — downstream code constructs
Sessions via Layer 2 deserialisation, which always calls `parseSession`.

```nim
func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  for cap in session.capabilities:
    if cap.kind == kind:
      return ok(cap)
  err()

func findCapabilityByUri*(session: Session, uri: string): Opt[ServerCapability] =
  ## Looks up a capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to
  ## ckUnknown and would be ambiguous via findCapability).
  for cap in session.capabilities:
    if cap.rawUri == uri:
      return ok(cap)
  err()

func primaryAccount*(session: Session, kind: CapabilityKind): Opt[AccountId] =
  let uri = ? capabilityUri(kind)
  for key, val in session.primaryAccounts:
    if key == uri:
      return ok(val)
  err()

func findAccount*(session: Session, id: AccountId): Opt[Account] =
  for key, val in session.accounts:
    if key == id:
      return ok(val)
  err()
```

**`findCapability` note.** `findCapability(session, ckUnknown)` returns the
first entry with `kind == ckUnknown`. When multiple vendor extensions are
present, use `findCapabilityByUri` instead.

**`primaryAccount` failure modes.** Returns `err()` in two cases: (1) `kind
== ckUnknown` (no canonical URI to look up — use `session.primaryAccounts`
directly with the raw URI string), or (2) no primary account is designated
for this capability (the URI is not a key in `primaryAccounts`). Callers who
need to distinguish these cases should check `capabilityUri(kind)` first.
For vendor extensions, access `session.primaryAccounts` directly with the
raw URI string.

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

type Invocation* = object
  name*: string             ## method name (request) or response name
  arguments*: JsonNode      ## named arguments — always a JObject
  methodCallId*: MethodCallId  ## correlates responses to requests
```

`arguments` is `JsonNode` at the envelope level. Typed extraction into
concrete method response types happens in Layer 3.

**Type precision note.** `arguments` is typed as `JsonNode` rather than a
wrapper enforcing `JObject` because the invariant is enforced by Layer 2
parsing and Layer 3 construction, not by Layer 1 types.

**No smart constructor.** Constructed by the Layer 3 builder (requests) or
Layer 2 deserialiser (responses).

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

`createdIds` is `Opt` because the RFC specifies it as optional. If present in
the request, the response will also include it.

**No smart constructor.** Built by the Layer 3 request builder.

**Module:** `src/jmap_client/envelope.nim`

### 6.3 Response

**RFC reference:** §3.4 (lines 975–1003).

```nim
type Response* = object
  methodResponses*: seq[Invocation]            ## same format as methodCalls
  createdIds*: Opt[Table[CreationId, Id]]      ## only if given in request
  sessionState*: JmapState                     ## current Session.state value
```

**No smart constructor.** Parsed from JSON by Layer 2.

**Module:** `src/jmap_client/envelope.nim`

### 6.4 ResultReference

**RFC reference:** §3.7 (lines 1220–1261).

Allows an argument to one method call to be taken from the result of a previous
method call in the same request. The client prefixes the argument name with `#`;
the value is a `ResultReference` object.

```nim
type ResultReference* = object
  resultOf*: MethodCallId  ## method call ID of previous call
  name*: string            ## expected response name
  path*: string            ## JSON Pointer (RFC 6901) with '*' array wildcard
```

**Path constants for common reference targets:**

```nim
const
  RefPathIds*                = "/ids"               ## IDs from /query result
  RefPathListIds*            = "/list/*/id"          ## IDs from /get result
  RefPathAddedIds*           = "/added/*/id"         ## IDs from /queryChanges result
  RefPathCreated*            = "/created"             ## created map from /changes or /set result
  RefPathUpdated*            = "/updated"             ## updated IDs from /changes result
  RefPathUpdatedProperties*  = "/updatedProperties"   ## updatedProperties from Mailbox/changes (RFC 8621 section 2.2)
```

**No smart constructor.** The server validates result references during
processing. Invalid references produce `invalidResultReference` method-level
errors.

**Module:** `src/jmap_client/envelope.nim`

### 6.5 Referencable[T]

**Architecture reference:** Decision 1.3B.

A variant type encoding the mutual exclusion between a direct value and a result
reference. Makes the illegal state "both direct value and reference" unrepresentable.

Isomorphic to Haskell's `Either T ResultReference`.

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

**Serialisation note (Layer 2).** `Referencable[seq[Id]]` serialises as either
`"ids": [...]` (direct) or `"#ids": {"resultOf": ..., "name": ..., "path": ...}`
(reference). The `#` prefix on the JSON key name is the discriminator on the
wire. This is a Layer 2 concern.

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

A recursive algebraic data type parameterised by condition type `C`. The Core
RFC defines the generic framework; entity-specific condition types (e.g.,
`MailboxFilterCondition` in RFC 8621) plug in as `C`.

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
`ref`. Verified: compiles under `--mm:arc` + `strictFuncs` + `strictCaseObjects`
+ `strictDefs`.

**Constructor helpers:**

```nim
func filterCondition*[C](cond: C): Filter[C] =
  Filter[C](kind: fkCondition, condition: cond)

func filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =
  Filter[C](kind: fkOperator, operator: op, conditions: conditions)
```

Total constructors. No validation needed — all inputs produce valid filters.

**Module:** `src/jmap_client/framework.nim`

### 7.2a PropertyName

**RFC reference:** §5.5 (property names in Comparator, referenced throughout).

A property name is a non-empty string identifying a field on an entity type.
Used in `Comparator.property` and potentially in future property-list
parameters.

**Type definition:**

```nim
type PropertyName* {.requiresInit.} = distinct string
defineStringDistinctOps(PropertyName)
```

Borrowed operations: `==`, `$`, `hash`, `len` (via `defineStringDistinctOps`).

**Smart constructor:**

```nim
func parsePropertyName*(raw: string): Result[PropertyName, ValidationError] =
  if raw.len == 0:
    return err(validationError("PropertyName", "must not be empty", raw))
  ok(PropertyName(raw))
```

**Module:** `src/jmap_client/framework.nim`

### 7.3 Comparator

**RFC reference:** §5.5. Determines the sort order for a `/query` request.

**Type definition:**

```nim
type Comparator* = object
  property*: PropertyName    ## property name to sort by
  isAscending*: bool         ## true = ascending (RFC default)
  collation*: Opt[string]    ## RFC 4790 collation algorithm identifier
```

`property` is a `PropertyName` (distinct string, non-empty) because every
Comparator must name a property. Entity-specific validity (which property
names are legal for a given entity type) is enforced by Layer 3 typed sort
builders, not at the Layer 1 type level.

`isAscending` defaults to `true` per RFC §5.5. The smart constructor mirrors
this default for convenience. Layer 2 deserialisation also applies this default
when the field is absent from JSON.

`collation` is `Opt[string]` because the RFC specifies it as optional. When
absent, the server uses its default collation for the property.

**Smart constructor:**

```nim
func parseComparator*(
  property: PropertyName,
  isAscending: bool = true,
  collation: Opt[string] = Opt.none(string)
): Result[Comparator, ValidationError] =
  ok(Comparator(property: property, isAscending: isAscending, collation: collation))
```

The non-empty property invariant is enforced by `PropertyName`'s smart
constructor (`parsePropertyName`). `parseComparator` is infallible given a
valid `PropertyName`. All other fields are unconstrained at the Core level.

**Module:** `src/jmap_client/framework.nim`

### 7.4 PatchObject

**RFC reference:** §5.3. A `PatchObject` is a map of JSON Pointer paths to
values, used in `/set` update operations.

**Type definition:**

```nim
import std/tables
import std/json

type PatchObject* {.requiresInit.} = distinct Table[string, JsonNode]
```

**Borrowed operations:**

```nim
func len*(p: PatchObject): int {.borrow.}
```

Only `len` is borrowed. `==`, `$`, and `hash` are not borrowed because
`PatchObject` equality and display are not needed in Layer 1. `[]=`, `del`,
`clear`, and all other mutating `Table` operations are deliberately excluded
— smart constructors (`setProp`, `deleteProp`) are the only write path,
ensuring path validation cannot be bypassed. Read-only table access (`[]`,
`hasKey`) is also not exported; all interaction goes through smart
constructors and `len`.

**Smart constructors:**

```nim
func emptyPatch*(): PatchObject =
  PatchObject(initTable[string, JsonNode]())

func setProp*(patch: PatchObject, path: string, value: JsonNode): Result[PatchObject, ValidationError] =
  ## Sets a property at the given JSON Pointer path.
  if path.len == 0:
    return err(validationError("PatchObject", "path must not be empty", ""))
  var t = Table[string, JsonNode](patch)
  t[path] = value
  ok(PatchObject(t))

func deleteProp*(patch: PatchObject, path: string): Result[PatchObject, ValidationError] =
  ## Sets a property to null (deletion in JMAP PatchObject semantics).
  if path.len == 0:
    return err(validationError("PatchObject", "path must not be empty", ""))
  var t = Table[string, JsonNode](patch)
  t[path] = newJNull()
  ok(PatchObject(t))
```

`setProp` and `deleteProp` copy the table to a local `var`, mutate it, and
rewrap. The input `PatchObject` is not modified. Under `--mm:arc`, the copy
uses move semantics when the caller does not retain the original. The local
`var` mutation is compatible with `func` under `strictFuncs` — mutation of
local variables (not parameters or globals) is permitted.

**Decision D8 rationale.** `distinct Table[string, JsonNode]` rather than plain
`Table[string, JsonNode]` per architecture Decision 1.5B. The `distinct` type
prevents passing an arbitrary table where a patch is expected, and the smart
constructors validate that paths are non-empty. Entity-specific typed patch
builders (architecture Decision 3.8A) will produce `PatchObject` values in
entity modules.

**Module:** `src/jmap_client/framework.nim`

### 7.5 AddedItem

**RFC reference:** §5.6. An element of the `added` array in a `/queryChanges`
response. Records that an item was added to the query results at a specific
position.

**Type definition:**

```nim
type AddedItem* = object
  id*: Id
  index*: UnsignedInt
```

**No smart constructor.** Both fields enforce their own invariants via their
respective smart constructors (`parseIdFromServer`, `parseUnsignedInt`).
Construction happens exclusively during JSON deserialisation (Layer 2).

**Module:** `src/jmap_client/framework.nim`

---

## 8. Error Types

Error types implement the three-track railway (architecture-options.md Decision
1.6C). The outer railway uses `JmapResult[T] = Result[T, ClientError]` for
transport/request failures. The inner railway uses `Result[T, MethodError]` per
invocation. `SetError` is data within successful `SetResponse` values.

All error constructors are `func` (pure) and return values directly — not
`Result`. Error types represent received data or classified exceptions; they
cannot fail construction. This contrasts with domain type smart constructors
(Sections 2–7) which return `Result[T, ValidationError]` because domain values
have invariants that can be violated.

All error types that carry a `type` string follow Decision 1.7C: a parsed enum
(`errorType`) alongside a preserved raw string (`rawType`) for lossless
round-trip. Serialisation always uses `rawType`, never `$errorType`.

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

**No smart constructor.** Plain enum, valid by construction. Constructed by
Layer 4 transport code when catching `CatchableError` from `std/httpclient`.

**Module:** `src/jmap_client/errors.nim`

### 8.2 TransportError

**RFC reference:** Not in RFC (library-internal type).

**Purpose:** Case object carrying a human-readable message and variant-specific
data for transport failures. The `tekHttpStatus` branch carries the HTTP status
code; other branches carry no additional data beyond the message.

```nim
type TransportError* = object
  message*: string
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard
```

**Design decisions:**

1. **`message` is a shared field** (outside the `case`), always accessible
   regardless of variant. It carries the underlying exception message from
   `std/httpclient` (e.g., `"Connection refused"`, `"certificate verify
   failed"`).

2. **`httpStatus` is `int`, not `UnsignedInt`.** HTTP status codes are standard
   integers (100–599). Using `UnsignedInt` (which requires a smart constructor
   returning `Result`) would add unnecessary ceremony for a field with no
   JMAP-specific semantics. The value comes directly from `std/httpclient`'s
   `HttpCode`.

3. **`tekHttpStatus` scope.** For HTTP responses that fail at the HTTP level and
   do not carry a valid RFC 7807 problem details body. If the response has a
   valid problem details JSON body, it becomes a `RequestError` instead (parsed
   by Layer 2). If the response is HTTP 200 with valid JMAP JSON, it is a
   success.

**Constructor helpers:**

```nim
func transportError*(kind: TransportErrorKind, message: string): TransportError =
  ## For non-HTTP-status transport errors.
  TransportError(kind: kind, message: message)

func httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  TransportError(kind: tekHttpStatus, message: message, httpStatus: status)
```

Plain `func` constructors, not `parseFoo`-style smart constructors returning
`Result`. There are no invariants that could fail at construction time. Follows
the pattern of `filterCondition`/`filterOperator` in Section 7.2.

**Construction layer:** Layer 4 (transport). The transport `proc` catches
`CatchableError` from `std/httpclient`, classifies the exception (e.g.,
`TimeoutError` → `tekTimeout`, `ProtocolError` → `tekNetwork`, SSL errors →
`tekTls`, non-200 HTTP status → `tekHttpStatus`), and constructs a
`TransportError`.

**Module:** `src/jmap_client/errors.nim`

### 8.3 RequestErrorType

**RFC reference:** §3.6.1 (request-level errors). RFC 7807 Problem Details.

**Purpose:** String-backed enum covering the four RFC-defined request-level
error types, plus `retUnknown` for server-specific extensions. Follows
Decision 1.7C.

```nim
type RequestErrorType* = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown
```

`retUnknown` has no string backing — it is the catch-all for unrecognised URIs.

**Parsing function:**

```nim
func parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  strutils.parseEnum[RequestErrorType](raw, retUnknown)
```

Same pattern as `parseCapabilityKind` (Section 4.1): total, uses
`strutils.parseEnum` with a default. The raw string is preserved separately
in `RequestError.rawType` (Section 8.4).

**Module:** `src/jmap_client/errors.nim`

### 8.4 RequestError

**RFC reference:** §3.6.1, RFC 7807.

**Purpose:** Represents a request-level error — an HTTP response with
`Content-Type: application/problem+json`. The server returns these when the
entire request is rejected before any method calls are processed.

```nim
type RequestError* = object
  errorType*: RequestErrorType   ## parsed enum variant
  rawType*: string               ## always populated — lossless round-trip
  status*: Opt[int]              ## RFC 7807 "status" field
  title*: Opt[string]            ## RFC 7807 "title" field
  detail*: Opt[string]           ## RFC 7807 "detail" field
  limit*: Opt[string]            ## which limit was exceeded (retLimit only)
  extras*: Opt[JsonNode]         ## non-standard fields, lossless preservation
```

**Design decisions:**

1. **Flat object, not a case object.** The `limit` field is relevant only for
   `retLimit`, but making it `Opt` on a flat object is simpler than a case
   object with four branches where only one has an extra field.

2. **`rawType` always populated (Decision 1.7C).** For known types, `rawType`
   contains the same URI as the enum's string backing. For `retUnknown`,
   `rawType` is the original unrecognised URI. Serialisation always uses
   `rawType`.

3. **`status` is `Opt[int]`, not `Opt[UnsignedInt]`.** Same rationale as
   `TransportError.httpStatus`.

4. **`extras: Opt[JsonNode]`.** RFC 7807 §3.1 allows extension members beyond
   the standard fields (`type`, `status`, `title`, `detail`, `instance`).
   Servers may include vendor-specific debugging fields (e.g., `requestId`,
   `timestamp`). The `extras` field preserves these for lossless round-trip,
   consistent with `MethodError` and `SetError` (Decision 1.7C). `Opt` rather
   than bare `JsonNode` because most errors have no extras.

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
  RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )
```

Encapsulates the lossless round-trip pattern: always populates both `errorType`
(parsed) and `rawType` (preserved) from the same input.

**Construction layer:** Layer 2 (serialisation). The `fromJson` for
`RequestError` extracts the `type` field from the RFC 7807 JSON body.

**Module:** `src/jmap_client/errors.nim`

### 8.5 ClientErrorKind

**RFC reference:** Not in RFC (library-internal). Decision 1.6C.

**Purpose:** Discriminator for the outer railway error type.

```nim
type ClientErrorKind* = enum
  cekTransport
  cekRequest
```

**No smart constructor.** Plain two-variant enum.

**Module:** `src/jmap_client/errors.nim`

### 8.6 ClientError

**RFC reference:** Not in RFC (library-internal). Decision 1.6C.

**Purpose:** The outer railway error type. Wraps either a `TransportError` or a
`RequestError`. This is the `E` in `JmapResult[T] = Result[T, ClientError]`.

When `ClientError` is on the error rail, no method responses exist — the entire
request failed at the transport or protocol level.

```nim
type ClientError* = object
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError
```

**Design decisions:**

1. **No shared fields.** `TransportError` and `RequestError` have different
   structures. A shared `message` field would be redundant with
   `TransportError.message`.

2. **`ValidationError` not included as a variant.** `ValidationError` is for
   smart constructor failures (Layer 1 construction-time). `ClientError` is for
   runtime communication failures (Layer 4). These are separate concerns per
   Decision 1.6C.

**Constructor helpers:**

```nim
func clientError*(transport: TransportError): ClientError =
  ClientError(kind: cekTransport, transport: transport)

func clientError*(request: RequestError): ClientError =
  ClientError(kind: cekRequest, request: request)
```

Two overloads — Nim dispatches on argument type.

**Accessor helper:**

```nim
func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport: err.transport.message
  of cekRequest:
    if err.request.detail.isSome: err.request.detail.unsafeGet
    elif err.request.title.isSome: err.request.title.unsafeGet
    else: err.request.rawType
```

Extracts a displayable message without requiring callers to match on `kind`.
For `cekRequest`, prefers `detail` over `title` over `rawType` (following
RFC 7807 guidance).

**Construction layer:** Layer 4 constructs `cekTransport` variants; Layer 4
also wraps `cekRequest` after Layer 2 parses the problem details body.

**Module:** `src/jmap_client/errors.nim`

### 8.7 MethodErrorType

**RFC reference:** §3.6.2 (method-level errors), plus §5.1–5.6 (method-specific
error types).

**Purpose:** String-backed enum covering all 19 RFC-defined method-level error
types, plus `metUnknown`. Follows Decision 1.7C.

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

**Design decisions:**

1. **All 19 types from RFC 8620.** Universal errors from §3.6.2 (10 types)
   plus method-specific errors from §5.1–5.6 (9 additional types, including
   `tooManyChanges` from §5.6 /queryChanges, and `fromAccountNotFound` and
   `fromAccountNotSupportedByMethod` from §5.4 /copy). RFC 8621 error types
   map to `metUnknown` with raw string preserved.

2. **`met` prefix.** Follows convention: `ck` for `CapabilityKind`, `set` for
   `SetErrorType`, `ret` for `RequestErrorType`.

**Parsing function:**

```nim
func parseMethodErrorType*(raw: string): MethodErrorType =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  strutils.parseEnum[MethodErrorType](raw, metUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.8 MethodError

**RFC reference:** §3.6.2.

**Purpose:** Per-invocation error within a JMAP response. When the server
returns `["error", {...}, "c1"]`, the arguments object is parsed into a
`MethodError`. This is the inner railway error — the `E` in
`Result[T, MethodError]`.

```nim
type MethodError* = object
  errorType*: MethodErrorType    ## parsed enum variant
  rawType*: string               ## always populated — lossless round-trip
  description*: Opt[string]      ## RFC "description" field
  extras*: Opt[JsonNode]         ## non-standard fields, lossless preservation
```

**Design decisions:**

1. **Flat object, not a case object.** Architecture-options.md §1.8 states:
   "MethodError is intentionally flat. RFC 8620 specifies only `description`
   as an optional per-type field. All method error types share the same shape."

2. **`extras: Opt[JsonNode]`.** Preserves additional server-sent fields not
   modelled as typed fields (e.g., some servers send `arguments` on
   `invalidArguments`). `Opt` rather than bare `JsonNode` because most
   errors have no extras.

3. **`description` as `Opt[string]`.** RFC says SHOULD have `description` —
   may be absent.

**Constructor helper:**

```nim
func methodError*(
  rawType: string,
  description: Opt[string] = Opt.none(string),
  extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )
```

**Construction layer:** Layer 2 (serialisation). When a response invocation
has `name == "error"`, Layer 2 extracts the arguments JSON and constructs a
`MethodError`.

**Module:** `src/jmap_client/errors.nim`

### 8.9 SetErrorType

**RFC reference:** §5.3 (/set errors), §5.4 (/copy errors).

**Purpose:** String-backed enum for 10 RFC-defined per-item error types,
plus `setUnknown`. Follows Decision 1.7C.

```nim
type SetErrorType* = enum
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
```

**Design decision:** `set` prefix distinguishes from `MethodErrorType` variants.
Several error type strings overlap (e.g., `"forbidden"` appears in both).

**Parsing function:**

```nim
func parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  strutils.parseEnum[SetErrorType](raw, setUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.10 SetError

**RFC reference:** §5.3, §5.4.

**Purpose:** Per-item error within `/set` and `/copy` responses. A case object
because the RFC mandates variant-specific fields on two error types.

```nim
type SetError* = object
  rawType*: string               ## always populated — lossless round-trip
  description*: Opt[string]      ## optional human-readable description
  extras*: Opt[JsonNode]         ## non-standard fields, lossless preservation
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string]     ## invalid property names (§5.3)
  of setAlreadyExists:
    existingId*: Id              ## the existing record's ID (§5.4)
  else:
    discard
```

**Design decisions:**

1. **Case object with variant-specific fields.** `invalidProperties` SHOULD
   carry `properties: String[]` (§5.3). `alreadyExists` MUST carry
   `existingId: Id` (§5.4). Making these typed means `existingId` cannot be
   accessed without matching `setAlreadyExists` — enforced by
   `strictCaseObjects`.

2. **Shared fields outside `case`.** `rawType`, `description`, `extras` always
   accessible regardless of variant.

3. **`properties: seq[string]`, not `Opt[seq[string]]`.** When absent, an
   empty `seq` is equivalent (no properties listed). More ergonomic for
   consumers: `for prop in err.properties`.

4. **`existingId: Id`.** Uses `Id` from Section 2.1 with the lenient parsing
   path (`parseIdFromServer`) since the ID is server-assigned.

5. **`else: discard`** for the 8 remaining error types that share the same
   shape (just `rawType`, `description`, `extras`).

**Constructor helpers (three constructors for three construction paths):**

```nim
func setError*(
  rawType: string,
  description: Opt[string] = Opt.none(string),
  extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## For non-variant-specific set errors.
  ## Defensively maps invalidProperties/alreadyExists to setUnknown when
  ## variant-specific data is absent.
  let errorType = parseSetErrorType(rawType)
  let safeType =
    if errorType in {setInvalidProperties, setAlreadyExists}: setUnknown else: errorType
  # Construct with setUnknown (compile-time literal), then set the actual
  # discriminator via uncheckedAssign. Safe because safeType is always in
  # the else-discard branch — same memory layout as setUnknown.
  result = SetError(
    errorType: setUnknown, rawType: rawType, description: description, extras: extras
  )
  {.cast(uncheckedAssign).}:
    result.errorType = safeType

func setErrorInvalidProperties*(
  rawType: string,
  properties: seq[string],
  description: Opt[string] = Opt.none(string),
  extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  SetError(
    errorType: setInvalidProperties, rawType: rawType,
    description: description, extras: extras,
    properties: properties,
  )

func setErrorAlreadyExists*(
  rawType: string,
  existingId: Id,
  description: Opt[string] = Opt.none(string),
  extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  SetError(
    errorType: setAlreadyExists, rawType: rawType,
    description: description, extras: extras,
    existingId: existingId,
  )
```

**Design decision for `setError` defensive fallback:** If the server sends
`{"type": "invalidProperties"}` without the `properties` array, or
`{"type": "alreadyExists"}` without the `existingId` field, the generic
constructor falls back to `setUnknown` (preserving `rawType`) rather than
constructing the variant-specific branch with default/empty values. Layer 2
calls `setErrorInvalidProperties` only when the JSON contains the
`properties` array, and `setErrorAlreadyExists` only when the JSON contains
`existingId`; otherwise it calls `setError`, which maps these to `setUnknown`.
This ensures that pattern-matching consumers do not encounter a
`setInvalidProperties` variant with an empty `properties` list or a
`setAlreadyExists` variant with a bogus `existingId`.

**Design decision for `uncheckedAssign` pattern:** `strictCaseObjects` requires
a compile-time literal for the discriminator when constructing a case object.
`safeType` is a runtime value (even though it is guaranteed to be in the
`else: discard` branch), so `SetError(errorType: safeType, ...)` does not
compile. The workaround constructs with the `setUnknown` literal first, then
reassigns the discriminator via `{.cast(uncheckedAssign).}`. This is safe
because all variants in the `else` branch share the same memory layout (no
variant-specific fields — just `discard`).

**Construction layer:** Layer 2 (serialisation). The `fromJson` examines the
`"type"` field, then dispatches to the appropriate constructor.

**Module:** `src/jmap_client/errors.nim`

### 8.11 JmapResult[T]

**RFC reference:** Not in RFC (library-internal). Decision 1.6C.

**Purpose:** Type alias for the outer railway. The return type of the transport
layer's `send` proc and the primary result type for all operations that cross
the network boundary.

```nim
type JmapResult*[T] = Result[T, ClientError]
```

**Design decisions:**

1. **Type alias, not distinct type.** All `Result` operations (`?`, `map`,
   `flatMap`, `mapErr`, `valueOr`) work directly. The alias exists for
   readability: `proc send(...): JmapResult[Response]` is clearer than
   `proc send(...): Result[Response, ClientError]`.

2. **No smart constructor.** Constructed using `ok(value)` and
   `err(clientError)` from `nim-results`.

**Module:** `src/jmap_client/types.nim` (not `errors.nim`). `JmapResult[T]`
needs both `T` (any Layer 1 type) and `ClientError` (from `errors.nim`)
visible, so it lives in the re-export module.

---

## 9. Borrowed Operations Summary

| Type | `==` | `$` | `hash` | `len` | `<` | `<=` | unary `-` |
|------|:----:|:---:|:------:|:-----:|:---:|:----:|:---------:|
| `Id` | Y | Y | Y | Y | | | |
| `UnsignedInt` | Y | Y | Y | | Y | Y | |
| `JmapInt` | Y | Y | Y | | Y | Y | Y |
| `Date` | Y | Y | Y | Y | | | |
| `UTCDate` | Y | Y | Y | Y | | | |
| `AccountId` | Y | Y | Y | Y | | | |
| `JmapState` | Y | Y | Y | | | | |
| `MethodCallId` | Y | Y | Y | | | | |
| `CreationId` | Y | Y | Y | | | | |
| `UriTemplate` | Y | Y | Y | Y | | | |
| `PropertyName` | Y | Y | Y | Y | | | |
| `PatchObject` | | | | Y | | | |

All borrowed operations are `func` and `{.raises: [].}` compatible.

No error types (Section 8) require borrowed operations. All error types are case
objects, plain objects, plain enums, or type aliases — standard operations are
built-in.

---

## 10. Smart Constructor Summary

| Type | Constructor | Validation | Returns |
|------|------------|-----------|---------|
| `Id` | `parseId` | Strict: 1-255 octets, base64url charset | `Result[Id, ValidationError]` |
| `Id` | `parseIdFromServer` | Lenient: 1-255 octets, no control chars | `Result[Id, ValidationError]` |
| `UnsignedInt` | `parseUnsignedInt` | `0 <= value <= 2^53-1` | `Result[UnsignedInt, ValidationError]` |
| `JmapInt` | `parseJmapInt` | `-2^53+1 <= value <= 2^53-1` | `Result[JmapInt, ValidationError]` |
| `Date` | `parseDate` | Pattern: T separator, uppercase, no zero frac | `Result[Date, ValidationError]` |
| `UTCDate` | `parseUtcDate` | Date rules + ends with Z | `Result[UTCDate, ValidationError]` |
| `AccountId` | `parseAccountId` | Lenient: 1-255 octets, no control chars | `Result[AccountId, ValidationError]` |
| `JmapState` | `parseJmapState` | Non-empty, no control chars | `Result[JmapState, ValidationError]` |
| `MethodCallId` | `parseMethodCallId` | Non-empty | `Result[MethodCallId, ValidationError]` |
| `CreationId` | `parseCreationId` | Non-empty, no `#` prefix | `Result[CreationId, ValidationError]` |
| `UriTemplate` | `parseUriTemplate` | Non-empty | `Result[UriTemplate, ValidationError]` |
| `CapabilityKind` | `parseCapabilityKind` | Total (always succeeds) | `CapabilityKind` |
| `Session` | `parseSession` | Core cap present, URLs valid, templates have variables | `Result[Session, ValidationError]` |
| `Account` | `findCapabilityByUri` | URI-based lookup (avoids ckUnknown ambiguity) | `Opt[AccountCapabilityEntry]` |
| `Session` | `findCapabilityByUri` | URI-based lookup (avoids ckUnknown ambiguity) | `Opt[ServerCapability]` |
| `PropertyName` | `parsePropertyName` | Non-empty | `Result[PropertyName, ValidationError]` |
| `Comparator` | `parseComparator` | Infallible (PropertyName enforces non-empty) | `Result[Comparator, ValidationError]` |
| `PatchObject` | `emptyPatch` | None (total) | `PatchObject` |
| `PatchObject` | `setProp` | Non-empty path | `Result[PatchObject, ValidationError]` |
| `PatchObject` | `deleteProp` | Non-empty path | `Result[PatchObject, ValidationError]` |
| `RequestErrorType` | `parseRequestErrorType` | Total (always succeeds) | `RequestErrorType` |
| `MethodErrorType` | `parseMethodErrorType` | Total (always succeeds) | `MethodErrorType` |
| `SetErrorType` | `parseSetErrorType` | Total (always succeeds) | `SetErrorType` |
| `TransportError` | `transportError` | None (total) | `TransportError` |
| `TransportError` | `httpStatusError` | None (total) | `TransportError` |
| `RequestError` | `requestError` | None (lossless round-trip) | `RequestError` |
| `ClientError` | `clientError` (2 overloads) | None (total) | `ClientError` |
| `MethodError` | `methodError` | None (lossless round-trip) | `MethodError` |
| `SetError` | `setError` | None (lossless + defensive fallback) | `SetError` |
| `SetError` | `setErrorInvalidProperties` | None (total) | `SetError` |
| `SetError` | `setErrorAlreadyExists` | None (total) | `SetError` |

All domain type constructors are `func` (pure) and return `Result[T,
ValidationError]`. All error type constructors are `func` (pure) and return
values directly — error types cannot fail construction.

---

## 11. Module File Layout

```
src/jmap_client/
  validation.nim      ← ValidationError, borrow templates, charset constants
  primitives.nim      ← Id, UnsignedInt, JmapInt, Date, UTCDate
  identifiers.nim     ← AccountId, JmapState, MethodCallId, CreationId
  capabilities.nim    ← CapabilityKind, CoreCapabilities, ServerCapability
  session.nim         ← Account, AccountCapabilityEntry, UriTemplate, Session
  envelope.nim        ← Invocation, Request, Response,
                        ResultReference, Referencable[T]
  framework.nim       ← PropertyName, FilterOperator, Filter[C],
                        Comparator, PatchObject, AddedItem
  errors.nim          ← TransportErrorKind, TransportError,
                        RequestErrorType, RequestError,
                        ClientErrorKind, ClientError,
                        MethodErrorType, MethodError,
                        SetErrorType, SetError
  types.nim           ← Re-exports all of the above; defines JmapResult[T]
```

### Import Graph

```
            validation.nim       (std/hashes)
             ↑         ↑
  primitives.nim    identifiers.nim   (std/hashes, std/sequtils each)
   ↑   ↑   ↑   ↑       ↑        ↑
   |   |   |  errors.nim |       |    (std/json, std/strutils)
   |   |   |             |       |
   |   | framework.nim   |       |    (std/hashes, std/json, std/tables)
   |   |                 |       |
   | capabilities.nim    |       |    (std/hashes, std/sets, std/strutils, std/json)
   |        ↑            |       |
   |    session.nim -----+       |    (std/hashes, std/sequtils, std/strutils, std/tables, std/json)
   |        |                    |
  envelope.nim ------------------+    (std/json, std/tables)
        ↑
  types.nim                           (re-exports all, defines JmapResult[T])
```

All arrows point upward — no cycles. `validation.nim` is the root dependency.
`primitives.nim` and `identifiers.nim` both depend on `validation.nim` directly.
`identifiers.nim` depends on `validation.nim` (for `defineStringDistinctOps`,
`ValidationError`, `validationError`), not on `primitives.nim` — no identifier
type references any primitive type. `errors.nim` depends on `primitives.nim`. `framework.nim` depends on both
`validation.nim` (for `defineStringDistinctOps`, `ValidationError`,
`validationError`) and `primitives.nim`. They do not depend on each other.
`capabilities.nim` depends on `primitives.nim` (for `UnsignedInt`), not on
`identifiers.nim`. `envelope.nim` depends on `identifiers.nim` (for
`MethodCallId`, `CreationId`, `JmapState`) and `primitives.nim` (for `Id`),
not on `session.nim`.
`session.nim` depends on `validation.nim` (for `ValidationError`,
`validationError`, `defineStringDistinctOps`), `identifiers.nim` (for
`AccountId`, `JmapState`) and `capabilities.nim` (for `CapabilityKind`,
`ServerCapability`, `CoreCapabilities`).

**Re-export policy.** Individual modules do not re-export their Layer 1
dependencies. Each module imports only what it directly needs. Downstream
code (Layer 2+, tests) should import `types` for the full public API. When
a module's public types reference types from another module (e.g., `envelope`
uses `Id` from `primitives`), it imports that module directly.

`types.nim` re-exports everything and defines the railway alias:

```nim
import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope
import ./framework
import ./errors

export validation, primitives, identifiers, capabilities,
       session, envelope, framework, errors

type JmapResult*[T] = Result[T, ClientError]
```

---

## 12. Test Fixtures

### 12.1 RFC §2.1 Session Example (Golden Test)

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

### 12.2 RFC §3.3.1 Request Example

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
- `request.methodCalls[0].name == "method1"`
- `request.methodCalls[0].methodCallId == MethodCallId("c1")`
- `request.createdIds.isNone`

### 12.3 RFC §3.4.1 Response Example

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
- `response.methodResponses[3].name == "error"` (method-level error)
- `response.sessionState == JmapState("75128aab4b1b")`
- `response.createdIds.isNone`

### 12.4 Edge Cases per Type

| Type | Input | Expected | Reason |
|------|-------|----------|--------|
| `Id` (strict) | `""` | `err` | empty |
| `Id` (strict) | `"a" * 256` | `err` | exceeds 255 octets |
| `Id` (strict) | `"a" * 255` | `ok` | maximum valid length |
| `Id` (strict) | `"abc123-_XYZ"` | `ok` | all base64url chars |
| `Id` (strict) | `"abc=def"` | `err` | pad character not allowed |
| `Id` (strict) | `"abc def"` | `err` | space not allowed |
| `Id` (lenient) | `"abc+def"` | `ok` | lenient allows non-base64url |
| `Id` (lenient) | `"abc\x00def"` | `err` | control characters rejected |
| `UnsignedInt` | `0` | `ok` | minimum valid |
| `UnsignedInt` | `9007199254740991` | `ok` | 2^53-1, maximum valid |
| `UnsignedInt` | `-1` | `err` | negative |
| `UnsignedInt` | `9007199254740992` | `err` | 2^53, exceeds maximum |
| `JmapInt` | `-9007199254740991` | `ok` | -(2^53-1), minimum valid |
| `JmapInt` | `9007199254740991` | `ok` | 2^53-1, maximum valid |
| `Date` | `"2014-10-30T14:12:00+08:00"` | `ok` | RFC example |
| `Date` | `"2014-10-30T14:12:00.123Z"` | `ok` | non-zero fractional seconds |
| `Date` | `"2014-10-30t14:12:00Z"` | `err` | lowercase 't' |
| `Date` | `"2014-10-30T14:12:00.000Z"` | `err` | zero frac must be omitted |
| `Date` | `"2014-10-30T14:12:00.Z"` | `err` | empty fractional part (no digits after dot) |
| `Date` | `"2014-10-30T14:12:00.0Z"` | `err` | zero fractional seconds must be omitted |
| `Date` | `"2014-10-30T14:12:00.100Z"` | `ok` | non-zero fractional (trailing zero is fine) |
| `Date` | `"2014-10-30T14:12:00z"` | `err` | lowercase 'z' |
| `Date` | `"2014-10-30"` | `err` | too short, missing time |
| `UTCDate` | `"2014-10-30T06:12:00Z"` | `ok` | RFC example |
| `UTCDate` | `"2014-10-30T06:12:00+00:00"` | `err` | must be Z, not +00:00 |
| `CapabilityKind` | `"urn:ietf:params:jmap:core"` | `ckCore` | known URI |
| `CapabilityKind` | `"urn:ietf:params:jmap:mail"` | `ckMail` | known URI |
| `CapabilityKind` | `"https://vendor.example/ext"` | `ckUnknown` | vendor URI |
| `CapabilityKind` | `""` | `ckUnknown` | empty string |
| `CreationId` | `"#abc"` | `err` | must not include # prefix |
| `CreationId` | `"abc"` | `ok` | valid creation ID |
| `AccountId` | `""` | `err` | empty |
| `AccountId` | `"A13824"` | `ok` | valid (RFC §2.1 example) |
| `AccountId` | `"a" * 256` | `err` | exceeds 255 octets |
| `AccountId` | `"a" * 255` | `ok` | maximum valid length |
| `AccountId` | `"abc\x00def"` | `err` | control characters rejected |
| `JmapState` | `""` | `err` | empty |
| `JmapState` | `"75128aab4b1b"` | `ok` | valid (RFC §2.1 example) |
| `JmapState` | `"abc\x00def"` | `err` | control characters rejected |
| `Session` | missing core capability | `err` | RFC MUST constraint |
| `Session` | downloadUrl without `{blobId}` | `err` | RFC MUST constraint |
| `Session` | valid RFC §2.1 example | `ok` | golden test |
| `Session` | constructed directly without `ckCore` | `coreCapabilities` raises `AssertionDefect` | invariant violation |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "https://example.com/apis/foobar")` | `ok(...)` with `kind == ckUnknown` | vendor extension lookup |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "urn:nonexistent")` | `err()` | unknown URI |
| `findCapabilityByUri` (Account) | `findCapabilityByUri(account, "urn:ietf:params:jmap:mail")` | `ok(...)` with `kind == ckMail` | known capability lookup |
| `primaryAccount` | `primaryAccount(session, ckMail)` | `ok(AccountId("A13824"))` | known capability with primary account |
| `primaryAccount` | `primaryAccount(session, ckUnknown)` | `err()` | ckUnknown has no canonical URI |
| `primaryAccount` | `primaryAccount(session, ckBlob)` | `err()` | known capability without primary account |
| `PropertyName` | `""` | `err` | empty property name |
| `PropertyName` | `"name"` | `ok` | valid property name |
| `Comparator` | `property: parsePropertyName("")` | `err` | empty property (PropertyName rejects) |
| `Comparator` | `property: parsePropertyName("name")` | `ok` | minimal valid |
| `Comparator` | `property: parsePropertyName("name"), collation: ok("i;unicode-casemap")` | `ok` | with collation |
| `PatchObject` | `setProp(emptyPatch(), "", ...)` | `err` | empty path |
| `PatchObject` | `setProp(emptyPatch(), "name", ...)` | `ok` | simple property set |
| `PatchObject` | `deleteProp(emptyPatch(), "addresses/0")` | `ok` | nested path deletion |
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
| `SetErrorType` | `"invalidProperties"` | `setInvalidProperties` | known type |
| `SetErrorType` | `"alreadyExists"` | `setAlreadyExists` | known type |
| `SetErrorType` | `"vendorSpecific"` | `setUnknown` | unknown type |
| `TransportError` | `transportError(tekTimeout, "timed out")` | valid, `kind == tekTimeout` | convenience constructor |
| `TransportError` | `httpStatusError(502, "Bad Gateway")` | valid, `httpStatus == 502` | HTTP status variant |
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = ok("maxCallsInRequest"))` | `errorType == retLimit`, rawType preserved | lossless round-trip |
| `RequestError` | `requestError("urn:vendor:custom")` | `errorType == retUnknown`, rawType preserved | unknown type preserved |
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = ok("maxCallsInRequest"), extras = ok(%*{"requestId": "abc"}))` | extras preserved | lossless round-trip for extension members |
| `ClientError` | `clientError(transportError(tekNetwork, "refused"))` | `kind == cekTransport` | wrapping transport |
| `ClientError` | `clientError(requestError("...notJSON"))` | `kind == cekRequest` | wrapping request |
| `MethodError` | `methodError("unknownMethod")` | `errorType == metUnknownMethod` | lossless round-trip |
| `MethodError` | `methodError("custom", extras = ok(%*{"hint": "retry"}))` | `errorType == metUnknown`, extras preserved | unknown with extras |
| `SetError` | `setError("forbidden")` | `errorType == setForbidden` | non-variant-specific |
| `SetError` | `setErrorInvalidProperties("invalidProperties", @["name"])` | `errorType == setInvalidProperties` | variant-specific |
| `SetError` | `setErrorAlreadyExists("alreadyExists", someId)` | `errorType == setAlreadyExists` | variant-specific |
| `SetError` | `setError("invalidProperties")` (no properties) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("alreadyExists")` (no existingId) | `errorType == setUnknown`, rawType preserved | defensive fallback for alreadyExists |
| `JmapResult` | `Result[Response, ClientError].ok(resp)` | `isOk` | success rail |
| `JmapResult` | `Result[Response, ClientError].err(clientErr)` | `isErr` | error rail |

---

## Appendix: RFC Section Cross-Reference

| Type | RFC 8620 Section |
|------|-----------------|
| `Id` | §1.2 |
| `Int` / `JmapInt` | §1.3 |
| `UnsignedInt` | §1.3 |
| `Date` | §1.4 |
| `UTCDate` | §1.4 |
| `Session` | §2 |
| `Account` | §2 (nested in Session.accounts) |
| `CoreCapabilities` | §2 (nested in Session.capabilities["urn:ietf:params:jmap:core"]) |
| `Invocation` | §3.2 |
| `Request` | §3.3 |
| `Response` | §3.4 |
| `ResultReference` | §3.7 |
| `CapabilityKind` (registry) | §9.4 |
| `MethodCallId` | §3.2 (element 3 of Invocation) |
| `CreationId` | §3.3 (Request.createdIds), §5.3 (/set create) |
| `AccountId` | §1.6.2, §2 (Session.accounts keys) |
| `JmapState` | §2 (Session.state), §3.4 (Response.sessionState), §5.1 (/get state) |
| `UriTemplate` | §2 (downloadUrl, uploadUrl, eventSourceUrl per RFC 6570) |
| `Referencable[T]` | §3.7 (back-reference mechanism) |
| `FilterOperator` | §5.5 |
| `Filter[C]` | §5.5 |
| `PropertyName` | §5.5 (property name in Comparator) |
| `Comparator` | §5.5 |
| `PatchObject` | §5.3 |
| `AddedItem` | §5.6 |
| `RequestErrorType` | §3.6.1 |
| `RequestError` | §3.6.1, RFC 7807 |
| `MethodErrorType` | §3.6.2, §5.1–5.6 |
| `MethodError` | §3.6.2 |
| `SetErrorType` | §5.3, §5.4 |
| `SetError` | §5.3, §5.4 |
| `TransportErrorKind` | Not in RFC (library-internal) |
| `TransportError` | Not in RFC (library-internal) |
| `ClientErrorKind` | Not in RFC (library-internal) |
| `ClientError` | Not in RFC (library-internal) |
| `JmapResult[T]` | Not in RFC (library-internal) |
| `UploadResponse` | §6.1 (deferred — see architecture.md §4.6) |
| `Blob/copy` types | §6.3 (deferred — Layer 3 method types) |
