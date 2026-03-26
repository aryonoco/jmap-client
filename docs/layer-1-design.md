# Layer 1: Core Types — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, smart constructor, and validation
rule for Layer 1 of the jmap-client library. It builds upon the decisions made in
`architecture-options.md` and resolves all deferred concrete choices so that
implementation is mechanical.

**Scope.** Layer 1 covers: primitive data types (RFC 8620 §1.2–1.4), domain
identifiers, the Session object and everything it contains (§2), and the
Request/Response envelope (§3.2–3.4, §3.7). Error types (Layer 2), serialisation
(Layer 3), standard method request/response shapes (Layer 5), and transport
(Layer 7) are out of scope.

**Relationship to architecture-options.md.** That document records broad
decisions across all 8 layers. This document is the detailed specification for
Layer 1 only. Decisions here are consistent with — and build upon — the
architecture document's choices 1A, 1D, 1G, 3G, and 4A–4H.

**Design principles.** Every decision follows:

- **Railway Oriented Programming** — `Result[T, E]` pipelines with `?` for
  early return. Smart constructors return `Result`, never raise.
- **Functional Core, Imperative Shell** — all Layer 1 code is `func` (pure, no
  side effects). `proc` appears only at the transport boundary (Layer 7).
- **Immutability by default** — `let` bindings. No `var` in Layer 1.
- **Total functions** — `{.push raises: [].}` on every module. Every function
  has a defined output for every input.
- **Parse, don't validate** — smart constructors produce well-typed values or
  structured errors. Invariants enforced at construction time.
- **Make illegal states unrepresentable** — distinct types, case objects, and
  smart constructors encode domain invariants in the type system.

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
| `std/tables` | `Table[string, T]` | For `Session.accounts`, `Session.primaryAccounts`, `Request.createdIds` |
| `std/sets` | `HashSet[string]` | For `CoreCapabilities.collationAlgorithms` — proper set semantics (no duplicates, O(1) lookup) |
| `std/strutils` | `parseEnum[T](s, default)` | `func`, total, no exceptions — replaces manual `CapabilityKind` case statement |
| `std/json` | `JsonNode`, `JsonNodeKind` | For untyped capability data (`ServerCapability`), `Invocation.arguments` |
| `std/sequtils` | `allIt`, `mapIt`, `filterIt`, `anyIt` | Templates that expand inline — work inside `func` |
| `std/setutils` | `set[CapabilityKind]` | Bitset for efficient capability membership checks |
| built-in `set[char]` | Charset validation constants | `{'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}` for `Id` validation |

### Modules evaluated and rejected

| Module | Reason not used in Layer 1 |
|--------|---------------------------|
| `std/times` | `times.parse` is `proc` not `func` (line 2245 of times.nim). Calling it from Layer 1 violates functional core purity. A convenience `toDateTime` converter may be provided in a separate utility module outside the pure core. |
| `std/parseutils` | `skipWhile` is `proc` not `func` (line 325 of parseutils.nim). Cannot call from smart constructors under `strictFuncs`. Pattern replicated using `allIt` template from sequtils. |
| `std/uri` | `parseUri` raises `UriParseError`. `apiUrl` is passed directly to the HTTP client — no need to decompose. |
| `std/options` | Project convention: `Opt[T]` from `results` library. `Opt[T]` is `Result[T, void]`, sharing the `?` operator with `Result[T, E]` for uniform ROP composition. stdlib `Option[T]` has `map`/`flatMap` but no `?` integration. |
| `std/enumutils` | `parseEnum` from `strutils` already covers enum parsing needs. |
| `std/httpcore` | `HttpCode` is relevant to Layer 2/7 (transport errors), not Layer 1. |

### Critical Nim findings that constrain the design

| Finding | Impact |
|---------|--------|
| `{.requiresInit.}` works on distinct types (verified in system.nim) | Can enforce initialisation on all distinct types |
| `hash` auto-borrows for distinct types (verified in hashes.nim) | No manual `hash` implementation needed — `{.borrow.}` suffices |
| `$` for string-backed enums returns the **symbolic name**, not the backing string (system/dollars.nim) | Need custom `func capabilityUri(kind): string` for serialisation |
| `parseEnum[T](s, default)` is a `func` (strutils.nim line 1326) | Total, no exceptions — can be called from pure code |
| `parseEnum` matches against **both** symbolic names and string backing values | Negligible risk: JMAP servers send URIs, not Nim identifiers |
| `RangeDefect` bypasses `{.push raises: [].}` (Defect, not CatchableError) | Range types are technically `raises: []` compatible but crash instead of returning `Result` |
| `allIt` is a template (sequtils.nim line 811) | Expands inline — works inside `func` for charset validation |
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
Layer 2's `ClientError` can wrap `ValidationError` for error composition.

**Module:** `src/jmap_client/validation.nim`

### 1.2 Smart Constructor Pattern

Every type with construction-time invariants has a smart constructor following
this pattern:

```nim
func parseFoo*(raw: InputType): Result[Foo, ValidationError]
```

- Always a `func` (pure, no side effects).
- Always returns `Result` (total, never raises).
- The raw constructor (`Foo(raw)`) is not exported — only the smart constructor
  is public.
- For types with no invariants beyond the base type, the raw constructor may be
  exported directly.

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

**Module:** `src/jmap_client/primitives.nim` (or a shared internal module).

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

Two constructors following Decision D4 (dual validation strictness):

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
type JmapInt* = distinct int64
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
primary use is in Layer 5 (`/query` request `position` and `anchorOffset`
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

```nim
const AsciiDigits = {'0'..'9'}

func parseDate*(raw: string): Result[Date, ValidationError] =
  ## Pattern validates RFC 3339 date-time structural constraints:
  ## - Minimum length (YYYY-MM-DDTHH:MM:SSZ = 20 chars)
  ## - 'T' separator present and uppercase
  ## - No lowercase 't' or 'z'
  ## - If fractional seconds present, must not be all zeroes
  ## Does NOT perform full calendar validation (e.g., February 30).
  if raw.len < 20:
    return err(validationError("Date", "too short for RFC 3339 date-time", raw))
  # Check date part: YYYY-MM-DD
  if not (raw[0..3].allIt(it in AsciiDigits) and raw[4] == '-' and
          raw[5..6].allIt(it in AsciiDigits) and raw[7] == '-' and
          raw[8..9].allIt(it in AsciiDigits)):
    return err(validationError("Date", "invalid date portion", raw))
  # Check 'T' separator
  if raw[10] != 'T':
    return err(validationError("Date", "'T' separator must be uppercase", raw))
  # Check time part: HH:MM:SS
  if not (raw[11..12].allIt(it in AsciiDigits) and raw[13] == ':' and
          raw[14..15].allIt(it in AsciiDigits) and raw[16] == ':' and
          raw[17..18].allIt(it in AsciiDigits)):
    return err(validationError("Date", "invalid time portion", raw))
  # Check no lowercase letters (RFC requires uppercase T, Z)
  if raw.anyIt(it in {'t', 'z'}):
    return err(validationError("Date", "letters must be uppercase", raw))
  # Check fractional seconds: if present, must not be ".0", ".00", ".000" etc.
  if raw.len > 19 and raw[19] == '.':
    let dotEnd = block:
      var i = 20
      while i < raw.len and raw[i] in AsciiDigits: inc i
      i
    if raw[20 ..< dotEnd].allIt(it == '0'):
      return err(validationError("Date", "zero fractional seconds must be omitted", raw))
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
type UTCDate* = distinct string
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
type AccountId* = distinct string
defineStringDistinctOps(AccountId)
```

**Smart constructor:**

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: non-empty, no control characters.
  ## AccountIds are server-assigned — same lenient rules as parseIdFromServer.
  if raw.len == 0:
    return err(validationError("AccountId", "must not be empty", raw))
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
  ## Non-empty. The RFC does not further constrain state tokens.
  if raw.len == 0:
    return err(validationError("JmapState", "must not be empty", raw))
  ok(JmapState(raw))
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
NOT include the `#` prefix — that is a serialisation concern (Layer 3).

```nim
type CreationId* = distinct string
func `==`*(a, b: CreationId): bool {.borrow.}
func `$`*(a: CreationId): string {.borrow.}
func hash*(a: CreationId): Hash {.borrow.}
```

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
  ckCore = "urn:ietf:params:jmap:core"
  ckMail = "urn:ietf:params:jmap:mail"
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

`$ckCore` returns `"ckCore"` (the symbolic name), NOT the URI string. For
serialisation to JSON, a custom function is needed:

```nim
func capabilityUri*(kind: CapabilityKind): string =
  ## Returns the IANA-registered URI for a known capability.
  ## Panics on ckUnknown — callers must use the rawUri from ServerCapability.
  case kind
  of ckCore: "urn:ietf:params:jmap:core"
  of ckMail: "urn:ietf:params:jmap:mail"
  of ckSubmission: "urn:ietf:params:jmap:submission"
  of ckVacationResponse: "urn:ietf:params:jmap:vacationresponse"
  of ckWebsocket: "urn:ietf:params:jmap:websocket"
  of ckMdn: "urn:ietf:params:jmap:mdn"
  of ckSmimeVerify: "urn:ietf:params:jmap:smimeverify"
  of ckBlob: "urn:ietf:params:jmap:blob"
  of ckQuota: "urn:ietf:params:jmap:quota"
  of ckContacts: "urn:ietf:params:jmap:contacts"
  of ckCalendars: "urn:ietf:params:jmap:calendars"
  of ckSieve: "urn:ietf:params:jmap:sieve"
  of ckUnknown: ""  # caller must use rawUri instead
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
deserialisation (Layer 3), which validates each field individually.

**Decision D6.** `HashSet[string]` from `std/sets` for `collationAlgorithms`
instead of `seq[string]`. The RFC defines this as a list of identifiers for
membership testing ("does the server support this collation?"). `HashSet`
provides: no duplicates, O(1) lookup via `in`, proper set semantics. Layer 3
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

func hasCapability*(account: Account, kind: CapabilityKind): bool =
  account.accountCapabilities.anyIt(it.kind == kind)
```

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
func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError] =
  ## Non-empty. No RFC 6570 parsing — template expansion is Layer 7 (IO).
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
etc.) is an IO concern belonging to Layer 7 (transport). Layer 1 stores the
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
  accounts*: Table[string, Account]            ## keyed by raw AccountId string
  primaryAccounts*: Table[string, AccountId]   ## keyed by raw capability URI
  username*: string                            ## or empty string if none
  apiUrl*: string                              ## URL for JMAP API requests
  downloadUrl*: UriTemplate                    ## RFC 6570 Level 1 template
  uploadUrl*: UriTemplate                      ## RFC 6570 Level 1 template
  eventSourceUrl*: UriTemplate                 ## RFC 6570 Level 1 template
  state*: JmapState                            ## session state token
```

All fields are required per the RFC. `accounts` and `primaryAccounts` use raw
string keys (not `CapabilityKind` or `AccountId`) to avoid the `ckUnknown` key
collision problem.

**Smart constructor:**

```nim
func parseSession*(
  capabilities: seq[ServerCapability],
  accounts: Table[string, Account],
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

**Accessor helpers:**

```nim
func coreCapabilities*(session: Session): CoreCapabilities =
  ## Returns the core capabilities. Total function (no Result) because
  ## parseSession guarantees ckCore is present.
  for cap in session.capabilities:
    if cap.kind == ckCore:
      return cap.core
  # Unreachable if Session was constructed via parseSession.
  # Under strictCaseObjects, this branch is required for exhaustiveness.
  CoreCapabilities()

func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  for cap in session.capabilities:
    if cap.kind == kind:
      return ok(cap)
  err()

func primaryAccount*(session: Session, kind: CapabilityKind): Opt[AccountId] =
  let uri = capabilityUri(kind)
  if uri.len > 0 and session.primaryAccounts.hasKey(uri):
    return ok(session.primaryAccounts[uri])
  err()

func findAccount*(session: Session, id: AccountId): Opt[Account] =
  let key = string(id)
  if session.accounts.hasKey(key):
    return ok(session.accounts[key])
  err()
```

**Module:** `src/jmap_client/session.nim`

---

## 6. Request/Response Envelope

### 6.1 Invocation

**RFC reference:** §3.2 (lines 865–880).

A tuple of three elements: method name, arguments object, method call ID.

**JSON serialisation quirk:** Invocations are serialised as 3-element JSON
arrays `["name", {args}, "callId"]`, NOT as JSON objects. This is a Layer 3
concern — the type definition here is the Nim representation.

```nim
import std/json

type Invocation* = object
  name*: string             ## method name (request) or response name
  arguments*: JsonNode      ## named arguments — always a JObject
  methodCallId*: MethodCallId  ## correlates responses to requests
```

`arguments` is `JsonNode` at the envelope level. Typed extraction into
concrete method response types happens in Layer 5.

**No smart constructor.** Constructed by the Layer 4 builder (requests) or
Layer 3 deserialiser (responses).

**Module:** `src/jmap_client/envelope.nim`

### 6.2 Request

**RFC reference:** §3.3 (lines 882–943).

```nim
import std/tables

type Request* = object
  using*: seq[string]              ## capability URIs the client wishes to use
  methodCalls*: seq[Invocation]    ## processed sequentially by server
  createdIds*: Opt[Table[CreationId, Id]]  ## optional; enables proxy splitting
```

`using` is `seq[string]` (raw URIs, not `seq[CapabilityKind]`) because vendor
extension URIs would collide at `ckUnknown`.

`createdIds` is `Opt` because the RFC specifies it as optional. If present in
the request, the response will also include it.

**No smart constructor.** Built by the Layer 4 request builder.

**Module:** `src/jmap_client/envelope.nim`

### 6.3 Response

**RFC reference:** §3.4 (lines 975–1003).

```nim
type Response* = object
  methodResponses*: seq[Invocation]            ## same format as methodCalls
  createdIds*: Opt[Table[CreationId, Id]]      ## only if given in request
  sessionState*: JmapState                     ## current Session.state value
```

**No smart constructor.** Parsed from JSON by Layer 3.

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
  RefPathCreated*            = "/created"             ## created IDs from /set result
  RefPathUpdated*            = "/updated"             ## updated IDs from /changes result
  RefPathUpdatedProperties*  = "/updatedProperties"   ## changed properties from /changes result
```

**No smart constructor.** The server validates result references during
processing. Invalid references produce `invalidResultReference` method-level
errors.

**Module:** `src/jmap_client/envelope.nim`

### 6.5 Referencable[T]

**Architecture reference:** Decision 3G.

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

func referenceTo*[T](ref: ResultReference): Referencable[T] =
  Referencable[T](kind: rkReference, reference: ref)
```

**Serialisation note (Layer 3).** `Referencable[seq[Id]]` serialises as either
`"ids": [...]` (direct) or `"#ids": {"resultOf": ..., "name": ..., "path": ...}`
(reference). The `#` prefix on the JSON key name is the discriminator on the
wire. This is a Layer 3 concern.

**Module:** `src/jmap_client/envelope.nim`

---

## 7. Borrowed Operations Summary

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

All borrowed operations are `func` and `{.raises: [].}` compatible.

---

## 8. Smart Constructor Summary

| Type | Constructor | Validation | Returns |
|------|------------|-----------|---------|
| `Id` | `parseId` | Strict: 1-255 octets, base64url charset | `Result[Id, ValidationError]` |
| `Id` | `parseIdFromServer` | Lenient: 1-255 octets, no control chars | `Result[Id, ValidationError]` |
| `UnsignedInt` | `parseUnsignedInt` | `0 <= value <= 2^53-1` | `Result[UnsignedInt, ValidationError]` |
| `JmapInt` | `parseJmapInt` | `-2^53+1 <= value <= 2^53-1` | `Result[JmapInt, ValidationError]` |
| `Date` | `parseDate` | Pattern: T separator, uppercase, no zero frac | `Result[Date, ValidationError]` |
| `UTCDate` | `parseUtcDate` | Date rules + ends with Z | `Result[UTCDate, ValidationError]` |
| `AccountId` | `parseAccountId` | Lenient: non-empty, no control chars | `Result[AccountId, ValidationError]` |
| `JmapState` | `parseJmapState` | Non-empty | `Result[JmapState, ValidationError]` |
| `MethodCallId` | `parseMethodCallId` | Non-empty | `Result[MethodCallId, ValidationError]` |
| `CreationId` | `parseCreationId` | Non-empty, no `#` prefix | `Result[CreationId, ValidationError]` |
| `UriTemplate` | `parseUriTemplate` | Non-empty | `Result[UriTemplate, ValidationError]` |
| `CapabilityKind` | `parseCapabilityKind` | Total (always succeeds) | `CapabilityKind` |
| `Session` | `parseSession` | Core cap present, URLs valid, templates have variables | `Result[Session, ValidationError]` |

All smart constructors are `func` (pure). None call `proc`s from the standard
library.

---

## 9. Module File Layout

```
src/jmap_client/
  validation.nim      ← ValidationError
  primitives.nim      ← Id, UnsignedInt, JmapInt, Date, UTCDate
                        borrow templates, charset constants
  identifiers.nim     ← AccountId, JmapState, MethodCallId, CreationId
  capabilities.nim    ← CapabilityKind, CoreCapabilities, ServerCapability
  session.nim         ← Account, AccountCapabilityEntry, UriTemplate, Session
  envelope.nim        ← Invocation, Request, Response,
                        ResultReference, Referencable[T]
  types.nim           ← Re-exports all of the above
```

### Import Graph

```
validation.nim       (no imports)
      ↑
primitives.nim       (std/hashes, std/sequtils)
      ↑
identifiers.nim      (std/hashes, std/sequtils)
      ↑              ↑
capabilities.nim     (std/hashes, std/sets, std/strutils, std/json)
      ↑
session.nim          (std/hashes, std/tables, std/json, std/sequtils)
      ↑
envelope.nim         (std/json, std/tables)
      ↑
types.nim            (re-exports all)
```

All arrows point upward — no cycles. Each module depends only on modules above
it in the diagram plus standard library imports.

`types.nim` re-exports everything for convenient single-import usage:

```nim
import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope

export validation, primitives, identifiers, capabilities, session, envelope
```

---

## 10. Test Fixtures

### 10.1 RFC §2.1 Session Example (Golden Test)

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
- `session.accounts` has 2 entries keyed by `"A13824"` and `"A97813"`
- `session.accounts["A13824"].isPersonal == true`
- `session.accounts["A13824"].accountCapabilities` has 2 entries (ckMail, ckContacts)
- `session.primaryAccounts["urn:ietf:params:jmap:mail"] == AccountId("A13824")`
- `session.username == "john@example.com"`
- `session.state == JmapState("75128aab4b1b")`
- `session.coreCapabilities.collationAlgorithms` contains `"i;ascii-numeric"`, `"i;ascii-casemap"`, `"i;unicode-casemap"`

**Note:** The RFC example has a typo: `"maxConcurrentRequest"` (singular)
instead of `"maxConcurrentRequests"` (plural, per the field definition in §2).
The deserialiser should accept both forms.

### 10.2 RFC §3.3.1 Request Example

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

### 10.3 RFC §3.4.1 Response Example

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

### 10.4 Edge Cases per Type

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
| `Date` | `"2014-10-30"` | `err` | too short, missing time |
| `UTCDate` | `"2014-10-30T06:12:00Z"` | `ok` | RFC example |
| `UTCDate` | `"2014-10-30T06:12:00+00:00"` | `err` | must be Z, not +00:00 |
| `CapabilityKind` | `"urn:ietf:params:jmap:core"` | `ckCore` | known URI |
| `CapabilityKind` | `"urn:ietf:params:jmap:mail"` | `ckMail` | known URI |
| `CapabilityKind` | `"https://vendor.example/ext"` | `ckUnknown` | vendor URI |
| `CapabilityKind` | `""` | `ckUnknown` | empty string |
| `CreationId` | `"#abc"` | `err` | must not include # prefix |
| `CreationId` | `"abc"` | `ok` | valid creation ID |
| `Session` | missing core capability | `err` | RFC MUST constraint |
| `Session` | downloadUrl without `{blobId}` | `err` | RFC MUST constraint |
| `Session` | valid RFC §2.1 example | `ok` | golden test |

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
