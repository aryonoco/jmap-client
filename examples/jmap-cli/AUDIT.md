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
- session:results-reexport: `import jmap_client` re-exports the `results`
  vocabulary (`Result`, `Opt`, `ok`, `err`, `valueOr`, `?`, `Opt.some/none`)
  — no separate `import results` needed. One import gets the error rail. [open]
- session:accessors: `session.username` / `session.apiUrl` are clean direct
  accessors; live Stalwart returns `alice` / `http://stalwart:8080/jmap/`
  (the plan's worry that `username` might be empty did not materialise). [open]
- session:type-safety: the verbose lifecycle is *type-safe* — `freeze`
  consumes the builder by `sink` (a second `send` of the same `BuiltRequest`
  is a compile error), and the `ResponseHandle[T]` returned by `add*Get`
  binds the get's result type, so `dr.get(handle)` cannot be mis-typed.
  Ceremony bought genuine compile-time guarantees. [open]

## Findings by command

### session
- session:connect: obtaining one usable client costs THREE sequential smart-constructor unwraps (`directEndpoint().valueOr`, `basicCredential().valueOr`, `initJmapClient().valueOr`) — sealing-chain ceremony with no single `connect(url, user, pass)` convenience shorthand on the hub [open]
- session:connect: NO hub-public `ClientError` constructor exists (only `transportError` -> `TransportError`; no `clientError`, no lift from `ValidationError`/`TransportError`), so a consumer cannot return its failures on the library's `JmapResult` rail and is forced to invent a CLI-local error type (`cli_session` uses `string`) and `.message`-stringify at every boundary [open]
- session:connect: the `?` operator cannot bridge a `Result[_, ValidationError]` (smart constructors, `initJmapClient`) into a `JmapResult[_]`/`ClientError` function — the two error rails do not auto-convert, so every constructor call needs an explicit `.valueOr: return err(...)` instead of `?` [open]
- session:lifecycle: the proving read costs a five-symbol chain — `client.newBuilder()` then `add*Get(b)` returning a `(RequestBuilder, ResponseHandle)` tuple then `b2.freeze()` (sink) then `client.send().valueOr` then `dr.get(handle).valueOr` — four unwraps plus manual threading of the opaque handle and the re-bound builder `b2` through the chain [open]
- session:capability: `primaryAccount(ckMail)` returns `Opt[AccountId]` forcing an unwrap, and requires the caller to first discover the `ckMail` enum value (a `CapabilityKind` back-reference) rather than offering a mail-specific shorthand like `session.mailAccountId()` (confirms tracker C5/C8) [open]
- session:limits: `CoreCapabilities` limits return `UnsignedInt` with only a `.toInt64` projection (no `toInt`, no snapshot-listed `$`), so every limit read needs `.toInt64` before printing/arithmetic; `parseUnsignedInt` also takes `int64`, not `int` [open]
- session:config: no config-file/loader in the API; the consumer hand-reads three env vars itself [open]

### mailbox
- mailbox:dr.get(handle): typed extraction is the same repeated ceremony as `session` — `newBuilder` -> `add*Get` (tuple) -> `freeze` -> `send.valueOr` -> `dr.get(handle).valueOr` -> iterate `.list`; no single-call get shorthand for the common "fetch all of one entity" case [open]
- mailbox:rightsSummary: no `canRead`/`canMutate`/`canDelete` (or any) roll-up over `MailboxRights`' nine independent `may*` bools (tracker C4) — every consumer hand-rolls an ACL digest; a hub-public rights predicate/digest helper would remove guesswork about which flags constitute "can write" [open]
- mailbox:mb.role: role is `Opt[MailboxRole]`; display needs an Opt unwrap then `identifier`/`$`, and "is this the inbox?" needs one of three divergent idioms — `role.kind == mrInbox`, the snapshot-UNLISTED const `roleInbox`, or `parseMailboxRole("inbox").get()` (a sealing chain) — none discoverable from the frozen snapshot [open]

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

- *all commands* (snapshot integrity, **high**): the frozen public-API
  contract `tests/wire_contract/public-api.txt` (locked by the H16 lint,
  regenerated by `scripts/freeze_public_api.nim` / `api_surface.nim`) is
  NOT a faithful enumeration of the hub-public surface. It silently omits
  the entire request-lifecycle verb set — `newBuilder` (0 hits), `freeze`
  (0 hits), the 2-arg `initJmapClient`, plus `fetchSession`/`setCredential`/
  `refreshSessionIfStale` — and all backtick operators (`$`/`==` on `Id`/
  `AccountId`/`UnsignedInt`/`MailboxRole`), const-block members
  (`roleInbox..`, `egp*`, `kw*`), and type-block continuation members
  (`ResponseHandle[T]`). The scraper runs away on typed literals
  (`0'u64` in `client.nim`, a parallel trap in `builder.nim`) and skips
  operator/continuation lines by construction. Consequence: a consumer
  who trusts the snapshot as the contract literally cannot discover how to
  build or dispatch a request, and the H16 lint passes only because the
  snapshot and the live resolver share the same blind spots — giving FALSE
  freeze-confidence (P1/P2). Every command in this bench is written against
  what actually compiles via `import jmap_client`, verified by build, not
  against the snapshot. This is the single most consequential finding of
  the bench and a freeze-blocker in its own right. [open]
- *all commands*: required a 4-call connect+session+account preamble;
  extracted to `cli_session.connect()`; confirms the C5/C8 connect-helper
  wrapper trigger [open]

<!-- friction that recurs across commands; promoted in Task 16 -->
