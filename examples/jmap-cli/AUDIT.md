# jmap-cli API ergonomics audit (P29 / tracker C1)

This ledger is the deliverable of the sample-consumer bench. The CLI is
the instrument; this file is the product. Each line records one
awkwardness encountered while writing the CLI against the **public
API only** (`import jmap_client` [+ `jmap_client/convenience`]).

**Status convention (Phase 2, triage).** Phase 1 logged every finding
`[open]` (observe-only — friction felt as a newcomer would feel it). The
six-sub-project API refactor (S0–S4) is now complete and merged, and this
pass dispositions each inline finding against the per-sub-project
resolution sections below. Every `[open]` is replaced by exactly one of:
`[resolved-Sn: <symbol>]` (fixed by sub-project Sn, naming the shipped
symbol — or a deliberate "won't-fix by Sn decision"); `[affirmed]` (a
positive finding, a win not friction, optionally "strengthened by Sn");
`[accepted-as-trade-off: <reason>]` (a conscious, documented cost);
`[filed-as-Cn: <gap>]` (a genuine residual gap, tracked as a new Section C
item). A finding may carry a PRIMARY tag plus a RESIDUAL pointer when its
common case is resolved but a deeper gap remains.

**Format.** `- <command>:<call-site>: <description> [disposition]`

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
- **Findings: 98 ledger lines** — the build-environment, positives,
  per-command, cross-cutting and Phase-0 lines. After **Phase 2 triage**
  (90 inline findings carry a disposition; the other 8 `[open]` substrings
  are prose references to the old observe-only convention), the breakdown is:
  **resolved-S0 7, resolved-S1 9, resolved-S2 11, resolved-S3 9,
  resolved-S4 22, affirmed 14, accepted-as-trade-off 11, filed-as-Cn 7**.
  Many resolutions also carry a RESIDUAL pointer (6 residual
  accepted-as-trade-off, and residual `filed-as-C11/C12/C15/C16`) for a
  deeper gap left after the common case was fixed. So **58 of 90 inline
  findings are resolved by S0–S4**, 14 were positives all along, 11 are
  documented trade-offs, and 7 are filed to Section C — four fresh items (C17
  the changes-combinator gap; C20 a query filter/sort builder; C21 a per-type
  state accessor; C22 typing the vacation singleton id) plus two against the
  existing C3 (the by-ids one-shots collapse the lifecycle but not the
  `Opt.some(direct(@[id]))` input wrapping). Each filed-as-Cn item is registered
  in Section C of `docs/TODO/pre-1.0-api-alignment.md` (alongside the
  residual-pointer items C11–C16 and the done-in-triage C18–C19).
- **Blocked commands (inexpressible with hub-public symbols): NONE.**
  Every command compiles and round-trips through `import jmap_client` only
  (S4 dissolved the P6 `jmap_client/convenience` quarantine, so the
  combinators are now on the always-on hub) — verified both in-tree under
  the library's full strict battery and by a pristine out-of-tree build with
  zero warnings. The Phase-1 near-blocker — the snapshot-integrity finding,
  where a strict "only `public-api.txt` counts" reading would have made the
  CLI un-expressible because `newBuilder`/`freeze`/`client.send` were
  reachable-but-unlisted — is **resolved-S0**: the `api_oracle.nim`
  compiler-as-library oracle now enumerates the full hub surface, so the
  freeze-blocking tooling defect is cleared.
- **Headline (high-severity) findings — all now resolved:** the frozen
  `public-api.txt` snapshot omitting the request-lifecycle bookends
  (resolved-S0); the 4-call connect preamble / C5/C8 wrapper trigger
  (resolved-S4 `connect`); the pervasive sealing-chain ceremony (resolved-S4
  one-shots, with the standing `parseUnsignedInt` seal as a documented
  residual); and on the send path — no plain-text body helper (resolved-S4
  `sendPlainText`, body via S3 `plainTextBody`), the misleading
  `addEmailSubmissionAndEmailSet` two-creation wiring (resolved-S4), and the
  untyped `emailId` forward-reference (resolved-S4 typed `creationRef`).

## Build environment (Phase 0)

Facts established while standing up the bench, before any command ran.
These are about the *build contract*, not a specific call site.

- build:module-name: the entry module cannot be named `jmap-cli.nim` —
  Nim module names must be valid identifiers, so a hyphen is rejected
  (`invalid module name: 'jmap-cli'`). Named the source `jmap_cli.nim`;
  the run-name `jmap-cli` comes from `-o:`. Incidental CLI plumbing, not
  an API finding. [accepted-as-trade-off: incidental CLI plumbing, not an API finding]
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
  without the library's warning-as-error battery. A genuine positive. [affirmed: the no-strictness-leak experiment confirms the library imposes none of its battery on consumers]
- build:transport-deps: `import jmap_client` transitively pulls in
  `std/httpclient`, `std/asyncdispatch`, `std/asyncfutures`, `std/random`
  — the default L4 transport is std-`httpclient`-based. A consumer who
  only wants the typed protocol core still links the async machinery.
  [accepted-as-trade-off: the default L4 transport is std/httpclient-based (P22 sync-first); a typed-core-only consumer still links the async machinery]

## Positive findings (what is genuinely good)

- build:compile: the smoke entry (`import jmap_client` + one smart
  constructor) compiled clean on the first valid-module-name attempt,
  even under the inherited strict battery. The public surface imports
  without ceremony. [affirmed]
- session:results-reexport: `import jmap_client` re-exports the `results`
  vocabulary (`Result`, `Opt`, `ok`, `err`, `valueOr`, `?`, `Opt.some/none`)
  — no separate `import results` needed. One import gets the error rail. [affirmed]
- session:accessors: `session.username` / `session.apiUrl` are clean direct
  accessors; live Stalwart returns `alice` / `http://stalwart:8080/jmap/`
  (the plan's worry that `username` might be empty did not materialise). [affirmed: strengthened by S2 (ApiUrl/DisplayName newtypes)]
- identity:fields: `Identity`'s `id`/`name`/`email` are direct public fields
  — reading a list of identities is a clean two-liner with no Opt/FieldEcho
  ceremony. The entity read-models are at their best when flat. [affirmed]
- session:type-safety: the verbose lifecycle is *type-safe* — `freeze`
  consumes the builder by `sink` (a second `send` of the same `BuiltRequest`
  is a compile error), and the `ResponseHandle[T]` returned by `add*Get`
  binds the get's result type, so `dr.get(handle)` cannot be mis-typed.
  Ceremony bought genuine compile-time guarantees. [affirmed]
- email query:back-reference type-safety: `reference[seq[Id]](queryH, …)`
  threads the Email/query result ids into Email/get within ONE request and
  is fully type-checked — no manual id plumbing, no second round-trip, and
  the generic pins the referenced shape to `seq[Id]`. The ceremony is real
  but it buys a genuinely safe server-side back-reference. [affirmed]
- email send:atomic-send-works: despite the friction, the hard thing is
  POSSIBLE and ATOMIC — a single request created the draft, submitted it,
  and (via `onSuccessUpdateEmail`) moved it to Sent, with live delivery
  alice->bob confirmed. The RFC 8621 §7 onSuccess semantics are faithfully
  exposed and the whole compound is one network round-trip. The API does
  not block the use case; it taxes the path to it. [affirmed]
- search:compound-ergonomics: `addEmailQueryWithSnippets` + `getBoth(chain)`
  is the API at its ERGONOMIC BEST — one call, one extraction, `.query.ids`
  + `.snippets.list`, the query->snippet back-reference wired and type-safe.
  When the API ships a purpose-built compound, the result is excellent; the
  problem is only that this one is invisible in the frozen contract. [affirmed]
- convenience:full-email-path: `addEmailQueryThenGet` returns FULL `Email`
  (plain `Opt` fields, no `FieldEcho`) in one call + one `getBoth` — a
  genuinely smoother read than the hand-wired partial back-reference, and
  the P6 quarantine (opt-in import) is correctly applied so the core stays
  uncontaminated. This is the model the send path is crying out for. [affirmed: strengthened by S4 (quarantine dissolved; now on the always-on hub)]
- build:no-strictness-leak: the **pristine out-of-tree build** (sources
  copied outside the repo, built with only `--mm:arc --threads:on
  --panics:on`, no `config.nims`) compiles `SuccessX` with zero warnings —
  proving the API imposes none of its own warning-as-error/strictDefs
  battery on consumers. The strict contract is the *library's* discipline,
  not a tax on its users. [affirmed]

## Findings by command

### session
- session:connect: obtaining one usable client costs THREE sequential smart-constructor unwraps (`directEndpoint().valueOr`, `basicCredential().valueOr`, `initJmapClient().valueOr`) — sealing-chain ceremony with no single `connect(url, user, pass)` convenience shorthand on the hub [resolved-S4: connect(url, user, pass) folds directEndpoint+basicCredential+initJmapClient onto the rail]
- session:connect: NO hub-public `ClientError` constructor exists (only `transportError` -> `TransportError`; no `clientError`, no lift from `ValidationError`/`TransportError`), so a consumer cannot return its failures on the library's `JmapResult` rail and is forced to invent a CLI-local error type (`cli_session` uses `string`) and `.message`-stringify at every boundary [resolved-S1: jmapValidation/jmapTransport/jmapRequest/jmapSession minting constructors + toJmapError/lift]
- session:connect: the `?` operator cannot bridge a `Result[_, ValidationError]` (smart constructors, `initJmapClient`) into a `JmapResult[_]`/`ClientError` function — the two error rails do not auto-convert, so every constructor call needs an explicit `.valueOr: return err(...)` instead of `?` [resolved-S1: ?parseX(...).lift folds construction onto the single JmapError rail]
- session:lifecycle: the proving read costs a five-symbol chain — `client.newBuilder()` then `add*Get(b)` returning a `(RequestBuilder, ResponseHandle)` tuple then `b2.freeze()` (sink) then `client.send().valueOr` then `dr.get(handle).valueOr` — four unwraps plus manual threading of the opaque handle and the re-bound builder `b2` through the chain [resolved-S4: getMailboxes/getEmails/... bare-get one-shots collapse the five-symbol lifecycle]
- session:capability: `primaryAccount(ckMail)` returns `Opt[AccountId]` forcing an unwrap, and requires the caller to first discover the `ckMail` enum value (a `CapabilityKind` back-reference) rather than offering a mail-specific shorthand like `session.mailAccountId()` (confirms tracker C5/C8) [resolved-S3: requireMail/requireSubmission/requireVacation named-soft resolvers]
- session:limits: `CoreCapabilities` limits return `UnsignedInt` with only a `.toInt64` projection (no `toInt`, no snapshot-listed `$`), so every limit read needs `.toInt64` before printing/arithmetic; `parseUnsignedInt` also takes `int64`, not `int` [resolved-S2: direct field core.maxCallsInRequest; residual accepted-as-trade-off: the .toInt64 projection]
- session:config: no config-file/loader in the API; the consumer hand-reads three env vars itself [accepted-as-trade-off: config loading is the application's responsibility, not a protocol library's — libcurl/SQLite parse no app config]

### mailbox
- mailbox:dr.get(handle): typed extraction is the same repeated ceremony as `session` — `newBuilder` -> `add*Get` (tuple) -> `freeze` -> `send.valueOr` -> `dr.get(handle).valueOr` -> iterate `.list`; no single-call get shorthand for the common "fetch all of one entity" case [resolved-S4: getMailboxes bare-get one-shot]
- mailbox:rightsSummary: no `canRead`/`canMutate`/`canDelete` (or any) roll-up over `MailboxRights`' nine independent `may*` bools (tracker C4) — every consumer hand-rolls an ACL digest; a hub-public rights predicate/digest helper would remove guesswork about which flags constitute "can write" [resolved-S3: won't-fix — rights stay orthogonal (RFC 8621 §2 may* bools), no blessed canWrite digest]
- mailbox:mb.role: role is `Opt[MailboxRole]`; display needs an Opt unwrap then `identifier`/`$`, and "is this the inbox?" needs one of three divergent idioms — `role.kind == mrInbox`, the snapshot-UNLISTED const `roleInbox`, or `parseMailboxRole("inbox").get()` (a sealing chain) — none discoverable from the frozen snapshot [resolved-S3: isInbox/hasRole; the snapshot-unlisted roleInbox is resolved-S0]

### email query
- email query:QueryParams.limit: a constant page size is a triple wrap `Opt.some(parseUnsignedInt(20).get())` — `int64` -> `Result[UnsignedInt]` -> `.get()` -> `Opt.some`; no plain-int convenience or `withLimit(20)` [resolved-S3: limit() window helper; residual accepted-as-trade-off: the parseUnsignedInt seal]
- email query:filter: `EmailFilterCondition` is a raw object literal with every field `Opt[...]`, so a two-field filter needs `Opt.some` on each; `addEmailQuery.filter` is `Opt[Filter[EmailFilterCondition]]`, so a single condition double-wraps as `Opt.some(filterCondition(cond))`; `notKeyword` takes `Opt[Keyword]` (not a string); no filter-builder DSL [filed-as-C20: a query filter/sort builder DSL]
- email query:sort: `addEmailQuery.sort` is `Opt[seq[EmailComparator]]` — one comparator becomes `Opt.some(@[plainComparator(...)])`; no single-comparator overload [filed-as-C20: a query filter/sort builder DSL]
- email query:reference: the back-reference `reference[seq[Id]](queryH, mnEmailQuery, rpIds)` makes the caller restate the producing method (`mnEmailQuery`) that `queryH` already encodes, pick the right `RefPath` member (`rpIds` among nine JSON-pointer variants), AND supply the generic `seq[Id]`, then wrap `Opt.some(...)`; a `queryH.idsReference()` helper would erase three enum-discovery foot-guns [resolved-S4: queryEmails one-shot folds Email/query -> Email/get and reads .query.ids/.get.list]
- email query:properties: `NonEmptySeq[EmailGetProperty]` is REQUIRED but declared after the defaulted `ids`, so it must be passed by name; building it is `parseNonEmptySeq(@[...]).get()` — a `.get()` sealing chain on a literal that cannot be empty [accepted-as-trade-off: the standing smart-constructor seal on a compile-safe literal, same class as the parseUnsignedInt no-int-literal note]
- email query:PartialEmail dual optionality: `id`/`threadId`/`receivedAt`/`preview` are `Opt[T]` but `subject`/`fromAddr`/`to`/`cc`/`bcc` are `FieldEcho[T]`; the consumer must remember which read style applies per field [resolved-S2: FieldEcho.valueOr reader unifies the read shape across Opt and FieldEcho]
- email query:FieldEcho: `FieldEcho[T]` has NO read accessor on the hub (only the `fieldAbsent`/`fieldNull`/`fieldValue` constructors + the public `value*` field), so reading subject/fromAddr requires a hand-written `case fe.kind of fekValue: fe.value of fekAbsent, fekNull: default` — every consumer reinvents `fieldEchoOr` [resolved-S2: FieldEcho.valueOr reader (+ isValue/isNull/isAbsent/items/toOpt)]
- email query:tooling: the `egp*` selectors and `kwSeen` (and `kwDraft`/`kwFlagged`/...) are `*`-exported and COMPILE via `import jmap_client`, yet are ABSENT from public-api.txt — `api_surface.nim` records a decl only when the logical line STARTS with a `DeclKinds` keyword, so grouped `const`-block members are silently dropped. Snapshot-strict consumers must fall back to `parseEmailGetProperty("id").get()` / `parseKeyword("$seen").get()` per value [resolved-S0: api_oracle.nim compiler-as-library oracle now lists every grouped-const member]
- email query:two error rails in one flow: `client.send` returns `JmapResult` (ClientError) while `dr.get(handle)` returns `Result[_, GetError]` — the call site cannot use one uniform `?`/`valueOr` style and bridges `ClientError` vs `GetError` manually [resolved-S1: send/get both return JmapError; method-level errors are MethodOutcome data on the ok branch]

### email read
- email read:maxBodyValueBytes: a compile-time-constant byte cap (65536) must be sealed through `parseUnsignedInt(65536).get()` then re-wrapped `Opt.some(...)` — a smart-constructor+get+Opt ceremony for a literal that can never fail; no `UnsignedInt` literal helper, no `EmailBodyFetchOptions.textBodies(maxBytes)` convenience [resolved-S3: textBodies()/textBodies(maxBytes) window helpers; residual accepted-as-trade-off: the parseUnsignedInt seal]
- email read:ids: a single id is `Opt.some(direct(@[id]))` (seq-wrap + `direct` + `Opt.some`); the in-tree `directIds` shorthand that would remove the nesting is ABSENT from public-api.txt, and the plan's `Opt.some(directIds(...))` is a hard double-Opt type error (`directIds` already returns `Opt[Referencable[seq[Id]]]`) — an easy footgun with no compiler hint until call time [resolved-S0: api_oracle now lists directIds; the double-Opt footgun was a snapshot-omission consequence]
- email read:isMultipart: `EmailBodyPart` is a case object on the `isMultipart` bool, so reaching a leaf's `partId`/`blobId` means matching the `of false` arm. (The consumer does NOT enable `strictCaseObjects` — it is a src/-only per-file pragma, verified by the pristine build — so a plain `if not part.isMultipart:` reads the field cleanly; there is no compiler-forced `case`.) The genuine residual ask is an `email.leafTextParts` iterator or an `email.decodedTextBody(): string` so a mail client need not re-implement the textBody-walk + bodyValues-by-partId join at all [resolved-S3: decodedTextBody/leafTextParts; residual filed-as-C11: EmailLeaf view type]
- email read:bodyValues: `Email.bodyValues` is a `std/tables` Table, but the hub re-exports `results` and NOT std/tables, so the consumer must add `import std/tables` solely to read a returned field — inconsistent and non-obvious [resolved-S3: bodyValue(e, pid) total std/tables-free reader]
- email read:decodeText: decoding the text body is a manual `textBody`-walk joined against the `bodyValues` table by partId; every consumer re-implements this part-id->value join. No `email.decodedTextBody(): string` exists despite it being the single most common read [resolved-S3: decodedTextBody(e): Opt[string]]
- email read:truncation: `EmailBodyValue.isTruncated` / `.isEncodingProblem` are plain bools the happy path silently ignores; nothing ties a truncated value back to the `maxBodyValueBytes` cap, so correctness depends on the consumer remembering to check two booleans [resolved-S3: bodyValue rich primitive surfaces isTruncated/isEncodingProblem for the textBodies cap loop]
- email read:id-parser-choice: the command must choose between strict `parseId` and lenient `parseIdFromServer` for a CLI-supplied id with no guidance — the strict/lenient pair (a sensible internal Postel's-law split) leaks to the consumer as a decision [accepted-as-trade-off: a principled Postel strict/lenient split]

### email flag
- email flag:set-construction: a single-email flag pays a two-layer sealing ceremony — `initEmailUpdateSet(ops).valueOr` then `parseNonEmptyEmailUpdates(@[(eid, updSet)]).valueOr` — so the "update ONE email" case still wraps the whole-container `NonEmptyEmailUpdates`; a one-shot `addEmailUpdate(acc, id, @[ops])` shorthand is missing [resolved-S2: projection iterators; residual filed-as-C15: no Email/set write one-shot]
- email flag:accumulating-rail: both `initEmailUpdateSet` and `parseNonEmptyEmailUpdates` return `Result[_, seq[ValidationError]]` for what is conceptually one construct, forcing `error.mapIt(it.message).join("; ")` rendering instead of the single `.message` that `parseId`/`parseKeyword`/`parseAccountId` give — two error-rail shapes in one command [resolved-S1: NonEmptySeq[ValidationError] folds into jeValidation; one err.message joins every violation]
- email flag:updateResults: the per-item success payload is `Result[Opt[PartialEmail], SetError]` — a Result-of-Opt double layer whose inner `Opt[PartialEmail]` is almost always `none` for a flag, so callers check `res.isOk` and discard the Opt; the three-layer unwrap reads awkwardly [resolved-S2: created/updated projection iterators; residual accepted-as-trade-off: the per-item Result-of-Opt read for callers needing SetError]
- email flag:SetError: only `se.message`/`se.description`/`se.rawType` are flat; structured detail (invalid property names, etc.) needs a `kind` case-match or the separate `mail_errors` helpers, which are easy to miss [accepted-as-trade-off: the structured detail is available via the kind case / mail_errors helpers; the flat message/description/rawType cover the common render]

### email move
- email move:repetition: identical triple-sealing chain to `email flag` (`initEmailUpdateSet` -> `parseNonEmptyEmailUpdates` -> `addEmailSet(update = Opt.some(...))`) — the only difference is `moveToMailbox(id)` vs `markRead()`; the recurring boilerplate is a cross-cutting wrapper trigger [resolved-S2: projection iterators; residual filed-as-C15: no Email/set write one-shot]
- email move:Opt-vs-value: `addEmailSet.update` is `Opt[NonEmptyEmailUpdates]` (needs an explicit `Opt.some(updates)`), whereas `addVacationResponseSet.update` takes its update set BY VALUE — the two `/set` builders disagree on the Opt-vs-value convention, so the consumer cannot muscle-memory one shape [accepted-as-trade-off: principled, not arbitrary — the four collection /set builders take update by `Opt` (it co-exists with optional create/destroy) while the vacation singleton takes it by value (no `Opt.none` "no-update" case — you omit the call), so each shape encodes its entity's operation model (P16); forcing uniformity would admit a meaningless `Opt.none` singleton call]
- email move:moveToMailbox: the DSL verb itself reads well and is total — `moveToMailbox(id)` clearly expresses full-replace mailbox membership; the friction is entirely in the sealing/dispatch envelope around it [affirmed]

### email send
_The longest section by design — this is the highest-friction public path. It nonetheless works end-to-end: a single request created the draft, submitted it, and moved it to Sent on success; live delivery alice->bob was verified (bob's inbox received `hello from jmap-cli`)._

Blueprint / body construction:
- email send:no-body-helper (**high**): there is NO plain-text body shorthand anywhere on the hub (no `textBody(str)`, no `plainTextBody`, no `initBlueprintLeafPart`). The single most common case — a plain string body — requires hand-building a 4-layer chain `BlueprintBodyValue -> BlueprintLeafPart{bpsInline} -> BlueprintBodyPart{text/plain} -> flatBody` before `parseEmailBlueprint`. This is the headline send-ergonomics gap [resolved-S4: sendPlainText one-shot, body via the S3 plainTextBody(text) leaf]
- email send:parsePartIdFromServer: the ONLY hub-public `PartId` mint is `parsePartIdFromServer`, whose name and docstring say "lenient, server-provided, receive-side (Postel)", yet the SEND path MUST call it to create a client-chosen creation-time partId; the plan's `parsePartId` does not exist — a discoverability/naming trap (a send-side call named `FromServer`) [resolved-S4: plainTextBody/sendPlainText mint the partId internally; residual filed-as-C12: parsePartIdFromServer send-side naming]
- email send:raw-case-literals: `BlueprintLeafPart` and `BlueprintBodyPart` are constructed as raw case-object literals (no smart constructor), so the caller hand-writes the discriminator literals `source: bpsInline` / `isMultipart: false` and must know which fields belong to which branch — counter to "smart constructors only / raw constructors private" [resolved-S4: plainTextBody/sendPlainText; residual filed-as-C12: still-public raw Blueprint* part constructors]
- email send:contentType-stringly: `BlueprintBodyPart.contentType` is a bare `string`, but `parseEmailBlueprint` rejects anything != "text/plain" for a text body (`ebcTextBodyNotTextPlain`) — a stringly-typed field guarded by deferred validation, with no compile-time aid [resolved-S4: plainTextBody mints the text/plain leaf internally; no stringly contentType at the call site]
- email send:blueprint-error-rail: `parseEmailBlueprint` returns `Result[_, EmailBlueprintErrors]` — a custom OPAQUE accumulator (not `seq[ValidationError]`), with no aggregate render-to-string helper, so the caller iterates `items`/`head` and joins `.message` itself [resolved-S1: EmailBlueprintErrors retired; parseEmailBlueprint returns NonEmptySeq[ValidationError] into jeValidation]
- email send:recipient-double-wrap: `parseEmailBlueprint`'s `fromAddr`/`to` are `Opt[seq[EmailAddress]]`, so a single recipient is `Opt.some(@[addr])` (Opt + seq) — ceremony for the common single-recipient case [resolved-S4: sendPlainText takes fromAddr/to/cc/bcc directly; no Opt+seq blueprint wrap at the call site]

Submission + the compound two-creation wiring (the centrepiece):
- email send:builder-does-not-create (**high**): `addEmailSubmissionAndEmailSet` does NOT create the email — its `create` table holds ONLY `EmailSubmissionBlueprint`; the "AndEmailSet" suffix is the SERVER's implicit Email/set emitted from `onSuccessUpdateEmail` (an UPDATE, not a create). The draft must be created by a SEPARATE `addEmailSet(create=...)` on the SAME builder. The builder name actively misleads; no convenience ties an Email create to a submission [resolved-S4: sendPlainText one-shot creates the draft and wires the submission in one call]
- email send:emailId-no-forward-ref (**high**): `EmailSubmissionBlueprint.emailId` is a plain `Id` with NO typed forward-reference, so pointing the submission at the freshly-created draft in one request has no type-level representation; the only hub-public encoding is `parseIdFromServer("#" & $draftCid)` — abusing the server-lenient parser to smuggle a client back-reference. The discoverable strict `parseId("#draft")` REJECTS the '#' (verified live) [resolved-S4: sendPlainText references the draft via the typed creationRef forward-reference; the #-smuggle is internal]
- email send:onSuccess-key: `onSuccessUpdateEmail` is keyed by `creationRef(subCid)` — the SUBMISSION's creation id, NOT the email's — a non-obvious indirection enforced only at runtime; easy to mis-key with the draft cid [resolved-S4: sendPlainText wires the onSuccess Drafts->Sent move internally (RFC 8621 §7.5.1)]
- email send:uncopyable-move: `addEmailSubmissionAndEmailSet` returns `Result[(RequestBuilder, EmailSubmissionHandles), ValidationError]` wrapping an UNCOPYABLE `RequestBuilder`, so the Ok value cannot be read with `.get()`/`.value` — the caller must `var r = ...; if r.isErr: ...; let (b, h) = move(r.value)`. Bespoke move ceremony unlike every other (bare-tuple) `add*` builder [resolved-S4: sendPlainText returns a flat SentEmail; no uncopyable-builder move at the call site]
- email send:raw-envelope: `SubmissionAddress(mailbox:, parameters:)` and `Envelope(mailFrom:, rcptTo:)` are raw object literals with no smart constructor; the overwhelmingly common no-params recipient must spell `Opt.none(SubmissionParams)`, and there is no `rcpt(mailbox)` / `envelope(from, @[to])` shorthand [resolved-S4: sendPlainText derives the envelope from fromAddr/to internally; no raw SubmissionAddress/Envelope literal at the call site]
- email send:sealing-pileup: four+ sealing constructors precede the build (`parseNonEmptyMailboxIdSet`, `parseEmailAddress`×2, `parsePartIdFromServer`, `parseRFC5321Mailbox`×2, `parseNonEmptyRcptList`, `parseEmailSubmissionBlueprint`, `initEmailUpdateSet`, `parseNonEmptyOnSuccessUpdateEmail`), each a separate Result the caller threads — some single-`ValidationError`, some accumulating `seq[ValidationError]`, the blueprint a third opaque shape: the caller adapts between THREE error-rail shapes in one command [resolved-S4: sendPlainText collapses the sealing pile-up; the three error-rail shapes unify on the JmapError rail (S1)]
- email send:three-response-shapes: one logical "send" yields three response shapes — the draft Email/set (`emailHandle`) plus the compound `getBoth` -> `CompoundResults{primary, implicit}` where `primary` is the EmailSubmission/set and `implicit` is the onSuccess Email/set update; nothing in `.primary`/`.implicit` says which carries `createResults` vs `updateResults` [resolved-S4: sendPlainText returns a flat SentEmail; no three-response-shape extraction at the call site]
- email send:nested-id-read: reading the created submission id is a nested rail — `getBoth().valueOr` then `primary.createResults` table-lookup then `res.value.id` (three unwraps) [resolved-S4: sendPlainText returns SentEmail{emailId, submissionId} directly]
- email send:freeze-not-build: the builder finaliser is `freeze` (sink), there is no `build`; combined with its absence from the snapshot, a discoverability trap at the dispatch site [resolved-S0: api_oracle now lists freeze (the snapshot-absence half); sendPlainText removes the finaliser from the common path]

### email sync
- email sync:state-roundtrips (POSITIVE): a `JmapState` cursor round-trips through `parseJmapState` (it is even in public-api.txt), so a consumer CAN persist a sync position to disk and resume after a process restart — the state is not trapped inside a live response object. This is exactly what incremental sync needs and the API gets it right [affirmed]
- email sync:changes-to-get-created-only (**medium**): the convenience `addEmailChangesToGet` (and its `*ChangesToGet` siblings) back-references ONLY the `/created` path into the Email/get, so the `ChangesGetResults.get.list` carries created records but NOT updated ones. A mail client doing incremental sync overwhelmingly cares about UPDATED messages (read/flag/move changes), yet to fetch their bodies it must abandon the one-call convenience and hand-compose `addEmailChanges` + `addPartialEmailGet(ids = reference[seq[Id]](ch, mnEmailChanges, rpUpdated))` — the convenience covers the rarer case and drops to manual for the common one (live-confirmed: flagging an email yielded `updated=1` with an empty `get.list`) [filed-as-C17: changes combinator covers only /created; /updated needs hand-composition]
- email sync:state-acquisition: `Email/changes` diffs against the Email OBJECT state (`GetResponse.state`), not the query state, and no command surfaces that state by default — the CLI had to issue an empty-ids `Email/get` purely to read `resp.state` as the initial cursor; a `session`- or get-level "current state per type" accessor would remove the bootstrap round-trip [filed-as-C21: a per-type current-state accessor to remove the changes bootstrap round-trip]

### thread
- thread:th.id / th.emailIds: `Thread` exposes NO public fields (empty type-shape); reads go through accessor funcs `id()`/`emailIds()` (the latter returning `lent seq[Id]`), diverging from `Mailbox`/`Identity` direct-field access — inconsistent entity read ergonomics across the same library [resolved-S2: Thread.id/emailIds are direct public fields (emailIds is NonEmptyIdSeq); lent dropped]
- thread:addThreadGet ids: fetching explicit ids repeats the `Opt.some(direct(@[id]))` `Referencable`-wrapping ceremony seen in `email read` — no `seq[Id]` convenience overload for the common literal-ids case [filed-as-C3: the getThreads one-shot collapses the build→dispatch→extract lifecycle but still takes `ids: Opt[Referencable[seq[Id]]]`, so `Opt.some(direct(@[id]))` for literal ids is unchanged — a byIds/`seq[Id]` overload is C3]
- thread:source: a `threadId` is only obtainable by first fetching it as the `egpThreadId` property of an email (`email query`/`email read`); there is no thread-of-this-email shortcut, so "show me this message's thread" is a two-step dance [accepted-as-trade-off: the threadId is the Thread handle, so the two-step reflects the JMAP id model (RFC 8621 §3); a thread-of-email convenience would be additive sugar]

### identity
- identity:read: `Identity` reads cleanly via direct public fields (`id`, `name`, `email`); the only friction is the universal one — like every read, there is no single hub-public call that builds+dispatches+extracts a bare Get (the convenience module covers query/changes pairs, not plain gets) [resolved-S4: getIdentities bare-get one-shot]

### vacation
- vacation:NoCreate-phantom: discovering that the create generic must be the `NoCreate` phantom requires reading the builder's return type `SetResponse[NoCreate, PartialVacationResponse]`; the phantom occupies the FIRST (create) slot, which is non-obvious, and `createResults` stays permanently empty — the "this singleton has no create rail" fact is encoded in a type position the consumer must reverse-engineer [accepted-as-trade-off: the NoCreate phantom correctly makes an illegal singleton-create unrepresentable (P16); the discoverability is the price of the type-level guarantee]
- vacation:set-echo-FieldEcho: the `/set` echo type is `PartialVacationResponse` with three-state `FieldEcho[T]` fields (no read accessor), so rendering the echoed state needs manual `case` dispatch; to show state cleanly the CLI re-fetches via `addVacationResponseGet`, whose `VacationResponse` has plain `Opt` fields — a missing `FieldEcho.toOpt`/value convenience forces the extra round-trip [resolved-S2: FieldEcho.toOpt/valueOr reader serves the set echo; no re-fetch needed]
- vacation:singleton-id: `VacationResponseSingletonId` is a raw `string` ("singleton"), not a typed `Id`, so looking the singleton up in `updateResults` (`Table[Id, _]`) would need `parseId(VacationResponseSingletonId).get()` first — a newtype leak on the one place the id matters [filed-as-C22: type the VacationResponse singleton id — a P15 newtype leak]
- vacation:get-clean: the GET path is genuinely clean — `VacationResponse.isEnabled` is a plain `bool` and `subject`/`textBody` are plain `Opt[string]`, so reading vacation state is a simple Opt unwrap with none of the set path's FieldEcho ceremony [affirmed]

### search
- search:helper-undiscoverable (**medium**): the ergonomic one-call compound `addEmailQueryWithSnippets` (+ `EmailQuerySnippetChain`, `EmailQuerySnippetResults`, `getBoth(chain)`) is exactly the right shape — one call wires the query result ids into the snippet get, one `getBoth` yields `.query.ids` and `.snippets.list` — and it works live (matched 54). Yet ALL FOUR symbols are absent from public-api.txt (the scraper truncates `mail_methods.nim` after `addSearchSnippetGetByRef`), so a snapshot-guided consumer would never find it and would hand-roll the manual `addEmailQuery` + `reference[seq[Id]]` + `addSearchSnippetGetByRef` path instead — the best ergonomics in the library, hidden by the broken contract [resolved-S0: api_oracle now lists addEmailQueryWithSnippets + its chain/results/getBoth overload; residual filed-as-C16: query-then-snippets one-shot]
- search:SearchSnippetGetResponse-shape: `SearchSnippetGetResponse.list` is compile-accessible but the type has NO entry in `type-shapes.txt` (response types in indented `type` blocks are not scraped), so the field a search consumer must read is invisible to the type-shape contract [resolved-S0: api_oracle freeze-type-shapes now emits the type-block continuation members]
- search:snippet-opt: `SearchSnippet.subject`/`.preview` are `Opt[string]` (each needs an Opt unwrap) while `emailId` is a bare `Id` — the now-familiar mixed-optionality read [accepted-as-trade-off: the optionality correctly mirrors RFC 8621 §5.2 — emailId always present, subject/preview optional]
- search:two-rails: `client.send` is `ClientError`-tailed but `dr.getBoth(chain)` is `GetError`-tailed — the same two-error-rail bridging as every other dispatch+extract [resolved-S1: send/getBoth both return JmapError]

### convenience
- convenience:import-discoverability: the pipeline combinators require an explicit `import jmap_client/convenience` and are deliberately NOT re-exported by `import jmap_client` (P6 quarantine — correct in principle), so the headline import alone cannot reach `addEmailQueryThenGet`/`getBoth`; the discoverability cost is the price of the (sound) quarantine [resolved-S4: P6 quarantine dissolved; addEmailQueryThenGet/addEmailChangesToGet/getBoth now on the always-on hub]
- convenience:result-shape: `getBoth` yields `QueryGetResults[Email]` exposing `.query` (a `QueryResponse` — read `.ids`) and `.get` (a `GetResponse` — read `.list`); two nested field hops, and the field names `query`/`get` read as verbs rather than nouns at the call site [accepted-as-trade-off: the two fields mirror the compound's two RFC methods (query + get)]
- convenience:two-rails: `getBoth` returns `GetError` while the enclosing `send` returns `ClientError` — same bridging friction as the manual paths [resolved-S1: getBoth/send both return JmapError]
- convenience:coverage-gap: the convenience module covers query-then-Email/get but has NO query-then-snippets analogue; the snippets compound lives un-snapshotted in `mail_methods`, so the opt-in layer cannot cover the search-highlight use case at all [resolved-S0: api_oracle now lists the snippet compound (the snapshot half); residual filed-as-C16: query-then-snippets one-shot]

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
  the bench and a freeze-blocker in its own right. [resolved-S0: api_oracle.nim compiler-as-library oracle (modulegraphs.allSyms) replaced the api_surface.nim scraper; public-api.txt now enumerates the full hub surface]
- *all commands* (connect preamble, **high**): every command needs the same
  4-call connect+session+account preamble (`directEndpoint` -> `basicCredential`
  -> `initJmapClient` -> `fetchSession` -> `primaryAccount(ckMail)`), which the
  bench had to extract into `cli_session.connect()`. The API makes you build
  the connect wrapper it should ship — the concrete C5/C8 wrapper trigger [resolved-S4: connect(url, user, pass) one-shot + requireMail; the four-call preamble is gone]
- *all commands* (sealing-chain ceremony, **high**): the dominant friction
  across the bench is the `parseX(...).get()/valueOr` -> `parseY(...).get()`
  ladder before a useful call — `directEndpoint`+`basicCredential`+`initJmapClient`
  (session); `parseUnsignedInt`+`filterCondition`+`parseNonEmptySeq` (query);
  `initEmailUpdateSet`+`parseNonEmptyEmailUpdates` (flag/move); and a 9-deep
  pile-up in send (mailbox set, addresses, partId, RFC5321, rcpt list, blueprints,
  update set, onSuccess). Each construct is individually principled (parse-don't-
  validate), but the consumer threads many fallible bookends before any wire call,
  with few one-shot shorthands [resolved-S4: connect/bare-get/queryEmails/sendPlainText one-shots collapse the chains; residual accepted-as-trade-off: the parseUnsignedInt no-int-literal seal]
- *all commands* (two error rails per dispatch, **medium**): every command
  that dispatches bridges TWO error types by hand — `client.send` returns
  `JmapResult`/`ClientError`, but `dr.get`/`dr.getBoth` return `Result[_, GetError]`,
  and the smart constructors return `ValidationError` (or `seq[ValidationError]`,
  or `EmailBlueprintErrors`). No single `?`/`valueOr` style spans
  build -> send -> extract; the rails do not auto-convert and there is no
  hub-public lift between them [resolved-S1: one JmapError rail spans build->send->extract; method errors are MethodOutcome data]
- read commands (no bare-get combinator, **medium**): mailbox/thread/identity/read
  all repeat `newBuilder` -> `add*Get` -> `freeze` -> `send` -> `get` -> iterate
  `.list` verbatim; the convenience module covers query/changes *pairs* and
  `*ThenGet`, but there is no one-call build-dispatch-extract for a plain Get,
  so the most basic read still costs the full five-symbol lifecycle [resolved-S4: six bare-get one-shots (getMailboxes/getEmails/getThreads/getIdentities/getVacationResponse/getEmailSubmissions)]
- write commands (accumulating seq[ValidationError] rail, **medium**):
  `initEmailUpdateSet`/`parseNonEmptyEmailUpdates`/`parseNonEmptyRcptList`/
  `parseEmailSubmissionBlueprint`/`parseNonEmptyOnSuccessUpdateEmail` all return
  `Result[_, seq[ValidationError]]` (and `parseEmailBlueprint` an opaque
  `EmailBlueprintErrors`), so single-value constructions render errors via
  `mapIt(it.message).join` instead of the single `.message` the L1 parsers give —
  three distinct error-render idioms across flag/move/send/vacation [resolved-S1: NonEmptySeq[ValidationError] + JmapError.message joins every violation into one err.message]
- query + vacation (FieldEcho has no read accessor, **medium**): `FieldEcho[T]`
  (three-state absent/null/value) appears on `PartialEmail` header fields and the
  vacation `/set` echo, but the hub ships only the `fieldAbsent`/`fieldNull`/
  `fieldValue` CONSTRUCTORS and the public `value*` field — no reader — so every
  consumer hand-writes the same `fieldEchoOr` matcher [resolved-S2: FieldEcho.valueOr reader (+ isValue/isNull/isAbsent/items/toOpt)]
- write commands (Result-of-Opt update read, **low**): `SetResponse.updateResults`
  is `Table[Id, Result[Opt[U], SetError]]` (flag/move/vacation), a three-layer
  unwrap whose inner `Opt[U]` is almost always `none`; callers check `isOk` and
  discard the Opt [resolved-S2: created/updated projection iterators; residual accepted-as-trade-off: the per-item Result-of-Opt read for callers needing SetError]
- read commands (Referencable id-wrapping, **low**): passing literal ids to
  `addEmailGet`/`addThreadGet` is `Opt.some(direct(@[id]))` (seq + `direct` +
  `Opt.some`) in email read/thread/sync; the in-tree `directIds` shorthand is
  unlisted and `Opt.some(directIds(...))` is a hard double-Opt error — no
  `seq[Id]` convenience overload [filed-as-C3: the bare-get one-shots collapse the
  lifecycle but still take `ids: Opt[Referencable[seq[Id]]]`, so the
  `direct(@[id])` wrapping for literal ids remains — a byIds/`seq[Id]` overload is
  C3; the snapshot-unlisted `directIds` itself is resolved-S0]
- email query / email read (same-field optionality split, **medium**): the
  SAME logical field is read two different ways depending on which get was
  issued — `subject` is `FieldEcho[string]` on `PartialEmail` (partial get)
  but `Opt[string]` on the full `Email`; `fromAddr` is `FieldEcho[seq[…]]`
  vs `Opt[seq[…]]`. A consumer who switches between `addPartialEmailGet`
  and `addEmailGet` must change its read idiom for fields that look
  identical, with no type-level cue at the call site that they differ [resolved-S2: FieldEcho.valueOr unifies the read shape across PartialEmail and the full Email]

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
| Email/set (create) | `email send` | `sendPlainText` (draft create, internal `addEmailSet(create=)`) |
| Email/changes | `email sync` | `addEmailChangesToGet` (convenience) |
| Thread | `thread show` | `addThreadGet` |
| Identity | `identity list` | `addIdentityGet` |
| EmailSubmission | `email send` | `sendPlainText` (submission + onSuccess Drafts → Sent move) |
| VacationResponse (get/set) | `vacation` | `addVacationResponseGet`/`Set` |
| SearchSnippet | `search` | `addEmailQueryWithSnippets` + `getBoth` |
| Query-then-get / changes combinators | `email query --one-shot`, `email sync` | `queryEmails` (S4 one-shot wrapping `addEmailQueryThenGet`), `addEmailChangesToGet` |

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

## S0 resolution — the public-API oracle (snapshot integrity)

Sub-project **S0** (PR #5) replaced the broken `api_surface.nim` text-scraper —
which recorded a declaration only when a logical line happened to START with a
`DeclKinds` keyword, and ran away on typed literals, unbalanced
quotes/comments, and grouped-`const`/`type` continuation lines — with a
**compiler-as-library oracle** (`scripts/api_oracle.nim` + the
`scripts/api_probe.nim` entry module). The oracle loads the module graph, runs
`sem`, and walks `modulegraphs.allSyms`, so its enumeration IS exactly what
`import jmap_client` exposes: there is no second resolver with a different blind
spot, which is what gave the old H16 lint its false freeze-confidence. It drives
`just freeze-api` / `just freeze-type-shapes` and the H16/H17 snapshot-lock
lints. The frozen `tests/wire_contract/public-api.txt` (1784 lines) now
CONTAINS every symbol the bench reported reachable-but-unlisted. The
snapshot-integrity findings above are **resolved**; the *ergonomic* residuals
that the snapshot omission masked (a query-then-snippets one-shot) are filed
separately. Mapping (finding → fix):

- **"the frozen `public-api.txt` … omits the request-CONSTRUCTION bookends and
  the dispatch/session verbs — `newBuilder`/`freeze`/the client-level `send`/the
  2-arg `initJmapClient`/`fetchSession` … FALSE freeze-confidence"**
  (*all commands*, snapshot integrity, **high**) → RESOLVED. The
  `allSyms`-walking oracle lists every one of those symbols; the snapshot and
  the live resolver can no longer share a blind spot because they are the same
  walk. The freeze-blocker is cleared — and the once-dropped backtick `$`/`==`
  operator overloads on `Id`/`AccountId`/`UnsignedInt`/`MailboxRole` are now
  listed in `public-api.txt` too.
- **"the `egp*` selectors and `kwSeen`/`kwDraft`/… COMPILE yet are ABSENT from
  public-api.txt — grouped `const`-block members are silently dropped"** (email
  query:tooling) → RESOLVED. The oracle enumerates each grouped-`const` member
  (`egp*`, `kw*`, `roleInbox..`) as a first-class symbol.
- **"the `directIds` shorthand is ABSENT from public-api.txt"** (email read:ids;
  read commands, Referencable id-wrapping) → RESOLVED. `directIds` is now listed;
  the double-Opt footgun was a consequence of consumers not seeing it in the
  contract, not a type defect.
- **"the snapshot-UNLISTED const `roleInbox`"** (mailbox:mb.role, the third
  inbox idiom) → RESOLVED. `roleInbox` is listed. (The `isInbox`/`hasRole`
  predicate that makes the idiom a one-liner is S3.)
- **"ALL FOUR snippet symbols (`addEmailQueryWithSnippets` + its chain/results +
  the `getBoth` overload) are absent — the scraper truncates `mail_methods.nim`
  after `addSearchSnippetGetByRef`"** (search:helper-undiscoverable, the
  snapshot half; convenience:coverage-gap, the snapshot half) → RESOLVED. The
  oracle lists the whole compound; a snapshot-guided consumer can now discover
  it. (The missing query-then-snippets convenience is the ergonomic residual,
  filed-as-C16.)
- **"`SearchSnippetGetResponse` has NO entry in `type-shapes.txt` — response
  types in indented `type` blocks are not scraped"**
  (search:SearchSnippetGetResponse-shape) → RESOLVED. `just freeze-type-shapes`
  runs the same oracle in type-shapes mode and emits the type-block continuation
  members.
- **"the builder finaliser `freeze` … its absence from the snapshot, a
  discoverability trap"** (email send:freeze-not-build, the snapshot half) →
  RESOLVED. `freeze` is listed. (S4's `sendPlainText` removes the finaliser from
  the common send path entirely.)

Standing caveat (NOT a regression): the oracle is a Nim compiler-as-library
program, so a Nim toolchain upgrade MUST re-verify it — `modulegraphs.allSyms`
and the `sem` walk are internal-compiler API, and a future Nim could change
their shape. The freeze is only as trustworthy as the oracle, and the oracle is
pinned to the current compiler.

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
record their Phase 2 disposition inline (they were `[open]` when S2 landed, under the observe-only convention); the
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
only, not new convenience, so S2 deferred them to S3 — now resolved-S3 below):

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
all** (the nine mailbox rights stay orthogonal). The inline finding lines record their Phase 2 disposition inline
(they were `[open]` when S3 landed, under the observe-only convention); the mapping
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
  family is uniformly named-soft with a single session-fault condition (the
  required capability is not advertised); the designated-primary-specific need
  is served by the public `session.primaryAccount(kind): Opt`.

Still open after S3 (tracked to their sub-projects): the readers and predicates
are now one-liners, but the request-lifecycle one-shots that still cost the full
five-symbol chain — `connect()`, a bare-Get combinator, and the `sendPlainText`
one-shot (the submission half `plainTextBody` does not cover) — are S4; the
sealing-chain ceremony around them is S4; the standing `parseUnsignedInt(…).get()`
no-int-literal seal rides along with it; and the snapshot-integrity freeze-blocker
is its own track. The read-model convenience the bench asked for is in.

## S4 resolution — request-lifecycle one-shots (the easy path)

Sub-project **S4** shipped the build-dispatch-extract one-shots the S1/S2/S3
passes left `[open]` — the single calls that fold construction, dispatch and
extraction of one logical operation onto the one `JmapError` rail. The design is
the libcurl/SQLite easy-path-beside-the-primitives split: the verbose builder
lifecycle stays for callers who batch or interleave methods, and each one-shot
collapses its single method's `MethodOutcome` onto the rail (RFC 8620 §3.6.2 — a
single-method shortcut, not a reclassification of the data semantics), so a
command that issues one operation threads on a bare `?` with **no `case
outcome.kind` ceremony at all** — that collapse is the whole win. The CLI was
re-benched against the one-shots; every adoption below is in the tree and
compiles public-surface-only with zero warnings. The inline finding lines record their Phase 2 disposition inline
(they were `[open]` when S4 landed, under the observe-only convention); the mapping
lives here. Mapping (finding → fix):

- **the connect preamble (C5/C8)** — "obtaining one usable client costs THREE
  sequential smart-constructor unwraps … no single `connect(url, user, pass)`
  convenience shorthand" (session:connect) + "every command needs the same
  4-call connect+session+account preamble … the API makes you build the connect
  wrapper it should ship" (*all commands*, connect preamble, **high**) →
  RESOLVED. `connect(url, user, pass)` folds `directEndpoint` + `basicCredential`
  + `initJmapClient` onto the rail (the RFC 8620 §2 session stays lazy, fetched
  on first send); a `connect(url, user, pass, transport)` overload threads a
  caller-supplied `Transport`. The CLI's shared helper (`commands/cli_session.nim`)
  collapses to `?connect(...)` + `fetchSession` + `requireMail`, and the verbose
  onboarding probe (`commands/session.nim`) adopts the same one-shot inline. The
  four-call boilerplate the bench was forced to extract is gone — the helper
  survives only to bind the resolved mail account alongside the client.
- **no bare-get combinator (R1)** — "the most basic read still costs the full
  five-symbol lifecycle" (read commands, no bare-get combinator, **medium**) +
  the per-command "`newBuilder` -> `add*Get` -> `freeze` -> `send` -> `get` ->
  iterate `.list`; no single-call get shorthand" (mailbox:dr.get(handle),
  identity:read, thread, email read) → RESOLVED. Six bare-get one-shots return
  the FULL `GetResponse[T]` (so `state` / `notFound` survive): `getMailboxes`
  (`commands/mailbox.nim`, and `resolveInbox` in `email_query.nim`),
  `getIdentities` (`commands/identity.nim`, and the send-path identity resolve),
  `getEmails` (`commands/email_read.nim`, and the `email_sync` state-cursor
  read), `getThreads` (`commands/thread.nim`), `getVacationResponse`
  (`commands/vacation.nim` doGet), and `getEmailSubmissions` (public, not
  separately driven). Each collapses the single method's outcome onto the rail,
  so the `case outcome.kind of mokMethodError/mokValue` block at every read site
  is deleted — the body reads `.list` directly.
- **the read combinator (query-then-get)** — the manual "restate the producing
  method `queryH` already encodes, pick `rpIds` among nine, supply the generic
  `seq[Id]`" (email query:reference) is now ALSO a one-shot. `queryEmails`
  (`commands/email_query.nim`, the `--one-shot` path) folds Email/query ->
  full-record Email/get and reads `.query.ids` / `.get.list`; `queryMailboxes` /
  `queryEmailSubmissions` are its siblings. The DEFAULT `email query`
  deliberately keeps the hand-wired back-reference + PartialEmail `FieldEcho`
  read, because the typed server-side back-reference and the three-state echo are
  documentary and `queryEmails` (full `Email`, plain `Opt`) exposes neither.
- **the send path (R4)** — the whole send-friction cluster: "NO plain-text body
  shorthand" (email send:no-body-helper, **high**), "`addEmailSubmissionAndEmailSet`
  does NOT create the email" (builder-does-not-create, **high**), "`emailId` …
  the only encoding is `parseIdFromServer('#' & $draftCid)`"
  (emailId-no-forward-ref, **high**), "returns an UNCOPYABLE `RequestBuilder` …
  must `move()`" (uncopyable-move), "four+ sealing constructors precede the
  build" (sealing-pileup), "one logical send yields three response shapes"
  (three-response-shapes), and "reading the created id is a nested rail"
  (nested-id-read) → RESOLVED. `sendPlainText(client, accountId, identityId,
  draftMailbox, sentMailbox, fromAddr, to, subject, body, cc, bcc)` is the one
  call: it builds the inline text/plain body (the S3 `plainTextBody`), files the
  draft in Drafts with `$draft`, references it from the submission via the typed
  `creationRef` forward-reference (the `#`-smuggle is internal and invisible),
  wires the onSuccess Drafts -> Sent move (RFC 8621 §7.5.1), and returns a flat
  `SentEmail{emailId, submissionId}`. The CLI's `email_send.nim` now only
  resolves the three ids it needs (`getIdentities` for the From, `getMailboxes` +
  `hasRole(mrDrafts)` / `hasRole(mrSent)` for the two mailboxes) and calls
  `sendPlainText` — the `buildDraftBlueprint` / `buildSubmissionBlueprint` /
  blueprint-`resolveRoles` / `parseEmailSubmissionSet` / `addEmailSubmissionSet`
  / `getBoth` body and its `std/tables` wiring are deleted. The doc-16 "they will
  wrap it" verdict for sending flips to "reach for it".
- **convenience import-discoverability (P6 dissolved)** — "the pipeline
  combinators require an explicit `import jmap_client/convenience` … the headline
  import alone cannot reach `addEmailQueryThenGet` / `getBoth`"
  (convenience:import-discoverability) + the whole `### convenience` section →
  RESOLVED by dissolution, not by a new symbol. The P6 quarantine is retired:
  `addEmailQueryThenGet` / `addEmailChangesToGet` / `getBoth` are now part of the
  always-on hub, surfaced through the single `import jmap_client` (the
  `jmap_client/convenience` module no longer exists). `commands/email_sync.nim`
  reaches the changes combinator through the plain hub import with no second
  import; the `email query --one-shot` path uses the `queryEmails` one-shot that
  wraps the same machinery. The discoverability cost the quarantine bought is
  gone, and `check-public-only.sh` still passes — an import of the deleted module
  would not even compile.

What S4 did NOT change (the honest parking lot):

- the standing `parseUnsignedInt(N).get()` no-int-literal seal still mints every
  `UnsignedInt` (the query `limit`, the body-fetch cap); the one-shots take the
  already-minted value, so the seal rides along unchanged — the same standing
  note S2/S3 recorded, not an S4 regression.
- the `EmailLeaf` / `leafTextParts` naming and the per-part body-value read
  remain exactly as S3 shipped them; no S4 rename. Triage parking-lot items.
- **Email/set has no write one-shot.** `email flag` (`commands/email_flag.nim`)
  and `email move` (`commands/email_move.nim`) keep the `initEmailUpdateSet` ->
  `parseNonEmptyEmailUpdates` -> `addEmailSet` triple-seal, and vacation set
  (`commands/vacation.nim` doSet) keeps its by-value update-set wiring; all three
  still iterate the `Table[Id, Result[Opt[U], SetError]]` `updateResults`, so
  their `std/tables` imports stay. An `addEmailUpdate`-style write one-shot is the
  obvious next combinator but is outside S4's connect/read/send scope.
- the search compound (`addEmailQueryWithSnippets`, `commands/search.nim`) has no
  one-shot — it is already the API's ergonomic best and is left hand-wired by
  choice (its dispatch envelope is a single `getBoth`).
- the snapshot-integrity freeze-blocker (the frozen `public-api.txt` omits the
  lifecycle bookends) is untouched and remains its own track.

API-gap findings surfaced by the S4 re-bench (where a one-shot did NOT fit a
command): the Email/set write path (flag/move/vacation-set) has no one-shot to
adopt; the search snippet compound has none; and the default `email query`
back-reference path is left hand-wired by design (the partial-get FieldEcho
demonstration is not reachable through `queryEmails`). None block a command —
each compiles and round-trips through the hub — they mark where the next
combinator (an Email/set write one-shot, a query-then-snippets one-shot) would go.
