# jmap-client

A cross-platform JMAP ([RFC 8620](https://www.rfc-editor.org/rfc/rfc8620)/[RFC 8621](https://www.rfc-editor.org/rfc/rfc8621)) client library written in Nim.

Designed to be usable from C/C++ via a clean C ABI (`{.exportc, cdecl.}`), with `--mm:arc` for deterministic, FFI-safe memory management.

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

## Licence

| Component | Licence |
|---|---|
| Source code (`src/`, `tests/`) | [MPL-2.0](LICENSES/MPL-2.0.txt) |
| Configuration and tooling | [0BSD](LICENSES/0BSD.txt) |
| Documentation | [CC-BY-4.0](LICENSES/CC-BY-4.0.txt) |

This project is [REUSE](https://reuse.software/) compliant.
