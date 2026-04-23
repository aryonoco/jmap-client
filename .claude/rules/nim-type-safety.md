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
(e.g., `Id` has a 1–255 octet constraint). See `layer-1-design.md` §3.2–3.4.

## Smart Constructors

Validation functions enforce domain constraints at construction time. They
return `Result[T, ValidationError]` via nim-results:

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1–255 octets, no control characters.
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("AccountId", "contains control characters", raw))
  ok(AccountId(raw))
```

`ValidationError` is a plain object with `typeName`, `message`, `value` fields.
Carried on the `Result` error rail — not an exception.

## Object Variants (Sum Types)

Nim's discriminated unions — equivalent to F#/OCaml/Haskell ADTs.

Standard Nim protects case objects: discriminator reassignment to a different
branch is a compile error, and accessing the wrong branch raises `FieldDefect`
at runtime. Shared fields (before `case`) always accessible. Discriminator
immutable after construction. Adding a variant forces errors at all unhandled
`case` sites.

## strictCaseObjects

Every src/ file enables `{.experimental: "strictCaseObjects".}`
immediately after its `{.push raises: ...}` pragma. Under strict, the
`FieldDefect` runtime check is replaced by a compile-time proof
obligation: every variant-field read must occur in a `case` branch
that provably matches the field's declaration. Four empirical rules
govern acceptance.

### Rule 1 — Case, not if

`if obj.kind == X: use obj.field` is NOT sufficient — strict only
proves discriminator values through `case` statements. Convert to
`case obj.kind of X: use obj.field`.

### Rule 2 — Match the declaration's branch structure

- If a field is declared in the object's `else:` branch, the use-site
  case must also go through `else:`. `case x.kind of <all of-arms>:
  ... else: <read else-field>` is strict-safe; `case x.kind of
  <value-in-else>: <read else-field>` is rejected — even when the
  value semantically falls under `else:`, strict requires literal
  structural match.
- If the type declares `of A, B: field: T` as a single combined arm,
  the use site must also combine them (`of A, B: use x.field`). Split-
  of-arms `of A: ... of B: ...` are rejected. To differentiate within
  a combined arm, use an inner `if x.kind == A:` — the outer combined
  `of` has already proved combined-arm membership, so the inner `if`
  is accepted for reading the variant field.

### Rule 3 — Accessors must be fields or templates

A `func` accessor returning the discriminator (`func kind(x): X =
x.rawKind`) hides the discriminator from strict. External `case
x.kind of Y: x.variantField` then fails — strict doesn't trace
through `func` bodies. Two fixes:

- **Preferred**: make the discriminator itself a public field
  (expose `errorType*: SetErrorType` directly).
- **Fallback**: use a `template` accessor — template expansion
  preserves symbol resolution, but the underlying field's visibility
  still governs external access. A private discriminator exposed only
  via template works within the defining module but fails from
  external modules.

### Rule 4 — Nested case objects aren't tracked across layers

If type A has `case k1: B` with B having its own `case k2: ...`,
strict proves only one level at a time — a use-site `case x.k1 of X:
case x.k2 of Y: x.innerField` is rejected even when logically valid.
Structural fix: extract the inner case into its own type and hold it
as a field. Each discriminator is then on its own type, so strict
tracks them independently.

### FFI panic avoidance

This project compiles with `--panics:on`, so any `Defect`
(`ResultDefect`, `FieldDefect`, `RangeDefect`, etc.) triggers
`rawQuit(1)` — immediate host-process termination, NO C-level error
return, NO cleanup, NO unwinding. For an FFI-exporting library that's
catastrophic.

- `.value` / `.error` / `.get()` route through `withAssertOk` →
  `raiseResultDefect` on Err. Strict-safe (the template is case-
  wrapped) but NOT panic-free. Do not use as an invariant-assertion
  in library code.
- **In "shouldn't-happen" contexts** (invariant already proved Ok):
  use `case x.isOk of true: x.unsafeValue of false: <default>`.
  Strict-safe (case proves the discriminator via literal match) AND
  panic-free (`unsafeValue` bypasses `withAssertOk`).
- **In error-handling contexts**: use `valueOr:` with an explicit
  `return err(...)` so the failure flows through the Result railway
  to the FFI boundary.

### `.unsafeValue` / `.unsafeError` / `.unsafeGet`

Bypass `withAssertOk` — direct variant-field reads. Under strict,
they're only accepted when the callsite wraps the access in a case
that proves the discriminator (e.g., `case x.isOk of true:
x.unsafeValue`). Naked `.unsafeGet` with no guard is strict-fatal.

### `var` parameters are not tracked by strict

`guards.nim:47-57` in the Nim compiler: `skParam` is treated as a
let-location only when its type is NOT `tyVar`. Consequence: calling
`.get()` / `.value()` on a var-lvalue picks the var-parameter
overload in nim-results (`func get*[T: not void, E](self: var
Result[T, E]): var T`, a generic func whose body strict cannot
prove). Always let-bind first: `let tmp = varExpr; tmp.get()` (if Ok
proved) or `let tmp = varExpr; tmp.valueOr: return err(...)` (if
error-handling required).

Nimalyzer does not flag or enforce the experimental pragma; the
convention is enforced by code review and CI.

### Two-variant sum (error type):

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
  ## Resolves via UFCS — ``err.message`` calls this function.
  case err.kind
  of cekTransport: err.transport.message
  of cekRequest: err.request.message
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
    message*: string
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

### Case objects need an explicit `==` / `$` / `hash`

Auto-derived `==` on a case object fails with *parallel 'fields'
iterator does not work for 'case' objects*. The failure often
surfaces transitively — a `distinct seq[X]` / `distinct Table[K, X]`
whose `X` is a case object only breaks when something downstream
(borrowed `==`, `Result[Distinct, _]` equality) forces structural
equality through it. Fix at the case-object level with an explicit
arm-dispatch `==` (same for `$` and `hash` if the chain needs them);
never paper over it on the distinct wrapper.

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
- For optional values, use `Opt[T]` from nim-results, not nilable refs or `std/options`.
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
