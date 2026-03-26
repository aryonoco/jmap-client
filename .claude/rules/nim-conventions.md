---
paths:
  - "src/**/*.nim"
  - "tests/**/*.nim"
---

# Nim Conventions

All changes must preserve these principles:

- **Railway Oriented Programming**: propagate errors via following Rust/OCaml paterns. Never raise exceptions for domain errors.
- **Functional Core, Imperative Shell**: Logic should be implemented pure modules which contain zero side effects. I/O belongs exclusively in boundary modules.
- **Immutability by default**: use `let` bindings. `var` only at I/O boundaries when unavoidable.
- **Total functions**: use `func` for pure functions, `proc` only for side effects. Return `Result` or `Opt` instead of raising.
- **`{.push raises: [].}`** on every module — enforces exception safety at compile time.
- **Distinct types** for domain identifiers (account IDs, email IDs, blob IDs) to prevent mixing.
- **UFCS chaining**: `.filterIt().mapIt().foldl()` preferred over nested calls.
- **C ABI exports** use `{.exportc, cdecl.}` — these are `proc` (never `func`) since they cross the FFI boundary.
