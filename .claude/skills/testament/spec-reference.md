# Testament Spec Reference

## File Structure

- Test files live in `tests/` directory
- File names start with `t` prefix: `tprimitives.nim`, `tidentifiers.nim` (project convention; testament itself does not require this)
- Every test file may start with an optional `discard """..."""` spec block
- Code follows the spec block — use `doAssert` and `assert` for assertions
- **No `check`, `suite`, `test`, or `expect`** — those are unittest, not testament

## Minimal Test (no spec needed)

```nim
doAssert 1 + 1 == 2
```

Sane defaults apply: action is "run", exitcode is 0, no output matching.

## Spec Header Fields

The spec block is a `discard """..."""` at the top of the file with key-value
pairs. All fields are optional. Keys are case-insensitive and underscore-insensitive
(e.g. `errorMsg`, `errormsg`, and `error_msg` are equivalent).

### Action

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `action` | string | `"run"` | `"run"`: compile and run. `"compile"`: compile only. `"reject"`: must fail to compile. |

### Output Matching

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `output` | string | `""` | Expected stdout (exact match) |
| `outputsub` | string | `""` | Expected stdout substring match |
| `sortoutput` | bool | `false` | Sort output lines before comparing |

> **Note:** `output` and `outputsub` are mutually exclusive — they share
> internal storage and the last one set wins. `outputsub` additionally
> includes both compiler and test execution output for matching.

### Exit and Error

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `exitcode` | int | `0` | Expected process exit code |
| `errormsg` | string | `""` | Expected error message (typically with `action: "reject"`) |
| `file` | string | `""` | Expected source file of error (reject action). Requires `errormsg` or `nimout` before it. |
| `line` | int | `0` | Expected line number of error (reject action). Requires `errormsg` or `nimout` before it. |
| `column` | int | `0` | Expected column of error (reject action). Requires `errormsg` before it. |

### Compiler Output

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nimout` | string | `""` | Expected compiler stdout (lines matched in order, extras allowed between) |
| `nimoutFull` | bool | `false` | If true, nimout must match ALL compiler output, not just contain lines |

### Input

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `input` | string | `""` | Stdin to feed to the test |

### Compilation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cmd` | string | (default nim cmd) | Custom compilation command. Supports `$target`, `$options`, `$file`, `$filedir` interpolation. `$$` for literal `$`. |
| `targets` / `target` | string | `"c"` | Space-separated backends: `"c"`, `"cpp"`, `"js"`, `"objc"` |
| `matrix` | string | `""` | Semicolon-separated flag combinations, e.g. `"; -d:release; -d:danger"` |
| `timeout` | float | (none) | Max seconds to run (fractional supported) |
| `maxcodesize` | int | (none) | Max generated C code file size |

### Test Aggregation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `batchable` | bool | `true` | Can be included in megatest batch |
| `joinable` | bool | `true` | Can be joined with other tests |

### Skipping

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `disabled` | string/bool (multi) | (none) | Skip test conditionally. Can appear multiple times. See Disabled Values below. |

#### Disabled Values

| Category | Examples | Notes |
|----------|----------|-------|
| Boolean | `true`, `false`, `yes`, `no`, `on`, `off`, `1`, `0` | `true` disables unconditionally |
| OS | `"win"`, `"linux"`, `"bsd"`, `"osx"`, `"unix"`, `"posix"`, `"freebsd"` | |
| Endianness | `"littleendian"`, `"bigendian"` | |
| Word size | `"32bit"`, `"64bit"`, `"cpu8"`, `"cpu16"`, `"cpu32"`, `"cpu64"`, `"8bit"`, `"16bit"` | |
| CI | `"azure"` | `"travis"` and `"appveyor"` also accepted but deprecated |
| Platform names | Any `compiler/platform.OS` or `platform.CPU` name, e.g. `"i386"`, `"amd64"`, `"arm64"` | Fallback: checked against Nim's platform tables |

### Retry

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retries` | int | `0` | Number of retry attempts if the test fails |

### Advanced

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `valgrind` | bool/string | `false` | `true`: run with Valgrind. `"leaks"`: Valgrind without leak check. Linux 64-bit only. **Side-effects:** sets `joinable: false` and output matching to substring mode. |
| `ccodecheck` | string (multi) | `[]` | Assert this string appears in generated C code. Can appear multiple times; entries accumulate. |

## Implicit Behaviours

Several spec fields silently set other fields. Be aware of these when combining fields:

| Field Set | Side-effect |
|-----------|-------------|
| `errormsg` | Sets `action` to `"reject"` |
| `exitcode` | Sets `action` to `"run"` |
| `valgrind` | Sets `joinable: false` and output matching to substring mode |
| Inline `#[tt.Error ...]#` | Sets `action` to `"reject"` and `joinable: false` |

**Consequence:** if you write `action: "run"` alongside `errormsg:`, the action is
silently overwritten to `"reject"`. If you write `action: "reject"` alongside
`exitcode:`, the action is silently overwritten to `"run"`. The spec parser
processes fields top-to-bottom; the last field parsed wins.

## Ordering Constraints

The spec parser processes fields top-to-bottom. Some fields require others to precede them:

- `file` requires `errormsg` or `nimout` before it
- `line` requires `errormsg` or `nimout` before it
- `column` requires `errormsg` or `nimout` before it

If the ordering is wrong, testament reports a parse error.

## Variable Interpolation

### Message Interpolation

`errormsg`, `nimout`, and inline error messages support these variables:

| Variable | Expands to |
|----------|------------|
| `${/}` | Platform directory separator (`/` on Unix, `\` on Windows) |
| `$file` | Test filename without directory path |
| `$$` | Literal `$` |

### Cmd Interpolation

The `cmd` field supports these variables:

| Variable | Expands to |
|----------|------------|
| `$target` | Compilation target (e.g. `c`, `js`) |
| `$options` | Compiler options |
| `$file` | Full file path of the test |
| `$filedir` | Directory containing the test file |
| `$$` | Literal `$` |

## Inline Error Annotations

Testament supports inline error checking with `#[tt.Error ^ message ]#` comments
directly in test source code. This tests the line, column, kind, and message of
compiler diagnostics without a spec header.

```nim
{.warning: "watch out"} #[tt.Warning
         ^ watch out [User] ]#
```

Supported kinds: `Hint`, `Warning`, `Error`. Multiple messages per line are delimited
with `;`. An `Error` kind implicitly sets `action: "reject"`.

For full syntax and multi-message examples, see `llms-full.txt` lines 230-268.

## Examples

### Compile-Only Test

```nim
discard """
  action: "compile"
"""
# Verify that these types compile without error
type
  MyId = distinct string
```

### Reject Test (must fail to compile)

```nim
discard """
  action: "reject"
  errormsg: "type mismatch"
"""
let x: int = "not an int"
```

### Output Matching Test

```nim
discard """
  output: "hello world"
"""
echo "hello world"
```

### Matrix Test (multiple flag combinations)

```nim
discard """
  matrix: "; -d:release"
"""
doAssert sizeof(int) > 0
```

This runs the test twice: once with default flags, once with `-d:release`.
