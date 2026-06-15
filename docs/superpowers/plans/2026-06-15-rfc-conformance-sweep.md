<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# RFC-conformance sweep — plan + findings ledger

> Post-S2 sub-project (user-approved). A whole-codebase audit of the jmap-client
> protocol surface against the authoritative RFC text (`docs/rfcs/`), because the
> S2 work found three agent-doc-vs-RFC conflicts (D5/B12/H1b). Branch
> `api/rfc-conformance-sweep` off `main` (after S2 merged, PR #7). Authority rule:
> the RFC governs; `docs/design/*` and the D/A/B decisions are fallible. See
> [[rfc-is-authoritative]].

## STATE / HANDOFF (update as each fix lands)

- **Branch:** `api/rfc-conformance-sweep` (off `main`, post-S2).
- **Verification:** `just build` per fix; both gates (`just ci` + `clean &&
  jmap-reset && test-full`) at the end. Linux-kernel commits, 3 trailers.
- **Status:** 🔜 starting.
  - F1 header-null bug ⬜ · F2 mrSubscriptions ⬜ · F3 D5 toJson→fixture ⬜ ·
    F4 VacationResponse vrgkId ⬜ · F5 deviation-register doc ⬜ · Gates ⬜.

## Findings ledger (from the 9-auditor RFC audit; high overall conformance)

### F1 — 🔴 HIGH-STAKES BUG: parseHeaderValue rejects JSON null (RFC 8621 §4.1.3)

`serde_headers.nim` `parseHeaderValue` rejects `null` for the four single-instance
forms `hfRaw`/`hfText`/`hfAddresses`/`hfGroupedAddresses` (they `?expectKind`
JString/JArray). RFC 8621 §4.1.3: a requested-but-absent single-instance header
returns `null` ("the value is null if fetching a single instance"). So the library
**cannot parse a conformant `Email/get` response that requested a header the message
lacks** — it errors on the receive path (`serde_email.nim` dynamic-header loop). The
3 nullable forms (`hfMessageIds`/`hfDate`/`hfUrls`) already handle null via `Opt`
arms. **Fix:** widen the 4 non-Opt `HeaderValue` arms to `Opt` (matching the 3 Opt
arms + the project's no-conflation principle), map `null`→`Opt.none` in
parseHeaderValue, emit `null` on `none` in toJson. TDD: round-trip
`{"header:Subject:asText": null}` and `{"header:X:asAddresses": null}`. Verify the
`:all` path (`parseHeaderValueArray` treats null as empty via `getElems` — confirm
that matches "empty array if requesting :all").

### F2 — 🟡 mrSubscriptions is not an IANA mailbox role (RFC 8621 §2)

`mailbox.nim` hardcodes `mrSubscriptions = "subscriptions"` as a well-known
MailboxRole + a PUBLIC `roleSubscriptions` const. `"subscriptions"` is NOT in the
IANA "IMAP Mailbox Name Attributes" registry RFC 8621 §2 requires roles to come from
(closest real attribute is `\Subscribed` → `"subscribed"`). The design doc mis-cited
RFC 5465 (which is Sieve, unrelated). The public const lets a consumer emit a
non-registry role on `Mailbox/set` → latent client→server §2 violation. **Fix:**
remove `mrSubscriptions`/`roleSubscriptions` (unknown roles already round-trip via
`mrOther`); correct/delete the RFC 5465 citation in the design doc. (Verify against
the IANA registry first.)

### F3 — 🟡 D5 (low-stakes): full-object Email/Mailbox.toJson emits null-for-none

`serde_email.nim` `Email.toJson` + `serde_mailbox.nim` `Mailbox.toJson` emit `null`
for every `Opt.none`, which would violate RFC 8620 §5.1 ("only the properties listed
are returned") IF used to build a `/get` response. **Verified no production caller**
(builders use creation models / PatchObject / Partial*; real responses parse via
`PartialEmail.fromJson` and emit via `PartialEmail.toJson`, which correctly omits
absent fields). **Fix:** rename to `toJsonForFixture` (or gate behind a define) +
comment pinning it to fixture use, so it can never be reused as a response
serialiser. Confirm with a grep first. Do NOT touch `Partial*.toJson` (RFC-correct).

### F4 — 🟡 VacationResponse vrgkId selector has no Partial field

`vacation.nim` `/get` selector exposes `vrgkId` but `PartialVacationResponse` has no
`id` field; the id is the compile-time constant `"singleton"`. **Fix:** drop `vrgkId`
(simplest; the value is a known constant) and document the singleton id is derived.

### F5 — 🟢 Deviation register (the 6 kept Postel divergences)

User chose: keep the receive-side leniencies, record them in a register doc. The six:
lenient `newState` (Opt vs required, Stalwart); `parseIdFromServer`/`parseAccountId`
accept non-base64url (Postel on receive — soften the `Id` docstring's base64url
claim); `maxSizeMailboxName` Opt + `emailQuerySortOptions` HashSet (Postel +
order-irrelevant set); `mayDelete` three-state `DeleteAuthority` (more robust than the
RFC Boolean — keep); shared `SubmissionParams` for mailFrom/rcptTo (server validates
SMTP context). **Fix:** write `docs/design/known-server-deviations.md` (or similar)
with each deviation, its RFC cite, and the rationale. These are NOT bugs.

## Out of scope / verified-correct
The audit verified correct (no change): Int/UnsignedInt/Date/UTCDate validators, the
full error model, the sparse-response machinery + FieldEcho 3-state, enum
round-trips, PatchObject null semantics, Thread non-empty emailIds, SMTP param
names/NOTIFY exclusivity, SearchSnippet id-exception, PartialEmail.toJson.
