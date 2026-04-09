# Nim FFI Language Reference

Authoritative specification text extracted from the Nim 2.2 documentation.
Each section cites its source. Consult this to verify any FFI claim.

When these extracts are insufficient, read the full source files:
- `.nim-reference/doc/manual.md` (9000+ lines)
- `.nim-reference/doc/destructors.md`
- `.nim-reference/doc/mm.md`
- `.nim-reference/doc/backends.md`
- `.nim-reference/lib/nimbase.h`


## exportc Pragma

Source: `manual.md` lines 8788-8814

> The `exportc` pragma provides a means to export a type, a variable, or a
> procedure to C. Enums and constants can't be exported. The optional argument
> is a string containing the C identifier. If the argument is missing, the C
> name is the Nim identifier *exactly as spelled*.

The string literal passed to `exportc` can be a format string. Only `$1`
is available (the Nim identifier); a literal dollar sign must be written
as `$$`.

> If the symbol should also be exported to a dynamic library, the `dynlib`
> pragma should be used in addition to the `exportc` pragma.


## dynlib Pragma for Export

Source: `manual.md` lines 9016-9028

> With the `dynlib` pragma, a procedure can also be exported to a dynamic
> library. The pragma then has no argument and has to be used in conjunction
> with the `exportc` pragma.

```nim
proc exportme(): int {.cdecl, exportc, dynlib.}
```

> This is only useful if the program is compiled as a dynamic library via
> the `--app:lib` command-line option.


## Calling Conventions

Source: `manual.md` lines 2209-2271

`nimcall`:
> is the default convention used for a Nim **proc**. It is the same as
> `fastcall`, but only for C compilers that support `fastcall`.

`cdecl`:
> The cdecl convention means that a procedure shall use the same convention
> as the C compiler. Under Windows the generated C procedure is declared
> with the `__cdecl` keyword.

`closure`:
> is the default calling convention for a **procedural type** that lacks
> any pragma annotations. It indicates that the procedure has a hidden
> implicit parameter (an *environment*). Proc vars that have the calling
> convention `closure` take up two machine words: One for the proc pointer
> and another one for the pointer to implicitly passed environment.

> The default calling convention is `nimcall`, unless it is an inner proc.

> Most calling conventions exist only for the Windows 32-bit platform.

**Implication for FFI:** The default `nimcall` is `fastcall`, which is NOT
C-compatible. Exported procs MUST use `cdecl` explicitly.


## cstring Type

Source: `manual.md` lines 1449-1503

> The `cstring` type meaning `compatible string` is the native
> representation of a string for the compilation backend. For the C backend
> the `cstring` type represents a pointer to a zero-terminated char array
> compatible with the type `char*` in ANSI C.

> Even though the conversion is implicit, it is not *safe*: The garbage
> collector does not consider a `cstring` to be a root and may collect the
> underlying memory. For this reason, the implicit conversion will be removed
> in future releases of the Nim compiler.

> `cstring` literals shouldn't be modified.

> A `$` proc is defined for cstrings that returns a string.


## Reference and Pointer Types

Source: `manual.md` lines 2028-2126

> Nim distinguishes between `traced` and `untraced` references. Untraced
> references are also called *pointers*. Traced references point to objects
> of a garbage-collected heap, untraced references point to manually
> allocated objects or objects somewhere else in memory. Thus, untraced
> references are *unsafe*.

> Traced references are declared with the **ref** keyword, untraced
> references are declared with the **ptr** keyword. In general, a `ptr T`
> is implicitly convertible to the `pointer` type.

> To allocate a new traced object, the built-in procedure `new` has to be
> used. To deal with untraced memory, the procedures `alloc`, `dealloc` and
> `realloc` can be used.

> Dereferencing `nil` is an unrecoverable fatal runtime error (and not a
> panic).

**Implication for FFI:** Use `ptr T` (untraced) for opaque handles, never
`ref T` (traced). `ptr T` from `create(T)` has no ARC refcount header and
is not managed by the garbage collector.


## Raises Pragma

Source: `manual.md` lines 5359-5443

> An empty `raises` list (`raises: []`) means that no exception may be
> raised.

> Procs that are `importc`'ed are assumed to have `.raises: []`, unless
> explicitly declared otherwise.

> Exceptions inheriting from `system.Defect` are not tracked with the
> `.raises: []` exception tracking mechanism. This is more consistent with
> the built-in operations.

> The reason for this is that `DivByZeroDefect` inherits from `Defect` and
> with `--panics:on` Defects become unrecoverable errors.

**Implication for FFI:** `{.raises: [].}` guarantees no `CatchableError`
escapes, but Defects (`IndexDefect`, `NilAccessDefect`, `OverflowDefect`)
can still crash the process. Defensive input validation is mandatory.


## Push and Pop Pragmas

Source: `manual.md` lines 7658-7690

> The `push/pop` pragmas are very similar to the option directive, but are
> used to override the settings temporarily.

```nim
{.push checks: off.}
# compile this section without runtime checks
# ... some code ...
{.pop.}
```

**Caution for FFI:** `{.push.}` affects everything in scope, including
type definitions. Never push `exportc` or `dynlib` across type definitions.


## Custom Pragma for Libraries

Source: `manual.md` lines 8604-8616

```nim
when appType == "lib":
  {.pragma: rtl, exportc, dynlib, cdecl.}
else:
  {.pragma: rtl, importc, dynlib: "client.dll", cdecl.}

proc p*(a, b: int): int {.rtl.} =
  result = a + b
```

> In the example, a new pragma named `rtl` is introduced that either
> imports a symbol from a dynamic library or exports the symbol for
> dynamic library generation.


## =destroy Hook

Source: `destructors.md` lines 108-155

> A `=destroy` hook frees the object's associated memory and releases
> other associated resources. Variables are destroyed via this hook when
> they go out of scope or when the routine they were declared in is about
> to return.

> A `=destroy` is implicitly annotated with `.raises: []`; a destructor
> should not raise exceptions.

The general pattern:

```nim
proc `=destroy`(x: T) =
  # first check if 'x' was moved to somewhere else:
  if x.field != nil:
    freeResource(x.field)
```


## Scope-Based Destruction

Source: `destructors.md` lines 435-448

> The current implementation follows strategy (2). This means that
> resources are destroyed at the scope exit.

Rewrite rule:

```
var x: T; stmts
---------------             (destroy-var)
var x: T; try stmts
finally: `=destroy`(x)
```

**Implication for FFI:** A local Nim `string` backing a `cstring` is
destroyed at scope exit. The `cstring` becomes a dangling pointer.


## ARC vs ORC

Source: `mm.md` lines 21-53

> ORC is the default memory management strategy. It is a memory management
> mode primarily based on reference counting.

> The reference counting operations (= "RC ops") do not use atomic
> instructions and do not have to -- instead entire subgraphs are *moved*
> between threads.

> `--mm:arc` uses the same mechanism as `--mm:orc`, but it leaves out the
> cycle collector. Both ARC and ORC offer deterministic performance for
> hard realtime systems.

> Roughly speaking the memory for a variable is freed when it goes
> "out of scope".


## NimMain and NimDestroyGlobals

Source: `backends.md` lines 231-252

> The C targets require you to initialize Nim's internals, which is done
> calling a `NimMain` function.

> The name `NimMain` can be influenced via the `--nimMainPrefix:prefix`
> switch.

> When compiling to static or dynamic libraries, they don't call destructors
> of global variables as normal Nim programs would do. A C API
> `NimDestroyGlobals` is provided to call these global destructors.

**Init chain under ARC** (verified from compiler source `cgen.nim`):
`NimMain()` calls `PreMain()` (system init + module `DatInit` functions)
then `NimMainInner()` (module top-level code). No GC to initialise, no
stack scanning. Neither call is thread-safe. Calling `NimMain()` twice
re-runs all module top-level code, corrupting state.


## Name Mangling

Source: `backends.md` lines 237-240

> By default, the Nim compiler will mangle all the Nim symbols to avoid
> any name collision, so the most significant thing the `exportc` pragma
> does is maintain the Nim symbol name, or if specified, use an alternative
> symbol for the backend.


## String/cstring Interop

Source: `backends.md` lines 368-387

> Nim's reference counting mechanism is not aware of the C code, once the
> `gimme` proc has finished it can reclaim the memory of the `cstring`.

> Custom data types that are to be shared between Nim and the backend will
> need careful consideration of who controls who.


## nimbase.h: C Type Definitions

Source: `.nim-reference/lib/nimbase.h` lines 318-463

### Boolean

```c
/* C++ */  #define NIM_BOOL bool
/* C99 */  #define NIM_BOOL _Bool
/* else */ typedef unsigned char NIM_BOOL;

NIM_STATIC_ASSERT(sizeof(NIM_BOOL) == 1, "");  /* always 1 byte */
```

### Integer Types

With `<stdint.h>` (most platforms):

```c
typedef int8_t  NI8;    typedef uint8_t  NU8;
typedef int16_t NI16;   typedef uint16_t NU16;
typedef int32_t NI32;   typedef uint32_t NU32;
typedef int64_t NI64;   typedef uint64_t NU64;

/* NI/NU are pointer-sized (NIM_INTBITS): */
typedef NI64 NI;  /* on 64-bit */
typedef NU64 NU;
```

### Float Types

```c
typedef float  NF32;
typedef double NF64;
typedef double NF;
```

### String and Nil

```c
typedef char  NIM_CHAR;
typedef char* NCSTRING;

/* C++ */ #define NIM_NIL nullptr
/* C */  #define NIM_NIL ((void*)0)
```


## nimbase.h: Export Macros

Source: `.nim-reference/lib/nimbase.h` lines 161-226

```c
/* extern "C" guard */
#ifdef  __cplusplus
#  define NIM_EXTERNC extern "C"
#else
#  define NIM_EXTERNC
#endif

/* Windows */
#define N_LIB_EXPORT  NIM_EXTERNC __declspec(dllexport)
#define N_LIB_IMPORT  extern __declspec(dllimport)

/* POSIX (GCC) */
#define N_LIB_EXPORT  NIM_EXTERNC __attribute__((visibility("default")))
#define N_LIB_IMPORT  extern
#define N_LIB_PRIVATE __attribute__((visibility("hidden")))
```


## nimbase.h: Calling Convention Macros

Source: `.nim-reference/lib/nimbase.h` lines 167-230

```c
/* Windows */
#define N_CDECL(rettype, name)    rettype __cdecl name
#define N_FASTCALL(rettype, name) rettype __fastcall name
#define N_STDCALL(rettype, name)  rettype __stdcall name

/* POSIX (GCC) -- cdecl is a no-op, fastcall uses attribute */
#define N_CDECL(rettype, name)    rettype name
#define N_FASTCALL(rettype, name) __attribute__((fastcall)) rettype name
```

The Nim default `nimcall` maps to `N_NIMCALL` which is `fastcall` on
platforms that support it.


## nimbase.h: Thread-Local Storage

Source: `.nim-reference/lib/nimbase.h` lines 112-142

```c
/* MSVC/Borland */  #define NIM_THREADVAR __declspec(thread)
/* C11 */           #define NIM_THREADVAR _Thread_local
/* GCC */           #define NIM_THREADVAR __thread
/* C++11 */         #define NIM_THREAD_LOCAL thread_local
```

Nim's `{.threadvar.}` pragma compiles to `NIM_THREADVAR` in the generated
C code (verified from compiler source `ccgthreadvars.nim`). Uses
compiler-native TLS, works on foreign C threads under ARC without Nim
thread registration.
