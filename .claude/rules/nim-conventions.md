---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Nim Conventions

## Module Boilerplate

Every `.nim` file must start with this structure:

```nim
# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/[strutils]       # std/ imports first
import results              # vendored at vendor/nim-results/
import ./types, ./errors    # local imports last
```

`{.push raises: [].}` is non-negotiable. It makes the compiler reject any function
that could raise a `CatchableError`. `Defect` (programmer errors like index out of
bounds) is NOT tracked by `raises` — it always propagates and crashes. This is
intentional.

## Error Handling — Railway Oriented Programming

This project uses `results` 0.5.1 (nim-results by arnetheduck).

### Core Types

```nim
Result[T, E]   # Success(T) | Error(E) — stack-allocated discriminated union
Opt[T]         # Result[T, void] — optional value, no error payload

# Three lifecycle railways (architecture-options.md §1.6C):
# Track 0 (construction): Result[T, ValidationError]   — smart constructors
# Track 1 (outer):        JmapResult[T]                — transport/request
# Track 2 (inner):        Result[T, MethodError]       — per-invocation
# Data-level:             Result[T, SetError]           — per-item in /set

# Project alias (defined in types.nim):
JmapResult[T] = Result[T, ClientError]
```

### Constructors

```nim
# Explicit (works anywhere):
JmapResult[int].ok(42)
JmapResult[int].err(ClientError(kind: cekTransport,
  transport: TransportError(kind: tekNetwork, message: "connection refused")))
Opt[int].ok(42)          # same as Opt.some(42)
Opt[int].err()           # same as Opt.none(int)

# Shorthand (works only inside funcs where return type is inferred):
ok(42)                   # deduced from enclosing func's return type
err(ClientError(...))    # deduced from enclosing func's return type
```

### The `?` Operator — Early Return

**PREFIX operator**, like Rust's `?`. If the Result is err, immediately returns
from the enclosing function with that error. If ok, unwraps to the value.

```nim
proc processAccount(client: JmapClient, raw: string): JmapResult[Account] =
  let session = ? client.discoverSession()  # outer railway: ClientError on failure
  let id = ? parseAccountId(raw)            # returns early on ClientError
  let account = ? validateAccount(session, id)
  ok(account)
```

The enclosing function's return type must be a compatible `Result`. If error types
differ, use `mapErr` to convert before `?`.

### Chaining with `map` / `flatMap` / `mapErr`

```nim
# map: transform success value (infallible)
# flatMap: chain fallible operations (monadic bind)
# mapErr: transform error value

func getSubject(raw: string): JmapResult[string] =
  parseEmail(raw)                        # JmapResult[Email]
    .flatMap(extractHeaders)             # JmapResult[Headers]
    .map(proc(h: Headers): string = h.subject)  # JmapResult[string]
    .mapErr(enrichError)                 # transform error if present
```

### Safe Access

```nim
# NEVER bare .get() / .value() — raises Defect. Preferred:
let name = result.valueOr: "default"       # template, lazily evaluated
let name = result.get("default")           # func, eagerly evaluated
let name = result.valueOr: logError(error); "fallback"  # error access in block
```

### `Opt[T]` (Optional Values)

```nim
func findAccount(accounts: openArray[Account], id: AccountId): Opt[Account] =
  for a in accounts:
    if a.id == id:
      return Opt.some(a)
  Opt.none(Account)

# Querying:
if opt.isSome: echo opt.get()
if opt.isNone: echo "missing"

# Use ? for early return:
func process(id: AccountId): Opt[string] =
  let account = ? findAccount(allAccounts, id)
  Opt.some(account.name)
```

### Wrapping Exception-Raising Code

Domain smart constructors return `Result[T, ValidationError]` — not
`ClientError`. Stdlib bridges (e.g., wrapping `parseInt`) may use
`Result[T, string]`. Use `mapErr` to lift into `JmapResult` at the boundary:

```nim
# Stdlib bridge — wraps exception-raising code with simple error:
func safeParseInt(s: string): Result[int, string] =
  try: ok(parseInt(s))
  except ValueError as e: err(e.msg)

# Lift into outer railway at the boundary via mapErr:
func parsePort(s: string): JmapResult[int] =
  safeParseInt(s).mapErr(toTransportError)
```

`try/except` inside `{.raises: [].}` is allowed — the compiler verifies all
possible exceptions are caught.

**No try/except in the functional core.** Layer 1-3 source modules must never
use try/except. The safeParseInt bridge pattern is for Layer 4 (imperative
shell) only, where stdlib procs that raise must be wrapped at the IO boundary.
In the functional core, avoid exception-raising stdlib calls entirely.

## Purity and Side Effects

- **`func`** = pure. Compiler-enforced `{.noSideEffect.}`. Cannot access global
  `var`, perform I/O, or call impure procs.
- **`proc`** = may have side effects (I/O, mutation of external state).
- `strictFuncs` is enabled — mutation through `ref` parameters also tracked.
- **Functional core** (func only, no I/O imports): `types.nim`, `errors.nim`,
  parsers, validators.
- **Imperative shell** (proc): HTTP, transport, FFI (`jmap_client.nim`).
- **Parse, don't validate** — smart constructors produce well-typed values or
  structured errors. Invariants enforced at construction time, not checked later.

```nim
# Pure core (func only):
func parseSession(raw: string): JmapResult[Session] =
  let json = ? safeParseJson(raw)
  ok(Session(apiUrl: ? extractField(json, "apiUrl")))

# Imperative shell (proc, calls pure core):
proc discoverSession(client: JmapClient): JmapResult[Session] =
  let body = ? client.httpGet(client.baseUrl)  # ClientError on transport failure
  parseSession(body)                            # ClientError on parse failure
```

## Immutability

- `let` by default. `var` only in three patterns: (a) mutable accumulators
  in the imperative shell; (b) local variable inside `func` when building a
  return value from stdlib containers whose APIs require mutation (e.g.,
  `Table`); (c) owned `var` parameter in `func` for builder accumulation
  (Decision 3.3B) — `strictFuncs` permits mutation of owned `var` parameters;
  only mutation through immutable parameters' `ref`/`ptr` chains is forbidden.
  `strictFuncs` enforces that mutation does not escape in patterns (b) and (c).
- `strictDefs` enabled — all variables must be initialised before use.
- Value types (`object`) over `ref` in functional core — `let` is deeply
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
- Types: `PascalCase`. Procs/funcs/vars/fields: `camelCase`.
- Enum values: lowercase prefix from type name (`cek` for `ClientErrorKind`,
  `tek` for `TransportErrorKind`).
- Comments/docstrings: British English. Identifiers: US English.
- `--hintAsError:DuplicateModuleImport` — no redundant imports.
