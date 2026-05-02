# Integration Testing Plan — Phase F

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **F0 — Devcontainer SMTP enablement** | **Done** (2026-05-02, `672aa4a`) | Pre-flight live probe confirmed Stalwart 0.15.5's defaults already provide the SMTP listener (`[server.listener.smtp] bind = "[::]:25"`), the `route.local` queue with the local-delivery worker, and the `urn:ietf:params:jmap:submission` capability on alice's session. F0 contributes only a JMAP-level smoke check appended to `seed-stalwart.sh` that fails fast if any of these regresses on a Stalwart upgrade — no `stalwart.toml` overlay, no `docker-compose.yml` change. |
| **F0.5 — `mlive` helper extraction** | **Done** (2026-05-02, `05fccd8`) | Six helpers landed: `resolveSubmissionAccountId`, `buildEnvelope`, `resolveOrCreateDrafts`, `resolveOrCreateSent`, `seedDraftEmail`, `pollSubmissionDelivery`. The `buildEnvelope` helper is an addition over the original plan — it absorbs the four-stage RFC5321Mailbox / SubmissionAddress / ReversePath / NonEmptyRcptList boilerplate that Steps 32–36 each need. |
| **F1 — EmailSubmission end-to-end + full Identity CRUD (six steps)** | **Done** (2026-05-02) | Steps 31–36 landed at `850cc13`, `9a95bb5`, `59aeb8a`, `5df9cea`, `99cd937`, and the Step 36 commit. Cumulative live tests: **34 / 34**. Cumulative captured-replay tests: **30 / 30** (23 base + 7 new from Phase F). |

Live-test pass rate (cumulative across A + B + C + D + E + F):
**34 / 34** (`*_live.nim` files run by `just test-integration`; the 28
pre-Phase-F + 6 new from Phase F).

## Catalogued divergences

Three pre-flight assumptions amended at execution time:

1. **Stalwart's `EmailSubmissionCreatedItem` payload is partial.**
   The strict typed parser at `serde_email_submission.nim` required
   `id`, `threadId`, and `sendAt` for every successful create. Stalwart
   0.15.5 returns just `{"id": "<id>"}`. Resolved at the parser layer
   in the Step 32 commit (`9a95bb5`): `threadId` and `sendAt` lifted to
   `Opt[T]` in `email_submission.nim`, the `fromJson` skips on absent
   per Postel's law. Mirrors the existing `IdentityCreatedItem.mayDelete`
   and `MailboxCreatedItem` count-field accommodations.
2. **Stalwart's `route.local` queue does not synthesise a DSN.**
   The plan's Step 33 expected `delivered.state == dsYes` for local-
   domain delivery; Stalwart actually reports `dsUnknown` because the
   queue worker deposits the message in bob's mailbox without
   generating a DSN. The SMTP reply (`250 2.1.5 Queued`) round-trips
   cleanly with the RFC 3463 enhanced status code. Resolved at the
   test layer.
3. **Stalwart projects bogus `sinceState` as `metInvalidArguments`.**
   RFC 8620 §5.5 permits either `cannotCalculateChanges` or
   `invalidArguments`; the plan asserted only `cannotCalculateChanges`.
   Step 36 uses set membership (`{metCannotCalculateChanges,
   metInvalidArguments}`), matching the pattern set by the existing
   Phase B `tcaptured_email_changes_bogus` replay test.

Three minor F-doc API errors were noted in the implementation plan
and corrected at the test layer rather than amended in this doc:
`parseEmailSubmissionBlueprint` takes `emailId: Id` directly (not
`directRef(...)`); `DeliveryStatus.smtpReply` is already
`ParsedSmtpReply` (no double-parse); the EmailUpdate constructor is
`initEmailUpdateSet` and the keyword set constructor is
`initKeywordSet`.

## Context

Phase E closed on 2026-05-02 with 28 live tests passing in ~10 s
against Stalwart 0.15.5. The integration-testing campaign now covers
every read-side mail surface RFC 8621 specifies, the entity-creation
half of `Mailbox/set`, `Identity/set`, `VacationResponse/set`, the
keyword-flip half of `Email/set`, full `Mailbox/set` CRUD with cascade
semantics, server-side `Email/copy` and `Email/import`, and
`Email/query` pagination across `position`, `anchor`, `anchorOffset`,
`calculateTotal`, plus the `metAnchorNotFound` error variant.

Three RFC 8621 surfaces remain unexercised against any server:

- **EmailSubmission §7** —
  `EmailSubmission/{set,get,changes,query,queryChanges}`, the
  `onSuccessUpdateEmail`/`DestroyEmail` implicit-chain machinery,
  `DeliveryStatus`, and `ParsedSmtpReply` with RFC 3464 enhanced
  status codes.
- **Identity full CRUD** — Phase A Step 5 created identities and
  read them back; updates (`IdentityUpdate` arms `setName`,
  `setReplyTo`, `setBcc`, `setTextSignature`, `setHtmlSignature`)
  and destroys never went over the wire.
- (Multi-account ACL — deferred to Phase G; adversarial wire formats
  — deferred to Phase H.)

The library implements these surfaces fully (verified 2026-05-02):
the GADT-indexed `EmailSubmission[S: static UndoStatus]` with
existential `AnyEmailSubmission` wrapper, `EmailSubmissionBlueprint`,
`EmailSubmissionUpdate` (single `esuSetUndoStatusToCanceled` variant),
`IdOrCreationRef` (icrDirect/icrCreation discriminated union),
`NonEmptyOnSuccessUpdateEmail`/`Destroy` containers, and full
`IdentityUpdate` algebra. The entity-specific compound builder
`addEmailSubmissionAndEmailSet` returns
`CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]`
extractable via the generic `getBoth`. No typedesc-`fromJson` wrapper
gaps exist (the historical Phase D D0.5 / Phase C Step 16 pattern is
not needed here — verified at `serde_email_submission.nim:132` and
`serde_identity.nim:149`).

The campaign's gap is therefore on the wire side. Phase F closes it.

## Strategy

Continue Phase A–E's bottom-up discipline. Each step adds **exactly
one new dimension** the prior steps have not touched. When Step N
fails, Steps 1..N-1 have been proven, so the bug is isolated.

Phase F's single biggest dependency is **Stalwart's local SMTP
delivery path**. Phase E ran exclusively on the JMAP port (8080)
because every prior surface was JMAP-internal. EmailSubmission is the
first surface where Stalwart's MTA half is exercised: alice POSTs an
`EmailSubmission/set` over JMAP, Stalwart enqueues the message, the
local-delivery worker walks the queue, looks up `bob@example.com`
against the local directory, and deposits the message in bob's inbox.
Without that pipeline, `DeliveryStatus.delivered` stays `"queued"` (or
becomes `"failed"`) indefinitely and `ParsedSmtpReply` carries no
useful wire content.

Phase F0 makes the pipeline work. Phase F0.5 adds the helpers Phase
F1 needs. Phase F1 then runs the six live tests in build order:

1. **Step 31** — Identity update + destroy. The simplest dimension
   that depends on F0 *not at all*; if Step 31 fails, the bug is in
   `IdentityUpdate` wire emission, not in submission.
2. **Step 32** — `EmailSubmission/set` baseline (alice → bob). First
   exercise of F0's SMTP path.
3. **Step 33** — `EmailSubmission/get` with `DeliveryStatus` +
   `ParsedSmtpReply` parsing. Read-side validation.
4. **Step 34** — `onSuccessUpdateEmail` chained `Email/set`. First
   exercise of `CompoundHandles[A, B]` for submission.
5. **Step 35** — `onSuccessDestroyEmail` chained destroy. Parallel
   arm to Step 34.
6. **Step 36** — `EmailSubmission/changes` + `queryChanges`.
   Capstone — mirrors Phase B Steps 11–12 applied to the new entity.

Step 36 is visibly harder than Step 31 by construction, mirroring
Phase A Step 7, B Step 12, C Step 18, D Step 24, E Step 30. The
asymmetry is intentional: the climb stays inside Phase F.

## Phase F0 — Devcontainer SMTP enablement

**Non-negotiable prerequisite.** Phase F cannot proceed without local
SMTP loopback delivery from `alice@example.com` to `bob@example.com`.
The current devcontainer (verified 2026-05-02) is JMAP-only:
`.devcontainer/docker-compose.yml` exposes only `8080:8080`, no
`stalwart.toml` is mounted, and `seed-stalwart.sh` creates bob without
any SMTP-path validation.

### Required changes

1. **Author `.devcontainer/config/stalwart.toml`** — minimal config
   enabling:
   - SMTP listener bound to `0.0.0.0:25` inside the container
     (loopback-only delivery; no TLS required for same-container
     traffic).
   - `example.com` declared as a local-delivery domain (Stalwart's
     `directory.local-domains` or equivalent — exact key verified at
     execution time against Stalwart 0.15 docs).
   - Queue → local-mailbox delivery enabled for the local domain
     (deposits messages directly into the recipient's JMAP inbox; no
     external relay attempted).
   - DKIM/SPF set to permissive or self-signed so loopback delivery
     does not require external DNS validation.

2. **Update `.devcontainer/docker-compose.yml`** — mount the new
   config: `volumes: - ./config/stalwart.toml:/opt/stalwart/etc/config.toml:ro`
   (mount path verified against Stalwart's image layout). External
   SMTP port exposure is optional (delivery is internal); add
   `ports: - "2525:25"` only if diagnostics require it.

3. **Update `.devcontainer/scripts/seed-stalwart.sh`** — extend the
   readiness loop with a delivery-path smoke check after principal
   seeding. The check submits a one-off `EmailSubmission/set` from
   alice to bob and polls `EmailSubmission/get` for `undoStatus ==
   "final"` within a 10 s budget; if the smoke fails, exit non-zero
   so `just stalwart-up` surfaces the regression early.

4. **`tests/integration/live/mconfig.nim`** — current contract
   (`JMAP_TEST_BOB_TOKEN` already present) is sufficient. Phase F
   tests fetch bob's session and resolve his accounts via JMAP rather
   than hard-coded env vars; no contract change needed.

5. **No new Nimble dependencies, no new devcontainer packages** —
   devcontainer-parity rule (Phase A §Step 6 retro at
   `01-integration-testing-A.md:249-255`) holds. Stalwart config
   additions live under `.devcontainer/` and are reproducible by any
   developer.

### Verification

A standalone smoke test (separate from F1's live tests) must pass
before F0.5 / F1 begin:

- `just stalwart-reset` succeeds.
- The seed script's delivery-path smoke check succeeds.
- A one-off Nim test (or `curl` script) issues an `EmailSubmission/set`
  from alice with bob as the recipient. Within 5 s, `Email/get`
  against bob's account returns the message in his Inbox.
- The submission's read-back `DeliveryStatus` map carries an entry
  keyed by `"bob@example.com"` with `delivered` ∈ {`"queued"`,
  `"yes"`} and a non-empty `smtpReply` field.

If the smoke test fails, F0 has not landed. F0.5 / F1 are blocked.

## Phase F0.5 — `mlive` helper extraction

Single commit. Mirrors the Phase B / C0 / D0 / E0 precedents.
Helpers land before any test consumes them.

### `resolveSubmissionAccountId`

```nim
func resolveSubmissionAccountId*(
    session: Session
): Result[AccountId, string]
```

Reads `session.primaryAccounts` for `"urn:ietf:params:jmap:submission"`.
Pure helper; structurally adjacent to the existing
`resolveCollationAlgorithms` (also pure, also session-only). Used by
Steps 31–36.

### `seedDraftEmail`

```nim
proc seedDraftEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    draftsMailbox: Id,
    fromAddr: EmailAddress,
    toAddr: EmailAddress,
    subject: string,
    body: string,
    creationLabel: string,
): Result[Id, string]
```

Variant of `seedSimpleEmail` targeting the Drafts mailbox, with
parameterised from/to addresses (rather than always `buildAliceAddr`
on both sides). Sets `keywords = {"$draft": true}` so Stalwart treats
it as a draft. Funnels through the existing private `emailSetCreate`.
Used by Steps 32–35.

### `resolveOrCreateDrafts` and `resolveOrCreateSent`

```nim
proc resolveOrCreateDrafts*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string]

proc resolveOrCreateSent*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string]
```

Locate (or create) the Drafts/Sent-roled mailboxes. Mirrors
`resolveOrCreateMailbox` from Phase E0 but matches by RFC 8621 §2.2
role, not by name. Stalwart 0.15.5 may auto-create on first principal
use; the helpers stay idempotent across re-runs.

### `pollSubmissionDelivery`

```nim
proc pollSubmissionDelivery*(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    budgetMs: int = 5000,
): Result[EmailSubmission[usFinal], string]
```

Poll loop (200 ms intervals) issuing `EmailSubmission/get` until
`undoStatus == final` or the budget elapses. Returns the
phantom-narrowed `EmailSubmission[usFinal]` on success. Mirrors Phase
C Step 18's threading-asynchrony re-fetch pattern. Used by Steps
32–36.

### Commit shape

One commit. SPDX header preserved. Helpers added in source order
(pure helpers before IO helpers). No existing helper modified. Must
pass `just test` (helpers are unused at this commit).

## Phase F1 — six live tests

Each test follows the project test idiom verbatim (`block <name>:` +
`doAssert`) and is gated on `loadLiveTestConfig().isOk` so the file
joins testament's megatest cleanly under `just test-full` when env
vars are absent. All six are listed in `tests/testament_skip.txt` so
`just test` skips them; run via `just test-integration`.

### Step 31 — `tidentity_set_crud_live`

Closes Phase A Step 5's create-only boundary. Validates the full
Identity CRUD path: create → update via each `IdentityUpdate` arm →
destroy.

Body — five sequential `client.send` calls in one block:

1. Resolve submission account.
2. `addIdentitySet(create = ...)` with one `IdentityCreate` carrying
   `email = "alice@example.com"` + `name = "phase-f step-31 initial"`.
   Capture `identityId`.
3. `addIdentitySet(update = ...)` with `IdentityUpdateSet` carrying
   `setName("phase-f step-31 renamed")` + `setReplyTo([replytoAddr])`
   + `setTextSignature("phase-f sig")`. Assert
   `updateResults[identityId].isOk`.
4. `addIdentityGet(ids = directIds(@[identityId]))`. Assert `name ==
   "phase-f step-31 renamed"`, `replyTo` populated, `textSignature ==
   "phase-f sig"`.
5. `addIdentitySet(destroy = directIds(@[identityId]))`. Assert
   `destroyResults[identityId].isOk`.

Capture: `identity-set-update-stalwart` after the update leg.

What this proves:

- `IdentityUpdate` case-object → wire patch shape Stalwart accepts
- `IdentityUpdateSet` and `NonEmptyIdentityUpdates` containers
  serialise correctly
- Identity destroy round-trips through `SetResponse[IdentityCreatedItem]`
  `destroyResults`
- `mayDelete: true` is honoured for self-created identities

### Step 32 — `temail_submission_set_baseline_live`

First wire test of `EmailSubmission/set`. Validates the simplest
happy-path send: a Draft from alice to bob, submitted via
`EmailSubmissionBlueprint`.

Body — five sequential `client.send` calls plus one poll:

1. Resolve mail and submission accounts. Resolve (create if absent)
   alice's Identity. Resolve Drafts via `resolveOrCreateDrafts`.
2. `seedDraftEmail` → captures `draftId`.
3. Build `EmailSubmissionBlueprint(identityId = aliceIdentityId,
   emailId = directRef(draftId), envelope = Envelope(mailFrom =
   alice, rcptTo = [bob]))`. Issue
   `addEmailSubmissionSet(create = {cid: blueprint})`.
4. Assert `setResp.createResults[cid].isOk`. Capture `submissionId`.
5. `pollSubmissionDelivery(submissionAccountId, submissionId)` →
   `Ok(EmailSubmission[usFinal])`.

Capture: `email-submission-set-baseline-stalwart` after the
submission send.

What this proves:

- `EmailSubmissionBlueprint` → wire shape Stalwart accepts
- `IdOrCreationRef` (icrDirect arm) wire emission for `emailId`
- `Envelope` + `Address` wire shapes
- F0's local-delivery pipeline completes inside the budget
- `EmailSubmissionCreatedItem` partial response (RFC 8620 §5.3
  server-set-subset) parses correctly

### Step 33 — `temail_submission_get_delivery_status_live`

Read back the submission, fully validating `DeliveryStatus` and
`ParsedSmtpReply` parsing.

Body — three sequential `client.send` calls plus a poll:

1. Resolve accounts. Run a Step 32-style seed-and-submit; if Step
   32 surfaces a "submit-then-fetch" duplication, an `mlive` helper
   `seedAndSubmit` may be added during F0.5 implementation.
2. After `pollSubmissionDelivery`, issue
   `addEmailSubmissionGet(ids = directIds(@[submissionId]),
   properties = Opt.none(seq[string]))` (full property fetch).
3. Pattern-match the typed `AnyEmailSubmission` via `asFinal()`
   returning `Opt[EmailSubmission[usFinal]]`. Assert:
   - `submission.deliveryStatus.isSome` and contains an entry keyed
     by `"bob@example.com"`
   - The entry's `delivered ∈ {"yes", "queued"}`
   - The entry's `smtpReply` parses via `parseSmtpReply` and
     `parsed.code == 250` (RFC 3464 success)
   - `undoStatus == usFinal`

Capture: `email-submission-get-delivery-status-stalwart`.

What this proves:

- Phantom-narrowed `EmailSubmission[usFinal]` extraction via
  `asFinal()`
- `DeliveryStatus` map (`Table[string, DeliveryStatus]`)
  deserialisation
- `ParsedSmtpReply` parsing of Stalwart's actual SMTP reply line
- The full read-side shape of EmailSubmission is wire-compatible

### Step 34 — `temail_submission_on_success_update_live`

First wire exercise of `addEmailSubmissionAndEmailSet` with
`onSuccessUpdateEmail`. Submission succeeds → Stalwart auto-issues
`Email/set update` against the draft, moving Drafts → Sent + flipping
`$draft → $seen`.

Body — four sequential `client.send` calls plus a poll:

1. Resolve accounts and Drafts/Sent mailboxes.
2. `seedDraftEmail` → `draftId`.
3. Build `EmailSubmissionBlueprint`. Build `NonEmptyOnSuccessUpdateEmail`
   with one entry: `draftId → PatchObject` removing the Drafts
   mailbox, adding the Sent mailbox, removing `$draft`, adding
   `$seen`. Issue `addEmailSubmissionAndEmailSet(create = {cid:
   blueprint}, onSuccessUpdateEmail = Opt.some(map))`.
4. Extract via `resp.getBoth(handles)` returning
   `(EmailSubmissionSetResponse, SetResponse[EmailCreatedItem])`.
   Assert both rails:
   - Submission `createResults[cid].isOk`
   - Implicit Email/set `updateResults[draftId].isOk`
5. `pollSubmissionDelivery` then `addEmailGet(ids =
   directIds(@[draftId]), properties = Opt.some(@["mailboxIds",
   "keywords"]))`. Assert:
   - `mailboxIds` contains `sentId == true`, `draftsId` absent
   - `keywords["$draft"]` absent, `keywords["$seen"] == true`

Capture: `email-submission-on-success-update-stalwart`.

What this proves:

- `CompoundHandles[EmailSubmissionSetResponse,
  SetResponse[EmailCreatedItem]]` extraction via `getBoth`
- `NonEmptyOnSuccessUpdateEmail` wire emission (object map per RFC
  8621 §7.5 ¶3)
- Stalwart's implicit-chain machinery actually fires
- `PatchObject` with JSON-Pointer keyed paths for `mailboxIds` flip
  and `keywords` flip

### Step 35 — `temail_submission_on_success_destroy_live`

Parallel arm to Step 34. Submission succeeds → Stalwart auto-issues
`Email/set destroy` against the draft.

Body — four sequential `client.send` calls plus a poll:

1. Resolve accounts and Drafts mailbox.
2. `seedDraftEmail` → `draftId`.
3. Build blueprint + `NonEmptyOnSuccessDestroyEmail([draftId])`. Issue
   `addEmailSubmissionAndEmailSet(create = {cid: blueprint},
   onSuccessDestroyEmail = Opt.some(seq))`.
4. Extract via `resp.getBoth(handles)`. Assert:
   - Submission `createResults[cid].isOk`
   - Implicit Email/set `destroyResults[draftId].isOk`
5. `pollSubmissionDelivery` then `addEmailGet(ids =
   directIds(@[draftId]))`. Assert `getResp.list.len == 0` and
   `draftId in getResp.notFound`.

Capture: `email-submission-on-success-destroy-stalwart`.

What this proves:

- `NonEmptyOnSuccessDestroyEmail` wire emission (array per RFC 8621
  §7.5 ¶3)
- Implicit Email/set destroy actually runs
- `getBoth` discriminates the chained `SetResponse[EmailCreatedItem]`
  from the parent submission response

### Step 36 — `temail_submission_changes_live`

Capstone. `EmailSubmission/changes` and
`EmailSubmission/queryChanges`. Mirrors Phase B Steps 11–12 applied
to submission. Most ambitious step in Phase F.

Body — six sequential `client.send` calls plus polls:

1. Resolve accounts.
2. `addEmailSubmissionGet(ids = directIds(@[]))` — empty-id
   baseline. Capture `baselineState`.
3. `addEmailSubmissionQuery(b, submissionAccountId)` — empty-filter
   baseline. Capture `baselineQueryState`.
4. Two sequential seed-and-submits (each is a logical sub-step
   composed of multiple HTTP calls — drafts, submissions, polls).
5. **Changes happy + sad in one combined Request** (two invocations
   in one HTTP call, mirroring Phase B Step 11):
   - Happy: `addChanges[AnyEmailSubmission](b, submissionAccountId,
     sinceState = baselineState)`. Assert `oldState == baselineState`,
     `created.len >= 2`, `updated.len == 0`, `destroyed.len == 0`.
   - Sad: `addChanges[AnyEmailSubmission](b, submissionAccountId,
     sinceState = JmapState("phase-f-bogus"))`. Assert err with
     `errorType ∈ {metCannotCalculateChanges, metInvalidArguments}`
     (both RFC-compliant per Phase B Step 11's catalogue).
6. **QueryChanges happy path** —
   `addEmailSubmissionQueryChanges(b, submissionAccountId,
   sinceQueryState = baselineQueryState, calculateTotal = true)`.
   Assert `oldQueryState == baselineQueryState`, `newQueryState !=
   baselineQueryState`, `total.isSome and total.unsafeGet >=
   UnsignedInt(2)`, `added.len >= 2`.

Captures: `email-submission-changes-stalwart` (leg 5 happy),
`email-submission-query-changes-stalwart` (leg 6).

What this proves:

- `addChanges[AnyEmailSubmission]` template resolves the registration
  correctly (no entity-specific overload exists — first test of the
  generic path for submissions)
- `ChangesResponse[AnyEmailSubmission]` deserialises with all six
  fields
- `addEmailSubmissionQueryChanges` builder emits the wire shape
  Stalwart accepts
- `QueryChangesResponse[AnyEmailSubmission]` deserialises including
  `total` when `calculateTotal=true`
- The state-delta protocol works on an entity that genuinely
  transitions (submission state changes as the queue processes)

## Captured-fixture additions

Seven new fixtures committed under `tests/testdata/captured/` (Step
36 captures two distinct legs):

- `identity-set-update-stalwart`
- `email-submission-set-baseline-stalwart`
- `email-submission-get-delivery-status-stalwart`
- `email-submission-on-success-update-stalwart`
- `email-submission-on-success-destroy-stalwart`
- `email-submission-changes-stalwart`
- `email-submission-query-changes-stalwart`

Seven always-on parser-only replay tests under `tests/serde/captured/`,
one per fixture. Variant assertions are precise where the RFC pins
the wire shape (`undoStatus == usFinal`, `setForbidden`); structural
where the wire has run-dependent content
(`deliveryStatus.len >= 1`, `submission ids non-empty`, `total >= 2`).

NOT listed in `testament_skip.txt`. Cumulative captured-replay total
rises from 23 to 30.

## Predictable wire-format divergences (Phase F catalogue)

Forward-looking — to be confirmed during F1 execution and amended
in-flight per Phase E precedent.

1. **DeliveryStatus timing.** Stalwart's local-delivery worker is
   asynchronous; `undoStatus` may read `pending` immediately after
   `EmailSubmission/set`. `pollSubmissionDelivery` covers it; the
   fix is at the test layer (extend budget) NOT at the parser.
2. **SmtpReply enhanced status codes.** RFC 3464 §4.2 makes enhanced
   codes OPTIONAL. Tests assert `code == 250` (basic) but never
   assert enhanced-code presence.
3. **DeliveryStatus map keying.** RFC 8621 §7 keys the map by
   recipient email address (string). If Stalwart 0.15.5 keys by
   recipient index or another shape, `serde_email_submission.nim`'s
   map deserialiser is the correct fix layer.
4. **Implicit chain ordering.** RFC 8621 §7.5 ¶3 says
   `onSuccessUpdateEmail` runs after the submission's `created`
   outcome. Tests assert both rails independently rather than fixing
   a relative order.
5. **EmailSubmission undoStatus enum extension.** If Stalwart emits
   a value outside `{usPending, usFinal, usCanceled}` (e.g.,
   `"bouncing"`), the parser projects through the existential
   `AnyEmailSubmission` arm; investigate whether to extend the enum
   or document the Stalwart-specific projection.
6. **Identity destroy permissions.** RFC 8621 §6.5: an Identity
   referenced by an existing EmailSubmission MUST NOT be destroyable.
   Step 31 destroys before any submission, so the path stays clean;
   if a future step crosses this boundary, the captured fixture pins
   Stalwart's actual SetError variant.

## Success criteria

Phase F is complete:

- [x] **Phase F0's devcontainer SMTP enablement** is verified —
  alice → bob loopback delivery completes in ~110 ms through
  `just stalwart-up`'s seed smoke check (no TOML overlay needed;
  Stalwart 0.15.5 defaults sufficed)
- [x] Phase F0.5's `mlive.nim` helper-extraction commit landed
  with six helpers (`resolveSubmissionAccountId`, `buildEnvelope`,
  `resolveOrCreateDrafts`, `resolveOrCreateSent`,
  `seedDraftEmail`, `pollSubmissionDelivery`); all consumed by
  Phase F tests
- [x] All six new live test files exist under
  `tests/integration/live/` following the established idiom
- [x] All six new files are listed in `tests/testament_skip.txt`
- [x] `just test-integration` exits 0 with **thirty-four** live
  tests passing (28 from A–E + 6 from F1)
- [x] Seven new captured fixtures exist under
  `tests/testdata/captured/`
- [x] Seven new always-on parser-only replay tests exist under
  `tests/serde/captured/` and pass under `just test` (cumulative
  count: 30)
- [x] No new Nimble dependencies; Stalwart config additions live
  under `.devcontainer/` and are reproducible
- [x] Every divergence between Stalwart's wire shape and the
  test's expected behaviour was catalogued in the section above
  and resolved at the right layer (parser fix for the partial
  `EmailSubmissionCreatedItem`; test-layer adjustment for
  `dsUnknown` and the `metInvalidArguments` projection)

## Out of scope for Phase F

Explicitly deferred to later phases:

- **Multi-account ACL** — alice ↔ bob shared mailbox access,
  `Email/copy` *across* `accountId` boundaries with `fromAccountId
  != accountId`, `forbidden` SetError variants on cross-account
  writes — Phase G.
- **Adversarial wire-format edge cases** — RFC 2047 encoded-word
  names in `EmailAddress.name`, fractional-second dates,
  empty-vs-null table entries, oversize at `maxSizeRequest`,
  control-character handling at byte boundaries,
  `maxBodyValueBytes` truncation marker, `metUnsupportedFilter` /
  `metUnsupportedSort` via raw-JSON injection bypassing the sealed
  builders — Phase H.
- **EmailSubmission filter + sort against a real corpus** —
  `EmailSubmissionFilterCondition` (`identityIds`, `emailIds`,
  `threadIds`, `undoStatus`, `before`, `after`) and
  `EmailSubmissionComparator` (`emailId`/`threadId`/`sentAt`/
  `identityId`) — natural follow-up; could extend Phase F if scope
  expands or land in an optional Phase J.
- **Header-form completeness** — `header:Foo:asMessageIds`,
  `asText`, `:all` ordering semantics (Phase D Step 22 covered
  only `urls`/`date`/`addresses`) — optional Phase I.
- **Email/set update beyond keyword + mailbox flips** — header
  replacement via patches, body content updates — optional Phase I.
- **Push notifications, blob upload/download, Layer 5 C ABI** —
  not yet implemented in the library; not part of the
  integration-testing campaign at all until they exist.
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in
  `tests/stress/` if/when it becomes a goal.

Phase G will exercise multi-account ACL and cross-account
`Email/copy` once Phase F's submission machinery is proven.
