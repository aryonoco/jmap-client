# Export Pragmas, Type Mapping, and Error Codes

Patterns for declaring the C interface. Consult when adding a new exported
proc, error code, or modifying the C header.


## Export Pragmas

Every exported proc requires FOUR pragmas, and carries no `*`:

```nim
proc jmapClientNew(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new", dynlib, cdecl, raises: [].} =
```

| Pragma | Purpose | What happens without it |
|--------|---------|------------------------|
| `exportc: "jmap_name"` | Prevents Nim name mangling; sets the C symbol name | Symbol gets `fastcall`-mangled name, unusable from C |
| `dynlib` | Shared library export (`N_LIB_EXPORT` in generated C) | Symbol hidden on POSIX (`visibility("hidden")`) |
| `cdecl` | C calling convention | Default `nimcall` = `fastcall` -- wrong convention, corrupted args |
| `raises: []` | Compile-time guarantee no `CatchableError` escapes | Exception crossing FFI boundary crashes the process |

**No export marker.** A C-linkage symbol carries no `*`. `exportc` already
publishes the C name; `*` would additionally put the Nim-side identifier on
the module's Nim API, and the two are disjoint contracts with separate
snapshots. `tests/wire_contract/public-api.txt` holds the Nim surface and
`tests/wire_contract/c-header.txt` the C one; a starred export would leak
an FFI entry point into the first.

Additional conventions:
- Always `proc` (never `func`) -- FFI is inherently side-effectful
- Nim-side name: `camelCase` per `--styleCheck:error`
- C-side name: `jmap_snake_case` prefix for all symbols
- `exportc` accepts format strings: `exportc: "jmap_$1"` substitutes the
  Nim identifier name (only `$1` available; literal `$` as `$$`)


## Pragma Bundling

**Do not bundle.** Write all four pragmas inline on every export.
Neither a custom pragma nor a surrounding `{.push.}` is acceptable *as a
way to supply these four*, however well the compiler accepts them. (The
module-level `{.push raises: [].}` every source module carries is a
different thing and stays: it is the file's default effect wall, not a
substitute for the per-export pragma text.)

```nim
# WRONG -- compiles, links, and fails the header inventory gate.
{.pragma: api, dynlib, cdecl, raises: [].}

proc jmapClientNew(sessionUrl, username, password: cstring,
    transport: pointer, outClient: ptr pointer): cint
    {.exportc: "jmap_client_new", api.} =
  ...
```

`tests/lint/h18_c_header_inventory.nim` reads the pragma as text, from
`exportc: "` to the closing `.}`, and requires `dynlib`, `cdecl` and
`raises: []` to appear inside it. Reading the source rather than the
compiler's view is what lets one lint cover every `.nim` file under `src/`
without compiling each; the cost is that a bundle satisfies the compiler
and fails the gate.

A further reason to avoid `{.push.}` here: it affects type definitions too,
so pushing `exportc` or `dynlib` across one would attempt to export the
type as a C symbol.


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
  `typedef enum { ... }`, so the header stays readable C with no
  `nimbase.h` dependency. No gate compares the two ordinal lists
  symbol by symbol -- the header snapshot lint locks the C members and
  their ordinals so a change to either side has to be deliberate, and the
  type cross-check reduces a C enum to `i32`, which is all the ABI cares
  about. The correspondence is held by hand and pinned behaviourally by
  the C compliance suite -- for `jmap_status`, with a `_Static_assert` per
  ordinal and a real call that returns each one; for the entity and option
  enums, with a call carrying the value in or out. So a new arm means
  editing both lists and adding the compliance case that reaches it.
  Exported signatures still return `cint`, and a C enum is `int`-sized,
  so the ABI matches either way. Bare `cint` constants are not an
  acceptable substitute: they give the C compiler nothing to switch
  exhaustively over and nothing to name in a debugger
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

The type is module-private, like every L5 type: only the C symbol is
published, and `cint` is what crosses the boundary.

```nim
type JmapStatus {.size: sizeof(cint).} = enum
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
and kept in step with this enum by hand, under the snapshot lock and the
compliance assertions described in Enum Handling above. Exported
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
fields are private to `internal/client.nim`, so
`createShared(JmapClientObj)` does not compile from
`src/jmap_client.nim`. The C `jmap_client` is
therefore a wrapper holding the L4 ref plus the slot; that also keeps the
error slot out of the Nim-facing API, where errors travel on the `Result`
rail instead.

Every borrow a diagnostic reader hands out is rendered into that slot at
record time, so the slot carries one field per reader.

```nim
type ErrorSlot = object
  status: JmapStatus ## jsOk until the first failure on this handle
  message: string ## rendered at record time; backs jmap_errmsg's borrow
  wireErrorType: string ## "" unless the outcome carried a typed wire
                        ## error; backs jmap_errtype's borrow

type JmapClientHandle = object
  ## What a C `jmap_client*` points at. L5-owned; minted with
  ## createShared(JmapClientHandle), never with the L4 constructors.
  client: JmapClient ## the L4 ref; dropping it closes the transport
  err: ErrorSlot ## most recent failure on THIS handle, never shared
```

Every write to the slot assigns the whole `ErrorSlot`, never a field of
one, so no write can leave a stale `message` or `wireErrorType` beside a
fresh `status`. There are five writers and they divide by where the
diagnostic came from:

| Writer | Records |
|--------|---------|
| `recordError` | An outcome carried on the `JmapError` rail from L4 |
| `recordMisuse` | A caller bug L5 detects itself -- a NULL out-parameter, a wrong handle |
| `recordProtocolFault` | A response that decoded cleanly but breaks a structural guarantee the RFC places on its shape |
| `recordValidationFault` | An argument L5 can prove invalid before any L4 call, reported as the status the substrate's own seal would answer |
| `clearError` | Success -- the slot resets, so the reader never sees a diagnostic from an earlier call |

The three siblings of `recordError` exist because their messages are
authored in L5 rather than carried from the rail; each returns the
`jmap_status` its export hands straight back, so the one-error-rail rule
holds either way. A cached failure may also be replayed into the slot
verbatim — the lazy session's primary-account failure is — but that
copies a slot rather than adding a sixth shape.

Each writer overwrites unconditionally: `sqlite3_errmsg` semantics are
"the most recent call on this handle", so there is no `clearLastError`
for a caller to forget at the top of an operation and no error queue to
drain. `clearError` is internal and runs on the success path, not a
prologue anyone can skip.

```nim
proc recordError(c: ptr JmapClientHandle, err: JmapError): cint =
  ## Records the diagnostic on the handle the call was made on and
  ## returns the status the C caller sees. JmapError.message is already
  ## a bounded, fully rendered projection, so recording cannot fail.
  let status = statusOf(err.kind)
  c[].err = ErrorSlot(status: status, message: err.message,
                      wireErrorType: wireErrorTypeOf(err))
  cint(ord(status))
```

`wireErrorTypeOf` is exhaustive over `JmapErrorKind` for the same reason
`statusOf` is: it yields the wire `type` string for the two arms that
carry one and `""` for the rest, so a new arm is a compile error rather
than a silently absent type.

### Reading the Diagnostic

`jmap_errmsg` borrows from the handle's own storage: valid until the
next fallible call on that handle or `jmap_client_free`, whichever comes
first. It never allocates and never fails.

```nim
proc jmapErrmsg(client: pointer): cstring
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

`jmap_errtype` reads the same slot for code rather than for prose: the
wire `type` string of the last typed JMAP failure, carried through
unchanged so a vendor-defined type reaches C intact. It returns NULL for
every outcome that carried no typed error, and never the empty string, so
"no type" and "an empty type" cannot be confused. The status the failing
call returned is what says which vocabulary the string came from -- a
method-level error type or a `/set` refusal -- because the two overlap.

```nim
proc jmapErrtype(client: pointer): cstring
    {.exportc: "jmap_errtype", dynlib, cdecl, raises: [].} =
  ## Same borrow window as jmap_errmsg: the next fallible call on this
  ## handle replaces it.
  if client.isNil:
    return nil
  let c = cast[ptr JmapClientHandle](client)
  if c[].err.wireErrorType.len == 0:
    return nil
  c[].err.wireErrorType.cstring
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
  of jsValidation: cstring"invalid input"
  of jsTransport: cstring"transport failure"
  of jsRequest: cstring"request rejected by server"
  of jsSession: cstring"session capability absent"
  of jsMisuse: cstring"API misuse"
  of jsProtocol: cstring"malformed server response"
  of jsMethod: cstring"method-level error"
  of jsSet: cstring"set-level error"

proc jmapStrerror(code: cint): cstring
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
proc jmapResponseInvocationIsError(
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
error there arrives as `jsMethod` / `jsSet` on the rail, with the prose in
`jmap_errmsg` and the wire `type` string in `jmap_errtype`.


## C Header

**`include/jmap_client.h` is the live contract. Read it before writing
or reviewing an export; nothing here reproduces it.** It is hand-curated
and self-contained -- it never includes `nimbase.h`, so consumers need no
Nim installation on their include path. Handle types are forward-declared
incomplete structs, not `void*` aliases, so the compiler keeps them apart
and `const` qualification means something.

Its shape, as a reviewer's checklist:

- `extern "C"` guards, an include guard, and `<stddef.h>` / `<stdint.h>`
  only. The version macros (`JMAP_CLIENT_VERSION_MAJOR` and its siblings)
  sit near the top; `jmap_version()` is among the first declarations,
  with `jmap_strerror()` the other function callable before
  initialisation.
- A preamble stating the rules that hold across the whole API once --
  the initialisation call, status-plus-out-parameter, who owns a returned
  pointer, and handle confinement -- so no per-declaration comment
  repeats them.
- Opaque `typedef struct jmap_x jmap_x;` per handle, the struct never
  defined.
- A C-native `typedef enum` per enum that crosses the boundary.
- Every fallible entry point returning `jmap_status` with its output in an
  out-parameter, never NULL-as-error; a `_new` paired with a `_free`; read
  accessors returning `const` borrows.
- The invalidation window spelled out on every accessor whose borrow dies
  before its owning handle does.

Three gates hold the header:

| Gate | What it holds |
|------|---------------|
| `just lint-c-header` | The header's function names and the `{.exportc.}` inventory under `src/`, both directions, plus the four mandatory pragmas |
| `just lint-c-header-snapshot` | The header against `tests/wire_contract/c-header.txt` as an ordered sequence -- parameter types, enum members and ordinals, typedef order, version macros. `just snapshot-c-header` regenerates it for a deliberate change |
| `just lint-c-header-types` | Each hand-written declaration against the Nim signature it stands for, via the prototypes `nim c --header:` emits |

The third is not redundant. C linkage matches by name alone, so a header
that misstates a parameter type still compiles, links, and returns right
answers on the host that wrote it -- a `size_t` written as `int` is wrong
only on a 32-bit target, and no name inventory or self-snapshot can see
it.

If distributing `nimbase.h` alongside the library, C consumers add the
Nim `lib/` directory to their include path (`-I`).


## Further Reading

- `docs/design/17-L5-FFI-Principles.md` -- the C ABI binding design
- `docs/design/14-Nim-API-Principles.md` -- library-wide API principles
- `docs/background/nim-c-abi-guide.md` -- general Nim C ABI guide
