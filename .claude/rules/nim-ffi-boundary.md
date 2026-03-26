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

```nim
proc jmapInit*(): cint {.exportc: "jmap_init", cdecl, dynlib.} =
  NimMain()
  return JMAP_OK
```

Rules:
- ALWAYS `proc` (never `func`) — FFI is inherently side-effectful.
- ALWAYS provide explicit export name: `exportc: "jmap_snake_name"`.
- Include `dynlib` for Windows DLL export compatibility.
- `jmap_` prefix + `snake_case` for all exported C symbols.
- Nim-side name uses `camelCase` per `--styleCheck:error`.

## Type Mapping (Nim -> C)

| Nim type    | C type         | Notes                                  |
|-------------|----------------|----------------------------------------|
| `cint`      | `int`          | Use for error codes. NOT Nim `int`.    |
| `cuint`     | `unsigned int` | 32-bit unsigned.                       |
| `csize_t`   | `size_t`       | For lengths and sizes.                 |
| `cstring`   | `const char*`  | Read-only pointer. Convert to `string` |
|             |                | immediately via `$` on entry.          |
| `pointer`   | `void*`        | Opaque handles.                        |

**NEVER** use bare Nim `int` in exported signatures — it's pointer-sized,
not C `int`-sized.

## String Handling

`cstring` is a raw `char*` — under ARC, the backing `string` may be destroyed
while the `cstring` alias is live, creating a dangling pointer.
`CStringConv` warning-as-error catches implicit conversion. Convert `cstring`
to `string` immediately on entry: `let s = $cParam`. NEVER return `cstring`
pointing into a local `string`.

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

Nim enums default to smallest fitting integer. C enums are `int`-sized:

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

C has no Result types. The two-level railway is projected to C as follows:

**Outer railway (transport + request failures):** return codes from operations
that hit the network. The most recent `ClientError` details are stored in
thread-local state and accessible via query functions.

**Inner railway (per-invocation method errors):** data within a successful
response. Accessed through response handle accessors, not return codes.

### Outer Railway: Return Codes and Thread-Local Error State

```nim
const
  JMAP_OK*                         = cint(0)
  # Transport errors (negative, starting at -1)
  JMAP_ERR_NETWORK*                = cint(-1)
  JMAP_ERR_TLS*                    = cint(-2)
  JMAP_ERR_TIMEOUT*                = cint(-3)
  JMAP_ERR_HTTP_STATUS*            = cint(-4)
  # Request-level errors (negative, starting at -10)
  JMAP_ERR_REQ_UNKNOWN_CAPABILITY* = cint(-10)
  JMAP_ERR_REQ_NOT_JSON*           = cint(-11)
  JMAP_ERR_REQ_NOT_REQUEST*        = cint(-12)
  JMAP_ERR_REQ_LIMIT*              = cint(-13)
  JMAP_ERR_REQ_UNKNOWN*            = cint(-14)
  # Caller errors (negative, starting at -90)
  JMAP_ERR_NULL*                   = cint(-90)
  JMAP_ERR_BUFSZ*                  = cint(-91)

# Thread-local error state: stores the most recent ClientError details.
var lastErrorCategory {.threadvar.}: JmapErrorCategory
var lastErrorMsg {.threadvar.}: string
var lastErrorHttpStatus {.threadvar.}: cint
var lastErrorDetail {.threadvar.}: string

proc clearLastError() =
  lastErrorCategory = jecNone
  lastErrorMsg = ""
  lastErrorHttpStatus = 0
  lastErrorDetail = ""

proc setLastError(err: ClientError): cint =
  ## Stores error details and returns the corresponding C error code.
  case err.kind
  of cekTransport:
    let te = err.transport
    lastErrorMsg = te.message
    lastErrorHttpStatus = if te.httpStatus.isSome: cint(te.httpStatus.get) else: 0
    lastErrorDetail = ""
    case te.kind
    of tekNetwork:
      lastErrorCategory = jecTransportNetwork
      return JMAP_ERR_NETWORK
    of tekTls:
      lastErrorCategory = jecTransportTls
      return JMAP_ERR_TLS
    of tekTimeout:
      lastErrorCategory = jecTransportTimeout
      return JMAP_ERR_TIMEOUT
    of tekHttpStatus:
      lastErrorCategory = jecTransportHttpStatus
      return JMAP_ERR_HTTP_STATUS
  of cekRequest:
    let re = err.request
    lastErrorMsg = re.rawType
    lastErrorHttpStatus = if re.status.isSome: cint(re.status.get) else: 0
    lastErrorDetail = if re.detail.isSome: re.detail.get else: ""
    case re.errorType
    of retUnknownCapability:
      lastErrorCategory = jecRequestUnknownCapability
      return JMAP_ERR_REQ_UNKNOWN_CAPABILITY
    of retNotJson:
      lastErrorCategory = jecRequestNotJson
      return JMAP_ERR_REQ_NOT_JSON
    of retNotRequest:
      lastErrorCategory = jecRequestNotRequest
      return JMAP_ERR_REQ_NOT_REQUEST
    of retLimit:
      lastErrorCategory = jecRequestLimit
      return JMAP_ERR_REQ_LIMIT
    of retUnknown:
      lastErrorCategory = jecRequestUnknown
      return JMAP_ERR_REQ_UNKNOWN

proc jmapSend*(handle: pointer, reqHandle: pointer, outResp: ptr pointer): cint
    {.exportc: "jmap_send", cdecl, dynlib.} =
  let client = cast[ptr JmapClientObj](handle)
  if client.isNil:
    return JMAP_ERR_NULL
  clearLastError()
  let res = client[].send(cast[ptr RequestObj](reqHandle)[])
  if res.isErr:
    return setLastError(res.error)
  outResp[] = allocResponse(res.get)
  return JMAP_OK
```

### Inner Railway: Per-Invocation Results via Response Handles

Method errors are **data within a successful response**, not return codes.
The C consumer iterates invocation results through the response handle:

```nim
proc jmapResponseInvocationCount*(resp: pointer): cint
    {.exportc: "jmap_response_invocation_count", cdecl, dynlib.} =
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil: return 0
  return cint(r[].invocations.len)

proc jmapResponseInvocationIsError*(resp: pointer, index: cint): cint
    {.exportc: "jmap_response_invocation_is_error", cdecl, dynlib.} =
  ## Returns 1 if the invocation at `index` is a MethodError, 0 if success.
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil or index < 0 or index >= cint(r[].invocations.len):
    return -1
  return if r[].invocations[index].isErr: 1 else: 0

proc jmapResponseMethodErrorType*(resp: pointer, index: cint,
    buf: cstring, bufLen: cint): cint
    {.exportc: "jmap_response_method_error_type", cdecl, dynlib.} =
  ## Copies the method error rawType string into `buf`.
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil: return JMAP_ERR_NULL
  let inv = r[].invocations[index]
  if inv.isOk: return 0  # not an error
  let errType = inv.error.rawType
  if errType.len >= bufLen:
    return JMAP_ERR_BUFSZ
  copyMem(buf, errType.cstring, errType.len + 1)
  return cint(errType.len)
```

`{.threadvar.}` gives each C thread its own outer-railway error state.
Per-invocation errors do not use thread-local state — they are accessed
directly from the response handle.

## Memory Ownership (ARC)

ARC = deterministic destruction, no GC pauses, no GC thread.

**Rule: whoever allocates, frees.** Provide create/destroy pairs.

Use `create[T]()` / `dealloc` for opaque handles — NOT `new(T)`. ARC would
free `new`-allocated objects when the Nim side loses its reference.
`create(T)` returns a zeroed, unmanaged `ptr T` (equivalent to
`cast[ptr T](alloc0(sizeof(T)))` but typed and cleaner).

```nim
type JmapClientObj = object   # internal, NOT exported
  baseUrl: string
  bearerToken: string
  session: Opt[Session]

proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", cdecl, dynlib.} =
  let p = create(JmapClientObj)
  p[].baseUrl = $url
  p[].bearerToken = $token
  return p

proc jmapClientDestroy*(handle: pointer)
    {.exportc: "jmap_client_destroy", cdecl, dynlib.} =
  if handle.isNil:
    return
  let p = cast[ptr JmapClientObj](handle)
  `=destroy`(p[])    # MUST run Nim destructors for managed fields (string, seq)
  dealloc(handle)    # then free raw memory
```

Forgetting `=destroy(p[])` before `dealloc` leaks all managed fields.

`GC_ref`/`GC_unref`/`GC_FullCollect` are no-ops under ARC — do not use.

## Library Initialisation

```nim
proc NimMain() {.importc.}

proc jmapInit*(): cint {.exportc: "jmap_init", cdecl, dynlib.} =
  NimMain()
  return JMAP_OK

proc jmapShutdown*() {.exportc: "jmap_shutdown", cdecl, dynlib.} =
  # Clean up module-level state if needed
  discard
```

`NimMain()` initialises the Nim runtime. Call exactly once from the main
thread before any other exported function. NOT thread-safe.

## Thread Safety

- `--threads:on` is enabled.
- Thread-local error state via `{.threadvar.}`.
- Opaque handles are NOT thread-safe — document per-function.
- Functional core (pure funcs, immutable data) is inherently thread-safe.
- `seq`/`string` are managed types — NEVER cross FFI directly. Use
  array+length or callback patterns instead.
