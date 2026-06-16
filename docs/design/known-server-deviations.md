<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Known server deviations / RFC-deviation register

**Policy.** The client follows Postel's law on receive — *liberal in what it
accepts, strict in what it sends* (CLAUDE.md "accept the most general type,
return the most specific"; `.claude/rules/nim-conventions.md` "be lenient on
receive"). Each entry below is a **deliberate receive-side leniency** that
diverges from a literal RFC `MUST`, recorded here so it reads as considered, not
overlooked. **The client never originates non-conformant wire output** — every
divergence is on the parse/receive path only; the strict client-construction
constructors (`parseId`, the creation models, the builders) enforce the RFC on
send. The authoritative source is the RFC text in `docs/rfcs/`; this register
records exactly where receive leniency intentionally exceeds the RFC's literal
`MUST` for real-server interop (Stalwart / Apache James / Cyrus).

This register was produced by the post-S2 whole-codebase RFC-conformance audit
(2026-06-15). The audit also found and fixed genuine bugs (header-`null`
parsing, the non-IANA `subscriptions` role, the fixture-only full-object
`toJson`, the redundant VacationResponse `id` selector); those are *not* listed
here — only the kept divergences are.

---

## 1. Lenient `newState` on `/set` and `/copy` responses

- **RFC:** RFC 8620 §5.3 / §5.4 type the response `newState` as a required,
  non-nullable `String`.
- **Code:** `SetResponse.newState` / `CopyResponse.newState : Opt[JmapState]`
  (`protocol/methods.nim`); `fromJson` reads it via the lenient `optState`.
- **Why kept:** Stalwart 0.15.5 omits `newState`. This is **receive-only** — the
  client never *emits* a `/set` or `/copy` response, so no non-conformant wire
  output is produced. On absence the client falls back to `oldState` or a fresh
  `Foo/get`. Tightening to a required field would reject real Stalwart payloads
  the client otherwise handles.

## 2. Server ids not restricted to the base64url alphabet

- **RFC:** RFC 8620 §1.2 — an `Id` `MUST` use `[A-Za-z0-9_-]`, `MUST NOT` start
  with `-`, and be 1–255 octets.
- **Code:** `parseIdFromServer` (`types/primitives.nim`) and `parseAccountId`
  (`types/identifiers.nim`) accept any non-control 1–255-octet token. The strict
  `parseId` — used for **client-constructed** ids that go on the wire — enforces
  the full base64url rule.
- **Why kept:** the §1.2 `MUST` binds the id *producer* (a conformant server). A
  client echoing a server's id back verbatim is exactly the opaque-token
  behaviour the protocol requires; ids are never interpreted. The client never
  *originates* a non-base64url id (strict `parseId` guards that). The `Id` type
  docstring notes this lenient-receive exception.

## 3. Mail account-capability fields tolerated absent; sort options as a set

- **RFC:** RFC 8621 §1.3.1 — the `urn:ietf:params:jmap:mail` account-capability
  object `MUST` contain `maxSizeMailboxName` and `maxMailboxesPerEmail`, and
  `emailQuerySortOptions` is typed `String[]`.
- **Code:** `maxSizeMailboxName` / `maxMailboxesPerEmail : Opt[UnsignedInt]`
  (default `none` when absent); `emailQuerySortOptions : HashSet[string]`
  (default empty when absent/null) — `types/account_capability_schemas.nim`,
  `serialisation/serde_session.nim`.
- **Why kept:** absence degrades gracefully — the client simply does not know a
  limit or the supported sort set; no request is corrupted. `emailQuerySortOptions`
  is a *set* of supported sort-property names, where order and duplicates carry
  no meaning, so `HashSet` is a faithful (arguably better) representation than an
  ordered `seq`.

## 4. `mayDelete` modelled as a three-state `DeleteAuthority`

- **RFC:** RFC 8621 §6 — Identity `mayDelete` is a server-set `Boolean` (always
  present).
- **Code:** `Identity.mayDelete : DeleteAuthority` (`daUnreported` / `daYes` /
  `daNo`); `PartialIdentity.mayDelete : Opt[bool]` (`mail/identity.nim`).
- **Why kept:** Stalwart 0.15.5 omits `mayDelete`. `daUnreported` honestly names
  "the server did not report" rather than collapsing the omission to `daNo`,
  which would *falsely* tell the consumer the user is forbidden to delete the
  identity. `mayDelete` is receive-only and server-set, so no wire request is
  affected, and the three-state model is strictly more informative than the bare
  Boolean — tightening to `bool` + fail-fast-on-absent would reject real
  payloads.

## 5. One `SubmissionParams` type for both `mailFrom` and `rcptTo`

- **RFC:** RFC 8621 §7 / RFC 5321 — SMTP `MAIL FROM` parameters (e.g. `ENVID`,
  `RET`, `SIZE`) and `RCPT TO` parameters (e.g. `NOTIFY`, `ORCPT`) belong to
  different SMTP commands.
- **Code:** a single `SubmissionParams` type carries both, with no client-side
  enforcement that a MAIL-only parameter stays on `mailFrom` or a RCPT-only one
  on `rcptTo` (`mail/submission_envelope.nim`).
- **Why kept:** the JMAP server validates the parameter context when translating
  the `Envelope` to SMTP `MAIL`/`RCPT` (RFC 8621 §7 references RFC 5321 "as
  appropriate") — this is a server-side concern, not a client conformance
  violation. (A future enhancement could add client-side context validation for
  earlier error detection; it is not required for conformance.)

## 6. Implicit `Email/set` after `EmailSubmission/set` modelled as conditional

- **RFC:** RFC 8621 §7.5 ¶3 — after the `EmailSubmission/set` items are
  processed, *a single implicit `Email/set` call `MUST` be made* and its
  response `MUST` be returned, with no stated condition on the call's presence.
- **Code:** `EmailSubmissionHandles.implicit : Opt[NameBoundHandle[...]]`
  (`mail/submission_builders.nim`) — the §5.4 implicit handle is present only
  when the spec carried an `onSuccessUpdateEmail` / `onSuccessDestroyEmail`, and
  `getBoth` is total over its absence.
- **Why kept:** in observed server behaviour (Stalwart / Cyrus / Apache James)
  the implicit `Email/set` response is returned only when an `onSuccess*`
  argument requested a change — the baseline fixtures return just
  `EmailSubmission/set`, the on-success fixtures return both. Reading §7.5 ¶3's
  *"to perform any changes requested in these two arguments"* as the operative
  condition, the library models the implicit handle as `Opt` and stays liberal
  on receive rather than demanding the unconditional response the literal `MUST`
  describes. This is receive-only — the client still *sends* the `onSuccess*`
  arguments per the RFC; only its expectation of the response is relaxed.

---

*Each entry is the considered, documented choice. Revisit an entry if a target
server's behaviour changes or if a future strict-conformance mode is wanted; do
not silently "fix" any of them — they exist to talk to real servers.*
