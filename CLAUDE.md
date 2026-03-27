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
- `just ci` - Run full CI pipeline (reuse + fmt-check + lint + test)
- `just clean` - Remove build artifacts
- `just docs` - Generate HTML documentation
- `just versions` - Show tool versions

## Project Structure

Architecture: 5 layers (see `docs/architecture-options.md`).

- `src/jmap_client.nim` - Library entry point (C ABI exports, Layer 5)
- `src/jmap_client/types.nim` - Domain types, errors, Result aliases (Layer 1)
- `src/jmap_client/errors.nim` - Error types and constructors (Layer 1)
- `src/jmap_client/session.nim` - JMAP session types (Layer 1)
- `src/jmap_client/client.nim` - HTTP client wrapper (Layer 4)
- `tests/` - Test modules (test_types)

## Functional Programming Conventions

- Follow "Functional Core, Imperative Shell" patterns consistently
- Use `func` for pure functions, `proc` only for side effects
- Use `let` bindings; `var` only when absolutely necessary
- Return `JmapResult[T]` for fallible operations, never raise exceptions
- Use `Opt[T]` for optional values with `.isSome`/`.isNone`
- Prefer expression-oriented style: if/case/block as expressions
- Chain operations with UFCS: `.filterIt().mapIt().foldl()`
- `{.push raises: [].}` on every module

## Type Safety

- Use distinct types for domain identifiers
- Export C ABI functions with `{.exportc, cdecl.}` pragmas

## Language

- Comments and docstrings: British English spelling
- Variable names and code identifiers: US English spelling

## Workflow

- Run `just ci` before committing (runs reuse + fmt-check + lint + test)
- Use nph for formatting (devcontainer auto-configured, format-on-save enabled)
- Run `just versions` to verify tool versions
