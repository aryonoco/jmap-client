# jmap-client

Cross-platform JMAP (RFC 8620/8621) client library in Nim. Designed for FFI use from C/C++ via `--mm:arc` and `{.exportc, cdecl.}`.

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

Sole dependency: `nim-results` 0.5.1 (status-im/nim-results), vendored at `vendor/nim-results/` with patches for `strictCaseObjects` compliance. Provides `Result[T, E]`, `Opt[T]`, `?` operator. Import as `import results`. See `.claude/rules/nim-conventions.md` for usage.

## Compiler Flags

Defined in `jmap_client.nimble`: `--mm:arc`, `strictDefs`, `strictFuncs`, `strictCaseObjects`, `strictNotNil`, `styleCheck:error`. `strictCaseObjects` is enforced per-module in `src/` via `{.experimental: "strictCaseObjects".}` (global enablement breaks `std/json`). See `.claude/rules/nim-type-safety.md` for implications.

## Project Structure

Architecture: 5 layers (see `docs/architecture-options.md`). Layer 1 detailed design in `docs/layer-1-design.md`.

- `src/jmap_client.nim` — Library entry point (C ABI exports, Layer 5)
- `src/jmap_client/types.nim` — Re-exports all Layer 1 modules; `JmapResult[T]` alias
- `src/jmap_client/validation.nim` — `ValidationError`, borrow templates, charset constants
- `src/jmap_client/primitives.nim` — `Id`, `UnsignedInt`, `JmapInt`, `Date`, `UTCDate`
- `src/jmap_client/identifiers.nim` — `AccountId`, `JmapState`, `MethodCallId`, `CreationId`
- `src/jmap_client/capabilities.nim` — `CapabilityKind`, `CoreCapabilities`, `ServerCapability`
- `src/jmap_client/session.nim` — `Account`, `UriTemplate`, `Session`
- `src/jmap_client/envelope.nim` — `Invocation`, `Request`, `Response`, `ResultReference`, `Referencable[T]`
- `src/jmap_client/framework.nim` — `PropertyName`, `FilterOperator`, `Filter[C]`, `Comparator`, `PatchObject`, `AddedItem`
- `src/jmap_client/errors.nim` — `TransportError`, `RequestError`, `ClientError`, `MethodError`, `SetError`
- `src/jmap_client/client.nim` — HTTP client wrapper (Layer 4)
- `tests/` — Test modules

## Functional Programming Conventions

- Follow "Functional Core, Imperative Shell" patterns consistently
- Use `func` for pure functions, `proc` only for side effects
- Use `let` bindings; `var` only when absolutely necessary
- Three error railways:
  - Smart constructors: `Result[T, ValidationError]` (construction-time)
  - Outer railway: `JmapResult[T]` = `Result[T, ClientError]` (transport/request)
  - Inner railway: `Result[T, MethodError]` (per-invocation)
- Never raise exceptions
- Use `Opt[T]` for optional values with `.isSome`/`.isNone`
- Parse, don't validate — smart constructors produce well-typed values or structured errors
- Make illegal states unrepresentable — distinct types, case objects, smart constructors
- Prefer expression-oriented style: if/case/block as expressions
- Prefer `collect` (std/sugar) for building new collections; `allIt`/`anyIt` for predicates
- `{.push raises: [].}` on every module
- `{.experimental: "strictCaseObjects".}` on every `src/` module

## Type Safety

- Use distinct types for domain identifiers
- Export C ABI functions with `{.exportc, cdecl.}` pragmas

## Language

- Comments and docstrings: British English spelling
- Variable names and code identifiers: US English spelling

## Nim Coding Rules

Detailed Nim patterns are in `.claude/rules/`:
- `nim-conventions.md` — ROP, purity, immutability, expression style, naming
- `nim-type-safety.md` — distinct types, `{.requiresInit.}`, case objects, enums, nil safety
- `nim-ffi-boundary.md` — C ABI exports, type mapping, memory ownership, error projection

## Workflow

- Run `just ci` before committing (runs reuse + fmt-check + lint + test)
- Use nph for formatting (devcontainer auto-configured, format-on-save enabled)
- Run `just versions` to verify tool versions
