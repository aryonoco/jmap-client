# Architecture Revision: Idiomatic Nim Migration

The five-layer architecture (L1 Types, L2 Serialisation, L3 Protocol Logic,
L4 Transport, L5 C ABI), the distinct domain types, and the error type
hierarchy are all retained. This document specifies the changes required to
bring the existing Layers 1–3 from strict FP-enforced Nim to idiomatic Nim.

The core principle of the revision: push strictness **outward** to Layer 5
(the C ABI boundary) rather than **inward** through every module. Layers 1–4
use normal Nim exceptions and standard library idioms. Layer 5 catches all
exceptions with `try/except` and converts them to C-compatible error codes,
enforced by `{.raises: [].}`.

Background: `docs/background/architecture-revision-conversation.md`

---

## 1. Compiler Configuration

### Remove from `config.nims`

- `system.switch("experimental", "strictFuncs")` (line 31)
- `system.switch("experimental", "strictNotNil")` (lines 35–36 and the
  `nimsuggest` guard)
- `system.switch("path", ... & "/vendor/nim-results")` (line 10)
- Comments referencing `strictCaseObjects`, vendored nim-results patches
  (lines 17–21); update `Uninit`/`UnsafeSetLen` comment (lines 52–58) to
  remove references to `initResultErr` and `{.requiresInit.}` workarounds

### Remove from `jmap_client.nimble`

- `strictFuncs`, `strictNotNil`, `strictCaseObjects` experimental flags
  (lines 24–28)

### Keep

| Setting | Reason |
|---------|--------|
| `mm:arc` | Required for FFI shared library |
| `strictDefs` | Generally useful; forces explicit initialisation |
| `threads:on` | Threading support |
| `floatChecks:on` | Float overflow/underflow detection |
| `styleCheck:error` | Naming consistency |
| `warningAsError: UnusedImport, Deprecated, CStringConv, EnumConv, HoleEnumConv, ProveInit` | Standard quality warnings |
| `warningAsError: Uninit, UnsafeSetLen` | Catches unsafe zero-initialisation and unsafe `setLen` on managed types |
| `hintAsError: DuplicateModuleImport` | Import hygiene |

---

## 2. Remove nim-results Dependency

The `Result[T, E]`, `Opt[T]`, and `?` operator from nim-results are replaced
by Nim's native error handling (exceptions) and `std/options`.

### Actions

- Delete `vendor/nim-results/` directory.
- Remove `requires "results == 0.5.1"` from `jmap_client.nimble`.
- Remove `import results` from all 14 src files and all test files that
  import it.
- Replace `Opt[T]` (79 uses across src) with `Option[T]` from `std/options`.
  - `Opt.some(x)` becomes `some(x)`
  - `Opt.none(T)` becomes `none(T)`
  - `.isSome` / `.isNone` / `.get()` remain the same (std/options provides
    these)
  - `.valueOr:` (nim-results template) has no std/options equivalent —
    replace with `if x.isSome: x.get() else: fallback`
- Remove `JmapResult[T]` alias from `types.nim`.
- Remove `initResultErr` helper from `serde.nim` and its 13 call sites in
  `serde_envelope.nim` and `methods.nim`.
- Remove all `Result[` return types (~93 uses). Smart constructors that
  returned `Result[T, ValidationError]` now raise `ValidationError` on
  failure and return `T` directly on success. See §7.

---

## 3. Remove `{.push raises: [].}` from Layers 1–4

Remove the `{.push raises: [].}` pragma (currently at line 4) from all 17
src modules **except** `src/jmap_client.nim` (the Layer 5 entry point).
Remove from all test files.

Layer 5 retains `{.push raises: [].}` — every `{.exportc, cdecl.}` proc
catches exceptions via `try/except` and converts them to C error codes.
The compiler enforces that no exception escapes.

---

## 4. Remove `{.experimental: "strictCaseObjects".}`

Remove the per-module `{.experimental: "strictCaseObjects".}` pragma
(currently at line 5) from all 16 src files that have it.

Standard Nim still protects case objects: discriminator reassignment to a
different branch is a compile error, and accessing the wrong branch raises
`FieldDefect` at runtime.

---

## 5. Remove `{.requiresInit.}` from Distinct Types

Remove `{.requiresInit.}` from all distinct types:

- `primitives.nim`: `Id`, `UnsignedInt`, `JmapInt`, `Date`, `UTCDate`,
  `MaxChanges`
- `identifiers.nim`: `AccountId`, `JmapState`, `MethodCallId`, `CreationId`
- `framework.nim`: `PropertyName`, `PatchObject`
- `session.nim`: `UriTemplate`

Smart constructors still enforce domain constraints at construction time.
The change is that `var x: Id` now compiles (producing an empty string)
rather than being a compile error. This eliminates:

- The `*Core` tuple-packing workarounds in serde code
- The `initResultErr` helper (workaround for nim-results + requiresInit)
- The `rawProperty`/`rawMethodCallId`/`rawId` private-field workarounds
  in `Comparator`, `Invocation`, and `AddedItem` (Pattern A from
  `00-architecture.md` §6a) — fields can use the distinct type directly

---

## 6. Switch `func` to `proc`

Change all `func` definitions in src/ to `proc`. This is a mechanical
replacement.

This eliminates:

- All 36 `{.cast(noSideEffect).}:` blocks across the serde files — these
  existed solely because `std/json` operations (allocation, `JsonNode`
  mutation) trigger side-effect violations under `strictFuncs`
- The `jStr`, `jInt`, `jBool`, `jObj`, `jArr` wrapper functions in
  `serde.nim` — these wrapped `%`, `newJObject()`, `newJArray()` in
  `{.cast(noSideEffect).}:` blocks; replace their call sites with the
  stdlib functions directly
- Borrow templates in `validation.nim` (`defineStringDistinctOps`,
  `defineIntDistinctOps`): change `func` to `proc` in template bodies

Purity discipline (no global state mutation, no I/O in L1–L3) is maintained
by convention and code review, not by compiler enforcement.

---

## 7. Error Types as Exceptions

### Construction errors

`ValidationError` in `validation.nim` becomes an exception:

```nim
type ValidationError* = object of CatchableError
  typeName*: string
  value*: string
```

The `message` field is inherited from `CatchableError`. Smart constructors
(e.g., `parseId`, `parseAccountId`, `parseUnsignedInt`) change from
returning `Result[T, ValidationError]` to raising `ValidationError` on
invalid input and returning `T` directly on success.

### Transport and request errors

`ClientError`, `TransportError`, and `RequestError` in `errors.nim` become
exceptions (inherit from `CatchableError`). These are raised by Layer 4
transport code and caught by Layer 5 C ABI procs.

### Method and set errors — remain as data

`MethodError` and `SetError` are **not** exceptions. They are data within
successful JMAP responses — the HTTP request succeeded, but individual
method calls or set items report errors as response fields. They remain
plain objects, returned as fields in `GetResponse`, `SetResponse`, etc.

---

## 8. Idiomatic `std/json` Usage

### Required fields

Replace `node{"key"}` + nil check + kind check (the current 5–6 line
pattern) with `node["key"]` for required fields. If the field is missing
or has the wrong type, Nim raises `KeyError` or `JsonKindError` — this is
now desirable, as exceptions propagate naturally.

### Optional fields

For genuinely optional fields (where absent/null is valid), use
`node.hasKey("key")` before access, or keep `node{"key"}` with a nil check.

### Helpers to revise or remove

- `checkJsonKind` template in `serde.nim`: remove (its purpose was to
  return `err(...)` on wrong kind; exceptions handle this now)
- `collectExtras` in `serde.nim`: change return type from `Opt[JsonNode]`
  to `Option[JsonNode]`
- `parseError` helper in `serde.nim`: change to raise `ValidationError`
  instead of returning one

### `to(T)` macro

Where appropriate, use `node.to(T)` from `std/json` for straightforward
object deserialisation. This replaces manual field-by-field extraction for
simple types. Types with custom wire formats (e.g., `Invocation` as a
3-element JSON array, `Referencable[T]` with `#`-prefixed keys) still
require manual serialisation.

---

## 9. Supporting Files

These files contain conventions that reference the removed patterns and
must be updated to reflect the new approach:

- `CLAUDE.md` — Update "Functional Programming Conventions" (remove ROP,
  `?` operator, `Opt[T]`, per-module `raises: []` and `strictCaseObjects`
  references), "Dependencies" (remove nim-results), and "Compiler Flags"
  sections.
- `.claude/rules/nim-conventions.md` — Rewrite module boilerplate (no
  `{.push raises: [].}`, no `import results`), error handling (exceptions
  not ROP), and purity (`proc` not `func`) sections.
- `.claude/rules/nim-type-safety.md` — Remove `{.requiresInit.}`,
  `strictCaseObjects`, and `strictNotNil` references.
- `.claude/rules/nim-ffi-boundary.md` — Update L5 pattern to show
  `try/except` catching exceptions and converting to C error codes.

The existing design documents (`00-architecture.md` through
`03-layer-3-design.md`) are **not** modified — they remain as historical
records of the original design decisions.

---

## 10. Test Infrastructure

- `tests/massertions.nim` — Rewrite assertion templates. `assertOk(expr)`
  becomes a direct evaluation (success = no exception). `assertErr(expr)`
  becomes `doAssertRaises(ValidationError): expr`. `assertErrFields`
  catches the exception and inspects its fields.
- All test files importing `results` — remove the import, replace `Opt`
  with `Option`, replace `Result`-based assertions with exception-based
  assertions.
- Property-based test generators in `tests/mproperty.nim` — update
  generators that produce `Result` values.

---

## What Does Not Change

- The 5-layer architecture (L1–L5) and module structure
- The distinct types (`Id`, `AccountId`, `JmapState`, etc.) and their
  smart constructors (which still validate inputs)
- The domain type hierarchy (`Invocation`, `Request`, `Response`,
  `Filter[C]`, `Comparator`, `PatchObject`, etc.)
- The error type hierarchy (`MethodError`, `SetError`, `RequestError`,
  `TransportError`) — only their base class changes
- The entity registration framework (`registerJmapEntity`,
  `registerQueryableEntity`)
- The `Referencable[T]` variant type for result references
- The `--mm:arc` memory management strategy
- The Layer 5 C ABI design (opaque handles, per-object free, error codes)
