# Integration Testing Plan — Phase G

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **G0 — `mlive` helper extraction** | **Done** (2026-05-02) | Seven helpers: `initBobClient`, `buildEnvelopeWithHoldFor`, `buildEnvelopeMulti`, `resolveOrCreateAliceIdentity`, `pollSubmissionPending`, `findEmailBySubjectInMailbox`, `seedMultiRecipientDraft`. Phase F migration consolidated five identity-resolve blocks onto the new helper in the same commit. Commit `1bd7ae1`. |
| **G1 — Multi-principal observability + EmailSubmission CRUD completion (six steps)** | **Done** (2026-05-02) | Six live tests (Steps 37–42), six captured fixtures, six captured replays. Cumulative: **40/40** live tests, **36/36** captured replays. Wall-clock for the full integration run ~49 s on the devcontainer (target <60 s). Commits `f580c49`, `048d840`, `fb145f9`, `5268a42`, `de84ec3`, `d19933e`. |

Live-test pass rate target (cumulative across A + B + C + D + E + F + G):
**40 / 40** (`*_live.nim` files run by `just test-integration`; the 34
pre-Phase-G + 6 new from Phase G).

## Context

Phase F closed on 2026-05-02 with 34 live tests passing in ~16 s against
Stalwart 0.15.5. The campaign now covers every read-side mail surface
RFC 8621 specifies, full CRUD on Mailbox/Identity/VacationResponse, server-
side `Email/copy` (intra-account rejection only — RFC 8620 §5.4 forbids
`fromAccountId == accountId`), `Email/import`, `Email/query` pagination,
`Mailbox/set destroy` cascade semantics, and the EmailSubmission *create*
arm including `onSuccessUpdateEmail` / `onSuccessDestroyEmail` chains plus
`EmailSubmission/changes` and `queryChanges`.

Three concrete gaps remain in the campaign's "validate existing surface"
mission:

1. **Bob has never authenticated.** `seed-stalwart.sh` provisions bob with a
   working bearer token; `mconfig.nim` exposes `bobToken`; but every live
   test from Phase A through Phase F authenticates exclusively as alice. The
   F1 SMTP smoke check submits *to* bob but observes the delivery only via
   alice's `EmailSubmission/get` polling — never via a `Email/get` against
   bob's own account. The "did the message actually land in bob's inbox?"
   post-condition is implicit, not asserted.

2. **The cross-account rejection rail is uncatalogued.** Phase E pinned
   `Email/copy` *intra-account* rejection (`fromAccountId == accountId`,
   RFC-forbidden). The complementary case — alice's session reaching into
   bob's accountId without sharing/ACL — has never been tested, so the
   wire shape Stalwart emits for this is not in any captured fixture. The
   library implements `MethodErrorType.metAccountNotFound` and
   `metForbidden` but no live test has elicited either.

3. **EmailSubmission's `update` and `destroy` arms are unwired.** RFC 8621
   §7.5 specifies three arms on `EmailSubmission/set`: create (Phase F),
   update (only one variant: `undoStatus → canceled` per RFC 8621 §7
   "Implementations MUST allow clients to cancel sending of an
   EmailSubmission while undoStatus is 'pending'"), and destroy. The
   library implements all three with a phantom-typed
   `cancelUpdate(s: EmailSubmission[usPending])` smart constructor
   (`src/jmap_client/mail/email_submission.nim:196–212`), but Phase F1 used
   `create` exclusively. The Update arm depends on observable
   `usPending` state, which depends on `FUTURERELEASE` / `HOLDFOR` —
   advertised in Stalwart's `submissionExtensions` but never exercised.

Phase G closes all three gaps in one phase. Multi-account ACL via the
JMAP-Sharing draft and the `urn:ietf:params:jmap:principals` capability
(both Stalwart-advertised) remain explicitly out of scope: neither
appears in RFC 8620 or RFC 8621, the library has no principal/sharing
surface, and the campaign's discipline is to validate **existing
RFC-aligned surface**, not to expand it.

## Strategy

Continue Phase A–F's bottom-up discipline. Each step adds **exactly one
new dimension** the prior steps have not touched. When Step N fails,
Steps 1..N-1 have been proven, so the bug is isolated.

Phase G's dimensions, in build order:

1. **Step 37** — first non-alice authentication. Bob fetches his own
   session and reads his own Inbox. If any prior assumption about the
   `JMAP_TEST_BOB_TOKEN` contract is wrong (token format, principal-id
   resolution, Stalwart's bob-side capability advertisement), it
   surfaces here, isolated from any submission machinery.
2. **Step 38** — cross-principal observation. alice submits a known
   message to bob; bob (in the same test, via a second `JmapClient`)
   queries his own Inbox and finds it. Closes the Phase F SMTP loop with
   a true post-condition assertion.
3. **Step 39** — cross-account rejection rail. alice's session attempts
   `Email/get` against bob's accountId. Stalwart MUST reject with a
   method-level error (RFC 8620 §3.6.2). Pins the wire shape.
4. **Step 40** — multi-entry `DeliveryStatus` map. alice submits one
   message addressed to both bob and herself (self-cc). Validates that
   the map deserialiser handles >1 recipient correctly — every Phase F
   capture had exactly one entry.
5. **Step 41** — first wire test of `EmailSubmissionUpdate`. alice
   submits with `HOLDFOR=300` (5 minutes), observes `undoStatus =
   usPending`, then issues an `EmailSubmission/set update` with the
   `cancelUpdate` arm. Validates the phantom-typed transition and pins
   Stalwart's response wire shape for the canceled state.
6. **Step 42 — capstone**. Full lifecycle: HOLDFOR submission → cancel
   via Update arm → destroy via `/set destroy` arm. Three sequential
   `EmailSubmission/set` invocations exercise all three arms in one
   test, mirroring the visible-difficulty climb of Phase A Step 7,
   B Step 12, C Step 18, D Step 24, E Step 30, F Step 36.

Step 42 is visibly harder than Step 37 by construction. The asymmetry
is intentional: the climb stays inside Phase G rather than spilling
into Phase H.

## Phase G0 — preparatory `mlive` helper extraction

Single commit. Mirrors B/C0/D0/E0/F0.5 precedent. Helpers land before
any test consumes them; commit must pass `just test` (helpers are
unused at this commit).

### `initBobClient`

```nim
proc initBobClient*(cfg: LiveTestConfig): Result[JmapClient, ClientError]
```

Convenience wrapper around `initJmapClient` with bob's token. Sibling
of the alice-flavoured initialisation idiom each Phase A–F test
already inlines. Used by Steps 37, 38.

### `buildEnvelopeWithHoldFor`

```nim
func buildEnvelopeWithHoldFor*(
    fromEmail, toEmail: string, holdSeconds: UnsignedInt
): Result[Envelope, string]
```

Variant of `buildEnvelope` that attaches a `HOLDFOR=<seconds>`
parameter to the `mailFrom` `SubmissionAddress.parameters` field per
RFC 4865 §3.2. Funnels through the existing
`parseRFC5321Mailbox` / `parseSubmissionParams` / `parseNonEmptyRcptList`
chain. Used by Steps 41, 42.

### `buildEnvelopeMulti`

```nim
func buildEnvelopeMulti*(
    fromEmail: string, toEmails: openArray[string]
): Result[Envelope, string]
```

Variant of `buildEnvelope` parametrised on a *list* of envelope
recipients (`rcptTo`) rather than a single recipient. Used by Step 40
to drive the multi-entry `DeliveryStatus` map. Funnels through the
existing `parseRFC5321Mailbox` / `parseNonEmptyRcptList` chain with
each `toEmails` entry mapped to a `SubmissionAddress` whose
`parameters` field is `Opt.none(SubmissionParams)`.

### `pollSubmissionPending`

```nim
proc pollSubmissionPending*(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    budgetMs: int = 5000,
): Result[EmailSubmission[usPending], string]
```

Polls `EmailSubmission/get` every 200 ms until `undoStatus == pending`,
returning the phantom-narrowed `EmailSubmission[usPending]`. Mirrors
`pollSubmissionDelivery` (which polls for `usFinal`) but on the opposite
phantom narrowing. Used by Steps 41, 42.

### `findEmailBySubjectInMailbox`

```nim
proc findEmailBySubjectInMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    mailbox: Id,
    subject: string,
    attempts: int = 10,
    intervalMs: int = 200,
): Result[Opt[Id], string]
```

Issues `Email/query` with `filter = inMailbox + subject`, retrying up to
`attempts` times with `intervalMs` between attempts. Returns
`Opt.some(emailId)` on first match, `Opt.none` after budget elapses.
Mirrors Phase C Step 18's threading-asynchrony re-fetch pattern: SMTP
delivery from alice's submission to bob's inbox is asynchronous in
Stalwart; the test layer absorbs the pipeline delay rather than weaken
assertions. Used by Step 38.

### `seedMultiRecipientDraft`

```nim
proc seedMultiRecipientDraft*(
    client: var JmapClient,
    mailAccountId: AccountId,
    drafts: Id,
    fromAddr: EmailAddress,
    toAddrs: openArray[EmailAddress],
    subject, body, creationLabel: string,
): Result[Id, string]
```

Variant of `seedDraftEmail` parametrised on a *list* of recipients
(`to: openArray[EmailAddress]`) rather than a single recipient.
Funnels through the existing private `emailSetCreate` and `makeLeafPart`
factories. Used by Step 40.

### Commit shape

One commit. SPDX header preserved. Helpers added in source order
(`initBobClient` first as the simplest, then envelope-with-HOLDFOR,
multi-recipient envelope, polling helper, observation helper, and
finally the multi-recipient seeder). No existing helper modified. Must
pass `just test`.

## Phase G1 — six live tests

Each test follows the project test idiom verbatim (`block <name>:` +
`doAssert`) and is gated on `loadLiveTestConfig().isOk` so the file
joins testament's megatest cleanly under `just test-full` when env
vars are absent. All six are listed in `tests/testament_skip.txt` so
`just test` skips them; run via `just test-integration`.

### Step 37 — `tbob_session_smoke_live`

First non-alice authentication. Validates `JMAP_TEST_BOB_TOKEN` end-
to-end, bob's session payload deserialisation, and bob's primary
account-capability advertisement. The simplest possible Phase G test:
a single `Mailbox/get` call from bob's session to his own account.

Body — three sequential `client.send` calls in one block:

1. `bobClient = initBobClient(cfg).expect(...)`.
2. `session = bobClient.fetchSession().expect(...)`. Assert
   `session.accounts.len >= 1`, exactly one account with
   `isPersonal == true`, `isReadOnly == false`. Capture
   `bobMailAccountId = session.primaryAccounts["urn:ietf:params:jmap:mail"]`
   and assert `string(bobMailAccountId) != string(aliceMailAccountId)`
   (sanity: bob's account-id is genuinely different from alice's).
3. `addGet[Mailbox]` against `bobMailAccountId`. Assert the response
   carries at least one mailbox with `roleInbox`.

Capture: `bob-session-stalwart` after the `fetchSession`.

What this proves:

- `JMAP_TEST_BOB_TOKEN` round-trips through `initJmapClient` and
  `Basic` auth scheme exactly as alice's does
- Bob's principal id is distinct from alice's; the campaign's
  multi-principal foundation is sound
- Bob's account advertises the same capability surface as alice's
  (no Stalwart-side per-principal capability gating that would break
  Steps 38–42)

Anticipated divergences: none beyond the standard Phase A bootstrap
risks. If Stalwart 0.15.5 changes its session URL pattern between
principals, this is the test that catches it.

### Step 38 — `temail_bob_receives_alice_delivery_live`

Cross-principal observation. Closes the Phase F SMTP loop's missing
post-condition: did the alice→bob submission *actually* deposit the
message in bob's Inbox, or did it merely make Stalwart's
`EmailSubmission/get` report `undoStatus == final`?

Body — six sequential `client.send` calls split across two clients:

1. **alice setup** — `aliceClient`, fetch session, resolve mail +
   submission accounts, resolve / seed Identity, resolve Drafts.
2. **alice seed-and-submit** — `seedDraftEmail` with `subject =
   "phase-g step-38 marker " & $epochTime()` (timestamp prevents
   re-run cross-talk if a previous run's email lingers in bob's
   inbox). `addEmailSubmissionSet(create = ...)`. Send. Assert
   create OK; capture `submissionId`.
3. **alice poll-to-final** — `pollSubmissionDelivery(...)`. Assert
   Ok.
4. **bob setup** — `bobClient = initBobClient(cfg)`, fetch session,
   resolve `bobMailAccountId`, resolve bob's Inbox via
   `resolveInboxId(bobClient, bobMailAccountId)`.
5. **bob observe** — `findEmailBySubjectInMailbox(bobClient,
   bobMailAccountId, bobInboxId, subject, attempts = 10,
   intervalMs = 200).expect(...)`. Assert `Opt.some` (the
   delivered email surfaced in bob's inbox).
6. **bob full-fetch** — `addEmailGet(ids = directIds(@[bobEmailId]),
   properties = Opt.some(@["id", "subject", "from", "mailboxIds"]))`.
   Assert the email's `subject` matches the seeded subject, `from`
   contains `alice@example.com`, and `mailboxIds` contains
   `bobInboxId == true` (the message genuinely deposited into bob's
   account, not just queued under alice's accountId).

Capture: `bob-inbox-after-alice-delivery-stalwart` after the bob
full-fetch.

What this proves:

- Two `JmapClient` instances coexist in one test without state
  contamination
- Stalwart's local-delivery pipeline genuinely deposits the message
  in bob's mailbox (not merely queues at alice's send rail)
- Bob's `Email/get` surfaces alice-from messages with the correct
  `from` field and `mailboxIds` referencing his own account's mailbox
  (not alice's)
- The asynchronous SMTP pipeline converges within the
  `findEmailBySubjectInMailbox` budget; if not, extend the budget at
  the test layer per the catalogued pattern

Anticipated divergences: SMTP delivery may take longer than 2 s in
constrained CI environments; the helper's `attempts × intervalMs`
budget is tunable.

### Step 39 — `tcross_account_email_get_rejection_live`

Cross-account rejection rail. alice's session, with alice's token,
issues `Email/get` against bob's accountId. Stalwart MUST reject:
RFC 8620 §3.6.2 defines `accountNotFound` ("The accountId does not
correspond to a valid account") and `forbidden` ("the method would
violate an ACL or other permissions policy"); without sharing, an
account that exists but is not visible to the caller is functionally
equivalent to non-existent from the caller's perspective.

Body — three sequential `client.send` calls:

1. **alice setup** — `aliceClient`, fetch session, resolve
   `aliceMailAccountId`.
2. **bob accountId discovery** — `bobClient = initBobClient(cfg)`,
   fetch session, capture `bobMailAccountId`. Close `bobClient`
   immediately (bob is no longer needed; only his account-id is).
3. **alice probes bob's accountId** — `addEmailGet(aliceClient,
   bobMailAccountId, ids = directIds(@[]))`. Note: alice's bearer
   token, but a foreign accountId in the method args. Send via
   `aliceClient`. Assert `resp.get(handle).isErr` and
   `methodErr.errorType in {metAccountNotFound, metForbidden}`.
   Both are RFC-compliant; capture Stalwart's actual variant via
   `methodErr.rawType` for the divergence catalogue below.

Capture: `email-get-cross-account-rejected-stalwart` after the
probing send.

What this proves:

- The campaign's cross-account rejection rail wire shape is pinned for
  the first time
- `MethodError.fromJson` correctly projects whichever variant Stalwart
  emits
- Without the JMAP-Sharing draft, accountId-level isolation is enforced
  by the JMAP server (consistent with RFC 8620 §1.7's "no data
  dependencies between accounts" design)

Anticipated divergences: the choice between `accountNotFound` and
`forbidden` is implementation-defined per RFC 8620 §3.6.2. Document
Stalwart 0.15.5's choice in the catalogue; do not weaken the assertion
to set membership unless Stalwart's choice varies between requests.

### Step 40 — `temail_submission_multi_recipient_live`

Multi-entry `DeliveryStatus` map. Phase F's six captured EmailSubmission
fixtures all carry single-recipient DeliveryStatus payloads (alice → bob
exclusively). RFC 8621 §7 specifies the map is keyed by recipient email
address with one entry per `rcptTo` recipient. The map shape with `len
>= 2` has not been wire-tested.

Body — five sequential `client.send` calls plus one poll:

1. Resolve mail + submission accounts, Identity, Drafts.
2. Build `aliceAddr`, `bobAddr` via `parseEmailAddress`.
3. `seedMultiRecipientDraft(client, mailAccountId, draftsId,
   aliceAddr, toAddrs = @[bobAddr, aliceAddr], subject, body,
   creationLabel)` — alice→[bob, alice self-cc]. Capture `draftId`.
4. `envelope = buildEnvelopeMulti("alice@example.com",
   @["bob@example.com", "alice@example.com"]).expect(...)` — a
   multi-rcptTo envelope. RFC 5321 separates message recipients from
   envelope recipients; Stalwart's local-delivery path generates
   per-rcptTo `DeliveryStatus` entries based on the envelope. The
   helper sits in G0 so this step stays at the established
   ~120-line test footprint instead of inlining envelope
   construction.
5. `EmailSubmissionBlueprint(identityId = aliceIdentityId, emailId =
   draftId, envelope = Opt.some(envelope))`. Issue
   `addEmailSubmissionSet(create = ...)`. Send. Capture
   `submissionId`.
6. `pollSubmissionDelivery(...)`. Assert Ok.
7. `addEmailSubmissionGet(ids = directIds(@[submissionId]))`. Send.
   Pattern-match via `asFinal()`. Assert
   `submission.deliveryStatus.unsafeGet.len >= 2` (one entry per
   envelope rcptTo address). For each entry, assert
   `entry.smtpReply.parsed.code == 250`.

Capture: `email-submission-multi-recipient-delivery-stalwart` after
the `EmailSubmission/get`.

What this proves:

- `DeliveryStatusMap` (`Table[string, DeliveryStatus]`) deserialises
  correctly with multiple entries
- Stalwart's local-delivery pipeline generates per-rcptTo statuses
  even when the same domain receives multiple recipients
- The `parameters: Opt.none(SubmissionParams)` envelope wiring still
  applies when `rcptTo` carries more than one entry (no SubmissionParam
  required for multi-rcpt; the multi-entry shape is purely about
  recipient list cardinality, not parameters)

Anticipated divergences:

- Stalwart may dedupe `rcptTo` entries pointing at the same domain or
  user. If `len == 1` after submission to `[bob, alice]`, that's a
  Stalwart-specific behaviour worth cataloguing — the assertion should
  accept `len >= 1` and additionally check that bob's entry is present
  by key.
- Per-recipient SMTP reply codes may differ if Stalwart's
  local-delivery worker emits distinct `Queued` replies per recipient.
  The assertion validates `code == 250` for every entry, accepting
  any 2.x.y enhanced status code.

### Step 41 — `temail_submission_cancel_pending_live`

First wire test of `EmailSubmissionUpdate`. alice submits with
`HOLDFOR=300` (RFC 4865 §3.2; 5 minutes), observes `undoStatus =
usPending` via `pollSubmissionPending`, then issues
`EmailSubmission/set update[id] = cancelUpdate(...)`. The phantom-
typed `EmailSubmission[usPending]` returned by the polling helper
narrows the cancel constructor's input to a verifiably pending
submission.

Body — five sequential `client.send` calls plus two polls:

1. Resolve mail + submission accounts, Identity, Drafts.
2. `seedDraftEmail(...)` for a single alice→bob message. Capture
   `draftId`.
3. `envelope = buildEnvelopeWithHoldFor("alice@example.com",
   "bob@example.com", UnsignedInt(300)).expect(...)`.
4. `addEmailSubmissionSet(create = {cid: blueprint with envelope})`.
   Send. Capture `submissionId`. Note: `pollSubmissionDelivery`
   would block for ~5 minutes here because the message will not
   reach final state until HOLDFOR elapses; we use
   `pollSubmissionPending` instead.
5. `pendingSubmission = pollSubmissionPending(client,
   submissionAccountId, submissionId).expect(...)`. The helper
   returns `EmailSubmission[usPending]`, type-narrowed.
6. `cancel = cancelUpdate(pendingSubmission)`. Build
   `NonEmptyEmailSubmissionUpdates` with the single entry
   `{submissionId: cancel}`. Issue `addEmailSubmissionSet(update =
   Opt.some(updates))`. Send. Assert
   `setResp.updateResults[submissionId].isOk`.
7. **Re-fetch and validate** —
   `addEmailSubmissionGet(ids = directIds(@[submissionId]))`. Send.
   Pattern-match via `AnyEmailSubmission` and either `asCanceled()`
   or `asFinal()`. Assert one of:
   - `asCanceled().isSome` (Stalwart immediately reflects the
     canceled state)
   - `asFinal().isSome` AND the final state's `deliveryStatus`
     indicates the submission was successfully canceled before send
     (Stalwart-specific behaviour worth catalogueing)
   The test asserts membership of these accepted projections; the
   captured fixture pins Stalwart's actual choice.

Capture: `email-submission-set-canceled-stalwart` after the cancel
`update` send (request 6).

What this proves:

- `cancelUpdate(s: EmailSubmission[usPending])` smart constructor
  surfaces the canceled-state wire shape Stalwart accepts
- `NonEmptyEmailSubmissionUpdates` round-trips the single-arm
  algebra (only one variant exists in
  `EmailSubmissionUpdate`)
- `holdForParam` / `parseSubmissionParams` produce a wire shape
  Stalwart's `FUTURERELEASE` extension accepts
- Phantom-typed phase progression (usPending → usCanceled) is
  enforceable at the type level

Anticipated divergences:

- `undoStatus` transition timing after the cancel update may not be
  immediate; the test layer absorbs this with the post-update
  re-fetch's accepted-projections set
- HOLDFOR=300 was chosen as a comfortable buffer (5 minutes); if
  Stalwart enforces a maximum HOLDFOR shorter than this on local-
  delivery, the test's HOLDFOR may need to drop to 60 s. The cap
  is in `session.accountCapabilities[submission].maxDelayedSend`
  (Stalwart 0.15.5 advertises 2592000 = 30 days); 300 s is
  comfortably under any sane cap.
- Stalwart may immediately deliver instead of holding when the
  envelope's HOLDFOR is honoured by the JMAP server but not the
  underlying MTA. If `pollSubmissionPending` times out without
  observing pending state, the test fails with a clear
  diagnostic, isolating the divergence to Stalwart's HOLDFOR
  honouring rather than the library's wire-shape correctness.

### Step 42 — `temail_submission_full_lifecycle_live` (capstone)

Full CRUD lifecycle: HOLDFOR submission → cancel via Update arm →
destroy via `/set destroy` arm. Three sequential
`EmailSubmission/set` invocations exercise all three arms in one
test. Mirrors the visibly-harder capstone discipline of
A Step 7 / B Step 12 / C Step 18 / D Step 24 / E Step 30 / F Step 36.

Body — six sequential `client.send` calls plus polls:

1. Resolve accounts, Identity, Drafts. Build envelope with HOLDFOR.
2. Seed draft. Submit with HOLDFOR. Capture `submissionId`. Poll to
   pending.
3. **Cancel via Update arm** — `EmailSubmission/set update[id] =
   cancelUpdate(pending)`. Send. Assert
   `updateResults[submissionId].isOk`.
4. **Re-fetch to confirm canceled** — `EmailSubmission/get`. Pattern-
   match canceled or final-with-canceled-status.
5. **Destroy via Destroy arm** —
   `addEmailSubmissionSet(destroy = directIds(@[submissionId]))`.
   Send. Assert `destroyResults[submissionId].isOk`. RFC 8621 §7.5
   permits destroying any submission record; Stalwart's behaviour
   for destroying a freshly-canceled submission is the principal
   capture target.
6. **Re-fetch to confirm absence** — `EmailSubmission/get(ids =
   directIds(@[submissionId]))`. Assert `list.len == 0` and
   `submissionId in notFound`.

Capture: `email-submission-destroy-canceled-stalwart` after the
destroy send (request 5).

What this proves:

- All three `EmailSubmission/set` arms (`create`, `update`,
  `destroy`) round-trip through the wire layer in a single test
- Stalwart's submission record lifecycle aligns with RFC 8621 §7.5
  (canceled submissions can be destroyed; destroyed submissions are
  absent from subsequent gets)
- The phantom-typed phase progression (usPending → usCanceled →
  destroyed) is type-safe at every transition
- The campaign now covers every standard-method arm of every
  RFC 8621 entity (modulo the explicit out-of-scope items below)

Anticipated divergences:

- Destroying a non-final submission (HOLDFOR not yet elapsed but
  canceled) may behave differently from destroying a final
  submission. RFC 8621 §7.5 does not specify; Stalwart's choice is
  the capture target.
- The destroy may fail with `setForbidden` if Stalwart restricts
  who can destroy submission records (e.g., requires admin). If so,
  the assertion must amend to accept either Ok or
  setForbidden, but the more likely behaviour given Stalwart's
  permissive defaults is unconditional success.

## Captured-fixture additions

Six new fixtures committed under `tests/testdata/captured/`,
captured against a freshly reset Stalwart 0.15.5 with
`JMAP_TEST_CAPTURE=1 just test-integration`:

- `bob-session-stalwart` (Step 37)
- `bob-inbox-after-alice-delivery-stalwart` (Step 38)
- `email-get-cross-account-rejected-stalwart` (Step 39)
- `email-submission-multi-recipient-delivery-stalwart` (Step 40)
- `email-submission-set-canceled-stalwart` (Step 41)
- `email-submission-destroy-canceled-stalwart` (Step 42)

Six always-on parser-only replay tests under
`tests/serde/captured/`, one per fixture:

- `tcaptured_bob_session.nim`
- `tcaptured_bob_inbox_after_delivery.nim`
- `tcaptured_email_get_cross_account_rejected.nim`
- `tcaptured_email_submission_multi_recipient.nim`
- `tcaptured_email_submission_set_canceled.nim`
- `tcaptured_email_submission_destroy_canceled.nim`

Variant assertions are precise where the RFC pins the wire shape;
structural where the wire has run-dependent content (recipient ids,
delivery codes, server-assigned ids). NOT listed in
`testament_skip.txt`. Cumulative captured-replay total rises from 30
to **36**.

## Predictable wire-format divergences (Phase G catalogue)

Forward-looking — to be confirmed during G1 execution and amended
in-flight per Phase E precedent.

1. **Cross-account `Email/get` rejection variant.** Step 39:
   Stalwart may return `accountNotFound` (per RFC 8620 §3.6.2 if it
   treats unauthorised account access as not-existent) or
   `forbidden` (if it surfaces the existence of bob's account but
   denies access). Both are RFC-compliant. The assertion accepts
   set membership; the captured fixture pins the actual choice.

2. **`DeliveryStatus` map keying for self-cc.** Step 40: when
   `from == one of to`, Stalwart may dedupe the recipient list or
   keep both entries. RFC 8621 §7 specifies map keying by recipient
   address; if Stalwart preserves the duplicate, `len >= 2`. The
   assertion checks `len >= 1` AND validates a bob entry by key,
   accepting either dedup or preservation.

3. **`undoStatus` transition timing after cancel.** Step 41/42:
   Stalwart's queue worker may not immediately reflect the canceled
   state. The post-update re-fetch accepts either `asCanceled().isSome`
   or `asFinal().isSome` with a canceled deliveryStatus indicator;
   document Stalwart's actual choice.

4. **EmailSubmission destroy semantics on non-final submission.**
   Step 42: RFC 8621 §7.5 leaves this unspecified. Stalwart may
   succeed unconditionally, reject with `setForbidden`, or reject
   with `setNotFound` if it had auto-destroyed the submission upon
   cancel. The assertion adapts based on the captured fixture.

5. **HOLDFOR honoring boundary.** Step 41/42: Stalwart's JMAP
   server may honour HOLDFOR but the underlying MTA may not. If
   `pollSubmissionPending` times out without observing pending,
   the divergence is at the Stalwart-config layer, not the
   library wire-shape layer; isolate and document but do not amend
   the parser.

## Success criteria

Phase G is complete when:

- [ ] Phase G0's `mlive.nim` helper-extraction commit lands with
  six helpers (`initBobClient`, `buildEnvelopeWithHoldFor`,
  `buildEnvelopeMulti`, `pollSubmissionPending`,
  `findEmailBySubjectInMailbox`, `seedMultiRecipientDraft`); all
  consumed by Phase G tests
- [ ] All six new live test files exist under
  `tests/integration/live/` with the established idiom (license,
  docstring, single `block`, `loadLiveTestConfig().isOk` guard,
  explicit `client.close()` before block exit, `doAssert` with
  narrative messages)
- [ ] All six new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six, B five, C six, D six, E six, F six
- [ ] `just test-integration` exits 0 with **forty** live tests
  passing (28 from A–E + 6 from F + 6 from G — `tsession_discovery`
  does not match `*_live.nim` and is not run by the integration
  runner)
- [ ] Six new captured fixtures exist under
  `tests/testdata/captured/`
- [ ] Six new always-on parser-only replay tests exist under
  `tests/serde/captured/` and pass under `just test` (cumulative
  count: 36)
- [ ] `just ci` is green (reuse + fmt-check + lint + analyse + test)
- [ ] No new Nimble dependencies, no new devcontainer packages —
  the 2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro
  at `01-integration-testing-A.md:249-255`) holds throughout
- [ ] Every divergence between Stalwart's wire shape and the
  test's expected behaviour has been classified (test premise /
  server quirk / client bug) and resolved at the right layer; no
  test papers over a real client bug
- [ ] Total wall-clock for the new tests under 30 s on the
  devcontainer (HOLDFOR=300 wait does not block — cancellation
  intercepts it; actual added wall-clock is dominated by the
  `findEmailBySubjectInMailbox` poll budget of ~2 s plus
  `pollSubmissionPending` of ~1 s × two tests)

## Out of scope for Phase G

Explicitly deferred to later phases:

- **`Mailbox/changes` and `Mailbox/queryChanges`** — builders exist
  in the library (`src/jmap_client/mail/mail_builders.nim`) with no
  live coverage. Defer to Phase H. Mirrors Phase B's
  `Email/changes` + `queryChanges` discipline; doesn't fit Phase
  G's multi-principal / submission theme.
- **`Identity/changes` and `Identity/queryChanges`** — Phase F
  closed Identity full CRUD but didn't cover the delta protocol.
  Defer to Phase H.
- **JMAP-Sharing draft / `urn:ietf:params:jmap:principals`** —
  neither RFC 8620 nor RFC 8621 defines these surfaces. Stalwart
  advertises the principals capability URI but `Principal/get`
  returns `forbidden` ("administrator has disabled directory
  queries") under default config. The library has zero
  principal/sharing surface (`CapabilityKind` enum has 12 URIs,
  none of which is principals; `Principal` type does not exist;
  `MailboxRights` has no `mayShare` field — RFC 8621 §2 defines
  nine ACL flags, none of which is `mayShare`). Implementing
  sharing would expand library scope; the campaign's discipline
  is to validate **existing** RFC-aligned surface. Sharing is
  permanent out-of-scope until the library implements it (a
  separate plan).
- **Cross-account `Email/copy` happy path** — requires sharing/ACL
  to exist between accounts. Without sharing, alice's session
  cannot reach bob's account at all (Step 39 catalogues the
  rejection); successful cross-account writes are not testable.
  Permanent out-of-scope per the same reasoning.
- **Adversarial wire-format edge cases** — RFC 2047 encoded-word
  names, fractional-second dates, empty-vs-null table entries,
  oversize at `maxSizeRequest`, control-character handling,
  `maxBodyValueBytes` truncation marker, `metUnsupportedFilter` /
  `metUnsupportedSort` via raw-JSON injection bypassing the
  sealed builders — Phase H.
- **Header-form completeness** — `header:Foo:asMessageIds`,
  `asText`, `:all` ordering semantics (Phase D Step 22 covered
  only `urls`/`date`/`addresses`) — Phase I.
- **`Email/set update` beyond keyword + mailbox flips** — header
  replacement via patches, body content updates — Phase I.
- **EmailSubmission filter + sort against a real corpus** —
  `EmailSubmissionFilterCondition` (`identityIds`, `emailIds`,
  `threadIds`, `undoStatus`, `before`, `after`) and
  `EmailSubmissionComparator` — Phase J.
- **Push notifications, blob upload/download, Layer 5 C ABI** —
  not yet implemented in the library; not part of the
  integration-testing campaign at all until they exist.
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in
  `tests/stress/` if/when it becomes a goal.

## Retrospective (2026-05-02)

Phase G closed in eight commits. Cumulative live-test count rose from
34 to 40, captured-replay count from 30 to 36, exactly as the plan
specified. Wall-clock for the full live suite is ~49 s on the
devcontainer (target <60 s).

Commit shape:

  1. `1bd7ae1` — Phase G0 helpers + Phase F migration onto
     `resolveOrCreateAliceIdentity`
  2. `f580c49` — Step 37 `tbob_session_smoke_live`
  3. `048d840` — Step 38 `temail_bob_receives_alice_delivery_live`
  4. `fb145f9` — Step 39 `tcross_account_email_get_rejection_live`
  5. `5268a42` — Step 40 `temail_submission_multi_recipient_live`
  6. `de84ec3` — Step 41 `temail_submission_cancel_pending_live`
  7. `d19933e` — Step 42 `temail_submission_full_lifecycle_live`
     (capstone)

Predictable wire-format divergences confirmed during execution:

  1. **Cross-account `Email/get` rejection variant** (Step 39).
     Stalwart 0.15.5 returns ``forbidden`` (rather than the alternative
     ``accountNotFound``). Account exists; the caller has no read
     permission without sharing/ACL. Captured fixture pins this choice.
  2. **`DeliveryStatus` map keying for self-cc** (Step 40). Stalwart
     does NOT dedupe a self-recipient — a two-recipient envelope
     `alice → [bob, alice-self]` produces two distinct map entries
     keyed by `parseRFC5321Mailbox` of each address.
  3. **`undoStatus` transition timing after cancel** (Step 41/42).
     Stalwart reflects the canceled state synchronously on the
     post-update re-fetch — no asynchronous transition through the
     SMTP queue worker. The deterministic projection is `asCanceled`
     (rather than the alternative `asCanceled-or-final` set membership
     the original blueprint admitted).
  4. **EmailSubmission destroy semantics on freshly-canceled
     submission** (Step 42). Stalwart admits the destroy with no
     `setForbidden` / `setNotFound` rejection — outcome is `Ok` and
     the post-destroy `/get` returns an empty list with the
     `submissionId` in `notFound`.
  5. **HOLDFOR honouring boundary** (Step 41/42). Stalwart honours
     RFC 4865 `HOLDFOR=300` exactly as advertised in
     `submissionExtensions.FUTURERELEASE`; the message stays in the
     queue as `usPending` until the cancel update intercepts it.
     `pollSubmissionPending` resolves on first observation (the
     submission is pending immediately on create) so the test does
     not block on HOLDFOR elapsing.

## Forward arc (informational)

Following this campaign through the user's 8–10 phase budget:

- **Phase H** — adversarial wire formats + `Mailbox/changes` +
  `Mailbox/queryChanges` + `Identity/changes` /
  `Identity/queryChanges` (cleanup phase: closes the changes-
  protocol gaps and the Phase E-deferred adversarial work)
- **Phase I** — header-form completeness + `Email/set update`
  beyond keyword/mailbox flips (closes Phase D's narrow scope)
- **Phase J** — EmailSubmission filter+sort against a real corpus
  + final regression hardening (captures any straggler wire
  divergences)

That's nine phases total (A through J), comfortably inside the
8–10 budget with one optional slot for a hardening / regression
phase if the campaign exposes a class of issue worth a dedicated
phase.
