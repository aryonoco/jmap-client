# Export Pragmas, Type Mapping, and Error Codes

Patterns for declaring the C interface. Consult when adding a new exported
proc, error code, or modifying the C header.


## Export Pragmas

Every exported proc requires FOUR pragmas:

```nim
proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", dynlib, cdecl, raises: [].} =
```

| Pragma | Purpose | What happens without it |
|--------|---------|------------------------|
| `exportc: "jmap_name"` | Prevents Nim name mangling; sets the C symbol name | Symbol gets `fastcall`-mangled name, unusable from C |
| `dynlib` | Shared library export (`N_LIB_EXPORT` in generated C) | Symbol hidden on POSIX (`visibility("hidden")`) |
| `cdecl` | C calling convention | Default `nimcall` = `fastcall` -- wrong convention, corrupted args |
| `raises: []` | Compile-time guarantee no `CatchableError` escapes | Exception crossing FFI boundary crashes the process |

Additional conventions:
- Always `proc` (never `func`) -- FFI is inherently side-effectful
- Nim-side name: `camelCase` per `--styleCheck:error`
- C-side name: `jmap_snake_case` prefix for all symbols
- `exportc` accepts format strings: `exportc: "jmap_$1"` substitutes the
  Nim identifier name (only `$1` available; literal `$` as `$$`)


## Pragma Bundling

**Custom pragma** (recommended -- bundles cannot carry per-proc `exportc`):

```nim
{.pragma: api, dynlib, cdecl, raises: [].}

proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create", api.} =
  ...
```

**Push/pop** (alternative):

```nim
{.push dynlib, cdecl, raises: [].}

proc jmapClientCreate*(url: cstring, token: cstring): pointer
    {.exportc: "jmap_client_create".} =
  ...

proc jmapClientDestroy*(handle: pointer)
    {.exportc: "jmap_client_destroy".} =
  ...

{.pop.}
```

**Caution:** `{.push.}` affects type definitions too. Never push `exportc`
or `dynlib` across type definitions -- it would attempt to export the type
as a C symbol.


## Type Mapping (Nim to C)

Verified against `nimbase.h` type definitions.

| Nim type | C type | nimbase.h typedef | Notes |
|----------|--------|-------------------|-------|
| `cint` | `int` | `NI32` (`int32_t`) | Always 32-bit |
| `csize_t` | `size_t` | pointer-sized unsigned | |
| `cstring` | `const char*` | `NCSTRING` (`char*`) | Magic type = raw `char*` pointer |
| `pointer` | `void*` | -- | Opaque handles |
| `ptr T` | `T*` | -- | Untraced, not managed by ARC |
| `bool` | `NIM_BOOL` | `_Bool` (C99) | Always 1 byte (static assert) |
| `int64` | `long long` | `NI64` (`int64_t`) | |
| `uint64` | `unsigned long long` | `NU64` (`uint64_t`) | |
| Nim `int` | -- | `NI` (pointer-sized) | **NEVER use in FFI signatures** |

**Never** bare Nim `int` in exported signatures -- it is pointer-sized
(`NI64` on 64-bit, `NI32` on 32-bit). Always use `cint` for 32-bit or
explicit-width types.

Convert `cstring` to `string` immediately on entry: `let s = $cParam`.
See String Handling in [memory-and-lifecycle.md](memory-and-lifecycle.md).


## Enum Handling

Nim enums default to smallest fitting integer. C enums are `int`-sized.
Force C-compatible sizing:

```nim
type JmapErrorCategory* {.size: sizeof(cint).} = enum
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

Rules:
- `{.size: sizeof(cint).}` -- matches C `int` size
- Assign explicit ordinal values for ABI stability
- Use gaps between groups (transport 1-4, request 5-9) for future
  extension without renumbering
- Architecture decision (5.4): no raw enum exposure through C ABI
  pre-1.0. Prefer `cint` constants for maximum stability.


## Error Codes and Thread-Local State

C has no `Result` types. Error handling projects to C as:
- **Result errors** (transport + request): return codes + thread-local state
- **Per-invocation method errors**: data in the response handle

### Error Code Constants

```nim
const
  JMAP_OK*           = cint(0)
  JMAP_ERR_NETWORK*  = cint(-1)   # transport errors: -1..-4
  JMAP_ERR_TLS*      = cint(-2)
  JMAP_ERR_TIMEOUT*  = cint(-3)
  JMAP_ERR_HTTP*     = cint(-4)
  # request errors: -10..-14 (gaps for future extension)
  JMAP_ERR_REQ_UNKNOWN_CAP* = cint(-10)
  JMAP_ERR_REQ_NOT_JSON*    = cint(-11)
  JMAP_ERR_REQ_NOT_REQUEST* = cint(-12)
  JMAP_ERR_REQ_LIMIT*       = cint(-13)
  JMAP_ERR_REQ_UNKNOWN*     = cint(-14)
  # caller errors: -90..-91
  JMAP_ERR_NULL*     = cint(-90)
  JMAP_ERR_BUFSZ*    = cint(-91)
```

### Thread-Local Error State

`{.threadvar.}` compiles to `NIM_THREADVAR` (compiler-native TLS:
`_Thread_local` on C11, `__thread` on GCC, `__declspec(thread)` on MSVC).
Each C thread gets its own error state.

```nim
var lastErrorCategory {.threadvar.}: JmapErrorCategory
var lastErrorMsg {.threadvar.}: string
var lastErrorHttpStatus {.threadvar.}: cint

proc clearLastError() =
  lastErrorCategory = jecNone
  lastErrorMsg = ""
  lastErrorHttpStatus = 0

proc setLastError(err: TransportError): cint =
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
    # ... exhaustive over all RequestErrorType variants
```


## Per-Invocation Results via Response Handles

Method errors are **data within a successful response**, not return codes.
C consumers access them through response handle accessors:

```nim
proc jmapResponseInvocationIsError*(resp: pointer, idx: cint): cint
    {.exportc: "jmap_response_invocation_is_error", dynlib, cdecl, raises: [].} =
  let r = cast[ptr JmapResponseObj](resp)
  if r.isNil or idx < 0 or idx >= cint(r[].invocations.len): return -1
  return if r[].invocations[idx].isErr: 1 else: 0
```

Per-invocation errors do not use thread-local state -- accessed directly
from the response handle via accessor procs (count, isError, errorType).


## C Header

For a self-contained header that does not require `nimbase.h`:

```c
/* jmap_client.h -- standalone C header */
#ifndef JMAP_CLIENT_H
#define JMAP_CLIENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t jmap_bool;     /* NIM_BOOL: always 1 byte */
typedef void*   jmap_handle;   /* opaque Nim object */

/* Error codes */
#define JMAP_OK              0
#define JMAP_ERR_NETWORK   (-1)
#define JMAP_ERR_TLS       (-2)
#define JMAP_ERR_TIMEOUT   (-3)
#define JMAP_ERR_HTTP      (-4)
#define JMAP_ERR_NULL     (-90)
#define JMAP_ERR_BUFSZ    (-91)

/* Lifecycle */
int  jmap_init(void);
void jmap_shutdown(void);

/* Client */
jmap_handle jmap_client_create(const char* url, const char* token);
void        jmap_client_destroy(jmap_handle h);

/* Error introspection */
const char* jmap_last_error_message(void);
int         jmap_last_error_http_status(void);

/* ... remaining exports ... */

#ifdef __cplusplus
}
#endif

#endif /* JMAP_CLIENT_H */
```

If distributing `nimbase.h` alongside the library, C consumers add the
Nim `lib/` directory to their include path (`-I`).
