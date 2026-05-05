# Integration Testing Plan — Phase B

## Status (living)

Phase B introduces five live tests that round out the standard RFC 8621
entity surfaces (`Thread`, `VacationResponse`, full `Mailbox/set` CRUD)
and the state-delta protocol (`Email/changes`, `Email/queryChanges`).
All five run unchanged today against every configured JMAP target —
Stalwart, James, Cyrus — under `forEachLiveTarget`, with
`assertSuccessOrTypedError` covering surfaces a target may not
implement.

| Test | File | Status |
|---|---|---|
| Step 8 — Thread/get | `tthread_get_live.nim` | passes against all three targets |
| Step 9 — VacationResponse/get + set | `tvacation_get_set_live.nim` | passes; Cyrus path verifies typed `unknownCapability` request-level error |
| Step 10 — Mailbox/set CRUD + `mailboxHasChild` | `tmailbox_set_crud_live.nim` | passes; cleanup split into two `Mailbox/set` calls (see Step 10) |
| Step 11 — Email/changes happy + bogus state | `temail_changes_live.nim` | passes; sad path accepts `metCannotCalculateChanges` ∪ `metInvalidArguments` |
| Step 12 — Email/queryChanges with `calculateTotal` | `temail_query_changes_live.nim` | passes; James returns typed `metUnknownMethod` via `assertSuccessOrTypedError` |

All five files are listed in `tests/testament_skip.txt` so `just test`
stays deterministic; run via `just test-integration` (or
`just capture-fixtures` to refresh wire fixtures under
`tests/testdata/captured/`).

Wire-format divergences root-caused at the `fromJson` layer:

- `MailboxCreatedItem` (`src/jmap_client/mail/mailbox.nim:249-268`)
  carries the five RFC 8621 §2.1 server-set fields all `Opt[T]`. The
  identity precedent (`IdentityCreatedItem`) and Stalwart's
  trim-to-`{"id":"…"}` shape converge on the same Postel-tolerant
  partial type.

Server-asynchrony / capability divergences accommodated **at the test
layer** (parser invariants preserved):

- `Thread/get` — Stalwart's threading pipeline is asynchronous. Step 8
  retries up to five attempts at 100 ms backoff before asserting; the
  `parseThread` non-empty `emailIds` invariant
  (`src/jmap_client/mail/thread.nim:32-36`) holds per RFC 8621 §3.
- `VacationResponse` — Stalwart returns the singleton in `notFound`
  (not `list`) until first `Set`; the test tolerates both shapes by
  asserting only post-`Set`. Cyrus 3.12.2 ships VacationResponse but
  the test image disables it via `imapd.conf: jmap_vacation: no`, so
  the URN is absent from `session.capabilities` and the request fails
  at the **request level** with `urn:ietf:params:jmap:error:unknownCapability`
  (the library projects this as `cekRequest`). The Cyrus arm asserts
  on this projection, captures the wire shape, and skips the
  dependent round-trip.
- `Email/changes` bogus state — both `metCannotCalculateChanges` and
  `metInvalidArguments` are RFC-compliant for an unknown state string;
  the assertion accepts either via `methodErr.errorType in
  {metCannotCalculateChanges, metInvalidArguments}`.
- `Email/queryChanges` — James 3.9 does not implement queryChanges
  (`EmailQueryMethod.scala` returns `canCalculateChanges = CANNOT`
  unconditionally and registers no `EmailQueryChangesMethod`). Step 12
  uses `assertSuccessOrTypedError` with allowed errors
  `{metCannotCalculateChanges, metUnknownMethod}` so the success arm
  exercises the round-trip semantic on Stalwart/Cyrus while the error
  arm exercises the typed-error projection on James.

## Context

Phase A established six foundational live tests against Stalwart 0.15.5:
`tsession_discovery`, `tcore_echo_live`, `tmailbox_get_all_live`,
`tidentity_get_live`, `temail_query_get_chain_live`, and
`temail_set_keywords_live`. Foundational JMAP request shapes (echo,
single-method get, set with `ifInState` state guards, two-method
back-reference chains) and both error rails (transport, method-level)
were exercised end-to-end.

The library implements considerably more than Phase A touched. Three
RFC 8621 entity surfaces (`Thread`, `VacationResponse`, full
`Mailbox/set` CRUD) had unit and serde coverage but no wire validation.
The state-delta protocol (`Foo/changes`, `Foo/queryChanges`) — the
operational counterpart of Phase A's state-guard machinery — was
unexercised against a real server.

Phase B closes that gap before any work begins on the harder surfaces:
chained query workflows (Phase C), EmailSubmission with implicit
chaining and `ParsedSmtpReply` round-trips (Phase D), and multi-account
shared access (Phase E). Push, Blob, and Layer 5 C ABI are out of
scope for the entire integration-testing campaign — they are not yet
implemented in the library, and the campaign exists to prove the
existing surface before more is built.

## Strategy

Continue Phase A's bottom-up discipline. Each step adds **exactly one
new dimension** the prior steps have not touched. When Step N fails,
Steps 1..N-1 have been proven, so the bug is isolated.

Phase B's dimensions, in build order:

1. The simplest unread entity in RFC 8621 (`Thread` — two properties).
2. The singleton entity shape (`VacationResponse`, no variable id).
3. The first CRUD round-trip (`Mailbox/set` create + update + destroy)
   plus the entity-specific `onDestroyRemoveEmails` extension and the
   first server-projected SetError variants (`setMailboxHasChild`).
4. The state-delta protocol (`Email/changes`) — the next vertical
   above Phase A's state guards.
5. The composed change-over-query protocol (`Email/queryChanges`) —
   stitches `Email/query` (Phase A) and `/changes` (Step 11) into one
   surface.

Step 12 is visibly harder than Step 8, mirroring the Phase A curve
where Step 7 was visibly harder than Step 3. That asymmetry is
intentional: the climb stays inside the phase rather than spilling
into Phase C.

## Test idiom

All Phase B tests live under `tests/integration/live/` and follow the
established multi-target idiom:

- SPDX header + copyright block on lines 1–2.
- `##` docstring explaining purpose, `testament_skip.txt` listing, the
  multi-target categorisation (Cat-A vs Cat-B per
  `docs/plan/12-integration-testing-L-cyrus.md` §0), and any server-
  specific divergences accommodated.
- Imports in fixed order: `std/...` first, then `results`, then
  `jmap_client`, `jmap_client/client`, then `./mcapture`, `./mconfig`,
  `./mlive`.
- Single top-level `block <camelCaseName>:` wrapping the test body.
- `forEachLiveTarget(target):` (`mconfig.nim:80-87`) iterates every
  configured target in enum order. The template guards on
  `loadLiveTestTargets().isOk` so the file joins testament's megatest
  cleanly under `just test-full` when env vars are absent.
- `var client = initJmapClient(sessionUrl = target.sessionUrl,
  bearerToken = target.aliceToken, authScheme = target.authScheme)
  .expect("initJmapClient[" & $target.kind & "]")`.
- `client.close()` immediately before the iteration's exit — explicit,
  no `defer`.
- `assertOn target, <invariant>, "<narrative>"` (`mlive.nim:1184-1194`)
  prefixes every failure with `[<server>]` so failures attribute to a
  specific target.
- `captureIfRequested(client, "<name>-" & $target.kind)` after the
  payload of interest writes
  `tests/testdata/captured/<name>-<kind>.json` when
  `JMAP_TEST_CAPTURE=1` and the destination does not yet exist
  (`mcapture.nim:44-61`).
- For surfaces that may legitimately not be implemented on a given
  target, `assertSuccessOrTypedError(target, extract, allowedErrors)`
  (`mlive.nim:1196-1228`) asserts on the success path **and** the
  typed-error projection — one positive client-library contract per
  arm. The test never branches its assertion on which server replied.

Shared seeding scaffolds live in `mlive.nim`:

- `resolveMailAccountId(session)` (`mlive.nim:563`) — read the
  `urn:ietf:params:jmap:mail` primary account id off the session.
- `resolveInboxId(client, mailAccountId)` (`mlive.nim:86-104`) —
  `Mailbox/get` → first mailbox with `role == roleInbox`.
- `seedSimpleEmail(client, mailAccountId, inbox, subject,
  creationLabel)` (`mlive.nim:138-173`) — single-blueprint
  `Email/set create` for a minimal text/plain alice → alice message;
  returns the assigned `EmailId`.

Step 8, 11, and 12 funnel through these helpers. Step 9 has no
seed scaffolding (singleton-only). Step 10 inlines `Mailbox/set` plumbing
because it is the first test exercising that surface.

## Phase B1 — Five live tests

### Step 8: `tthread_get_live.nim` — Thread/get against the seeded email's threadId

Scope: simplest unread entity in RFC 8621. Validates `Thread.fromJson`,
the generic `addGet[Thread]` overload via `registerJmapEntity(Thread)`,
and Stalwart's threading actually emits a Thread node for a freshly
created Email.

Body — sequential `client.send` calls in one `forEachLiveTarget`
iteration:

1. `resolveInboxId(client, mailAccountId)` → resolve the Inbox id.
2. `seedSimpleEmail(client, mailAccountId, inbox, "phase-b step-8 seed",
   "seedThread")` → create a single text/plain message; capture the
   server-assigned id.
3. `addEmailGet(initRequestBuilder(), mailAccountId, ids =
   directIds(@[seededId]), properties = Opt.some(@["id", "threadId"]))`
   → fetch the Email's `threadId`. Read it via the JSON node's
   `{"threadId"}.getStr("")`, then parse via `parseIdFromServer`.
4. **Bounded retry loop** — up to five attempts at 100 ms backoff:
   `addGet[Thread](initRequestBuilder(), mailAccountId, ids =
   directIds(@[threadId]))`, parse `Thread.fromJson(threadResp.list[0])`.
   First Ok wins; loop exits via `break`. After the loop:
   - `thread.isSome` (the `assertOn` failure message: "Thread/get must
     return the seeded thread within 500 ms").
   - `string(t.id) == string(threadId)`.
   - `seededId in t.emailIds`.

Capture: `thread-get-<kind>.json` written after the first successful
extract (so the captured fixture always shows the populated Thread
shape, never an in-flight retry).

What this proves:

- `urn:ietf:params:jmap:mail` capability URI is auto-injected for the
  generic `addGet[Thread]` (no entity-specific overload exists for
  Thread, so this is the first test exercising the
  `registerJmapEntity(Thread)` path).
- `Thread.fromJson` accepts every target's actual wire shape; `emailIds`
  is non-empty and parseable as `seq[Id]` after the asynchrony retry
  closes.
- Every target populates `Email.threadId` consistently with the
  `Thread.emailIds` membership.

`parseThread` enforces a non-empty invariant per
`src/jmap_client/mail/thread.nim:32-36`, and that invariant is correct
per RFC 8621 §3 — every Thread MUST have at least one Email. The retry
loop accommodates server asynchrony, NOT a parser limitation.

### Step 9: `tvacation_get_set_live.nim` — VacationResponse get + set against the singleton

Scope: the only RFC 8621 entity without a variable id. Validates the
`urn:ietf:params:jmap:vacationresponse` capability URI auto-injection,
the singleton-id wire encoding (`"singleton"` hardcoded by the builder
per `mail_methods.nim:78`), and the typed
`VacationResponseUpdateSet` patch encoding.

Account resolution: `session.primaryAccounts.withValue(
"urn:ietf:params:jmap:vacationresponse", v): vacAccountId = v ...`. If
the URN is absent from `primaryAccounts` (the URN is advertised but the
account is missing), the test calls `client.close()` and `continue` —
this is a **session-level capability gate**, distinct from the
**request-level** Cyrus path described below.

Body — three sequential `client.send` calls plus a cleanup leg:

1. `addVacationResponseSet(initRequestBuilder(), vacAccountId, update =
   updateSet)` where `updateSet = initVacationResponseUpdateSet(@[
   setIsEnabled(true), setSubject(Opt.some("phase-b step-9 OOO")),
   setTextBody(Opt.some("Out until next sprint.")) ]).expect(...)`.

   The pre-set `VacationResponse/get` round-trip is **deliberately
   omitted**: Stalwart returns the singleton in `notFound` (not `list`)
   until first Set, so the only universally meaningful state to assert
   is post-Set. The first request issued is the Set itself, capturing
   the typed-error projection on Cyrus before any other round-trip.

   On Cyrus, the `addVacationResponseSet` builder injects
   `urn:ietf:params:jmap:vacationresponse` into the request's `using`
   set; Cyrus rejects at the request level because the URN is absent
   from its session capabilities (Cyrus 3.12.2 ships VacationResponse
   but the test image disables it via `imapd.conf: jmap_vacation: no`).
   The library projects this as
   `Err(ClientError(kind: cekRequest, ...))`. The Cyrus arm asserts
   `err.kind == cekRequest`, captures the wire shape via
   `captureIfRequested`, calls `client.close()`, and `continue`s.
   Capture is Cyrus-only here so an unconditional capture would not
   silently change Stalwart/James fixtures from get-response to
   set-response on a re-capture.

2. **Method-level extract** — `assertSuccessOrTypedError(target,
   setExtract, {metUnknownMethod}): ...`. Inside the success arm:
   `setResp1.updateResults.withValue(singletonId, outcome): if
   outcome.isOk: updateOk = true`.

3. **Re-read** (only if `updateOk`) — `addVacationResponseGet`. Inside
   `assertSuccessOrTypedError(target, getExtract2, {metUnknownMethod})`:
   `getResp2.list.len == 1`, parse via `VacationResponse.fromJson`,
   then assert:
   - `vr.isEnabled == true`
   - `vr.subject.isSome and vr.subject.get() == "phase-b step-9 OOO"`
   - `vr.textBody.isSome and vr.textBody.get() == "Out until next
     sprint."`

4. **Cleanup leg** — `addVacationResponseSet` flipping `isEnabled` back
   to false, so re-runs against the same servers see the same
   baseline. No assertion — best-effort idempotency hygiene.

Capture: `vacation-get-singleton-<kind>.json`.

What this proves:

- `urn:ietf:params:jmap:vacationresponse` URI is in
  `session.primaryAccounts` (or the request-level error projection
  fires) and the builder auto-injects the URN into the request's
  `using` set.
- The hardcoded singleton id `"singleton"` round-trips through every
  configured target's wire layer.
- `VacationResponseUpdate` case-object → `(string, JsonNode)` patch
  pair (per `serde_vacation.nim:113`) renders as RFC 8620 §5.3
  `update[id][path]` shape that every implementing target accepts.
- `VacationResponse.fromJson` accepts every implementing target's wire
  shape including any string fields (`subject`, `textBody`, `htmlBody`)
  and any UTC date fields.

The library exposes no creation or destroy path for VacationResponse
(no `parseVacationResponseCreate`, no `setSingleton`-triggering
overload). The singleton invariant is type-enforced at the source
level. A separate adversarial test
(`tvacation_set_all_arms_live.nim`) exercises the full update-arm
matrix; Step 9's role is the singleton round-trip.

### Step 10: `tmailbox_set_crud_live.nim` — Mailbox/set create + update + destroy with onDestroyRemoveEmails + setMailboxHasChild

Scope: first full CRUD round-trip; first server-projected entity-
specific SetError variant. Validates `parseMailboxCreate`, the
`MailboxUpdateSet` typed patch path, the entity-specific `addMailboxSet`
overload (the only standard /set with a non-standard extra parameter
— `onDestroyRemoveEmails`, emitted via `extras` per
`mail_builders.nim:112-143`), and the `setMailboxHasChild` SetError.

Body — six `client.send` calls per target iteration:

1. `addGet[Mailbox]` → resolve Inbox id (parent for the hierarchy) by
   walking `mbResp.list` and matching `roleInbox`.
2. `addMailboxSet(initRequestBuilder(), mailAccountId, create =
   Opt.some(parentTbl))` with one `parseMailboxCreate(name = "phase-b
   parent", parentId = Opt.some(inbox))` entry. Capture
   `parentId = setResp1.createResults[parentCid].unsafeValue.id`
   (after asserting `outcome.isOk`).
3. `addMailboxSet(... create = Opt.some(childTbl))` with one
   `parseMailboxCreate(name = "phase-b child", parentId =
   Opt.some(parentId))`. Capture `childId` analogously.
4. **Sad path** — `addMailboxSet(... destroy = directIds(@[parentId]))`
   without `onDestroyRemoveEmails`. Every target must reject with the
   `setMailboxHasChild` SetError per RFC 8621 §2.5. Assert:
   `outcome.isErr` and `setErr.errorType == setMailboxHasChild`. Capture
   `mailbox-set-has-child-<kind>.json` after the round-trip — this is
   the canonical SetError fixture for downstream parser-only replay
   tests.
5. **Update leg** — `let renameUpdate = setName("phase-b renamed");
   let renameSet = initMailboxUpdateSet(@[renameUpdate]).get();
   let renameUpdates = parseNonEmptyMailboxUpdates(@[(childId,
   renameSet)]).get(); addMailboxSet(... update =
   Opt.some(renameUpdates))`. Assert
   `setResp4.updateResults[childId].isOk`. Validates the
   `MailboxUpdate` case-object → wire patch path
   (`mailbox.nim:283-360` plus serde).
6. **Cleanup** — **two separate `Mailbox/set` calls**, child first,
   then parent. RFC 8620 §5.3 specifies in-order processing of
   `destroy[]` within a single set, but James 3.9 batches the
   `mailboxHasChild` validation up-front and rejects the parent destroy
   regardless of whether a sibling destroy in the same call would have
   removed the child first. Two separate invocations sidestep the
   divergence and exercise the contract correctly on every target —
   the protocol contract is "child then parent", not "atomic batch".
   Both calls assert `outcome.isOk`.

What this proves:

- `parseMailboxCreate` produces wire-compatible JSON every target
  accepts.
- The `parentId` field round-trips as a JSON string id (not a
  reference).
- The entity-specific `addMailboxSet` overload
  (`mail_builders.nim:112-143`) emits its arguments in the order
  every target expects (creates, updates, destroys per RFC 8620 §5.3).
- The `setMailboxHasChild` SetError variant projects through the
  L3 error rail with `errorType == setMailboxHasChild` and its raw
  string `"mailboxHasChild"` round-trips losslessly via `rawType`.
- `MailboxUpdate.setName` (`mailbox.nim:337`) renders as the RFC §5.3
  patch shape `{"name": "..."}` every target accepts.
- `MailboxCreatedItem` (`mailbox.nim:249-268`) parses every
  target's `created[cid]` payload — Stalwart trims to `{"id": "..."}`,
  others may include the five server-set fields, all `Opt[T]`.

`onDestroyRemoveEmails` itself is exercised at the **builder** level
(the Step 4 sad path implicitly passes `false` by relying on the
default; the Step 6 cleanups also pass `false`). Validating the
**semantic effect** of `onDestroyRemoveEmails: true` (deleting emails
on parent destroy) lives in
`tmailbox_destroy_remove_emails_live.nim`, which Step 10 enables by
proving the surrounding plumbing.

### Step 11: `temail_changes_live.nim` — Email/changes happy path + cannotCalculateChanges/invalidArguments sad path

Scope: first state-delta test; introduces the `/changes` method shape.
Validates `addChanges[Email]` template resolution to
`ChangesResponse[Email]`, the delta arrays (`created`, `updated`,
`destroyed`), and the method-error projection for an unknown state.

Body — sequential `client.send` calls per target iteration:

1. `addEmailGet(initRequestBuilder(), mailAccountId, ids =
   directIds(@[]), properties = Opt.some(@["id"]))` — fetch the empty
   list to capture the *baseline* `state`. Asking `Email/get` with a
   literal empty ids array forces every target to return `list: []`
   plus the current `state` — costs one round-trip but produces a
   clean baseline that does not depend on knowing any pre-existing
   email ids. Capture `baselineState = getResp.state`.
2. `resolveInboxId` → `seedSimpleEmail` twice with subjects `"phase-b
   step-11 a"` and `"phase-b step-11 b"`; capture `idA` and `idB`.
3. **Happy path** — `addChanges[Email](initRequestBuilder(),
   mailAccountId, sinceState = baselineState)`. Assert:
   - `string(cr.oldState) == string(baselineState)`
   - `cr.created.len == 2`
   - `cr.updated.len == 0`
   - `cr.destroyed.len == 0`
   - `idA in cr.created and idB in cr.created`
4. **Sad path** — `addChanges[Email](... sinceState =
   JmapState("phase-b-bogus-state"))`. The plain `parseJmapState`
   accepts arbitrary non-empty strings, so the request is well-formed;
   every target must reject at the method level. Capture
   `email-changes-bogus-state-<kind>.json` after the round-trip.
   Assert:
   - `sadExtract.isErr`
   - `methodErr.errorType in {metCannotCalculateChanges,
     metInvalidArguments}` — both are RFC-compliant for an unknown
     state string per RFC 8620 §5.2; `rawType` carries the lossless
     wire spelling for diagnostics.

What this proves:

- The `addChanges[T]` template (`builder.nim:202-214`) expands to
  `addChanges[Email, changesResponseType(Email)]` which resolves to
  `ChangesResponse[Email]` — the registration is wired correctly for
  Email.
- `ChangesResponse[T]` deserialises with all six fields present
  (`accountId`, `oldState`, `newState`, `hasMoreChanges`, plus the
  three id arrays).
- The state strings round-trip: `baselineState` echoed as `oldState`.
- Both candidate MethodError variants project from their respective
  wire strings via `parseMethodErrorType` and `MethodError.rawType`
  (`errors.nim:225-237`).

`MaxChanges` (the optional integer cap) is NOT exercised in Step 11.
A dedicated test (`temail_changes_max_changes_live.nim`) covers the
cap behaviour separately so Step 11 stays focused on the baseline
delta protocol.

### Step 12: `temail_query_changes_live.nim` — Email/queryChanges with calculateTotal=true and =absent

Scope: composed change-over-query protocol. Validates
`addEmailQueryChanges` (`mail_builders.nim:234-256`),
`QueryChangesResponse[Email]` deserialisation, and the `AddedItem`
shape (`{id, index}` pair from `framework.nim:81-95`). Cat-B refactor:
James 3.9 returns typed `metUnknownMethod` (no
`EmailQueryChangesMethod` is registered); the test exercises both the
implementing path (Stalwart, Cyrus) and the typed-error projection
path (James) in a single uniformly-asserted body.

Body — sequential `client.send` calls per target iteration:

1. `resolveInboxId` → `seedSimpleEmail` three times with subjects
   `"phase-b step-12 a-1"`, `"phase-b step-12 a-2"`, `"phase-b step-12
   a-3"`; capture `id1`, `id2`, `id3`.
2. `addEmailQuery(initRequestBuilder(), mailAccountId)` — no filter, no
   sort. Capture `queryState1 = queryResp.queryState` and
   `baselineCount = queryResp.ids.len`. Assert each of `id1`, `id2`,
   `id3` is in `queryResp.ids`. The full live suite shares a server
   instance, so the inbox may already hold messages seeded by earlier
   tests; the test asserts on **deltas** captured against
   `baselineCount`, never on absolute counts.
3. `seedSimpleEmail` with subject `"phase-b step-12 a-4"`; capture
   `id4`.
4. `addEmailQueryChanges(initRequestBuilder(), mailAccountId,
   sinceQueryState = queryState1, calculateTotal = true)` —
   `collapseThreads` defaults to false. Capture
   `email-query-changes-with-total-<kind>.json`. Inside
   `assertSuccessOrTypedError(target, qcExtract,
   {metCannotCalculateChanges, metUnknownMethod})`:
   - `string(qcr.oldQueryState) == string(queryState1)`
   - `string(qcr.newQueryState) != string(queryState1)`
   - **Lower-bound** total: if `qcr.total.isSome`, then
     `qcr.total.get() >= UnsignedInt(baselineCount + 1)`. RFC 8620 §5.6
     permits a server to return `calculateTotal` as absent (James 3.9
     does not honour `calculateTotal` on Email/query); when present,
     it must reflect the latest count.
   - **Reposition tolerance** on `removed` ∪ `added`: RFC 8620 §5.6
     permits the same id appearing in both `removed` and `added` to
     signal a reposition under a sorted query. The client-library
     contract verifies the wire shape parses; the exact cardinality of
     each array is server-specific. The assertion is only that
     `id4` appears in `qcr.added`, with that item's
     `index < UnsignedInt(baselineCount + 1)` (positional bound on
     the new query).
5. `addEmailQueryChanges(... sinceQueryState = queryState1)` — second
   call with `calculateTotal` defaulting to false. Capture
   `email-query-changes-no-total-<kind>.json`. Inside
   `assertSuccessOrTypedError(target, qcNoTotalExtract,
   {metCannotCalculateChanges, metUnknownMethod})`: only the wire-
   shape parse is asserted (`discard success`). RFC 8620 §5.6 says
   `total` is "only present" when `calculateTotal: true` was sent;
   some servers (Cyrus 3.12.2) populate the field unconditionally. The
   client-library contract is the parse — both `Opt.none` and
   `Opt.some` are accepted; the parser-only replay tests under
   `tests/serde/captured/` exercise the captured shapes.

What this proves:

- The entity-specific `addEmailQueryChanges` overload
  (`mail_builders.nim:234-256`) emits the request shape every
  implementing target accepts (including the `collapseThreads: false`
  default).
- `QueryChangesResponse[T]` deserialises with all six standard fields
  (`accountId`, `oldQueryState`, `newQueryState`, `total`, `removed`,
  `added`).
- `AddedItem` (`framework.nim:81-95`) deserialises both the `id`
  string and the `index` UnsignedInt; construction is sealed via
  `initAddedItem` (Pattern A).
- The `calculateTotal: true` parameter actually elicits a `total`
  field in implementing servers; absence on `false` is wire-shape-
  parsed without assertion of *absence*.
- The typed-error projection for `metUnknownMethod` (James) and
  `metCannotCalculateChanges` (any server) routes through
  `assertSuccessOrTypedError` and is exercised against a real-world
  response.

A second sad-path leg (calling `addEmailQueryChanges` with a different
filter than the original query) is **deliberately omitted from
Step 12**. RFC 8620 §5.6 permits — but does not require — the server
to return `cannotCalculateChanges` if the filter or sort changes
between calls; servers vary in strictness. A dedicated test
(`temail_query_changes_filter_mismatch_live.nim`) covers that surface
separately so Step 12 stays focused on the baseline composed
delta protocol.

## Predictable wire-format divergences (Phase B catalogue)

Catalogue of what live testing typically reveals at each new surface
Phase B introduces. The Postel-tolerant boundary in the library is the
right place to absorb each one — never the test layer (with the
exception of bounded server-asynchrony retries, which model real-world
client behaviour).

1. **Thread emailIds asynchrony.** Step 8: a target's threading
   pipeline may not have populated `Thread.emailIds` by the time
   `Thread/get` is called. Bounded retry (5 attempts × 100 ms) at the
   **test** layer; the parser invariant
   (`parseThread` non-empty `emailIds`) is preserved per RFC 8621 §3.
2. **VacationResponse pre-set notFound.** Step 9: a target may return
   the singleton in `notFound` (not `list`) until the first
   `VacationResponse/set` materialises it (RFC 8621 §7 mandates a
   default; some servers depart). The test asserts only on the
   post-`Set` round-trip.
3. **VacationResponse capability gating.** Step 9: a target may ship
   the implementation but disable it via configuration, surfacing as
   the URN being absent from `session.capabilities`. The library
   projects this as a request-level `cekRequest` error
   (`urn:ietf:params:jmap:error:unknownCapability`); the test asserts
   on the projection and skips the dependent round-trip.
4. **VacationResponse optional fields.** Step 9: optional string and
   date fields (`subject`, `textBody`, `htmlBody`, `fromDate`,
   `toDate`) may be `null` vs. absent vs. empty string. `Opt[T]` plus
   the lenient `*FromServer` parsers handle all three.
5. **Mailbox/set destroy batching.** Step 10: RFC 8620 §5.3 specifies
   create-then-update-then-destroy regardless of argument order, and
   in-order processing within `destroy[]`. Some servers (James 3.9)
   batch `mailboxHasChild` validation up-front. Cleanup is split
   across two `Mailbox/set` calls so the contract is exercised
   correctly on every target.
6. **Mailbox `created[cid]` partial.** Step 10: per RFC 8620 §5.3 the
   server returns only `id` plus server-set/modified properties.
   Stalwart trims further to `{"id": "..."}`. The library type
   `MailboxCreatedItem` makes all five RFC 8621 §2.1 server-set
   fields `Opt[T]`.
7. **SetError raw type spelling.** Step 10: any divergence between a
   server's emitted `type` string and the RFC 8621 §10.6 registry
   projects as `setUnknown` with a non-empty `rawType`. The lossless
   `rawType` field carries the wire spelling for diagnostics.
8. **Unknown state — cannotCalculateChanges vs invalidArguments.**
   Step 11: a server may return either `cannotCalculateChanges` or
   `invalidArguments` for a synthetic bogus state — both are RFC-
   compliant. The assertion accepts either via `errorType in {...}`.
9. **queryChanges `total` echo.** Step 12: a server may emit `total`
   even when `calculateTotal=false` (Cyrus 3.12.2), or omit `total`
   even when `true` was requested if the server does not honour the
   parameter on the underlying query (James 3.9 on Email/query).
   The assertion is a **lower-bound** when `total.isSome`, never a
   strict equality, and never an absence assertion when `false`.
10. **queryChanges unimplemented.** Step 12: a server may not register
    the `Email/queryChanges` method at all (James 3.9). The library
    projects this as `metUnknownMethod`; `assertSuccessOrTypedError`
    exercises the typed-error projection in the same body that
    asserts the round-trip semantic on implementing servers.

## Success criteria

Phase B is complete when:

- All five new live test files exist under `tests/integration/live/`
  with the multi-target idiom (license, docstring, single `block`,
  `forEachLiveTarget` iteration, `client.close()` per iteration,
  `assertOn target, ...` with narrative messages,
  `assertSuccessOrTypedError` where applicable, `captureIfRequested`
  for the canonical fixture).
- All five new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six.
- `just test-integration` exits 0 with all configured targets
  passing.
- Every wire-format divergence Phase B surfaces is either absorbed at
  the `fromJson`/`toJson` layer, accommodated via
  `assertSuccessOrTypedError` on the typed-error rail, or — in the
  bounded-retry case for server asynchrony — modelled at the test
  layer with the parser invariant preserved.
- No new Nimble dependencies, no new devcontainer packages — the
  devcontainer-parity rule established at Phase A holds throughout.

## Out of scope for Phase B

Explicitly deferred to later phases:

- **EmailSubmission end-to-end** (alice → bob delivery, implicit
  chaining via `onSuccessUpdateEmail`, `DeliveryStatus` shape,
  `ParsedSmtpReply` round-trip with real RFC 3464 enhanced status
  codes) — Phase D.
- **`SearchSnippet/get`** (mandatory filter, `ChainedHandles[A, B]`
  generic, `addEmailQueryWithSnippets` builder) and
  **`EmailQueryThreadChain`** (RFC 8621 §4.10 four-call workflow,
  arity-4 chain record) — Phase C.
- **Multi-account ACL** (alice ↔ bob shared mailbox access,
  `Email/copy` between accounts, `forbidden` SetError variants on
  cross-account writes) — Phase E.
- **Push notifications, blob upload/download, Layer 5 C ABI** — not
  yet implemented in the library; not part of the integration-
  testing campaign at all until they exist.
- **Adversarial wire-format edge cases** (RFC 2047 encoded-word names
  in `EmailAddress.name`, fractional-second dates,
  empty-vs-null table entries, oversized request rejection at
  `maxSizeRequest`) — Phase F.
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in `tests/stress/`
  if/when it becomes a goal.

Phase C will introduce the chain machinery (`SearchSnippet/get` plus
`EmailQueryThreadChain`), validating the H1 type-lift work
(`ChainedHandles[A, B]` and the arity-4 record) against a real server
for the first time.
