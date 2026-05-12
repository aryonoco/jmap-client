# AI Comment Anti-Patterns

Detect and eliminate every instance of these patterns. Each pattern includes a
detection heuristic and the correct response.

## Contents

1. [Tautological comments](#1-tautological-comments)
2. [Signature restatement in docstrings](#2-signature-restatement-in-docstrings)
3. [Numbered step narration](#3-numbered-step-narration)
4. [Section header ASCII art](#4-section-header-ascii-art)
5. [Generic boilerplate headers](#5-generic-boilerplate-headers)
6. [Over-documented parameters](#6-over-documented-parameters)
7. [Trailing inline restaters](#7-trailing-inline-restaters)
8. [Enthusiastic or marketing language](#8-enthusiastic-or-marketing-language)
9. [File-level "this file contains" comments](#9-file-level-this-file-contains-comments)
10. [Commented-out code without context](#10-commented-out-code-without-context)
11. [Architecture or design documentation references](#11-architecture-or-design-documentation-references)
12. [AI-era hedging and slop phrasing](#12-ai-era-hedging-and-slop-phrasing)
13. [TODO/FIXME/XXX without owner or ticket](#13-todofixmexxx-without-owner-or-ticket)

## 1. Tautological Comments

**Detection**: Comment restates the code on the next line in natural language.

**Before** (delete):
```
# Increment the counter
counter += 1

# Return the result
return result

# Check if the session is valid
if session.isValid:
```

**Action**: Delete the comment entirely. The code is the documentation.

## 2. Signature Restatement in Docstrings

**Detection**: Docstring repeats the function name, parameter names, parameter types,
or return type that are already expressed in the function signature or type system.

**Before** (delete or rewrite):
```nim
## Parses the AccountId from the given raw string.
## Returns a Result containing the AccountId or a ValidationError.
func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
```

**Action**: Delete the docstring if the function name is self-explanatory.
Rewrite only if there is a non-obvious "why" to document (e.g. validation rules,
encoding constraints, ownership semantics).

## 3. Numbered Step Narration

**Detection**: Comments follow a `# Step N:` pattern.

**Before** (delete):
```nim
# Step 1: Parse the JSON
let node = ? safeParseJson(raw)
# Step 2: Extract the session
let session = ? parseSession(node)
# Step 3: Validate capabilities
let validated = ? validateCapabilities(session)
```

**Action**: Delete all step comments. If the sequence has a non-obvious ordering
constraint, replace with a single comment explaining WHY that order matters.

## 4. Section Header ASCII Art

**Detection**: Lines of `===`, `---`, `***`, `###`, or box-drawing characters used
as visual separators between code sections.

**Before** (delete):
```
# ============================================
# ===        SESSION DISCOVERY             ===
# ============================================
```

**Action**: Delete entirely. If a file needs section headers, the file is too long.
In the rare case a section marker is genuinely needed, a bare `# --- Discovery`
suffices, but prefer splitting the file.

## 5. Generic Boilerplate Headers

**Detection**: Comments like `# Import modules`, `# Define types`, `# Helper functions`,
`# Handle errors`, `# Export`, `# This module provides...`.

**Before** (delete):
```nim
# Import necessary modules
import std/[json, tables]

# Define types
type AccountId* = distinct string
```

**Action**: Delete. These are content-free section labels.

## 6. Over-Documented Parameters

**Detection**: Every parameter is documented with a restatement of its name or type.

**Before** (delete the redundant docs):
```nim
## Validates the session object.
## Parameters:
##   session - The session to validate
##   strict - Whether to use strict validation
func validateSession*(session: Session, strict: bool): Result[Session, ValidationError] =
```

**Action**: Delete parameter documentation that adds nothing beyond the signature.
Keep only where the docstring adds context the type cannot express (valid ranges,
encoding, ownership semantics, side effects).

## 7. Trailing Inline Restaters

**Detection**: End-of-line comments that restate the variable or field name.

**Before** (delete):
```nim
let name = node{"name"}.getStr("")         # Get the account name
let isPersonal = node{"isPersonal"}.getBool(false)  # Check if personal
```

**Action**: Delete. The variable name and accessor are the documentation.

## 8. Enthusiastic or Marketing Language

**Detection**: Words like "elegantly", "seamlessly", "beautifully", "leverage",
"powerful", "robust", "cutting-edge", "state-of-the-art".

**Action**: Replace with factual language or delete the sentence.

## 9. File-Level "This File Contains" Comments

**Detection**: `## This module provides...`, `## This file contains...`,
`## This module is responsible for...`.

**Action**: Rewrite to explain WHY the module exists and what architectural
role it plays, or delete if the filename and exports are self-explanatory.

## 10. Commented-Out Code Without Context

**Detection**: Blocks of commented-out code without an explanation of why they are
retained (e.g. no TODO, no issue reference).

**Action**: Do NOT delete commented-out code (that would be a functional change
in some contexts). Instead, add a brief comment explaining why it is retained,
or flag it for the developer's attention.

## 11. Architecture or design documentation references

**Detection**: any reference to project-internal documentation. The
following exact patterns occur in this codebase and must all be
stripped:

- `docs/design/<anything>.md` (path reference)
- `design §N.N` (parenthetical design-section pointer)
- `Decision <Letter><Number>` (decision log; letters A, B, C, D, E
  observed)
- `Design Decision <Letter><Number>` (verbose form)
- `Pattern <Letter>` (architectural pattern catalogue)
- `Pattern L3-<Letter>` (layer-3 sub-pattern)
- `Pattern A (architecture §N.N.N)` (composite form)
- `Pattern A (architecture Limitation N/Na)` (composite form with
  limitation pointer)
- `Limitation N` / `Limitation N/Na` (architecture limitation log)
- `Part <Letter> design §N` (design-document part)
- `Part <Letter> §N.N` (design-document part with section)
- `Part <Letter> migration` (migration plan pointer)
- `G<N>[<letter>]` — goal numbers from the design doc
- `H<N>` — hypothesis numbers
- `R<N>` — requirement numbers
- `Phase N Step N` / `(Phase N Step N)` — design-doc phase pointer
- `architecture §N.N.N` — architecture document section

**Action**: strip the design reference; reword the rationale to stand
alone using RFC sections or pure domain language. If the comment was
*only* a pointer (no rationale beyond the citation), delete it.

**Before** (`framework.nim:60`):

```nim
## Construction sealed via Pattern A (architecture §1.5.2): ``rawProperty`` is
## module-private; same-name accessors UFCS-project on read.
```

**After**:

```nim
## Sealed construction: ``rawProperty`` is module-private; same-name
## accessors UFCS-project on read.
```

**Before** (`submission_envelope.nim:123`):

```nim
## Strict client-side constructor (design §2.5 G7): rejects empty list
## AND duplicate recipients keyed on ``RFC5321Mailbox``.
```

**After**:

```nim
## Strict client-side constructor: rejects empty list and duplicate
## recipients keyed on ``RFC5321Mailbox``.
```

**Before** (`mail_builders.nim:535`):

```nim
## ``filter`` is mandatory (H6; RFC 8621 §4.10 ¶1 — first-login always
## defaults to ``true`` per RFC §4.10 example (H13).
```

**After**:

```nim
## ``filter`` is mandatory (RFC 8621 §4.10 ¶1). First-login defaults to
## ``true`` per RFC 8621 §4.10 example.
```

**Before** (`vacation.nim:7`):

```nim
## ("singleton") is handled purely in serialisation (Design Decision A6).
```

**After**:

```nim
## ("singleton") is handled purely in serialisation.
```

**Before** (`client.nim:599`):

```nim
# Phase 1 body size enforcement (R9) — reject before reading body
```

**After**:

```nim
# Body-size pre-flight rejection — refuse before reading body
```

## 12. AI-era hedging and slop phrasing

**Detection**: any phrase from the exhaustive list below. Match
case-insensitively at word boundaries.

**Agentic / first-person phrasing** (always strip):
- `I'll`, `I've`, `I'm`, `we'll`, `we've`, `we're`, `let's`
- `you can`, `you may`, `you might`, `you should`, `you'll`
- `feel free to`, `make sure to`, `be sure to`, `remember to`

**Hedging / epistemic uncertainty** (always strip; if the uncertainty
is real, document the constraint that would resolve it):
- `appears to`, `seems to`, `looks like`, `seems like`
- `almost certainly`, `most likely`, `may want to`
- `perhaps`, `possibly`, `probably`, `arguably`

**Sycophantic intensifiers** (always strip):
- `certainly`, `obviously`, `naturally`, `of course`
- `as expected`, `needless to say`, `clearly`
- `essentially`, `basically`, `actually`
- `straightforward`, `trivial`, `simple` (as evaluation),
  `easy`, `intuitive`

**Filler intensifiers** (strip when filler; preserve when restrictive):
- `simply`, `just`. Restrictive `just` (= "only/nothing more than")
  is load-bearing — preserve. Filler `just` (= "really"/intensifier)
  — strip. Apply the substitution test: if removing the word does
  not change the meaning, strip; if removing it would change the
  scope or quantity, preserve.

**Marketing / superlative language** (always strip):
- `elegantly`, `seamlessly`, `beautifully`, `smoothly`
- `powerful`, `robust`, `production-ready`, `battle-tested`
- `comprehensive`, `complete`, `cutting-edge`, `state-of-the-art`
- `leverage`, `empower`, `unlock`, `enables you to`, `drives`

**Self-referential narration** (always strip):
- `this is a`, `this code does`, `this function performs`
- `this method handles`, `the following code`, `the code below`,
  `the code above`

**Tutorial framing** (always strip):
- `first we`, `then we`, `now we`, `next we`
- `as we can see`, `as you can see`, `notice that`

**Action**: replace with a factual assertion or delete the sentence.
If the hedge masked a real constraint, document the constraint.

**Before** (`convenience.nim:113`):

```nim
## Composes naturally with the ``?`` operator:
```

**After**:

```nim
## Composes with the ``?`` operator:
```

**Before** (`email_submission.nim:318`):

```nim
## on the server side and is almost certainly a caller bug, so it is
```

**After**:

```nim
## on the server side and indicates a caller bug, so it is
```

**Before** (`serde_mailbox.nim:127`):

```nim
# the serialiser simply projects the backing set onto the ``{id: true, ...}``
```

**After**:

```nim
# the serialiser projects the backing set onto the ``{id: true, ...}``
```

**Before** (`mailbox.nim:181`):

```nim
## Duplicates are naturally deduplicated by the underlying HashSet.
```

**After**:

```nim
## Duplicates are deduplicated by the underlying HashSet.
```

## 13. TODO/FIXME/XXX without owner or ticket

**Detection**: any of `TODO`, `FIXME`, `XXX`, `HACK`, `BUG`, `NOTE`
appearing without both an owner handle and an issue number.

**Mandatory format**: `TODO(@<github-handle>, #<issue-number>): <description>`

- `TODO` is the only accepted marker; `FIXME`, `XXX`, `HACK`, `BUG`,
  `NOTE` are rewritten to `TODO` if retained.
- `@<github-handle>` identifies the owner; must be a real GitHub
  username, not a placeholder.
- `#<issue-number>` is a positive integer referring to an open issue
  in the project's tracker.

**Action**: if the marker is essential, rewrite to the mandatory
format; if no owner or issue can be assigned, delete the marker and
move the work to the issue tracker. Orphaned markers rot.

**Before**:

```nim
# TODO: handle the empty case
# FIXME: this is wrong
# XXX revisit when we have time
```

**After** (option A — retain):

```nim
# TODO(@aryan-ameri, #142): handle the empty case per RFC 8620 §5.1
```

**After** (option B — delete and move to tracker).
