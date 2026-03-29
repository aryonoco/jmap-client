---
name: testament
description: "Nim testament test framework reference — magic spec headers (action, output, exitcode, errormsg, nimout, retries), file naming (t-prefix in tests/ directory), assertion idioms (doAssert and assert, NOT check/suite/expect from unittest), compile and reject test modes, inline error annotations, variable interpolation, implicit field behaviours, and megatest aggregation. Use when writing, reviewing, or running any Nim test file."
user-invocable: false
---

# Testament Test Framework Reference

**Testament is NOT unittest.** It does not have `check`, `suite`, `test`, or
`expect` — those are unittest constructs that do not exist in testament.
Use `doAssert` / `assert` for assertions and magic `discard """..."""` spec
headers for test configuration.

## Nim Version

!`docker exec jmap-client nim --version 2>/dev/null | head -1`

## References

- [Spec header field reference](spec-reference.md) — all spec fields with types and defaults
- [Project-specific test patterns](test-patterns.md) — patterns for this project
- `.claude/llms/testament/llms-full.txt` — upstream docs, spec parser, and test utilities (1101 lines)

When the quick references in `spec-reference.md` and `test-patterns.md` are insufficient,
read the relevant section from `llms-full.txt` using the section index in
`.claude/llms/testament/llms.txt`.

## Decision Tree

| Question | Action |
|----------|--------|
| How to create a new test file? | See File Structure in [spec-reference.md](spec-reference.md) |
| What spec header fields exist? | See Spec Fields in [spec-reference.md](spec-reference.md) |
| How to test that a Result is ok/err? | See [test-patterns.md](test-patterns.md) |
| How to test stdout output? | See Output Matching in [spec-reference.md](spec-reference.md) |
| How to test compile-time rejection? | See Reject Action in [spec-reference.md](spec-reference.md) |
| How to run tests? | `just test` (all), `just test-file tests/unit/tfoo.nim` (single) |
| How to run tests verbosely? | `just test-verbose` |
| What fields interact implicitly? | See Implicit Behaviours in [spec-reference.md](spec-reference.md) |
| How to test inline compiler errors? | See Inline Error Annotations in [spec-reference.md](spec-reference.md) |
| What variables can I use in spec fields? | See Variable Interpolation in [spec-reference.md](spec-reference.md) |
| Need exact spec parser detail? | Read `.claude/llms/testament/llms-full.txt` using index |
