# nim-results 0.5.1 API Reference

## Core Types

```nim
type
  Result*[T, E] = object
    ## Stack-allocated discriminated union: Success(T) | Error(E)

  Opt*[T] = Result[T, void]
    ## Optional value — Result with no error payload

  ResultDefect* = object of Defect
    ## Raised when accessing value on err or error on ok (via get/value/[])

  ResultError*[E] = object of ValueError
    ## Raised by tryValue in exception bridge mode
    error*: E
```

`Result` is a value type. `T` is the success type, `E` is the error type.
Either `T` or `E` (or both) may be `void`.

## Constructors

### Typed constructors (work anywhere)

```nim
Result[int, string].ok(42)          # Result[int, string] with value 42
Result[int, string].err("failed")   # Result[int, string] with error
Result[void, string].ok()           # Result[void, string] success (no value)
Result[int, void].err()             # Result[int, void] error (no payload)
```

### Shorthand constructors (deduced from enclosing return type)

```nim
func doWork(): Result[int, string] =
  ok(42)          # deduced as Result[int, string].ok(42)
  err("failed")   # deduced as Result[int, string].err("failed")
```

**These only work inside a `func`/`proc` whose return type is `Result`.**
Outside such context, use the typed form.

### Assignment constructors (set existing var)

```nim
var r: Result[int, string]
r.ok(42)         # sets r to ok
r.err("failed")  # sets r to err
```

### Opt constructors

```nim
Opt[int].ok(42)       # == Opt.some(42)
Opt[int].err()        # == Opt.none(int)
Opt.some(42)          # alias for ok
Opt.none(int)         # alias for err()
```

## Predicates

```nim
template isOk*(self: Result): bool    # true if value is set
template isErr*(self: Result): bool   # true if error is set
template isSome*(self: Opt): bool # alias for isOk
template isNone*(self: Opt): bool # alias for isErr
```

## The `?` Prefix Operator

**PREFIX** (not postfix like Rust). If the Result is err, immediately returns
from the enclosing function with that error. If ok, unwraps to the value.

```nim
func processData(raw: string): JmapResult[Data] =
  let parsed = ? parseInput(raw)     # early return on error
  let validated = ? validate(parsed)  # early return on error
  ok(transform(validated))
```

The enclosing function's return type must be `Result[T, E]` where `E` matches
the error type. If error types differ, use `mapErr` BEFORE `?`:

```nim
func process(): JmapResult[Data] =
  # parseInput returns Result[Input, ParseError], not JmapResult
  let input = ? parseInput(raw).mapErr(toClientError)
  ok(input)
```

For `Opt[T]`, `?` works the same — returns `Opt.none` on error.

## Combinators

### Value transformation

```nim
func map*[T0: not void, E; T1: not void](self: Result[T0, E], f: proc(x: T0): T1): Result[T1, E]
  ## Transform success value. Error passes through unchanged.
  ## 4 overloads exist for void T0/T1 combinations — see llms-full.txt lines 522-588.

func flatMap*[T0: not void, E, T1](self: Result[T0, E], f: proc(x: T0): Result[T1, E]): Result[T1, E]
  ## Chain fallible operations (monadic bind).
  ## f must return the same error type E. Void-T0 overload also exists.
```

### Error transformation

```nim
func mapErr*[T; E0: not void, E1: not void](self: Result[T, E0], f: proc(x: E0): E1): Result[T, E1]
  ## Transform error value. Success passes through unchanged.
  ## 4 overloads exist for void E0/E1 combinations — see llms-full.txt lines 614-666.

func mapConvert*[T0: not void, E](self: Result[T0, E], T1: type): Result[T1, E]
  ## Convert value type using implicit conversion (T0 must convert to T1)

func mapConvertErr*[T, E0](self: Result[T, E0], E1: type): Result[T, E1]
  ## Convert error type using implicit conversion
```

### Filtering

```nim
func filter*[T, E](self: Result[T, E], callback: proc(x: T): Result[void, E]): Result[T, E]
  ## If ok and callback(value) returns err, return that error. Else return self.
  ## If already err, pass through unchanged.

func filter*[E](self: Result[void, E], callback: proc(): Result[void, E]): Result[void, E]
  ## Void-value variant. If ok and callback() returns err, return that error.

func filter*[T](self: Opt[T], callback: proc(x: T): bool): Opt[T]
  ## If some and callback(value) is false, convert to none.
```

**Project convention**: The library accepts `proc` callbacks (effects propagate via
`{.effectsOf: f.}`). This project uses `func` callbacks exclusively in domain logic —
all Layers 1-3 are pure. See CLAUDE.md.

### Flattening

```nim
func flatten*[T, E](self: Result[Result[T, E], E]): Result[T, E]
  ## Unwrap nested Result. If outer is err, result is err.
  ## If outer is ok, result is the inner Result.
```

### Boolean combinators

```nim
template `and`*[T0, E, T1](self: Result[T0, E], other: Result[T1, E]): Result[T1, E]
  ## If self is ok, return other. If self is err, return self's error.
  ## `other` is lazily evaluated.

template `or`*[T, E0, E1](self: Result[T, E0], other: Result[T, E1]): Result[T, E1]
  ## If self is ok, return self (converted). If self is err, return other.
  ## `other` is lazily evaluated.

template orErr*[T, E0, E1](self: Result[T, E0], error: E1): Result[T, E1]
  ## If self is ok, return self (converted). If self is err, return err(error).
```

## Safe Value Access

### `valueOr` — preferred (lazy, error access)

```nim
template valueOr*[T: not void, E](self: Result[T, E], def: untyped): T
  ## Return value if ok, else evaluate def.
  ## def is lazily evaluated. Inside def, `error` refers to the error value.

let name = result.valueOr: "default"
let name = result.valueOr:
  log("Error: " & error)  # `error` is the E value
  "fallback"
```

### `get` with default — eager evaluation

```nim
func get*[T, E](self: Result[T, E], otherwise: T): T
  ## Return value if ok, else return otherwise.
  ## otherwise is eagerly evaluated.

let name = result.get("default")
```

### `errorOr` — for error access with fallback

```nim
template errorOr*[T; E: not void](self: Result[T, E], def: untyped): E
  ## Return error if err, else evaluate def.
  ## Inside def, `value` refers to the success value.
```

## Dangerous Value Access (avoid)

```nim
func value*[T, E](self: Result[T, E]): T    # raises ResultDefect if err
func get*[T, E](self: Result[T, E]): T      # alias for value
template `[]`*[T, E](self: Result[T, E]): T # alias for value
func error*[T, E](self: Result[T, E]): E    # raises ResultDefect if ok
```

**These raise `ResultDefect` (a `Defect`, not `CatchableError`)** when called
on the wrong variant. Defects crash the process and are NOT caught by
`{.raises: [].}`. Use `valueOr`, `get(default)`, or `?` instead.

### Exception bridge (tryValue/tryGet)

```nim
func tryValue*[T, E](self: Result[T, E]): T  # raises ResultError[E] or exception
template tryGet*[T, E](self: Result[T, E]): T # alias for tryValue
```

If `E` is an `Exception` type or has a `toException` converter, raises that
exception. Otherwise raises `ResultError[E]`. Unlike `value`/`get`, this raises
`CatchableError` (not `Defect`), so the compiler WILL reject calls to `tryValue`
inside `{.raises: [].}` functions — unlike `value`/`get`, which raise `Defect` and
silently bypass the raises tracker.

## Conditional Execution

```nim
template isOkOr*[T, E](self: Result[T, E], body: untyped)
  ## Execute body only if result is err. Inside body, `error` is available.

template isErrOr*[T, E](self: Result[T, E], body: untyped)
  ## Execute body only if result is ok. Inside body, `value` is available.
```

## Conversion

```nim
func optValue*[T, E](self: Result[T, E]): Opt[T]
  ## Convert to Opt[T], discarding error info.

func optError*[T, E](self: Result[T, E]): Opt[E]
  ## Convert error to Opt[E], discarding value info.
```

## Utility

```nim
func containsValue*(self: Result, v: auto): bool  # isOk and value == v
func containsError*(self: Result, e: auto): bool  # isErr and error == e
func contains*(self: Opt, v: auto): bool           # isSome and value == v
func `$`*(self: Result): string                    # string representation
func `==`*(lhs, rhs: Result): bool                 # deep equality
```

## Collection Iterators

For batch processing of `seq[Result]` or `seq[Opt]` — e.g. parsing an array of
JMAP method responses where each can independently fail. For single-Result ROP
pipelines, prefer `?`, `valueOr`, or `map`.

```nim
iterator values*[T, E](self: Result[T, E]): T
  ## Yield the value if ok, nothing if err. Result as a 0-or-1 collection.

iterator errors*[T, E](self: Result[T, E]): E
  ## Yield the error if err, nothing if ok.

iterator items*[T](self: Opt[T]): T
  ## Yield the value if some, nothing if none. Opt as a 0-or-1 collection.
```

```nim
# Collect all successful parses from a batch, discarding errors
let accounts: seq[Account] =
  responses.mapIt(parseAccount(it)).mapIt(it.values.toSeq).concat
```

## Exception Wrapping

```nim
template catch*(body: typed): Result[type(body), ref CatchableError]
  ## Execute body, catching any CatchableError into Result.

template capture*[E: Exception](T: type, ex: ref E): Result[T, ref E]
  ## Wrap an existing exception ref into a Result.
```

## Opt[T] = Result[T, void]

`Opt` is just a type alias. All `Result` operations work on `Opt`:

```nim
let x: Opt[int] = Opt.some(42)
let y: Opt[int] = Opt.none(int)

doAssert x.isSome
doAssert y.isNone
doAssert x.get() == 42        # DANGER: raises Defect if none
doAssert x.get(0) == 42       # safe: returns 0 if none
let v = x.valueOr: 0          # safe: lazy default

# ? works with Opt too:
func findThing(): Opt[Thing] =
  let account = ? findAccount(id)  # returns none if not found
  Opt.some(account.thing)

# map/flatMap work:
let name = findAccount(id).map(proc(a: Account): string = a.name)
```
