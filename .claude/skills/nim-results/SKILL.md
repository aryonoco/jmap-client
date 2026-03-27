---
name: nim-results
description: "nim-results 0.5.1 library API reference for Nim — Result[T,E] and Opt[T] constructors, combinators (map, flatMap, mapErr, mapConvert, filter, valueOr), the prefix ? operator for early return, error type compatibility, and Opt as Result[T, void]. Use when writing, reviewing, or modifying any Nim code that imports results or pkg/results."
user-invocable: false
---

# nim-results 0.5.1 API Reference

This skill complements `.claude/rules/nim-conventions.md` — that rule shows
WHICH patterns to use (ROP, `?`, `valueOr`); this skill provides the complete
API reference and documents common mistakes.

## Project Dependency Version

!`docker exec jmap-client nimble dump 2>/dev/null | grep -E "requires|version" | head -5`

## References

- [Complete API reference](api-reference.md) — all constructors, combinators, and access patterns
- [Common mistakes](common-mistakes.md) — errors Claude frequently makes with this library
- `.claude/llms/nim-results/llms-full.txt` — authoritative full source code (1640 lines)

When the quick reference in `api-reference.md` is insufficient (edge cases,
advanced overloads, or anything uncertain), read the relevant section from
`llms-full.txt` using the section index in `.claude/llms/nim-results/llms.txt`.

## Decision Tree

| Question | Action |
|----------|--------|
| How to construct a Result? | See [Constructors](api-reference.md#constructors) |
| How to chain fallible operations? | See [Combinators](api-reference.md#combinators) |
| How to early-return on error? | See [The ? Operator](api-reference.md#the--prefix-operator) |
| How to safely unwrap a value? | See [Safe Access](api-reference.md#safe-value-access) |
| How to convert between error types? | See [mapErr](api-reference.md#error-transformation) |
| How to use Opt[T]? | See [Opt](api-reference.md#optt--resultt-void) |
| What NOT to do? | See [common-mistakes.md](common-mistakes.md) |
| Need exact function signature? | Read `.claude/llms/nim-results/llms-full.txt` |
