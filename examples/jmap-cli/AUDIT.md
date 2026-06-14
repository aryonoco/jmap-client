# jmap-cli API ergonomics audit (P29 / tracker C1)

This ledger is the deliverable of the sample-consumer bench. The CLI is
the instrument; this file is the product. Each line records one
awkwardness encountered while writing the CLI against the **public
API only** (`import jmap_client` [+ `jmap_client/convenience`]).

**Status convention (Phase 1, observe-only).** Every finding is logged
`[open]`. This is a deliberate divergence from tracker C1's
`[resolved | accepted | filed-as-Cn]` wording: this pass *catalogues*
friction without resolving it, so the API is felt as a newcomer would
feel it. Triage into resolve/accept/file is a separate later pass.

**Format.** `- <command>:<call-site>: <description> [open]`

**Expected categories.** UFCS chain >3 levels; `.get()`/`valueOr` chain
over an `Opt` of a `Result`; sealed-type construction ceremony; three-
state `FieldEcho[T]` reads; back-reference enum discovery
(`reference[T](h, mn…, rp…)`); raw `JsonNode` at a call site; concept
that must be learned before the simple thing works; a command that
cannot be expressed with hub-public symbols at all (highest severity).

## Build environment (Phase 0)

Facts established while standing up the bench, before any command ran.
These are about the *build contract*, not a specific call site.

- build:module-name: the entry module cannot be named `jmap-cli.nim` —
  Nim module names must be valid identifiers, so a hyphen is rejected
  (`invalid module name: 'jmap-cli'`). Named the source `jmap_cli.nim`;
  the run-name `jmap-cli` comes from `-o:`. Incidental CLI plumbing, not
  an API finding. [open]
- build:config-inheritance: an in-tree consumer under `examples/` cannot
  escape the library's root `config.nims`; the compiler walks up from the
  source file and applies the full `warningAsError` battery + `strictDefs`
  + `panics`/`floatChecks`/`overflowChecks`. So this bench builds *under*
  the library's own strictness, not a pristine consumer's. The "does the
  API leak strictness onto consumers?" hypothesis (nim.cfg note in the
  plan) can only be tested by an out-of-tree build with the sample copied
  outside the repo — done once in the final task. [open]
- build:transport-deps: `import jmap_client` transitively pulls in
  `std/httpclient`, `std/asyncdispatch`, `std/asyncfutures`, `std/random`
  — the default L4 transport is std-`httpclient`-based. A consumer who
  only wants the typed protocol core still links the async machinery.
  [open]

## Positive findings (what is genuinely good)

- build:compile: the smoke entry (`import jmap_client` + one smart
  constructor) compiled clean on the first valid-module-name attempt,
  even under the inherited strict battery. The public surface imports
  without ceremony. [open]

## Findings by command

### session
### mailbox
### email query
### email read
### email flag
### email move
### email send
### thread
### identity
### vacation
### search
### convenience

## Cross-cutting findings

<!-- friction that recurs across commands; promoted in Task 16 -->
