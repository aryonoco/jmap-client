---
name: nim-json-serde
description: "Nim std/json serialisation and deserialisation reference under {.push raises: [].} — raises-free accessors (node{key}, getStr, getInt, getBool, getFloat), boundary parsing patterns (safeParseJson via try/except), toJson and fromJson for objects and case objects, enum serialisation ($ returns backing string, symbolName returns identifier), Opt[T] field omission, and Invocation as JSON array. Use when writing or reviewing JSON serialisation code in Nim."
user-invocable: false
---

# std/json Serialisation Reference

This skill complements `.claude/rules/nim-conventions.md` — that rule enforces
`{.push raises: [].}` and `func` purity; this skill shows which `std/json` APIs
are safe to use under those constraints and provides serialisation patterns.

## Core Constraint

All serialisation and deserialisation logic in this project lives in `func`
(pure, `{.noSideEffect.}`) with `{.push raises: [].}`. The only exception is
the raw JSON parsing boundary, which is a `proc` that catches `CatchableError`.

## References

- [Raises-free vs raises-prone accessor categorisation](accessor-reference.md)
- [Serialisation patterns for this project](serde-patterns.md)
- `.nim-reference/lib/pure/json.nim` — authoritative stdlib source (1398 lines)

## Decision Tree

| Question | Action |
|----------|--------|
| Which accessor inside a `func`? | ONLY raises-free. See [accessor-reference.md](accessor-reference.md) |
| How to parse a raw JSON string? | Boundary `proc` catching CatchableError. See [serde-patterns.md](serde-patterns.md) |
| How to write toJson for an object? | See Object Pattern in [serde-patterns.md](serde-patterns.md) |
| How to write fromJson for a case object? | See Case Object Pattern in [serde-patterns.md](serde-patterns.md) |
| How to serialise/deserialise enums? | See Enum Serialisation in [serde-patterns.md](serde-patterns.md) |
| How to handle Invocation as JSON array? | See Array Tuple Pattern in [serde-patterns.md](serde-patterns.md) |
| How to handle Opt[T] fields? | See Optional Fields in [serde-patterns.md](serde-patterns.md) |
| How to handle `#`-prefixed reference keys? | See Referencable Pattern in [serde-patterns.md](serde-patterns.md) |

When these references are insufficient, read the stdlib source directly:
`.nim-reference/lib/pure/json.nim`.
