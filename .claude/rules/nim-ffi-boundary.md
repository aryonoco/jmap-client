---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# FFI Boundary (C ABI)

This library exposes a C API via `--mm:arc` and
`{.exportc: "jmap_name", dynlib, cdecl, raises: [].}`.
`src/jmap_client.nim` is the ONLY module with `{.exportc.}` procs.

For detailed FFI patterns, see the `nim-ffi-boundary` skill.

## Mandatory Rules

1. **Four pragmas, no export marker** on every exported proc:
   `exportc: "jmap_name"`, `dynlib`, `cdecl`, `raises: []`. Always `proc`,
   never `func` -- crossing into C is inherently side-effectful. Each pragma
   prevents a distinct failure: Nim name mangling, POSIX symbol hiding, the
   wrong calling convention (`nimcall` is `fastcall`, not `cdecl`), and an
   exception unwinding through a C stack frame. Write all four inline on the
   proc, never bundled into a custom pragma or a surrounding `{.push.}`: the
   header inventory lint reads the pragma text literally, from `exportc: "`
   to the closing `.}`, so a bundle the compiler accepts fails the gate.
   And no `*` on the Nim identifier -- `exportc` already publishes the C
   symbol, while `*` would additionally put the Nim-side name on the
   module's Nim API. The C surface and the Nim surface are separate
   contracts with separate snapshots, and no C entry point belongs in
   `tests/wire_contract/public-api.txt`.

2. **Never bare Nim `int`** in exported signatures -- it is pointer-sized
   (`NI`), so one header would describe a 4-byte field on 32-bit and an
   8-byte field on 64-bit. Use `cint`, `csize_t`, or explicit-width integers.

3. **Never return `cstring` from a local `string`** -- ARC frees the
   payload at scope exit, so the pointer dangles before the caller reads
   it. Return borrows backed by handle-owned storage: the owning handle
   keeps the Nim `string` alive, and the `const char*` is valid until that
   handle is freed. Callers never free anything a read accessor returns.
   Never back a borrow with `{.threadvar.}` storage.

4. **Use `createShared(T)` / `deallocShared`**, not `new(T)` and not the
   thread-local `create(T)` / `dealloc` pair -- an opaque handle lives in C,
   where ARC cannot see the reference, so it must be untracked (no
   `RefHeader`, no refcount); and the C contract lets a consumer hand a
   handle to another thread, which `create` and `dealloc` forbid
   (`lib/system/memalloc.nim`: "The allocated memory belongs to its
   allocating thread!", "The freed memory must belong to its allocating
   thread!"). `T` is always an L5-owned wrapper object holding the L4 `ref`
   plus the handle's slots, never an L4 object type: L4 object types are
   private to their defining modules, so `createShared` cannot even name
   them from `src/jmap_client.nim`.

5. **Call `` `=destroy`(p[]) `` before `deallocShared`** -- deallocation
   releases only the wrapper's own bytes. Without the destructor every
   managed field leaks: `string` and `seq` payloads, and the L4 `ref` whose
   drop is what closes the transport.

6. **Validate all pointer arguments** -- nil checks, bounds checks. Defects
   are fatal with `--panics:on` (`rawQuit(1)`, no unwinding, no `finally`,
   no destructors), so a NULL or an out-of-range index arriving from C is
   something to reject with a status code, never something to catch.

7. **Pattern-match on Result, not try/except** -- FFI procs project
   `Result` onto `jmap_status`:
   `if r.isErr: return recordError(handle, r.error)`, where
   `recordError` stores the error on the handle the call was made on and
   returns its status code. There is no `clearLastError` / `setLastError`
   pair, because no error state exists outside a handle.

8. **Per-handle error state, never thread-local** -- errors travel
   through the returned `jmap_status`; the diagnostic lives on the handle
   (`jmap_errmsg(handle)`, `sqlite3_errmsg` semantics, with
   `jmap_errtype(handle)` beside it for the wire `type` string of a typed
   JMAP failure); static text comes from `jmap_strerror(code)`. The handle
   slot holds every borrow those readers hand out, so each is rendered once
   at record time and none of them allocates. Thread-local last-error state
   is forbidden: it is the OpenSSL `ERR_get_error` pattern, whose
   cross-thread contamination and forgotten-clear bugs are documented
   across every binding ecosystem that consumed it. A handle is confined
   to one thread while in use, so the writer and the reader of its error
   slot are the same thread by construction -- that is what makes
   per-handle state race-free without TLS and without a lock.

## Further reading

- `include/jmap_client.h` -- the live C contract; hand-curated, and what a
  consumer actually compiles against
- `docs/design/17-L5-FFI-Principles.md` -- the C ABI binding design
- `docs/design/14-Nim-API-Principles.md` -- library-wide API principles
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI reference
