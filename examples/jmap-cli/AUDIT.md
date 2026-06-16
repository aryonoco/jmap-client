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

## Summary

- **Commands exercised: 13** — `session`, `mailbox`, `email query` /
  `read` / `flag` / `move` / `send` / `sync`, `thread`, `identity`,
  `vacation`, `search`, and the convenience pipeline. Every public
  RFC 8620/8621 entity area is covered (see [Coverage](#coverage)),
  live-verified against Stalwart — including real alice → bob delivery and
  an incremental-sync delta.
- **Findings: 92 ledger lines** — ≈16 positives (what is genuinely good)
  and ≈76 friction findings. Severity is tagged on the cross-cutting and
  headline items: **6 high, 7 medium, 2 low**; the remaining per-command
  lines are local observations catalogued for triage (effectively low
  under the observe-only posture).
- **Blocked commands (inexpressible with hub-public symbols): NONE.**
  Every command compiles and round-trips through `import jmap_client`
  (+ `jmap_client/convenience`) only — verified both in-tree under the
  library's full strict battery and by a pristine out-of-tree build with
  zero warnings. The nearest thing to a blocker is the snapshot-integrity
  finding: a strict "only `public-api.txt` counts" reading of *hub-public*
  would make the whole CLI un-expressible, because `newBuilder`/`freeze`/
  `client.send` are reachable-but-unlisted — a freeze-blocking **tooling**
  defect, not an API expressibility gap.
- **Headline (high-severity) findings:** the frozen `public-api.txt`
  snapshot omits the request-lifecycle bookends (contract/tooling); the
  4-call connect preamble (C5/C8 wrapper trigger); the pervasive
  sealing-chain ceremony; and on the send path — no plain-text body
  helper, the misleading `addEmailSubmissionAndEmailSet` two-creation
  wiring, and the untyped `emailId` forward-reference.

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
  + `panics`/`floatChecks`/`overflowChecks`. So the in-tree bench builds
  *under* the library's own strictness, not a pristine consumer's.
  **Resolved (the experiment was run):** copying the sources outside the
  repo and building with ONLY `--mm:arc --threads:on --panics:on` (no
  `config.nims` in scope — confirmed: only the two system config files are
  used) compiles `SuccessX` with **zero warnings**. So the API leaks NO
  strictness onto consumers: the sample compiles identically with and
  without the library's warning-as-error battery. A genuine positive. [open]
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
- email send:atomic-send-works: despite the friction, the hard thing is
  POSSIBLE and ATOMIC — a single request created the draft, submitted it,
  and (via `onSuccessUpdateEmail`) moved it to Sent, with live delivery
  alice->bob confirmed. The RFC 8621 §7 onSuccess semantics are faithfully
  exposed and the whole compound is one network round-trip. The API does
  not block the use case; it taxes the path to it. [open]
- search:compound-ergonomics: `addEmailQueryWithSnippets` + `getBoth(chain)`
  is the API at its ERGONOMIC BEST — one call, one extraction, `.query.ids`
  + `.snippets.list`, the query->snippet back-reference wired and type-safe.
  When the API ships a purpose-built compound, the result is excellent; the
  problem is only that this one is invisible in the frozen contract. [open]
- convenience:full-email-path: `addEmailQueryThenGet` returns FULL `Email`
  (plain `Opt` fields, no `FieldEcho`) in one call + one `getBoth` — a
  genuinely smoother read than the hand-wired partial back-reference, and
  the P6 quarantine (opt-in import) is correctly applied so the core stays
  uncontaminated. This is the model the send path is crying out for. [open]
- build:no-strictness-leak: the **pristine out-of-tree build** (sources
  copied outside the repo, built with only `--mm:arc --threads:on
  --panics:on`, no `config.nims`) compiles `SuccessX` with zero warnings —
  proving the API imposes none of its own warning-as-error/strictDefs
  battery on consumers. The strict contract is the *library's* discipline,
  not a tax on its users. [open]

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
- email read:isMultipart: `EmailBodyPart` is a case object on the `isMultipart` bool, so reaching a leaf's `partId`/`blobId` means matching the `of false` arm. (The consumer does NOT enable `strictCaseObjects` — it is a src/-only per-file pragma, verified by the pristine build — so a plain `if not part.isMultipart:` reads the field cleanly; there is no compiler-forced `case`.) The genuine residual ask is an `email.leafTextParts` iterator or an `email.decodedTextBody(): string` so a mail client need not re-implement the textBody-walk + bodyValues-by-partId join at all [open]
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

### email send
_The longest section by design — this is the highest-friction public path. It nonetheless works end-to-end: a single request created the draft, submitted it, and moved it to Sent on success; live delivery alice->bob was verified (bob's inbox received `hello from jmap-cli`)._

Blueprint / body construction:
- email send:no-body-helper (**high**): there is NO plain-text body shorthand anywhere on the hub (no `textBody(str)`, no `plainTextBody`, no `initBlueprintLeafPart`). The single most common case — a plain string body — requires hand-building a 4-layer chain `BlueprintBodyValue -> BlueprintLeafPart{bpsInline} -> BlueprintBodyPart{text/plain} -> flatBody` before `parseEmailBlueprint`. This is the headline send-ergonomics gap [open]
- email send:parsePartIdFromServer: the ONLY hub-public `PartId` mint is `parsePartIdFromServer`, whose name and docstring say "lenient, server-provided, receive-side (Postel)", yet the SEND path MUST call it to create a client-chosen creation-time partId; the plan's `parsePartId` does not exist — a discoverability/naming trap (a send-side call named `FromServer`) [open]
- email send:raw-case-literals: `BlueprintLeafPart` and `BlueprintBodyPart` are constructed as raw case-object literals (no smart constructor), so the caller hand-writes the discriminator literals `source: bpsInline` / `isMultipart: false` and must know which fields belong to which branch — counter to "smart constructors only / raw constructors private" [open]
- email send:contentType-stringly: `BlueprintBodyPart.contentType` is a bare `string`, but `parseEmailBlueprint` rejects anything != "text/plain" for a text body (`ebcTextBodyNotTextPlain`) — a stringly-typed field guarded by deferred validation, with no compile-time aid [open]
- email send:blueprint-error-rail: `parseEmailBlueprint` returns `Result[_, EmailBlueprintErrors]` — a custom OPAQUE accumulator (not `seq[ValidationError]`), with no aggregate render-to-string helper, so the caller iterates `items`/`head` and joins `.message` itself [open]
- email send:recipient-double-wrap: `parseEmailBlueprint`'s `fromAddr`/`to` are `Opt[seq[EmailAddress]]`, so a single recipient is `Opt.some(@[addr])` (Opt + seq) — ceremony for the common single-recipient case [open]

Submission + the compound two-creation wiring (the centrepiece):
- email send:builder-does-not-create (**high**): `addEmailSubmissionAndEmailSet` does NOT create the email — its `create` table holds ONLY `EmailSubmissionBlueprint`; the "AndEmailSet" suffix is the SERVER's implicit Email/set emitted from `onSuccessUpdateEmail` (an UPDATE, not a create). The draft must be created by a SEPARATE `addEmailSet(create=...)` on the SAME builder. The builder name actively misleads; no convenience ties an Email create to a submission [open]
- email send:emailId-no-forward-ref (**high**): `EmailSubmissionBlueprint.emailId` is a plain `Id` with NO typed forward-reference, so pointing the submission at the freshly-created draft in one request has no type-level representation; the only hub-public encoding is `parseIdFromServer("#" & $draftCid)` — abusing the server-lenient parser to smuggle a client back-reference. The discoverable strict `parseId("#draft")` REJECTS the '#' (verified live) [open]
- email send:onSuccess-key: `onSuccessUpdateEmail` is keyed by `creationRef(subCid)` — the SUBMISSION's creation id, NOT the email's — a non-obvious indirection enforced only at runtime; easy to mis-key with the draft cid [open]
- email send:uncopyable-move: `addEmailSubmissionAndEmailSet` returns `Result[(RequestBuilder, EmailSubmissionHandles), ValidationError]` wrapping an UNCOPYABLE `RequestBuilder`, so the Ok value cannot be read with `.get()`/`.value` — the caller must `var r = ...; if r.isErr: ...; let (b, h) = move(r.value)`. Bespoke move ceremony unlike every other (bare-tuple) `add*` builder [open]
- email send:raw-envelope: `SubmissionAddress(mailbox:, parameters:)` and `Envelope(mailFrom:, rcptTo:)` are raw object literals with no smart constructor; the overwhelmingly common no-params recipient must spell `Opt.none(SubmissionParams)`, and there is no `rcpt(mailbox)` / `envelope(from, @[to])` shorthand [open]
- email send:sealing-pileup: four+ sealing constructors precede the build (`parseNonEmptyMailboxIdSet`, `parseEmailAddress`×2, `parsePartIdFromServer`, `parseRFC5321Mailbox`×2, `parseNonEmptyRcptList`, `parseEmailSubmissionBlueprint`, `initEmailUpdateSet`, `parseNonEmptyOnSuccessUpdateEmail`), each a separate Result the caller threads — some single-`ValidationError`, some accumulating `seq[ValidationError]`, the blueprint a third opaque shape: the caller adapts between THREE error-rail shapes in one command [open]
- email send:three-response-shapes: one logical "send" yields three response shapes — the draft Email/set (`emailHandle`) plus the compound `getBoth` -> `CompoundResults{primary, implicit}` where `primary` is the EmailSubmission/set and `implicit` is the onSuccess Email/set update; nothing in `.primary`/`.implicit` says which carries `createResults` vs `updateResults` [open]
- email send:nested-id-read: reading the created submission id is a nested rail — `getBoth().valueOr` then `primary.createResults` table-lookup then `res.value.id` (three unwraps) [open]
- email send:freeze-not-build: the builder finaliser is `freeze` (sink), there is no `build`; combined with its absence from the snapshot, a discoverability trap at the dispatch site [open]

### email sync
- email sync:state-roundtrips (POSITIVE): a `JmapState` cursor round-trips through `parseJmapState` (it is even in public-api.txt), so a consumer CAN persist a sync position to disk and resume after a process restart — the state is not trapped inside a live response object. This is exactly what incremental sync needs and the API gets it right [open]
- email sync:changes-to-get-created-only (**medium**): the convenience `addEmailChangesToGet` (and its `*ChangesToGet` siblings) back-references ONLY the `/created` path into the Email/get, so the `ChangesGetResults.get.list` carries created records but NOT updated ones. A mail client doing incremental sync overwhelmingly cares about UPDATED messages (read/flag/move changes), yet to fetch their bodies it must abandon the one-call convenience and hand-compose `addEmailChanges` + `addPartialEmailGet(ids = reference[seq[Id]](ch, mnEmailChanges, rpUpdated))` — the convenience covers the rarer case and drops to manual for the common one (live-confirmed: flagging an email yielded `updated=1` with an empty `get.list`) [open]
- email sync:state-acquisition: `Email/changes` diffs against the Email OBJECT state (`GetResponse.state`), not the query state, and no command surfaces that state by default — the CLI had to issue an empty-ids `Email/get` purely to read `resp.state` as the initial cursor; a `session`- or get-level "current state per type" accessor would remove the bootstrap round-trip [open]

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
- search:helper-undiscoverable (**medium**): the ergonomic one-call compound `addEmailQueryWithSnippets` (+ `EmailQuerySnippetChain`, `EmailQuerySnippetResults`, `getBoth(chain)`) is exactly the right shape — one call wires the query result ids into the snippet get, one `getBoth` yields `.query.ids` and `.snippets.list` — and it works live (matched 54). Yet ALL FOUR symbols are absent from public-api.txt (the scraper truncates `mail_methods.nim` after `addSearchSnippetGetByRef`), so a snapshot-guided consumer would never find it and would hand-roll the manual `addEmailQuery` + `reference[seq[Id]]` + `addSearchSnippetGetByRef` path instead — the best ergonomics in the library, hidden by the broken contract [open]
- search:SearchSnippetGetResponse-shape: `SearchSnippetGetResponse.list` is compile-accessible but the type has NO entry in `type-shapes.txt` (response types in indented `type` blocks are not scraped), so the field a search consumer must read is invisible to the type-shape contract [open]
- search:snippet-opt: `SearchSnippet.subject`/`.preview` are `Opt[string]` (each needs an Opt unwrap) while `emailId` is a bare `Id` — the now-familiar mixed-optionality read [open]
- search:two-rails: `client.send` is `ClientError`-tailed but `dr.getBoth(chain)` is `GetError`-tailed — the same two-error-rail bridging as every other dispatch+extract [open]

### convenience
- convenience:import-discoverability: the pipeline combinators require an explicit `import jmap_client/convenience` and are deliberately NOT re-exported by `import jmap_client` (P6 quarantine — correct in principle), so the headline import alone cannot reach `addEmailQueryThenGet`/`getBoth`; the discoverability cost is the price of the (sound) quarantine [open]
- convenience:result-shape: `getBoth` yields `QueryGetResults[Email]` exposing `.query` (a `QueryResponse` — read `.ids`) and `.get` (a `GetResponse` — read `.list`); two nested field hops, and the field names `query`/`get` read as verbs rather than nouns at the call site [open]
- convenience:two-rails: `getBoth` returns `GetError` while the enclosing `send` returns `ClientError` — same bridging friction as the manual paths [open]
- convenience:coverage-gap: the convenience module covers query-then-Email/get but has NO query-then-snippets analogue; the snippets compound lives un-snapshotted in `mail_methods`, so the opt-in layer cannot cover the search-highlight use case at all [open]

## Cross-cutting findings

- *all commands* (snapshot integrity, **high**): the frozen public-API
  contract `tests/wire_contract/public-api.txt` (locked by the H16 lint,
  regenerated by `scripts/freeze_public_api.nim` / `api_surface.nim`) is
  NOT a faithful enumeration of the hub-public surface. It omits the
  request-CONSTRUCTION bookends and the dispatch/session verbs — `newBuilder`
  (0 hits), `freeze` (0 hits), the client-level `send` (only the unrelated
  `Transport.send` is listed), the 2-arg `initJmapClient`, and
  `fetchSession`/`setCredential`/`refreshSessionIfStale` — even though the
  *middle* of the lifecycle (`add*Get`, `get`, `getBoth`, `direct`,
  `reference`) DOES survive. It also drops all backtick operators (`$`/`==`
  on `Id`/`AccountId`/`UnsignedInt`/`MailboxRole`), grouped const-block
  members (`roleInbox..`, `egp*`, `kw*`), the snippet compound
  (`addEmailQueryWithSnippets` + its chain/results + `getBoth` overload),
  the `EmailUpdateSet`/`NonEmptyEmailUpdates` family, and type-block
  continuation members (`ResponseHandle[T]`). The scraper runs away on a
  typed literal (`0'u64` at `client.nim:139`, which is why the 3-arg
  `initJmapClient` survives but everything after it is swallowed), an
  analogous unbalanced-quote/comment trap in `builder.nim`, and a
  `stripComment` defect in `email_update.nim`; it skips operator and
  grouped-`const`/type continuation lines by construction. Consequence: a
  consumer
  who trusts the snapshot as the contract literally cannot discover how to
  build or dispatch a request, and the H16 lint passes only because the
  snapshot and the live resolver share the same blind spots — giving FALSE
  freeze-confidence (P1/P2). Every command in this bench is written against
  what actually compiles via `import jmap_client`, verified by build, not
  against the snapshot. This is the single most consequential finding of
  the bench and a freeze-blocker in its own right. [open]
- *all commands* (connect preamble, **high**): every command needs the same
  4-call connect+session+account preamble (`directEndpoint` -> `basicCredential`
  -> `initJmapClient` -> `fetchSession` -> `primaryAccount(ckMail)`), which the
  bench had to extract into `cli_session.connect()`. The API makes you build
  the connect wrapper it should ship — the concrete C5/C8 wrapper trigger [open]
- *all commands* (sealing-chain ceremony, **high**): the dominant friction
  across the bench is the `parseX(...).get()/valueOr` -> `parseY(...).get()`
  ladder before a useful call — `directEndpoint`+`basicCredential`+`initJmapClient`
  (session); `parseUnsignedInt`+`filterCondition`+`parseNonEmptySeq` (query);
  `initEmailUpdateSet`+`parseNonEmptyEmailUpdates` (flag/move); and a 9-deep
  pile-up in send (mailbox set, addresses, partId, RFC5321, rcpt list, blueprints,
  update set, onSuccess). Each construct is individually principled (parse-don't-
  validate), but the consumer threads many fallible bookends before any wire call,
  with few one-shot shorthands [open]
- *all commands* (two error rails per dispatch, **medium**): every command
  that dispatches bridges TWO error types by hand — `client.send` returns
  `JmapResult`/`ClientError`, but `dr.get`/`dr.getBoth` return `Result[_, GetError]`,
  and the smart constructors return `ValidationError` (or `seq[ValidationError]`,
  or `EmailBlueprintErrors`). No single `?`/`valueOr` style spans
  build -> send -> extract; the rails do not auto-convert and there is no
  hub-public lift between them [open]
- read commands (no bare-get combinator, **medium**): mailbox/thread/identity/read
  all repeat `newBuilder` -> `add*Get` -> `freeze` -> `send` -> `get` -> iterate
  `.list` verbatim; the convenience module covers query/changes *pairs* and
  `*ThenGet`, but there is no one-call build-dispatch-extract for a plain Get,
  so the most basic read still costs the full five-symbol lifecycle [open]
- write commands (accumulating seq[ValidationError] rail, **medium**):
  `initEmailUpdateSet`/`parseNonEmptyEmailUpdates`/`parseNonEmptyRcptList`/
  `parseEmailSubmissionBlueprint`/`parseNonEmptyOnSuccessUpdateEmail` all return
  `Result[_, seq[ValidationError]]` (and `parseEmailBlueprint` an opaque
  `EmailBlueprintErrors`), so single-value constructions render errors via
  `mapIt(it.message).join` instead of the single `.message` the L1 parsers give —
  three distinct error-render idioms across flag/move/send/vacation [open]
- query + vacation (FieldEcho has no read accessor, **medium**): `FieldEcho[T]`
  (three-state absent/null/value) appears on `PartialEmail` header fields and the
  vacation `/set` echo, but the hub ships only the `fieldAbsent`/`fieldNull`/
  `fieldValue` CONSTRUCTORS and the public `value*` field — no reader — so every
  consumer hand-writes the same `fieldEchoOr` matcher [open]
- write commands (Result-of-Opt update read, **low**): `SetResponse.updateResults`
  is `Table[Id, Result[Opt[U], SetError]]` (flag/move/vacation), a three-layer
  unwrap whose inner `Opt[U]` is almost always `none`; callers check `isOk` and
  discard the Opt [open]
- read commands (Referencable id-wrapping, **low**): passing literal ids to
  `addEmailGet`/`addThreadGet` is `Opt.some(direct(@[id]))` (seq + `direct` +
  `Opt.some`) in email read/thread/sync; the in-tree `directIds` shorthand is
  unlisted and `Opt.some(directIds(...))` is a hard double-Opt error — no
  `seq[Id]` convenience overload [open]
- email query / email read (same-field optionality split, **medium**): the
  SAME logical field is read two different ways depending on which get was
  issued — `subject` is `FieldEcho[string]` on `PartialEmail` (partial get)
  but `Opt[string]` on the full `Email`; `fromAddr` is `FieldEcho[seq[…]]`
  vs `Opt[seq[…]]`. A consumer who switches between `addPartialEmailGet`
  and `addEmailGet` must change its read idiom for fields that look
  identical, with no type-level cue at the call site that they differ [open]

## Coverage

The brainstorming decision was **full-entity coverage** — every public
RFC 8620/8621 entity area exercised at least once, including the
`EmailSubmission` send path. That bar is met:

| Entity area | Command(s) | Key builder |
|---|---|---|
| Session / capabilities | `session` | `fetchSession`, `primaryAccount(ckMail)`, `coreCapabilities` |
| Mailbox (get) | `mailbox`, + role resolution in query/move/send | `addMailboxGet` |
| Email/query + back-ref | `email query` | `addEmailQuery` + `reference` + `addPartialEmailGet` |
| Email/get (full) | `email read` | `addEmailGet` (+ body values) |
| Email/set (update) | `email flag`, `email move` | `addEmailSet(update=)` |
| Email/set (create) | `email send` | `addEmailSet(create=)` |
| Email/changes | `email sync` | `addEmailChangesToGet` (convenience) |
| Thread | `thread show` | `addThreadGet` |
| Identity | `identity list` | `addIdentityGet` |
| EmailSubmission | `email send` | `addEmailSubmissionAndEmailSet` (+ onSuccess) |
| VacationResponse (get/set) | `vacation` | `addVacationResponseGet`/`Set` |
| SearchSnippet | `search` | `addEmailQueryWithSnippets` + `getBoth` |
| Convenience pipeline | `email query --via-convenience`, `email sync` | `addEmailQueryThenGet`, `addEmailChangesToGet` |

**Deliberately out of scope** (method-level surfaces beyond the entity bar;
recorded here so the ledger reads as a *choice*, not an oversight). These
compile and are hub-public but were not driven by the CLI: structural
`/set` — `addMailboxSet` (folder create/rename/delete), `addIdentitySet`;
the `EmailSubmission` *read* path (`addEmailSubmissionGet`/`Query`/`Changes`,
the `AnyEmailSubmission` `undoStatus`/`deliveryStatus` model); cross-account
`addEmailCopy`/`addEmailCopyAndDestroy`; `addMailboxQuery` and the
`*QueryChanges` variants; `addEmailQueryWithThreads` (conversation view);
the non-Email partial gets; and four of the five `*ChangesToGet` convenience
combinators (only `addEmailChangesToGet` was exercised). Of the 8 public
convenience combinators, 2 were driven (`addEmailQueryThenGet`,
`addEmailChangesToGet`). Blob upload/download and Push are deferred
project-wide and are correctly absent.

## S1 resolution — one error rail (`JmapError`)

Sub-project **S1** collapsed the five fragmented call-path rails into a single
`JmapError` sum and re-benched this CLI against it. The error-rail findings
above are **resolved**; their *non*-rail aspects (constructor-count ceremony,
read-model unevenness, missing one-shots) are out of S1's scope and stay open
for S2–S4. Mapping (finding → fix):

- **"NO hub-public `ClientError` constructor … forced to invent a CLI-local
  error type (`string`)"** (session:connect) → RESOLVED. The hub now exports
  per-arm minting constructors (`jmapValidation` / `jmapTransport` /
  `jmapRequest` / `jmapSession`), the `toJmapError` lifts, and the `lift`
  helper, so a consumer returns its own failures on the library rail. The CLI's
  `Result[T, string]` rail and hand-rolled `joinErrs` are deleted.
- **"`?` cannot bridge `ValidationError` → `ClientError` … every constructor
  call needs an explicit `.valueOr: return err(...)`"** (session:connect) →
  RESOLVED. A construction call folds onto the rail with one explicit
  `?parseX(...).lift`; the `build → send → get` pipeline threads on a bare `?`
  (`?client.send(...)`, `?dr.get(h)`), one uniform style end to end.
- **"two error rails per dispatch — `send` is `ClientError`, `dr.get`/`getBoth`
  is `GetError`"** (*all commands*, email query, search, convenience) →
  RESOLVED. `send`, `fetchSession`, `get`, `getBoth`, `getAll` and the L4
  constructors all return `Result[_, JmapError]`. A server method-level error
  is no longer a rail error at all: it is data on the ok branch via
  `MethodOutcome[T]` (`mokValue` / `mokMethodError`), so a batch's successful
  siblings survive (RFC 8620 §3.6.2). Only dispatch faults (`jeMisuse` /
  `jeProtocol`) ride the rail.
- **"accumulating `seq[ValidationError]` rail … `mapIt(it.message).join` instead
  of the single `.message`"** (email flag, write commands) → RESOLVED. The 14
  accumulating validators return `NonEmptySeq[ValidationError]`, and
  `JmapError.message` (the `jeValidation` arm) joins every violation, so the
  consumer renders one `err.message` like every other rail value.
- **"blueprint error-rail — `parseEmailBlueprint` returns an opaque
  `EmailBlueprintErrors` accumulator"** (email send) → RESOLVED.
  `EmailBlueprintErrors` is retired; `parseEmailBlueprint` returns
  `NonEmptySeq[ValidationError]` (the typed body-part location is preserved in
  each violation's reason), folding into `jeValidation` like every other
  construction failure — the "three error-rail shapes in one command" become one.
- **"`primaryAccount(ckMail)` returns `Opt[AccountId]` forcing an unwrap"**
  (session:capability) → PARTIALLY RESOLVED at S1; **fully resolved in S3 + the
  capability-resolution reconcile.** S1 first put capability/account resolution
  on the rail (`jeSession`); S3 added the named-soft shorthand `requireMail`
  (+ `requireSubmission` / `requireVacation`), and the reconcile then retired the
  interim general-strict resolver, leaving one coherent named-soft family. See the
  S3 resolution section below.

Still open after S1 (tracked to their sub-projects): the sealing-chain
constructor ceremony and the missing `connect()` / bare-get / `sendPlainText`
one-shots (S4); the `FieldEcho` reader and `SetError` `Result`-of-`Opt`
read-model and the same-field `FieldEcho`-vs-`Opt` split (S2/S3). The headline
error-rail friction the bench reported across *every* command is gone.

## S2 resolution — read-model uniformity (direct public fields)

Sub-project **S2** made every read off a returned value uniform (root cause
R6). Immutable DATA records now expose direct public fields; the
pass-through accessor and `lent` ceremony is gone, retained only where a
returned value is a stateful HANDLE (the client, the request builder). The
three-state `FieldEcho` echo gained a hub reader that mirrors `Opt`, so an
`Opt` field and a `FieldEcho` field read through one call shape. S2 settled
SHAPES only; findings that need a NEW reader or predicate (not just a uniform
shape) are deferred to S3 and marked as such below. The inline finding lines
keep their `[open]` tag, matching the S1 pass's observe-only convention; the
mapping lives here. Mapping (finding → fix):

- **"`FieldEcho[T]` has NO read accessor on the hub … every consumer
  reinvents `fieldEchoOr`"** (email query:FieldEcho; cross-cutting "FieldEcho
  has no read accessor") → RESOLVED. The hub ships the reader: `valueOr` (a
  template mirroring `nim-results` `Opt.valueOr`), `isValue`/`isNull`/`isAbsent`,
  an `items` iterator, and `toOpt`. The CLI DELETED its hand-written
  `fieldEchoOr` (`commands/email_query.nim`): `pe.subject.valueOr("(no subject)")`
  now reads identically to the plain-`Opt` `pe.preview.valueOr("")`. Both types
  are kept — the 3-state `FieldEcho` still carries the RFC 8620 §5.3
  absent-vs-null bit that a 2-state `Opt` would lose — but the idiom flip no
  longer costs the consumer a hand-rolled matcher.
- **"PartialEmail dual optionality … the consumer must remember which read
  style applies per field"** + **"the SAME logical field is read two
  different ways … `subject` is `FieldEcho` on `PartialEmail` but `Opt` on the
  full `Email`"** (email query:PartialEmail dual optionality; cross-cutting
  same-field optionality split) → RESOLVED (read shape). Both now read through
  `valueOr`, so switching between `addPartialEmailGet` and `addEmailGet` no
  longer changes the call shape. The two field TYPES still differ, but by
  design — that difference is the absent-vs-null fidelity, not an
  inconsistency to erase.
- **"the `/set` echo `PartialVacationResponse` has `FieldEcho` fields with no
  read accessor … forces the extra round-trip"** (vacation:set-echo-FieldEcho)
  → RESOLVED. The same hub reader serves the set echo: `toOpt` lets the echoed
  `PartialVacationResponse` and the fetched `VacationResponse` flow through one
  rendering path, so showing the echoed state no longer needs a re-fetch
  through the plain-`Opt` get.
- **"`Thread` exposes NO public fields … reads go through accessor funcs
  `id()`/`emailIds()` (the latter returning `lent seq[Id]`)"** (thread:th.id /
  th.emailIds) → RESOLVED. `Thread.id`/`emailIds` are direct public fields;
  `emailIds` is a `NonEmptyIdSeq`, so the "every Thread holds ≥1 Email"
  invariant (RFC 8621 §3, implicit in the spec) lives in the field TYPE
  (Tier-A) yet reads like a plain seq (`.len`, iteration) with no unwrap. The
  CLI's Thread reads did not change at all — UFCS made the flip transparent
  (the quiet success: a read-model improvement with zero consumer churn).
- **"three different read shapes for three entities — direct fields
  (`Mailbox`, `Identity`), accessor funcs (`Thread`), and the dual
  Opt/FieldEcho split (`Email`)"** (the Reading narrative; doc 16) → RESOLVED.
  Every immutable data record now reads by direct public field. Beyond
  `Thread`, the infallible-constructor / parse-enforced seals on `Account`,
  `Session`, the capability schemas (`CoreCapabilities`,
  `MailAccountCapabilities`, `SubmissionAccountCapabilities`), `Comparator` and
  `AddedItem` all flipped to public fields: `session.coreCapabilities()` is now
  `session.core`, and the capability case-objects expose a public discriminator
  plus public arms (the `SetError` idiom).
- **"`lent` ceremony on the seq/set data fields"** → RESOLVED. `lent` is
  dropped: a public field is already a zero-copy in-place read, and `lent` is
  invisible across the C FFI boundary anyway.
- **"`SetResponse.updateResults` is `Table[Id, Result[Opt[U], SetError]]`, a
  three-layer unwrap whose inner `Opt[U]` is almost always `none`"** (email
  flag:updateResults; cross-cutting Result-of-Opt update read) → RESOLVED
  (easy-read path). `SetResponse` keeps its typed three-rail tables for callers
  that need the per-item `SetError`, but S2 adds six projection iterators —
  `created`/`createFailures`, `updated`/`updateFailures`,
  `destroyed`/`destroyFailures` — so the common "successes, ignore the error
  rail" read is one `for` loop. `updated` still surfaces the RFC 8620 §5.3
  `Opt[U]` server-echo, but the caller no longer pattern-matches `Result` then
  `Opt` by hand.
- **"`session.username` / `session.apiUrl` are clean direct accessors"**
  (positive, session:accessors) → STRENGTHENED (not friction). `apiUrl` is now
  a sealed `ApiUrl` newtype (its non-empty / no-CRLF invariant lifted into the
  type) and `Account.name` a sealed `DisplayName`; both still read as direct
  fields, so the ergonomics are unchanged while the types now carry their own
  invariants. (`username` stays a plain `string`.)

Deferred to **S3** (these need NEW readers/predicates — S2 settled SHAPES
only, not new convenience, so they remain `[open]`):

- the mailbox "is this the inbox?" three-idiom friction (mailbox:mb.role) —
  wants an `isInbox` / role predicate.
- `Email.bodyValues` forcing `import std/tables` on the consumer (email
  read:bodyValues) — wants a reader that does not leak the container type.
- `decodedTextBody` / `leafTextParts` (email read:isMultipart, email
  read:decodeText) — want new body-walk readers.

RFC-conformance bonus (beyond R6; surfaced by an S2 RFC audit and recorded
honestly): `parseAccount` had been silently dropping write-implying
capabilities from a read-only account (the agent-invented "B12" rule). This
VIOLATED RFC 8620 §2 — a capability MUST be listed "if the user may use those
methods with this account", and `isReadOnly` is a separate account-wide axis (a
read-only mail account still supports `Email/get`, `Email/query`, `Mailbox/get`).
The filter made `hasCapability(ckMail)` / `mailCapability()` falsely report
that a read-only account had no mail support at all. The filter (and the
`WriteImplyingAccountCapabilities` set) is REMOVED: `parseAccount` now
preserves the server's `accountCapabilities` verbatim. The same audit corrected
several over-claimed RFC citations in docstrings (`DisplayName` control-char
rejection and `ApiUrl` non-empty/no-CRLF are defensive Layer-1 safeguards, NOT
RFC 8620 §2 text; `Thread.emailIds` non-emptiness is implicit in RFC 8621 §3,
not an explicit property constraint) — wording only, behaviour unchanged. The
agent-authored design docs were not authoritative; the RFC is.

Standing note (NOT an S2 item, not a regression): displaying a core limit
still needs `.toInt64` — the limits are `UnsignedInt` distincts
(session:limits). S2 made each limit a direct public field on
`CoreCapabilities` (so `core.maxCallsInRequest` drops the accessor parens), but
the `.toInt64` projection to print or do arithmetic is unchanged.

Still open after S2 (tracked to their sub-projects): the read-model is now
uniform, but the convenience readers that turn a settled shape into a one-liner
— `isInbox`, `decodedTextBody`, `leafTextParts`, a `bodyValues` reader — are
S3; the sealing-chain ceremony and the missing `connect()` / bare-get /
`sendPlainText` one-shots are S4; and the snapshot-integrity freeze-blocker is
its own track. The read-model unevenness the bench reported is gone.

## S3 resolution — body readers, role predicates, preflight sugar

Sub-project **S3** shipped the convenience readers and predicates the S2 pass
left `[open]` — the symbols that turn a settled SHAPE into a one-liner. The
design throughout is the libcurl/SQLite split, not the OpenSSL one: a **rich
primitive** that carries every signal (`bodyValue`, with `isTruncated` /
`isEncodingProblem`) sits beside a **simple convenience** that covers the
overwhelmingly common case (`decodedTextBody`); capability resolution is a
**uniform bare-`AccountId`** resolve (`requireMail` and siblings); and where a
roll-up would bake one library's opinion into the type, S3 ships **no roll-up at
all** (the nine mailbox rights stay orthogonal). The inline finding lines keep
their `[open]` tag, matching the S1/S2 observe-only convention; the mapping
lives here. The CLI was re-benched against these symbols — every adoption below
is in the tree and compiles public-surface-only. Mapping (finding → fix):

- **"no `canRead`/`canMutate`/`canDelete` (or any) roll-up over `MailboxRights`'
  nine independent `may*` bools (tracker C4)"** (mailbox:rightsSummary) →
  RESOLVED AS WON'T-FIX (by decision, not by symbol). S3 ships NO rights
  roll-up: the nine RFC 8621 §2 `may*` rights are orthogonal (read; the four
  write components; the three admin components; submit), and any blessed
  `canWrite` digest would freeze one library's opinion of which flags constitute
  "write" into the API — the OpenSSL-style over-abstraction the bench rejects.
  The CLI keeps its own `rwas` digest (`commands/mailbox.nim`) as a *consumer*
  choice; the hub stays primitives-only. (libcurl exposes the bytes; it does not
  decide what they mean.)
- **"'is this the inbox?' needs one of three divergent idioms — `role.kind ==
  mrInbox`, the snapshot-UNLISTED const `roleInbox`, or
  `parseMailboxRole("inbox").get()`"** (mailbox:mb.role; S2-deferred) →
  RESOLVED. `isInbox(mb)` is the one blessed spelling; `hasRole(mb, kind)`
  generalises it to any well-known role. The CLI adopted both: `mb.isInbox` in
  `commands/email_query.nim` (`resolveInbox`) and `mb.hasRole(mrDrafts)` /
  `mb.hasRole(mrSent)` in `commands/email_send.nim` (`resolveRoles`), deleting
  the per-mailbox `for role in mb.role` unwrap at each site.
- **"decoding the text body is a manual `textBody`-walk joined against the
  `bodyValues` table by partId; every consumer re-implements this … the genuine
  residual ask is an `email.leafTextParts` iterator or an
  `email.decodedTextBody(): string`"** (email read:decodeText, email
  read:isMultipart; S2-deferred) → RESOLVED. Both shipped. `decodedTextBody(e):
  Opt[string]` joins the `text/plain` leaves (case-insensitive media-type match,
  RFC 8621 §4.1.4 sequential order), `none` when none was fetched — the single
  most common read is now one call. `leafTextParts` iterates the display leaves
  for callers that need per-part access. The CLI's hand-written `decodeTextBody`
  func is DELETED (`commands/email_read.nim`); the read is
  `e.decodedTextBody().valueOr(…)`.
- **"`Email.bodyValues` is a `std/tables` Table, but the hub re-exports
  `results` and NOT std/tables, so the consumer must add `import std/tables`
  solely to read a returned field"** (email read:bodyValues; S2-deferred) →
  RESOLVED. `bodyValue(e, pid): Opt[EmailBodyValue]` is a total,
  `std/tables`-free lookup — no `KeyError`, no container-type leak. The CLI
  DROPPED its `import std/tables` (it existed only for the `withValue` join);
  since UnusedImport is a hard error here, the drop is load-bearing proof the
  leak is gone.
- **"a compile-time-constant byte cap (65536) must be sealed through
  `parseUnsignedInt(65536).get()` then re-wrapped `Opt.some(...)` … no
  `EmailBodyFetchOptions.textBodies(maxBytes)` convenience"** (email
  read:maxBodyValueBytes) → RESOLVED (the convenience half). `textBodies(maxBytes)`
  / `textBodies()` build the fetch options with the `bvsText` scope set and the
  `maxBodyValueBytes` `Opt` wrapped internally; the CLI passes
  `bodyFetchOptions = textBodies(parseUnsignedInt(65536).get())`. The residual
  `parseUnsignedInt(…).get()` to mint the `UnsignedInt` is the standing
  no-int-literal-helper note, not a `textBodies` gap.
- **"`EmailBodyValue.isTruncated` / `.isEncodingProblem` are plain bools the
  happy path silently ignores; nothing ties a truncated value back to the
  `maxBodyValueBytes` cap"** (email read:truncation) → RESOLVED (read path).
  `bodyValue` is the rich primitive that carries `isTruncated` /
  `isEncodingProblem`, deliberately NOT folded into the `decodedTextBody`
  convenience (rich primitive vs simple convenience — the consumer opts into the
  detail). The CLI now reads it: after the `decodedTextBody` print it walks
  `leafTextParts` and flags any `bodyValue(…).isTruncated`, closing the loop
  back to the `textBodies` cap.
- **"a constant page size is a triple wrap `Opt.some(parseUnsignedInt(20).get())`
  … no plain-int convenience or `withLimit(20)`"** (email query:QueryParams.limit)
  → RESOLVED (the window half). `limit(count)` returns a `QueryParams` with the
  field set and the `Opt` wrapped; the CLI uses `limit(parseUnsignedInt(20).get())`
  / `limit(parseUnsignedInt(10).get())`, dropping the
  `QueryParams(limit: Opt.some(…))` field name + Opt wrap. (The `parseUnsignedInt`
  seal is the same standing no-int-literal note.)
- **"there is NO plain-text body shorthand anywhere on the hub … requires
  hand-building a 4-layer chain `BlueprintBodyValue -> BlueprintLeafPart{bpsInline}
  -> BlueprintBodyPart{text/plain} -> flatBody`"** (email send:no-body-helper,
  **high**) → RESOLVED (the S3 half). `plainTextBody(text)` mints the inline
  `text/plain` leaf and its creation-time `partId` in one call, returning the
  `EmailBlueprintBody` `parseEmailBlueprint` expects. The CLI's
  `buildDraftBlueprint` 4-layer chain (and its `parsePartIdFromServer("text")`)
  collapses to `let draftBody = plainTextBody(body)`. The one-shot
  `sendPlainText(…)` that would ALSO wire the submission + onSuccess move
  remains S4 — `plainTextBody` is only the body half.
- **"`primaryAccount(ckMail)` returns `Opt[AccountId]` forcing an unwrap, and
  requires the caller to first discover the `ckMail` enum value … rather than
  offering a mail-specific shorthand like `session.mailAccountId()`"**
  (session:capability; S1 left `requirePrimaryAccount` PARTIALLY RESOLVED, the
  mail-specific shorthand deferred to S3) → RESOLVED. The three capability
  resolvers ship: `requireMail` / `requireSubmission` / `requireVacation`, each a
  uniform bare-`AccountId` resolve on the `JmapError` rail (`jeSession` when no
  account advertises the capability), primary-preferred with a per-account
  fallback (RFC 8620 §2) — no `ckMail` enum at the call site, no `Opt` unwrap.
  The CLI adopted `requireMail` in both the shared `connect()`
  (`commands/cli_session.nim`) and the verbose onboarding probe
  (`commands/session.nim`), replacing `requirePrimaryAccount(ckMail)`.
  `requireSubmission` / `requireVacation` are the submission/vacation siblings of
  the same shape; the CLI routes those entities through its single shared mail
  account, so it does not separately resolve them, but they close the identical
  finding for those two capabilities.
  The capability-resolution reconcile then removed the interim general-strict
  resolver and its dead `sfPrimaryAccountAbsent` session fault, so the resolver
  family is uniformly named-soft with one session-fault reason
  (`sfCapabilityAbsent`); the designated-primary-specific need is served by the
  public `session.primaryAccount(kind): Opt`.

Still open after S3 (tracked to their sub-projects): the readers and predicates
are now one-liners, but the request-lifecycle one-shots that still cost the full
five-symbol chain — `connect()`, a bare-Get combinator, and the `sendPlainText`
one-shot (the submission half `plainTextBody` does not cover) — are S4; the
sealing-chain ceremony around them is S4; the standing `parseUnsignedInt(…).get()`
no-int-literal seal rides along with it; and the snapshot-integrity freeze-blocker
is its own track. The read-model convenience the bench asked for is in.
