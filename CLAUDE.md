# jmap-client

Cross-platform JMAP (RFC 8620/8621) client library in Nim. Designed for FFI use from C/C++ via `--mm:arc` and `{.exportc, dynlib, cdecl, raises: [].}`.

## CRITICAL: NO AI ATTRIBUTION

**DO NOT** mention AI, LLM, Claude, Claude Code, Anthropic, "generated", "assisted", or any similar reference **anywhere** — not in code, comments, commit messages, docstrings, PR descriptions, or any other artifact. No `Co-Authored-By`, no `Generated with`, no `AI-assisted`, nothing.

## Development Environment

This project uses a devcontainer. Tool versions are managed by mise — `mise.toml` is the single source of truth.

## Commands

- `just` - Show all available commands
- `just build` - Build shared library
- `just test` - Run test suite
- `just fmt` - Format all source files with nph
- `just fmt-check` - Verify formatting (CI-friendly)
- `just lint` - Run lint checks
- `just analyse` - Run nimalyzer static analysis
- `just ci` - Run full CI pipeline (reuse + fmt-check + lint + analyse + test)
- `just clean` - Remove build artifacts
- `just docs` - Generate HTML documentation
- `just versions` - Show tool versions

## Dependencies

No external dependencies. All imports are from Nim's standard library (`std/options`, `std/json`, `std/tables`, etc.).

## Compiler Flags

Defined in `jmap_client.nimble` and `config.nims`: `--mm:arc`, `strictDefs`, `threads:on`, `floatChecks:on`, `styleCheck:error`. Various `warningAsError` settings for quality enforcement. See `.claude/rules/nim-type-safety.md` for implications.

## Project Structure

Architecture: 5 layers (see `docs/00architecture-options.md`). Layer 1 detailed design in `docs/layer-1-design.md`.

- `src/jmap_client.nim` — Library entry point (C ABI exports, Layer 5)
- `src/jmap_client/types.nim` — Re-exports all Layer 1 modules
- `src/jmap_client/validation.nim` — `ValidationError` (exception), borrow templates, charset constants
- `src/jmap_client/primitives.nim` — `Id`, `UnsignedInt`, `JmapInt`, `Date`, `UTCDate`
- `src/jmap_client/identifiers.nim` — `AccountId`, `JmapState`, `MethodCallId`, `CreationId`
- `src/jmap_client/capabilities.nim` — `CapabilityKind`, `CoreCapabilities`, `ServerCapability`
- `src/jmap_client/session.nim` — `Account`, `UriTemplate`, `Session`
- `src/jmap_client/envelope.nim` — `Invocation`, `Request`, `Response`, `ResultReference`, `Referencable[T]`
- `src/jmap_client/framework.nim` — `PropertyName`, `FilterOperator`, `Filter[C]`, `Comparator`, `PatchObject`, `AddedItem`
- `src/jmap_client/errors.nim` — `TransportError`, `RequestError`, `ClientError` (exceptions); `MethodError`, `SetError` (response data)
- `src/jmap_client/client.nim` — HTTP client wrapper (Layer 4)
- `tests/` — Test modules (categories: `unit/`, `serde/`, `property/`, `compliance/`, `stress/`)

## Coding Conventions

- Use `const` and `let` bindings; `var` only when absolutely necessary
- Error handling:
  - Smart constructors raise `ValidationError` on invalid input, return `T` directly on success
  - Transport/request failures raise `ClientError` (with `TransportError`/`RequestError` subtypes)
  - Method errors (`MethodError`) and set errors (`SetError`) are data within successful responses, not exceptions
  - Layer 5 C ABI catches all exceptions via `try/except` and converts to C error codes
- Use `Option[T]` from `std/options` for optional values
- Parse, don't validate — smart constructors produce well-typed values or raise structured errors
- Make illegal states unrepresentable — distinct types, case objects, smart constructors
- Prefer expression-oriented style: if/case/block as expressions
- Prefer `collect` (std/sugar) for building new collections; `allIt`/`anyIt` for predicates
- Purity by convention: Layers 1–3 do not perform I/O or mutate global state
- `{.push raises: [].}` ONLY on Layer 5 C ABI module (`src/jmap_client.nim`)

## Type Safety

- Use distinct types for domain identifiers
- Export C ABI functions with `{.exportc: "jmap_name", dynlib, cdecl, raises: [].}` pragmas

## Language

- Comments and docstrings: British English spelling

## Nim Coding Rules

Detailed Nim patterns are in `.claude/rules/`:
- `nim-conventions.md` — error handling, immutability, expression style, naming
- `nim-type-safety.md` — distinct types, case objects, enums, smart constructors
- `nim-ffi-boundary.md` — C ABI exports, type mapping, memory ownership, error projection

## Workflow

- Run `just ci` before committing (runs reuse + fmt-check + lint + test)
- Use nph for formatting (devcontainer auto-configured, format-on-save enabled)
- Run `just versions` to verify tool versions
