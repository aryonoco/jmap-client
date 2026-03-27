---
name: comment-base
description: "Universal code commenting principles — comment 'why' not 'what', eliminate AI anti-patterns, enforce British English. Shared foundation referenced by all language-specific commenting skills."
user-invocable: false
---

# Universal Commenting Principles

These rules apply to ALL languages. Language-specific skills layer their own conventions
on top. See [anti-patterns.md](anti-patterns.md) for a detection checklist with examples.

## Core Rules

1. **Comment "why", never "what"** — if the code says it, the comment must not repeat it.
   A comment must provide information not recoverable from reading the code alone.

2. **Earn every comment** — each comment must justify its existence. Delete any comment
   that a competent developer would find redundant after reading the surrounding code.

3. **Self-documenting code first** — if a "what" comment feels necessary, the code likely
   has a naming or structure problem. Do not add a comment to compensate; the skill's
   scope is comments only, so flag but do not fix code structure issues.

4. **Document constraints, trade-offs, and gotchas** — the highest-value comments explain:
   - Why this approach was chosen over a simpler alternative
   - What would break if this code were changed
   - What business rule or external constraint drives the logic
   - What is coupled to another system, file, or configuration
   - What temporal ordering or concurrency constraint exists

5. **Terseness is a virtue** — a good comment is the shortest string of words that
   resolves the reader's confusion. One sentence is almost always enough.

6. **Irregular placement** — comments appear where confusion exists, not at mechanical
   intervals. If every function has a docstring, most of those docstrings are noise.
   Trivially obvious functions (getters, simple delegations) need no docstring.

7. **No functional changes** — only comments, docstrings, and documentation may be
   modified. Variable names, logic, imports, formatting, and whitespace outside of
   comment blocks must not change. This is the single most important constraint.

## British English

All comments must use British English spelling exclusively:
- colour, behaviour, initialise, serialise, organisation, licence (noun), defence
- "ise" not "ize" (standardise, normalise, optimise)
- "re" not "er" (centre, metre — but "computer", "parameter" are unchanged)
- "ou" not "o" (colour, behaviour, favour, honour)

Variable names, function names, identifiers, and string literals must NEVER be changed,
even if they use American English spelling. This is a zero-functional-changes constraint.

## Tone

Write comments with the persona of a senior SRE at a top-tier engineering organisation.
Comments should be dry, factual, and terse. Never:
- Use emoji in any comment
- Use enthusiastic adjectives ("elegantly", "seamlessly", "beautifully", "powerful")
- Use marketing language ("leverage", "unlock", "empower")
- Use slang or informal language
- Use ASCII art headers, box-drawing separators, or decorative formatting
- Use numbered step narration ("Step 1: ...", "Step 2: ...")

## Workflow

When invoked, the language-specific skill will:

1. **Discover files** — Glob for the language's file extensions in `$ARGUMENTS`,
   excluding generated files per the language-specific exclusion list.
2. **Read each file completely** — understand the full context before making changes.
3. **Analyse existing comments** — identify "what" comments, redundant docstrings,
   AI anti-patterns (see [anti-patterns.md](anti-patterns.md)), and missing "why" comments.
4. **Edit comments in place** — use the Edit tool to modify only comment text.
   Never use the Write tool to overwrite an entire file.
5. **Re-read modified files** — confirm no functional changes were introduced.
