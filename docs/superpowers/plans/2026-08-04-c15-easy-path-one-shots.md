<!--
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2026 Aryan Ameri
-->

# C15 Easy-Path One-Shots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Nim easy path so a consumer (and, next, the C ABI
of `docs/design/17-L5-FFI-Principles.md`) can drive the full email-client
loop through one-shots alone: mark read/unread, move, destroy, vacation
set, state bootstrap, and incremental sync.

**Architecture:** Six new public one-shots land in the existing L4 module
`src/jmap_client/internal/one_shot.nim` (already re-exported by the root
hub — no hub change needed), riding one new private `runSet` helper. One
new L3 combinator in `src/jmap_client/internal/mail/combinators.nim`
back-references both `/created` and `/updated` from `Email/changes`
(closing ledger item C17). Everything follows the established one-shot
contract: `Result[T, JmapError]` returns, fail-fast `fulfil` collapse for
whole-method errors, per-item `SetError`s remaining data on the response.

**Tech Stack:** Nim 2.2.8, nim-results (vendored), testament via
`just test`; no new dependencies.

## Global Constraints

- Every public one-shot signature spells `Result[X, JmapError]` longhand
  (NOT the `JmapResult` alias) — the frozen `public-api.txt` records the
  longhand form.
- `one_shot.nim` is L4: `{.push raises: [].}` +
  `{.experimental: "strictCaseObjects".}`, public entry points are
  `proc` (they perform IO); `combinators.nim` is L3:
  `{.push raises: [], noSideEffect.}` — `func` only.
- Adding/changing PUBLIC symbols breaks the H16/H17 snapshot lints until
  `just freeze-api` and (for new public object types)
  `just freeze-type-shapes` are re-run — do this INSIDE the task that
  adds the symbol, before its commit, and review the snapshot diff
  (additions must be exactly the task's new symbols).
- Run `just fmt` then `just fmt-check` before every commit; run
  `just ci` before every commit (it is the gate: reuse, fmt-check, full
  lint battery incl. H15/H16/H17, analyse, fast tests).
- Never loosen compiler or nimalyzer settings; never add a `ruleOff`
  beyond what a task explicitly specifies.
- Docstrings: British English, why-not-what, no design-doc or ledger
  references inside source comments.
- Tests go in `tests/unit/tone_shot.nim` (fast suite) using its existing
  harness: `testCase` from `../mtestblock`, `assertOk`/`assertEq`/
  `assertLen` from `../massertions`, fixtures from `../mfixtures`,
  canned/recording transports from `../mtransport`, and the local
  `envelope(...)`/`cannedClient(...)` helpers. Builder call ids are
  deterministic: `c0`, `c1`, `c2` in add-order. Testament here uses NO
  `discard """..."""` spec block — plain module, `doAssert`-style helpers
  from massertions, joinable megatest defaults.
- Every commit message: Linux-kernel style (subsystem prefix, imperative,
  subject < 75 chars, body wrapped ~75 cols explaining why), ending with
  EXACTLY these three lines:

  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-5-fable
  ```

  No other AI attribution anywhere. Stage explicit paths only — NEVER
  `git add -A`.
- Base: `main` AFTER PR #18 (the L5 design note) has merged. Branch:
  `api/c15-easy-path-one-shots`.

---

### Task 0: Branch and land the plan

**Files:**
- Create: `docs/superpowers/plans/2026-08-04-c15-easy-path-one-shots.md`
  (this file)

- [ ] **Step 1: Branch off updated main**

```bash
git checkout main && git pull --ff-only
git checkout -b api/c15-easy-path-one-shots
```

- [ ] **Step 2: Commit the plan**

```bash
git add docs/superpowers/plans/2026-08-04-c15-easy-path-one-shots.md
git commit -m "docs/plans: plan the C15 easy-path one-shots"
```

(Full commit body: state that this plans the prerequisite PR from
`docs/design/17-L5-FFI-Principles.md` §8 — write one-shots, vacation set,
state bootstrap, and sync — then the three mandated trailer lines.)

---

### Task 1: `getEmailState` one-shot (state bootstrap, ledger C21)

**Files:**
- Modify: `src/jmap_client/internal/one_shot.nim` (append after
  `getVacationResponse`, ~line 148)
- Test: `tests/unit/tone_shot.nim`
- Modify: `tests/wire_contract/public-api.txt` (via `just freeze-api`)

**Interfaces:**
- Consumes: `getEmails` (one_shot.nim:101), `direct` (types/envelope.nim:298),
  `GetResponse[T].state` (protocol/methods.nim:209).
- Produces: `proc getEmailState*(client: JmapClient, accountId: AccountId):
  Result[JmapState, JmapError]` — Task 6's sync bootstrap and Task 7's CLI
  adoption call this.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/tone_shot.nim` (new section banner in the file's
existing style):

```nim
# -----------------------------------------------------------------------------
# getEmailState
# -----------------------------------------------------------------------------

testCase oneShotGetEmailStateSuccess:
  ## The state bootstrap issues one empty-ids Email/get and surfaces its
  ## ``state`` field alone — the sinceState cursor for a first sync.
  let responseJson = envelope(
    %*[
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s-42", "list": [], "notFound": []},
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.getEmailState(makeAccountId("acct-1"))
  assertOk(res)
  assertEq(res.value, makeState("s-42"))

testCase oneShotGetEmailStateMethodError:
  ## A method-level error on the single call collapses onto the rail as
  ## jeMethod — the fail-fast one-shot contract.
  let responseJson =
    envelope(%*[["error", {"type": "serverFail"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.getEmailState(makeAccountId("acct-1"))
  doAssert res.isErr
  doAssert res.error.kind == jeMethod
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nim c -r tests/unit/tone_shot.nim`
Expected: FAIL to compile with `undeclared identifier: 'getEmailState'`.

- [ ] **Step 3: Implement**

Append to `src/jmap_client/internal/one_shot.nim` directly after
`getVacationResponse`:

```nim
proc getEmailState*(
    client: JmapClient, accountId: AccountId
): Result[JmapState, JmapError] =
  ## Current ``Email`` object state — the ``sinceState`` cursor a first
  ## ``syncEmails`` call needs. Issues an ``Email/get`` with an empty ids
  ## list purely for its ``state`` field, so bootstrapping a sync cursor
  ## costs no email payload.
  let resp = ?client.getEmails(accountId, ids = Opt.some(direct(newSeq[Id]())))
  ok(resp.state)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nim c -r tests/unit/tone_shot.nim`
Expected: PASS (all existing cases plus the two new ones).

- [ ] **Step 5: Refreeze the API snapshot and gate**

```bash
just freeze-api
git diff tests/wire_contract/public-api.txt
```
Expected diff: exactly one added line — the `getEmailState` signature in
the `## jmap_client/internal/one_shot` block. (No new public TYPE, so
`freeze-type-shapes` is not needed.) Then:

```bash
just fmt && just fmt-check && just ci
```
Expected: `All CI checks passed!`

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/one_shot.nim tests/unit/tone_shot.nim \
  tests/wire_contract/public-api.txt
git commit -m "client: add the getEmailState bootstrap one-shot"
```

Body: why — `Email/changes` diffs against the object state, but nothing
surfaced it, forcing consumers to hand-roll an empty-ids `Email/get`
(the CLI's sync command documents the trick); this one-shot folds it.
Then the three trailers.

---

### Task 2: `runSet` helper + `markEmailsRead` / `markEmailsUnread`

**Files:**
- Modify: `src/jmap_client/internal/one_shot.nim`
- Test: `tests/unit/tone_shot.nim`
- Modify: `tests/wire_contract/public-api.txt` (refreeze)

**Interfaces:**
- Consumes: `initEmailUpdateSet` (mail/email_update.nim:263, returns
  `Result[EmailUpdateSet, NonEmptySeq[ValidationError]]`),
  `parseNonEmptyEmailUpdates` (email_update.nim:311, takes
  `openArray[(Id, EmailUpdateSet)]`), `markRead()`/`markUnread()`
  (email_update.nim:97/101), `addEmailSet` (mail/mail_builders.nim:326,
  `update: Opt[NonEmptyEmailUpdates]`), `.lift`
  (protocol/jmap_error.nim:353), `fulfil` (jmap_error.nim:393),
  `mnEmailSet` (types/methods_enum.nim:40).
- Produces:
  - private `proc runSet(client: JmapClient, accountId: AccountId,
    ids: openArray[Id], update: EmailUpdate):
    Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError]` —
    Task 3 reuses it.
  - `proc markEmailsRead*(client: JmapClient, accountId: AccountId,
    ids: openArray[Id]): Result[SetResponse[EmailCreatedItem,
    PartialEmail], JmapError]` and `markEmailsUnread*` (same shape).

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/tone_shot.nim`:

```nim
# -----------------------------------------------------------------------------
# markEmailsRead / markEmailsUnread
# -----------------------------------------------------------------------------

proc setUpdatedNullResponse(id: string): string =
  ## Email/set success where the server confirms the update with a null
  ## echo — the common case for keyword patches.
  envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "updated": {id: nil},
        },
        "c0",
      ]
    ]
  )

testCase oneShotMarkEmailsReadSuccess:
  ## One id marked read: the one-shot folds the triple seal and emits a
  ## single Email/set whose update patch sets keywords/$seen; the
  ## response surfaces through the S2 iterators.
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()),
    setUpdatedNullResponse("em-1"),
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-1")])
  assertOk(res)
  var updatedCount = 0
  for id, serverEcho in res.value.updated:
    updatedCount.inc
    assertEq($id, "em-1")
    doAssert serverEcho.isNone
  assertEq(updatedCount, 1)
  for _, _ in res.value.updateFailures:
    doAssert false
  # The emitted request carries the $seen patch for exactly this id.
  doAssert """"update":{"em-1":{"keywords/$seen":true}}""" in
    recorder.lastRequest.body

testCase oneShotMarkEmailsUnreadEmitsRemoval:
  ## markEmailsUnread patches keywords/$seen to null (removal).
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()),
    setUpdatedNullResponse("em-1"),
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res = client.markEmailsUnread(makeAccountId("acct-1"), @[makeId("em-1")])
  assertOk(res)
  doAssert """"update":{"em-1":{"keywords/$seen":null}}""" in
    recorder.lastRequest.body

testCase oneShotMarkEmailsReadSetErrorIsData:
  ## A per-id notUpdated entry stays DATA on the ok branch — the rail is
  ## reserved for whole-method failure.
  let responseJson = envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s1",
          "notUpdated": {"em-9": {"type": "notFound"}},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-9")])
  assertOk(res)
  var failureCount = 0
  for id, error in res.value.updateFailures:
    failureCount.inc
    assertEq($id, "em-9")
  assertEq(failureCount, 1)

testCase oneShotMarkEmailsReadEmptyIdsIsValidation:
  ## An empty ids list cannot form a NonEmptyEmailUpdates — the seal's
  ## own validation rides the rail; nothing is sent.
  let client = cannedClient(envelope(%*[]))
  let res = client.markEmailsRead(makeAccountId("acct-1"), newSeq[Id]())
  doAssert res.isErr
  doAssert res.error.kind == jeValidation

testCase oneShotMarkEmailsReadMethodError:
  ## A whole-method error collapses fail-fast onto jeMethod.
  let responseJson =
    envelope(%*[["error", {"type": "serverFail"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-1")])
  doAssert res.isErr
  doAssert res.error.kind == jeMethod
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nim c -r tests/unit/tone_shot.nim`
Expected: compile FAIL, `undeclared identifier: 'markEmailsRead'`.

- [ ] **Step 3: Implement**

Append to `one_shot.nim` (a new `# --- Email/set write one-shots ---`
section before the send-path section):

```nim
proc runSet(
    client: JmapClient,
    accountId: AccountId,
    ids: openArray[Id],
    update: EmailUpdate,
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Shared body of the Email/set write one-shots: seal one ``update``
  ## across every id, dispatch, and collapse the method outcome.
  ## Per-id ``SetError``s stay data on the response (``updateResults``
  ## and the projection iterators) — the rail carries only whole-method
  ## failure, so one rejected email never hides its siblings' results.
  let updateSet = ?initEmailUpdateSet(@[update]).lift
  var items = newSeqOfCap[(Id, EmailUpdateSet)](ids.len)
  for id in ids:
    items.add((id, updateSet))
  let updates = ?parseNonEmptyEmailUpdates(items).lift
  let (b, handle) =
    client.newBuilder().addEmailSet(accountId, update = Opt.some(updates))
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnEmailSet)

proc markEmailsRead*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Sets ``$seen`` on every id in one ``Email/set``. Empty or duplicate
  ## ids reject at the seal (the update set demands distinct, non-empty
  ## targets), so an empty call never reaches the network.
  runSet(client, accountId, ids, markRead())

proc markEmailsUnread*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Removes ``$seen`` from every id in one ``Email/set``.
  runSet(client, accountId, ids, markUnread())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nim c -r tests/unit/tone_shot.nim`
Expected: PASS. If the request-shape assertions fail on exact JSON
spelling, print `recorder.lastRequest.body`, confirm the patch object is
semantically identical (key order may differ), and match on the two
stable substrings `"keywords/$seen":true` / `"keywords/$seen":null` plus
`"em-1"` separately instead — do not weaken the semantic assertion.

- [ ] **Step 5: Refreeze, gate**

```bash
just freeze-api
git diff tests/wire_contract/public-api.txt   # exactly the 2 new procs
just fmt && just fmt-check && just ci
```

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/one_shot.nim tests/unit/tone_shot.nim \
  tests/wire_contract/public-api.txt
git commit -m "client: add the markEmailsRead/markEmailsUnread one-shots"
```

Body: why — the "update ONE email" case paid the
initEmailUpdateSet → parseNonEmptyEmailUpdates → addEmailSet triple seal
(the consumer bench's flag command repeats it verbatim in two files);
the one-shots fold it while keeping per-id SetErrors as data. Trailers.

---

### Task 3: `moveEmails` + `destroyEmails`

**Files:**
- Modify: `src/jmap_client/internal/one_shot.nim`
- Test: `tests/unit/tone_shot.nim`
- Modify: `tests/wire_contract/public-api.txt` (refreeze)

**Interfaces:**
- Consumes: Task 2's `runSet`; `moveToMailbox` (email_update.nim:113 —
  a FULL mailboxIds replace); `addEmailSet`'s
  `destroy: Opt[Referencable[seq[Id]]]` parameter; `directIds`
  (protocol/builder.nim:668 — ALREADY returns the full
  `Opt[Referencable[seq[Id]]]`; wrapping it in `Opt.some` again is a
  type error); `destroyed`/`destroyFailures` iterators
  (protocol/methods.nim:321/330).
- Produces: `proc moveEmails*(client: JmapClient, accountId: AccountId,
  ids: openArray[Id], mailboxId: Id): Result[SetResponse[
  EmailCreatedItem, PartialEmail], JmapError]`;
  `proc destroyEmails*(client: JmapClient, accountId: AccountId,
  ids: openArray[Id]): Result[SetResponse[EmailCreatedItem,
  PartialEmail], JmapError]`.

- [ ] **Step 1: Write the failing tests**

```nim
# -----------------------------------------------------------------------------
# moveEmails / destroyEmails
# -----------------------------------------------------------------------------

testCase oneShotMoveEmailsReplacesMembership:
  ## moveEmails is a full mailboxIds replace — the emitted patch names
  ## exactly the destination.
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()),
    setUpdatedNullResponse("em-1"),
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res = client.moveEmails(
    makeAccountId("acct-1"), @[makeId("em-1")], makeId("mb-2")
  )
  assertOk(res)
  doAssert """"mailboxIds":{"mb-2":true}""" in recorder.lastRequest.body

testCase oneShotDestroyEmailsSuccess:
  ## destroyEmails surfaces destroyed ids through the destroyed iterator;
  ## per-id refusals stay data in destroyFailures.
  let responseJson = envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "destroyed": ["em-1"],
          "notDestroyed": {"em-2": {"type": "forbidden"}},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.destroyEmails(
    makeAccountId("acct-1"), @[makeId("em-1"), makeId("em-2")]
  )
  assertOk(res)
  var destroyedIds: seq[string] = @[]
  for id in res.value.destroyed:
    destroyedIds.add($id)
  assertEq(destroyedIds, @["em-1"])
  var refusals = 0
  for id, error in res.value.destroyFailures:
    refusals.inc
    assertEq($id, "em-2")
  assertEq(refusals, 1)

testCase oneShotDestroyEmailsMethodError:
  let responseJson =
    envelope(%*[["error", {"type": "forbidden"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.destroyEmails(makeAccountId("acct-1"), @[makeId("em-1")])
  doAssert res.isErr
  doAssert res.error.kind == jeMethod
```

- [ ] **Step 2: Verify they fail**

Run: `nim c -r tests/unit/tone_shot.nim`
Expected: compile FAIL, `undeclared identifier: 'moveEmails'`.

- [ ] **Step 3: Implement**

```nim
proc moveEmails*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id], mailboxId: Id
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Moves every id to ``mailboxId`` — a full mailbox-membership replace,
  ## because "move" means the email is in the destination and nowhere
  ## else. Callers wanting additive membership use the builder path's
  ## ``addToMailbox`` update instead.
  runSet(client, accountId, ids, moveToMailbox(mailboxId))

proc destroyEmails*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Destroys every id in one ``Email/set``. Per-id refusals stay data
  ## (``destroyFailures``); the rail carries whole-method failure only.
  ## An empty ids list is legal wire and destroys nothing — the call
  ## still round-trips.
  let (b, handle) =
    client.newBuilder().addEmailSet(accountId, destroy = directIds(ids))
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnEmailSet)
```

- [ ] **Step 4: Verify tests pass** — `nim c -r tests/unit/tone_shot.nim`

- [ ] **Step 5: Refreeze, gate** — `just freeze-api`, inspect the diff
  (exactly 2 procs), `just fmt && just fmt-check && just ci`.

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/one_shot.nim tests/unit/tone_shot.nim \
  tests/wire_contract/public-api.txt
git commit -m "client: add the moveEmails and destroyEmails one-shots"
```

Body: why — completes the write half of the email-client loop the
consumer bench drives through hand-wired builders today; move is a
deliberate full-replace, destroy keeps per-id refusals as data. Trailers.

---

### Task 4: `setVacationResponse` one-shot

**Files:**
- Modify: `src/jmap_client/internal/one_shot.nim`
- Test: `tests/unit/tone_shot.nim`
- Modify: `tests/wire_contract/public-api.txt` (refreeze)

**Interfaces:**
- Consumes: `initVacationResponseUpdateSet`
  (mail/vacation.nim:203, `openArray[VacationResponseUpdate] →
  Result[VacationResponseUpdateSet, NonEmptySeq[ValidationError]]`),
  the update DSL `setIsEnabled(bool)` / `setFromDate` / `setToDate`
  (`Opt[UTCDate]`) / `setSubject` / `setTextBody` / `setHtmlBody`
  (`Opt[string]`) (vacation.nim:84-106), `addVacationResponseSet`
  (mail/mail_methods.nim:101 — `update` BY VALUE, singleton id internal)
  returning `ResponseHandle[SetResponse[NoCreate,
  PartialVacationResponse]]`.
- Produces: `proc setVacationResponse*(client: JmapClient,
  accountId: AccountId, updates: openArray[VacationResponseUpdate]):
  Result[SetResponse[NoCreate, PartialVacationResponse], JmapError]`.

- [ ] **Step 1: Confirm the method-name enum arm**

Run: `grep -n "VacationResponse" src/jmap_client/internal/types/methods_enum.nim`
Expected: an arm named `mnVacationResponseSet = "VacationResponse/set"`
(alongside `mnVacationResponseGet`). Use the exact arm name found in the
implementation below; if the name differs from `mnVacationResponseSet`,
use the file's name — do not add an arm.

- [ ] **Step 2: Write the failing tests**

```nim
# -----------------------------------------------------------------------------
# setVacationResponse
# -----------------------------------------------------------------------------

testCase oneShotSetVacationResponseSuccess:
  ## Enabling the singleton folds the update-set seal and dispatch into
  ## one call; the server confirms via updated["singleton"].
  let responseJson = envelope(
    %*[
      [
        "VacationResponse/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "updated": {"singleton": nil},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.setVacationResponse(
    makeAccountId("acct-1"),
    @[
      setIsEnabled(true),
      setSubject(Opt.some("Out of office")),
      setTextBody(Opt.some("Back Monday.")),
    ],
  )
  assertOk(res)
  var confirmed = 0
  for id, serverEcho in res.value.updated:
    confirmed.inc
    assertEq($id, "singleton")
  assertEq(confirmed, 1)

testCase oneShotSetVacationResponseEmptyIsValidation:
  ## An empty update batch has exactly one representation — not calling.
  ## The seal rejects it before any network traffic.
  let client = cannedClient(envelope(%*[]))
  let res = client.setVacationResponse(
    makeAccountId("acct-1"), newSeq[VacationResponseUpdate]()
  )
  doAssert res.isErr
  doAssert res.error.kind == jeValidation
```

- [ ] **Step 3: Verify they fail** — compile error on
  `setVacationResponse`.

- [ ] **Step 4: Implement**

```nim
proc setVacationResponse*(
    client: JmapClient,
    accountId: AccountId,
    updates: openArray[VacationResponseUpdate],
): Result[SetResponse[NoCreate, PartialVacationResponse], JmapError] =
  ## Updates the vacation singleton in one call, folding the update-set
  ## seal (which rejects empty batches, duplicate properties, and a
  ## backwards window) and the dispatch ceremony. The singleton id is
  ## the library's concern, not the caller's.
  let updateSet = ?initVacationResponseUpdateSet(updates).lift
  let (b, handle) =
    client.newBuilder().addVacationResponseSet(accountId, updateSet)
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnVacationResponseSet)
```

- [ ] **Step 5: Verify tests pass; refreeze; gate** — as before
  (`just freeze-api` diff = exactly 1 proc; `just fmt && just fmt-check
  && just ci`).

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/one_shot.nim tests/unit/tone_shot.nim \
  tests/wire_contract/public-api.txt
git commit -m "client: add the setVacationResponse one-shot"
```

Body: why — the vacation-set path paid the same seal-then-dispatch
ceremony as the email writes; folding it completes the write-side easy
path for every entity the library models. Trailers.

---

### Task 5: `addEmailChangesToGetAll` combinator (ledger C17)

**Files:**
- Modify: `src/jmap_client/internal/mail/combinators.nim`
- Test: `tests/protocol/tconvenience.nim` (the combinator test module —
  fast suite; its section B holds the existing `addEmailChangesToGet`
  cases this task's tests sit beside)
- Modify: `tests/wire_contract/public-api.txt` AND
  `tests/wire_contract/type-shapes.txt` (two new public generic types)

**Interfaces:**
- Consumes: `addEmailChanges` (mail_builders.nim:194), `addEmailGet`
  (mail_builders.nim:173), `reference[seq[Id]](handle, mnEmailChanges,
  rpCreated | rpUpdated)` (protocol/dispatch.nim:398; `rpUpdated`
  already exists at types/methods_enum.nim:88), `ChangesGetHandles[T]`
  precedent (combinators.nim:53), `getBoth` precedent
  (combinators.nim:252).
- Produces (all Task 6 consumes):

```nim
type ChangesGetAllHandles*[T] = object
  changes*: ResponseHandle[ChangesResponse[T]]
  created*: ResponseHandle[GetResponse[T]]
  updated*: ResponseHandle[GetResponse[T]]

type ChangesGetAllResults*[T] = object
  changes*: MethodOutcome[ChangesResponse[T]]
  created*: MethodOutcome[GetResponse[T]]
  updated*: MethodOutcome[GetResponse[T]]

func addEmailChangesToGetAll*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ChangesGetAllHandles[Email])

func getAll*[T](
    dr: DispatchedResponse, handles: ChangesGetAllHandles[T]
): Result[ChangesGetAllResults[T], JmapError]
```

- [ ] **Step 1: Write the failing tests**

Append to section B of `tests/protocol/tconvenience.nim` (after
`addEmailChangesToGetWiresCreatedReference`, ~line 72), mirroring the
section's exact harness:

```nim
testCase addEmailChangesToGetAllEmitsThreeInvocations:
  ## Changes plus BOTH back-referenced gets, in dispatch order.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, handles) =
    addEmailChangesToGetAll(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 3
  assertEq req.methodCalls[0].name, mnEmailChanges
  assertEq req.methodCalls[1].name, mnEmailGet
  assertEq req.methodCalls[2].name, mnEmailGet
  doAssert $handles.changes == "c0"
  doAssert $handles.created == "c1"
  doAssert $handles.updated == "c2"

testCase addEmailChangesToGetAllWiresBothReferences:
  ## /created feeds the first get, /updated the second — sync needs
  ## both halves of the fetchable delta.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) =
    addEmailChangesToGetAll(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  let createdRef = req.methodCalls[1].arguments{"#ids"}
  doAssert not createdRef.isNil
  assertEq createdRef{"name"}.getStr(""), "Email/changes"
  assertEq createdRef{"path"}.getStr(""), "/created"
  let updatedRef = req.methodCalls[2].arguments{"#ids"}
  doAssert not updatedRef.isNil
  assertEq updatedRef{"name"}.getStr(""), "Email/changes"
  assertEq updatedRef{"path"}.getStr(""), "/updated"
```

- [ ] **Step 2: Verify it fails** — compile error on
  `addEmailChangesToGetAll`.

- [ ] **Step 3: Implement**

Append to `combinators.nim`, after the existing `ChangesGetResults`
family (types near line 77, builder near line 154, extractor near
line 252 — keep the file's grouping: types together, builders together,
extractors together):

```nim
type ChangesGetAllHandles*[T] = object
  ## Handles for Email/changes plus BOTH back-referenced fetches. The
  ## delta a sync needs is created ∪ updated; destroyed ids need no
  ## fetch, so no third get exists.
  changes*: ResponseHandle[ChangesResponse[T]]
  created*: ResponseHandle[GetResponse[T]]
  updated*: ResponseHandle[GetResponse[T]]

type ChangesGetAllResults*[T] = object
  ## Each outcome is a MethodOutcome so one erroring method never
  ## discards its siblings' results (RFC 8620 §3.6.2).
  changes*: MethodOutcome[ChangesResponse[T]]
  created*: MethodOutcome[GetResponse[T]]
  updated*: MethodOutcome[GetResponse[T]]

func addEmailChangesToGetAll*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ChangesGetAllHandles[Email]) =
  ## ``Email/changes`` plus two server-side back-referenced
  ## ``Email/get`` calls — ``/created`` for new mail and ``/updated``
  ## for flag, keyword, and mailbox changes. Incremental sync needs
  ## both: fetching only ``/created`` leaves read/move churn invisible
  ## until a full refetch.
  let (b1, ch) = addEmailChanges(b, accountId, sinceState, maxChanges)
  let createdRef = reference[seq[Id]](ch, mnEmailChanges, rpCreated)
  let (b2, created) = addEmailGet(
    b1, accountId, ids = Opt.some(createdRef), bodyFetchOptions = bodyFetchOptions
  )
  let updatedRef = reference[seq[Id]](ch, mnEmailChanges, rpUpdated)
  let (b3, updated) = addEmailGet(
    b2, accountId, ids = Opt.some(updatedRef), bodyFetchOptions = bodyFetchOptions
  )
  (b3, ChangesGetAllHandles[Email](changes: ch, created: created, updated: updated))

func getAll*[T](
    dr: DispatchedResponse, handles: ChangesGetAllHandles[T]
): Result[ChangesGetAllResults[T], JmapError] =
  ## Extracts all three outcomes; the rail carries dispatch faults only.
  ok(
    ChangesGetAllResults[T](
      changes: ?dr.get(handles.changes),
      created: ?dr.get(handles.created),
      updated: ?dr.get(handles.updated),
    )
  )
```

- [ ] **Step 4: Verify the builder tests pass**

Run: `nim c -r tests/protocol/tconvenience.nim`
Expected: PASS (all existing section A–C cases plus the two new ones).

- [ ] **Step 5: Refreeze BOTH snapshots, gate**

```bash
just freeze-api          # + addEmailChangesToGetAll, getAll overload
just freeze-type-shapes  # + ChangesGetAllHandles, ChangesGetAllResults
git diff tests/wire_contract/
just fmt && just fmt-check && just ci
```

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/mail/combinators.nim \
  tests/protocol/tconvenience.nim tests/wire_contract/public-api.txt \
  tests/wire_contract/type-shapes.txt
git commit -m "mail: back-reference /updated in a changes-to-get-all combinator"
```

Body: why — the existing combinator fetches only `/created`, yet sync
overwhelmingly needs `/updated` (read/flag/move churn); a new combinator
rather than a parameter because the handle shape differs and the frozen
signature of the existing one must not change. Trailers.

---

### Task 6: `syncEmails` one-shot + `EmailSync` record

**Files:**
- Modify: `src/jmap_client/internal/one_shot.nim`
- Test: `tests/unit/tone_shot.nim`
- Modify: both wire-contract snapshots (new public type + proc)

**Interfaces:**
- Consumes: Task 5's `addEmailChangesToGetAll`/`getAll`;
  `fulfil` with `mnEmailChanges` / `mnEmailGet`; `ChangesResponse[Email]`
  fields (oldState/newState/hasMoreChanges/created/updated/destroyed).
- Produces:

```nim
type EmailSync* = object
  changes*: ChangesResponse[Email]
  created*: GetResponse[Email]
  updated*: GetResponse[Email]

proc syncEmails*(
    client: JmapClient,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): Result[EmailSync, JmapError]
```

- [ ] **Step 1: Write the failing tests**

```nim
# -----------------------------------------------------------------------------
# syncEmails
# -----------------------------------------------------------------------------

testCase oneShotSyncEmailsSuccess:
  ## One round-trip yields the full fetchable delta: the changes triple
  ## plus both back-referenced gets, every outcome already collapsed
  ## onto the rail. Canned gets return empty lists — the wiring, not
  ## Email decoding, is under test (bare-get coverage owns decoding).
  let responseJson = envelope(
    %*[
      [
        "Email/changes",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "hasMoreChanges": false,
          "created": ["em-new"],
          "updated": ["em-upd"],
          "destroyed": ["em-gone"],
        },
        "c0",
      ],
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s2", "list": [], "notFound": []},
        "c1",
      ],
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s2", "list": [], "notFound": []},
        "c2",
      ],
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.syncEmails(makeAccountId("acct-1"), makeState("s1"))
  assertOk(res)
  let sync = res.value
  assertEq($sync.changes.newState, "s2")
  doAssert not sync.changes.hasMoreChanges
  assertLen(sync.changes.created, 1)
  assertLen(sync.changes.updated, 1)
  assertLen(sync.changes.destroyed, 1)
  assertLen(sync.created.list, 0)
  assertLen(sync.updated.list, 0)

testCase oneShotSyncEmailsChangesErrorFailsFast:
  ## cannotCalculateChanges on the changes call collapses onto jeMethod
  ## even though the dependent gets also errored — fail-fast reports the
  ## root cause, not the cascade.
  let responseJson = envelope(
    %*[
      ["error", {"type": "cannotCalculateChanges"}, "c0"],
      ["error", {"type": "invalidResultReference"}, "c1"],
      ["error", {"type": "invalidResultReference"}, "c2"],
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.syncEmails(makeAccountId("acct-1"), makeState("s1"))
  doAssert res.isErr
  doAssert res.error.kind == jeMethod
```

- [ ] **Step 2: Verify they fail** — compile error on `syncEmails`.

- [ ] **Step 3: Implement**

```nim
type EmailSync* = object
  ## The full fetchable delta since a cursor. ``destroyed`` ids live on
  ## ``changes`` — there is nothing left to fetch for them.
  changes*: ChangesResponse[Email]
  created*: GetResponse[Email]
  updated*: GetResponse[Email]

proc syncEmails*(
    client: JmapClient,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): Result[EmailSync, JmapError] =
  ## Incremental sync in one round-trip: ``Email/changes`` plus both
  ## back-referenced fetches. Persist ``changes.newState`` as the next
  ## cursor; when ``changes.hasMoreChanges`` is true, call again from
  ## that cursor. Fail-fast: the changes call erroring is the root
  ## cause, so it is what the rail reports.
  let (b, handles) = client.newBuilder().addEmailChangesToGetAll(
    accountId, sinceState, maxChanges, bodyFetchOptions
  )
  let dr = ?client.send(b.freeze())
  let results = ?dr.getAll(handles)
  let changes = ?results.changes.fulfil(mnEmailChanges)
  let created = ?results.created.fulfil(mnEmailGet)
  let updated = ?results.updated.fulfil(mnEmailGet)
  ok(EmailSync(changes: changes, created: created, updated: updated))
```

`EmailSync`'s three fields have three distinct types, so no
`{.ruleOff: "objects".}` is expected; if `just analyse` disagrees, stop
and restructure rather than adding the pragma (Global Constraints).

- [ ] **Step 4: Verify tests pass.**

- [ ] **Step 5: Refreeze BOTH snapshots (new type + proc), inspect
  diffs, gate.**

- [ ] **Step 6: Commit**

```bash
git add src/jmap_client/internal/one_shot.nim tests/unit/tone_shot.nim \
  tests/wire_contract/public-api.txt tests/wire_contract/type-shapes.txt
git commit -m "client: add the syncEmails incremental-sync one-shot"
```

Body: why — sync was the last leg of the client loop with no easy path:
the bench hand-wired changes-to-get and still saw only created records.
One call now returns the full fetchable delta with a persistable cursor.
Trailers.

---

### Task 7: CLI bench adoption

**Files:**
- Modify: `examples/jmap-cli/commands/email_flag.nim` (full rewrite below)
- Modify: `examples/jmap-cli/commands/email_move.nim` (full rewrite below)
- Modify: `examples/jmap-cli/commands/email_sync.nim` (targeted edits)
- Modify: `examples/jmap-cli/commands/vacation.nim` (set path only)
- Modify: `examples/jmap-cli/AUDIT.md` (disposition updates)

**Interfaces:**
- Consumes: every Task 1–6 public. The CLI imports only `jmap_client`
  (enforced by `check-public-only.sh`) — the new one-shots are already
  reachable through the hub.

- [ ] **Step 1: Rewrite `email_flag.nim`**

Replace the command's body so the P29 bench documents the folded path
(keep the file's SPDX header and module docstring shape; update the
docstring to record that the one-shot replaced the triple seal). The
core becomes:

```nim
import jmap_client
import ./cli_session

proc flagLogic(args: seq[string]): JmapResult[int] =
  let emailId = ?parseIdFromServer(args[0]).lift
  let ctx = ?connect()
  let resp = ?ctx.client.markEmailsRead(ctx.mailAccount, @[emailId])
  for id, serverEcho in resp.updated:
    echo "marked read: ", id
  for id, error in resp.updateFailures:
    stderr.writeLine "not updated: ", id, ": ", error.message
  ok(0)

proc run*(args: seq[string]): int =
  if args.len != 1:
    stderr.writeLine "usage: jmap-cli email flag <emailId>"
    return 2
  flagLogic(args).valueOr:
    stderr.writeLine error.message
    return 1
```

(Match the surrounding files' exact `run*`/logic-proc split and echo
formatting; the S2 iterators replace the raw-table walk deliberately —
record that in the module docstring as the finding's resolution.)

- [ ] **Step 2: Rewrite `email_move.nim`** — the module docstring
  records that the former "repetition is the finding" comment is
  resolved: both commands are now one-liners over one-shots. The core
  becomes:

```nim
import jmap_client
import ./cli_session

proc moveLogic(args: seq[string]): JmapResult[int] =
  let emailId = ?parseIdFromServer(args[0]).lift
  let mailboxId = ?parseIdFromServer(args[1]).lift
  let ctx = ?connect()
  let resp = ?ctx.client.moveEmails(ctx.mailAccount, @[emailId], mailboxId)
  for id, serverEcho in resp.updated:
    echo "moved: ", id
  for id, error in resp.updateFailures:
    stderr.writeLine "not moved: ", id, ": ", error.message
  ok(0)

proc run*(args: seq[string]): int =
  if args.len != 2:
    stderr.writeLine "usage: jmap-cli email move <emailId> <mailboxId>"
    return 2
  moveLogic(args).valueOr:
    stderr.writeLine error.message
    return 1
```

- [ ] **Step 3: Edit `email_sync.nim`** — two changes:
  1. The no-argument bootstrap replaces its empty-ids `getEmails` trick
     with `let state = ?ctx.client.getEmailState(ctx.mailAccount)`;
     update the comment that documented the trick to state the accessor
     now exists.
  2. The since-state path replaces `addEmailChangesToGet` + `getBoth`
     with `let sync = ?ctx.client.syncEmails(ctx.mailAccount, sinceState)`;
     print created subjects from `sync.created.list`, UPDATED subjects
     from `sync.updated.list` (new capability — previously bare ids),
     destroyed ids from `sync.changes.destroyed`, and the cursor line
     from `sync.changes.oldState`/`newState`/`hasMoreChanges`. Remove
     the now-false "created records only" caveat comment.

- [ ] **Step 4: Edit `vacation.nim`** — the set path becomes:

```nim
let resp = ?ctx.client.setVacationResponse(
  ctx.mailAccount,
  @[
    setIsEnabled(true),
    setSubject(Opt.some("Out of office")),
    setTextBody(Opt.some(bodyText)),
  ],
)
```

with the confirmation loop over `resp.updated` replacing the manual
builder + `updateResults` walk. Keep the get path untouched.

- [ ] **Step 5: Update `AUDIT.md` dispositions** — locate (grep) the
  findings `email flag:set-construction`, `email move:repetition`,
  `email sync:changes-to-get-created-only`, `email sync:state-acquisition`,
  and the vacation set-ceremony finding if one carries a `filed` tag;
  flip each `filed-as-C15`/`filed-as-C17`/`filed-as-C21`-style tag to the
  matching `resolved-C15` / `resolved-C17` / `resolved-C21` (same tag
  grammar the ledger triage established). Do not touch any other
  disposition.

- [ ] **Step 6: Verify** — `just build`, then compile the CLI:
  `cd examples/jmap-cli && nim c jmap_cli.nim && ./check-public-only.sh`
  (run the script from wherever the repo invokes it — check its header).
  Then `just fmt && just fmt-check && just ci` at the repo root.

- [ ] **Step 7: Commit**

```bash
git add examples/jmap-cli/commands/email_flag.nim \
  examples/jmap-cli/commands/email_move.nim \
  examples/jmap-cli/commands/email_sync.nim \
  examples/jmap-cli/commands/vacation.nim examples/jmap-cli/AUDIT.md
git commit -m "examples/jmap-cli: adopt the write and sync one-shots"
```

Body: why — the bench exists to prove the API on real consumer code;
four commands shed their hand-wired ceremony, and sync gains updated-
record fetching the old path could not express. Trailers.

---

### Task 8: Ledger and design-note close-out

**Files:**
- Modify: `docs/TODO/pre-1.0-api-alignment.md`
- Modify: `docs/design/17-L5-FFI-Principles.md`

- [ ] **Step 1: Ledger item flips** (verify each body before editing):
  - C15 (~L2984) → `✅ DONE` dated 2026-08-04, noting what shipped:
    `markEmailsRead`/`markEmailsUnread`/`moveEmails`/`destroyEmails` +
    `setVacationResponse` (the vacation-set clause included by user
    decision), all on the one-shot contract.
  - C17 (~L3004) → `✅ DONE`: `addEmailChangesToGetAll` back-references
    both `/created` and `/updated`; the existing combinator's frozen
    signature untouched.
  - C21 (~L3039) → `✅ DONE`: `getEmailState`.
  - NEW item `### C23. Email/changes sync one-shot *(P7)* — ✅ DONE`
    appended after C22: body records `syncEmails` + `EmailSync`
    (subsuming C17's back-reference and C21's state accessor as its
    components), opened and closed by this PR as the design note's §8
    prescribed.
- [ ] **Step 2: Dashboard recount** — re-derive with the file's own
  documented grep; C15/C17/C21 move TODO→DONE, C23 adds one DONE.
- [ ] **Step 3: Design-note update** — in
  `docs/design/17-L5-FFI-Principles.md`, settled-decision 2 and §8's
  prerequisite bullet currently say the sync one-shot has NO ledger item
  and "the prerequisite PR opens one" — update both to cite C23 as
  opened-and-closed, and mark the §8 table's two "prerequisite PR" rows
  as landed.
- [ ] **Step 4: Gate and commit**

```bash
just ci
git add docs/TODO/pre-1.0-api-alignment.md docs/design/17-L5-FFI-Principles.md
git commit -m "docs/TODO: close C15, C17, C21 and file C23 as shipped"
```

Body: why — the prerequisite the L5 design note names is now real; the
ledger records exactly what shipped and the note stops pointing at an
unopened item. Trailers.

---

### Final verification (before the PR)

- [ ] `just ci` — green on the final tree.
- [ ] `git diff main --stat` — files touched are exactly those this plan
  names.
- [ ] The live gate (`just jmap-up` + `just test-full`) is the human's
  to run per project convention — flag it in the PR body as recommended
  before merge, since the new one-shots and combinator changed live
  request shapes (three-invocation sync).
- [ ] Confirm push/PR with the human (branch
  `api/c15-easy-path-one-shots`, base `main`).
