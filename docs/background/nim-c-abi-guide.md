# Building Nim Libraries with an Idiomatic C ABI

*Reference for Nim 2.2.x*

---

Nim compiles to C, which makes it uniquely well-suited among high-level languages for producing shared and static libraries that expose clean, idiomatic C APIs. A C consumer should be able to use your Nim library with nothing more than a `.so`/`.dll`/`.dylib`, a `.h` header, and standard C tooling -- no knowledge of Nim required.

This guide covers the full picture: compiler flags, pragma annotations, memory ownership, type design, error handling, runtime lifecycle, header generation, build integration, and the real-world gotchas that only surface in production.


## The Core Formula

Every Nim-to-C library project reduces to the same essential recipe:

```
nim c --app:lib --noMain --mm:arc -d:release -d:noSignalHandler --header:mylib.h src/mylib.nim
```

The pieces:

- **`--app:lib`** -- produce a shared library (`.so`, `.dll`, `.dylib`) instead of an executable. Use `--app:staticLib` for a `.a`/`.lib` archive (which implies `--noMain` automatically).
- **`--noMain`** -- suppress generation of the C `main()` entry point and platform init hooks. Without this flag, `--app:lib` auto-generates a `DllMain` (Windows) or `__attribute__((constructor))` function (POSIX) that calls `NimMain()` on library load. With `--noMain`, you control exactly when `NimMain()` runs via an exported init function. See the "Runtime Initialisation" section for details.
- **`--mm:arc`** -- select ARC (automatic reference counting) as the memory management strategy. See the dedicated section below for why this is the right choice for library work.
- **`-d:release`** -- enable optimisations and disable most runtime checks.
- **`-d:noSignalHandler`** -- prevent Nim from installing signal handlers at startup. See the "Signal Handling" section for details.
- **`--header:mylib.h`** -- emit a C header into nimcache containing declarations for all `{.exportc.}` symbols.

Every exported proc must carry four pragmas: `{.exportc, dynlib, cdecl, raises: [].}`. Miss any one and you get silent breakage, crashes, or undefined behaviour when called from C:

- `exportc` -- prevents Nim name mangling; exposes the symbol with a C-compatible name
- `dynlib` -- marks the symbol for shared library export (generates `__declspec(dllexport)` on Windows, `__attribute__((visibility("default")))` on POSIX); also requires `exportc` and auto-sets `cdecl` if no explicit calling convention is given
- `cdecl` -- sets the C calling convention (Nim's default is `nimcall`, which maps to `__fastcall`)
- `raises: []` -- compile-time guarantee that no `CatchableError` escapes the proc body

**Note on `raises: []` and Defects:** The `raises` pragma tracks only `CatchableError` subclasses. `Defect` subclasses (`IndexDefect`, `NilAccessDefect`, `OverflowDefect`, etc.) are explicitly excluded from tracking. With `--panics:on`, Defects abort the process immediately via `rawQuit(1)`. See the "Defects and `--panics:on`" section for implications.


## `--app:lib` vs `--noMain` Interaction

Three configurations exist, and the distinction matters:

**`--app:lib` alone** (without `--noMain`): Nim generates a `DllMain` on Windows or a POSIX `__attribute__((constructor))` function that calls `NimMain()` automatically when the shared library is loaded. Simpler, but the caller has no control over initialisation timing and cannot handle init failures.

**`--app:lib --noMain`** (recommended): No auto-init. You must export an `mylib_init()` function that calls `NimMain()`. The C consumer decides when to initialise. This is the standard pattern for C libraries.

**`--app:staticLib`**: Automatically implies `--noMain`. You do not need to specify both. You must export an init function.


## Why `--mm:arc` for C Libraries (Not ORC)

Nim 2.0 made ORC (ARC plus a cycle collector) the default memory management strategy, and Nim 2.2 continues with ORC as the default. ORC handles reference cycles automatically and is the right choice for general Nim application development, especially code using `async`.

For C library work, **`--mm:arc` is the better choice** for several reasons:

**Deterministic destruction.** ARC frees memory the instant a variable's reference count drops to zero. There is no cycle collector running on an adaptive threshold, no surprise collection pauses, and no non-deterministic timing. When your C caller invokes `mylib_destroy(ctx)`, the memory is freed *right then*. This is what C programmers expect.

**Smaller binary size.** ORC adds the cycle collector machinery -- the trial deletion algorithm, the list of potential cycle roots, the `=trace` hooks. For a C-facing library where you control the object graph and can guarantee no cycles (which is almost always the case in FFI code using `ptr` and `object` types rather than `ref`), this is dead weight.

**No threading subtlety.** ORC's cycle collector is not thread-safe. Only a single thread may perform cycle collection. ARC's reference counting, by contrast, operates per-value with no global collector state. This is simpler to reason about when C code calls into your library from arbitrary threads.

**No cycle leaks to worry about.** If you accidentally create a reference cycle under ARC, you get a memory leak -- which is detectable with tools like Valgrind or AddressSanitizer. Under ORC, cycles are *supposed* to be collected, but subtle issues with the adaptive threshold or custom types missing `=trace` hooks can produce hard-to-diagnose leaks that look like ORC bugs.

**When to use ORC instead.** If your library's *internal* implementation uses `async/await` (which creates reference cycles by design), you must use `--mm:orc`. If your internal data structures involve `ref` types with unavoidable cycles, ORC may be necessary. But idiomatic C-facing library code should avoid both patterns in its exported surface area.

**Build-specific vs shared flags.** Flags like `--mm:arc` and `-d:noSignalHandler` can go in `config.nims` (applied to all compilations including tests). Flags like `--app:lib` and `--noMain` should go in the build command or justfile, since the same project also builds tests and executables that must not be compiled as a library.


## The Pragma Toolkit

### `{.exportc.}`

Nim mangles all symbol names by default to avoid collisions. The `exportc` pragma overrides this, preserving the identifier name exactly as written in the generated C code. You can also specify a custom name:

```nim
proc mylib_version(): cint {.exportc: "mylib_version", dynlib, cdecl, raises: [].} =
  return 1
```

Format strings are supported: `{.exportc: "mylib_$1".}` substitutes the Nim identifier for `$1`. Literal dollar signs are escaped as `$$`.

The pragma works on procs, types, and global variables. **Enums and constants cannot be exported** -- they exist only at compile time in Nim. Expose them via getter functions or duplicate them in your C header.

### `{.cdecl.}`

Sets the C calling convention. Nim's default calling convention is `nimcall`, which maps to `N_NIMCALL` in the generated C code -- this uses `__fastcall` on compilers that support it. When called from C code that assumes standard C calling conventions (which is always the case for a C library consumer), `nimcall` produces incorrect behaviour: corrupted arguments, wrong return values, stack misalignment. Every exported proc needs `cdecl`. Every callback type that C code will invoke also needs `cdecl`.

### `{.dynlib.}` (Without Arguments -- For Exporting)

The `{.dynlib.}` pragma without arguments marks a symbol for shared library export. It generates `N_LIB_EXPORT` in the C output, which maps to:

- **Windows**: `__declspec(dllexport)`
- **POSIX (Linux, macOS)**: `__attribute__((visibility("default")))`

**This is NOT a no-op on POSIX.** The visibility attribute matters when the library is compiled with `-fvisibility=hidden` (a common hardening practice) or when using linker scripts. Without `{.dynlib.}`, symbols may be hidden.

**Two additional behaviours:**

1. `{.dynlib.}` **requires** `{.exportc.}` on the same symbol. The compiler emits an error if `dynlib` is used without `exportc`.
2. If no explicit calling convention is set, `{.dynlib.}` **automatically sets `cdecl`**. So `{.exportc, dynlib.}` implicitly gets `cdecl`, though being explicit is recommended for clarity.

### `{.raises: [].}`

Tells the Nim compiler: "this proc raises no `CatchableError`." The compiler enforces this statically. If a called function *can* raise, you must catch it within the proc body. This is critical because if a Nim exception propagates past an `{.exportc, cdecl.}` boundary into C code, the result is undefined behaviour: corrupted stack, resource leaks, crashes.

**Important:** `{.raises: [].}` does NOT track `Defect` subclasses. A proc annotated with `{.raises: [].}` can still raise `IndexDefect`, `NilAccessDefect`, `OverflowDefect`, etc. See the "Defects and `--panics:on`" section for the implications.

Procs marked `{.importc.}` are assumed to have `{.raises: [].}` by default unless explicitly annotated otherwise.

### The Custom Pragma and Push/Pop Patterns

Repeating four pragmas on every exported proc is error-prone. Two approaches help:

**Custom pragma bundle:** Define a pragma that bundles everything except `exportc` (since `exportc` needs a per-proc name argument that custom pragma bundles cannot carry):

```nim
{.pragma: api, dynlib, cdecl, raises: [].}

proc mylib_init(): cint {.exportc: "mylib_init", api.} =
  ## Returns 0 on success, non-zero on failure.
  ...

proc mylib_compute(x: cint, y: cint): cint {.exportc: "mylib_compute", api.} =
  return x + y
```

**Push/pop block:** Apply pragmas across a range of declarations. Each proc still gets its own `exportc`:

```nim
{.push dynlib, cdecl, raises: [].}

proc mylib_open(path: cstring): pointer {.exportc: "mylib_open".} =
  ...

proc mylib_close(handle: pointer) {.exportc: "mylib_close".} =
  ...

{.pop.}
```

**Caution:** `{.push.}` affects type definitions too (via `implicitPragmas`), not just procs. Do not push `exportc` or `dynlib` across type definitions unless you intend to export those types. Pushing `raises: []` across type definitions is harmless. Pushing `cdecl` across type definitions is harmless.

**Note:** Push/pop pragmas are NOT applied to symbols generated from generic instantiations.

### `{.emit.}`

Injects raw C code into the generated output. Use sparingly -- it bypasses Nim's type system. Section control (`/*TYPESECTION*/`, `/*VARSECTION*/`, `/*INCLUDESECTION*/`) lets you place code precisely:

```nim
{.emit: """/*INCLUDESECTION*/
#include <string.h>
""".}
```


## Type Mapping: Making C Consumers Feel at Home

### Primitive Types

Nim's `int` is pointer-sized (64-bit on 64-bit platforms), not 32-bit like C's `int`. Always use the `c*` type aliases from `system` for exported interfaces. These are defined in `lib/system/ctypes.nim`:

| Nim Type | C Equivalent | Definition |
|----------|-------------|------------|
| `cint` | `int` | Always `int32`. Not platform-dependent. |
| `cuint` | `unsigned int` | Always `uint32`. |
| `cshort` | `short` | Always `int16`. |
| `cushort` | `unsigned short` | Always `uint16`. |
| `clong` | `long` | `int32` on Windows; `int` (pointer-sized) on Unix (LP64). |
| `culong` | `unsigned long` | `uint32` on Windows; `uint` (pointer-sized) on Unix. |
| `clonglong` | `long long` | Always `int64`. |
| `culonglong` | `unsigned long long` | Always `uint64`. |
| `csize_t` | `size_t` | `uint` (pointer-sized unsigned). |
| `cfloat` | `float` | Always `float32`. Note: Nim's `float` is `float64`/`cdouble`. |
| `cdouble` | `double` | Always `float64`. |
| `cstring` | `char*` | Pointer to null-terminated string. |
| `pointer` | `void*` | Generic untyped pointer. |
| `ptr T` | `T*` | Typed pointer -- untracked by ARC. |
| `bool` | `NIM_BOOL` | `_Bool` (C99+), `bool` (C++), or `unsigned char` (C89). Always 1 byte (`nimbase.h` enforces this with a static assert). |

**Rule of thumb:** If a type appears in an exported proc's signature, it must be a `c*` type, a `ptr` type, or a plain `object` (not `ref`).

### Struct Layout

Nim `object` types map directly to C structs with fields in declaration order:

```nim
type
  MyPoint* {.exportc, bycopy.} = object
    x*: cfloat
    y*: cfloat
```

Generates the C equivalent:

```c
typedef struct {
    float x;
    float y;
} MyPoint;
```

Key pragmas for struct control:

- **`{.bycopy.}`** -- pass by value in function calls. Use for small structs (points, colours, rectangles) that C code will pass on the stack. A `{.byref.}` on a parameter overrides the type's `{.bycopy.}`.
- **`{.byref.}`** -- always pass by pointer. Use for large structs.
- **`{.packed.}`** -- generates `__attribute__((packed))`, disabling padding. Use for wire protocols and file formats.
- **`{.union.}`** -- generates a C `union` instead of a struct.

**Enum sizing:** Nim enums default to the smallest integer type that fits all values (often 1 byte). C enums are `int`-sized. The `{.size.}` pragma accepts 1, 2, 4, or 8 bytes. For C compatibility:

```nim
type
  MyError* {.exportc, size: sizeof(cint).} = enum
    MyErrorNone = 0
    MyErrorInvalidArg = 1
    MyErrorOutOfMemory = 2
    MyErrorIO = 3
```

### The Opaque Handle Pattern

This is the most important API design pattern for Nim-to-C libraries. The C consumer never sees your internal struct layout -- they receive an opaque handle (a pointer to a forward-declared struct) and interact with it exclusively through your API functions. This gives you complete freedom to change internal representations between library versions without breaking ABI compatibility.

```nim
# Internal Nim types -- never exposed to C
type
  ContextObj = object
    name: string          # Nim string, managed by ARC
    items: seq[int]       # Nim sequence, managed by ARC
    refCount: int         # Your own usage tracking if needed

  # The C-facing handle is a raw pointer
  Context* = ptr ContextObj

{.pragma: api, dynlib, cdecl, raises: [].}

# --- Lifecycle ---

proc mylib_context_create(name: cstring): Context {.exportc: "mylib_context_create", api.} =
  ## Creates a new context. Caller must eventually call mylib_context_destroy.
  ## Returns nil on failure.
  if name.isNil:
    return nil
  let ctx = create(ContextObj)  # alloc0 + zero-init via c_calloc
  ctx[] = ContextObj(
    name: $name,    # Convert cstring to Nim string (copies)
    items: @[],
    refCount: 1
  )
  return ctx

proc mylib_context_destroy(ctx: Context) {.exportc: "mylib_context_destroy", api.} =
  ## Frees a context created by mylib_context_create.
  ## Safe to call with nil.
  if ctx.isNil:
    return
  `=destroy`(ctx[])  # Run destructors on Nim fields (string, seq)
  dealloc(ctx)

# --- Operations ---

proc mylib_context_add_item(ctx: Context, value: cint): cint {.exportc: "mylib_context_add_item", api.} =
  ## Adds an item. Returns 0 on success.
  if ctx.isNil:
    return -1
  ctx.items.add(int(value))
  return 0

proc mylib_context_get_item(ctx: Context, index: cint, outValue: ptr cint): cint
    {.exportc: "mylib_context_get_item", api.} =
  ## Gets an item by index. Returns 0 on success, -1 on out-of-bounds.
  if ctx.isNil or outValue.isNil:
    return -1
  if index < 0 or index >= cint(ctx.items.len):
    return -1
  outValue[] = cint(ctx.items[index])
  return 0

proc mylib_context_count(ctx: Context): cint {.exportc: "mylib_context_count", api.} =
  ## Returns the number of items, or -1 if ctx is nil.
  if ctx.isNil:
    return -1
  return cint(ctx.items.len)

proc mylib_context_name(ctx: Context): cstring {.exportc: "mylib_context_name", api.} =
  ## Returns the context name. Pointer is valid until the context is destroyed.
  if ctx.isNil:
    return nil
  return cstring(ctx.name)
```

The corresponding C header declares:

```c
typedef struct ContextObj ContextObj;
typedef ContextObj* Context;

Context mylib_context_create(const char* name);
void    mylib_context_destroy(Context ctx);
int     mylib_context_add_item(Context ctx, int value);
int     mylib_context_get_item(Context ctx, int index, int* out_value);
int     mylib_context_count(Context ctx);
const char* mylib_context_name(Context ctx);
```

A C programmer sees a familiar create/use/destroy pattern with no Nim concepts leaking through.


## Memory Ownership at the Boundary

This is the area most likely to produce bugs. The core principle: **the FFI boundary is a bright line between managed and unmanaged memory.** On the Nim side, ARC manages lifetimes. On the C side, the programmer manages lifetimes manually. Your API must make ownership transfer unambiguous.

### Strings

Under `--mm:arc`, Nim's `string` is implemented as `NimStringV2` (defined in `lib/system/strs_v2.nim`):

```
Stack:  NimStringV2 { len: int, p: ptr NimStrPayload }
Heap:   NimStrPayload { cap: int, data: UncheckedArray[char] }
```

ARC tracks the `NimStringV2` value itself via compiler-inserted `=copy`/`=sink`/`=destroy` hooks. There is no explicit reference count field in the string payload -- ARC uses the compiler's knowledge of ownership to insert the appropriate lifecycle operations. When `p` is `nil`, the string is empty (len == 0). The `data` array is null-terminated.

A `string` is implicitly convertible to `cstring` (a `char*`), which returns a pointer to the `data` field of the heap payload. **This pointer is only valid as long as the Nim `string` is alive and unmodified.**

**Compile-time protection:** The `CStringConv` warning (which should be promoted to an error via `--warningAsError:CStringConv`) catches dangerous implicit `string` to `cstring` conversions at compile time. This is a critical safety net for library work.

```nim
proc mylib_get_name(ctx: Context): cstring {.exportc: "mylib_get_name", api.} =
  # SAFE: ctx.name outlives the function call, and the caller
  # only needs the pointer until the next API call or destroy.
  return cstring(ctx.name)
```

```nim
proc mylib_greet(name: cstring): cstring {.exportc: "mylib_greet", api.} =
  # DANGEROUS: the Nim string is a local variable.
  # After this function returns, ARC destroys it.
  # The returned cstring points to freed memory!
  let greeting = "Hello, " & $name
  return cstring(greeting)  # BUG: dangling pointer
```

For functions that need to return dynamically constructed strings, use one of these patterns:

**Pattern A: Caller-provided buffer (preferred)**

```nim
proc mylib_get_greeting(name: cstring, buf: cstring, bufLen: cint): cint
    {.exportc: "mylib_get_greeting", api.} =
  ## Writes greeting into buf. Returns required length (excluding null).
  ## If buf is nil or bufLen is too small, still returns required length.
  let greeting = "Hello, " & $name
  let needed = cint(greeting.len)
  if not buf.isNil and bufLen > needed:
    copyMem(buf, cstring(greeting), greeting.len + 1)
  return needed
```

**Pattern B: Library-allocated, caller-freed**

```nim
proc mylib_strdup(s: string): cstring =
  ## Internal helper: allocates a C string copy with alloc.
  let p = cast[cstring](alloc(s.len + 1))
  copyMem(p, cstring(s), s.len)
  cast[ptr char](cast[int](p) + s.len)[] = '\0'
  return p

proc mylib_get_greeting(name: cstring): cstring {.exportc: "mylib_get_greeting", api.} =
  ## Returns a newly allocated string. Caller must free with mylib_free.
  return mylib_strdup("Hello, " & $name)

proc mylib_free(p: pointer) {.exportc: "mylib_free", api.} =
  ## Frees memory allocated by any mylib_* function.
  if not p.isNil:
    dealloc(p)
```

### Sequences / Arrays

Nim `seq[T]` has no C equivalent. At the boundary, use pointer-plus-length:

```nim
proc mylib_get_results(ctx: Context, outData: ptr ptr cint,
                       outLen: ptr cint): cint
    {.exportc: "mylib_get_results", api.} =
  ## Fills outData with a pointer to an array and outLen with its length.
  ## Caller must free the array with mylib_free.
  if ctx.isNil or outData.isNil or outLen.isNil:
    return -1
  let items = ctx.items
  let buf = cast[ptr UncheckedArray[cint]](alloc(items.len * sizeof(cint)))
  for i in 0 ..< items.len:
    buf[i] = cint(items[i])
  outData[] = cast[ptr cint](buf)
  outLen[] = cint(items.len)
  return 0
```

### The Golden Rules

1. **Never return `cstring` from a Nim local.** The backing `string` dies at scope end.
2. **Never pass `ref T` across the boundary.** Use `ptr T` (unmanaged) exclusively. Under ARC, `ref T` has a hidden reference count header (`RefHeader`) and is tracked by compiler-inserted lifecycle operations. Passing it to C code bypasses this tracking entirely.
3. **Every alloc needs a documented free.** Provide `mylib_free()` and document which functions return memory that needs it.
4. **Validate every pointer argument.** C callers will pass `NULL`. Check every `ptr` and `cstring` parameter at the top of every exported function.
5. **Use `create(T)` / `dealloc` for opaque handles.** `create(T)` (defined in `lib/system/memalloc.nim`) calls `alloc0()` which is `c_calloc` -- it allocates zero-initialised memory and returns `ptr T`. This memory is untracked by ARC. Both `alloc`/`alloc0`/`dealloc` are always raw C allocator calls (`c_malloc`/`c_calloc`/`c_free`) regardless of GC mode -- they are never tracked by ARC. Do not use `new(T)` for FFI handles -- `new` returns `ref T` which is tracked by ARC and will be freed when ARC's lifecycle hooks determine the reference is dead.


## Error Handling: Exceptions Stop at the Border

Nim exceptions use `goto`-based unwinding under `--mm:arc` (or `setjmp`/`longjmp` under other GC modes). If one propagates past an `{.exportc, cdecl.}` boundary into C code, the behaviour is undefined. The `{.raises: [].}` annotation makes this a compile-time guarantee for `CatchableError` subclasses, not just a convention.

### Defects and `--panics:on`

**This section is critical for projects that use `--panics:on`.**

Nim's exception hierarchy has two branches:

```
Exception
  Defect          -- programmer errors (bugs), NOT tracked by {.raises: []}
    IndexDefect
    FieldDefect
    ObjectConversionDefect
    OverflowDefect
    DivByZeroDefect
    NilAccessDefect
    RangeDefect
    AssertionDefect
    ...
  CatchableError  -- recoverable errors, tracked by {.raises: []}
    ValueError
    IOError
    OSError
    ...
```

**`{.raises: [].}` does NOT prevent Defects.** A proc annotated with `{.raises: [].}` can still trigger `IndexDefect`, `NilAccessDefect`, `OverflowDefect`, etc. The Nim manual states this explicitly: "Exceptions inheriting from `system.Defect` are not tracked with the `.raises: []` exception tracking mechanism."

**With `--panics:on`** (recommended for this project): Defects call `rawQuit(1)`, which terminates the process immediately. There is no unwinding, no cleanup, no chance for `try/except` to catch them. This is by design -- Defects represent bugs in the library, not recoverable conditions.

**With `--panics:off`** (the default): Defects are raised as exceptions and CAN be caught with `try/except`, but `{.raises: [].}` still does not track them. This means a Defect could propagate into C code, causing undefined behaviour.

**Implications for library work:**

- A `{.raises: [].}` exported proc CAN still terminate the host process (with `--panics:on`) or cause undefined behaviour (with `--panics:off`) via a Defect.
- **Defensive coding is essential:** Validate all inputs (bounds checks, nil checks) BEFORE operations that could trigger Defects. Check array indices before indexing. Check pointers for nil before dereferencing. Check divisors before dividing.
- With `--panics:on`, a bug in the library kills the host application. This is the fail-fast philosophy: bugs should be found and fixed, not silently handled.

### Pattern 1: Integer Error Codes

The simplest approach. Return 0 for success, negative values for errors:

```nim
const
  MYLIB_OK* = cint(0)
  MYLIB_ERR_NULL* = cint(-1)
  MYLIB_ERR_BOUNDS* = cint(-2)
  MYLIB_ERR_IO* = cint(-3)
  MYLIB_ERR_UNKNOWN* = cint(-99)

template wrapErrors(body: untyped): cint =
  try:
    body
    MYLIB_OK
  except IOError:
    MYLIB_ERR_IO
  except CatchableError:
    MYLIB_ERR_UNKNOWN

proc mylib_load_file(ctx: Context, path: cstring): cint
    {.exportc: "mylib_load_file", api.} =
  if ctx.isNil or path.isNil:
    return MYLIB_ERR_NULL
  wrapErrors:
    ctx.data = readFile($path)
```

**Note:** Do not catch `IndexDefect` or other Defects in the `wrapErrors` template. With `--panics:on`, Defects abort before reaching the `except` clause. Without `--panics:on`, catching Defects masks bugs. Instead, validate bounds before indexing:

```nim
proc mylib_get_item(ctx: Context, index: cint, out: ptr cint): cint
    {.exportc: "mylib_get_item", api.} =
  if ctx.isNil or out.isNil:
    return MYLIB_ERR_NULL
  if index < 0 or index >= cint(ctx.items.len):
    return MYLIB_ERR_BOUNDS  # Defensive check BEFORE indexing
  out[] = cint(ctx.items[index])
  return MYLIB_OK
```

### Pattern 2: Thread-Local Error State

Mimics `errno` / `GetLastError()`. More informative than bare error codes:

```nim
var lastError {.threadvar.}: string
var lastErrorCode {.threadvar.}: cint

proc setError(code: cint, msg: string) =
  lastErrorCode = code
  lastError = msg

proc mylib_get_last_error(): cint {.exportc: "mylib_get_last_error", api.} =
  ## Returns the error code from the last failed operation.
  return lastErrorCode

proc mylib_get_last_error_message(): cstring {.exportc: "mylib_get_last_error_message", api.} =
  ## Returns the error message from the last failed operation.
  ## Pointer valid until the next mylib call on this thread.
  if lastError.len == 0:
    return nil
  return cstring(lastError)

proc mylib_parse(input: cstring, outValue: ptr cint): cint
    {.exportc: "mylib_parse", api.} =
  if input.isNil or outValue.isNil:
    setError(-1, "null argument")
    return -1
  try:
    outValue[] = cint(parseInt($input))
    return 0
  except ValueError as e:
    setError(-2, "parse error: " & e.msg)
    return -2
```

### Pattern 3: Error Struct (Out Parameter)

For APIs where error detail matters:

```nim
type
  MyLibError* {.exportc, bycopy.} = object
    code*: cint
    message*: array[256, char]  # Fixed-size buffer, no allocation

proc setErrorStruct(err: ptr MyLibError, code: cint, msg: string) =
  if err.isNil: return
  err.code = code
  let msgBytes = min(msg.len, 255)
  if msgBytes > 0:
    copyMem(addr err.message[0], cstring(msg), msgBytes)
  err.message[msgBytes] = '\0'
```


## Runtime Initialisation and Shutdown

### What NimMain Does Under ARC

`NimMain()` must be called exactly once before any other Nim code executes. Under `--mm:arc`, NimMain performs two steps:

1. **`PreMain()`** -- initialises global variables by calling `*DatInit000` and `*Init000` functions for each imported module in dependency order.
2. **`NimMainInner()`** -- runs the main module's top-level code (statements at module scope).

Under ARC there is no garbage collector to initialise -- no stack scanning setup, no heap management init, no GC thread. This makes initialisation fast and lightweight compared to older GC modes.

### The Init/Deinit Pattern

```nim
proc NimMain() {.importc.}

var initialised: bool = false

proc mylib_init(): cint {.exportc: "mylib_init", api.} =
  ## Initialise the library. Must be called before any other mylib function.
  ## Returns 0 on success. Safe to call multiple times.
  if initialised:
    return 0
  NimMain()
  initialised = true
  return 0

proc mylib_deinit() {.exportc: "mylib_deinit", api.} =
  ## Clean up library resources. Call when done with the library.
  if not initialised:
    return
  # Clean up any global state here
  initialised = false
```

For thread-safe initialisation (if your library may be loaded from multiple threads simultaneously):

```nim
import std/atomics

var initFlag: Atomic[bool]

proc mylib_init(): cint {.exportc: "mylib_init", api.} =
  if not initFlag.exchange(true):
    NimMain()
  return 0
```

### Multiple Libraries in One Process

If two Nim libraries coexist, each needs a unique initialisation function. The `--nimMainPrefix:MyLib` flag renames the internal symbols:

```
nim c --app:lib --noMain --mm:arc --nimMainPrefix:MyLib src/mylib.nim
```

This prefixes: `NimMain`, `PreMain`, `PreMainInner`, `NimMainInner`, `NimMainModule`, and `NimDestroyGlobals`. Module-level init functions (`*Init000`, `*DatInit000`) use mangled module names that are already unique per library -- they do not need prefixing.

Then in your Nim code:

```nim
proc MyLibNimMain() {.importc.}

proc mylib_init(): cint {.exportc: "mylib_init", api.} =
  MyLibNimMain()
  return 0
```

### Cleanup Limitations

`NimDestroyGlobals()` (or `MyLibNimDestroyGlobals()` with `--nimMainPrefix`) calls destructors on global variables. However, Nim has no mechanism to fully deallocate its runtime when a library is unloaded. A `mylib_deinit()` function should call this, but complete cleanup is not guaranteed. For most practical purposes, this only matters if your library is loaded and unloaded repeatedly in a long-running process.


## Signal Handling

By default, Nim registers signal handlers at runtime startup (in `lib/system/excpt.nim`) for the following signals:

| Signal | Purpose |
|--------|---------|
| `SIGINT` | Interrupt (Ctrl+C) |
| `SIGSEGV` | Segmentation fault (nil pointer access) |
| `SIGABRT` | Abnormal termination |
| `SIGFPE` | Floating-point exception (divide by zero) |
| `SIGILL` | Illegal instruction |
| `SIGBUS` | Bus error (platform-dependent; not on all systems) |
| `SIGPIPE` | Broken pipe (ignored by default in modern Nim via `SIG_IGN`, not handled) |

**For library work, this is problematic.** A library should never install signal handlers -- the host application controls signal handling. Use `-d:noSignalHandler` to suppress all signal handler registration. This define prevents the entire signal handler infrastructure from being compiled.


## Header Generation

### The `--header` Flag

Nim's `--header:filename.h` flag generates a C header containing all `{.exportc.}` symbols plus the `NimMain()` declaration (as `N_CDECL(void, NimMain)(void)`). The output lands in `nimcache` and depends on `nimbase.h` (Nim's base C header defining macros like `N_CDECL`, `N_LIB_IMPORT`, `N_LIB_EXPORT`, `NIM_BOOL`, etc.).

Type visibility rules in the generated header:

- Types passed **by pointer** in exported procs -> forward declarations only (`typedef struct Foo Foo;`)
- Types passed **by value** (with `{.bycopy.}`) -> full struct definitions
- Types not referenced in any exported proc -> omitted entirely

This means opaque handle types get forward declarations automatically (which is what you want), while value types like `MyPoint` get full definitions (also what you want).

The generated header also includes thread-local storage declarations (via `generateThreadLocalStorage()` in the compiler).

**Known limitation:** Types marked `{.exportc, byref.}` may not appear in the generated header even when used in exported procs. Large exported structs only passed by pointer may need a dummy by-value proc to force the full definition into the header.

### Manual Headers (Recommended for Production)

For libraries intended for public consumption, **write and maintain the C header by hand**. The auto-generated header has Nim-specific macros, lacks `const` annotations, and doesn't wrap in `extern "C"` for C++ consumers. A clean manual header looks like:

```c
/* mylib.h -- Public C API for mylib */
#ifndef MYLIB_H
#define MYLIB_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* Version */
#define MYLIB_VERSION_MAJOR 1
#define MYLIB_VERSION_MINOR 0

/* Error codes */
#define MYLIB_OK            0
#define MYLIB_ERR_NULL     -1
#define MYLIB_ERR_BOUNDS   -2
#define MYLIB_ERR_IO       -3

/* Opaque handle */
typedef struct ContextObj ContextObj;
typedef ContextObj* mylib_context_t;

/* Value types */
typedef struct {
    float x;
    float y;
} mylib_point_t;

/* Lifecycle */
int  mylib_init(void);
void mylib_deinit(void);

/* Context */
mylib_context_t mylib_context_create(const char* name);
void            mylib_context_destroy(mylib_context_t ctx);
int             mylib_context_add_item(mylib_context_t ctx, int value);
int             mylib_context_get_item(mylib_context_t ctx, int index, int* out_value);
int             mylib_context_count(mylib_context_t ctx);
const char*     mylib_context_name(mylib_context_t ctx);

/* Error info */
int         mylib_get_last_error(void);
const char* mylib_get_last_error_message(void);

/* Memory */
void mylib_free(void* ptr);

#ifdef __cplusplus
}
#endif

#endif /* MYLIB_H */
```


## Callbacks: C Code Calling Back into Nim

When C code needs to invoke Nim functions (event handlers, comparators, iterators), use callback function pointers with the `cdecl` convention:

```nim
type
  MyCallback* = proc(value: cint, userData: pointer): cint {.cdecl.}

proc mylib_set_callback(ctx: Context, cb: MyCallback, userData: pointer): cint
    {.exportc: "mylib_set_callback", api.} =
  if ctx.isNil:
    return -1
  ctx.callback = cb
  ctx.callbackData = userData
  return 0
```

**Critical rule:** If the C library invokes the callback from a thread that Nim did not create, you have a problem under the old `refc` GC (which required `setupForeignThreadGc()`). Under `--mm:arc`, this is a non-issue -- ARC has no thread-local GC state. This is another reason ARC is preferred for library work.

The callback itself should never let exceptions escape:

```nim
proc myNimCallback(value: cint, userData: pointer): cint {.cdecl.} =
  try:
    # Do Nim things
    return 0
  except CatchableError:
    return -1
```

**Note on `--panics:on`:** The `try/except CatchableError` pattern does NOT catch Defects. If the callback triggers a Defect (e.g., index out of bounds), the process aborts with `--panics:on`. Validate all inputs defensively.

**Note on `{.push raises: [].}`:** The `raises` pragma on a `proc` type parameter does not propagate from a module-level `{.push raises: [].}`. Callback types require explicit `{.raises: [].}` annotation: `proc(value: cint): cint {.cdecl, raises: [].}`.


## Building: Shared, Static, and Cross-Platform

### Shared Libraries

```bash
nim c --app:lib --noMain --mm:arc -d:release -d:noSignalHandler -o:libmylib.so src/mylib.nim
```

Platform output names:

| Platform | Output | Notes |
|----------|--------|-------|
| Linux | `libmylib.so` | Set SONAME manually: `--passL:"-Wl,-soname,libmylib.so.1"` |
| macOS | `libmylib.dylib` | Set install_name: `--passL:"-Wl,-install_name,@rpath/libmylib.dylib"` |
| Windows | `mylib.dll` | Symbols need `{.dynlib.}` for `__declspec(dllexport)` |

### Static Libraries

```bash
nim c --app:staticLib --mm:arc -d:release -d:noSignalHandler -o:libmylib.a src/mylib.nim
```

Note: `--app:staticLib` implies `--noMain` -- you do not need to specify both.

**Major caveat:** Linking two Nim static libraries into one binary produces multiple-definition errors for internal symbols like `PreMainInner`, `PreMain`, and runtime helpers. The `--nimMainPrefix` flag renames `NimMain`, `PreMain`, `PreMainInner`, `NimMainInner`, `NimMainModule`, and `NimDestroyGlobals`. Module-level init functions already use mangled module names and do not collide. The remaining collision risk is from Nim runtime internals that are duplicated in each static library. **Use shared libraries when multiple Nim libraries must coexist.**

Additionally, `{.exportc.}` symbols in static libraries may be generated with `__attribute__((visibility("hidden")))`, making them invisible to the linker. Work around this by adding `{.dynlib.}` to force `__attribute__((visibility("default")))`, or use `--passC:"-fvisibility=default"`.

### Cross-Compilation and Portable C

For distributing to targets where Nim is not installed, generate portable C source files:

```bash
nim c --compileOnly --genScript --nimcache:build/csources --mm:arc --noMain src/mylib.nim
```

This produces a `nimcache` directory with `.c` files and a `compile_mylib.sh` script. Transfer these to the target machine and compile with any C99 compiler -- no Nim installation required.

### CMake Integration

The simplest approach treats Nim's output as a pre-built artifact:

```cmake
# CMakeLists.txt
find_program(NIM_COMPILER nim REQUIRED)

add_custom_command(
  OUTPUT ${CMAKE_BINARY_DIR}/libmylib.a
  COMMAND ${NIM_COMPILER} c
    --app:staticLib --mm:arc -d:release -d:noSignalHandler
    --nimcache:${CMAKE_BINARY_DIR}/nimcache
    -o:${CMAKE_BINARY_DIR}/libmylib.a
    ${CMAKE_SOURCE_DIR}/src/mylib.nim
  DEPENDS ${CMAKE_SOURCE_DIR}/src/mylib.nim
  COMMENT "Compiling Nim library"
)

add_custom_target(nim_lib ALL DEPENDS ${CMAKE_BINARY_DIR}/libmylib.a)

add_library(mylib STATIC IMPORTED)
set_target_properties(mylib PROPERTIES IMPORTED_LOCATION ${CMAKE_BINARY_DIR}/libmylib.a)
add_dependencies(mylib nim_lib)

target_link_libraries(myapp PRIVATE mylib dl)  # dl needed on Linux
```

### Makefile Integration

```makefile
NIM       := nim
NIMFLAGS  := --app:lib --noMain --mm:arc -d:release -d:noSignalHandler

ifeq ($(OS),Windows_NT)
  LIBEXT := .dll
else
  UNAME := $(shell uname)
  ifeq ($(UNAME),Darwin)
    LIBEXT := .dylib
  else
    LIBEXT := .so
  endif
endif

libmylib$(LIBEXT): src/mylib.nim
	$(NIM) c $(NIMFLAGS) --out:$@ $<

.PHONY: clean
clean:
	rm -f libmylib$(LIBEXT)
	rm -rf nimcache
```

### Nimble Configuration

Nimble lacks a native `--app:lib` build mode. Use a custom task:

```nim
# mylib.nimble
version       = "1.0.0"
author        = "You"
description   = "A Nim library with C ABI"
license       = "MIT"

task buildLib, "Build shared library":
  exec "nim c --app:lib --noMain --mm:arc -d:release -d:noSignalHandler -o:libmylib.so src/mylib.nim"

task buildStatic, "Build static library":
  exec "nim c --app:staticLib --mm:arc -d:release -d:noSignalHandler -o:libmylib.a src/mylib.nim"
```


## A Complete Minimal Example

Here is a self-contained example of a Nim library that exposes an idiomatic C API for a simple key-value store.

### `src/kvstore.nim`

```nim
## kvstore -- A simple in-memory key-value store with C ABI.

import std/tables

{.pragma: api, dynlib, cdecl, raises: [].}

# --- Internal types ---

type
  KVStoreObj = object
    data: Table[string, string]

  KVStore* = ptr KVStoreObj

# --- Runtime init ---

proc NimMain() {.importc.}
var inited: bool

proc kvstore_init(): cint {.exportc: "kvstore_init", api.} =
  if not inited:
    NimMain()
    inited = true
  return 0

# --- Lifecycle ---

proc kvstore_create(): KVStore {.exportc: "kvstore_create", api.} =
  let store = create(KVStoreObj)
  store[] = KVStoreObj(data: initTable[string, string]())
  return store

proc kvstore_destroy(store: KVStore) {.exportc: "kvstore_destroy", api.} =
  if store.isNil: return
  `=destroy`(store[])
  dealloc(store)

# --- Operations ---

proc kvstore_set(store: KVStore, key: cstring, value: cstring): cint
    {.exportc: "kvstore_set", api.} =
  if store.isNil or key.isNil or value.isNil:
    return -1
  try:
    store.data[$key] = $value
    return 0
  except CatchableError:
    return -99

proc kvstore_get(store: KVStore, key: cstring): cstring
    {.exportc: "kvstore_get", api.} =
  ## Returns the value, or nil if not found. Pointer valid until next set/delete
  ## on the same key.
  if store.isNil or key.isNil:
    return nil
  try:
    let k = $key
    if k in store.data:
      return cstring(store.data[k])
    return nil
  except CatchableError:
    return nil

proc kvstore_delete(store: KVStore, key: cstring): cint
    {.exportc: "kvstore_delete", api.} =
  if store.isNil or key.isNil:
    return -1
  try:
    let k = $key
    if k in store.data:
      store.data.del(k)
    return 0
  except CatchableError:
    return -99

proc kvstore_count(store: KVStore): cint {.exportc: "kvstore_count", api.} =
  if store.isNil: return 0
  return cint(store.data.len)

# --- Memory ---

proc kvstore_free(p: pointer) {.exportc: "kvstore_free", api.} =
  if not p.isNil: dealloc(p)
```

### Build

```bash
nim c --app:lib --noMain --mm:arc -d:release -d:noSignalHandler --header:kvstore.h -o:libkvstore.so src/kvstore.nim
```

### `example.c` -- A C consumer

```c
#include <stdio.h>
#include <assert.h>

/* In production, use a manually maintained header */
typedef struct KVStoreObj KVStoreObj;
typedef KVStoreObj* KVStore;

extern int         kvstore_init(void);
extern KVStore     kvstore_create(void);
extern void        kvstore_destroy(KVStore store);
extern int         kvstore_set(KVStore store, const char* key, const char* value);
extern const char* kvstore_get(KVStore store, const char* key);
extern int         kvstore_delete(KVStore store, const char* key);
extern int         kvstore_count(KVStore store);

int main(void) {
    kvstore_init();

    KVStore db = kvstore_create();
    assert(db != NULL);

    kvstore_set(db, "language", "Nim");
    kvstore_set(db, "version", "2.2");
    kvstore_set(db, "backend", "C");

    printf("Count: %d\n", kvstore_count(db));
    printf("language = %s\n", kvstore_get(db, "language"));
    printf("version  = %s\n", kvstore_get(db, "version"));

    kvstore_delete(db, "backend");
    printf("After delete, count: %d\n", kvstore_count(db));
    printf("backend  = %s\n", kvstore_get(db, "backend") ? kvstore_get(db, "backend") : "(nil)");

    kvstore_destroy(db);
    printf("Done.\n");
    return 0;
}
```

### Compile and run

```bash
gcc -o example example.c -L. -lkvstore -Wl,-rpath,.
./example
```


## Platform-Specific Gotchas

### Windows

- **`DllMain` restrictions.** With `--noMain`, Nim does not generate a `DllMain`. Do not call `NimMain()` from your own `DllMain` -- this can deadlock due to the Windows loader lock. Instead, expose `mylib_init()` and require callers to invoke it after `LoadLibrary`.
- **`--tlsEmulation`** controls how `{.threadvar.}` is implemented. When off (the default), native TLS is used (`__declspec(thread)` on MSVC, `__thread` on GCC). When on, all thread-local variables are collected into a struct accessed via a helper function. TLS emulation is only enabled automatically for Boehm GC (which cannot scan native TLS). Test with it on and off if you encounter DLL loading issues on older Windows.
- **MinGW runtime DLLs** (libgcc, libwinpthread) must be distributed alongside your DLL or statically linked with `--passL:"-static"`.
- **Import libraries.** For MSVC consumers, you may need a `.lib` import library. Generate one from the `.dll` using `lib /def:mylib.def /out:mylib.lib`.

### Linux

- **SONAME.** Nim does not set this automatically. Pass `--passL:"-Wl,-soname,libmylib.so.1"` and create the appropriate symlinks (`libmylib.so -> libmylib.so.1 -> libmylib.so.1.0.0`).
- **`-ldl` for static libraries.** When linking a Nim static library into a C program on Linux, you usually need `-ldl` for `dlopen` functionality.
- **rpath.** Users need `LD_LIBRARY_PATH` or you need `-Wl,-rpath,$ORIGIN` for the library to be found at runtime.

### macOS

- **`install_name`.** macOS dylibs encode their install path. Use `--passL:"-Wl,-install_name,@rpath/libmylib.dylib"` for relocatable libraries.
- **Framework bundles** require manual setup -- Nim does not generate `.framework` directories.
- **Apple Silicon / Universal binaries.** Compile separately for x86_64 and arm64, then combine with `lipo`.


## Thread-Local Variables

The `{.threadvar.}` pragma maps to platform-specific thread-local storage:

| Platform | C Mapping |
|----------|-----------|
| GCC / Clang (POSIX) | `__thread` |
| MSVC / Borland (Windows) | `__declspec(thread)` |
| C11+ | `_Thread_local` |
| C++ | `thread_local` |

When `--tlsEmulation:on` is set (and `--threads:on` is enabled), all `{.threadvar.}` variables are instead collected into a `struct NimThreadVars` and accessed via a `GetThreadLocalVars()` helper function. This mode is automatic for Boehm GC but otherwise off by default.


## ABI Stability

**Nim does not guarantee ABI stability between compiler versions.** Name mangling for internal symbols, object layouts for Nim-internal types, and runtime internals can change between releases.

What this means in practice:

- **Your exported API is stable** -- you control the symbol names with `{.exportc.}`, the struct layouts with `{.exportc, bycopy.}`, and the function signatures. These don't change when you update the Nim compiler, because you defined them explicitly.
- **Internal Nim runtime symbols are unstable** -- `NimMain`, `PreMain`, and internal type metadata can change. Callers should never access these directly beyond the documented `NimMain()` call.
- **Don't mix Nim compiler versions.** A library compiled with one Nim version and another with a different version may have incompatible runtime internals. Build all Nim libraries in a project with the same compiler version.
- **The `nimrtl` shared runtime** allows sharing GC-managed types between Nim DLLs, but its threading support is untested and likely broken. Avoid it for new projects.

The `-d:useMalloc` flag routes all allocations through C's `malloc`/`free`, which is useful for debugging with Valgrind or AddressSanitizer (which understand these allocators natively).


## Checklist: Before You Ship

1. **Every exported proc** has `{.exportc: "prefix_name", dynlib, cdecl, raises: [].}`.
2. **`NimMain()` is called** before any other Nim code, via an exported `mylib_init()`.
3. **No Nim `CatchableError` exceptions** cross the FFI boundary. The `raises: []` pragma enforces this at compile time.
4. **Defects are understood.** `{.raises: [].}` does NOT prevent Defects. With `--panics:on`, Defects abort the process. Validate all inputs defensively.
5. **No `ref T`** in any exported signature. Use `ptr T` or opaque handles.
6. **No `string` or `seq`** in any exported signature. Use `cstring`, `ptr T`, and `cint` for lengths.
7. **Memory ownership is documented** for every function that allocates. Provide `mylib_free()`.
8. **All pointer arguments** are checked for nil at function entry.
9. **All exported symbols** use a consistent library prefix (`mylib_`).
10. **The header file** wraps in `extern "C"` for C++ consumers and uses standard C types.
11. **`-d:noSignalHandler`** prevents signal handler conflicts. Suppresses handlers for: SIGINT, SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS, SIGPIPE.
12. **`--warningAsError:CStringConv`** catches dangerous implicit `string` to `cstring` conversions at compile time.
13. **Test from C.** Compile a C program that links your library and exercises the API. This catches issues that Nim-to-Nim testing won't find.
14. **Test with sanitizers.** Build with `-d:useMalloc --passC:"-fsanitize=address"` and run your C test suite.
