---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Type Safety

The compiler flags in `jmap_client.nimble` create a strict type environment.
This file documents how to work within it.

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
(e.g., `Id` has a 1-255 octet constraint). See `layer-1-design.md` §3.2-3.4.

## `{.requiresInit.}` — Smart Constructors

Forces explicit initialisation — `var id: AccountId` is rejected. Combine
with a validation function for the smart constructor pattern:

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("AccountId", "contains control characters", raw))
  ok(AccountId(raw))
```

Smart constructors return `Result[T, ValidationError]` — a structured error
with `typeName`, `message`, and `value`. Not `ClientError` (that is for
transport/request failures) and not bare `string` (loses context). Lift with
`mapErr` at the boundary where needed.

## Object Variants (Sum Types)

Nim's discriminated unions — equivalent to F#/OCaml/Haskell ADTs.

`strictCaseObjects` enforced per-module in `src/` via `{.experimental:
"strictCaseObjects".}`. Global enablement breaks `std/json`. Variant fields
require matching the discriminator in a `case` statement (`if` is insufficient).
Shared fields (before `case`) always accessible. Discriminator immutable after
construction. Adding a variant forces errors at all unhandled `case` sites.
Do not use `unsafeGet`/`unsafeValue` in `src/` modules — use `valueOr` instead.

### Two-variant sum (outer railway error):

```nim
type
  ClientErrorKind* = enum
    cekTransport
    cekRequest

  ClientError* = object
    case kind*: ClientErrorKind
    of cekTransport:
      transport*: TransportError
    of cekRequest:
      request*: RequestError
```

```nim
func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport: err.transport.message
  of cekRequest:
    if err.request.detail.isSome: err.request.detail.unsafeGet
    elif err.request.title.isSome: err.request.title.unsafeGet
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

  TransportError* = object
    message*: string                      # shared — always accessible
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
    description*: Opt[string]
    extras*: Opt[JsonNode]         # preserves non-standard server fields
```

When a few variants carry extra fields, use `case` with `else: discard`:

```nim
type SetError* = object
  rawType*: string
  description*: Opt[string]
  extras*: Opt[JsonNode]
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

func parseEmail*(raw: string): JmapResult[Email[Unvalidated]] = ...
func validateEmail*(e: Email[Unvalidated]): JmapResult[Email[Validated]] = ...
proc sendEmail*(e: Email[Validated]): JmapResult[void] = ...
# sendEmail(unvalidatedEmail)  # REJECTED: type mismatch
```

Use when the safety benefit is clear, not on every type.

## Nil Safety

- `strictNotNil` enabled: `ref T` may be nil, `ref T not nil` cannot.
- Prefer value types in functional core — nil impossible.
- For optional refs, use `Opt[ref T]` not nilable refs.
- `Uninit` + `ProveInit` warnings are errors — all vars provably initialised.

## Anti-Patterns

- **NEVER define `converter` procs** — silent implicit conversions, ambiguous
  overloads, hidden allocations.
- **`CStringConv` warning is an error** — catches dangerous implicit
  `string` -> `cstring` that creates dangling pointers under ARC.
- **Avoid `range[T]` for domain constraints** — `RangeDefect` is fatal, bypasses
  `raises: []`. Use smart constructors returning `Result` instead.
- **Concepts** — structural, not nominal. Simple flat concepts OK under strict
  mode. Deeply chained or recursive concepts interact unpredictably with
  `strictFuncs` and `raises: []` — avoid those.
