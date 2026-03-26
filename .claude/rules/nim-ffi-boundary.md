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
type JmapErrorKind* {.size: sizeof(cint).} = enum
  jekNone = 0
  jekParse = 1
  jekNetwork = 2
  jekAuth = 3
  jekProtocol = 4
```

Always assign explicit ordinal values for ABI stability.

## Error Handling Across FFI

C has no Result types. Translate `JmapResult[T]` to return codes:

```nim
const
  JMAP_OK*          = cint(0)
  JMAP_ERR_NETWORK* = cint(-1)
  JMAP_ERR_AUTH*    = cint(-2)
  JMAP_ERR_PARSE*   = cint(-3)
  JMAP_ERR_PROTOCOL*= cint(-4)
  JMAP_ERR_BUFSZ*   = cint(-5)
  JMAP_ERR_NULL*    = cint(-6)

var lastErrorKind {.threadvar.}: JmapErrorKind
var lastErrorMsg {.threadvar.}: string

proc setLastError(err: JmapError) =
  lastErrorKind = err.kind
  lastErrorMsg = err.message

proc jmapSessionDiscover*(handle: pointer, outSession: ptr pointer): cint
    {.exportc: "jmap_session_discover", cdecl, dynlib.} =
  let client = cast[ptr JmapClientObj](handle)
  if client.isNil:
    return JMAP_ERR_NULL
  let res = discoverSession(client[].baseUrl, client[].bearerToken)
  if res.isErr:
    setLastError(res.error)
    return cint(ord(res.error.kind)) * -1
  outSession[] = allocSession(res.get)
  return JMAP_OK
```

`{.threadvar.}` gives each C thread its own error state.

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
