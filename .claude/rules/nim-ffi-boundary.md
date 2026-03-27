---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# FFI Boundary (C ABI)

This library exposes a C API via `--mm:arc` and `{.exportc, cdecl.}`.
The FFI layer IS the "imperative shell" — it bridges pure Nim types to
C-compatible types and translates `JmapResult[T]` -> C error codes.

## Architecture

- `src/jmap_client.nim` is the ONLY module with `{.exportc.}` procs.
- Internal modules use pure Nim (`func`, `Result`, distinct types).
- FFI procs are thin adapters: convert C types -> Nim types, call pure
  core, translate Result -> error code.

## Export Pragmas

- ALWAYS `proc` (never `func`) — FFI is inherently side-effectful.
- ALWAYS provide explicit export name: `exportc: "jmap_snake_name"`.
- Include `dynlib` for Windows DLL export compatibility.
- `jmap_` prefix + `snake_case` for all exported C symbols.
- Nim-side name uses `camelCase` per `--styleCheck:error`.

## Type Mapping (Nim -> C)

| Nim type    | C type         | Notes                                |
|-------------|----------------|--------------------------------------|
| `cint`      | `int`          | Error codes. NOT Nim `int`.          |
| `csize_t`   | `size_t`       | Lengths and sizes.                   |
| `cstring`   | `const char*`  | Convert to `string` via `$` on entry.|
| `pointer`   | `void*`        | Opaque handles.                      |

**NEVER** bare Nim `int` in exported signatures — it's pointer-sized.

## String Handling

`cstring` is a raw `char*` — under ARC the backing `string` may be freed while
the `cstring` is live. Convert to `string` immediately: `let s = $cParam`.
NEVER return `cstring` pointing into a local `string`.

Safe patterns for returning strings to C:

```nim
# Pattern 1: Caller-allocated buffer
proc jmapLastErrorMessage*(buf: cstring, bufLen: cint): cint
    {.exportc: "jmap_last_error_message", cdecl, dynlib.} =
  if lastErrorMsg.len >= bufLen:
    return JMAP_ERR_BUFSZ
  copyMem(buf, lastErrorMsg.cstring, lastErrorMsg.len + 1)
  return cint(lastErrorMsg.len)

# Pattern 2: Library-owned storage (valid until next error-modifying call)
var lastErrorMsg {.threadvar.}: string
proc jmapLastError*(): cstring {.exportc: "jmap_last_error", cdecl, dynlib.} =
  lastErrorMsg.cstring
```

## Enums Across FFI

Nim enums default to smallest fitting integer. C enums are `int`-sized.
Force C-compatible sizing:

```nim
type JmapErrorCategory* {.size: sizeof(cint).} = enum
  ## Coarse error category for C return codes.
  ## Flattens the Nim ClientError (TransportError | RequestError) into one enum.
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

C has no Result types. The two-level railway projects to C as:
- **Outer railway** (transport + request): return codes + thread-local error state.
- **Inner railway** (per-invocation method errors): data in the response handle.

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

proc setLastError(err: ClientError): cint =
  ## Stores details in thread-local state, returns C error code.
  case err.kind
  of cekTransport:
    let te = err.transport
    lastErrorMsg = te.message
    case te.kind
    of tekHttpStatus:
      lastErrorHttpStatus = cint(te.httpStatus)  # branch-guarded
      return JMAP_ERR_HTTP
    of tekNetwork: return JMAP_ERR_NETWORK
    # ... (exhaustive over all TransportErrorKind variants)
  of cekRequest:
    let re = err.request
    lastErrorMsg = re.rawType
    case re.errorType
    of retUnknownCapability: return JMAP_ERR_REQ_UNKNOWN_CAP
    # ... (exhaustive over all RequestErrorType variants)
```

Pattern: `clearLastError()` before each operation, `setLastError` on failure.
`{.threadvar.}` gives each C thread its own error state.

### Inner Railway: Per-Invocation Results via Response Handles

Method errors are **data within a successful response**, not return codes.
C consumers access them through response handle accessors:

```nim
proc jmapResponseInvocationIsError*(resp: pointer, idx: cint): cint
    {.exportc: "jmap_response_invocation_is_error", cdecl, dynlib.} =
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil or idx < 0 or idx >= cint(r[].invocations.len): return -1
  return if r[].invocations[idx].isErr: 1 else: 0
```

Per-invocation errors do not use thread-local state — accessed directly
from the response handle via accessor procs (count, isError, errorType, etc.).

## Memory Ownership (ARC)

ARC = deterministic destruction, no GC pauses, no GC thread.

**Rule: whoever allocates, frees.** Provide create/destroy pairs.

Use `create(T)` / `dealloc` for opaque handles — NOT `new(T)`. ARC frees
`new`-allocated objects when the Nim side loses its reference.

```nim
proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", cdecl, dynlib.} =
  let p = create(JmapClientObj)   # zeroed, unmanaged ptr T
  p[].baseUrl = $url
  p[].bearerToken = $token
  return p

proc jmapClientDestroy*(handle: pointer)
    {.exportc: "jmap_client_destroy", cdecl, dynlib.} =
  if handle.isNil: return
  let p = cast[ptr JmapClientObj](handle)
  `=destroy`(p[])    # MUST run Nim destructors for string/seq fields
  dealloc(handle)
```

Forgetting `` `=destroy`(p[]) `` before `dealloc` leaks managed fields.
`GC_ref`/`GC_unref`/`GC_FullCollect` are no-ops under ARC.

## Library Initialisation

`NimMain()` initialises the Nim runtime — call exactly once from the main
thread before any other exported function. NOT thread-safe. Expose as
`jmap_init` / `jmap_shutdown`:

```nim
proc NimMain() {.importc.}

proc jmapInit*(): cint {.exportc: "jmap_init", cdecl, dynlib.} =
  NimMain()
  return JMAP_OK
```

## Thread Safety

- `--threads:on` is enabled.
- Thread-local error state via `{.threadvar.}`.
- Opaque handles are NOT thread-safe — document per-function.
- Functional core (pure funcs, immutable data) is inherently thread-safe.
- `seq`/`string` are managed types — NEVER cross FFI directly. Use
  array+length or callback patterns instead.
