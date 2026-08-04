---
name: nim-ffi-boundary
description: "Nim C ABI/FFI reference for Layer 5 -- export pragmas (exportc, dynlib, cdecl, raises), Nim-to-C type mapping (cint, cstring, pointer, bool via nimbase.h), cstring handling (caller-allocated buffer, handle-owned borrows), enum sizing ({.size: sizeof(cint).}), the per-handle error model (jmap_status return codes, recordError(handle, err), jmap_errmsg with sqlite3_errmsg semantics, static jmap_strerror; thread-local last-error state via {.threadvar.} is forbidden), opaque handle lifecycle (create/accessor/destroy pairs), collection accessors (count + indexed get), memory ownership (create/dealloc, =destroy before dealloc, ARC), library initialisation (NimMain, NimDestroyGlobals), callback annotation ({.cdecl, raises: [].}), thread safety (handle confinement, one thread per handle), and defect/panics implications (rawQuit, no unwinding). Use when writing or reviewing C ABI exports in src/jmap_client.nim."
user-invocable: false
---

# Nim C ABI / FFI Boundary Reference

This skill provides C ABI patterns for `src/jmap_client.nim`, the only
module with `{.exportc.}` procs. The binding design is
`docs/design/17-L5-FFI-Principles.md` (D10) -- it is authoritative over
this skill wherever the two disagree, and it supersedes
`docs/design/00-architecture.md` §5.1-5.4 (handle naming and inventory,
enum exposure, error model). `docs/background/nim-c-abi-guide.md` is the
general Nim C ABI reference; its thread-local last-error pattern is
forbidden here.

## Error Model (Settled)

Errors travel through return values; diagnostics live on the handle the
call was made on; nothing lives in thread-local or global state
(design doc 17 sections 1 and 3; `.claude/rules/nim-ffi-boundary.md`
rules 3, 7, 8):

- Every fallible exported proc returns `jmap_status`; outputs travel
  through out-parameters. Never NULL-as-error, never a fetchable side
  channel.
- `recordError(handle, err)` stores the `JmapError` kind and its bounded
  `message()` in the handle's error slot and returns the projected
  `jmap_status`. There is no `clearLastError` / `setLastError` pair.
- `jmap_errmsg(handle)` returns a `const char*` borrowed from that
  handle's storage (`sqlite3_errmsg` semantics); `jmap_strerror(code)`
  is static, stateless text for a status code.
- `{.threadvar.}` error state is the OpenSSL `ERR_get_error`
  anti-pattern P14 forbids by name. Handle confinement (P24) is what
  makes per-handle state race-free.

## References

- [Nim FFI language reference](nim-ffi-reference.md) -- authoritative spec text extracted from the Nim manual, destructors doc, memory management doc, backends doc, and nimbase.h
- [Export pragmas, type mapping, error codes](export-and-types.md) -- patterns for declaring the C interface
- [Memory, lifecycle, strings, handles](memory-and-lifecycle.md) -- patterns for implementing exported proc bodies
- `docs/design/17-L5-FFI-Principles.md` -- the binding C ABI design (error model, handles, ownership, header gates)
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide (compiler flags, full examples); its Pattern 2 (thread-local error state) is forbidden here
- `docs/design/00-architecture.md` sections 5.1-5.4 -- Layer 5 architecture decisions, **superseded by doc 17** on handle naming/inventory, enum exposure and the error model (dated amendments are in that file); only §5.1 (lossy projection) and §5.3A (per-object free functions) still apply as written

## Decision Tree

| Question | Action |
|----------|--------|
| What pragmas does an exported proc need? | See Export Pragmas in [export-and-types.md](export-and-types.md) |
| How to bundle pragmas (custom pragma vs push)? | See Pragma Bundling in [export-and-types.md](export-and-types.md) |
| What is the C type for a Nim type? | See Type Mapping in [export-and-types.md](export-and-types.md) |
| How to expose an enum to C? | See Enum Handling in [export-and-types.md](export-and-types.md) -- hand-written C enum in the curated header, gate-checked against the Nim enum; never the Nim type, never bare `cint` constants |
| What status code to return, and where does the message go? | See Error Codes and Per-Handle Error State in [export-and-types.md](export-and-types.md) |
| How is the public C header written? | See C Header in [export-and-types.md](export-and-types.md) -- hand-curated and gate-checked against the exports, never generated |
| How to return a string to C safely? | See String Handling in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| How to manage opaque handle memory? | See Opaque Handle Lifecycle in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| How to expose a seq/collection to C? | See Collection Accessors in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| How to handle errors across FFI? | See Error Handling Pattern in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| How to initialise/shut down the library? | See Library Initialisation in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| What are the thread safety rules? | See Thread Safety in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| What about Defects and `--panics:on`? | See Defects in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| Pre-ship review checklist? | See Pre-Ship Checklist in [memory-and-lifecycle.md](memory-and-lifecycle.md) |
| Need to verify an FFI claim against the Nim spec? | See [nim-ffi-reference.md](nim-ffi-reference.md) |
| Need full compiler flags or build recipe? | See `docs/background/nim-c-abi-guide.md` |
