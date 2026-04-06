---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# FFI Boundary (C ABI)

This library exposes a C API via `--mm:arc` and
`{.exportc: "jmap_name", dynlib, cdecl, raises: [].}`.
The FFI layer IS the "imperative shell" — it bridges Nim types to
C-compatible types and catches exceptions, translating them to C error codes.

Background reference: `docs/background/nim-c-abi-guide.md`

## Architecture

- `src/jmap_client.nim` is the ONLY module with `{.exportc.}` procs.
- Internal modules use nim-results ROP (`func`/`proc`, `Result[T, E]`,
  `?` operator, distinct types). `{.push raises: [].}` on every module.
- FFI procs are thin adapters: convert C types -> Nim types, call internal
  Nim code, pattern-match on `Result` values to produce C error codes.
  Stdlib IO calls that raise are wrapped in `try/except` +
  `{.cast(raises: [CatchableError]).}` at the L4 IO boundary.

## Export Pragmas

Every exported proc requires FOUR pragmas:

- `exportc: "jmap_snake_name"` — explicit C symbol name, `jmap_` prefix
- `dynlib` — shared library export (`__declspec(dllexport)` on Windows,
  `__attribute__((visibility("default")))` on POSIX). Requires `exportc`.
  Auto-sets `cdecl` if omitted, but be explicit.
- `cdecl` — C calling convention (Nim default is `nimcall`/`__fastcall`)
- `raises: []` — compile-time guarantee no `CatchableError` escapes

Additional conventions:
- ALWAYS `proc` (never `func`) — FFI is inherently side-effectful.
- Nim-side name uses `camelCase` per `--styleCheck:error`.
- Use `{.pragma: api, dynlib, cdecl, raises: [].}` bundle with per-proc
  `exportc: "jmap_name"` (bundles cannot carry per-proc exportc arguments).
- Or use `{.push dynlib, cdecl, raises: [].}` with per-proc `exportc`.

**Caution:** `{.push.}` affects type definitions too. Do not push `exportc`
or `dynlib` across type definitions.

## Type Mapping (Nim -> C)

| Nim type    | C type         | Notes                                |
|-------------|----------------|--------------------------------------|
| `cint`      | `int`          | Always `int32`. NOT Nim `int`.       |
| `csize_t`   | `size_t`       | Pointer-sized unsigned.              |
| `cstring`   | `const char*`  | Convert to `string` via `$` on entry.|
| `pointer`   | `void*`        | Opaque handles.                      |
| `bool`      | `NIM_BOOL`     | Always 1 byte.                       |

**NEVER** bare Nim `int` in exported signatures — it's pointer-sized.

## String Handling

`cstring` is a raw `char*` — under ARC the backing `string` may be freed while
the `cstring` is live. Convert to `string` immediately: `let s = $cParam`.
NEVER return `cstring` pointing into a local `string`.

`--warningAsError:CStringConv` catches dangerous implicit conversions at
compile time.

Safe patterns for returning strings to C:

```nim
# Pattern 1: Caller-allocated buffer
proc jmapLastErrorMessage*(buf: cstring, bufLen: cint): cint
    {.exportc: "jmap_last_error_message", dynlib, cdecl, raises: [].} =
  if lastErrorMsg.len >= bufLen:
    return JMAP_ERR_BUFSZ
  copyMem(buf, lastErrorMsg.cstring, lastErrorMsg.len + 1)
  return cint(lastErrorMsg.len)

# Pattern 2: Library-owned storage (valid until next error-modifying call)
var lastErrorMsg {.threadvar.}: string
proc jmapLastError*(): cstring
    {.exportc: "jmap_last_error", dynlib, cdecl, raises: [].} =
  lastErrorMsg.cstring
```

## Enums Across FFI

Nim enums default to smallest fitting integer. C enums are `int`-sized.
Force C-compatible sizing:

```nim
type JmapErrorCategory* {.size: sizeof(cint).} = enum
  ## Coarse error category for C return codes.
  jecNone = 0
  jecTransportNetwork = 1
  jecTransportTls = 2
  jecTransportTimeout = 3
  jecTransportHttpStatus = 4
  jecRequestUnknownCapability = 5
  jecRequestNotJson = 6
  jecRequestNotRequest = 7
  jecRequestLimit = 8
  jecRequestUnknown = 9
```

Always assign explicit ordinal values for ABI stability. Use gaps between
groups (transport 1-4, request 5-9) for future extension without renumbering.

## Error Handling Across FFI

C has no Result types. Error handling projects to C as:
- **Result errors** (transport + request): return codes + thread-local error state.
- **Per-invocation method errors**: data in the response handle.

### Defects and `--panics:on`

**Critical:** This project uses `--panics:on`. `{.raises: [].}` does NOT
track Defects (`IndexDefect`, `NilAccessDefect`, `OverflowDefect`, etc.).
With `--panics:on`, Defects call `rawQuit(1)` — immediate process abort,
no unwinding, no cleanup.

**Defensive coding is mandatory:** Validate all inputs (bounds, nil, divisors)
BEFORE operations that could trigger Defects. Never rely on catching Defects.

### Error Codes and Thread-Local State

```nim
const
  JMAP_OK*           = cint(0)
  JMAP_ERR_NETWORK*  = cint(-1)   # transport errors: -1..-4
  JMAP_ERR_TLS*      = cint(-2)
  JMAP_ERR_TIMEOUT*  = cint(-3)
  JMAP_ERR_HTTP*     = cint(-4)
  # request errors: -10..-14 (gaps allow future extension)
  JMAP_ERR_REQ_UNKNOWN_CAP* = cint(-10)
  JMAP_ERR_REQ_NOT_JSON*    = cint(-11)
  # ... (exhaustive over RequestErrorType variants)
  JMAP_ERR_NULL*     = cint(-90)  # caller errors
  JMAP_ERR_BUFSZ*    = cint(-91)

var lastErrorCategory {.threadvar.}: JmapErrorCategory
var lastErrorMsg {.threadvar.}: string
var lastErrorHttpStatus {.threadvar.}: cint

proc setLastError(err: TransportError): cint =
  ## Stores details in thread-local state, returns C error code.
  lastErrorMsg = err.message
  case err.kind
  of tekHttpStatus:
    lastErrorHttpStatus = cint(err.httpStatus)
    return JMAP_ERR_HTTP
  of tekNetwork: return JMAP_ERR_NETWORK
  of tekTls: return JMAP_ERR_TLS
  of tekTimeout: return JMAP_ERR_TIMEOUT

proc setLastError(err: ClientError): cint =
  case err.kind
  of cekTransport: return setLastError(err.transport)
  of cekRequest:
    lastErrorMsg = err.request.rawType
    case err.request.errorType
    of retUnknownCapability: return JMAP_ERR_REQ_UNKNOWN_CAP
    # ... (exhaustive over all RequestErrorType variants)
```

Pattern: `clearLastError()` before each operation, `setLastError` on failure.
`{.threadvar.}` gives each C thread its own error state.

Usage in exported procs (pattern-matching on Result, not try/except):

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

### Per-Invocation Results via Response Handles

Method errors are **data within a successful response**, not return codes.
C consumers access them through response handle accessors:

```nim
proc jmapResponseInvocationIsError*(resp: pointer, idx: cint): cint
    {.exportc: "jmap_response_invocation_is_error", dynlib, cdecl, raises: [].} =
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil or idx < 0 or idx >= cint(r[].invocations.len): return -1
  return if r[].invocations[idx].isErr: 1 else: 0
```

Per-invocation errors do not use thread-local state — accessed directly
from the response handle via accessor procs (count, isError, errorType, etc.).

## Memory Ownership (ARC)

ARC = deterministic destruction, no GC pauses, no GC thread.

**Rule: whoever allocates, frees.** Provide create/destroy pairs.

Use `create(T)` / `dealloc` for opaque handles — NOT `new(T)`. `create(T)`
calls `alloc0()` (`c_calloc`) — zero-initialised, untracked by ARC. `new(T)`
returns `ref T` tracked by ARC and freed when ARC determines the ref is dead.

```nim
proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", dynlib, cdecl, raises: [].} =
  let p = create(JmapClientObj)   # zeroed, unmanaged ptr T
  p[].baseUrl = $url
  p[].bearerToken = $token
  return p

proc jmapClientDestroy*(handle: pointer)
    {.exportc: "jmap_client_destroy", dynlib, cdecl, raises: [].} =
  if handle.isNil: return
  let p = cast[ptr JmapClientObj](handle)
  `=destroy`(p[])    # MUST run Nim destructors for string/seq fields
  dealloc(handle)
```

Forgetting `` `=destroy`(p[]) `` before `dealloc` leaks managed fields.
`GC_ref`/`GC_unref`/`GC_FullCollect` are no-ops under ARC.

## Library Initialisation

`NimMain()` initialises the Nim runtime — call exactly once from the main
thread before any other exported function. Under ARC, NimMain calls
`PreMain()` (global variable init) then `NimMainInner()` (module top-level
code). No GC to initialise. NOT thread-safe. Expose as `jmap_init` /
`jmap_shutdown`:

```nim
proc NimMain() {.importc.}

proc jmapInit*(): cint
    {.exportc: "jmap_init", dynlib, cdecl, raises: [].} =
  NimMain()
  return JMAP_OK
```

## Callbacks

Callback types require explicit `{.cdecl, raises: [].}` annotation.
`{.push raises: [].}` does NOT propagate to proc-type parameters.

## Thread Safety

- `--threads:on` is enabled.
- Thread-local error state via `{.threadvar.}`.
- Opaque handles are NOT thread-safe — document per-function.
- Domain core (Layers 1–3) avoids shared mutable state by convention.
- `seq`/`string` are managed types — NEVER cross FFI directly. Use
  array+length or callback patterns instead.
