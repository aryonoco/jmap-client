# Layer 1: Domain Types + Errors — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, smart constructor, and validation
rule for Layer 1 of the jmap-client library. It builds upon the decisions made in
`00-architecture.md` and incorporates the architecture revision documented in
`04-architecture-revision.md`.

**Scope.** Layer 1 covers: primitive data types (RFC 8620 §1.2–1.4), domain
identifiers, the Session object and everything it contains (§2), the
Request/Response envelope (§3.2–3.4, §3.7), the generic method framework
types (§5.3 PatchObject, §5.5 Filter/Comparator, §5.6 AddedItem), and all
error types (TransportError, RequestError, ClientError as exceptions;
MethodError and SetError as response data). Serialisation (Layer 2), protocol
logic (Layer 3), and transport (Layer 4) are out of scope. Binary data (§6)
and push (§7) are deferred; see architecture.md §4.5–4.6.

**Relationship to architecture documents.** `00-architecture.md` records
broad decisions across all 5 layers. `04-architecture-revision.md` specifies
the migration from strict FP-enforced Nim to idiomatic Nim. This document
reflects the codebase after that revision.

**Design principles.** Every decision follows:

- **Exception-based error handling** — smart constructors raise
  `ValidationError` (a `CatchableError`) on invalid input and return `T`
  directly on success. Exceptions propagate naturally through Layers 1–4
  and are caught at the Layer 5 C ABI boundary.
- **Functional Core, Imperative Shell** — Layers 1–3 do not perform I/O or
  mutate global state. Purity is maintained by convention and code review,
  not by compiler enforcement. `proc` is used throughout (not `func`).
  Layer 4 performs I/O. Layer 5 catches exceptions.
- **Immutability by default** — `let` bindings. No mutable state in Layer 1.
  Local `var` inside `proc` is permitted when building return values from
  stdlib containers whose APIs require mutation (e.g., `Table` in
  `PatchObject.setProp`).
- **Total functions** — every function has a defined output for every input.
  Functions that rely on constructor-guaranteed invariants (e.g.,
  `coreCapabilities` depends on `parseSession` having validated `ckCore`
  presence) are total over the image of their smart constructor. If the
  invariant is violated by direct construction bypassing the smart
  constructor, `AssertionDefect` terminates the process — this signals a
  programming error, not a recoverable runtime condition. With
  `--panics:on`, Defects abort via `rawQuit(1)`.
- **Parse, don't validate** — smart constructors produce well-typed values or
  raise structured errors. Invariants enforced at construction time.
- **Make illegal states unrepresentable** — distinct types, case objects, and
  smart constructors encode domain invariants in the type system where the
  type system permits. Some invariants (e.g., `Invocation.arguments` must be
  a JSON object, not an array) are enforced at construction time by Layer 2
  parsing and Layer 3 builders rather than by the Layer 1 type definition,
  because `JsonNode` is an opaque stdlib type that cannot be further
  constrained without a wrapper.
- **Dual validation strictness** — accept server-generated data leniently
  (tolerating minor RFC deviations such as non-base64url ID characters),
  construct client-generated data strictly. Both paths raise on truly invalid
  input — neither silently accepts garbage. Strict constructors are used when
  the client creates values; lenient constructors are used during JSON
  deserialisation of server responses. This principle appears concretely in
  `Id` (§2.1: `parseId` vs `parseIdFromServer`), `AccountId` (§3.1), and
  `Session` cross-reference validation (§5.3).

**Compiler flags.** These constrain every type definition (from `config.nims`):

```
--mm:arc
--panics:on
--experimental:strictDefs
--threads:on
--floatChecks:on
--overflowChecks:on
--boundChecks:on
--objChecks:on
--rangeChecks:on
--fieldChecks:on
--assertions:on
```

Warnings promoted to errors include `CStringConv`, `EnumConv`,
`HoleEnumConv`, `AnyEnumConv`, `BareExcept`, `Uninit`, `UnsafeSetLen`,
`ProveInit`, and many others. See `config.nims` for the full list.

**Notable compiler flags NOT used:**

- `strictFuncs` — removed in architecture revision; purity by convention
- `strictNotNil` — removed; fires inside stdlib generics in Nim 2.2
- `strictCaseObjects` — removed; standard Nim case object protections suffice
- `{.push raises: [].}` — only on Layer 5 (`src/jmap_client.nim`)

---

## Standard Library Utilisation

Layer 1 maximises use of the Nim standard library. Every adoption and rejection
has a concrete reason tied to the compiler constraints.

### Modules used in Layer 1

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/hashes` | `Hash` type, `hash` borrowing for distinct types | `hash(distinctVal)` auto-delegates to base type via `{.borrow.}` |
| `std/tables` | `Table[AccountId, T]`, `Table[string, T]` | For `Session.accounts`, `Session.primaryAccounts`, `Request.createdIds`, `PatchObject` base type |
| `std/sets` | `HashSet[string]` | For `CoreCapabilities.collationAlgorithms` — proper set semantics (no duplicates, O(1) lookup) |
| `std/strutils` | `parseEnum[T](s, default)`, `contains` | `parseEnum` is total, no exceptions — replaces manual `CapabilityKind` case statement |
| `std/json` | `JsonNode`, `JsonNodeKind`, `newJNull` | For untyped capability data (`ServerCapability`), `Invocation.arguments`, `PatchObject` deletion |
| `std/options` | `Option[T]`, `some`, `none`, `isSome`, `isNone`, `get` | For optional values throughout. Re-exported via `types.nim` |
| `std/sequtils` | `allIt`, `anyIt` | Predicate templates that expand inline — work inside `proc` for charset validation |
| built-in `set[char]` | Charset validation constants | `{'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}` for `Id` validation |

### Modules evaluated and rejected

| Module | Reason not used in Layer 1 |
|--------|---------------------------|
| `std/times` | `times.parse` is `proc` with side effects. A convenience `toDateTime` converter may be provided in a separate utility module. |
| `std/parseutils` | Pattern replicated using `allIt` template from sequtils. |
| `std/uri` | `parseUri` raises `UriParseError`. `apiUrl` is passed directly to the HTTP client — no need to decompose. |
| `std/enumutils` | `parseEnum` from `strutils` covers parsing. `symbolName` returns the symbolic name (vs `$` which returns the backing string), but symbolic names are not needed in Layer 1. |
| `std/httpcore` | `HttpCode` is relevant to Layer 4 (transport errors), not Layer 1. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `hash` auto-borrows for distinct types | No manual `hash` implementation needed — `{.borrow.}` suffices |
| `$` for string-backed enums returns the **backing string**, not the symbolic name; `symbolName` from `std/enumutils` returns the symbolic name | `$ckCore` returns `"urn:ietf:params:jmap:core"`. However `$ckUnknown` returns `"ckUnknown"` (no backing string), requiring custom `proc capabilityUri(kind): Option[string]` to force callers to handle `ckUnknown` |
| `parseEnum[T](s, default)` is total (no exceptions) | Can be called freely — returns the default on any unrecognised input |
| `parseEnum` matches against **both** symbolic names and string backing values | Negligible risk: JMAP servers send URIs, not Nim identifiers |
| `RangeDefect` bypasses `{.push raises: [].}` (Defect, not CatchableError) | Range types crash instead of raising — not suitable for expected runtime failures |
| `allIt` is a template that expands inline | Works for charset validation in smart constructors |
| `allIt` on empty seq returns `true` (vacuous truth) | Callers must guard `allIt` predicate checks with a non-empty check when an empty input requires a different error |
| Defects (RangeDefect, FieldDefect, AssertionDefect) are fatal | With `--panics:on`, they abort via `rawQuit(1)` — not suitable for expected runtime failures |

---

## 1. Validation Infrastructure

### 1.1 ValidationError

RFC reference: not applicable (library-internal type).

`ValidationError` is the error type for Layer 1 smart constructors. It inherits
from `CatchableError` and carries enough context to produce a useful error
message without requiring the caller to know which constructor failed.

```nim
type ValidationError* = object of CatchableError
  typeName*: string   ## which type failed ("Id", "UnsignedInt", etc.)
  value*: string      ## the raw input that failed validation
```

The `msg` field (inherited from `CatchableError`) carries the failure reason
(e.g., "length must be 1-255 octets").

Constructor helper:

```nim
proc newValidationError*(typeName, message, value: string): ref ValidationError =
  ## Constructs a ref ValidationError suitable for raising.
  result = (ref ValidationError)(msg: message, typeName: typeName, value: value)
```

`newValidationError` returns `ref ValidationError` because Nim's `raise`
statement requires a `ref` to a `CatchableError` subtype. Smart constructors
call `raise newValidationError(...)` on invalid input.

`ValidationError` is the error type for smart constructor failures (Layer 1
construction-time validation). `ClientError` (Section 8.6) is a separate
concern for runtime transport/request failures (Layer 4). These are different
error categories and are not unified into a single type.

**Module:** `src/jmap_client/validation.nim`

### 1.2 Smart Constructor Pattern

Every type with construction-time invariants has a smart constructor following
this pattern:

```nim
proc parseFoo*(raw: InputType): Foo =
  ## Raises ValidationError on invalid input.
  if <validation fails>:
    raise newValidationError("Foo", "reason", raw)
  doAssert <postcondition>
  Foo(raw)
```

- Always a `proc`.
- Raises `ValidationError` on invalid input, returns `T` directly on success.
- Uses `doAssert` postconditions to verify invariants after construction.
  With `--panics:on` and `--assertions:on`, failed assertions abort the
  process — these are programmer error checks, not runtime validation.
- For distinct types (e.g., `Id`, `UnsignedInt`, `Date`), the raw constructor
  is the base type conversion (`string(x)` or `int64(x)`), which is not
  accessible outside the defining module without explicit borrowing. Only the
  smart constructor is public.
- For non-distinct object types (e.g., `Session`), Nim cannot prevent direct
  construction via `Session(field1: val1, ...)` when fields are public. The
  smart constructor enforces invariants that direct construction does not.
  Functions that depend on these invariants (e.g., `coreCapabilities`) use
  `raiseAssert` for the unreachable branch.
- For types with no invariants beyond their constituent types, the raw
  constructor may be exported directly.

### 1.3 Borrow Templates

To reduce boilerplate, two templates define the standard borrowed operations for
distinct types. Uses `std/hashes` for the `Hash` type.

```nim
import std/hashes

template defineStringDistinctOps*(T: typedesc) =
  proc `==`*(a, b: T): bool {.borrow.}
  proc `$`*(a: T): string {.borrow.}
  proc hash*(a: T): Hash {.borrow.}
  proc len*(a: T): int {.borrow.}

template defineIntDistinctOps*(T: typedesc) =
  proc `==`*(a, b: T): bool {.borrow.}
  proc `<`*(a, b: T): bool {.borrow.}
  proc `<=`*(a, b: T): bool {.borrow.}
  proc `$`*(a: T): string {.borrow.}
  proc hash*(a: T): Hash {.borrow.}
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
type Id* = distinct string
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
proc parseId*(raw: string): Id =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  if raw.len < 1 or raw.len > 255:
    raise newValidationError("Id", "length must be 1-255 octets", raw)
  if not raw.allIt(it in Base64UrlChars):
    raise newValidationError("Id", "contains characters outside base64url alphabet", raw)
  let id = Id(raw)
  doAssert id.len >= 1 and id.len <= 255
  id

proc parseIdFromServer*(raw: string): Id =
  ## Lenient: 1-255 octets, no control characters (including DEL).
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  if raw.len < 1 or raw.len > 255:
    raise newValidationError("Id", "length must be 1-255 octets", raw)
  if raw.anyIt(it < ' ' or it == '\x7F'):
    raise newValidationError("Id", "contains control characters", raw)
  let id = Id(raw)
  doAssert id.len >= 1 and id.len <= 255
  id
```

**Rationale for dual constructors.** The RFC MUST constraint is 1–255 octets
and base64url charset. In practice, some servers send IDs with characters
outside this set. Refusing to parse the entire server response because of an
ID charset violation makes the library unusable with those servers. Both
constructors raise on truly invalid input (empty strings, control characters)
— neither silently accepts garbage. The strict constructor is used when the
client constructs IDs; the lenient constructor is used during JSON
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
proc parseUnsignedInt*(value: int64): UnsignedInt =
  if value < 0:
    raise newValidationError("UnsignedInt", "must be non-negative", $value)
  if value > MaxUnsignedInt:
    raise newValidationError("UnsignedInt", "exceeds 2^53-1", $value)
  doAssert value >= 0 and value <= MaxUnsignedInt
  UnsignedInt(value)
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
proc parseJmapInt*(value: int64): JmapInt =
  if value < MinJmapInt or value > MaxJmapInt:
    raise newValidationError("JmapInt", "outside JSON-safe integer range", $value)
  doAssert value >= MinJmapInt and value <= MaxJmapInt
  JmapInt(value)
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

Validation is decomposed into four private helpers, called sequentially in
`parseDate`. Each raises `ValidationError` on the first failure encountered.

```nim
const AsciiDigits = {'0'..'9'}

proc validateDatePortion(raw: string) =
  ## YYYY-MM-DD at positions 0..9.
  if not (
    raw[0 .. 3].allIt(it in AsciiDigits) and raw[4] == '-' and
    raw[5 .. 6].allIt(it in AsciiDigits) and raw[7] == '-' and
    raw[8 .. 9].allIt(it in AsciiDigits)
  ):
    raise newValidationError("Date", "invalid date portion", raw)

proc validateTimePortion(raw: string) =
  ## HH:MM:SS at positions 11..18, with uppercase 'T' separator at 10.
  if raw[10] != 'T':
    raise newValidationError("Date", "'T' separator must be uppercase", raw)
  if not (
    raw[11 .. 12].allIt(it in AsciiDigits) and raw[13] == ':' and
    raw[14 .. 15].allIt(it in AsciiDigits) and raw[16] == ':' and
    raw[17 .. 18].allIt(it in AsciiDigits)
  ):
    raise newValidationError("Date", "invalid time portion", raw)
  if raw.anyIt(it in {'t', 'z'}):
    raise newValidationError("Date", "'T' and 'Z' must be uppercase (RFC 3339)", raw)

proc validateFractionalSeconds(raw: string) =
  ## If a '.' follows position 19, digits must follow and not all be zero.
  if raw.len > 19 and raw[19] == '.':
    let dotEnd = block:
      var i = 20
      while i < raw.len and raw[i] in AsciiDigits:
        inc i
      i
    if dotEnd == 20:
      raise newValidationError(
        "Date", "fractional seconds must contain at least one digit", raw
      )
    if raw[20 ..< dotEnd].allIt(it == '0'):
      raise newValidationError("Date", "zero fractional seconds must be omitted", raw)

proc offsetStart(raw: string): int =
  ## Returns the position where the timezone offset begins.
  result = 19
  if result < raw.len and raw[result] == '.':
    inc result
    while result < raw.len and raw[result] in AsciiDigits:
      inc result

proc isValidNumericOffset(raw: string, pos: int): bool =
  ## Checks that raw[pos..pos+5] matches +HH:MM or -HH:MM structurally.
  pos + 6 == raw.len and raw[pos + 1] in AsciiDigits and raw[pos + 2] in AsciiDigits and
    raw[pos + 3] == ':' and raw[pos + 4] in AsciiDigits and raw[pos + 5] in AsciiDigits

proc validateTimezoneOffset(raw: string) =
  ## Validates timezone offset after seconds and optional fractional seconds.
  ## Must be 'Z' or '+HH:MM' or '-HH:MM'.
  let pos = offsetStart(raw)
  if pos >= raw.len:
    raise newValidationError("Date", "missing timezone offset", raw)
  if raw[pos] == 'Z':
    if pos + 1 != raw.len:
      raise newValidationError("Date", "trailing characters after 'Z'", raw)
    return
  if raw[pos] notin {'+', '-'} or not isValidNumericOffset(raw, pos):
    raise newValidationError("Date", "timezone offset must be 'Z' or '+/-HH:MM'", raw)

proc parseDate*(raw: string): Date =
  ## Structural validation of an RFC 3339 date-time string.
  ## Does NOT perform calendar validation (e.g., February 30).
  if raw.len < 20:
    raise newValidationError("Date", "too short for RFC 3339 date-time", raw)
  validateDatePortion(raw)
  validateTimePortion(raw)
  validateFractionalSeconds(raw)
  validateTimezoneOffset(raw)
  doAssert raw.len >= 20 and raw[10] == 'T'
  Date(raw)
```

**Decision D3 rationale.** `std/times.DateTime` was evaluated but rejected for
Layer 1 because `distinct string` preserves the exact server representation
for lossless round-trip. A convenience converter `proc toDateTime*(d: Date):
DateTime` may be provided in a separate utility module outside the pure core.

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
proc parseUtcDate*(raw: string): UTCDate =
  ## All Date validation rules, plus: must end with 'Z'.
  discard parseDate(raw)
  if raw[^1] != 'Z':
    raise newValidationError("UTCDate", "time-offset must be 'Z'", raw)
  doAssert raw[^1] == 'Z'
  UTCDate(raw)
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
proc parseMaxChanges*(raw: UnsignedInt): MaxChanges =
  ## Rejects 0, which the RFC forbids.
  if int64(raw) == 0:
    raise newValidationError("MaxChanges", "must be greater than 0", $int64(raw))
  MaxChanges(raw)
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
type AccountId* = distinct string
defineStringDistinctOps(AccountId)
```

**Smart constructor:**

```nim
proc parseAccountId*(raw: string): AccountId =
  ## Lenient: 1-255 octets, no control characters (including DEL).
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  if raw.len < 1 or raw.len > 255:
    raise newValidationError("AccountId", "length must be 1-255 octets", raw)
  if raw.anyIt(it < ' ' or it == '\x7F'):
    raise newValidationError("AccountId", "contains control characters", raw)
  doAssert raw.len >= 1 and raw.len <= 255
  AccountId(raw)
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.2 JmapState

**RFC reference:** §2 (Session.state), §5.1 (/get response `state`), §5.2
(/changes `sinceState`).

An opaque state token generated by the server. Changes when the data it
represents changes. Used for change detection and delta synchronisation.

```nim
type JmapState* = distinct string
proc `==`*(a, b: JmapState): bool {.borrow.}
proc `$`*(a: JmapState): string {.borrow.}
proc hash*(a: JmapState): Hash {.borrow.}
```

`len` is not borrowed — the length of a state token is not meaningful to
consumers.

**Smart constructor:**

```nim
proc parseJmapState*(raw: string): JmapState =
  ## Non-empty, no control characters (including DEL). Server-assigned —
  ## same defensive checks as other server-assigned identifiers.
  if raw.len == 0:
    raise newValidationError("JmapState", "must not be empty", raw)
  if raw.anyIt(it < ' ' or it == '\x7F'):
    raise newValidationError("JmapState", "contains control characters", raw)
  doAssert raw.len > 0
  JmapState(raw)
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.3 MethodCallId

**RFC reference:** §3.2 (Invocation, element 3).

An arbitrary string from the client, echoed back in the response. Used to
correlate responses to method calls.

```nim
type MethodCallId* = distinct string
proc `==`*(a, b: MethodCallId): bool {.borrow.}
proc `$`*(a: MethodCallId): string {.borrow.}
proc hash*(a: MethodCallId): Hash {.borrow.}
```

`len` is not borrowed — method call IDs are opaque correlation tokens whose
length is not meaningful to consumers (same rationale as `JmapState`, §3.2).

**Smart constructor:**

```nim
proc parseMethodCallId*(raw: string): MethodCallId =
  ## Non-empty. Client-generated.
  if raw.len == 0:
    raise newValidationError("MethodCallId", "must not be empty", raw)
  doAssert raw.len > 0
  MethodCallId(raw)
```

**Module:** `src/jmap_client/identifiers.nim`

### 3.4 CreationId

**RFC reference:** §3.3 (Request.createdIds), §5.3 (/set `create` argument).

A client-generated identifier for a record being created. On the wire, creation
IDs are prefixed with `#` when used as forward references. The stored value does
NOT include the `#` prefix — that is a serialisation concern (Layer 2).

```nim
type CreationId* = distinct string
proc `==`*(a, b: CreationId): bool {.borrow.}
proc `$`*(a: CreationId): string {.borrow.}
proc hash*(a: CreationId): Hash {.borrow.}
```

`len` is not borrowed — creation IDs are opaque client-generated identifiers
whose length is not meaningful to consumers.

**Smart constructor:**

```nim
proc parseCreationId*(raw: string): CreationId =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  if raw.len == 0:
    raise newValidationError("CreationId", "must not be empty", raw)
  if raw[0] == '#':
    raise newValidationError("CreationId", "must not include '#' prefix", raw)
  doAssert raw.len > 0 and raw[0] != '#'
  CreationId(raw)
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
cannot be default-constructed meaningfully. `seq` operations (`setLen`, `reset`)
must default-construct elements, so the default `CapabilityKind` must select the
`else` branch — whose `rawData: JsonNode` is nil-safe. Placing `ckMail` first
satisfies this constraint.

**Parsing (stdlib `parseEnum`):**

```nim
import std/strutils

proc parseCapabilityKind*(uri: string): CapabilityKind =
  ## Maps a capability URI string to an enum value.
  ## Total function: always succeeds. Unknown URIs map to ckUnknown.
  strutils.parseEnum[CapabilityKind](uri, ckUnknown)
```

This is a single line, total, no exceptions. `parseEnum` with a `default`
parameter never raises — it returns the default on any unrecognised input.

**Serialisation (reverse direction):**

`$ckCore` returns `"urn:ietf:params:jmap:core"` (the backing string).
However, `$ckUnknown` returns `"ckUnknown"` (no backing string assigned),
which is not a valid capability URI. A function returning `Option[string]`
forces callers to handle `ckUnknown` explicitly:

```nim
proc capabilityUri*(kind: CapabilityKind): Option[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns none for ckUnknown — callers must use rawUri from ServerCapability.
  case kind
  of ckCore: some("urn:ietf:params:jmap:core")
  of ckMail: some("urn:ietf:params:jmap:mail")
  of ckSubmission: some("urn:ietf:params:jmap:submission")
  of ckVacationResponse: some("urn:ietf:params:jmap:vacationresponse")
  of ckWebsocket: some("urn:ietf:params:jmap:websocket")
  of ckMdn: some("urn:ietf:params:jmap:mdn")
  of ckSmimeVerify: some("urn:ietf:params:jmap:smimeverify")
  of ckBlob: some("urn:ietf:params:jmap:blob")
  of ckQuota: some("urn:ietf:params:jmap:quota")
  of ckContacts: some("urn:ietf:params:jmap:contacts")
  of ckCalendars: some("urn:ietf:params:jmap:calendars")
  of ckSieve: some("urn:ietf:params:jmap:sieve")
  of ckUnknown: none(string)
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
  collationAlgorithms*: HashSet[string]  ## Collation algorithm identifiers (RFC 4790)
```

**No smart constructor.** The `UnsignedInt` fields enforce their own invariants
via their smart constructors. Construction happens exclusively during JSON
deserialisation (Layer 2), which validates each field individually.

**Decision D6.** `HashSet[string]` from `std/sets` for `collationAlgorithms`
instead of `seq[string]`. The RFC defines this as a list of identifiers for
membership testing ("does the server support this collation?"). `HashSet`
provides: no duplicates, O(1) lookup via `in`, proper set semantics.

**Helper:**

```nim
proc hasCollation*(caps: CoreCapabilities, algorithm: string): bool =
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
proc findCapability*(account: Account, kind: CapabilityKind): Option[AccountCapabilityEntry] =
  for _, entry in account.accountCapabilities:
    if entry.kind == kind:
      return some(entry)
  none(AccountCapabilityEntry)

proc findCapabilityByUri*(account: Account, uri: string): Option[AccountCapabilityEntry] =
  ## Looks up an account capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to
  ## ckUnknown and would be ambiguous via findCapability).
  for _, entry in account.accountCapabilities:
    if entry.rawUri == uri:
      return some(entry)
  none(AccountCapabilityEntry)

proc hasCapability*(account: Account, kind: CapabilityKind): bool =
  account.findCapability(kind).isSome
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
type UriTemplate* = distinct string
defineStringDistinctOps(UriTemplate)
```

**Smart constructor:**

```nim
proc parseUriTemplate*(raw: string): UriTemplate =
  ## Non-empty. No RFC 6570 parsing — template expansion is Layer 4 (IO).
  if raw.len == 0:
    raise newValidationError("UriTemplate", "must not be empty", raw)
  UriTemplate(raw)
```

**Variable presence check:**

```nim
proc hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## Checks if the template contains {name}. Simple string search.
  let target = "{" & name & "}"
  target in string(tmpl)
```

Used by the Session smart constructor to verify required template variables.

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
apply, and the only Layer 1 invariants (non-empty, no newlines) are enforced
by `parseSession`.

**Private helper:**

```nim
proc hasKind(caps: openArray[ServerCapability], kind: CapabilityKind): bool =
  ## Checks whether any capability matches the given kind. Used by parseSession
  ## before a Session object exists.
  for _, cap in caps:
    if cap.kind == kind:
      return true
  false
```

**Smart constructor:**

```nim
proc parseSession*(
  capabilities: seq[ServerCapability],
  accounts: Table[AccountId, Account],
  primaryAccounts: Table[string, AccountId],
  username: string,
  apiUrl: string,
  downloadUrl: UriTemplate,
  uploadUrl: UriTemplate,
  eventSourceUrl: UriTemplate,
  state: JmapState,
): Session =
  ## Validates structural invariants:
  ## 1. capabilities includes ckCore (RFC §2: MUST)
  ## 2. apiUrl is non-empty
  ## 3. apiUrl contains no newline characters
  ## 4. downloadUrl contains {accountId}, {blobId}, {type}, {name} (RFC §2)
  ## 5. uploadUrl contains {accountId} (RFC §2)
  ## 6. eventSourceUrl contains {types}, {closeafter}, {ping} (RFC §2)
  if not capabilities.hasKind(ckCore):
    raise newValidationError(
      "Session", "capabilities must include urn:ietf:params:jmap:core", ""
    )
  if apiUrl.len == 0:
    raise newValidationError("Session", "apiUrl must not be empty", "")
  if apiUrl.contains({'\c', '\L'}):
    raise newValidationError(
      "Session", "apiUrl must not contain newline characters", apiUrl
    )
  for variable in ["accountId", "blobId", "type", "name"]:
    if not downloadUrl.hasVariable(variable):
      raise newValidationError(
        "Session", "downloadUrl missing {" & variable & "}", string(downloadUrl)
      )
  if not uploadUrl.hasVariable("accountId"):
    raise newValidationError(
      "Session", "uploadUrl missing {accountId}", string(uploadUrl)
    )
  for variable in ["types", "closeafter", "ping"]:
    if not eventSourceUrl.hasVariable(variable):
      raise newValidationError(
        "Session", "eventSourceUrl missing {" & variable & "}", string(eventSourceUrl)
      )
  let session = Session(
    capabilities: capabilities,
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: username,
    apiUrl: apiUrl,
    downloadUrl: downloadUrl,
    uploadUrl: uploadUrl,
    eventSourceUrl: eventSourceUrl,
    state: state,
  )
  doAssert session.capabilities.hasKind(ckCore)
  doAssert session.apiUrl.len > 0
  session
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
proc coreCapabilities*(session: Session): CoreCapabilities =
  ## Returns the core capabilities. Total over Sessions constructed via
  ## parseSession (which guarantees ckCore is present). Raises AssertionDefect
  ## if the invariant is violated by direct construction.
  for _, cap in session.capabilities:
    case cap.kind
    of ckCore:
      return cap.core
    else:
      discard
  raiseAssert "Session missing ckCore: violated parseSession invariant"
```

**Invariant note.** `coreCapabilities` is total over Sessions constructed
via `parseSession`, which guarantees `ckCore` is present. If `Session` is
constructed directly without `ckCore`, `coreCapabilities` raises
`AssertionDefect` — a `Defect` (fatal, not `CatchableError`). With
`--panics:on`, this aborts the process.

```nim
proc findCapability*(session: Session, kind: CapabilityKind): Option[ServerCapability] =
  for _, cap in session.capabilities:
    if cap.kind == kind:
      return some(cap)
  none(ServerCapability)

proc findCapabilityByUri*(session: Session, uri: string): Option[ServerCapability] =
  ## Looks up a capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions.
  for _, cap in session.capabilities:
    if cap.rawUri == uri:
      return some(cap)
  none(ServerCapability)

proc primaryAccount*(session: Session, kind: CapabilityKind): Option[AccountId] =
  let uriOpt = capabilityUri(kind)
  if uriOpt.isNone:
    return none(AccountId)
  let uri = uriOpt.get()
  for key, val in session.primaryAccounts:
    if key == uri:
      return some(val)
  none(AccountId)

proc findAccount*(session: Session, id: AccountId): Option[Account] =
  for key, val in session.accounts:
    if key == id:
      return some(val)
  none(Account)
```

**`primaryAccount` failure modes.** Returns `none` in two cases: (1) `kind
== ckUnknown` (no canonical URI to look up — use `session.primaryAccounts`
directly with the raw URI string), or (2) no primary account is designated
for this capability. For vendor extensions, access `session.primaryAccounts`
directly with the raw URI string.

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
  methodCallId*: MethodCallId  ## validated method call ID
```

`arguments` is `JsonNode` at the envelope level. Typed extraction into
concrete method response types happens in Layer 3.

**Constructor:**

```nim
proc initInvocation*(name: string, arguments: JsonNode, methodCallId: MethodCallId): Invocation =
  Invocation(name: name, arguments: arguments, methodCallId: methodCallId)
```

**Module:** `src/jmap_client/envelope.nim`

### 6.2 Request

**RFC reference:** §3.3 (lines 882–943).

```nim
import std/tables

type Request* = object
  `using`*: seq[string]            ## capability URIs the client wishes to use
  methodCalls*: seq[Invocation]    ## processed sequentially by server
  createdIds*: Option[Table[CreationId, Id]]  ## optional; enables proxy splitting
```

`using` is `seq[string]` (raw URIs, not `seq[CapabilityKind]`) because vendor
extension URIs would collide at `ckUnknown`.

`createdIds` is `Option` because the RFC specifies it as optional.

**No smart constructor.** Built by the Layer 3 request builder.

**Module:** `src/jmap_client/envelope.nim`

### 6.3 Response

**RFC reference:** §3.4 (lines 975–1003).

```nim
type Response* = object
  methodResponses*: seq[Invocation]            ## same format as methodCalls
  createdIds*: Option[Table[CreationId, Id]]   ## only if given in request
  sessionState*: JmapState                     ## current Session.state value
```

**Module:** `src/jmap_client/envelope.nim`

### 6.4 ResultReference

**RFC reference:** §3.7 (lines 1220–1261).

Allows an argument to one method call to be taken from the result of a previous
method call in the same request.

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
proc direct*[T](value: T): Referencable[T] =
  Referencable[T](kind: rkDirect, value: value)

proc referenceTo*[T](reference: ResultReference): Referencable[T] =
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
proc filterCondition*[C](cond: C): Filter[C] =
  Filter[C](kind: fkCondition, condition: cond)

proc filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =
  Filter[C](kind: fkOperator, operator: op, conditions: conditions)
```

Total constructors. No validation needed — all inputs produce valid filters.

**Module:** `src/jmap_client/framework.nim`

### 7.2a PropertyName

**RFC reference:** §5.5 (property names in Comparator, referenced throughout).

A property name is a non-empty string identifying a field on an entity type.

**Type definition:**

```nim
type PropertyName* = distinct string
defineStringDistinctOps(PropertyName)
```

**Smart constructor:**

```nim
proc parsePropertyName*(raw: string): PropertyName =
  if raw.len == 0:
    raise newValidationError("PropertyName", "must not be empty", raw)
  PropertyName(raw)
```

**Module:** `src/jmap_client/framework.nim`

### 7.3 Comparator

**RFC reference:** §5.5. Determines the sort order for a `/query` request.

**Type definition:**

```nim
type Comparator* = object
  property*: PropertyName    ## property name to sort by
  isAscending*: bool         ## true = ascending (RFC default)
  collation*: Option[string]    ## RFC 4790 collation algorithm identifier
```

`isAscending` defaults to `true` per RFC §5.5. The constructor mirrors
this default for convenience.

**Constructor:**

```nim
proc parseComparator*(
  property: PropertyName,
  isAscending: bool = true,
  collation: Option[string] = none(string)
): Comparator =
  Comparator(property: property, isAscending: isAscending, collation: collation)
```

The non-empty property invariant is enforced by `PropertyName`'s smart
constructor (`parsePropertyName`). `parseComparator` is infallible given a
valid `PropertyName`.

**Module:** `src/jmap_client/framework.nim`

### 7.4 PatchObject

**RFC reference:** §5.3. A `PatchObject` is a map of JSON Pointer paths to
values, used in `/set` update operations.

**Type definition:**

```nim
import std/tables
import std/json

type PatchObject* = distinct Table[string, JsonNode]
```

**Borrowed operations:**

```nim
proc len*(p: PatchObject): int {.borrow.}
```

Only `len` is borrowed. Mutating `Table` operations (`[]=`, `del`, `clear`)
are deliberately excluded — smart constructors (`setProp`, `deleteProp`) are
the only write path, ensuring path validation cannot be bypassed.

**Smart constructors:**

```nim
proc emptyPatch*(): PatchObject =
  PatchObject(initTable[string, JsonNode]())

proc setProp*(patch: PatchObject, path: string, value: JsonNode): PatchObject =
  ## Sets a property at the given JSON Pointer path.
  if path.len == 0:
    raise newValidationError("PatchObject", "path must not be empty", "")
  var t = Table[string, JsonNode](patch)
  t[path] = value
  PatchObject(t)

proc deleteProp*(patch: PatchObject, path: string): PatchObject =
  ## Sets a property to null (deletion in JMAP PatchObject semantics).
  if path.len == 0:
    raise newValidationError("PatchObject", "path must not be empty", "")
  var t = Table[string, JsonNode](patch)
  t[path] = newJNull()
  PatchObject(t)
```

`setProp` and `deleteProp` copy the table to a local `var`, mutate it, and
rewrap. The input `PatchObject` is not modified. Under `--mm:arc`, the copy
uses move semantics when the caller does not retain the original.

**Read accessor:**

```nim
proc getKey*(patch: PatchObject, key: string): Option[JsonNode] =
  ## Returns the value at key, or none if absent.
  let t = Table[string, JsonNode](patch)
  if t.hasKey(key):
    some(t[key])
  else:
    none(JsonNode)
```

**Module:** `src/jmap_client/framework.nim`

### 7.5 AddedItem

**RFC reference:** §5.6. An element of the `added` array in a `/queryChanges`
response.

**Type definition:**

```nim
type AddedItem* = object
  id*: Id
  index*: UnsignedInt
```

**No smart constructor.** Both fields enforce their own invariants via their
respective smart constructors (`parseIdFromServer`, `parseUnsignedInt`).

**Module:** `src/jmap_client/framework.nim`

---

## 8. Error Types

Error types implement a three-track error hierarchy. The outer railway uses
exception types (`TransportError`, `RequestError`, `ClientError`) for
transport/request failures — these inherit from `CatchableError` and are
raised by Layer 4 transport code, then caught at the Layer 5 C ABI boundary.
The inner railway uses data types (`MethodError`, `SetError`) for
per-invocation and per-item errors within successful JMAP responses — these
are NOT exceptions.

All error constructors are `proc` and return values directly. Error types
represent received data or classified exceptions; they cannot fail
construction.

All error types that carry a `type` string follow the lossless round-trip
pattern: a parsed enum (`errorType`) alongside a preserved raw string
(`rawType`). Serialisation always uses `rawType`, never `$errorType`.

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

**Purpose:** Exception type (inherits from `CatchableError`) carrying a
human-readable message and variant-specific data for transport failures.

```nim
type TransportError* = object of CatchableError
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard
```

**Design decisions:**

1. **Inherits from `CatchableError`.** Transport errors are raised by Layer 4
   and caught at the Layer 5 C ABI boundary. The `msg` field (inherited from
   `CatchableError`) carries the human-readable message.

2. **`httpStatus` is `int`, not `UnsignedInt`.** HTTP status codes are standard
   integers (100–599). Using `UnsignedInt` would add unnecessary ceremony.

3. **`tekHttpStatus` scope.** For HTTP responses that fail at the HTTP level and
   do not carry a valid RFC 7807 problem details body. If the response has a
   valid problem details JSON body, it becomes a `RequestError` instead.

**Constructor helpers:**

```nim
proc transportError*(kind: TransportErrorKind, message: string): TransportError =
  TransportError(kind: kind, msg: message)

proc httpStatusError*(status: int, message: string): TransportError =
  TransportError(kind: tekHttpStatus, msg: message, httpStatus: status)
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
proc parseRequestErrorType*(raw: string): RequestErrorType =
  strutils.parseEnum[RequestErrorType](raw, retUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.4 RequestError

**RFC reference:** §3.6.1, RFC 7807.

**Purpose:** Exception type representing a request-level error — an HTTP
response with `Content-Type: application/problem+json`.

```nim
type RequestError* = object of CatchableError
  errorType*: RequestErrorType   ## parsed enum variant
  rawType*: string               ## always populated — lossless round-trip
  status*: Option[int]           ## RFC 7807 "status" field
  title*: Option[string]         ## RFC 7807 "title" field
  detail*: Option[string]        ## RFC 7807 "detail" field
  limit*: Option[string]         ## which limit was exceeded (retLimit only)
  extras*: Option[JsonNode]      ## non-standard fields, lossless preservation
```

**Constructor helper:**

```nim
proc requestError*(
  rawType: string,
  status: Option[int] = none(int),
  title: Option[string] = none(string),
  detail: Option[string] = none(string),
  limit: Option[string] = none(string),
  extras: Option[JsonNode] = none(JsonNode),
): RequestError =
  result = RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )
  doAssert result.rawType == rawType
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

**Purpose:** The outer railway exception type. Wraps either a `TransportError`
or a `RequestError`. When raised, no method responses exist — the entire
request failed at the transport or protocol level.

```nim
type ClientError* = object of CatchableError
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError
```

**Constructor helpers:**

```nim
proc clientError*(transport: TransportError): ClientError =
  ClientError(kind: cekTransport, transport: transport, msg: transport.msg)

proc clientError*(request: RequestError): ClientError =
  ClientError(kind: cekRequest, request: request, msg: request.rawType)

proc newClientError*(transport: TransportError): ref ClientError =
  ## Ref-returning constructor for raising transport failures as exceptions.
  (ref ClientError)(kind: cekTransport, transport: transport, msg: transport.msg)

proc newClientError*(request: RequestError): ref ClientError =
  ## Ref-returning constructor for raising request rejections as exceptions.
  (ref ClientError)(kind: cekRequest, request: request, msg: request.rawType)
```

Two pairs of constructors: value-returning (`clientError`) for data
manipulation, and ref-returning (`newClientError`) for raising as exceptions.

**Accessor helper:**

```nim
proc message*(err: ClientError): string =
  case err.kind
  of cekTransport: err.transport.msg
  of cekRequest:
    if err.request.detail.isSome: err.request.detail.get()
    elif err.request.title.isSome: err.request.title.get()
    else: err.request.rawType
```

For `cekRequest`, prefers `detail` over `title` over `rawType` (following
RFC 7807 guidance).

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
proc parseMethodErrorType*(raw: string): MethodErrorType =
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
  errorType*: MethodErrorType    ## parsed enum variant
  rawType*: string               ## always populated — lossless round-trip
  description*: Option[string]   ## RFC "description" field
  extras*: Option[JsonNode]      ## non-standard fields, lossless preservation
```

**Constructor helper:**

```nim
proc methodError*(
  rawType: string,
  description: Option[string] = none(string),
  extras: Option[JsonNode] = none(JsonNode),
): MethodError =
  result = MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )
  doAssert result.rawType == rawType
```

**Module:** `src/jmap_client/errors.nim`

### 8.9 SetErrorType

**RFC reference:** §5.3 (/set errors), §5.4 (/copy errors).

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

**Parsing function:**

```nim
proc parseSetErrorType*(raw: string): SetErrorType =
  strutils.parseEnum[SetErrorType](raw, setUnknown)
```

**Module:** `src/jmap_client/errors.nim`

### 8.10 SetError

**RFC reference:** §5.3, §5.4.

**Purpose:** Per-item error within `/set` and `/copy` responses. Response
data, NOT an exception. A case object because the RFC mandates
variant-specific fields on two error types.

```nim
type SetError* = object
  rawType*: string               ## always populated — lossless round-trip
  description*: Option[string]   ## optional human-readable description
  extras*: Option[JsonNode]      ## non-standard fields, lossless preservation
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string]     ## invalid property names (§5.3)
  of setAlreadyExists:
    existingId*: Id              ## the existing record's ID (§5.4)
  else:
    discard
```

**Constructor helpers (three constructors for three construction paths):**

```nim
proc setError*(
  rawType: string,
  description: Option[string] = none(string),
  extras: Option[JsonNode] = none(JsonNode),
): SetError =
  ## For non-variant-specific set errors.
  ## Defensively maps invalidProperties/alreadyExists to setUnknown when
  ## variant-specific data is absent.
  let errorType = parseSetErrorType(rawType)
  let safeType =
    if errorType in {setInvalidProperties, setAlreadyExists}: setUnknown else: errorType
  SetError(
    errorType: safeType, rawType: rawType, description: description, extras: extras
  )

proc setErrorInvalidProperties*(
  rawType: string,
  properties: seq[string],
  description: Option[string] = none(string),
  extras: Option[JsonNode] = none(JsonNode),
): SetError =
  SetError(
    errorType: setInvalidProperties, rawType: rawType,
    description: description, extras: extras,
    properties: properties,
  )

proc setErrorAlreadyExists*(
  rawType: string,
  existingId: Id,
  description: Option[string] = none(string),
  extras: Option[JsonNode] = none(JsonNode),
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

**Module:** `src/jmap_client/errors.nim`

---

## 9. Borrowed Operations Summary

| Type | `==` | `$` | `hash` | `len` | `<` | `<=` | unary `-` |
|------|:----:|:---:|:------:|:-----:|:---:|:----:|:---------:|
| `Id` | Y | Y | Y | Y | | | |
| `UnsignedInt` | Y | Y | Y | | Y | Y | |
| `JmapInt` | Y | Y | Y | | Y | Y | Y |
| `Date` | Y | Y | Y | Y | | | |
| `UTCDate` | Y | Y | Y | Y | | | |
| `MaxChanges` | Y | Y | Y | | Y | Y | |
| `AccountId` | Y | Y | Y | Y | | | |
| `JmapState` | Y | Y | Y | | | | |
| `MethodCallId` | Y | Y | Y | | | | |
| `CreationId` | Y | Y | Y | | | | |
| `UriTemplate` | Y | Y | Y | Y | | | |
| `PropertyName` | Y | Y | Y | Y | | | |
| `PatchObject` | | | | Y | | | |

All borrowed operations are `proc`.

---

## 10. Smart Constructor Summary

| Type | Constructor | Validation | Behaviour |
|------|------------|-----------|-----------|
| `Id` | `parseId` | Strict: 1-255 octets, base64url charset | raises `ValidationError` or returns `Id` |
| `Id` | `parseIdFromServer` | Lenient: 1-255 octets, no control chars | raises `ValidationError` or returns `Id` |
| `UnsignedInt` | `parseUnsignedInt` | `0 <= value <= 2^53-1` | raises `ValidationError` or returns `UnsignedInt` |
| `JmapInt` | `parseJmapInt` | `-2^53+1 <= value <= 2^53-1` | raises `ValidationError` or returns `JmapInt` |
| `MaxChanges` | `parseMaxChanges` | Must be > 0 | raises `ValidationError` or returns `MaxChanges` |
| `Date` | `parseDate` | Structural RFC 3339 + timezone offset | raises `ValidationError` or returns `Date` |
| `UTCDate` | `parseUtcDate` | Date rules + ends with Z | raises `ValidationError` or returns `UTCDate` |
| `AccountId` | `parseAccountId` | Lenient: 1-255 octets, no control chars | raises `ValidationError` or returns `AccountId` |
| `JmapState` | `parseJmapState` | Non-empty, no control chars | raises `ValidationError` or returns `JmapState` |
| `MethodCallId` | `parseMethodCallId` | Non-empty | raises `ValidationError` or returns `MethodCallId` |
| `CreationId` | `parseCreationId` | Non-empty, no `#` prefix | raises `ValidationError` or returns `CreationId` |
| `UriTemplate` | `parseUriTemplate` | Non-empty | raises `ValidationError` or returns `UriTemplate` |
| `CapabilityKind` | `parseCapabilityKind` | Total (always succeeds) | returns `CapabilityKind` |
| `Session` | `parseSession` | Core cap present, URLs valid, templates have variables, no newlines in apiUrl | raises `ValidationError` or returns `Session` |
| `PropertyName` | `parsePropertyName` | Non-empty | raises `ValidationError` or returns `PropertyName` |
| `Comparator` | `parseComparator` | Infallible (PropertyName enforces non-empty) | returns `Comparator` |
| `PatchObject` | `emptyPatch` | None (total) | returns `PatchObject` |
| `PatchObject` | `setProp` | Non-empty path | raises `ValidationError` or returns `PatchObject` |
| `PatchObject` | `deleteProp` | Non-empty path | raises `ValidationError` or returns `PatchObject` |
| `RequestErrorType` | `parseRequestErrorType` | Total (always succeeds) | returns `RequestErrorType` |
| `MethodErrorType` | `parseMethodErrorType` | Total (always succeeds) | returns `MethodErrorType` |
| `SetErrorType` | `parseSetErrorType` | Total (always succeeds) | returns `SetErrorType` |
| `TransportError` | `transportError` | None (total) | returns `TransportError` |
| `TransportError` | `httpStatusError` | None (total) | returns `TransportError` |
| `RequestError` | `requestError` | None (lossless round-trip) | returns `RequestError` |
| `ClientError` | `clientError` (2 overloads) | None (total) | returns `ClientError` |
| `ClientError` | `newClientError` (2 overloads) | None (total) | returns `ref ClientError` |
| `MethodError` | `methodError` | None (lossless round-trip) | returns `MethodError` |
| `SetError` | `setError` | None (lossless + defensive fallback) | returns `SetError` |
| `SetError` | `setErrorInvalidProperties` | None (total) | returns `SetError` |
| `SetError` | `setErrorAlreadyExists` | None (total) | returns `SetError` |

All domain type constructors are `proc`. Smart constructors that validate
raise `ValidationError` on failure. Error type constructors return values
directly — error types cannot fail construction.

---

## 11. Module File Layout

```
src/jmap_client/
  validation.nim      <- ValidationError (CatchableError), borrow templates,
                         charset constants
  primitives.nim      <- Id, UnsignedInt, JmapInt, Date, UTCDate, MaxChanges
  identifiers.nim     <- AccountId, JmapState, MethodCallId, CreationId
  capabilities.nim    <- CapabilityKind, CoreCapabilities, ServerCapability
  session.nim         <- Account, AccountCapabilityEntry, UriTemplate, Session
  envelope.nim        <- Invocation, Request, Response,
                         ResultReference, Referencable[T]
  framework.nim       <- PropertyName, FilterOperator, Filter[C],
                         Comparator, PatchObject, AddedItem
  errors.nim          <- TransportErrorKind, TransportError (CatchableError),
                         RequestErrorType, RequestError (CatchableError),
                         ClientErrorKind, ClientError (CatchableError),
                         MethodErrorType, MethodError (plain object),
                         SetErrorType, SetError (plain object)
  types.nim           <- Re-exports all of the above + std/options
```

### Import Graph

```
            validation.nim       (std/hashes)
             ^         ^
  primitives.nim    identifiers.nim   (std/hashes, std/sequtils each)
   ^   ^   ^   ^       ^        ^
   |   |   |  errors.nim |       |    (std/options, std/strutils, std/json)
   |   |   |             |       |
   |   | framework.nim   |       |    (std/hashes, std/options, std/tables, std/json)
   |   |                 |       |
   | capabilities.nim    |       |    (std/options, std/strutils, std/sets, std/json)
   |        ^            |       |
   |    session.nim -----+       |    (std/hashes, std/options, std/strutils, std/tables, std/json)
   |        |                    |
  envelope.nim ------------------+    (std/options, std/tables, std/json)
        ^
  types.nim                           (re-exports all + std/options)
```

All arrows point upward — no cycles. `validation.nim` is the root dependency.
`primitives.nim` and `identifiers.nim` both depend on `validation.nim` directly.
`identifiers.nim` depends on `validation.nim` (for `defineStringDistinctOps`,
`ValidationError`, `newValidationError`), not on `primitives.nim`.
`errors.nim` depends on `primitives.nim` (for `Id`).
`framework.nim` depends on both `validation.nim` and `primitives.nim`.
`capabilities.nim` depends on `primitives.nim` (for `UnsignedInt`).
`envelope.nim` depends on `identifiers.nim` (for `MethodCallId`, `CreationId`,
`JmapState`) and `primitives.nim` (for `Id`).
`session.nim` depends on `validation.nim`, `identifiers.nim` (for `AccountId`,
`JmapState`) and `capabilities.nim` (for `CapabilityKind`, `ServerCapability`,
`CoreCapabilities`).

**Re-export policy.** Individual modules do not re-export their Layer 1
dependencies. Each module imports only what it directly needs. Downstream
code (Layer 2+, tests) should import `types` for the full public API.

`types.nim` re-exports everything plus `std/options`:

```nim
import std/options

import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope
import ./framework
import ./errors

export options
export validation, primitives, identifiers, capabilities,
       session, envelope, framework, errors
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
| `Id` (strict) | `""` | raises | empty |
| `Id` (strict) | `"a" * 256` | raises | exceeds 255 octets |
| `Id` (strict) | `"a" * 255` | `Id` | maximum valid length |
| `Id` (strict) | `"abc123-_XYZ"` | `Id` | all base64url chars |
| `Id` (strict) | `"abc=def"` | raises | pad character not allowed |
| `Id` (strict) | `"abc def"` | raises | space not allowed |
| `Id` (lenient) | `"abc+def"` | `Id` | lenient allows non-base64url |
| `Id` (lenient) | `"abc\x00def"` | raises | control characters rejected |
| `Id` (lenient) | `"abc\x7Fdef"` | raises | DEL rejected |
| `UnsignedInt` | `0` | `UnsignedInt` | minimum valid |
| `UnsignedInt` | `9007199254740991` | `UnsignedInt` | 2^53-1, maximum valid |
| `UnsignedInt` | `-1` | raises | negative |
| `UnsignedInt` | `9007199254740992` | raises | 2^53, exceeds maximum |
| `MaxChanges` | `UnsignedInt(1)` | `MaxChanges` | minimum valid |
| `MaxChanges` | `UnsignedInt(0)` | raises | must be > 0 |
| `JmapInt` | `-9007199254740991` | `JmapInt` | -(2^53-1), minimum valid |
| `JmapInt` | `9007199254740991` | `JmapInt` | 2^53-1, maximum valid |
| `Date` | `"2014-10-30T14:12:00+08:00"` | `Date` | RFC example |
| `Date` | `"2014-10-30T14:12:00.123Z"` | `Date` | non-zero fractional seconds |
| `Date` | `"2014-10-30t14:12:00Z"` | raises | lowercase 't' |
| `Date` | `"2014-10-30T14:12:00.000Z"` | raises | zero frac must be omitted |
| `Date` | `"2014-10-30T14:12:00.Z"` | raises | empty fractional part (no digits after dot) |
| `Date` | `"2014-10-30T14:12:00.0Z"` | raises | zero fractional seconds must be omitted |
| `Date` | `"2014-10-30T14:12:00.100Z"` | `Date` | non-zero fractional (trailing zero is fine) |
| `Date` | `"2014-10-30T14:12:00z"` | raises | lowercase 'z' |
| `Date` | `"2014-10-30"` | raises | too short, missing time |
| `Date` | `"2014-10-30T14:12:00"` | raises | missing timezone offset |
| `UTCDate` | `"2014-10-30T06:12:00Z"` | `UTCDate` | RFC example |
| `UTCDate` | `"2014-10-30T06:12:00+00:00"` | raises | must be Z, not +00:00 |
| `CapabilityKind` | `"urn:ietf:params:jmap:core"` | `ckCore` | known URI |
| `CapabilityKind` | `"urn:ietf:params:jmap:mail"` | `ckMail` | known URI |
| `CapabilityKind` | `"https://vendor.example/ext"` | `ckUnknown` | vendor URI |
| `CapabilityKind` | `""` | `ckUnknown` | empty string |
| `CreationId` | `"#abc"` | raises | must not include # prefix |
| `CreationId` | `"abc"` | `CreationId` | valid creation ID |
| `AccountId` | `""` | raises | empty |
| `AccountId` | `"A13824"` | `AccountId` | valid (RFC §2.1 example) |
| `AccountId` | `"a" * 256` | raises | exceeds 255 octets |
| `AccountId` | `"a" * 255` | `AccountId` | maximum valid length |
| `AccountId` | `"abc\x00def"` | raises | control characters rejected |
| `AccountId` | `"abc\x7Fdef"` | raises | DEL rejected |
| `JmapState` | `""` | raises | empty |
| `JmapState` | `"75128aab4b1b"` | `JmapState` | valid (RFC §2.1 example) |
| `JmapState` | `"abc\x00def"` | raises | control characters rejected |
| `JmapState` | `"abc\x7Fdef"` | raises | DEL rejected |
| `Session` | missing core capability | raises | RFC MUST constraint |
| `Session` | downloadUrl without `{blobId}` | raises | RFC MUST constraint |
| `Session` | apiUrl with newline | raises | newline characters rejected |
| `Session` | valid RFC §2.1 example | `Session` | golden test |
| `Session` | constructed directly without `ckCore` | `coreCapabilities` raises `AssertionDefect` | invariant violation |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "https://example.com/apis/foobar")` | `some(...)` with `kind == ckUnknown` | vendor extension lookup |
| `findCapabilityByUri` (Session) | `findCapabilityByUri(session, "urn:nonexistent")` | `none` | unknown URI |
| `findCapabilityByUri` (Account) | `findCapabilityByUri(account, "urn:ietf:params:jmap:mail")` | `some(...)` with `kind == ckMail` | known capability lookup |
| `primaryAccount` | `primaryAccount(session, ckMail)` | `some(AccountId("A13824"))` | known capability with primary account |
| `primaryAccount` | `primaryAccount(session, ckUnknown)` | `none` | ckUnknown has no canonical URI |
| `primaryAccount` | `primaryAccount(session, ckBlob)` | `none` | known capability without primary account |
| `PropertyName` | `""` | raises | empty property name |
| `PropertyName` | `"name"` | `PropertyName` | valid property name |
| `Comparator` | `property: parsePropertyName("")` | raises | empty property (PropertyName rejects) |
| `Comparator` | `property: parsePropertyName("name")` | `Comparator` | minimal valid |
| `Comparator` | `property: parsePropertyName("name"), collation: some("i;unicode-casemap")` | `Comparator` | with collation |
| `PatchObject` | `setProp(emptyPatch(), "", ...)` | raises | empty path |
| `PatchObject` | `setProp(emptyPatch(), "name", ...)` | `PatchObject` | simple property set |
| `PatchObject` | `deleteProp(emptyPatch(), "addresses/0")` | `PatchObject` | nested path deletion |
| `PatchObject` | `getKey(emptyPatch(), "name")` | `none` | absent key |
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
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = some("maxCallsInRequest"))` | `errorType == retLimit`, rawType preserved | lossless round-trip |
| `RequestError` | `requestError("urn:vendor:custom")` | `errorType == retUnknown`, rawType preserved | unknown type preserved |
| `RequestError` | `requestError("urn:ietf:params:jmap:error:limit", limit = some("maxCallsInRequest"), extras = some(%*{"requestId": "abc"}))` | extras preserved | lossless round-trip for extension members |
| `ClientError` | `clientError(transportError(tekNetwork, "refused"))` | `kind == cekTransport` | wrapping transport |
| `ClientError` | `clientError(requestError("...notJSON"))` | `kind == cekRequest` | wrapping request |
| `MethodError` | `methodError("unknownMethod")` | `errorType == metUnknownMethod` | lossless round-trip |
| `MethodError` | `methodError("custom", extras = some(%*{"hint": "retry"}))` | `errorType == metUnknown`, extras preserved | unknown with extras |
| `SetError` | `setError("forbidden")` | `errorType == setForbidden` | non-variant-specific |
| `SetError` | `setErrorInvalidProperties("invalidProperties", @["name"])` | `errorType == setInvalidProperties` | variant-specific |
| `SetError` | `setErrorAlreadyExists("alreadyExists", someId)` | `errorType == setAlreadyExists` | variant-specific |
| `SetError` | `setError("invalidProperties")` (no properties) | `errorType == setUnknown`, rawType preserved | defensive fallback |
| `SetError` | `setError("alreadyExists")` (no existingId) | `errorType == setUnknown`, rawType preserved | defensive fallback for alreadyExists |

---

## Appendix: RFC Section Cross-Reference

| Type | RFC 8620 Section |
|------|-----------------|
| `Id` | §1.2 |
| `Int` / `JmapInt` | §1.3 |
| `UnsignedInt` | §1.3 |
| `MaxChanges` | §5.2 |
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
| `UploadResponse` | §6.1 (deferred — see architecture.md §4.6) |
| `Blob/copy` types | §6.3 (deferred — Layer 3 method types) |
