# Testament Spec Reference

## File Structure

- Test files live in `tests/` directory
- File names start with `t` prefix: `tprimitives.nim`, `tidentifiers.nim`
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
pairs. All fields are optional.

### Action

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `action` | string | `"run"` | `"run"`: compile and run. `"compile"`: compile only. `"reject"`: must fail to compile. |

### Output Matching

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `output` | string | `""` | Expected stdout (exact match unless `outputsub` used) |
| `outputsub` | string | `""` | Expected stdout substring match |
| `sortoutput` | bool | `false` | Sort output lines before comparing |

### Exit and Error

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `exitcode` | int | `0` | Expected process exit code |
| `errormsg` | string | `""` | Expected error message (typically with `action: "reject"`) |
| `file` | string | `""` | Expected source file of error (reject action) |
| `line` | string | `""` | Expected line number of error (reject action) |
| `column` | string | `""` | Expected column of error (reject action) |

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
| `cmd` | string | (default nim cmd) | Custom compilation command. Supports `$file`, `$target` interpolation |
| `targets` | string | `"c"` | Space-separated backends: `"c"`, `"cpp"`, `"js"`, `"objc"` |
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
| `disabled` | string/bool | (none) | Skip on OS (`"win"`, `"bsd"`), arch (`"32bit"`, `"i386"`), CI (`"azure"`), or `true` for always |

### Advanced

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `valgrind` | bool/string | `false` | `true`: run with Valgrind. `"leaks"`: Valgrind without leak check. Linux 64-bit only. |
| `ccodecheck` | string | `""` | Assert this string appears in generated C code |

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
