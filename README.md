# jmap-client

> [!WARNING]
> **This project is a very early stage prototype.** It is not alpha quality software and is not usable in any shape or form. There is no stable API, no complete functionality, and no guarantee that anything works. **Do not use this for anything.**

A cross-platform JMAP ([RFC 8620](https://www.rfc-editor.org/rfc/rfc8620)/[RFC 8621](https://www.rfc-editor.org/rfc/rfc8621)) client library implemented in Nim, providing a stable C API as a shared library. Callable from C, C++, and any language with foreign function interface support.

## Status

Early development.

## Building

Requires Nim >= 2.2.0. Development environment provided via devcontainer.

```bash
just build          # Build shared library (.so/.dylib/.dll)
just test           # Run tests
just ci             # Full CI pipeline
```

## Architecture

- **Functional core, imperative shell** — pure domain logic in Layers 1–3, I/O at the boundary
- **ARC memory management** — deterministic, no GC pauses, FFI-safe
- **C API boundary** — Layer 5 exports `{.exportc, dynlib, cdecl, raises: [].}` functions, catching all exceptions and projecting them as C error codes

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
