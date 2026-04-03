---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Type Safety

## Distinct Types for Domain Identifiers

Prevent mixing identifiers that are all strings at runtime. A bare `distinct`
type has ZERO operations — borrow using templates:

```nim
type
  AccountId* = distinct string
  EmailId* = distinct string
  BlobId* = distinct string
```

```nim
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

defineStringDistinctOps(AccountId)
defineStringDistinctOps(EmailId)
defineStringDistinctOps(BlobId)
```

Do NOT borrow `&` — concatenating IDs is nonsensical.

Explicit conversion: `string(id)` to unwrap, `AccountId(s)` to wrap.

**When NOT to use `defineStringDistinctOps`.** Opaque token types where `len`
is semantically meaningless (e.g., `JmapState`, `MethodCallId`, `CreationId`)
should manually borrow only `==`, `$`, `hash` — omitting `len`. The template
includes `len` because it targets identifier types where length IS meaningful
(e.g., `Id` has a 1–255 octet constraint). See `layer-1-design.md` §3.2–3.4.

## Smart Constructors

Validation functions enforce domain constraints at construction time. They
raise `ValidationError` on invalid input and return the validated type
directly on success:

```nim
proc parseAccountId*(raw: string): AccountId =
  ## Lenient: 1–255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2).
  if raw.len < 1 or raw.len > 255:
    raise newException(ValidationError, "length must be 1-255 octets")
  if raw.anyIt(it < ' '):
    raise newException(ValidationError, "contains control characters")
  AccountId(raw)
```

`ValidationError` is a `CatchableError` with `typeName`, `value` fields
and the inherited `msg` field. Not `ClientError` (that is for transport/request
failures) and not bare `string` (loses context).

## Object Variants (Sum Types)

Nim's discriminated unions — equivalent to F#/OCaml/Haskell ADTs.

Standard Nim protects case objects: discriminator reassignment to a different
branch is a compile error, and accessing the wrong branch raises `FieldDefect`
at runtime. Shared fields (before `case`) always accessible. Discriminator
immutable after construction. Adding a variant forces errors at all unhandled
`case` sites.

### Two-variant sum (error type):

```nim
type
  ClientErrorKind* = enum
    cekTransport
    cekRequest

  ClientError* = object of CatchableError
    case kind*: ClientErrorKind
    of cekTransport:
      transport*: TransportError
    of cekRequest:
      request*: RequestError
```

```nim
proc message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport: err.transport.msg
  of cekRequest:
    if err.request.detail.isSome: err.request.detail.get()
    elif err.request.title.isSome: err.request.title.get()
    else: err.request.rawType
  # Exhaustive — adding a new ClientErrorKind variant forces a compile error here
```

### Case object with shared field and sparse branches (transport errors):

```nim
type
  TransportErrorKind* = enum
    tekNetwork
    tekTls
    tekTimeout
    tekHttpStatus

  TransportError* = object of CatchableError
    case kind*: TransportErrorKind
    of tekHttpStatus:
      httpStatus*: int                    # only accessible after matching kind
    of tekNetwork, tekTls, tekTimeout:
      discard
```

### Enum with string backing + lossless round-trip (method/set errors):

```nim
type
  MethodErrorType* = enum
    metServerFail = "serverFail"
    metInvalidArguments = "invalidArguments"
    # ... (exhaustive over RFC variants)
    metUnknown                     # catch-all for server extensions

  MethodError* = object            # flat — all variants share same shape
    errorType*: MethodErrorType
    rawType*: string               # always populated, lossless round-trip
    description*: Option[string]
    extras*: Option[JsonNode]      # preserves non-standard server fields
```

When a few variants carry extra fields, use `case` with `else: discard`:

```nim
type SetError* = object
  rawType*: string
  description*: Option[string]
  extras*: Option[JsonNode]
  case errorType*: SetErrorType
  of setInvalidProperties: properties*: seq[string]
  of setAlreadyExists: existingId*: Id
  else: discard
```

## Enums

- Constrain values to known sets — NEVER use `string` for a finite set.
- `--warningAsError:EnumConv` — no implicit enum conversions.
- `--warningAsError:HoleEnumConv` — no integer->enum for enums with gaps.
- String values via `= "literal"` for serialisation.
- Always handle ALL variants — avoid catch-all `else`.

```nim
type MethodName* = enum
  mnMailboxGet = "Mailbox/get"
  mnMailboxSet = "Mailbox/set"
  mnEmailGet = "Email/get"
  mnEmailSet = "Email/set"
```

**Gotcha:** `$` on a string-backed enum returns the **backing string**, not the
symbolic name (`$mnMailboxGet` -> `"Mailbox/get"`). `symbolName` from
`std/enumutils` returns the symbolic name (`symbolName(mnMailboxGet)` ->
`"mnMailboxGet"`). For variants without a backing string (e.g., a catch-all
`metUnknown`), `$` falls back to the symbolic name. For FFI enums:
`{.size: sizeof(cint).}` + explicit ordinals.

## Phantom Types

Generic markers for compile-time state transitions. Zero runtime cost:

```nim
type
  Validated* = object; Unvalidated* = object
  Email*[State] = object
    id*: EmailId; subject*: string; body*: string

proc parseEmail*(raw: string): Email[Unvalidated] = ...
proc validateEmail*(e: Email[Unvalidated]): Email[Validated] = ...
proc sendEmail*(e: Email[Validated]) = ...
# sendEmail(unvalidatedEmail)  # REJECTED: type mismatch
```

Use when the safety benefit is clear, not on every type.

## Nil Avoidance

- Prefer value types in domain core — nil impossible.
- For optional values, use `Option[T]` from `std/options`, not nilable refs.
- `Uninit` + `ProveInit` warnings are errors — all vars provably initialised.

## Anti-Patterns

- **NEVER define `converter` procs** — silent implicit conversions, ambiguous
  overloads, hidden allocations.
- **`CStringConv` warning is an error** — catches dangerous implicit
  `string` -> `cstring` that creates dangling pointers under ARC.
- **Avoid `range[T]` for domain constraints** — `RangeDefect` is fatal and
  crashes the process. Use smart constructors that raise `ValidationError`
  instead.
- **Concepts** — structural, not nominal. Simple flat concepts are acceptable.
  Deeply chained or recursive concepts can cause cryptic compiler errors —
  avoid those.
