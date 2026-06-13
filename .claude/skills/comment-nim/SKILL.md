---
name: comment-nim
description: "Review and rewrite comments and ## docstrings in Nim files: enforce why-not-what, RFC-section-only external refs (no design-doc cross-refs), no AI-era hedging, smart-constructor documentation, British English. Apply whenever working on comments or docstrings in any .nim file."
user-invocable: true
disable-model-invocation: true
argument-hint: <directory-or-file-path>
---

# Comment Review: Nim

Review and improve all comments in Nim files at: `$ARGUMENTS`

## Instructions

Read the universal commenting principles first:

- [Universal rules](../comment-base/SKILL.md)
- [AI anti-patterns to eliminate](../comment-base/anti-patterns.md)

Then read the Nim-specific conventions:

- [Nim conventions](conventions.md)

## External references

Comments and `##` docstrings may cite **only** RFC sections. Never
reference any project-internal documentation. See
[../comment-base/design-refs.md](../comment-base/design-refs.md) for
the full strip + reword ruleset.

The canonical citation form in Nim doc comments is:

```nim
## Constructed value must satisfy 1-255 octets (RFC 8620 §1.2).
```

For inline `#` comments next to an implementing step:

```nim
# RFC 8621 §4.1.1: keyword case folding before set comparison
```

## File Discovery

Glob for `**/*.nim` in the target path. Exclude:

- `**/nimcache/**`
- `**/nimbledeps/**`
- `**/.nim-reference/**`
- `**/megatest.nim`

## Workflow

For each discovered file:

1. Read the entire file
2. **Grep for design references first** — before rewriting any
   comment, run a mental grep over the file for every pattern in
   [../comment-base/design-refs.md](../comment-base/design-refs.md)
   §[Detection patterns]. Every match must be addressed (strip +
   reword) during this pass. Missing one means a second pass later.
3. Identify every comment (`##` doc comments, `#` inline comments)
4. Apply the universal rules and Nim conventions
5. Edit only comments — zero changes to code, imports, formatting, or whitespace
6. After editing, re-read the file and verify no functional changes occurred

## Gotchas: Nim-specific failure modes

### `hasDoc all` requires every exported symbol to carry a `##` line

`nimalyzer.cfg` enables `check hasDoc all` (verified at
`nimalyzer.cfg:30`). Every exported symbol — including trivial
borrowed operations (`==`, `$`, `hash`, `len`) — must keep at least
one short `##` line. A bare placeholder (`## Equality comparison.`)
is acceptable. Deleting the docstring will fail static analysis.

### `{.experimental: "strictCaseObjects".}` enforces invariants at compile time

Every `src/` `.nim` file activates `strictCaseObjects` (verified at
`.claude/rules/nim-type-safety.md`). A "safe because the
discriminator is X" comment is informational only — the compiler
enforces the proof. Do not rewrite such comments to claim *the
comment* makes the code safe. Phrase as "the discriminator proves
…" not "this comment proves …".

### RFC references without section number are uninformative

`RFC 8620` alone is not a citation. Always cite at section
granularity: `RFC 8620 §1.2`. If the section number is unknown,
look it up in `docs/rfcs/` (read-only) before rewriting; do not
guess.

### Stale invariant comments after refactor

The `.get()`-on-`Result`-with-invariant pattern (see
`nim-functional-core.md` pattern 8) is sound only as long as the
adjacent invariant still holds. When rewriting a comment that
proves an invariant, verify the invariant still holds against the
current code. An invariant comment that no longer holds is a
correctness liability.

### Postel's-law terminology is load-bearing

`Postel's law`, `Postel-strict`, `Postel-receive`,
`parseFromServer`, `parseIdFromServer`,
`parseKeywordFromServer` are all part of the strict-vs-lenient
design vocabulary. Preserve them. The strict/lenient ctor pair is
the canonical idiom in this codebase (26 occurrences) and the
documentation depends on the terminology.

### SPDX `REUSE-IgnoreStart` / `REUSE-IgnoreEnd` markers are structural

These markers (when present) are tooling directives for the REUSE
licence compliance tool, not comments. Do not rewrite, edit, or
remove them. Treat them like the SPDX header itself.

## Key reminders (non-functional)

- `##` doc comments only on exported symbols with non-obvious
  behaviour; trivially obvious symbols still need a single-line
  placeholder to satisfy `hasDoc all`.
- Module-level doc comments explain architectural role, not "this
  module provides …".
- Smart-constructor doc comments document validation rules, not
  return types; name the *consequence* of precondition violation,
  not just the precondition (Chronos-style).
- External references: **RFC sections only**; never design-doc, never
  decision-log, never pattern-catalogue, never goal/hypothesis/requirement.
  See [../comment-base/design-refs.md](../comment-base/design-refs.md).
- SPDX header is structural — never comment it. REUSE-IgnoreStart/End
  are structural — never edit.
- All comments in British English spelling; identifiers stay
  unchanged regardless of spelling.
- RFC 2119 keywords (`MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`,
  `MAY`, `NEVER`) adjacent to an RFC citation are preserved as-is;
  they are technical keywords, not imperatives.
- Only TODO marker accepted: `TODO(@<github-handle>, #<issue>): text`.
  See anti-pattern 13 in
  [../comment-base/anti-patterns.md](../comment-base/anti-patterns.md).
