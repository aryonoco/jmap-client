# Design-doc reference strip-and-reword rules

The only permitted external citation in any comment is `RFC NNNN §X.Y`.
This file enumerates every project-internal documentation reference
style and gives the rewrite rule for each.

## Contents

1. [The rule](#the-rule)
2. [Why this rule](#why-this-rule)
3. [Detection patterns](#detection-patterns)
4. [Reword or delete: the decision tree](#reword-or-delete-the-decision-tree)
5. [What survives — terms that are not references](#what-survives--terms-that-are-not-references)
6. [What an RFC section reference looks like](#what-an-rfc-section-reference-looks-like)
7. [Mixed RFC + design references](#mixed-rfc--design-references)
8. [Worked example](#worked-example)

## The rule

Comments may cite **only RFC sections**. Never reference:

- design documents at any path (`docs/design/*`, `docs/architecture/*`,
  `docs/decisions/*`, `docs/rfcs-internal/*`);
- decision logs (`Decision A6`, `Decision B3`, `Decision D3.6`,
  `Design Decision A6`);
- pattern catalogues (`Pattern A`, `Pattern L3-A`, `Pattern A
  (architecture §1.5.2)`);
- limitation lists (`Limitation 5/6a`);
- design-doc parts (`Part E §4.2`, `Part F design §3.2.4`,
  `Part F migration`);
- enumerated goals (`G7`, `G34`), hypotheses (`H1`, `H6`, `H10`),
  or requirements (`R9`);
- phase or step pointers (`Phase 3 Step 11`, `Step 12`);
- architecture-document sections (`architecture §1.5.2`).

## Why this rule

RFC sections are stable external authority — published, versioned,
immutable. Design documents are project-internal artefacts that drift
under refactoring. A comment that names `Decision D3.6` couples the
code to a document the comment cannot prove still exists, still
matches the named decision, or still holds. Worse, decision numbers
get renumbered when documents are split or merged.

Comments must read at code-review time without requiring the reader
to fetch an external document. The rationale itself must live in the
comment; the comment becomes the source of truth, not a pointer.

## Detection patterns

Every reference style observed in this codebase, in regex form:

| Pattern | Regex | Example |
|---|---|---|
| Path | `docs/(design\|architecture\|decisions)/[^ ]+` | `docs/design/12-mail-G1-design.md` |
| Design section | `design §[0-9]+(\.[0-9]+)*` | `design §2.5 G7` |
| Decision | `Decision [A-Z][0-9]+(\.[0-9]+)?` | `Decision D3.6`, `Decision B20` |
| Verbose decision | `Design Decision [A-Z][0-9]+` | `Design Decision A6` |
| Pattern | `Pattern [A-Z](-[A-Z])?` | `Pattern A`, `Pattern L3-A` |
| Limitation | `Limitation [0-9]+(/[0-9]+[a-z]?)?` | `Limitation 5/6a` |
| Part | `Part [A-Z]( design)? §[0-9]+(\.[0-9]+)*` | `Part F design §3.2.4` |
| Migration | `Part [A-Z] migration` | `Part F migration` |
| Goal | `\bG[0-9]+[a-z]?\b` (when adjacent to design context) | `G7`, `G34`, `G8a` |
| Hypothesis | `\bH[0-9]+\b` (when adjacent to design context) | `H6`, `H10` |
| Requirement | `\bR[0-9]+\b` (when adjacent to design context) | `R9` |
| Phase + Step pointer | `\(Phase [0-9]+ Step [0-9]+\)` | `(Phase 3 Step 11)` |
| Bare phase pointer | `\bPhase [0-9]+\b` (when context is implementation roadmap, not RFC) | `Phase 1 body size enforcement` |
| Step pointer | `\(?Step [0-9]+\)?` (when not an anti-pattern-3 narration) | `(Step 12)` |
| Architecture section | `architecture §[0-9]+(\.[0-9]+)*` | `architecture §1.5.2` |

A goal/hypothesis/requirement bare letter-plus-number (`G7`, `H6`,
`R9`) is a design reference only when the surrounding context names
the design — e.g., inside a parenthetical alongside other design
terms. A standalone `G7` in a comment about an RFC error code is not
this pattern.

## Reword or delete: the decision tree

For every match:

1. Read the comment containing the match in its entirety.
2. Mentally remove the design reference (and any "see …", "per …",
   "as described in …" framing around it).
3. **If what remains is a complete, useful "why" statement → reword**.
   The reword keeps the surviving rationale and removes only the
   pointer. This is the default.
4. **If what remains is empty or content-free → delete the whole
   comment**. The comment was only a pointer; the code structure
   already speaks.
5. **If what remains is a "what" (signature restatement, tautology)
   → delete**. The comment was a pointer plus a tautology; both go.

Choose reword > delete > rewrite-from-scratch in that order.

## What survives — terms that are not references

The following are project-domain vocabulary, not references:

- "Layer 1", "Layer 2", "Layer 3", "Layer 4", "Layer 5" (the
  layered architecture is named in the codebase, not in an external
  doc; these labels stand alone).
- "imperative shell", "functional core" (FP architecture vocabulary).
- "smart constructor", "smart-constructor" (DDD vocabulary).
- "sealed accessor", "Pattern A sealing" → strip `Pattern A`; the
  word "sealed" stands alone.
- "Postel's law", "Postel-strict", "Postel-receive" (recognised
  RFC-engineering vocabulary).
- "sole translation boundary", "imperative shell boundary"
  (architectural-role descriptors).
- "module-private", "module-private invariant".
- "creation type", "read model", "blueprint", "envelope", "atom"
  (domain DTOs).

## What an RFC section reference looks like

The canonical form is `RFC NNNN §X.Y`, with full-width `§` or ASCII
`section` — both accepted. Always at section granularity (never just
`RFC 8620` with no section). Placed inline next to the implementing
step, never as a "see" reference at the top of an unrelated comment.

Examples that already exist in `src/` and are correct:

```nim
## JMAP identifier: 1-255 octets, base64url charset (RFC 8620 §1.2).
## RFC 8620 §2: apiUrl MUST be a non-empty URL free of embedded …
## (RFC 8621 §5.1 ¶2) — paragraph granularity is permitted.
```

Subsection citations (`§5.1 ¶2`, `§4.10 example`) are permitted when
the cited material lives in a numbered paragraph or labelled
sub-element of the RFC section.

## Mixed RFC + design references

When a single comment carries both an RFC ref and a design ref:

- Strip the design ref.
- Retain the RFC ref intact.
- If the rationale text relied on the design ref for context, reword
  it to stand alone in domain language.

**Before** (`mail_builders.nim:535`):

```nim
## ``filter`` is mandatory (H6; RFC 8621 §4.10 ¶1 — first-login always
## defaults to ``true`` per RFC §4.10 example (H13).
```

**After**:

```nim
## ``filter`` is mandatory (RFC 8621 §4.10 ¶1). First-login defaults
## to ``true`` per RFC 8621 §4.10 example.
```

The `H6` and `H13` markers go; the two RFC section references stay;
the rationale ("mandatory", "first-login defaults to true") survives
unchanged.

## Worked example

`src/jmap_client/internal/mail/submission_envelope.nim` lines 14 and
120–143 contain a module-level design pointer plus a strict/lenient
constructor pair, each carrying a design reference inside an
otherwise sound docstring.

**Before** — module header (line 14):

```nim
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.5.
```

**After**:

```
(line deleted entirely — it was a pure pointer with no surviving
rationale)
```

**Before** — strict ctor docstring (lines 123–132):

```nim
func parseNonEmptyRcptList*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, seq[ValidationError]] =
  ## Strict client-side constructor (design §2.5 G7): rejects empty list
  ## AND duplicate recipients keyed on ``RFC5321Mailbox``. Accumulates
  ## every violation into one seq — mirrors ``parseSubmissionParams``.
```

**After**:

```nim
func parseNonEmptyRcptList*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, seq[ValidationError]] =
  ## Strict client-side constructor: rejects empty list and duplicate
  ## recipients keyed on ``RFC5321Mailbox``. Accumulates every violation
  ## into one seq — mirrors ``parseSubmissionParams``.
```

**Before** — lenient ctor docstring (lines 134–143):

```nim
func parseNonEmptyRcptListFromServer*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, ValidationError] =
  ## Lenient server-side constructor (design §2.5 G7, Postel's law):
  ## rejects only empty. Single ``ValidationError`` matches the
  ## ``parseIdFromServer`` / ``parseKeywordFromServer`` shape.
```

**After**:

```nim
func parseNonEmptyRcptListFromServer*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, ValidationError] =
  ## Lenient server-side constructor (Postel's law): rejects only
  ## empty. Single ``ValidationError`` matches the
  ## ``parseIdFromServer`` / ``parseKeywordFromServer`` shape.
```

Three changes — module header line deleted, two `(design §2.5 G7)`
parentheticals stripped. The `Postel's law` reference in the lenient
ctor survives (per the "what survives" list). The RFC reference at
the top of the file (line 4) is untouched. No identifiers, no logic,
no formatting changed.
