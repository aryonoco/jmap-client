# Export Pragmas, Type Mapping, and Error Codes

Patterns for declaring the C interface. Consult when adding a new exported
proc, error code, or modifying the C header.


## Export Pragmas

Every exported proc requires FOUR pragmas:

```nim
proc jmapClientNew*(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new", dynlib, cdecl, raises: [].} =
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

proc jmapClientNew*(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new", api.} =
  ...
```

**Push/pop** (alternative):

```nim
{.push dynlib, cdecl, raises: [].}

proc jmapClientNew*(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new".} =
  ...

proc jmapClientFree*(handle: pointer)
    {.exportc: "jmap_client_free".} =
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
(`NI64` on 64-bit, `NI32` on 32-bit), so a single header would describe
two different field widths. Always use `cint` for 32-bit or explicit-width
types.

Convert `cstring` to `string` immediately on entry: `let s = $cParam`.
See String Handling in [memory-and-lifecycle.md](memory-and-lifecycle.md).


## Enum Handling

Nim enums default to the smallest fitting integer. C enums are `int`-sized,
so every enum whose ordinals cross the boundary carries
`{.size: sizeof(cint).}`. `JmapStatus` (Status Codes, below) is the
canonical case and the only one defined in full here.

Rules:
- `{.size: sizeof(cint).}` -- matches C `int` size
- Assign explicit ordinal values: the ordinal, not the identifier, is what
  a compiled consumer holds
- Ordinals are locked at the first release and grow additively. An existing
  ordinal is never renumbered or reused, because a consumer compiled
  against the old header keeps sending and comparing the old number
- **The Nim enum type is never itself exposed.** Its C twin is
  hand-written in `include/jmap_client.h` as a C-native
  `typedef enum { ... }`, and a CI consistency gate cross-checks the two,
  so the header stays readable C with no `nimbase.h` dependency while
  drift is caught at build time. Exported signatures still return `cint`,
  and a C enum is `int`-sized, so the ABI matches either way. Bare `cint`
  constants are not an acceptable substitute: they give the C compiler
  nothing to switch exhaustively over and nothing to name in a debugger
- Entity enums (mailbox role, sort key, …) project the same way, with an
  `_UNKNOWN` ordinal for the forward-compatibility arm plus a
  raw-identifier string getter, so a server value this build does not know
  is still legible to the consumer


## Error Codes and Per-Handle Error State

C has no `Result` types. Error handling projects to C as:
- **Rail errors** (`JmapError`): a `jmap_status` return code, with the
  diagnostic recorded on the handle the call was made on
- **Per-invocation method errors**: data in the response handle

Three error-reporting shapes are common in C ABIs: an integer status code
returned from every call; a thread-local last error fetched by a separate
call; and an error-struct out-parameter. This library uses the first plus
per-handle diagnostics -- the SQLite model. Thread-local last-error state
is forbidden: it is OpenSSL's `ERR_get_error`, whose cross-thread
contamination and forgotten-clear bugs are documented across every binding
ecosystem that consumed it.

### Status Codes

One status enum across the whole ABI, the C projection of
`JmapErrorKind` plus success. Ordinals are locked at the first release and
grow additively -- an existing ordinal is never renumbered or reused,
because already-compiled consumers compare against the old numbers.

```nim
type JmapStatus* {.size: sizeof(cint).} = enum
  jsOk = 0
  jsValidation = 1 ## client-supplied input was invalid
  jsTransport = 2 ## network / TLS / timeout / HTTP status
  jsRequest = 3 ## whole request rejected (RFC 7807)
  jsSession = 4 ## expected session capability absent
  jsMisuse = 5 ## caller bug: NULL argument, wrong handle, bad option type
  jsProtocol = 6 ## malformed or non-conforming server response
  jsMethod = 7 ## method-level error on the one-shot path
  jsSet = 8 ## /set error on the one-shot path
```

Enums cannot carry `{.exportc.}` (see [nim-ffi-reference.md](nim-ffi-reference.md)),
so the C `jmap_status` typedef is hand-written in `include/jmap_client.h`
and a CI consistency gate cross-checks it against this enum. Exported
signatures return `cint`; a C enum is `int`-sized, so the ABI matches.

### Projecting the Rail onto a Status

`statusOf` is exhaustive over `JmapErrorKind` -- a new arm on the Nim
rail is a compile error here, never a silent collapse to a generic code.

```nim
func statusOf(kind: JmapErrorKind): JmapStatus =
  case kind
  of jeValidation: jsValidation
  of jeTransport: jsTransport
  of jeRequest: jsRequest
  of jeSession: jsSession
  of jeMisuse: jsMisuse
  of jeProtocol: jsProtocol
  of jeMethod: jsMethod
  of jeSet: jsSet
```

### The Handle's Error Slot

Diagnostics live on the handle, never in a `{.threadvar.}` and never in
a global. The slot holds the projected status and the message rendered
once at record time -- the rendered string is the storage that backs the
`const char*` handed to C, so reads allocate nothing.

The slot lives on an **L5-owned wrapper object**, never on an L4 type.
`JmapClient` is `ref JmapClientObj`, and both that object type and its
fields are private to `internal/client.nim`, so `create(JmapClientObj)`
does not compile from `src/jmap_client.nim`. The C `jmap_client` is
therefore a wrapper holding the L4 ref plus the slot; that also keeps the
error slot out of the Nim-facing API, where errors travel on the `Result`
rail instead.

```nim
type ErrorSlot = object
  status: JmapStatus ## jsOk until the first failure on this handle
  message: string ## rendered at record time; backs jmap_errmsg's borrow

type JmapClientHandle = object
  ## What a C `jmap_client*` points at. L5-owned; minted with
  ## create(JmapClientHandle), never with the L4 constructors.
  client: JmapClient ## the L4 ref; dropping it closes the transport
  err: ErrorSlot ## most recent failure on THIS handle, never shared
```

`recordError` is the only writer. It overwrites unconditionally:
`sqlite3_errmsg` semantics are "the most recent call on this handle",
so there is no `clearLastError` to forget at the top of an operation
and no error queue to drain.

```nim
proc recordError(c: ptr JmapClientHandle, err: JmapError): cint =
  ## Records the diagnostic on the handle the call was made on and
  ## returns the status the C caller sees. JmapError.message is already
  ## a bounded, fully rendered projection, so recording cannot fail.
  let status = statusOf(err.kind)
  c[].err = ErrorSlot(status: status, message: err.message)
  cint(ord(status))
```

### Reading the Diagnostic

`jmap_errmsg` borrows from the handle's own storage: valid until the
next fallible call on that handle or `jmap_client_free`, whichever comes
first. It never allocates and never fails.

```nim
proc jmapErrmsg*(client: pointer): cstring
    {.exportc: "jmap_errmsg", dynlib, cdecl, raises: [].} =
  ## sqlite3_errmsg semantics -- see the invalidation window documented
  ## on this symbol in include/jmap_client.h.
  if client.isNil:
    return cstring"null client handle"
  let c = cast[ptr JmapClientHandle](client)
  if c[].err.status == jsOk:
    return cstring"no error"
  c[].err.message.cstring ## borrow: handle-owned, not caller-freed
```

`jmap_strerror` is static and stateless -- it reads no handle, is
callable before `jmap_init`, and is the only diagnostic available when a
call fails before a handle exists (`jmap_client_new` rejecting its
arguments).

```nim
func statusText(s: JmapStatus): cstring =
  ## Exhaustive over JmapStatus -- a new status is a compile error here.
  ## cstring literals are static storage in the generated C: never freed,
  ## safe to hand out forever.
  case s
  of jsOk: cstring"no error"
  of jsValidation: cstring"invalid argument"
  of jsTransport: cstring"transport failure"
  of jsRequest: cstring"request rejected by server"
  of jsSession: cstring"required session capability absent"
  of jsMisuse: cstring"API misuse"
  of jsProtocol: cstring"malformed server response"
  of jsMethod: cstring"method-level error"
  of jsSet: cstring"set-level error"

proc jmapStrerror*(code: cint): cstring
    {.exportc: "jmap_strerror", dynlib, cdecl, raises: [].} =
  ## Total over every cint: a newer header linked against an older
  ## library passes an ordinal this build has never heard of. Matching
  ## by ordinal avoids an int-to-enum conversion, which this project
  ## turns into a hard error via --warningAsError:AnyEnumConv
  ## (config.nims), whether or not the enum has holes.
  for s in JmapStatus:
    if cint(ord(s)) == code:
      return statusText(s)
  cstring"unknown status code"
```

### Forbidden

- `{.threadvar.}` error state, `jmap_last_error()`, `setLastError` /
  `clearLastError`, or any error queue. Fetch-the-error-afterwards designs
  make the diagnostic outlive the call that produced it and leak across
  threads and across unrelated calls.
- Failure signalled by NULL alone, by a negative sentinel, or by any
  side state the caller has to fetch separately. A sentinel folded into
  the answer is indistinguishable from a legitimate value at some future
  widening of the range, and it names no variant.
- Sharing a handle between threads while calls are in flight. Handles are
  confined to one thread at a time; that contract, not TLS, is what makes
  the error slot race-free.


## Per-Invocation Results via Response Handles

Method errors are **data within a successful response**, not return codes.
C consumers access them through response handle accessors:

```nim
proc jmapResponseInvocationIsError*(
    resp: pointer, idx: cint, outIsError: ptr cint
): cint {.exportc: "jmap_response_invocation_is_error", dynlib, cdecl, raises: [].} =
  # Status return + out-param -- never a -1 sentinel folded into the
  # answer, which would be unreadable from a boolean out-value.
  if resp.isNil or outIsError.isNil: return cint(ord(jsMisuse))
  let r = cast[ptr JmapResponseObj](resp)
  if idx < 0 or idx >= cint(r[].invocations.len): return cint(ord(jsMisuse))
  outIsError[] = if r[].invocations[idx].isErr: 1 else: 0
  return cint(ord(jsOk))
```

Per-invocation errors are not rail errors: they never reach the handle's
error slot and never become a `jmap_status`. They are read directly from
the response handle via accessor procs (count, isError, errorType). The
one-shot easy path is the exception -- it fails fast, so a method or set
error there arrives as `jsMethod` / `jsSet` on the rail with the detail
in `jmap_errmsg`.


## C Header

`include/jmap_client.h` is hand-curated and self-contained -- it never
includes `nimbase.h`, so consumers need no Nim installation on their
include path, and a CI gate cross-checks it against the `{.exportc.}`
inventory so the two cannot drift. Handle types are forward-declared
incomplete structs, not `void*` aliases, so the compiler keeps them apart
and `const` qualification means something:

```c
/* jmap_client.h -- standalone C header */
#ifndef JMAP_CLIENT_H
#define JMAP_CLIENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t jmap_bool;     /* NIM_BOOL: always 1 byte */

/* Opaque handles -- incomplete types, never defined here */
typedef struct jmap_client    jmap_client;
typedef struct jmap_transport jmap_transport;

/* Status codes -- ordinals locked at v1, additive growth only */
typedef enum {
  JMAP_OK           = 0,
  JMAP_E_VALIDATION = 1,
  JMAP_E_TRANSPORT  = 2,
  JMAP_E_REQUEST    = 3,
  JMAP_E_SESSION    = 4,
  JMAP_E_MISUSE     = 5,
  JMAP_E_PROTOCOL   = 6,
  JMAP_E_METHOD     = 7,
  JMAP_E_SET        = 8
} jmap_status;

/* Lifecycle -- jmap_init is required because the library is built
 * --app:lib --noMain, so nothing calls NimMain for the consumer. */
int  jmap_init(void);
void jmap_cleanup(void);

/* Client. transport == NULL selects the built-in transport; C has no
 * default arguments, so the selector is an explicit NULL. Every
 * fallible entry point returns jmap_status and writes its output
 * through an out-parameter -- never NULL-as-error. */
int  jmap_client_new(const char* session_url, const char* username,
                     const char* password, jmap_transport* transport,
                     jmap_client** out);
void jmap_client_free(jmap_client* client);

/* Error introspection.
 * jmap_strerror: static text for a code; reads no state.
 * jmap_errmsg:   diagnostic of the most recent failure on THIS handle,
 *                owned by the handle, valid until the next fallible call
 *                on it or jmap_client_free -- sqlite3_errmsg semantics.
 *                There is no process- or thread-wide last error. */
const char* jmap_strerror(int code);
const char* jmap_errmsg(const jmap_client* client);

/* ... remaining exports ... */

#ifdef __cplusplus
}
#endif

#endif /* JMAP_CLIENT_H */
```

If distributing `nimbase.h` alongside the library, C consumers add the
Nim `lib/` directory to their include path (`-I`).


## Further Reading

- `docs/design/17-L5-FFI-Principles.md` -- the C ABI binding design
- `docs/design/14-Nim-API-Principles.md` -- library-wide API principles
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide
