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
`UnsignedInt` (with only `.toInt64`), and the four-phase request
lifecycle (`newBuilder` → `add*Get` → `freeze` → `send` → `get`). The
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
reaching each leaf through a `case part.isMultipart of true: discard of
false: …` whose dead arm exists only to satisfy strict case objects. Two
papercuts pile on: reading a returned field forces `import std/tables`
(the hub re-exports `results` but not `tables`), and the `isTruncated` /
`isEncodingProblem` flags on a body value are easy to forget. None of this
is wrong — it is RFC fidelity — but `email.decodedTextBody()` is the one
convenience whose absence every mail client will feel immediately.

## Mutating: flags, moves, vacation
<!-- filled in Tasks 10–12 -->

## Sending: the EmailSubmission path
<!-- filled in Task 13 -->

## Search and the convenience layer
<!-- filled in Tasks 14–15 -->

## Cross-cutting verdict
<!-- filled in Task 17: would a competent developer reach for this
     directly, or wrap it? (P7) -->
