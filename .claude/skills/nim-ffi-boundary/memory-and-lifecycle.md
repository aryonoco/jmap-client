# Memory, Lifecycle, Strings, and Handles

Patterns for implementing the body of exported procs. Consult when writing
a new create/destroy pair, returning strings, or handling errors.


## String Handling

`cstring` is literally `char*` (a magic Nim type, not a wrapper). Under
ARC the backing `NimStringV2` payload pointer is freed deterministically
at scope exit via `=destroy`. A `cstring` pointing into a local `string`
becomes dangling the moment the scope ends.

Convert `cstring` parameters to `string` immediately on entry:

```nim
let s = $cParam   # allocates a new Nim string, safe to keep
```

`--warningAsError:CStringConv` catches dangerous implicit conversions at
compile time.

### Pattern A: Caller-Allocated Buffer

The C caller provides a buffer. The Nim proc copies into it and returns
the byte count, or `JMAP_ERR_BUFSZ` if the buffer is too small.

```nim
proc jmapLastErrorMessage*(buf: cstring, bufLen: cint): cint
    {.exportc: "jmap_last_error_message", dynlib, cdecl, raises: [].} =
  if buf.isNil: return JMAP_ERR_NULL
  if lastErrorMsg.len >= bufLen: return JMAP_ERR_BUFSZ
  copyMem(buf, lastErrorMsg.cstring, lastErrorMsg.len + 1)
  return cint(lastErrorMsg.len)
```

### Pattern B: Library-Owned Storage

A `{.threadvar.}` string whose memory is valid until the next
error-modifying call. The returned `cstring` borrows from this storage.

```nim
var lastErrorMsg {.threadvar.}: string

proc jmapLastError*(): cstring
    {.exportc: "jmap_last_error", dynlib, cdecl, raises: [].} =
  lastErrorMsg.cstring   # valid until next call that modifies lastErrorMsg
```


## Memory Ownership (ARC)

ARC = deterministic destruction, no GC pauses, no GC thread.

**`create(T)`** allocates via `alloc0(sizeof(T))` (zero-initialised,
`c_calloc` on malloc systems or Nim's TLSF allocator). Returns `ptr T` --
untracked by ARC, no `RefHeader`, no reference count.

**`new(T)`** returns `ref T` with an ARC `RefHeader` (reference count
field). ARC tracks and frees it when the refcount drops to zero.
Unsuitable for opaque handles that must outlive Nim scope boundaries.

**Rule: whoever allocates, frees.** Provide create/destroy pairs.

```nim
let p = create(JmapClientObj)   # alloc0, zeroed, unmanaged ptr T
p[].baseUrl = $url
p[].bearerToken = $token
```

**`dealloc`** under ARC calls `rawDealloc` directly on the pointer.
Before calling `dealloc`, you MUST call `` `=destroy`(p[]) `` to run Nim
destructors on managed fields (`string` payloads via `deallocShared`,
`seq` payloads similarly). Forgetting `` `=destroy`(p[]) `` leaks all
managed fields.

**Thread-local heap:** `create(T)` allocates from the calling thread's
allocator. Under ARC, `allocShared` = `allocImpl` (there is no separate
shared heap). For cross-thread handle transfer, use
`createShared(T)` / `deallocShared()`.


## Opaque Handle Lifecycle

Architecture decisions: C consumers never see Nim type internals (5.2).
Per-object free functions, not arena (5.3A).

### Create

```nim
proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", dynlib, cdecl, raises: [].} =
  if url.isNil or token.isNil: return nil
  let p = create(JmapClientObj)
  p[].baseUrl = $url
  p[].bearerToken = $token
  return p
```

### Accessor (Borrowed Pointer)

Returns a `cstring` that borrows from the handle's memory. Valid until
the handle is destroyed.

```nim
proc jmapClientBaseUrl*(handle: pointer): cstring
    {.exportc: "jmap_client_base_url", dynlib, cdecl, raises: [].} =
  if handle.isNil: return nil
  let c = cast[ptr JmapClientObj](handle)
  return c[].baseUrl.cstring
```

### Destroy

```nim
proc jmapClientDestroy*(handle: pointer)
    {.exportc: "jmap_client_destroy", dynlib, cdecl, raises: [].} =
  if handle.isNil: return
  let p = cast[ptr JmapClientObj](handle)
  `=destroy`(p[])    # MUST run Nim destructors for string/seq fields
  dealloc(handle)
```


## Collection Accessor Pattern

Nim `seq`/`string` are managed types (internal layout: `len` + `ptr payload`).
Never expose directly. Use count + indexed get:

```nim
proc jmapResponseCount*(resp: pointer): cint
    {.exportc: "jmap_response_count", dynlib, cdecl, raises: [].} =
  let r = cast[ptr ResponseObj](resp)
  if r.isNil: return 0
  return cint(r[].items.len)

proc jmapResponseGetJson*(resp: pointer, idx: cint,
    buf: cstring, bufLen: cint): cint
    {.exportc: "jmap_response_get_json", dynlib, cdecl, raises: [].} =
  let r = cast[ptr ResponseObj](resp)
  if r.isNil or idx < 0 or idx >= cint(r[].items.len):
    return JMAP_ERR_NULL
  let s = $r[].items[idx]
  if s.len >= bufLen: return JMAP_ERR_BUFSZ
  copyMem(buf, s.cstring, s.len + 1)
  return cint(s.len)
```


## Error Handling Pattern

FFI procs pattern-match on `Result` values (not `try/except`):

```nim
proc jmapDoSomething*(...): cint
    {.exportc: "jmap_do_something", dynlib, cdecl, raises: [].} =
  clearLastError()
  let r = internalOperation(...)
  if r.isErr:
    return setLastError(r.error)
  # use r.get() ...
  return JMAP_OK
```

Error code constants and `setLastError` overloads are in
[export-and-types.md](export-and-types.md).


## Library Initialisation

`NimMain()` initialises the Nim runtime. Under ARC: calls `PreMain()`
(system init + module `DatInit` functions) then `NimMainInner()` (module
top-level code). No GC to initialise, no stack scanning.

**Consequences:**
- Omitting `NimMain()` leaves globals uninitialised -- undefined behaviour
- Calling it twice re-runs all module top-level code, corrupting state
- Neither `NimMain()` nor `NimDestroyGlobals()` is thread-safe

```nim
proc NimMain() {.importc.}
proc NimDestroyGlobals() {.importc.}

proc jmapInit*(): cint
    {.exportc: "jmap_init", dynlib, cdecl, raises: [].} =
  NimMain()
  return JMAP_OK

proc jmapShutdown*()
    {.exportc: "jmap_shutdown", dynlib, cdecl, raises: [].} =
  NimDestroyGlobals()
```

Call `jmap_init()` exactly once from the main thread before any other
exported function. Call `jmap_shutdown()` once after all handles are
destroyed.


## Callbacks

Callback types require explicit `{.cdecl, raises: [].}` annotation.
`{.push raises: [].}` does NOT propagate to proc-type parameters.

```nim
type LogCallback* = proc(msg: cstring) {.cdecl, raises: [].}
```

For effect-polymorphic callbacks (where the callback's effects should be
inferred from the caller), use `{.effectsOf: paramName.}` on the wrapping
proc instead of forcing `{.raises: [].}` on all callback types.


## Thread Safety

- `{.threadvar.}` compiles to `NIM_THREADVAR` (compiler-native TLS). Uses
  `_Thread_local` (C11), `__thread` (GCC), or `__declspec(thread)` (MSVC).
  Works on foreign C threads under ARC (no Nim thread registration needed).
- Concurrent calls from different threads are safe provided each thread
  uses its own handles. No handle may be shared across threads.
- Domain core (Layers 1-3) avoids shared mutable state by convention.


## Defects and `--panics:on`

`{.raises: [].}` does NOT track Defects (`IndexDefect`,
`NilAccessDefect`, `OverflowDefect`, `DivByZeroDefect`, etc.). From the
Nim manual:

> Exceptions inheriting from `system.Defect` are not tracked with the
> `.raises: []` exception tracking mechanism.

With `--panics:on`, Defects call `rawQuit(1)` which maps to C `exit(1)`:
- No Nim stack unwinding
- No `finally` blocks
- No `=destroy` for locals
- C `atexit` handlers and stdio flushing still run (it is `exit()`, not
  `_exit()` or `abort()`)


## Input Validation

Validate all inputs BEFORE operations that could trigger Defects:

```nim
proc jmapResponseGetItem*(resp: pointer, idx: cint): cint
    {.exportc: "jmap_response_get_item", dynlib, cdecl, raises: [].} =
  if resp.isNil: return JMAP_ERR_NULL            # prevents NilAccessDefect
  let r = cast[ptr ResponseObj](resp)
  if idx < 0 or idx >= cint(r[].items.len):
    return JMAP_ERR_NULL                          # prevents IndexDefect
  # now safe to index
  return cint(r[].items[idx])
```


## Pre-Ship Checklist

- [ ] Every exported proc has all 4 pragmas (`exportc`, `dynlib`, `cdecl`, `raises: []`)
- [ ] No bare Nim `int` in signatures (it is pointer-sized `NI`)
- [ ] No `cstring` returned from local `string`
- [ ] Every `create(T)` has matching destroy with `=destroy(p[])` + `dealloc`
- [ ] All pointer arguments nil-checked
- [ ] All index arguments bounds-checked before use
- [ ] All `Result` values pattern-matched (not `try/except`)
- [ ] `clearLastError()` at start of every operation
- [ ] Enums use `{.size: sizeof(cint).}` with explicit ordinals
- [ ] `--app:lib` in build command
- [ ] C header has `extern "C"` guards for C++ consumers
- [ ] `jmap_init()` documented as required before any other call
