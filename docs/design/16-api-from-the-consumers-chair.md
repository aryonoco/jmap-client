<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# 16. The API from the consumer's chair

A narrative companion to `14-Nim-API-Principles.md`, written from the
seat of an application developer building an email client against the
jmap_client public API via the `examples/jmap-cli/` bench (tracker
C1 / P29). Where `AUDIT.md` is the terse ledger of individual
awkwardnesses, this document records the *feel*: what is elegant, what
grates, what surprised, and the verdict on the make-or-break
first-fifteen-minutes path. Findings cross-reference principles
P1–P29 by number.

## The first fifteen minutes

The make-or-break path — env to a usable client to the first useful
answer — is **discoverable and type-safe, but front-loads ceremony**.
A newcomer meets roughly eight concepts before `session` prints
anything: the `Result` rail and `.valueOr`, `Opt`, `SessionEndpoint`,
`Credential`, `CapabilityKind` (specifically the `ckMail` value),
`UnsignedInt` (with only `.toInt64`), and the four-type-phase request
lifecycle — builder → built → dispatched → response — reached through the
five-verb chain `newBuilder` → `add*Get` → `freeze` → `send` → `get`. The
single import is a genuine kindness: `import jmap_client` re-exports the
whole `results` vocabulary, so the error rail arrives for free with no
second import to discover (P5 — one public surface).

The grating part is the **connect preamble**. Three fallible smart
constructors (`directEndpoint`, `basicCredential`, `initJmapClient`)
each demand an unwrap before the first network call, and there is no
`connect(url, user, pass)` shorthand on the hub — so every consumer
writes the same four-call boilerplate, which this bench was forced to
extract into `cli_session.connect()`. That extraction *is* the C5/C8
"connect-wrapper trigger" made concrete: the API makes you build the
wrapper it should have shipped. Two sharper edges compound it. First,
the consumer cannot return failures on the library's own `JmapResult`
rail, because there is **no hub-public `ClientError` constructor** (only
`transportError`); the CLI had to invent a local `string` error type and
stringify everything via `.message`. Second, the two error rails do not
compose — `?` cannot lift a constructor's `Result[_, ValidationError]`
into a `ClientError`-tailed function — so the elegant `?` operator is
unusable across the connect boundary and every step needs an explicit
`valueOr: return err(...)`.

Against that, the lifecycle's verbosity buys real safety: `freeze`
consumes the builder by `sink` (a double-`send` is a *compile* error),
and the `ResponseHandle[T]` returned from `add*Get` pins the result type
so `dr.get(handle)` cannot be mistyped (P16, P21 — preconditions and
lifecycle encoded in types). The capability pre-flight is honest —
`primaryAccount(ckMail)` returns `Opt[AccountId]`, refusing to pretend a
non-mail server has a mail account — though it forces the newcomer to
discover the `ckMail` enum value rather than offering a
`session.mailAccountId()`. Verdict: a competent developer reaches the
first answer in well under fifteen minutes and trusts it, but writes a
connect helper on the way and grumbles at the missing `ClientError`
constructor. The lifecycle is sound; the on-ramp wants one convenience
function and one error-rail bridge.

The most serious thing surfaced here is not ergonomic but
**contractual**: the symbols that make the lifecycle work — `newBuilder`,
`freeze`, the 2-arg `initJmapClient` — are absent from the frozen
`public-api.txt` snapshot the project intends as its 1.0 contract (see
`AUDIT.md` cross-cutting, high severity). A consumer who took that
snapshot literally could not discover how to issue a request at all. The
bench proceeds against what genuinely compiles through `import
jmap_client`; the snapshot generator needs fixing before the freeze.

## Reading: mailboxes, queries, messages, threads, identities

**Mailboxes.** `mailbox list` is the cleanest read in the API once the
connect helper exists: `addMailboxGet(account)` with no id filter fetches
all of them, and `Mailbox`'s fields are direct and well-named (`name`,
`unreadEmails`, `totalEmails`, `myRights`, `role`). Two rough edges. The
role is `Opt[MailboxRole]`, and there are three unrelated ways to ask "is
this the inbox?" — `role.kind == mrInbox`, a named `roleInbox` constant,
or `parseMailboxRole("inbox")` — with no single blessed idiom and (worse)
the constants invisible in the frozen contract. And `MailboxRights` is
nine independent ACL booleans with no roll-up: the CLI had to invent a
`rwas` digest and *guess* that "can write" means
`mayAddItems and mayRemoveItems and maySetSeen and maySetKeywords`
(tracker C4). A `canWrite`/`canAdminister` predicate would turn a guess
into a contract. The dispatch ceremony — `newBuilder → add*Get → freeze →
send → get` — is identical to every other read; type-safe, but repeated
verbatim each time.

**Queries.** `email query` is where the API's best and worst instincts
sit side by side. The best: the server-side back-reference. `reference[
seq[Id]](queryH, mnEmailQuery, rpIds)` threads the Email/query result ids
straight into a partial Email/get in a *single* request, fully type-
checked — no client round-trip, no manual id plumbing (P19, schema-driven
references). That is genuinely excellent and is exactly what a hand-rolled
HTTP client gets wrong. The worst: the friction to *get there*. The limit
is a triple wrap (`Opt.some(parseUnsignedInt(20).get())`); the filter is a
raw all-`Opt` object literal double-wrapped through `filterCondition`; the
back-reference makes you restate the method `queryH` already knows and
pick `rpIds` out of nine `RefPath` members; and the property list is
`parseNonEmptySeq(@[…]).get()` — a fallible parse of a literal that cannot
be empty. Then the read side splits its optionality model:
`PartialEmail.id`/`receivedAt`/`preview` are `Opt[T]`, but
`subject`/`fromAddr` are `FieldEcho[T]` (absent/null/value) with **no read
accessor on the hub** — so every consumer writes the same `fieldEchoOr`
three-state matcher. The echo is principled (it distinguishes "server
omitted" from "server sent null"), but shipping it without a reader pushes
that principle onto every call site. Net: the power is real and safe; the
on-ramp is a sequence of small sealing ceremonies that a thin combinator
layer (a query-then-get helper, a `fieldEchoOr`, a limit shorthand) would
smooth without losing any safety.

**Incremental sync.** `email sync` exercises the path a real mail client
actually lives on, and it surfaces both a quiet win and a real gap. The
win: a `JmapState` cursor round-trips through `parseJmapState` (P15 — a
smart constructor, and it is even in the snapshot), so a client can persist
its sync position to disk and resume after a restart. The state is a
first-class value, not something trapped inside a live response — exactly
what sync needs. The gap is in the convenience layer: `addEmailChangesToGet`
back-references only the `/created` path into its Email/get, so the
returned records cover *created* messages but not *updated* ones. For a mail
client, "updated" (read/flag/move) is the dominant case, so the moment you
want the bodies of changed messages you drop out of the one-call
convenience and hand-compose `addEmailChanges` + `addPartialEmailGet(ids =
reference(ch, mnEmailChanges, rpUpdated))`. The change *counts* are all
there (`created`/`updated`/`destroyed` ids on the response), so the delta is
honest; it is only the fetch that is created-biased. One bootstrap wrinkle:
the diff is against the Email *object* state (`GetResponse.state`), which no
command surfaces by default, so the CLI issues an empty-ids `Email/get` just
to read the initial cursor.

**Messages.** `email read` reads cleanly once you accept that decoding a
plain-text body is a manual join: `addEmailGet` returns the full `Email`
(no `properties` arg — that is the separate `addPartialEmailGet`, which
also flips the result type to `PartialEmail`), whose `subject` is a plain
`Opt[string]` and `preview` a bare `string`. That is *easier* than the
partial get — and that is itself the surprise: the same `subject` field is
`FieldEcho` on `PartialEmail` and `Opt` on `Email`, so switching between
the two gets silently changes the read idiom with no call-site cue. The
body itself is the bigger ask. RFC 8621 separates body *structure*
(`textBody`) from body *values* (`bodyValues`, keyed by `partId`), and the
API faithfully mirrors that — correct, but it means every consumer
hand-writes a `textBody`-walk that joins against the `bodyValues` table,
reaching each leaf through the `isMultipart` discriminator (a plain `if not
part.isMultipart` suffices — the consumer does not inherit the library's
`strictCaseObjects`, which is a src/-only pragma). Two papercuts pile on:
reading a returned field forces `import std/tables`
(the hub re-exports `results` but not `tables`), and the `isTruncated` /
`isEncodingProblem` flags on a body value are easy to forget. None of this
is wrong — it is RFC fidelity — but `email.decodedTextBody()` is the one
convenience whose absence every mail client will feel immediately.

**Threads and identities** expose the read-model's *inconsistency*.
`Identity` is flat and direct — `id`/`name`/`email` are public fields, and
`identity list` is a clean two-liner. `Thread`, by contrast, is a sealed
type with *no* public fields: `id` and `emailIds` are accessor functions
(`emailIds` returning a `lent seq`). Both are defensible in isolation, but
a consumer learning the library meets three different read shapes for
three entities — direct fields (`Mailbox`, `Identity`), accessor funcs
(`Thread`), and the dual Opt/FieldEcho split (`Email`/`PartialEmail`) —
with no signposting of which to expect. And a `threadId` is only reachable
as an email property, so "show this message's thread" is inherently two
round-trips. These are small frictions, but their *unevenness* is the
finding: the API would feel more learnable if its read-models shared one
access idiom.

## Mutating: flags, moves, vacation

The write path is where the type system's discipline is most visible and
most expensive. The DSL verbs are excellent: `markRead()`,
`moveToMailbox(id)`, `setIsEnabled(true)` are total, named, and read like
the spec (P18 — sum-typed operations, not flag soup). The cost sits in
the envelope around them. Flagging *one* email is a two-layer seal —
`initEmailUpdateSet(@[markRead()])` then
`parseNonEmptyEmailUpdates(@[(id, set)])` — so the single-email case still
pays the whole-batch `NonEmptyEmailUpdates` wrap, and *both* layers ride
an **accumulating `seq[ValidationError]`** rail. That last detail is a
genuine ergonomic tax: every other smart constructor in the library
(`parseId`, `parseKeyword`) returns a single `ValidationError` with a
`.message`, but these two return a *seq*, so the call site needs
`error.mapIt(it.message).join("; ")` — a different error-rendering idiom
for the write path than the read path. `email move` is the same chain
verbatim with `moveToMailbox` swapped for `markRead`; the repetition begs
for an `addEmailUpdate(account, id, @[ops])` one-shot.

Reading the result back is a *third* layer: `updateResults` is
`Table[Id, Result[Opt[PartialEmail], SetError]]`, a Result-of-Opt whose
inner `Opt` is almost always `none` for a flag — so the happy path is
"check `isOk`, ignore the payload," and the nested shape carries more
structure than the common case uses.

Vacation adds two instructive wrinkles. First, an *inconsistency*:
`addVacationResponseSet` takes its update set **by value**, while
`addEmailSet` takes `Opt[...]` — two `/set` builders, two conventions, no
way to muscle-memory one. Second, a *phantom done right but hidden*: the
set response is `SetResponse[NoCreate, PartialVacationResponse]`, where the
`NoCreate` marker in the first generic slot encodes "this singleton has no
create rail" — correct and principled (P16), but the consumer only learns
it by reading the return type, and the echo fields are `FieldEcho` again,
so rendering state cleanly means re-fetching through the plain-`Opt`
`VacationResponse` get. The verdict for mutation: the *operations* are a
model of typed-DSL design; the *plumbing* (triple seal, accumulating
error seq, Result-of-Opt read-back, Opt-vs-value drift) is where a thin
write-combinator layer would pay for itself many times over.

## Sending: the EmailSubmission path

This is the path where the question "would a competent developer reach for
this directly, or wrap it?" (P7) gets its sharpest answer — and the honest
answer is **they will wrap it, but they can build the wrapper.** It works:
the bench sent a real message alice→bob in one request that created the
draft, submitted it, and moved it to Sent on success, all verified against
live Stalwart. Nothing about the use case is blocked. But getting there
exercises almost every friction the rest of the API hints at, concentrated
in one place.

Two things dominate. First, **there is no plain-text body shorthand.** A
one-line string body becomes a four-layer hand-build —
`BlueprintBodyValue → BlueprintLeafPart{bpsInline} → BlueprintBodyPart{
text/plain} → flatBody` — with raw case-object literals (no smart
constructor), a `contentType` string that must be *exactly* `"text/plain"`
or a deferred validation rejects it, and a mandatory `partId` that can only
be minted by `parsePartIdFromServer` — a function whose name says
*receive-side* but which the *send* path is forced to call. Every mail
client sends plain text; every one will hit this first.

Second, the **compound builder misleads by its name.**
`addEmailSubmissionAndEmailSet` does not create the email — its `create` is
the submission table only, and the "AndEmailSet" is the server's *implicit*
Email/set driven by `onSuccessUpdateEmail` (an update). The draft is created
by a *separate* `addEmailSet` on the same builder, and the submission points
back at it through `emailId` — which is a plain `Id` with no typed
forward-reference, so the same-request link is smuggled as
`parseIdFromServer("#" & $draftCid)` because the strict `parseId` rejects
the `#`. The `onSuccessUpdateEmail` map is then keyed by the *submission's*
creation id, not the email's. None of this is discoverable from types; it
was recoverable only by reading the source. The compound builder even
returns a `Result` wrapping an *uncopyable* builder, so the Ok tuple must be
`move`d rather than `.get()`d — a one-off ceremony unlike every other
builder.

And yet — the underlying design is *correct*. RFC 8621's onSuccess
semantics are faithfully exposed; the send is genuinely atomic; the
three-response compound (`CompoundResults.primary`/`.implicit` plus the
draft create) models exactly what the server does. The verdict for sending:
the **protocol fidelity is excellent and the safety is real, but the
ergonomic surface is the strongest argument in the whole library for a
thin, blessed convenience layer** — a `sendPlainText(account, identity,
from, to, subject, body)` that hides the body chain, the `#`-ref smuggle,
the two-creation wiring, and the move ceremony. Without it, every consumer
writes that wrapper, which is precisely the P7 smell. With it, jmap-client
would be a library a competent developer reaches for directly.

## Search and the convenience layer

These two commands show what the API looks like when it *does* ship the
combinator — and it is a different, better library. `search` uses
`addEmailQueryWithSnippets`: one call wires the Email/query result ids into
a SearchSnippet/get, and a single `getBoth(chain)` returns `.query.ids`
alongside `.snippets.list`. It worked live the first time (54 matches with
`<mark>`-highlighted snippets). This is the same back-reference machinery
that felt like ceremony in `email query`, but packaged — and packaged, it
is a pleasure. The catch is pure tooling: all four symbols of this compound
(`addEmailQueryWithSnippets`, `EmailQuerySnippetChain`,
`EmailQuerySnippetResults`, the `getBoth` overload) are missing from the
frozen `public-api.txt`, so a consumer reading the contract would never
find the good path and would hand-roll the tedious one. The best ergonomics
in the library are the ones the contract hides.

The opt-in convenience module makes the same point deliberately.
`addEmailQueryThenGet` builds Email/query → Email/get returning *full*
`Email` records (plain `Opt` fields, no `FieldEcho`) in one call and one
`getBoth`. It is exactly the smoothing the read path wanted, and it is
correctly quarantined (P6): you reach it only through an explicit `import
jmap_client/convenience`, so the core surface stays uncontaminated and the
import guard still passes. The residual friction is minor and honest — the
`.query`/`.get` field names read as verbs, the `getBoth`/`send` two-rail
split persists, and the module covers query-then-get but not
query-then-snippets. The lesson the two commands teach together is the
through-line of this whole document: **the protocol core is sound and
safe, the convenience layer proves the library knows how to package it, and
the gap between them is exactly where the pre-1.0 work should go** — extend
the blessed convenience layer to cover the send path and the snippet
compound, and fix the snapshot so consumers can find what already exists.

## Cross-cutting verdict

The bench set out to answer one question (P29): build a real consumer
against the public API only, and treat its sore spots as bugs in the API,
not the user. Thirteen commands later — every RFC 8620/8621 entity area
exercised, real mail delivered alice → bob, an incremental-sync delta
observed — the headline is reassuring: **nothing was inexpressible.** Not
one command had to reach into `jmap_client/internal`; every path compiled
through `import jmap_client` (+ the opt-in `convenience`) and round-tripped
against a live server, under the library's own full strict battery *and*
in a pristine out-of-tree build with zero warnings. The protocol core is
sound, safe, and complete.

**Would a competent developer reach for it directly, or wrap it? (P7)** —
the honest answer is *area-dependent*:

- **Reading (mailbox, query, read, thread, identity, sync): reach for it
  directly.** The entity models are clean, the server-side back-reference
  (`reference[seq[Id]]`) is a genuine highlight that a hand-rolled client
  gets wrong, and the convenience `*ThenGet`/`*ChangesToGet` combinators
  already smooth the common pairs. A thin `fieldEchoOr` and a bare-get
  one-shot are the only things a reader writes twice.
- **Mutating (flag, move, vacation): reach for it, but write one helper.**
  The DSL verbs (`markRead`, `moveToMailbox`, `setIsEnabled`) are exemplary
  (P18); the triple-seal + accumulating-error envelope around them is the
  one thing every consumer will wrap in an `addEmailUpdate(account, id,
  ops)` shorthand.
- **Sending (EmailSubmission): they will wrap it — today.** This is the one
  area that trips the P7 wire: no plain-text body helper, a misleadingly
  named compound that does not create the email, an untyped `emailId`
  forward-reference smuggled through a `#`-prefixed lenient parse, and a
  `move`-not-`get` Result tuple. It *works*, atomically and correctly, but
  no application developer will hand-write that sequence twice. A blessed
  `sendPlainText(...)` convenience would flip this area from "wrap it" to
  "reach for it."
- **Search: reach for it — if you can find the good path.** `addEmailQuery
  WithSnippets` is the API at its best, but it is invisible in the frozen
  contract, so a snapshot-guided developer would hand-roll the tedious
  manual back-reference instead.

**The first fifteen minutes (P29).** A newcomer meets ~8 concepts before
`session` prints, reaches a trustworthy answer well inside the window, and
— tellingly — writes a connect helper on the way, because the 4-call
preamble has no shorthand (the concrete C5/C8 trigger). Discoverable and
safe, but front-loaded.

**What is genuinely excellent — and should not change.** The single
re-exporting hub that also surfaces the `results` vocabulary (P5); the
phantom-typed lifecycle where `freeze` consumes the builder by `sink` and
`ResponseHandle[T]` pins the get's result type, so illegal sequences are
*compile* errors (P16, P21); the named-variant error rail
(`ClientError`/`GetError`/`SetError`/`ValidationError`, each with
`.message`) instead of stringly errors (P13); sealed smart constructors
that parse-once-trust-forever (P15); the type-safe server-side
back-references (P19); and the correctly-quarantined convenience layer
(P6). These are the decisions that age well, exactly as the great-library
case studies in doc 14 predict.

**What grates — and is cheap to fix before 1.0.** Almost all of it is
*envelope*, not *core*: the pervasive sealing-chain ceremony; the absence
of a plain-text body helper and a `decodedTextBody` reader; `FieldEcho`
shipped without a reader accessor; the accumulating `seq[ValidationError]`
rail on single constructions; the two-error-rail split between `send`
(`ClientError`) and `get` (`GetError`); and the read-model unevenness
(direct fields vs accessor funcs vs Opt-vs-FieldEcho for the same field).
A small, blessed convenience layer — `connect`, `sendPlainText`,
`addEmailUpdate`, `fieldEchoOr`, `decodedTextBody` — would erase the
friction without touching the principled core.

**The most consequential finding is not ergonomic at all.** The frozen
`public-api.txt` contract — the thing meant to lock the surface at 1.0
(P1/P2) — does not actually capture the public surface: `newBuilder`,
`freeze`, `client.send`, and the 2-arg `initJmapClient` are reachable and
load-bearing yet absent, because the snapshot generator runs aground on a
typed literal and a comment-stripping bug. The H16 lint passes only because
the snapshot and the resolver share the blind spot. A consumer who took the
contract literally could not issue a request at all. **That must be fixed
before the freeze** — a contract that omits the entry points is worse than
no contract, because it certifies a surface nobody can use.

**One-line verdict.** *A protocol-faithful, type-safe core that a competent
developer can already use directly for everything but sending — bring the
send path and the snippet compound into a thin blessed convenience layer,
and fix the freeze snapshot to enumerate the lifecycle, and jmap-client is
a library people reach for rather than wrap.*
