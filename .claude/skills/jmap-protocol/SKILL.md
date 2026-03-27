---
name: jmap-protocol
description: "JMAP protocol reference (RFC 8620 core, RFC 8621 mail) — Session object, Request and Response envelopes, Invocation as 3-element JSON array, result references with # prefix, the 6 standard methods (get, set, query, changes, queryChanges, copy) with request/response field shapes, and the error hierarchy (request-level, method-level, set-level). Use when implementing JMAP types, wire format, or method handlers."
user-invocable: false
---

# JMAP Protocol Reference

This skill complements `docs/architecture-options.md` (which records design
decisions) and `docs/layer-1-design.md` (which specifies Layer 1 types). This
skill provides the RFC context those documents reference.

## References

- [Wire format with JSON examples](wire-format.md) — Session, envelopes, errors
- [The 6 standard methods](method-patterns.md) — request/response shapes per method
- `.claude/llms/jmap/llms-full.txt` — condensed RFC text with section index
- `docs/rfcs/rfc8620-jmap-core.txt` — full RFC 8620 (5043 lines)
- `docs/rfcs/rfc8621-jmap-mail.txt` — full RFC 8621

When the quick references are insufficient, read the relevant section from
`llms-full.txt` using the index in `.claude/llms/jmap/llms.txt`, or the
raw RFC files in `docs/rfcs/`.

## Decision Tree

| Question | Action |
|----------|--------|
| What is the wire format for X? | See [wire-format.md](wire-format.md) |
| What are the 6 standard methods? | See [method-patterns.md](method-patterns.md) |
| What does a Session object contain? | See Session in [wire-format.md](wire-format.md) |
| How do result references work? | See Result References in [wire-format.md](wire-format.md) |
| What error types exist at each level? | See Error Hierarchy in [wire-format.md](wire-format.md) |
| Need full RFC text for section X? | Read `.claude/llms/jmap/llms-full.txt` using index |
