# Integration Testing Plan — Phase H

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **H0 — `mlive` helper extraction** | **Done** (2026-05-03) | Single helper: `captureBaselineState[T]` appended to `tests/integration/live/mlive.nim`. Consumed at four sites in Steps 43, 45, 46, 47, 48. |
| **H1 — State-delta protocol completion (six steps)** | **Done** (2026-05-03) | Six live tests (Steps 43–48) plus seven captured fixtures and seven always-on parser-only replays. Cumulative: **46 / 46** live tests, **43 / 43** captured replays. |

### Stalwart 0.15.5 empirical pins (catalogued during execution)

Each pin records Stalwart's discretionary choice within an
RFC-permitted shape; the live-test assertions remain shape-membership
and pass for any conformant server.

| Observation | Captured fixture | RFC clause |
|---|---|---|
| Bogus-`sinceState` errorType: `invalidArguments` (not `cannotCalculateChanges`) — Mailbox/Thread/Identity all behave identically | `mailbox-changes-bogus-state-stalwart.json`, `thread-changes-bogus-state-stalwart.json`, `identity-changes-bogus-state-stalwart.json` | RFC 8620 §5.5 permits either |
| `Mailbox/queryChanges` `removed`-array carries repositioning entries (same id in both `removed` and `added` for a non-cascade mutation) | `mailbox-query-changes-with-total-stalwart.json` | RFC 8620 §5.6 explicitly permits the same id in both arms to signal a sort-position change |
| `Mailbox/changes` `updatedProperties` field carries `["totalEmails", "unreadEmails", "totalThreads", "unreadThreads"]` after an email seed into a child mailbox | `combined-changes-mailbox-thread-email-stalwart.json` | RFC 8621 §2.2 server MAY emit |
| `Mailbox/changes` after `onDestroyRemoveEmails` cascade: id appears in BOTH `updated` and `destroyed` (RFC 8620 §5.2 forbids — Stalwart bug worth a follow-up focused test, not asserted in Step 48 to keep cascade-coherence concerns separate from response-shape conformance) | `cascade-changes-mailbox-email-thread-coherence-stalwart.json` | RFC 8620 §5.2 violated |
| Thread merging discretionary per RFC 8621 §3 — Stalwart 0.15.5 merges threads in Inbox synchronously (Phase C Step 18 converges in 1 s) but does NOT merge threads for emails seeded into a non-Inbox child mailbox within any practical observation window (>30 s tested, never converges) | `cascade-changes-mailbox-email-thread-coherence-stalwart.json` (six distinct threadIds for six emails) | RFC 8621 §3 makes algorithm server-discretionary |

Live-test pass rate target (cumulative across A + B + C + D + E + F + G + H):
**46 / 46** (`*_live.nim` files run by `just test-integration`; the 40
pre-Phase-H + 6 new from Phase H). Captured-replay target rises from
36 to 43.

## Context

Phase G closed on 2026-05-02 with 40 live tests passing in ~49 s
against Stalwart 0.15.5. The campaign now covers every read-side mail
surface RFC 8621 specifies, full CRUD on
Mailbox/Identity/VacationResponse, server-side `Email/copy` (intra-
account rejection only), `Email/import`, `Email/query` pagination,
`Mailbox/set destroy` cascade semantics, the EmailSubmission *create*
arm and full Update/Destroy lifecycle (Phase G), `EmailSubmission/changes`
+ `queryChanges`, multi-principal observation, and the cross-account
rejection rail.

One concrete gap remains in the campaign's "validate existing surface"
mission: the **state-delta protocol** is wire-tested only for `Email/*`
(Phase B Steps 11–12) and `EmailSubmission/*` (Phase F Step 36). The
library implements `*/changes` for **six** entities — `Email`,
`EmailSubmission`, `Mailbox`, `Thread`, `Identity`, plus the existential
`AnyEmailSubmission` — verified at `src/jmap_client/mail/mail_entities.nim`
via the `registerJmapEntity` macro calls (lines 66, 122, 198, 290, 363).
Three entity surfaces remain unexercised against Stalwart's wire:

1. **`Mailbox/changes` and `Mailbox/queryChanges`.** Mailbox carries an
   *extended* changes response per RFC 8621 §2.2 — Stalwart MAY echo
   `updatedProperties: seq[string]` to short-circuit the client's
   property re-fetch. The library models this as
   `MailboxChangesResponse` (`src/jmap_client/mail/mailbox_changes_response.nim:25–30`)
   composing `base: ChangesResponse[Mailbox]` with
   `updatedProperties: Opt[seq[string]]`, both reachable via UFCS-
   forwarded accessors (lines 38–69). The extension parser (lines 75–113)
   has serde-test coverage but no live coverage. Stalwart's actual
   choice on `updatedProperties` (null / absent / array) is unverified.

2. **`Thread/changes`.** Thread (RFC 8621 §3) lacks `/query` and
   therefore lacks `/queryChanges`; only `/changes` is in scope. The
   library uses the generic `addChanges[Thread]` (no entity-specific
   overload). Stalwart's threading pipeline is asynchronous — the
   Phase B Step 8 catalogue documents the re-fetch pattern; Phase H
   Step 45 must apply it to BOTH baseline capture and post-mutation
   observation.

3. **`Identity/changes`.** Identity (RFC 8621 §6) similarly lacks
   `/query` / `/queryChanges`. The library exposes `addIdentityChanges`
   as a thin alias over the generic. Phase F Step 31 wired full
   Identity CRUD (create + update + destroy across four sequential
   sends) but never exercised the changes-delta side.

The complementary `*/queryChanges` methods for Thread and Identity do
**not exist** — neither the library nor RFC 8621 defines them. Phase H
correctly covers exactly four new methods: `Mailbox/changes`,
`Mailbox/queryChanges`, `Thread/changes`, `Identity/changes`.

Phase H closes this gap in one phase. **Library is wire-ready — ZERO
pre-flight fixes needed.** The Phase C16 / D0.5 / F0.5 typedesc-`fromJson`
wrapper-gap pattern does NOT recur; verified:

- `ChangesResponse[T].fromJson` typedesc overload at
  `src/jmap_client/methods.nim:674–702`
- `QueryChangesResponse[T].fromJson` typedesc overload at
  `src/jmap_client/methods.nim:796–831`
- `MailboxChangesResponse.fromJson` typedesc overload at
  `src/jmap_client/mail/mailbox_changes_response.nim:75–113`
- Entity-specific aliases `addMailboxChanges`, `addMailboxQueryChanges`
  exist in `src/jmap_client/mail/mail_builders.nim`
- `addIdentityChanges` exists in
  `src/jmap_client/mail/identity_builders.nim`
- Thread routes through generic `addChanges[Thread]` exclusively

No devcontainer changes, no library modifications, no new Nimble
dependencies — Phase H is purely additive at the test layer.

## Strategy

Continue Phase A–G's bottom-up discipline. Each step adds **exactly one
new dimension** the prior steps have not touched. When Step N fails,
Steps 1..N-1 have been proven, so the bug is isolated.

Phase H's dimensions, in build order:

1. **Step 43** — `Mailbox/changes` happy + sad. The simplest of the
   three new entities to wire-test, AND the only one whose response is
   *extended* per RFC 8621 §2.2. The test must assert on
   `MailboxChangesResponse.updatedProperties` (presence / absence both
   RFC-permitted, but capture Stalwart's choice) — otherwise the
   extension parser is silently untested while the standard composition
   does the work.
2. **Step 44** — `Mailbox/queryChanges` with `calculateTotal=true` then
   without. Mirrors Phase B Step 12's two-fixture pattern. First wire
   test of `addMailboxQueryChanges` and the `MailboxFilterCondition`
   filter type via `Filter[C]`.
3. **Step 45** — `Thread/changes`. The threading-asynchrony re-fetch
   loop (Phase B Step 8 / Phase C Step 18 precedent) must be applied
   to both baseline capture and post-mutation observation, otherwise
   the test races with prior tests' threading residue. First wire
   exercise of generic `addChanges[Thread]`.
4. **Step 46** — `Identity/changes`. Combined create+update+destroy in
   one `Identity/set` arm-set, then `Identity/changes` from baseline
   asserts the entity id surfaces in the appropriate delta. RFC 8620
   §5.2 permits the server to collapse a same-state-window
   create+update+destroy into a single delta entry — assertion accepts
   the id appearing in `created ∪ updated ∪ destroyed`.
5. **Step 47** — first multi-method `*/changes` composition.
   `Mailbox/changes` + `Thread/changes` + `Email/changes` in ONE
   Request envelope, all from the mail accountId (avoids cross-
   accountId confound — Identity lives on the submission accountId).
   Proves response demux across heterogeneous typed handles + Stalwart's
   atomic-snapshot consistency across entity types.
6. **Step 48 — capstone**. Cascade-coherence. Seed N=3 unique threads
   each with M=2 emails (6 emails total) into a child mailbox; destroy
   the mailbox with `onDestroyRemoveEmails=true` (Phase E Step 30
   scaffold). From one logical baseline window, query
   `Mailbox/changes` + `Email/changes` + `Thread/changes` in ONE
   Request. Assert: 1 mailbox in `Mailbox/changes.destroyed`; every
   cascaded email id in `Email/changes.destroyed ∪ updated`
   (RFC-permitted disjunction); every cascaded thread id in
   `Thread/changes.destroyed` (RFC 8621 §3 invariant: last-email-
   destroyed → thread destroyed).

Step 48 is visibly harder than Step 43 by construction. The asymmetry
is intentional: the climb stays inside Phase H rather than spilling
into Phase I. Step 48 also subsumes Step 47's three-entity demux
dimension while introducing the cross-entity cascade semantic — the
new dimension at the capstone.

## Phase H0 — preparatory `mlive` helper extraction

Single commit. Mirrors B/C0/D0/E0/F0.5/G0 precedent. One helper lands
before any test consumes it; commit must pass `just test` (helper is
unused at this commit).

### `captureBaselineState`

```nim
proc captureBaselineState*[T](
    client: var JmapClient, accountId: AccountId
): Result[JmapState, string]
```

Issues `addGet[T](initRequestBuilder(), accountId, ids = directIds(@[]))`,
sends the request, extracts the response via `resp.get(getHandle)`,
returns `getResp.state`. Phase B Step 11 inlines this pattern across
~10 lines per use site (`tests/integration/live/temail_changes_live.nim:50–58`);
Phase H consumes it at four sites (Steps 43, 45, 46, 48) so extraction
is justified.

The generic `T` constraint is satisfied by entities exposing
`addGet[T]` — i.e., any entity registered via `registerJmapEntity`.
Used in Phase H for `T ∈ {Mailbox, Thread, Identity, Email}`.

### Why no `captureBaselineQueryState`

Phase H exercises queryChanges only against Mailbox (Step 44).
Following Phase B Step 12's precedent (inline `addEmailQuery` call to
capture `queryState_1`,
`tests/integration/live/temail_query_changes_live.nim:68–71`), Step 44
inlines `addMailboxQuery` directly. A second helper would create
speculative API surface for one use site — skip.

### Commit shape

One commit. SPDX header preserved. Helper added in source order
(after the existing `findEmailBySubjectInMailbox`). No existing helper
modified. Must pass `just test`.

## Phase H1 — six live tests

Each test follows the project test idiom verbatim (`block <name>:` +
`doAssert`) and is gated on `loadLiveTestConfig().isOk` so the file
joins testament's megatest cleanly under `just test-full` when env
vars are absent. All six are listed in `tests/testament_skip.txt` so
`just test` skips them; run via `just test-integration`.

### Step 43 — `tmailbox_changes_live`

Closes the campaign's most architecturally-distinct changes gap:
`Mailbox/changes` returns the *extended* `MailboxChangesResponse` with
RFC 8621 §2.2's `updatedProperties` extension, NOT the bare
`ChangesResponse[Mailbox]`. The test must exercise BOTH the standard
composition AND the extension parser.

Body — three sequential `client.send` calls in one block:

1. Resolve mail account via `session.primaryAccounts.withValue(...)`.
2. Capture baseline state via
   `captureBaselineState[Mailbox](client, mailAccountId)`.
3. Mutate: create a child mailbox under the inbox, then destroy it.
   Two sequential `Mailbox/set` invocations producing one create then
   one destroy outcome — both operations advance the mailbox state
   between baseline and the changes call.
4. **Happy path** — `addMailboxChanges(initRequestBuilder(),
   mailAccountId, sinceState = baselineState)`. Send. Assert:
   - `cr.oldState == baselineState`
   - `cr.created.len + cr.destroyed.len >= 2` (at minimum the
     create-then-destroy seeded above; Stalwart MAY collapse the
     create+destroy of the same id into a single `destroyed` entry per
     RFC 8620 §5.2 — assertion is `created ∪ destroyed` cardinality)
   - `cr.hasMoreChanges == false` at this cardinality
   - **`cr.updatedProperties` field accessed** — assertion accepts both
     `Opt.none` (Stalwart says "any property may have changed") and
     `Opt.some(@[...])` (Stalwart says "only these specific properties
     changed"). Capture which arm Stalwart chooses for the catalogue.
5. **Sad path** — `addMailboxChanges(initRequestBuilder(),
   mailAccountId, sinceState = JmapState("phase-h-bogus-state"))`. Send.
   Assert via `resp.get(handle).isErr` and
   `methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments}`
   (RFC 8620 §5.5 set membership, identical to Phase B Step 11
   precedent).

Capture: `mailbox-changes-bogus-state-stalwart` after the sad-path send.

What this proves:

- `addMailboxChanges` builder emits the wire shape Stalwart accepts
- `MailboxChangesResponse.fromJson` round-trips Stalwart's actual
  payload, both the standard envelope (via the composed
  `ChangesResponse[Mailbox]`) and the §2.2 `updatedProperties` extension
- UFCS-forwarded accessors (`cr.oldState`, `cr.created`, etc.) resolve
  correctly through the `forwardChangesFields(MailboxChangesResponse)`
  template
- Sad-path projection lands on `MethodError` with one of the two RFC-
  compliant `errorType` variants and a non-empty `rawType`

### Step 44 — `tmailbox_query_changes_live`

First wire test of `addMailboxQueryChanges` and the `Filter[C]` /
`Comparator` combination at the Mailbox surface. Mirrors Phase B Step
12's two-fixture pattern verbatim (one happy with `calculateTotal=true`,
one separate send without).

Body — four sequential `client.send` calls in one block:

1. Resolve mail account.
2. **Baseline `Mailbox/query`** — inline `addMailboxQuery(b,
   mailAccountId)` (no helper, mirrors Phase B Step 12's precedent at
   `temail_query_changes_live.nim:68–75`). Capture `baselineQueryState`
   and `baselineCount = queryResp.ids.len`.
3. **Mutate** — `resolveOrCreateMailbox(client, mailAccountId,
   "phase-h step-44 added")`. The helper either creates or returns an
   existing id; on first run it creates, advancing the mailbox query
   state.
4. **Happy with calculateTotal=true** —
   `addMailboxQueryChanges(b, mailAccountId, sinceQueryState =
   baselineQueryState, calculateTotal = true)`. Send. Capture
   `mailbox-query-changes-with-total-stalwart`. Assert:
   - `qcr.oldQueryState == baselineQueryState`
   - `qcr.newQueryState != baselineQueryState` (state advanced after
     the `resolveOrCreateMailbox` mutation, OR — if the mailbox already
     existed — equals baseline; assertion accepts either case but logs
     the observation)
   - `qcr.total.isSome and qcr.total.get() >= UnsignedInt(baselineCount)`
   - `qcr.removed.len == 0`
   - For each `item in qcr.added`: `string(item.id).len > 0`
     and `item.index < UnsignedInt(baselineCount + qcr.added.len)`
     (membership-only on `index` — server-determined per RFC 8620 §5.5).
5. **No-calculateTotal** — same call without `calculateTotal`. Send.
   Capture `mailbox-query-changes-no-total-stalwart`. Assert
   `qcrNoTotal.total.isNone`.

What this proves:

- `addMailboxQueryChanges` wire shape Stalwart accepts
- `QueryChangesResponse[Mailbox]` deserialises via the generic
  typedesc overload at `methods.nim:796`
- `AddedItem` (`{id, index}` per `framework.nim:81–94`) deserialises
- `total` field is gated on `calculateTotal=true` per RFC 8620 §5.6 ¶2
- Mailbox query-state bookkeeping advances on hierarchy mutation

### Step 45 — `tthread_changes_live`

First wire test of generic `addChanges[Thread]`. Closes the
threading-pipeline asynchrony loop that Phase B Step 8 first
catalogued: Stalwart's threading is asynchronous, so both baseline
capture AND post-mutation observation may race the pipeline. The
re-fetch pattern lives at the test layer per the established
discipline.

Body — three sequential `client.send` calls plus a re-fetch loop:

1. Resolve mail account.
2. **Baseline state** — `captureBaselineState[Thread](client,
   mailAccountId)`. Note: `Thread/get(ids = directIds(@[]))` is
   well-defined per RFC 8621 §3 and returns the current state without
   any list entries.
3. **Mutate** — seed two threaded emails via `seedThreadedEmails(client,
   mailAccountId, inbox, @["phase-h step-45 root", "phase-h step-45
   reply"], rootMessageId = "<phase-h-step-45-root@example.com>")`.
   Capture both ids.
4. **Happy path with re-fetch loop** — up to 5 attempts, 200 ms apart:
   1. `addChanges[Thread](initRequestBuilder(), mailAccountId,
      sinceState = baselineState)`.
   2. Send.
   3. Extract `cr = resp.get(threadChangesHandle)`.
   4. If `cr.created.len + cr.updated.len >= 1` (at least one Thread
      surfaces in the delta): exit loop.
   5. Otherwise sleep 200 ms.
   6. After 5 attempts without success: `doAssert false, "Stalwart
      threading did not converge within 1 s — extend re-fetch budget
      or investigate Stalwart 0.15.5 threading pipeline"`.
5. After loop succeeds, assert:
   - `cr.oldState == baselineState`
   - `cr.created.len + cr.updated.len >= 1` (Stalwart MAY emit a
     freshly-created Thread id in either bucket — RFC 8620 §5.2 doesn't
     pin which)
   - `cr.destroyed.len == 0`
   - `cr.hasMoreChanges == false`
6. **Sad path** — `addChanges[Thread](initRequestBuilder(),
   mailAccountId, sinceState = JmapState("phase-h-bogus-state"))`. Send.
   Capture `thread-changes-bogus-state-stalwart`. Same set-membership
   assertion as Step 43.

What this proves:

- Generic `addChanges[T]` template resolves to
  `addChanges[Thread, ChangesResponse[Thread]]` correctly via the
  `changesResponseType(Thread)` registration
- `ChangesResponse[Thread].fromJson` round-trips Stalwart's wire
- Threading-asynchrony pattern transfers cleanly from `Thread/get` (B
  Step 8) to `Thread/changes` (H Step 45)

### Step 46 — `tidentity_changes_live`

First wire test of `addIdentityChanges`. Combines create + update +
destroy in ONE `Identity/set` invocation (single combined arm-set),
then issues `Identity/changes` to assert the entity id surfaces in
the appropriate delta bucket per Stalwart's collapse semantics.

Body — three sequential `client.send` calls in one block:

1. Resolve submission account via `resolveSubmissionAccountId(session)`.
2. **Baseline state** — `captureBaselineState[Identity](client,
   submissionAccountId)`.
3. **Mutate (combined CRUD)** — single `addIdentitySet(create =
   Opt.some({createCid: parseIdentityCreate("alice@example.com",
   Opt.some("phase-h step-46")).expect(...)}.toTable))`. Send. Capture
   the assigned `identityId` from `setResp.createResults[createCid]`.
4. **Happy path** — `addIdentityChanges(initRequestBuilder(),
   submissionAccountId, sinceState = baselineState)`. Send. Assert:
   - `cr.oldState == baselineState`
   - `identityId in cr.created or identityId in cr.updated or
     identityId in cr.destroyed`. RFC 8620 §5.2 permits the server to
     collapse same-state-window mutations into the most-final delta
     arm; assertion accepts any of the three buckets and logs which
     arm Stalwart chose for the catalogue.
   - `cr.hasMoreChanges == false`
5. **Sad path** — `addIdentityChanges(initRequestBuilder(),
   submissionAccountId, sinceState = JmapState("phase-h-bogus-state"))`.
   Send. Capture `identity-changes-bogus-state-stalwart`. Same
   set-membership assertion.
6. **Cleanup** — destroy `identityId` via
   `addIdentitySet(destroy = directIds(@[identityId]))`. No assertion;
   best-effort idempotency hygiene so re-runs see a clean baseline.

Note: Phase H Step 46 deliberately DOES NOT exercise update arms in
the create+update+destroy combined invocation. Per RFC 8621 §6.5, an
Identity referenced by an existing `EmailSubmission` MUST NOT be
destroyable; combining create+update+destroy in one arm-set across an
unsubmitted Identity stays clean, but adding update arms expands the
test's surface beyond `Identity/changes` proper. Phase J's "Identity
update beyond name" expansion picks this up.

What this proves:

- `addIdentityChanges` builder routes to `Identity/changes` correctly
- `ChangesResponse[Identity].fromJson` round-trips Stalwart's wire
- Stalwart's same-state-window collapse semantics are catalogued
  (which delta arm receives the combined CRUD's id)

### Step 47 — `tcombined_changes_live`

First test composing three heterogeneous `*/changes` invocations in
ONE Request envelope. Proves response-demux across heterogeneous typed
handles + Stalwart's atomic-snapshot consistency across entity types.

All three entities are on the **mail accountId** (avoids cross-
accountId confound — Identity lives on submission). Combination chosen:
`Mailbox/changes` + `Thread/changes` + `Email/changes`. The Email
arm is well-tested by Phase B Step 11; its presence here is a
"known-good reference" alongside the two new methods, demonstrating
that the combined envelope routes each invocation to the correct
typed handle.

Body — five sequential `client.send` calls in one block:

1. Resolve mail account.
2. Capture three baselines via `captureBaselineState[Mailbox]`,
   `captureBaselineState[Thread]`, `captureBaselineState[Email]`.
3. Mutate across all three entity types in distinct sends:
   1. Create-then-destroy a child mailbox (advances Mailbox state).
   2. Seed a single email via `seedSimpleEmail` (advances Email and
      Thread state).
4. **Combined Request** — single `RequestBuilder` carrying three
   invocations in order:
   1. `addMailboxChanges(b, mailAccountId, sinceState =
      baselineMailboxState)`.
   2. `addChanges[Thread](b, mailAccountId, sinceState =
      baselineThreadState)`.
   3. `addChanges[Email](b, mailAccountId, sinceState =
      baselineEmailState)`.
   Send. Capture
   `combined-changes-mailbox-thread-email-stalwart`.
5. Extract via three independent `resp.get(handle)` calls — RFC 8620
   §3.6 guarantees `methodResponses` order mirrors `methodCalls`
   order. Assert each:
   - Mailbox response: `cr.oldState == baselineMailboxState`,
     `cr.hasMoreChanges == false`
   - Thread response: `cr.oldState == baselineThreadState`,
     `cr.hasMoreChanges == false`
   - Email response: `cr.oldState == baselineEmailState`, seeded id in
     `cr.created`
6. Re-fetch loop guard if Step 45's threading-asynchrony pattern is
   needed for the Thread arm at this combined-call cardinality
   (precedent: same pattern as Step 45).

What this proves:

- Three different `*/changes` invocations coexist in one HTTP request
- Stalwart's response envelope correctly demuxes three different
  response shapes (`MailboxChangesResponse`, `ChangesResponse[Thread]`,
  `ChangesResponse[Email]`) keyed by `methodCallId`
- Each typed handle resolves the correct `fromJson` overload via Nim's
  `mixin` discovery at the dispatch site
- Stalwart's per-(account, type) state bookkeeping is internally
  consistent: three independent baselines all return their expected
  oldState echo

### Step 48 — `tcascade_changes_coherence_live` (capstone)

Visibly-harder cascade capstone. Mirrors the visibly-harder discipline
of A Step 7 / B Step 12 / C Step 18 / D Step 24 / E Step 30 / F Step 36
/ G Step 42. Stitches Phase E Step 30's cascade scaffold
(`onDestroyRemoveEmails=true`) with Phase B Step 11's delta protocol,
extended to three entity types from one logical baseline window.

Body — six sequential `client.send` calls in one block (plus the
internal sends of `seedThreadedEmails`):

1. Resolve mail account.
2. Capture three baselines via `captureBaselineState[Mailbox]`,
   `captureBaselineState[Email]`, `captureBaselineState[Thread]`.
3. **Set up cascade scenario** — `resolveOrCreateMailbox(client,
   mailAccountId, "phase-h step-48 cascade")`. Capture `cascadeId`.
4. Seed N=3 unique threads × M=2 emails per thread via three calls
   to `seedThreadedEmails` (each with a distinct `rootMessageId` like
   `"<phase-h-step-48-tN-root@example.com>"`), targeted at the
   `cascadeId` mailbox. Capture all 6 email ids and (after a
   threading-asynchrony re-fetch loop) the 3 thread ids by reading
   `Email/get properties = ["threadId"]` for one email per thread.
5. **Destroy with cascade** — `addMailboxSet(initRequestBuilder(),
   mailAccountId, destroy = directIds(@[cascadeId]),
   onDestroyRemoveEmails = true)`. Send. Assert
   `setResp.destroyResults[cascadeId].isOk`.
6. **Combined three-changes Request** — single `RequestBuilder`:
   1. `addMailboxChanges(b, mailAccountId, sinceState =
      baselineMailboxState)`.
   2. `addChanges[Email](b, mailAccountId, sinceState =
      baselineEmailState)`.
   3. `addChanges[Thread](b, mailAccountId, sinceState =
      baselineThreadState)`.
   Send. Capture
   `cascade-changes-mailbox-email-thread-coherence-stalwart`.
7. Extract three deltas. Assert:
   - **Mailbox**: `cascadeId in mailboxCr.destroyed`;
     `mailboxCr.hasMoreChanges == false`
   - **Email**: every cascaded email id appears in
     `emailCr.destroyed ∪ emailCr.updated` (RFC-permitted disjunction
     — destroyed if Stalwart emits cascade-destroys directly, updated
     if Stalwart first emits the mailbox-set-empty update before the
     destroy); `emailCr.hasMoreChanges == false`
   - **Thread**: every cascaded thread id appears in
     `threadCr.destroyed` (RFC 8621 §3 invariant: every Thread MUST
     have ≥1 Email; when the last email is destroyed, the Thread
     record itself is destroyed, not emptied); `threadCr.hasMoreChanges
     == false`

What this proves:

- The campaign's most complex cross-entity semantic (cascade) projects
  coherently across three independent state-delta queries from one
  logical baseline window
- Stalwart's per-(account, type) state bookkeeping respects the
  cascade as a single atomic event visible across all three entity
  types
- The RFC 8621 §3 thread-empty invariant is wire-enforced by Stalwart
- The combined Request envelope carries N entities × delta cardinalities
  (1 + 6 + 3 = 10 ids) without exceeding any sane Stalwart limit
- `hasMoreChanges == false` at this cardinality validates the
  per-entity `MaxChanges` default

## Captured-fixture additions

Seven new fixtures committed under `tests/testdata/captured/`,
captured against a freshly reset Stalwart 0.15.5 with
`JMAP_TEST_CAPTURE=1 just test-integration`:

- `mailbox-changes-bogus-state-stalwart` (Step 43 sad)
- `mailbox-query-changes-with-total-stalwart` (Step 44 with-total)
- `mailbox-query-changes-no-total-stalwart` (Step 44 no-total)
- `thread-changes-bogus-state-stalwart` (Step 45 sad)
- `identity-changes-bogus-state-stalwart` (Step 46 sad)
- `combined-changes-mailbox-thread-email-stalwart` (Step 47 happy)
- `cascade-changes-mailbox-email-thread-coherence-stalwart` (Step 48
  capstone)

Seven always-on parser-only replay tests under `tests/serde/captured/`,
one per fixture:

- `tcaptured_mailbox_changes_bogus.nim` — set-membership assertion on
  `errorType in {metCannotCalculateChanges, metInvalidArguments}`
  (mirrors `tcaptured_email_changes_bogus.nim`)
- `tcaptured_mailbox_query_changes_with_total.nim` —
  `qcr.total.isSome`, `qcr.added.len >= 0`, non-empty `oldQueryState`
  / `newQueryState` (mirrors
  `tcaptured_email_query_changes_with_total.nim`)
- `tcaptured_mailbox_query_changes_no_total.nim` —
  `qcr.total.isNone`, structural otherwise (mirrors
  `tcaptured_email_query_changes_no_total.nim`)
- `tcaptured_thread_changes_bogus.nim` — same shape as mailbox-bogus
- `tcaptured_identity_changes_bogus.nim` — same shape
- `tcaptured_combined_changes_mailbox_thread_email.nim` — structural:
  `methodResponses.len == 3`; pattern-match each `inv.rawName ∈
  {"Mailbox/changes", "Thread/changes", "Email/changes"}`; each typed
  parse via the corresponding `*.fromJson` succeeds. No run-dependent
  cardinality assertions.
- `tcaptured_cascade_changes_mailbox_email_thread_coherence.nim` —
  precise structural: Mailbox response `destroyed` carries the
  cascaded mailbox id; Email response's `destroyed ∪ updated`
  cardinality equals the seeded email count (6); Thread response's
  `destroyed` cardinality equals the seeded thread count (3)

NOT listed in `testament_skip.txt` — these are always-on parser
regressions that run under `just test` and `just ci`. Cumulative
captured-replay total rises from **36 to 43**.

## Predictable wire-format divergences (Phase H catalogue)

Forward-looking — to be confirmed during H1 execution and amended
in-flight per Phase E precedent.

1. **`MailboxChangesResponse.updatedProperties` shape** (Step 43).
   RFC 8621 §2.2 permits null/absent (server says "any property may
   have changed, full re-fetch needed") OR a non-empty array (server
   short-circuits the re-fetch by listing exactly which properties
   changed). Stalwart's choice unverified; the Step 43 assertion
   accepts both arms. Whichever Stalwart emits, the captured fixture
   pins it for the replay test.

2. **`cannotCalculateChanges` vs `invalidArguments`** (Steps 43, 45,
   46). Identical to Phase B Step 11 catalogue: RFC 8620 §5.2 permits
   either method-error variant for an unknown `sinceState`. Set-
   membership assertion accepts both. The captured fixtures pin
   Stalwart 0.15.5's actual choice for each entity (may differ across
   entities — server's choice is per-call, not per-entity).

3. **Thread state derivation timing** (Step 45). Stalwart's
   `Thread/changes.{oldState, newState}` is derived from email events
   propagating through the threading pipeline. The baseline capture
   must wait for the pipeline to settle, otherwise the captured state
   may not match the eventual `oldState` echo. The re-fetch loop in
   Step 45 absorbs this; if 5 × 200 ms is insufficient, extend the
   budget at the test layer per the established
   "asynchrony-belongs-in-the-test" discipline (Phase C Step 18
   catalogue).

4. **Identity update collapse** (Step 46). RFC 8620 §5.2 permits a
   server to collapse a same-state-window create+(update+)destroy of
   one entity into a single delta entry (e.g., just `destroyed` on
   the merged outcome). The Step 46 assertion uses set union
   `created ∪ updated ∪ destroyed` for the entity id; the captured
   fixture pins which arm Stalwart chooses.

5. **Cascade delta as `destroyed` vs `updated`** (Step 48). RFC 8620
   §5.2 + RFC 8621 §2.5 don't pin whether cascade-destroyed emails
   surface in `Email/changes.destroyed` or `updated` (mailbox-set
   went empty before destroy, then destroy itself fires). Both
   RFC-permitted; assertion uses `destroyed ∪ updated`. The captured
   fixture pins Stalwart's choice.

6. **`hasMoreChanges` at cascade cardinality** (Step 48). Cascade of
   6 emails plus 3 threads plus 1 mailbox is well within any sane
   Stalwart `maxChanges` default (commonly 200+). The Step 48
   assertion is `hasMoreChanges == false` for all three deltas; if
   Stalwart trips `true` at this cardinality, lower N×M and document
   in the catalogue.

7. **`calculateTotal` echo asymmetry** (Step 44). Identical to Phase
   B Step 12 catalogue — server may emit `total` even when
   `calculateTotal=false`; the test asserts `isSome` only on the
   `true`-requested side, never absence on the false-requested side.

8. **`addMailboxQuery` filter / sort defaults** (Step 44). The Step
   44 baseline uses `addMailboxQuery(b, mailAccountId)` with no
   filter / sort. Stalwart's default ordering for unsorted Mailbox
   query results is implementation-defined per RFC 8620 §5.5; Step 44
   does not assert on `AddedItem.index` value, only on the bound
   `index < UnsignedInt(baselineCount + qcr.added.len)`.

## Success criteria

Phase H is complete when:

- [ ] Phase H0's `mlive.nim` helper-extraction commit lands with the
  one helper (`captureBaselineState[T]`); consumed by Phase H tests
- [ ] All six new live test files exist under
  `tests/integration/live/` with the established idiom (license,
  docstring, single `block`, `loadLiveTestConfig().isOk` guard,
  explicit `client.close()` before block exit, `doAssert` with
  narrative messages)
- [ ] All six new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six, B five, C six, D six, E six, F six,
  G six
- [ ] `just test-integration` exits 0 with **forty-six** live tests
  passing (40 from A–G + 6 from H — `tsession_discovery` does not
  match `*_live.nim` and is not run by the integration runner)
- [ ] Seven new captured fixtures exist under
  `tests/testdata/captured/`
- [ ] Seven new always-on parser-only replay tests exist under
  `tests/serde/captured/` and pass under `just test` (cumulative
  count: **43**)
- [ ] `just ci` is green (reuse + fmt-check + lint + analyse + test)
- [ ] No new Nimble dependencies, no new devcontainer packages — the
  2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro at
  `01-integration-testing-A.md:249-255`) holds throughout
- [ ] No library source modifications (`git diff src/` is empty after
  H0's helper-only commit) — the wire-readiness audit confirmed
  ZERO pre-flight typedesc-`fromJson` wrapper gaps
- [ ] Every divergence between Stalwart's wire shape and the test's
  expected behaviour has been classified (test premise / server
  quirk / client bug) and resolved at the right layer; no test
  papers over a real client bug
- [ ] Total wall-clock for the new tests under ~15 s on the
  devcontainer (Phase H is JMAP-only, no SMTP polling; the
  threading re-fetch loops in Steps 45 / 47 / 48 contribute the
  only meaningful delay — at most ~1 s per test if Stalwart
  converges on first attempt)

## Out of scope for Phase H

Explicitly deferred to later phases:

- **Adversarial wire-format edge cases** — RFC 2047 encoded-word
  names in `EmailAddress.name`, fractional-second dates,
  empty-vs-null table entries, oversize at `maxSizeRequest`,
  control-character handling at byte boundaries,
  `maxBodyValueBytes` truncation marker, `metUnsupportedFilter` /
  `metUnsupportedSort` via raw-JSON injection bypassing the sealed
  builders — **Phase I**
- **`Email/queryChanges` filter mismatch** — RFC 8620 §5.6 deferral
  from Phase C Step 12 ("server MAY return `cannotCalculateChanges`
  if filter/sort changes between calls"; Stalwart's behaviour
  unverified) — **Phase I** (adversarial-themed)
- **`MaxChanges` parameter exercise** — Phase B Step 11's catalogue
  noted "promote to a future regression if Stalwart ever changes
  its default"; Phase H Step 48 asserts `hasMoreChanges == false`
  but does not pass an explicit `maxChanges` cap to force pagination —
  **Phase I**
- **Header-form completeness** — `header:Foo:asMessageIds`,
  `asText`, `:all` ordering semantics (Phase D Step 22 covered only
  `urls`/`date`/`addresses`) — **Phase J**
- **`Email/set update` beyond keyword + mailbox flips** — header
  replacement via patches, body content updates — **Phase J**
- **EmailSubmission filter + sort against a real corpus** —
  `EmailSubmissionFilterCondition` (`identityIds`, `emailIds`,
  `threadIds`, `undoStatus`, `before`, `after`) and
  `EmailSubmissionComparator` (`emailId` / `threadId` / `sentAt` /
  `identityId`) — **Phase J**
- **Identity update arms** beyond the create-then-destroy combined
  pattern of Step 46 — `IdentityUpdate` arm coverage
  (`setName`, `setReplyTo`, `setBcc`, `setTextSignature`,
  `setHtmlSignature`) is wire-tested in Phase F Step 31 already;
  combining update arms inside a single `Identity/changes` window
  is the natural Phase J extension
- **JMAP-Sharing draft / `urn:ietf:params:jmap:principals`** —
  permanent out-of-scope per Phase G's "Out of scope" justification:
  neither RFC 8620 nor RFC 8621 defines these surfaces; library has
  zero principal/sharing surface; campaign discipline is to
  validate **existing** RFC-aligned surface
- **Cross-account `Email/copy` happy path** — requires sharing/ACL,
  permanent out-of-scope per same reasoning
- **Push notifications, blob upload/download, Layer 5 C ABI** — not
  yet implemented in the library; not part of the integration-
  testing campaign at all until they exist
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in `tests/stress/`
  if/when it becomes a goal

## Forward arc (informational)

Following this campaign through the user's 8–10 phase budget:

- **Phase I** — adversarial wire formats: RFC 2047 encoded-words,
  fractional-second dates, empty-vs-null table entries, oversize at
  `maxSizeRequest`, `maxBodyValueBytes` truncation marker,
  control-character handling at byte boundaries, raw-JSON injection
  for `metUnsupportedFilter` / `metUnsupportedSort`, plus the
  `Email/queryChanges` filter-mismatch deferred from Phase C and the
  `MaxChanges` pagination deferred from Phases B / H.
- **Phase J** — header-form completeness (`asMessageIds` / `asText`
  / `:all` ordering) + `Email/set update` beyond keyword/mailbox
  flips + EmailSubmission filter+sort against a real corpus +
  Identity update-arm coverage inside one changes window + final
  regression hardening (captures any straggler wire divergences).

That totals ten phases (A through J), comfortably inside the 8–10
budget. Each remaining phase is themed coherently and follows the
established 5–6-tests-per-phase cadence with a visibly-harder
capstone.
