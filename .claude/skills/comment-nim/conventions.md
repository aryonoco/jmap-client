# Nim Commenting Conventions

## Contents

1. [Comment syntax](#comment-syntax)
2. [Module-level doc comments](#module-level-doc-comments)
3. [Exported symbol doc comments](#exported-symbol-doc-comments)
4. [Smart constructor documentation](#smart-constructor-documentation)
5. [Inline comments (`#`)](#inline-comments-)
6. [External references — RFC sections only](#external-references--rfc-sections-only)
7. [Smart-constructor error contract](#smart-constructor-error-contract)
8. [TODO/FIXME/XXX markers](#todofixmexxx-markers)
9. [Module-level docstring template](#module-level-docstring-template)
10. [`runnableExamples` over prose code blocks](#runnableexamples-over-prose-code-blocks)
11. [Structural elements — never comment](#structural-elements--never-comment)
12. [Pragma comments](#pragma-comments)
13. [British English in comments](#british-english-in-comments)

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

**Prefer minimal doc comments on**:

- Trivially obvious `func`/`proc` (single-expression, self-documenting name)
- Borrowed operations on distinct types (`==`, `$`, `hash`)
- Simple field accessors
- Type definitions where the field names are self-documenting

However, nimalyzer enforces `check hasDoc all` — every exported symbol must
have a `##` doc comment. Where a doc comment adds no real insight, keep it to
a single short line (e.g. `## Equality comparison.`) rather than omitting it
entirely. Do not pad these with filler; a terse placeholder satisfies the
linter without introducing noise.

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

## External references — RFC sections only

Comments and `##` docstrings may cite only RFC sections. Never
reference design docs, decision logs, pattern catalogues, hypothesis
numbers, goal numbers, requirement numbers, or any project-internal
documentation. See
[../comment-base/design-refs.md](../comment-base/design-refs.md) for
the full strip + reword ruleset.

**In doc comments** (`##`):

```nim
func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only (RFC 8620 §1.2).
  ## For client-constructed IDs (e.g., method call IDs used as
  ## creation IDs).
```

**In inline comments** (`#`):

```nim
# RFC 6901 §3 reference-token escaping. ``~`` MUST be escaped first:
```

**RFC 2119 keywords** (`MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`,
`MAY`, `NEVER`) are preserved as-is when adjacent to an RFC
citation. They are technical keywords with defined meaning, not
emphasis. Outside an RFC-citation context, do not use ALL-CAPS
imperatives without an accompanying "because …" clause.

## Smart-constructor error contract

Smart constructors return `Result[T, ValidationError]`. The
docstring must:

1. Name the constraints enforced (size, charset, structural).
2. Name the *consequence* of violation — what kind of error is
   returned and why the caller should care (Chronos pattern: name
   the consequence, not just the precondition).
3. Distinguish strict (`parseX`) from lenient (`parseXFromServer`)
   when both exist. Strict = client-constructed values; lenient =
   server-received values, Postel's law on receive.

```nim
func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only (RFC 8620 §1.2).
  ## Returns ``err(ValidationError)`` on out-of-range length or
  ## charset violation — callers must handle the error rail.

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters. Returns
  ## ``err(ValidationError)`` only on structural failure; tolerates
  ## servers that deviate from the strict base64url charset
  ## (e.g., Cyrus IMAP).
```

When the strict/lenient gap is *not* meaningful (no spec-specific
constraints beyond the structural ones), a single parser suffices —
do not invent a lenient variant for symmetry. Document the absence
of a `*FromServer` variant in the strict parser's docstring with
one line of rationale.

## TODO/FIXME/XXX markers

The codebase currently has zero TODO/FIXME/XXX markers (verified
2026-05-12). The rule going forward:

**Sole accepted form**:

```nim
# TODO(@<github-handle>, #<issue>): <description>
```

- `TODO` is the only accepted marker. Rewrite `FIXME`, `XXX`,
  `HACK`, `BUG`, and `NOTE` to `TODO` if retained, or delete them.
- `@<github-handle>` identifies the owner.
- `#<issue-number>` references an open issue in the project tracker.

Both `@handle` and `#issue` are mandatory. An orphan TODO without
either is deleted on sight; if the work is real, move it to the
tracker before rewriting the marker.

## Module-level docstring template

Every module begins (after the SPDX header) with a module-level
`##` docstring naming the module's architectural role and key
invariants. Modelled on `sequtils` and `lib/pure/times.nim` from
the Nim standard library.

Template:

```nim
## <One-line summary of the module's architectural role.>
##
## <Optional second paragraph: key invariants, RFC scope, layer
## position. Multi-paragraph only when the module is non-trivial.>
##
## See also:
## * `<sibling-module>` for <related responsibility>
```

Concrete example (modelled on the existing
`src/jmap_client/internal/types/primitives.nim`):

```nim
## RFC 8620 primitive types with smart constructors enforcing
## wire-format constraints. Bounded to JSON-safe integer ranges
## (2^53-1) per the JMAP specification.
```

**Module headers must NOT contain**:

- "This module provides …"
- "This file contains …"
- A list of the module's exports (the source already lists them).
- A "Design authority:" line or any other design-doc pointer.

For complex modules, internal RST section headers (`## ====`,
`## ----`) are permitted and exemplified by `lib/pure/times.nim`.
Use only when the module exceeds ~300 lines and natural sub-sections
exist.

## `runnableExamples` over prose code blocks

When an exported function benefits from a usage example, prefer
`runnableExamples` (compiled and tested as part of `nim doc`) over
a prose code block in the docstring:

```nim
func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only (RFC 8620 §1.2).
  runnableExamples:
    doAssert parseId("abc123").isOk
    doAssert parseId("").isErr
  …
```

A prose ``` ```nim ``` block is acceptable when the example is too
elaborate to inline (multiple types, helper setup), but
`runnableExamples` is the default.

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
