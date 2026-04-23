# jmap-client

Cross-platform JMAP (RFC 8620/8621) client library in Nim. Designed for FFI use from C/C++


## CRITICAL: Git Commit Message Format

Git Commit messages MUST be modeled after the Linux kernel.

The subject line should use the subsystem/component: short description format, stay under 75 characters, and use imperative mood ("fix" not "fixed" or "fixes").

The body should be wrapped at ~75 columns, explain why the change is needed (not just what it does), and be separated from the subject by a blank line.

The following 3 lines MUST be included at the end of EVERY git message body:

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.7-opus

No other AI/LLM attribution in any other format should appear in the git message.

## Development Principles

**IMPORTANT**: All code MUST adhere to the following principles:

**Domain Modeling**
- Domain-Driven Design: code reads like the spec.
- Newtype everything that has meaning.
- Make illegal states unrepresentable.
- Make state transitions explicit in the type. Not `User` with a `status` field — three types or a sum type.
- One source of truth per fact. If two fields can disagree, one shouldn't exist.
- Booleans are a code smell.

**Boundaries**
- Functional core, imperative shell. Push effects to the edge; keep the middle pure.
- Parse once at the boundary; trust forever in the interior.
- Constructors are privileges, not rights. Smart constructors only; raw constructors private.
- Immutability by default. Mutation should be explicitly justified and local.
- Total functions. Defined for every input of the declared type.

**Signatures**
- Errors are part of the API. Name variants, never collapse to strings.
- Railway-oriented: errors flow through `Result`, not exceptions.
- Return types are documentation the compiler checks. Prefer rich return types over rich docstrings.
- Constructors that can fail return `Result`; constructors that can't, don't.
- Postel's law: accept the most general type, return the most specific.

**API ergonomics**
- Make the right thing easy and the wrong thing hard.
- DRY — but duplicated appearance is not duplicated knowledge.

## Development Environment

You are running in the  devcontainer. Tooling is managed by `mise.toml` - single source of truth.

## Commands

- `just` - Show all available commands
- `just build` - Build shared library
- `just test` - Run fast suite (skips slow files in `tests/testament_skip.txt`); agents should use this for validation and leave `just test-full` (runs everything) for the user.
- `just fmt` - Format all source files with nph
- `just fmt-check` - Verify formatting
- `just lint` - Run lint checks
- `just analyse` - Run nimalyzer static analysis
- `just ci` - Run full CI pipeline (reuse + fmt-check + lint + analyse + test)
- `just stalwart-up` — Start Stalwart JMAP server and seed test accounts
- `just stalwart-down` — Stop Stalwart
- `just stalwart-reset` — Tear down and recreate with fresh data
- `just test-integration` — Run live integration tests (requires Stalwart running)
- `just clean` - Remove build artifacts
- `just docs` - Generate HTML documentation

## Dependencies

One external dependency: `nim-results` (status-im/nim-results) for `Result[T, E]`,
`Opt[T]`, and the `?` operator. All other imports are from Nim's standard library
(`std/json`, `std/tables`, etc.).

## Compiler Flags

Defined in `jmap_client.nimble` and `config.nims`: `--mm:arc`, `strictDefs`, `threads:on`, `floatChecks:on`, `styleCheck:error`. Various `warningAsError`.
Never loosen compiler or analyzer's settings.

## Nim Reference

Access the Nim source code at /.nim-reference
- Standard Library: at /.nim-reference/lib
- Official Nim docs: /.nim-reference/doc

## Important Directories

- `docs/design/` — Architecture and design specifications
- `docs/rfcs/` — Authoritative text of various RFCs related to the project.
  Consult freely to validate your understanding of what an RFC actually stipulates.

- `src/jmap_client.nim` — Library entry point (C ABI exports, Layer 5)
- `src/jmap_client/types.nim` — Re-exports all Layer 1 modules
- `src/jmap_client/validation.nim` — `ValidationError` (plain object for Result error rail), borrow templates, charset constants
- `src/jmap_client/primitives.nim` — `Id`, `UnsignedInt`, `JmapInt`, `Date`, `UTCDate`, `MaxChanges`
- `src/jmap_client/identifiers.nim` — `AccountId`, `JmapState`, `MethodCallId`, `CreationId`
- `src/jmap_client/capabilities.nim` — `CapabilityKind`, `CoreCapabilities`, `ServerCapability`
- `src/jmap_client/session.nim` — `AccountCapabilityEntry`, `Account`, `UriTemplate`, `Session`
- `src/jmap_client/envelope.nim` — `Invocation`, `Request`, `Response`, `ResultReference`, `Referencable[T]`
- `src/jmap_client/framework.nim` — `PropertyName`, `FilterOperator`, `Filter[C]`, `Comparator`, `AddedItem`
- `src/jmap_client/errors.nim` — `TransportError`, `RequestError`, `ClientError`, `MethodError`, `SetError`
- `src/jmap_client/client.nim` — HTTP client wrapper (Only Layer 4 file)
- `src/jmap_client/mail` — RFC8621 JMAP Mail implementation
- `tests/` — Test modules (categories: `unit/`, `serde/`, `property/`, `compliance/`, `stress/`)

## Coding Conventions

- Use `const` and `let` bindings; `var` only when absolutely necessary and only locally
- Error handling via Railway-Oriented Programming (nim-results):
  - Smart constructors return `Result[T, ValidationError]` — no exceptions
  - Transport/request failures use `Result[T, ClientError]` (`JmapResult[T]` alias)
  - Method errors (`MethodError`) and set errors (`SetError`) are data within successful responses
  - All error types are plain objects carried on the Result error rail
  - The `?` operator provides early-return error propagation
- Use `Opt[T]` from nim-results for optional fields (not `std/options`); prefer `for val in opt:` over `if opt.isSome: opt.get()`
- Prefer expression-oriented style: if/case/block as expressions
- Prefer `collect` (std/sugar) for building new collections; `allIt`/`anyIt` for predicates
- **`func` is mandatory in L1–L3** (types, serde, protocol) — no `proc` permitted. `{.push raises: [], noSideEffect.}` at the top of each L1–L3 module enforces purity at compile time. Callback parameters use `{.noSideEffect, raises: [].}` on the proc type; `mixin` resolves pure at instantiation. `proc` only allowed in L4 (IO/transport) and L5 (C ABI exports)
- **Push pragmas on every source module** — L1–L3: `{.push raises: [], noSideEffect.}` (totality + purity); L4–L5: `{.push raises: [].}`
- **`{.experimental: "strictCaseObjects".}` in src/ only** — every `.nim` file under `src/` MUST have this pragma immediately after its `{.push raises: ...}` pragma. Applies to both debug and release builds via the source-level pragma (no compiler-flag dependency). Tests/ are exempt. Under strict:
  - Use `case x.kind of foo:` — NOT `if x.kind == foo:` — to read variant fields. Strict only proves discriminator values through `case`.
  - Use-site case arms must mirror the declaration's `of`/`else:` combinations exactly. Fields declared in the object's `else:` branch require a use-site `else:`. Split-of-arms (`of A: ... of B: ...`) are rejected when the declaration combines them (`of A, B: field: T`); within a combined arm, differentiate via inner `if x.kind == A:` (the outer combined `of` has already proved combined-arm membership).
  - Accessor funcs hide the discriminator. Expose discriminators as public fields (preferred) or use template accessors (limited to same-module callers because template expansion respects source-module visibility).
  - Nested case objects aren't tracked across layers. Extract the inner case into its own type and hold it as a field.
  - `.value` / `.error` / `.get()` on a Result panic on Err via `raiseResultDefect` — under `--panics:on` that's `rawQuit(1)`, catastrophic for the FFI boundary. In "shouldn't-happen" contexts (invariant-proved Ok), prefer `case x.isOk of true: x.unsafeValue of false: <default>` — strict-safe AND panic-free. In genuine error-handling contexts, use `valueOr: return err(...)` so the failure flows through the Result railway.
  - `.unsafeValue` / `.unsafeError` / `.unsafeGet` bypass `withAssertOk` — under strict they're only accepted inside a case that proves the discriminator (the `case x.isOk of true:` pattern above).
  - Do NOT call `.get()` / `.value()` on a `var`-lvalue. Nim picks the `var Result → var T` overload in nim-results, which strict cannot prove (compiler limitation: var params are excluded from let-location tracking — see `guards.nim:47-57` in the Nim compiler). Let-bind to an immutable local first: `let tmp = varExpr; tmp.get()`.

## C ABI

  - Export C ABI functions with `{.exportc: "jmap_name", dynlib, cdecl, raises: [].}` pragmas
  - Layer 5 C ABI pattern-matches on Result values to produce C error codes

## Comments

- Comments should explain _why_, never _what_. The _what_ belongs in the types.
- Comments and docstrings: British English spelling

## Nim Coding Rules

Detailed Nim patterns are in `.claude/rules/`:
- `nim-conventions.md` — error handling, immutability, expression style, naming
- `nim-type-safety.md` — distinct types, case objects, enums, smart constructors
- `nim-functional-core.md` — L1–L3 FP idioms: safe stdlib primitives, sum-type ADTs, `withValue`, set algebra, translation boundaries
- `nim-ffi-boundary.md` — C ABI exports, type mapping, memory ownership, error projection

## Static Analysis

- Never suppress or relax nimalyzer rules (e.g. `ruleOff: "complexity"`). Always restructure code to comply. To reduce complexity decompose into sub-helpers, extract field-group comparisons, use generics for shared logic.

## Workflow

- Run `just ci` before committing (runs reuse + fmt-check + lint + test)
- Use nph for formatting
