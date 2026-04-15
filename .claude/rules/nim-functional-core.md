---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Functional Core (L1–L3)

## Scope

Applies to **L1 (types), L2 (serde), L3 (protocol)** modules under
`{.push raises: [], noSideEffect.}`. Layer 4 (transport/IO) and Layer 5
(C ABI) are NOT governed by this rule — those layers legitimately mutate,
raise, and perform IO; see `nim-ffi-boundary.md`. Module boilerplate and
the layer pragma split live in `nim-conventions.md` (Module Boilerplate).

## Mental Model

You are writing OCaml/Haskell-shaped code on Nim primitives. The compiler
proves purity and totality via `{.push raises: [], noSideEffect.}`; your
job is to pick the stdlib operations that survive those pragmas. Every
`func` is a total function from its declared input type. Every variant
of every sum type is handled exhaustively. Every error is named in the
type, never collapsed to a string. Local state is fine; observable side
effects are not.

## Safe primitives under `raises: [], noSideEffect`

| Operation | ✅ Use | ❌ Avoid | Why |
|---|---|---|---|
| Table key lookup | `withValue`, `getOrDefault`, `mgetOrPut`, `hasKeyOrPut`, `contains`/`hasKey`, `pop` | `Table.[]` | `[]` raises `KeyError`, inferred into `raises:` |
| Table mutation | `[]=`, `del` on local `var` | — | local mutation is not observable |
| HashSet construction | `initHashSet`, `toHashSet`, `incl` | — | |
| HashSet algebra | `*` `+` `-` `-+-`, `<` `<=` `==`, `disjoint`, `card` | — | set-theoretic, total |
| Seq FP | `mapIt`, `filterIt`, `foldl`, `toSeq`, `concat`, `allIt`, `anyIt`, `&` | nested `It`-templates | templates expand inline — inherit caller's purity |
| Closure-taking procs | `seq.map(p)` / `seq.filter(p)` with `effectsOf: op` | — | pass a pure callback; the call stays pure |
| List comprehension | `collect` (std/sugar) | — | expands to `var res = newSeq(); res.add(...); res` — local only |
| Opt[T] / Result[T,E] | `?` operator, `valueOr:`, `for v in opt:`, `.optValue`, `.map`, `.flatMap` | `.get()` without invariant | `.get()` is legal but carries a proof obligation (pattern 8) |
| String ops | `&`, `$T` on distincts, join via `foldl`, `strutils.join` | formatters that raise (e.g., `parseInt`) | parsing goes through smart constructors, never inline |

## Pattern Catalogue

Eight patterns, each with a canonical example in the codebase. Reference
by symbol name (not line number) so the rule survives edits.

### 1. Sum-type ADT for internal classification

Name every shape your domain can take. Adding a variant then forces a
compile error at every `case` site — that is the whole point.

```nim
type ConflictKind = enum
  ckDuplicatePath
  ckOppositeOps
  ckPrefixCollision

type Conflict {.ruleOff: "objects".} = object
  case kind: ConflictKind
  of ckDuplicatePath, ckOppositeOps: targetPath: string
  of ckPrefixCollision: property: string
```

Canonical: `Conflict` in `src/jmap_client/mail/email_update.nim`. The ADT
decouples domain classification (detection functions) from wire
serialisation (the single translation function — see pattern 5).

### 2. Set algebra for membership rules

Membership rules often collapse to a single set operation once you name
the sets. Build two sets, then intersect / union / subtract.

```nim
let replaced =
  ops.filterIt(it.kind.shape == psFullReplace).mapIt(it.parentPath).toHashSet
let subPathed =
  ops.filterIt(it.kind.shape == psSubPath).mapIt(it.parentPath).toHashSet
collect:
  for parent in (replaced * subPathed):
    Conflict(kind: ckPrefixCollision, property: parent)
```

Canonical: `parentPrefixConflicts` in `email_update.nim`. The RFC 8620 §5.3
rule "no full-replace on `<p>` alongside a sub-path write under `<p>/...`"
IS set intersection; the code just says so.

### 3. `withValue` for safe table lookup

`Table.[]` raises `KeyError`; under `raises: []` that's a compile error.
The OCaml `match Map.find_opt k m with Some v -> ... | None -> ...` is
spelled `withValue(k, v): ... do: ...` in Nim — safe, total, idiomatic.

```nim
var firstKindAt = initTable[string, EmailUpdateVariantKind]()
for op in ops:
  firstKindAt.withValue(op.targetPath, firstKind):
    # found — firstKind is `addr Value`; deref with `[]`
    if firstKind[] == op.kind: ...
    else: ...
  do:
    # not found
    firstKindAt[op.targetPath] = op.kind
```

Canonical: `samePathConflicts` in `email_update.nim`. The `firstKind[]`
deref is required because `withValue` yields the address, not the value.

### 4. Literal discriminator at case-object construction

Nim rejects runtime discriminator values at case-object construction —
even when every arm has the same field shape. The `kind:` field must be
a syntactic literal so the compiler can prove which branch's fields are
valid. Split into branches, each with its own literal `kind:`.

```nim
# ❌ REJECTED — runtime discriminator
let k = if firstKind[] == op.kind: ckDuplicatePath else: ckOppositeOps
result.add Conflict(kind: k, targetPath: op.targetPath)

# ✅ ACCEPTED — literal per branch
if firstKind[] == op.kind:
  result.add Conflict(kind: ckDuplicatePath, targetPath: op.targetPath)
else:
  result.add Conflict(kind: ckOppositeOps, targetPath: op.targetPath)
```

Canonical: `samePathConflicts` in `email_update.nim`. See also
`nim-type-safety.md` "Construction Requires Literal Discriminator".

### 5. Translation at the boundary

One function converts the internal ADT to the wire error shape. New
variant ⇒ compile error at exactly this function, never silent at a serde
site.

```nim
func toValidationError(c: Conflict): ValidationError =
  case c.kind
  of ckDuplicatePath:
    validationError("EmailUpdateSet", "duplicate target path", c.targetPath)
  of ckOppositeOps:
    validationError("EmailUpdateSet", "opposite operations ...", c.targetPath)
  of ckPrefixCollision:
    validationError("EmailUpdateSet", "sub-path alongside ...", c.property)
```

Canonical: `toValidationError` in `email_update.nim`. Detection stays in
`Conflict`-shape; only this function touches `ValidationError`.

### 6. Derived-not-stored fields

If a fact follows mechanically from another, don't store it — compute it.
One source of truth per fact.

```nim
func shape(k: EmailUpdateVariantKind): PathShape =
  case k
  of euAddKeyword, euRemoveKeyword, euAddToMailbox, euRemoveFromMailbox: psSubPath
  of euSetKeywords, euSetMailboxIds: psFullReplace
```

Canonical: `shape` in `email_update.nim`. `PathShape` is derived from the
update kind — storing it would let the two disagree.

### 7. Imperative kernel inside a functional shell

`noSideEffect` forbids side effects visible to the caller, not local
mutation. Accumulating folds, building a table, `collect` — all fine
inside a `func`. The test is: does the mutation leak past the `return`?

```nim
func samePathConflicts(ops: openArray[PathOp]): seq[Conflict] =
  result = @[]
  var firstKindAt = initTable[string, EmailUpdateVariantKind]()
  for op in ops:
    firstKindAt.withValue(...): ... do: ...
```

Canonical: `samePathConflicts` in `email_update.nim`. The `var Table` is
invisible outside the call; the function remains pure by the pragma.

### 8. Invariant-proved `.get()` on Result

`.get()` on a `Result` raises if the value is `Err`. Legal under
`raises: []` because the panic path is a defect, not a checked exception —
but it carries a proof obligation: the adjacent comment MUST state the
invariant that proves `Ok`. Otherwise use `?` or `valueOr:`.

```nim
func moveToMailbox*(id: Id): EmailUpdate =
  EmailUpdate(
    kind: euSetMailboxIds,
    # @[id] is non-empty by construction; parseNonEmptyMailboxIdSet cannot
    # Err here.
    mailboxes: parseNonEmptyMailboxIdSet(@[id]).get(),
  )
```

Canonical: `moveToMailbox` in `email_update.nim`. The invariant "literal
`@[id]` has length 1" proves `Ok`, so `.get()` is total in context even
though the return type admits `Err`.

## Named two-case enum replaces bool

For a finite, mutually-
exclusive classification, an enum names the alternatives and makes `case`
exhaustive.

```nim
# ✅ named alternatives
type PathShape = enum
  psSubPath
  psFullReplace

# ❌ positional meaning; `if isFullReplace` reads nothing at the call site
let isFullReplace: bool = ...
```

Canonical: `PathShape` in `email_update.nim`.

**Exception.** When multiple independent booleans are ALL legal in
combination and no smart constructor gates the shape, a clustered-bool
object is acceptable. Canonical: `MailboxRights` in
`src/jmap_client/mail/mailbox.nim` (Decision B6 documented on the type).
Nine RFC 8621 ACL flags, each independent; an enum would be wrong.

## Named record replaces anonymous tuple for domain meaning

`(string, string, EmailUpdateVariantKind)` is positional. Field semantics
live in the call site, not the type. Replace with a named `object` as
soon as the fields carry meaning.

```nim
type PathOp = object
  targetPath: string
  parentPath: string
  kind: EmailUpdateVariantKind
```

Canonical: `PathOp` in `email_update.nim`. Anonymous tuples remain fine
for ephemeral multi-return (e.g., a builder + handle pair).

## Nim concessions vs OCaml/Haskell

Knowing what Nim does NOT have saves you from reaching for non-existent
features:

- **No `Map.alter` / `mapAccumL` / `partition`.** Compose from `withValue`,
  `foldl`, or two `filterIt` passes.
- **No persistent immutable collections.** All stdlib collections are
  mutation-based under `--mm:arc`; local mutation in a `func` is the
  idiom — see pattern 7.
- **No deep pattern matching.** `case` dispatches on an enum or a case-
  object discriminator only. No `Just (x, _)` destructure; no guards on
  nested shapes. Bind fields manually after the `case`.
- **No effect rows.** Only `noSideEffect` vs. allowed, and `raises: [...]`
  vs. `raises: []`. No `Reader`/`State`/`IO` monad stack.
- **No nominative variant constructors.** `Conflict(kind: ckDup, targetPath:
  p)` is the Nim spelling of OCaml's `Dup p` — verbose, but explicit.
- **`toSeq` bridges iterators.** `openArray` and iterator results don't
  directly participate in `mapIt`/`filterIt` chains in every position;
  `toSeq` is the reifier.
- **No runtime variant discriminator at construction** — see pattern 4.

## Hard prohibitions under `raises: [], noSideEffect`

- Never `Table.[]` — use `withValue` / `getOrDefault` / `mgetOrPut`.
- Never a boolean field when a named two-case enum fits.
- Never an anonymous tuple carrying domain meaning — use a named `object`.
- Never store a field derivable from another field in the same type.
- Never a `case` with catch-all `else` when variants are finite — it
  hides exhaustiveness failures at the compiler.
- Never a runtime-valued discriminator at case-object construction — use
  a literal `kind:` per branch.
- Never a raising stdlib call without checking for a safe alternative
  first (`Table.[]` vs `withValue`, `parseInt` vs `parseInt.Result`).
- Never `.get()` on a `Result` without an adjacent invariant comment
  proving `Ok`.
- Never delegate understanding to `raises: [Exception]` — name every
  variant in the type.
