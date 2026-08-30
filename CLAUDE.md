# jmap-client

Cross-platform JMAP (RFC 8620/8621) client library in Nim. Designed for FFI use from C/C++


## CRITICAL: Git Commit Message Format

Git Commit messages MUST be modeled after the Linux kernel.

The subject line should use the subsystem/component: short description format, stay under 75 characters, and use imperative mood ("fix" not "fixed" or "fixes").

The body should be wrapped at ~75 columns, explain why the change is needed (not just what it does), and be separated from the subject by a blank line.

The following 3 lines MUST be included at the end of EVERY git message body:

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-5-fable

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
- `just setup` - Install dependencies and git hooks (`core.hooksPath` → `.githooks/`)
- `just build` / `just build-release` - Build `bin/libjmap_client.so`
- `just test` - Run fast suite (skips slow files in `tests/testament_skip.txt`); agents should use this for validation and leave `just test-full` (runs everything) for the user.
- `just test-file <path>` - Run a single testament file
- `just test-c` - Build, then compile and run every `ctests/*.c` under ASan/UBSan
- `just build-c-bench` - Build `examples/jmap-c-cli` against `include/jmap_client.h` alone
- `just fmt` - Format all source files with nph
- `just fmt-check` - Verify formatting
- `just lint` - Run lint checks
- `just analyse` - Run nimalyzer static analysis
- `just check` - Every quality gate except reuse, build and tests
- `just ci` - Full pipeline (mirrors `.github/workflows/ci.yml`): reuse, fmt-check, the lint battery (`lint`, `lint-isolated`, `lint-style`, `lint-defect-audits`, the boundary lints, the H13/H15/H16/H17 snapshot locks), analyse, `build`, the H18/H19/H20 C-header gates, `test-c`, `build-c-bench`, `test`. Requires a C toolchain, not just Nim.
- `just stalwart-up` / `stalwart-down` / `stalwart-reset` — Stalwart only
- `just james-up` / `james-down` / `james-reset` — Apache James only
- `just cyrus-up` / `cyrus-down` / `cyrus-reset` — Cyrus IMAP only
- `just jmap-up` / `jmap-down` / `jmap-reset` / `jmap-status` — every configured target (Stalwart, James, Cyrus)
- `just test-integration` — Run live integration tests against every configured JMAP target (requires `just jmap-up`, or per-server variants)
- `just capture-fixtures` — Capture wire fixtures from every configured target
- `just clean` - Remove build artifacts
- `just docs` - Generate HTML documentation

## Dependencies

One dependency: `nim-results`  for `Result[T, E]`,
`Opt[T]`, and the `?` operator. vendored and patched in `vendor/nim-results`
All other imports are from Nim's standard library.

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

- `src/jmap_client.nim` — Library entry point and sole public re-export hub (C ABI exports land here per A10)
- `src/jmap_client/internal/types.nim` — Re-exports all Layer 1 modules (internal hub; re-exported from `src/jmap_client.nim`)
- L1 modules under `src/jmap_client/internal/types/` (`validation`,
  `primitives`, `identifiers`, `collation`, `submission_atoms`,
  `capabilities`, `account_capability_schemas`, `methods_enum`,
  `session`, `envelope`, `framework`, `errors`, `field_echo`,
  `credential`, `session_endpoint`) — re-exported via
  `src/jmap_client/internal/types.nim` and surfaced to consumers
  through `src/jmap_client.nim`. See `docs/design/01-layer-1-design.md`
  for per-module symbol inventory.
- `src/jmap_client/internal/serialisation/` — Layer 2 serde modules (no public hub; in-tree callers import leaves directly under H10)
- `src/jmap_client/internal/protocol.nim` — Re-exports the Layer 3 protocol surface (builders, dispatch, methods, entity)
- `src/jmap_client/internal/transport.nim` — Pluggable HTTP transport interface (Layer 4; re-exported from `src/jmap_client.nim`)
- `src/jmap_client/internal/client.nim` — JMAP client handle (Layer 4; re-exported from `src/jmap_client.nim`)
- `src/jmap_client/internal/one_shot.nim` — Build-dispatch-extract one-shot helpers (Layer 4; re-exported from `src/jmap_client.nim`)
- `src/jmap_client/internal/mail/` — RFC 8621 JMAP Mail entities, including `combinators.nim` (the per-entity pipeline combinators, always-on — re-exported from `src/jmap_client.nim`)
- `src/jmap_client/internal/{push,websocket}.nim` — Type stubs for RFC 8620 §7 Push and RFC 8887 WebSocket; types re-exported from root, no separate public module paths (A10c per P5 + P23)
- `tests/` — Test modules (categories: `unit/`, `serde/`, `property/`, `compliance/`, `stress/`, `protocol/`, `integration/`, `wire_contract/`, `compile/`, `lint/`)
- `tests/wire_contract/` — Checked-in snapshots (see Snapshot Locks)
- `include/jmap_client.h` — The hand-curated C header; the C API's source of truth
- `ctests/` — Plain-C ABI compliance tests, run by `just test-c`. Deliberately outside `tests/`: testament's `all` mode asserts on a category with no `.nim` files
- `examples/jmap-cli` (Nim) and `examples/jmap-c-cli` (C) — Consumer benches, compiled against the public surface only
- `docs/design/14-Nim-API-Principles.md`, `docs/design/17-L5-FFI-Principles.md` — Where the A/P/D ledger numbers cited in justfile and code comments are defined
- `docs/TODO/` — Registers of deferred work

## Coding Conventions

- Use `const` and `let` bindings; `var` only when absolutely necessary and only locally
- Error handling via Railway-Oriented Programming (nim-results):
  - Smart constructors return `Result[T, ValidationError]` — no exceptions
  - Transport/request/protocol failures use `Result[T, JmapError]` (`JmapResult[T]` alias) — `JmapError` is the flat 8-arm consumer-facing error rail
  - Method errors (`MethodError`) and set errors (`SetError`) are data within successful responses
  - All error types are plain objects carried on the Result error rail
  - The `?` operator provides early-return error propagation
- Use `Opt[T]` from nim-results for optional fields (not `std/options`); prefer `for val in opt:` over `if opt.isSome: opt.get()`
- Prefer expression-oriented style: if/case/block as expressions
- Prefer `collect` (std/sugar) for building new collections; `allIt`/`anyIt` for predicates
- **`func` is mandatory in L1–L3** (types, serde, protocol) — no `proc` permitted. `{.push raises: [], noSideEffect.}` at the top of each L1–L3 module enforces purity at compile time. Callback parameters use `{.noSideEffect, raises: [].}` on the proc type; `mixin` resolves pure at instantiation. `proc` only allowed in L4 (IO/transport) and L5 (C ABI exports)
- **Push pragmas on every source module** — L1–L3: `{.push raises: [], noSideEffect.}` (totality + purity); L4–L5: `{.push raises: [].}`
- **`{.experimental: "strictCaseObjects".}` in src/ only** — every `.nim` file under `src/` MUST have this pragma immediately after its `{.push raises: ...}`. Tests/ are exempt. See `nim-type-safety.md` for details.

## C ABI

- Every export lives in `src/jmap_client.nim` as `{.exportc: "jmap_name", dynlib, cdecl, raises: [].}`; nothing else in the tree exports to C
- `include/jmap_client.h` is hand-curated, not generated. Changing an export means editing it by hand, then passing H18 (`lint-c-header`, inventory both ways), H19 (`lint-c-header-snapshot`) and H20 (`lint-c-header-types`, cross-checks declarations against `nim c --header` output)
- Error model follows SQLite: a `jmap_status` ordinal returned per call, `recordError(handle, err)` filling a per-handle slot that `jmap_errmsg` (borrowed message) and `jmap_errtype` (wire error type) read back. `jmap_strerror` is static and handle-free. No thread-local last-error state
- `jmap_init` runs `NimMain()` behind a process-wide latch. The library is `--app:lib --noMain`, so module globals are uninitialised until it runs; every export that allocates or returns a status checks the latch first. `jmap_strerror` and `jmap_version` are the only pre-init entry points
- `docs/design/17-L5-FFI-Principles.md` is authoritative for the C ABI and supersedes `.claude/rules/nim-ffi-boundary.md` and `docs/design/00-architecture.md` §5 where they disagree

## Comments

- Comments should explain _why_, never _what_. The _what_ belongs in the types.
- Comments and docstrings: British English spelling

## Licensing

Every new file needs an inline SPDX header (a `BSD-2-Clause` licence identifier plus a copyright line) or a matching annotation in `REUSE.toml`, or `just reuse` — the first step of `just ci` — fails. `ctests/`, `include/` and `examples/` match no `REUSE.toml` path glob and rely entirely on inline headers. REUSE scans this file too, so never spell a literal SPDX tag out in prose here — it gets parsed as a real one.

## Nim Coding Rules

Detailed Nim patterns are in `.claude/rules/`:
- `nim-conventions.md` — error handling, immutability, expression style, naming
- `nim-type-safety.md` — distinct types, case objects, enums, smart constructors
- `nim-functional-core.md` — L1–L3 FP idioms: safe stdlib primitives, sum-type ADTs, `withValue`, set algebra, translation boundaries
- `nim-ffi-boundary.md` — C ABI exports, type mapping, memory ownership, error projection

## Static Analysis

- Never suppress or relax nimalyzer rules (e.g. `ruleOff: "complexity"`). Always restructure code to comply. To reduce complexity decompose into sub-helpers, extract field-group comparisons, use generics for shared logic.

## Snapshot Locks

Five gates compare live output against a checked-in snapshot under
`tests/wire_contract/` and fail closed on drift. Never hand-edit a
snapshot — regenerate it, review the diff, and tag the PR.

| Snapshot | Lint | Regenerate | PR tag |
|---|---|---|---|
| `module-paths.txt` | H13 `lint-module-paths` | `just freeze-module-paths` | `[MODULE-PATH-CHANGE]` |
| `error-messages.txt` | H15 `lint-error-messages` | `just freeze-error-messages` | `[ERR-MSG-CHANGE]` |
| `public-api.txt` | H16 `lint-public-api` | `just freeze-api` | `[API-CHANGE]` |
| `type-shapes.txt` | H17 `lint-type-shapes` | `just freeze-type-shapes` | `[TYPE-SHAPE-CHANGE]` |
| `c-header.txt` | H19 `lint-c-header-snapshot` | `just snapshot-c-header` | `[C-ABI-CHANGE]` |

## Workflow

- Run `just ci` before committing — the full gate list above, including the C-header gates and the C compliance suite
- The four compile-time defect audits are skip-listed from `just test` (each needs its own compile). They run only via `just lint-defect-audits`. An audit that never compiles is silent, not green.
- Use nph for formatting
