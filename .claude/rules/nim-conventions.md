---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Nim Conventions

## Module Boilerplate

Every `.nim` file must start with this structure:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

import std/[strutils]       # std/ imports first
import ./types, ./errors    # local imports last
```

Layer 5 (`src/jmap_client.nim`) additionally has `{.push raises: [].}` after the
copyright header — this is the ONLY module with that pragma. All other modules
allow exceptions to propagate naturally.

## Error Handling

Errors are communicated
via exceptions that propagate naturally through Layers 1–4, and are caught
at the Layer 5 C ABI boundary.

### Error Type Hierarchy

```nim
# Construction errors (Layer 1 smart constructors):
ValidationError* = object of CatchableError
  typeName*: string     # e.g. "AccountId"
  value*: string        # the rejected input

# Transport/request errors (Layer 4):
TransportError* = object of CatchableError
  # ... (case object with kind discriminator)
RequestError* = object of CatchableError
  # ...
ClientError* = object of CatchableError
  # Wraps TransportError or RequestError

# Method/set errors — NOT exceptions, these are DATA in responses:
MethodError* = object        # plain object, not CatchableError
SetError* = object           # plain object, not CatchableError
```

### Smart Constructors

Smart constructors validate input and raise `ValidationError` on failure,
returning the validated type directly on success:

```nim
proc parseAccountId*(raw: string): AccountId =
  ## Lenient: 1–255 octets, no control characters.
  if raw.len < 1 or raw.len > 255:
    raise newException(ValidationError, "length must be 1-255 octets")
  if raw.anyIt(it < ' '):
    raise newException(ValidationError, "contains control characters")
  AccountId(raw)
```

### Layer 5 Exception Boundary

Layer 5 (`src/jmap_client.nim`) has `{.push raises: [].}` and wraps every
exported proc in `try/except`, converting exceptions to C error codes:

```nim
proc jmapDoSomething*(...): cint
    {.exportc: "jmap_do_something", dynlib, cdecl, raises: [].} =
  try:
    let result = internalOperation(...)
    return JMAP_OK
  except TransportError as e:
    return setLastError(e)
  except RequestError as e:
    return setLastError(e)
  except CatchableError as e:
    return setLastError(e)
```

The compiler enforces that no `CatchableError` escapes from `{.raises: [].}`
procs. `Defect` (programmer errors like index out of bounds) is NOT tracked
by `raises`. With `--panics:on` (enabled in this project), Defects abort
the process via `rawQuit(1)`. Validate all inputs defensively before
operations that could trigger Defects.

### Optional Values

Use `Option[T]` from `std/options` for optional values:

```nim
import std/options

proc findAccount(accounts: openArray[Account], id: AccountId): Option[Account] =
  for a in accounts:
    if a.id == id:
      return some(a)
  none(Account)

# Querying:
if opt.isSome: echo opt.get()
if opt.isNone: echo "missing"
```

## Conventions

- All routines use `proc`. Purity is maintained by convention:
  Layers 1–3 (types, serialisation, protocol logic) do not perform I/O or
  mutate global state. Layer 4 (transport) performs I/O. Layer 5 (C ABI)
  catches exceptions.
- **Parse, don't validate** — smart constructors produce well-typed values or
  raise structured errors. Invariants enforced at construction time, not
  checked later.

## Immutability

- `let` by default. `var` only in three patterns: (a) mutable accumulators
  in Layer 4/5; (b) local variable inside a `proc` when building a return
  value from stdlib containers whose APIs require mutation (e.g., `Table`);
  (c) `var` parameter for builder accumulation.
- `strictDefs` enabled — all variables must be initialised before use.
- Value types (`object`) preferred in domain core — `let` is deeply
  immutable. `let` on `ref` does NOT prevent field mutation.
- `openArray[T]` for read-only parameters. `collect` (std/sugar) over
  `.filterIt().mapIt()` for building new collections. `allIt`/`anyIt` for
  predicates. NEVER define `converter` procs.

## Expression-Oriented Style

```nim
# if/case/block as expressions:
let status = if code == 200: "ok" else: "error"
let description = case method.kind
  of jmkEcho: "echo test"
  of jmkMailboxGet: "fetch mailboxes"

# UFCS chaining over nested calls:
let result = items.filterIt(it.isActive).mapIt(it.name).foldl(a & ", " & b)

# collect (std/sugar) — preferred for building new collections:
let positives = collect:
  for x in items:
    if x > 0: x
```

Expression `if` MUST have `else`. Expression `case` must be exhaustive.
Do not nest `It`-templates — inner `it` shadows outer.

## Naming and Style

- `--styleCheck:error` — must match declaration-site casing.
- Types: `PascalCase`. Procs/vars/fields: `camelCase`.
- Enum values: lowercase prefix from type name (`cek` for `ClientErrorKind`,
  `tek` for `TransportErrorKind`).
- Comments/docstrings: British English. Identifiers: US English.
- `--hintAsError:DuplicateModuleImport` — no redundant imports.
