---
name: comment-nim
description: "Review and rewrite comments in Nim files to explain 'why' not 'what', following Nim doc comment conventions (##), smart constructor documentation patterns, and senior engineering standards."
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

## File Discovery

Glob for `**/*.nim` in the target path. Exclude:

- `**/nimcache/**`
- `**/nimbledeps/**`
- `**/.nim-reference/**`
- `**/megatest.nim`

## Workflow

For each discovered file:

1. Read the entire file
2. Identify every comment (`##` doc comments, `#` inline comments)
3. Apply the universal rules and Nim conventions
4. Edit only comments — zero changes to code, imports, formatting, or whitespace
5. After editing, re-read the file and verify no functional changes occurred

## Key Reminders

- `##` doc comments only on exported symbols with non-obvious behaviour
- Module-level doc comments explain architectural role, not "This module provides..."
- Smart constructor doc comments document validation rules, not return types
- SPDX header and `{.push raises: [].}` are structural — never comment them
- All comments in British English spelling; never rename identifiers
