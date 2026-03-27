# Common Mistakes with nim-results

## 1. Bare `.get()` / `.value()` / `[]` Without Default

**Detection**: Calling `.get()`, `.value()`, or `self[]` without a fallback.

**Wrong**:
```nim
let account = result.get()  # raises ResultDefect if err — CRASHES
let id = opt[]              # raises ResultDefect if none — CRASHES
```

**Right**:
```nim
let account = result.valueOr: return err(fallbackError)
let account = result.get(defaultAccount)
let account = ? result  # early return on error
```

**Why**: `get()`/`value()`/`[]` raise `ResultDefect` (a `Defect`), which is NOT
tracked by `{.raises: [].}` and will crash the process. The compiler will not
warn you. Always use `valueOr:`, `get(default)`, or `?`.

---

## 2. Using stdlib `Option[T]` Instead of `Opt[T]`

**Detection**: Importing `std/options` and using `Option[T]`, `some()`, `none()`.

**Wrong**:
```nim
import std/options
func findAccount(id: AccountId): Option[Account] =
  if found: some(account) else: none(Account)
```

**Right**:
```nim
import pkg/results
func findAccount(id: AccountId): Opt[Account] =
  if found: Opt.some(account) else: Opt.none(Account)
```

**Why**: This project uses `Opt[T]` (from nim-results) exclusively. `Opt` is
`Result[T, void]`, giving access to the full Result API (`?`, `map`, `flatMap`,
`valueOr`). stdlib `Option` has a different, incompatible API.

---

## 3. Postfix `?` (Rust-style)

**Detection**: Writing `result?` or `call()?` with `?` after the expression.

**Wrong**:
```nim
let session = client.discoverSession()?   # COMPILE ERROR
let id = parseAccountId(raw)?             # COMPILE ERROR
```

**Right**:
```nim
let session = ? client.discoverSession()  # PREFIX operator
let id = ? parseAccountId(raw)            # PREFIX operator
```

**Why**: In nim-results, `?` is a PREFIX template, not postfix like Rust.
It binds tightly: `? expr` is `(? expr)`.

---

## 4. `mapErr` After `?` Instead of Before

**Detection**: Calling `?` before converting the error type with `mapErr`.

**Wrong**:
```nim
func process(): JmapResult[Data] =
  let input = ? parseInput(raw)          # ParseError ≠ ClientError — COMPILE ERROR
  let input2 = (? parseInput(raw)).mapErr(toClientError)  # Wrong: ? already returned
```

**Right**:
```nim
func process(): JmapResult[Data] =
  let input = ? parseInput(raw).mapErr(toClientError)  # mapErr FIRST, then ?
```

**Why**: `?` checks the Result and returns immediately on error. If the error
type doesn't match the enclosing function's return type, it won't compile.
`mapErr` must convert the error type BEFORE `?` evaluates.

---

## 5. Shorthand `ok()`/`err()` Outside Deducible Context

**Detection**: Using bare `ok(value)` or `err(error)` where the return type
cannot be deduced.

**Wrong**:
```nim
let x = ok(42)  # COMPILE ERROR: can't deduce Result type
var results: seq[Result[int, string]]
results.add(ok(42))  # COMPILE ERROR: can't deduce
```

**Right**:
```nim
let x = Result[int, string].ok(42)
var results: seq[Result[int, string]]
results.add(Result[int, string].ok(42))
```

**Why**: The shorthand `ok()`/`err()` templates deduce the full Result type
from the enclosing function's return type. In other contexts (variable
declarations, seq operations), the type must be explicit.

---

## 6. Using `proc` Callbacks in the Functional Core

**Detection**: Passing a `proc` (not `func`) callback to `map`, `flatMap`, or
`mapErr` inside `func` context.

**Wrong**:
```nim
result.flatMap(proc(x: int): Result[string, Error] = ok($x))
# Inside a func, proc propagates side effects — compiler rejects
```

**Right**:
```nim
result.flatMap(func(x: int): Result[string, Error] = ok($x))
# func is compiler-enforced pure
```

**Why**: The library accepts `proc` callbacks (effects propagate via
`{.effectsOf: f.}`), but this project's functional core uses `func` exclusively.
Inside a `func` (noSideEffect), passing a `proc` callback would propagate side
effects, which the compiler rejects. Use `func` for callbacks in all domain logic.

---

## 7. `Result[T, string]` for Domain Errors

**Detection**: Using `string` as the error type for domain validation.

**Wrong**:
```nim
func parseAccountId(raw: string): Result[AccountId, string] =
  if raw.len == 0: err("must not be empty")
  else: ok(AccountId(raw))
```

**Right**:
```nim
func parseAccountId(raw: string): Result[AccountId, ValidationError] =
  if raw.len == 0: err(validationError("AccountId", "must not be empty", raw))
  else: ok(AccountId(raw))
```

**Why**: This project uses structured error types. `ValidationError` carries
`typeName`, `message`, and `value` fields, enabling callers to inspect errors
programmatically. `string` loses context and forces callers to parse error
messages. Use `mapErr` to lift `ValidationError` into `ClientError` at
boundaries.
