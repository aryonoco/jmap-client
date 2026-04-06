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

Every module should have a doc comment at the top (after the copyright header):

```nim
## Distinct identifier types and smart constructors for the JMAP domain model.
## Enforces non-empty constraints at construction time; returns
## Result[T, ValidationError] on the error rail for invalid input.
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

- Trivially obvious `func`/`proc` (single-expression, self-documenting name)
- Borrowed operations on distinct types (`==`, `$`, `hash`)
- Simple field accessors
- Type definitions where the field names are self-documenting

## Smart Constructor Documentation

Document the **validation rules**, not the return type:

```nim
func parseUnsignedInt*(raw: int64): Result[UnsignedInt, ValidationError] =
  ## Must be >= 0 and <= 2^53-1. Prevents negative integers and values
  ## outside JSON's safe integer range.
```

NOT: `## Parses an integer into an UnsignedInt, returning a Result.`

## Inline Comments (`#`)

Explain WHY, never WHAT:

```nim
proc parseCapabilityKind*(uri: string): CapabilityKind =
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

<!-- REUSE-IgnoreStart -->
- `# SPDX-License-Identifier: BSD-2-Clause` — structural header, not a comment to review
<!-- REUSE-IgnoreEnd -->
- `import std/[...]` / `import ./...` — import grouping convention, never add
  "import section" headers
- `template defineStringDistinctOps*` — borrow template, self-documenting

## Pragma Comments

Comment a pragma only when the reason is non-obvious:

```nim
# Layer 5 boundary: catches all exceptions from the Nim core and
# converts them to C error codes for the FFI consumer.
proc jmapDiscoverSession*(...): cint
    {.exportc: "jmap_discover_session", dynlib, cdecl, raises: [].} =
```

Do NOT comment `{.exportc, dynlib, cdecl, raises: [].}` — the FFI boundary rule explains these.

## British English in Comments

All comments use British English:
- serialise, deserialise, initialise, normalise, standardise
- colour, behaviour, favour, honour
- centre, metre (but: computer, parameter)
- licence (noun), defense → defence

Identifiers use US English and must NEVER be changed, even if they spell
"serialize" or "color". The zero-functional-changes constraint is absolute.
