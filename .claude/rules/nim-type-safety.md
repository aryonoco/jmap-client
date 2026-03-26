---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Type Safety

The compiler flags in `jmap_client.nimble` create a strict type environment.
This file documents how to work within it.

## Distinct Types for Domain Identifiers

Prevent mixing identifiers that are all strings at runtime:

```nim
type
  AccountId* = distinct string
  EmailId* = distinct string
  BlobId* = distinct string
  ThreadId* = distinct string
  MailboxId* = distinct string
```

A bare `distinct` type has ZERO operations. Borrow selectively:

```nim
func `==`*(a, b: AccountId): bool {.borrow.}
func `$`*(a: AccountId): string {.borrow.}
func len*(a: AccountId): int {.borrow.}
func hash*(a: AccountId): Hash {.borrow.}
```

For bulk borrowing across multiple ID types, use a template:

```nim
template defineIdOps(T: typedesc) =
  func `==`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}

defineIdOps(AccountId)
defineIdOps(EmailId)
defineIdOps(BlobId)
```

Do NOT borrow `&` — concatenating IDs is nonsensical.

Explicit conversion: `string(id)` to unwrap, `AccountId(s)` to wrap.

## `{.requiresInit.}` — Smart Constructors

Forces explicit initialisation — cannot rely on zero-default:

```nim
type AccountId* {.requiresInit.} = distinct string

# var id: AccountId         # REJECTED: must be explicitly initialised
let id = AccountId("abc")   # OK
```

Combine with a validation function for the smart constructor pattern:

```nim
func parseAccountId*(raw: string): JmapResult[AccountId] =
  if raw.len == 0:
    return err(JmapError(kind: jekParse, message: "empty account ID"))
  ok(AccountId(raw))
```

## Object Variants (Sum Types)

Nim's discriminated unions — equivalent to F#/OCaml/Haskell ADTs:

```nim
type
  JmapErrorKind* = enum
    jekParse
    jekNetwork
    jekAuth
    jekProtocol

  JmapError* = object
    message*: string           # shared field — always accessible
    case kind*: JmapErrorKind
    of jekParse:
      detail*: string
    of jekNetwork:
      statusCode*: int
    of jekAuth:
      realm*: string
    of jekProtocol:
      methodName*: string
```

`--experimental:strictCaseObjects` is enabled:
- Cannot access variant-specific fields without matching the discriminator.
  Shared fields (before `case`) are always accessible without checks.
- Cannot change the discriminator after construction.
- Adding a variant forces compile errors at all unhandled `case` sites.

```nim
func errorMessage*(e: JmapError): string =
  case e.kind
  of jekParse: "Parse error: " & e.detail
  of jekNetwork: "Network error: " & $e.statusCode
  of jekAuth: "Auth required: " & e.realm
  of jekProtocol: "Protocol error in " & e.methodName
  # Exhaustive — adding a new JmapErrorKind variant forces a compile error here
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

For enums exposed across FFI, add `{.size: sizeof(cint).}` and explicit
ordinal values (see `nim-ffi-boundary.md`).

## Phantom Types

Generic marker types for compile-time state transitions:

```nim
type
  Validated* = object
  Unvalidated* = object

  Email*[State] = object
    id*: EmailId
    subject*: string
    body*: string

func parseEmail*(raw: string): JmapResult[Email[Unvalidated]] = ...
func validateEmail*(e: Email[Unvalidated]): JmapResult[Email[Validated]] = ...
proc sendEmail*(e: Email[Validated]): JmapResult[void] = ...
# sendEmail(unvalidatedEmail)  # REJECTED: type mismatch
```

Use when the safety benefit is clear, not on every type.

## Nil Safety

- `--experimental:strictNotNil` enabled.
- `ref T` may be nil. `ref T not nil` guaranteed non-nil.
- Prefer value types in the functional core — nil is impossible.
- For optional references, use `Opt[ref T]` (explicit) not nilable refs.
- `--warningAsError:Uninit` + `ProveInit` — all vars must be provably initialised.

## Anti-Patterns

- **NEVER define `converter` procs** — silent implicit conversions, ambiguous
  overloads, hidden allocations.
- **`CStringConv` warning is an error** — catches dangerous implicit
  `string` -> `cstring` that creates dangling pointers under ARC.
- **Concepts** — structural, not nominal. Still experimental in 2.2.
  Use sparingly for genuinely structural constraints.
