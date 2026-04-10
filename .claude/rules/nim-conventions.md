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

{.push raises: [], noSideEffect.}   # L1–L3 modules

import std/[strutils]       # std/ imports first
import ./types, ./errors    # local imports last
```

- **L1–L3** (types, serde, protocol): `{.push raises: [], noSideEffect.}` —
  compiler-enforced total functions AND purity. Every routine in the module
  must be side-effect free, regardless of whether it uses `func` or `proc`.
- **L4** (IO/transport) and **L5** (C ABI exports): `{.push raises: [].}` —
  only totality enforced; side effects are legitimate for IO and FFI.

Error handling uses `Result[T, E]` from nim-results throughout.

## Error Handling

All error handling uses Railway-Oriented Programming via nim-results.
All error types are plain objects (not exceptions) carried on the
`Result[T, E]` error rail. The `?` operator provides early-return
error propagation.

### Error Type Hierarchy

```nim
# Construction errors (Layer 1 smart constructors):
ValidationError* = object
  typeName*: string     # e.g. "AccountId"
  message*: string      # the failure reason
  value*: string        # the rejected input

# Transport/request errors (Layer 4):
TransportError* = object     # case object with kind discriminator
RequestError* = object       # RFC 7807 problem details
ClientError* = object        # wraps TransportError or RequestError

# Per-invocation and per-item errors — DATA in responses:
MethodError* = object        # plain object
SetError* = object           # plain object

# Railway aliases:
JmapResult*[T] = Result[T, ClientError]   # outer railway
```

### Smart Constructors

Smart constructors return `Result[T, ValidationError]`:

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1–255 octets, no control characters.
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("AccountId", "contains control characters", raw))
  ok(AccountId(raw))
```

### Serde Conventions

- **Lenient fromJson for server data** — All `fromJson` for distinct types
  use the lenient `*FromServer` parser variant (e.g., `parseIdFromServer`,
  `parseKeywordFromServer`). Strict parsers (e.g., `parseId`,
  `parseKeyword`) are for client-constructed values only. Postel's law:
  be lenient on receive.
- **Strict/lenient pairs are principled, not mechanical** — The pair exists
  only when there is a meaningful gap between spec-specific constraints
  (e.g., IMAP forbidden chars for Keyword) and structural constraints
  (non-empty, bounded length, no control chars). When no gap exists (e.g.,
  `MailboxRole`), a single parser suffices for both client and server use.
- **Creation types and filter conditions are toJson-only** — Types that
  flow client → server (creation models like `IdentityCreate`,
  `MailboxCreate`; query specifications like `MailboxFilterCondition`) have
  `toJson` but no `fromJson`. The server never sends these back.

### Builder Conventions

- **Entity-specific builders accept typed creation models** — Custom
  builder functions that exist for other reasons (extra parameters like
  `onDestroyRemoveEmails`) should accept typed creation models (e.g.,
  `Table[CreationId, MailboxCreate]`) rather than raw `JsonNode`. The
  builder calls `toJson` internally. Generic builders (`addSet[T]`) accept
  `JsonNode` because they must be entity-agnostic.

### Layer 5 C ABI Boundary

Layer 5 pattern-matches on `Result` values to produce C error codes.
Stdlib IO calls (in L4) that can raise are wrapped in `try/except` +
`{.cast(raises: [CatchableError]).}` to convert exceptions to `Result`
at the IO boundary. L4–L5 use `{.push raises: [].}`; L1–L3 use
`{.push raises: [], noSideEffect.}` (see Module Boilerplate above).

### Optional Values

Use `Opt[T]` from nim-results for optional fields — not `std/options`.
`Opt[T]` is `Result[T, void]`, so it shares the full Result API (`?`,
`valueOr:`, `map`, `flatMap`, iterators):

```nim
func findAccount(accounts: openArray[Account], id: AccountId): Opt[Account] =
  for a in accounts:
    if a.id == id:
      return Opt.some(a)
  Opt.none(Account)
```

Prefer `for val in opt:` over `if opt.isSome: opt.get()` for conditional
consumption. Use `valueOr:` for fallback values. Use `?` for early return
from functions returning `Opt[T]`. Use `.optValue` to bridge `Result[T, E]`
to `Opt[T]` (discards error details).

## Conventions

- **`func` is mandatory in L1–L3** — no `proc` permitted in types,
  serde, or protocol modules. `{.push raises: [], noSideEffect.}` at
  the top of each L1–L3 module enforces this at compile time — any
  routine with side effects will fail to compile. Callback parameters
  take `{.noSideEffect, raises: [].}` on the proc type; `mixin`
  resolves pure at instantiation. Builders return
  `(RequestBuilder, ResponseHandle[T])` tuples — no `var` mutation.
  `proc` only for: IO (L4 transport) and L5 C ABI exports, which use
  `{.push raises: [].}` without `noSideEffect`.
- **Parse, don't validate** — smart constructors produce `Result` values.
  Invariants enforced at construction time, not checked later.

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
- nimalyzer `params` rule: prefer natural consumption of `typedesc`
  parameters (e.g., `$T` in `checkJsonKind`/`validationError` calls instead
  of hardcoding the type name). Fall back to `discard $T` only when the
  function has no place to use the parameter (e.g., returns a literal or
  delegates immediately). Never use `{.push ruleOff: "params".}`.
