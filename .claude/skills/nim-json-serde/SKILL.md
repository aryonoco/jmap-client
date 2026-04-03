---
name: nim-json-serde
description: "Nim std/json serialisation and deserialisation reference — idiomatic accessors (node[\"key\"], node{\"key\"}, getStr, getInt, to(T)), toJson and fromJson patterns for objects and case objects, enum serialisation ($ returns backing string, symbolName returns identifier), Option[T] field handling, and Invocation as JSON array. Use when writing or reviewing JSON serialisation code in Nim."
user-invocable: false
---

# std/json Serialisation Reference

This skill complements `.claude/rules/nim-conventions.md` — it provides
`std/json` API patterns and serialisation conventions for this project.

## Approach

Serialisation and deserialisation use `proc` with standard `std/json` APIs.
Required fields use direct accessors (`node["key"]`, `to(T)`) that raise on
missing/wrong-type data. Optional fields use nil-safe accessors (`node{"key"}`,
`getStr`, etc.) or `hasKey` checks. Exceptions propagate naturally through
Layers 1–4; Layer 5 catches them.

## References

- [Accessor categorisation](accessor-reference.md) — idiomatic, nil-safe, and dangerous accessors
- [Serialisation patterns for this project](serde-patterns.md)
- `.nim-reference/lib/pure/json.nim` — authoritative stdlib source (1398 lines)

## Decision Tree

| Question | Action |
|----------|--------|
| Which accessor for required fields? | `node["key"]` or `to(T)`. See [accessor-reference.md](accessor-reference.md) |
| Which accessor for optional fields? | `node{"key"}` + nil-safe extractors. See [accessor-reference.md](accessor-reference.md) |
| How to parse a raw JSON string? | `parseJson(s)` — raises on malformed input. See [serde-patterns.md](serde-patterns.md) |
| How to write toJson for an object? | See Object Pattern in [serde-patterns.md](serde-patterns.md) |
| How to write fromJson for a case object? | See Case Object Pattern in [serde-patterns.md](serde-patterns.md) |
| How to serialise/deserialise enums? | See Enum Serialisation in [serde-patterns.md](serde-patterns.md) |
| How to handle Invocation as JSON array? | See Array Tuple Pattern in [serde-patterns.md](serde-patterns.md) |
| How to handle Option[T] fields? | See Optional Fields in [serde-patterns.md](serde-patterns.md) |
| How to handle `#`-prefixed reference keys? | See Referencable Pattern in [serde-patterns.md](serde-patterns.md) |

When these references are insufficient, read the stdlib source directly:
`.nim-reference/lib/pure/json.nim`.
