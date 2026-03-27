# Nim Commenting Conventions

## Comment Syntax

Nim has two comment forms:

- `##` — Documentation comment. Appears in generated HTML docs (`nim doc`).
  Used for exported symbols only.
- `#` — Inline comment. Not included in generated docs. Used for "why"
  annotations within function bodies.

Multi-line forms: `##[` ... `]##` for doc blocks, `#[` ... `]#` for inline blocks.
Prefer single-line `##` over multi-line blocks for consistency.

## Module-Level Doc Comments

Every module should have a doc comment immediately after `{.push raises: [].}`:

```nim
{.push raises: [].}

## Distinct identifier types and smart constructors for the JMAP domain model.
## Enforces non-empty constraints at construction time via Result[T, ValidationError].
```

**Good**: Explains the module's architectural role and key invariant.

**Bad**: `## This module provides types and functions for working with JMAP identifiers.`
— restates the obvious.

**Bad**: `## Contains AccountId, EmailId, BlobId, MailboxId, CreationId types.`
— listing exports is what the source code already does.

## Exported Symbol Doc Comments

Add `##` only when the function has non-obvious behaviour:

```nim
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Rejects empty strings. Does not validate format beyond non-emptiness —
  ## JMAP servers define valid ID formats per implementation.
```

**Do NOT add doc comments to**:

- Trivially obvious `func` (single-expression, self-documenting name)
- Borrowed operations on distinct types (`==`, `$`, `hash`)
- Simple field accessors
- Type definitions where the field names are self-documenting

## Smart Constructor Documentation

Document the **validation rules**, not the return type:

```nim
func parseUnsignedInt*(raw: int): Result[UnsignedInt, ValidationError] =
  ## Must be >= 0. Prevents negative integers that JavaScript's
  ## Number type can produce from JSON parsing.
```

NOT: `## Parses an integer into an UnsignedInt, returning a Result.`

## Inline Comments (`#`)

Explain WHY, never WHAT:

```nim
func parseCapabilityKind*(uri: string): CapabilityKind =
  # Exhaustive match against IANA-registered URIs.
  # Falls back to ckUnknown for vendor extensions — these are
  # preserved via rawUri on the parent ServerCapability.
  case uri
  of "urn:ietf:params:jmap:core": ckCore
  of "urn:ietf:params:jmap:mail": ckMail
  # ...
  else: ckUnknown
```

## Structural Elements — Never Comment

These are project idioms. Every developer knows them. Never add comments:

- `# SPDX-License-Identifier: BSL-1.0` — structural header, not a comment to review
- `{.push raises: [].}` — project-wide convention, never explain it
- `import std/[...]` / `import pkg/results` / `import ./...` — import grouping
  convention, never add "import section" headers
- `template defineStringDistinctOps*` — borrow template, self-documenting

## Pragma Comments

Comment a pragma only when the reason is non-obvious:

```nim
# Network errors from std/httpclient can raise CatchableError;
# this proc is the boundary where we catch and wrap them.
proc discoverSession*(client: JmapClient): JmapResult[Session] =
```

Do NOT comment `{.exportc, cdecl, dynlib.}` — the FFI boundary rule explains these.

## British English in Comments

All comments use British English:
- serialise, deserialise, initialise, normalise, standardise
- colour, behaviour, favour, honour
- centre, metre (but: computer, parameter)
- licence (noun), defense → defence

Identifiers use US English and must NEVER be changed, even if they spell
"serialize" or "color". The zero-functional-changes constraint is absolute.
