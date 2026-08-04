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
Binding design: `docs/design/17-L5-FFI-Principles.md` (D10).
Background reference: `docs/background/nim-c-abi-guide.md`

## Mandatory Rules

1. **Four pragmas** on every exported proc: `exportc: "jmap_name"`, `dynlib`,
   `cdecl`, `raises: []`. Always `proc`, never `func`.

2. **Never bare Nim `int`** in exported signatures -- it is pointer-sized
   (`NI`). Use `cint`, `csize_t`, or explicit-width integers.

3. **Never return `cstring` from a local `string`** -- ARC frees the
   payload at scope exit. Return borrows backed by handle-owned storage:
   the owning handle keeps the Nim `string` alive, and the `const char*`
   is documented valid until that handle is freed (library-owned-borrow
   model, design doc 17 §3). Never `{.threadvar.}` storage.

4. **Use `create(T)` / `dealloc`**, not `new(T)` -- opaque handles must be
   untracked by ARC (no `RefHeader`). `T` is always an L5-owned wrapper
   object holding the L4 `ref` (plus the error slot), never an L4 object
   type: those are private to their modules (design doc 17 §2).

5. **Call `` `=destroy`(p[]) `` before `dealloc`** -- forgetting this leaks
   all managed fields (`string`, `seq`).

6. **Validate all pointer arguments** -- nil checks, bounds checks. Defects
   are fatal with `--panics:on` (`rawQuit(1)`, no unwinding, no `finally`).

7. **Pattern-match on Result, not try/except** -- FFI procs project
   `Result` onto `jmap_status`:
   `if r.isErr: return recordError(handle, r.error)`, where
   `recordError` stores the error on the handle the call was made on
   and returns its status code. No `clearLastError`/`setLastError`
   pair; no error state exists outside a handle.

8. **Per-handle error state, never thread-local** -- errors travel
   through the returned `jmap_status`; diagnostics live on the handle
   (`jmap_errmsg(handle)`, `sqlite3_errmsg` semantics); static text via
   `jmap_strerror(code)`. `{.threadvar.}` error state is the OpenSSL
   anti-pattern P14 forbids by name. Handles must not cross threads
   while in use (P24) -- which is exactly what makes per-handle state
   race-free.
