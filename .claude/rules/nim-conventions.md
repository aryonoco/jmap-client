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
import pkg/results          # pkg/ imports second
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

# Project alias (defined in types.nim):
JmapResult[T] = Result[T, JmapError]
```

### Constructors

```nim
# Explicit (works anywhere):
JmapResult[int].ok(42)
JmapResult[int].err(JmapError(kind: jekParse, message: "bad input"))
Opt[int].ok(42)          # same as Opt.some(42)
Opt[int].err()           # same as Opt.none(int)

# Shorthand (works only inside funcs where return type is inferred):
ok(42)                   # deduced from enclosing func's return type
err(JmapError(...))      # deduced from enclosing func's return type
```

### The `?` Operator — Early Return

**PREFIX operator**, like Rust's `?`. If the Result is err, immediately returns
from the enclosing function with that error. If ok, unwraps to the value.

```nim
func processAccount(raw: string): JmapResult[Account] =
  let id = ? parseAccountId(raw)       # returns early on error
  let session = ? loadSession(id)      # returns early on error
  let account = ? validateAccount(session)
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
# NEVER call .get() / .value() without checking .isOk first — raises Defect.
# Preferred patterns:
let name = result.valueOr: "default"       # template, lazily evaluated
let name = result.get("default")           # func, eagerly evaluated

# valueOr provides error access in the block:
let name = result.valueOr: logError(error); "fallback"

# Explicit branching:
if result.isOk:
  let val = result.get()
else:
  let e = result.error()
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

```nim
func safeParseInt(s: string): JmapResult[int] =
  try:
    ok(parseInt(s))
  except ValueError as e:
    err(JmapError(kind: jekParse, message: e.msg))
```

`try/except` inside `{.raises: [].}` is allowed — the compiler verifies all
possible exceptions are caught.

## Purity and Side Effects

- **`func`** = pure. Compiler-enforced `{.noSideEffect.}`. Cannot access global
  `var`, perform I/O, or call impure procs.
- **`proc`** = may have side effects (I/O, mutation of external state).
- `strictFuncs` is enabled — mutation through `ref` parameters also tracked.
- **Functional core** (func only, no I/O imports): `types.nim`, `errors.nim`,
  parsers, validators.
- **Imperative shell** (proc): HTTP, transport, FFI (`jmap_client.nim`).

```nim
# Pure core (func only):
func parseSession(raw: string): JmapResult[Session] =
  let json = ? safeParseJson(raw)
  ok(Session(apiUrl: ? extractField(json, "apiUrl")))

# Imperative shell (proc, calls pure core):
proc discoverSession(url: string): JmapResult[Session] =
  parseSession(httpGet(url))    # I/O at boundary, logic in pure core
```

## Immutability

- `let` by default. `var` only when unavoidable (I/O buffers, perf-critical
  sequence building).
- `strictDefs` enabled — all variables must be initialised before use.
- Value types (`object`) over `ref` in functional core — `let` is deeply
  immutable. `let` on `ref` does NOT prevent field mutation.
- `openArray[T]` for read-only parameters. `.filterIt().mapIt()` over `var` +
  mutation. NEVER define `converter` procs.

## Expression-Oriented Style

```nim
# if/case/block as expressions:
let status = if code == 200: "ok" else: "error"

let description = case method.kind
  of jmkEcho: "echo test"
  of jmkMailboxGet: "fetch mailboxes"

let value = block:
  let raw = fetchData()
  raw.strip()

# UFCS chaining over nested calls:
let result = items.filterIt(it.isActive).mapIt(it.name).foldl(a & ", " & b)
```

Expression `if` MUST have `else`. Expression `case` must be exhaustive.
Do not nest `It`-templates — inner `it` shadows outer.

## Naming and Style

- `--styleCheck:error` — must match declaration-site casing.
- Types: `PascalCase`. Procs/funcs/vars/fields: `camelCase`.
- Enum values: lowercase prefix from type name (`jek` for `JmapErrorKind`).
- Comments/docstrings: British English. Identifiers: US English.
- `--hintAsError:DuplicateModuleImport` — no redundant imports.
