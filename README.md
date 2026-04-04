# jmap-client

> [!WARNING]
> **This project is a very early stage prototype.** It is not alpha quality software and is not usable in any shape or form. There is no stable API, no complete functionality, and no guarantee that anything works. **Do not use this for anything.**

A cross-platform JMAP ([RFC 8620](https://www.rfc-editor.org/rfc/rfc8620)/[RFC 8621](https://www.rfc-editor.org/rfc/rfc8621)) client library written in Nim.

Designed to be usable from C/C++ via a clean C ABI (`{.exportc, dynlib, cdecl, raises: [].}`), with `--mm:arc` for deterministic, FFI-safe memory management.

## Status

Early development — project skeleton only.

## Building

Requires Nim >= 2.2.0. Development environment provided via devcontainer.

```bash
just build          # Build shared library
just test           # Run tests
just ci             # Full CI pipeline
```

## Architecture

- **Functional Core, Imperative Shell** — pure domain logic, I/O at boundaries
- **Result types** — `JmapResult[T]` for error handling, never raise
- **ARC memory management** — deterministic, no GC pauses, FFI-safe

## AI/LLM Disclosure

This project was developed with significant LLM involvement. I designed the core logic, made technical decisions and directed development but AI/LLM tools generated most of the code.

All code was reviewed, tested, and iterated on by me. The design choices (Result types, functional patterns, compiler settings, etc) are mine. Most of the Nim code is not.

## Licence

Copyright 2026 Aryan Ameri.

| Content | Licence |
|---------|---------|
| Source code, configuration, and tooling | [BSD-2-Clause](LICENSES/BSD-2-Clause.txt) |
| Documentation | [CC-BY-4.0](LICENSES/CC-BY-4.0.txt) |

This project is [REUSE](https://reuse.software/) compliant. See [REUSE.toml](REUSE.toml) for details.
