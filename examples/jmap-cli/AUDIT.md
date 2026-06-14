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
- identity:fields: `Identity`'s `id`/`name`/`email` are direct public fields
  — reading a list of identities is a clean two-liner with no Opt/FieldEcho
  ceremony. The entity read-models are at their best when flat. [open]
- session:type-safety: the verbose lifecycle is *type-safe* — `freeze`
  consumes the builder by `sink` (a second `send` of the same `BuiltRequest`
  is a compile error), and the `ResponseHandle[T]` returned by `add*Get`
  binds the get's result type, so `dr.get(handle)` cannot be mis-typed.
  Ceremony bought genuine compile-time guarantees. [open]
- email query:back-reference type-safety: `reference[seq[Id]](queryH, …)`
  threads the Email/query result ids into Email/get within ONE request and
  is fully type-checked — no manual id plumbing, no second round-trip, and
  the generic pins the referenced shape to `seq[Id]`. The ceremony is real
  but it buys a genuinely safe server-side back-reference. [open]

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
- email query:QueryParams.limit: a constant page size is a triple wrap `Opt.some(parseUnsignedInt(20).get())` — `int64` -> `Result[UnsignedInt]` -> `.get()` -> `Opt.some`; no plain-int convenience or `withLimit(20)` [open]
- email query:filter: `EmailFilterCondition` is a raw object literal with every field `Opt[...]`, so a two-field filter needs `Opt.some` on each; `addEmailQuery.filter` is `Opt[Filter[EmailFilterCondition]]`, so a single condition double-wraps as `Opt.some(filterCondition(cond))`; `notKeyword` takes `Opt[Keyword]` (not a string); no filter-builder DSL [open]
- email query:sort: `addEmailQuery.sort` is `Opt[seq[EmailComparator]]` — one comparator becomes `Opt.some(@[plainComparator(...)])`; no single-comparator overload [open]
- email query:reference: the back-reference `reference[seq[Id]](queryH, mnEmailQuery, rpIds)` makes the caller restate the producing method (`mnEmailQuery`) that `queryH` already encodes, pick the right `RefPath` member (`rpIds` among nine JSON-pointer variants), AND supply the generic `seq[Id]`, then wrap `Opt.some(...)`; a `queryH.idsReference()` helper would erase three enum-discovery foot-guns [open]
- email query:properties: `NonEmptySeq[EmailGetProperty]` is REQUIRED but declared after the defaulted `ids`, so it must be passed by name; building it is `parseNonEmptySeq(@[...]).get()` — a `.get()` sealing chain on a literal that cannot be empty [open]
- email query:PartialEmail dual optionality: `id`/`threadId`/`receivedAt`/`preview` are `Opt[T]` but `subject`/`fromAddr`/`to`/`cc`/`bcc` are `FieldEcho[T]`; the consumer must remember which read style applies per field [open]
- email query:FieldEcho: `FieldEcho[T]` has NO read accessor on the hub (only the `fieldAbsent`/`fieldNull`/`fieldValue` constructors + the public `value*` field), so reading subject/fromAddr requires a hand-written `case fe.kind of fekValue: fe.value of fekAbsent, fekNull: default` — every consumer reinvents `fieldEchoOr` [open]
- email query:tooling: the `egp*` selectors and `kwSeen` (and `kwDraft`/`kwFlagged`/...) are `*`-exported and COMPILE via `import jmap_client`, yet are ABSENT from public-api.txt — `api_surface.nim` records a decl only when the logical line STARTS with a `DeclKinds` keyword, so grouped `const`-block members are silently dropped. Snapshot-strict consumers must fall back to `parseEmailGetProperty("id").get()` / `parseKeyword("$seen").get()` per value [open]
- email query:two error rails in one flow: `client.send` returns `JmapResult` (ClientError) while `dr.get(handle)` returns `Result[_, GetError]` — the call site cannot use one uniform `?`/`valueOr` style and bridges `ClientError` vs `GetError` manually [open]

### email read
- email read:maxBodyValueBytes: a compile-time-constant byte cap (65536) must be sealed through `parseUnsignedInt(65536).get()` then re-wrapped `Opt.some(...)` — a smart-constructor+get+Opt ceremony for a literal that can never fail; no `UnsignedInt` literal helper, no `EmailBodyFetchOptions.textBodies(maxBytes)` convenience [open]
- email read:ids: a single id is `Opt.some(direct(@[id]))` (seq-wrap + `direct` + `Opt.some`); the in-tree `directIds` shorthand that would remove the nesting is ABSENT from public-api.txt, and the plan's `Opt.some(directIds(...))` is a hard double-Opt type error (`directIds` already returns `Opt[Referencable[seq[Id]]]`) — an easy footgun with no compiler hint until call time [open]
- email read:isMultipart: reaching a leaf part's `partId` forces a full `case part.isMultipart of true: discard of false: ...` with a dead `discard` arm purely to satisfy strictCaseObjects (an `if part.isMultipart` read is rejected); an `email.leafTextParts` iterator would erase this [open]
- email read:bodyValues: `Email.bodyValues` is a `std/tables` Table, but the hub re-exports `results` and NOT std/tables, so the consumer must add `import std/tables` solely to read a returned field — inconsistent and non-obvious [open]
- email read:decodeText: decoding the text body is a manual `textBody`-walk joined against the `bodyValues` table by partId; every consumer re-implements this part-id->value join. No `email.decodedTextBody(): string` exists despite it being the single most common read [open]
- email read:truncation: `EmailBodyValue.isTruncated` / `.isEncodingProblem` are plain bools the happy path silently ignores; nothing ties a truncated value back to the `maxBodyValueBytes` cap, so correctness depends on the consumer remembering to check two booleans [open]
- email read:id-parser-choice: the command must choose between strict `parseId` and lenient `parseIdFromServer` for a CLI-supplied id with no guidance — the strict/lenient pair (a sensible internal Postel's-law split) leaks to the consumer as a decision [open]

### email flag
- email flag:set-construction: a single-email flag pays a two-layer sealing ceremony — `initEmailUpdateSet(ops).valueOr` then `parseNonEmptyEmailUpdates(@[(eid, updSet)]).valueOr` — so the "update ONE email" case still wraps the whole-container `NonEmptyEmailUpdates`; a one-shot `addEmailUpdate(acc, id, @[ops])` shorthand is missing [open]
- email flag:accumulating-rail: both `initEmailUpdateSet` and `parseNonEmptyEmailUpdates` return `Result[_, seq[ValidationError]]` for what is conceptually one construct, forcing `error.mapIt(it.message).join("; ")` rendering instead of the single `.message` that `parseId`/`parseKeyword`/`parseAccountId` give — two error-rail shapes in one command [open]
- email flag:updateResults: the per-item success payload is `Result[Opt[PartialEmail], SetError]` — a Result-of-Opt double layer whose inner `Opt[PartialEmail]` is almost always `none` for a flag, so callers check `res.isOk` and discard the Opt; the three-layer unwrap reads awkwardly [open]
- email flag:SetError: only `se.message`/`se.description`/`se.rawType` are flat; structured detail (invalid property names, etc.) needs a `kind` case-match or the separate `mail_errors` helpers, which are easy to miss [open]

### email move
- email move:repetition: identical triple-sealing chain to `email flag` (`initEmailUpdateSet` -> `parseNonEmptyEmailUpdates` -> `addEmailSet(update = Opt.some(...))`) — the only difference is `moveToMailbox(id)` vs `markRead()`; the recurring boilerplate is a cross-cutting wrapper trigger [open]
- email move:Opt-vs-value: `addEmailSet.update` is `Opt[NonEmptyEmailUpdates]` (needs an explicit `Opt.some(updates)`), whereas `addVacationResponseSet.update` takes its update set BY VALUE — the two `/set` builders disagree on the Opt-vs-value convention, so the consumer cannot muscle-memory one shape [open]
- email move:moveToMailbox: the DSL verb itself reads well and is total — `moveToMailbox(id)` clearly expresses full-replace mailbox membership; the friction is entirely in the sealing/dispatch envelope around it [open]

### vacation
### email send
### thread
- thread:th.id / th.emailIds: `Thread` exposes NO public fields (empty type-shape); reads go through accessor funcs `id()`/`emailIds()` (the latter returning `lent seq[Id]`), diverging from `Mailbox`/`Identity` direct-field access — inconsistent entity read ergonomics across the same library [open]
- thread:addThreadGet ids: fetching explicit ids repeats the `Opt.some(direct(@[id]))` `Referencable`-wrapping ceremony seen in `email read` — no `seq[Id]` convenience overload for the common literal-ids case [open]
- thread:source: a `threadId` is only obtainable by first fetching it as the `egpThreadId` property of an email (`email query`/`email read`); there is no thread-of-this-email shortcut, so "show me this message's thread" is a two-step dance [open]

### identity
- identity:read: `Identity` reads cleanly via direct public fields (`id`, `name`, `email`); the only friction is the universal one — like every read, there is no single hub-public call that builds+dispatches+extracts a bare Get (the convenience module covers query/changes pairs, not plain gets) [open]

### vacation
- vacation:NoCreate-phantom: discovering that the create generic must be the `NoCreate` phantom requires reading the builder's return type `SetResponse[NoCreate, PartialVacationResponse]`; the phantom occupies the FIRST (create) slot, which is non-obvious, and `createResults` stays permanently empty — the "this singleton has no create rail" fact is encoded in a type position the consumer must reverse-engineer [open]
- vacation:set-echo-FieldEcho: the `/set` echo type is `PartialVacationResponse` with three-state `FieldEcho[T]` fields (no read accessor), so rendering the echoed state needs manual `case` dispatch; to show state cleanly the CLI re-fetches via `addVacationResponseGet`, whose `VacationResponse` has plain `Opt` fields — a missing `FieldEcho.toOpt`/value convenience forces the extra round-trip [open]
- vacation:singleton-id: `VacationResponseSingletonId` is a raw `string` ("singleton"), not a typed `Id`, so looking the singleton up in `updateResults` (`Table[Id, _]`) would need `parseId(VacationResponseSingletonId).get()` first — a newtype leak on the one place the id matters [open]
- vacation:get-clean: the GET path is genuinely clean — `VacationResponse.isEnabled` is a plain `bool` and `subject`/`textBody` are plain `Opt[string]`, so reading vacation state is a simple Opt unwrap with none of the set path's FieldEcho ceremony [open]

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
- email query / email read (same-field optionality split, **medium**): the
  SAME logical field is read two different ways depending on which get was
  issued — `subject` is `FieldEcho[string]` on `PartialEmail` (partial get)
  but `Opt[string]` on the full `Email`; `fromAddr` is `FieldEcho[seq[…]]`
  vs `Opt[seq[…]]`. A consumer who switches between `addPartialEmailGet`
  and `addEmailGet` must change its read idiom for fields that look
  identical, with no type-level cue at the call site that they differ [open]

<!-- friction that recurs across commands; promoted in Task 16 -->
