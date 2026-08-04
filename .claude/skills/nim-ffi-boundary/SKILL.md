---
name: nim-ffi-boundary
description: "Nim C ABI/FFI reference for Layer 5 -- export pragmas (exportc, dynlib, cdecl, raises), Nim-to-C type mapping (cint, cstring, pointer, bool via nimbase.h), cstring handling (caller-allocated buffer, handle-owned borrows), enum sizing ({.size: sizeof(cint).}), the per-handle error model (jmap_status return codes, recordError(handle, err), jmap_errmsg with sqlite3_errmsg semantics, static jmap_strerror; thread-local last-error state via {.threadvar.} is forbidden), opaque handle lifecycle (create/accessor/destroy pairs), collection accessors (count + indexed get), memory ownership (create/dealloc, =destroy before dealloc, ARC), library initialisation (NimMain, NimDestroyGlobals), callback annotation ({.cdecl, raises: [].}), thread safety (handle confinement, one thread per handle), and defect/panics implications (rawQuit, no unwinding). Use when writing or reviewing C ABI exports in src/jmap_client.nim."
user-invocable: false
---

# Nim C ABI / FFI Boundary Reference

C ABI patterns for `src/jmap_client.nim`, the only module in this library
that carries `{.exportc.}` procs. Everything a C consumer can touch --
opaque handles, status codes, borrowed strings, callbacks -- is declared
and implemented there, behind a hand-curated `include/jmap_client.h`.

## Error Model

Errors travel through return values; the diagnostic lives on the handle
the call was made on; nothing lives in thread-local or global state.

- Every fallible exported proc returns `jmap_status`, and its outputs
  travel through out-parameters. Never NULL-as-error, never a negative
  sentinel folded into an answer, never a side channel the caller has to
  fetch separately.
- `recordError(handle, err)` stores the `JmapError` kind and its bounded
  `message()` in the handle's error slot and returns the projected
  `jmap_status`. There is no `clearLastError` / `setLastError` pair.
- `jmap_errmsg(handle)` returns a `const char*` borrowed from that
  handle's own storage, describing the most recent failure on that handle
  (`sqlite3_errmsg` semantics). `jmap_strerror(code)` is static, stateless
  text for a status code, callable before any handle exists.
- Thread-local error state (`{.threadvar.}`, a `jmap_last_error()`
  fetcher, an error queue) is forbidden: that is the OpenSSL
  `ERR_get_error` pattern, whose cross-thread contamination and
  forgotten-clear bugs are documented across every binding ecosystem that
  consumed it. A handle is confined to one thread while in use, so the
  writer and the reader of its error slot are the same thread by
  construction -- per-handle state is race-free without TLS and without a
  lock.

## Skill Files

- [Export pragmas, type mapping, error codes](export-and-types.md) --
  declaring the C interface: pragmas and bundling, Nim-to-C type mapping,
  enum projection, status codes, the handle error slot, the C header
- [Memory, lifecycle, strings, handles](memory-and-lifecycle.md) --
  implementing exported proc bodies: string ownership, `create`/`dealloc`,
  handle new/accessor/free, collection accessors, initialisation,
  callbacks, thread safety, Defects, pre-ship checklist
- [Nim FFI language reference](nim-ffi-reference.md) -- specification text
  quoted from the Nim manual, destructors doc, memory-management doc,
  backends doc and `nimbase.h`; consult to verify any FFI claim

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

## Further Reading

- `docs/design/17-L5-FFI-Principles.md` -- the C ABI binding design
  (error model, handles, ownership, header gates)
- `docs/design/14-Nim-API-Principles.md` -- library-wide API principles
  the C ABI inherits
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide,
  including compiler flags and full build recipes
