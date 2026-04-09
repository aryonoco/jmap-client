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
Background reference: `docs/background/nim-c-abi-guide.md`

## Mandatory Rules

1. **Four pragmas** on every exported proc: `exportc: "jmap_name"`, `dynlib`,
   `cdecl`, `raises: []`. Always `proc`, never `func`.

2. **Never bare Nim `int`** in exported signatures -- it is pointer-sized
   (`NI`). Use `cint`, `csize_t`, or explicit-width integers.

3. **Never return `cstring` from a local `string`** -- ARC frees the
   payload at scope exit. Use caller-allocated buffer or library-owned
   `{.threadvar.}` storage.

4. **Use `create(T)` / `dealloc`**, not `new(T)` -- opaque handles must be
   untracked by ARC (no `RefHeader`).

5. **Call `` `=destroy`(p[]) `` before `dealloc`** -- forgetting this leaks
   all managed fields (`string`, `seq`).

6. **Validate all pointer arguments** -- nil checks, bounds checks. Defects
   are fatal with `--panics:on` (`rawQuit(1)`, no unwinding, no `finally`).

7. **Pattern-match on Result, not try/except** -- FFI procs use
   `clearLastError()`, then `if r.isErr: return setLastError(r.error)`.

8. **Thread-local error state** via `{.threadvar.}` -- each C thread gets
   its own error state. Handles must not cross threads.
