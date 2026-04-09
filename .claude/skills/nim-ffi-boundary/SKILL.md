---
name: nim-ffi-boundary
description: "Nim C ABI/FFI reference for Layer 5 -- export pragmas (exportc, dynlib, cdecl, raises), Nim-to-C type mapping (cint, cstring, pointer, bool via nimbase.h), cstring handling (caller-allocated buffer, library-owned storage), enum sizing ({.size: sizeof(cint).}), error codes with thread-local state (threadvar, clearLastError, setLastError), opaque handle lifecycle (create/accessor/destroy pairs), collection accessors (count + indexed get), memory ownership (create/dealloc, =destroy before dealloc, ARC), library initialisation (NimMain, NimDestroyGlobals), callback annotation ({.cdecl, raises: [].}), thread safety (threadvar TLS, per-thread handles), and defect/panics implications (rawQuit, no unwinding). Use when writing or reviewing C ABI exports in src/jmap_client.nim."
user-invocable: false
---

# Nim C ABI / FFI Boundary Reference

This skill provides C ABI patterns for `src/jmap_client.nim`, the only
module with `{.exportc.}` procs. It complements `docs/design/00-architecture.md`
sections 5.1-5.4 (Layer 5 design decisions) and `docs/background/nim-c-abi-guide.md`
(general Nim C ABI reference).

## References

- [Nim FFI language reference](nim-ffi-reference.md) -- authoritative spec text extracted from the Nim manual, destructors doc, memory management doc, backends doc, and nimbase.h
- [Export pragmas, type mapping, error codes](export-and-types.md) -- patterns for declaring the C interface
- [Memory, lifecycle, strings, handles](memory-and-lifecycle.md) -- patterns for implementing exported proc bodies
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide (compiler flags, full examples)
- `docs/design/00-architecture.md` sections 5.1-5.4 -- Layer 5 architecture decisions

## Decision Tree

| Question | Action |
|----------|--------|
| What pragmas does an exported proc need? | See Export Pragmas in [export-and-types.md](export-and-types.md) |
| How to bundle pragmas (custom pragma vs push)? | See Pragma Bundling in [export-and-types.md](export-and-types.md) |
| What is the C type for a Nim type? | See Type Mapping in [export-and-types.md](export-and-types.md) |
| How to expose an enum to C? | See Enum Handling in [export-and-types.md](export-and-types.md) |
| What error code constant to use? | See Error Codes in [export-and-types.md](export-and-types.md) |
| How to generate a standalone C header? | See C Header in [export-and-types.md](export-and-types.md) |
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
