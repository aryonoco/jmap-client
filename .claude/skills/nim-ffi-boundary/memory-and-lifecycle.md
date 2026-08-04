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

### Pattern A: Caller-Allocated Buffer (exception, not default)

The C caller provides a buffer and the Nim proc copies into it. Reserved
for bulk payloads a caller genuinely wants in its own memory; the default
for every read accessor is Pattern B. Whatever the payload, the operation
reports the required size and never truncates silently -- a silently
truncated buffer is a data-loss bug the caller cannot detect.

```nim
proc jmapEmailBodyCopy*(email: pointer, buf: cstring, bufLen: csize_t,
    required: ptr csize_t): cint
    {.exportc: "jmap_email_body_copy", dynlib, cdecl, raises: [].} =
  if email.isNil or buf.isNil or required.isNil:
    return cint(ord(jsMisuse))
  let e = cast[ptr JmapEmailObj](email)
  let body = e[].bodyText
  required[] = csize_t(body.len + 1)          # including the NUL
  if csize_t(body.len + 1) > bufLen:
    return cint(ord(jsMisuse))                # too small -- size reported, retry
  copyMem(buf, body.cstring, body.len + 1)
  return cint(ord(jsOk))
```

### Pattern B: Handle-Owned Storage (default)

The owning object keeps the Nim `string` alive; the returned `cstring`
borrows from it. Nothing a read accessor returns is ever freed by the
caller, so there is one ownership rule to remember rather than one per
accessor. The header documents the invalidation window on every accessor
whose window is narrower than the owning handle's lifetime.

```nim
type ErrorSlot = object
  status: JmapStatus
  message: string ## handle-owned storage backing the const char* borrow

type JmapClientHandle = object
  ## L5-owned wrapper: what a C `jmap_client*` points at. It holds the
  ## L4 `JmapClient` ref (whose object type is private to
  ## internal/client.nim) plus this handle's error slot.
  client: JmapClient
  err: ErrorSlot ## most recent failure on THIS handle -- never a threadvar

proc jmapErrmsg*(client: pointer): cstring
    {.exportc: "jmap_errmsg", dynlib, cdecl, raises: [].} =
  ## Borrow valid until the next fallible call on this handle or
  ## jmap_client_free -- sqlite3_errmsg semantics.
  if client.isNil:
    return cstring"null client handle"
  let c = cast[ptr JmapClientHandle](client)
  if c[].err.status == jsOk:
    return cstring"no error"
  c[].err.message.cstring
```

**Never `{.threadvar.}` storage.** A borrow anchored to an object the
caller holds has a validity window the caller can reason about and control
by holding the object; a TLS slot's window depends on which thread ran
which unrelated call, which is exactly how OpenSSL-style last-error state
produces cross-thread contamination bugs.


## Memory Ownership (ARC)

ARC = deterministic destruction, no GC pauses, no GC thread.

**`create(T)`** allocates via `alloc0(sizeof(T))` (zero-initialised,
`c_calloc` on malloc systems or Nim's TLSF allocator). Returns `ptr T` --
untracked by ARC, no `RefHeader`, no reference count.

**`new(T)`** returns `ref T` with an ARC `RefHeader` (reference count
field). ARC tracks and frees it when the refcount drops to zero.
Unsuitable for opaque handles: the only reference lives in C, where ARC
cannot see it, so the object would be freed while the caller still holds
the pointer.

**Rule: whoever allocates, frees.** Provide `_new`/`_free` pairs.

The `T` is always an L5-owned wrapper object, never an L4 type: the L4
handles (`JmapClient`, `Transport`) are `ref`s over objects private to
their defining modules, so `create` cannot name them from
`src/jmap_client.nim`.

```nim
let p = create(JmapClientHandle)   # alloc0, zeroed, unmanaged ptr T
p[].client = connected              # the L4 ref this wrapper owns
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

C consumers never see Nim type internals. Every handle is a per-object
`_new`/`_free` pair rather than an arena or a session-wide allocator, so a
consumer frees exactly what it created, in any order.

### New

Fallible construction returns a status and writes the handle through an
out-parameter -- never NULL-as-error, which cannot distinguish "bad
argument" from "network down".

```nim
proc jmapClientNew*(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new", dynlib, cdecl, raises: [].} =
  if sessionUrl.isNil or username.isNil or password.isNil or
      outClient.isNil:
    return cint(ord(jsMisuse))
  # NULL transport selects the built-in one -- C has no default
  # arguments, so the two Nim `connect` overloads collapse into one C
  # entry point with an explicit selector.
  let connected =
    if transport.isNil:
      connect($sessionUrl, $username, $password)
    else:
      connect($sessionUrl, $username, $password,
              cast[ptr JmapTransportHandle](transport)[].transport)
  if connected.isErr:
    return cint(ord(statusOf(connected.error.kind)))  # no handle yet
  let p = create(JmapClientHandle)
  p[].client = connected.get()
  outClient[] = p
  return cint(ord(jsOk))
```

### Accessor (Borrowed Pointer)

Per-field getters are total and infallible, so they return the value
directly: a `cstring` borrowing from the object that owns the view,
valid until that object is freed. There is no status to report and
nothing for the caller to free.

```nim
proc jmapMailboxName*(view: pointer): cstring
    {.exportc: "jmap_mailbox_name", dynlib, cdecl, raises: [].} =
  ## Borrow into the result object this view belongs to: invalidated by
  ## jmap_mailboxes_free on that result, never freed by the caller.
  if view.isNil: return nil
  let mb = cast[ptr JmapMailboxView](view)
  return mb[].name.cstring
```

### Free

```nim
proc jmapClientFree*(handle: pointer)
    {.exportc: "jmap_client_free", dynlib, cdecl, raises: [].} =
  if handle.isNil: return
  let p = cast[ptr JmapClientHandle](handle)
  `=destroy`(p[])    # drops the L4 ref (closing the transport) and
                     # runs destructors for string/seq fields
  dealloc(handle)
```


## Collection Accessor Pattern

Nim `seq`/`string` are managed types (internal layout: `len` + `ptr payload`).
Never expose directly. Use count + indexed borrow, then per-field
getters on the borrowed view -- **never a JSON string**: `char *json`
parameters and return values are forbidden, because they move the schema
out of the type system into text no compiler checks and force every
consumer to link a JSON parser to read a field.

```nim
proc jmapMailboxesCount*(res: pointer): csize_t
    {.exportc: "jmap_mailboxes_count", dynlib, cdecl, raises: [].} =
  if res.isNil: return 0
  let r = cast[ptr JmapMailboxesResult](res)
  return csize_t(r[].items.len)

proc jmapMailboxesAt*(res: pointer, idx: csize_t): pointer
    {.exportc: "jmap_mailboxes_at", dynlib, cdecl, raises: [].} =
  ## NULL when out of range -- a bounds miss is never a defect, and the
  ## view it would return is a borrow, so there is no status to report.
  if res.isNil: return nil
  let r = cast[ptr JmapMailboxesResult](res)
  if idx >= csize_t(r[].items.len): return nil
  return addr r[].items[int(idx)]

proc jmapMailboxUnread*(view: pointer): uint32
    {.exportc: "jmap_mailbox_unread", dynlib, cdecl, raises: [].} =
  if view.isNil: return 0
  let mb = cast[ptr JmapMailboxView](view)
  return mb[].unreadEmails
```


## Error Handling Pattern

FFI procs pattern-match on `Result` values (not `try/except`) and record
the failure on the handle the call was made on:

```nim
proc jmapDoSomething*(client: pointer, ...): cint
    {.exportc: "jmap_do_something", dynlib, cdecl, raises: [].} =
  if client.isNil:
    return cint(ord(jsMisuse))         # no handle -> code-granular only
  let c = cast[ptr JmapClientHandle](client)
  let r = internalOperation(c, ...)
  if r.isErr:
    return recordError(c, r.error)     # stores kind + message, returns status
  # use r.get() ...
  return cint(ord(jsOk))
```

No `clearLastError()` prologue: `recordError` overwrites the slot
unconditionally, so the slot always describes the most recent failing
call on that handle (`sqlite3_errmsg` semantics), and a success leaves a
stale message that the status code already tells the caller to ignore.
This is deliberate -- a clear-then-call protocol is one the caller can
forget, and forgetting it is how a stale diagnostic gets attributed to an
unrelated call.

Failure *before* a handle exists (`jmap_client_new` rejecting its
arguments) reports through the status code alone -- `jmap_strerror`
supplies the text. That is the one place diagnostics are code-granular
rather than message-granular, and it is the price of holding all state on
handles rather than in a global.

`JmapStatus`, `statusOf`, `recordError`, `jmap_errmsg`, and
`jmap_strerror` are in [export-and-types.md](export-and-types.md).


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
  return cint(ord(jsOk))

proc jmapCleanup*()
    {.exportc: "jmap_cleanup", dynlib, cdecl, raises: [].} =
  NimDestroyGlobals()
```

The library is built `--app:lib --noMain` (`justfile`), which suppresses
the `__attribute__((constructor))` NimMain call Nim would otherwise emit
for a POSIX shared library -- that is why `jmap_init` exists at all.
Call it exactly once from the main thread before any other exported
function; call `jmap_cleanup()` once after all handles are freed. The
process-wide latch that lets a skipped `jmap_init` be answered with
`jsMisuse` instead of undefined behaviour is the *only* module-level
state the library holds.


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

- **Handle confinement is the contract:** a handle is used by one thread
  at a time; hand it to another thread by ceasing to use it on the old
  one. Concurrent calls from different threads are safe provided each
  thread uses its own handles. A library that claims blanket thread safety
  and cannot deliver it is worse than one that states a confinement rule
  the consumer can honour.
- Per-handle error state rides that contract: the writer (`recordError`)
  and the reader (`jmap_errmsg`) are on the same thread by construction,
  so the slot needs no TLS and no lock.
- `{.threadvar.}` compiles to `NIM_THREADVAR` (compiler-native TLS) and
  does work on foreign C threads under ARC without Nim thread
  registration -- but it is **forbidden for error state** here, and
  nothing else in this library needs it, because the library keeps no
  ambient configuration and no global callbacks.
- The library holds no cross-handle caches and no module-level mutable
  state beyond the single write-once `jmap_init` latch: two `jmap_client`
  handles in one process never observe each other. The domain core
  (Layers 1-3) is pure by pragma.


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
proc jmapResponseGetItem*(resp: pointer, idx: cint, outItem: ptr cint): cint
    {.exportc: "jmap_response_get_item", dynlib, cdecl, raises: [].} =
  if resp.isNil or outItem.isNil:
    return cint(ord(jsMisuse))                    # prevents NilAccessDefect
  let r = cast[ptr ResponseObj](resp)
  if idx < 0 or idx >= cint(r[].items.len):
    return cint(ord(jsMisuse))                    # prevents IndexDefect
  outItem[] = cint(r[].items[idx])                # now safe to index
  return cint(ord(jsOk))
```


## Pre-Ship Checklist

- [ ] Every exported proc has all 4 pragmas (`exportc`, `dynlib`, `cdecl`, `raises: []`)
- [ ] No bare Nim `int` in signatures (it is pointer-sized `NI`)
- [ ] No `cstring` returned from local `string`
- [ ] Every `create(T)` has matching destroy with `=destroy(p[])` + `dealloc`
- [ ] All pointer arguments nil-checked
- [ ] All index arguments bounds-checked before use
- [ ] All `Result` values pattern-matched (not `try/except`)
- [ ] Every failure path returns a `jmap_status` -- no NULL-as-error, no sentinels
- [ ] Every `Err` recorded via `recordError(handle, err)` before returning
- [ ] No `{.threadvar.}`, no `jmap_last_error()`, no global error state
- [ ] Every returned `const char*` is backed by handle-owned storage, with its
      invalidation window documented in the header
- [ ] Enums use `{.size: sizeof(cint).}` with explicit ordinals
- [ ] `--app:lib` in build command
- [ ] C header has `extern "C"` guards for C++ consumers
- [ ] `jmap_init()` documented as required before any other call


## Further Reading

- `docs/design/17-L5-FFI-Principles.md` -- the C ABI binding design
- `docs/design/14-Nim-API-Principles.md` -- library-wide API principles
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide
