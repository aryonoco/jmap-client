# Integration Testing Plan — Phase B

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **B1 — Round out standard surfaces + changes protocol** | Not started | Five live tests (Steps 8–12) extending Phase A's foundation. Each step is one commit. `just test-integration` must finish under 30s wall-clock on completion. |

Live-test pass rate (cumulative across Phase A + B): **6 / 11**.
Wire-format divergences root-caused at the `fromJson` layer post-Phase-A:
**1** (Identity/set partial response, commit `c45ff46`). Phase B
divergences will be tabulated as they land.

## Context

Phase A closed on 2026-05-01 with six live tests passing in 6.2s
against Stalwart 0.15.5: `tsession_discovery`, `tcore_echo_live`,
`tmailbox_get_all_live`, `tidentity_get_live`,
`temail_query_get_chain_live`, `temail_set_keywords_live`. Foundational
JMAP request shapes (echo, single-method get, set-with-`ifInState`
state guards, two-method back-reference chains) and both error rails
(transport, method-level) are exercised end-to-end.

The library implements considerably more than Phase A touched. Three
RFC 8621 entity surfaces (`Thread`, `VacationResponse`, full
`Mailbox/set` CRUD) have unit and serde tests but no wire validation.
The state-delta protocol (`Foo/changes`, `Foo/queryChanges`) — the
operational counterpart of Phase A's state-guard machinery — is
unexercised against a real server. Stalwart's behaviour for these
surfaces is unknown until tested.

Phase B closes that gap before any work begins on the harder
surfaces: chained query workflows (Phase C), EmailSubmission with
implicit chaining and `ParsedSmtpReply` round-trips (Phase D), and
multi-account shared access (Phase E). Push, Blob, and Layer 5 C ABI
are out of scope for the entire integration-testing campaign — they
are not yet implemented in the library, and the campaign exists to
prove the existing surface before more is built.

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

## Phase B1 — Five live tests

All tests live under `tests/integration/live/` and follow the
established idiom verbatim (Phase A established it across its six
files):

- SPDX header + copyright block on lines 1–2
- `##` docstring (lines 4–~25) explaining purpose, Stalwart
  prerequisite, `testament_skip.txt` listing, and the
  `loadLiveTestConfig().isOk` guard semantics
- Imports in fixed order: `std/...` first, then `results`, then
  `jmap_client`, `jmap_client/client`, then `./mconfig`
- Single top-level `block <camelCaseName>:` wrapping the test body
- `let cfgRes = loadLiveTestConfig(); if cfgRes.isOk:` guard so the
  file joins testament's megatest cleanly when Stalwart is down
- `var client = initJmapClient(...).expect("initJmapClient")`
- `client.close()` immediately before the block exit — explicit, no
  `defer`
- `doAssert <invariant>, "<narrative explaining the invariant>"`
- All new files added to `tests/testament_skip.txt` so `just test`
  stays deterministic; run via `just test-integration`

Write them in order. Each step builds on what the previous step
proved.

### Step 8: `tthread_get_live.nim` — Thread/get against the seeded email's threadId

Scope: simplest unread entity in RFC 8621. Validates `Thread.fromJson`,
the generic `addGet[Thread]` overload via `registerJmapEntity(Thread)`,
and Stalwart's threading actually emits a Thread node for a freshly
created Email.

Body — four sequential `client.send` calls in one block:

1. `addGet[Mailbox](initRequestBuilder(), mailAccountId)` → resolve
   the Inbox id (re-using Phase A Step 6's `withValue` /
   `roleInbox` lookup pattern verbatim from
   `tests/integration/live/temail_query_get_chain_live.nim:50-61`).
2. `addEmailSet(create=...)` with a one-entry `EmailBlueprint` table —
   reuse the seed shape from Step 6 (`temail_query_get_chain_live.nim:63-100`)
   so this step proves nothing about creation that Step 6 already
   proved. Capture the seeded Email id from
   `setResp.createResults[cid].get().id`.
3. `addEmailGet(ids = directIds(@[seededId]), properties =
   Opt.some(@["id", "threadId"]))` → fetch the Email's `threadId`.
   Read it via `node{"threadId"}.getStr("")` (raw string, then
   parse via `parseId`).
4. `addGet[Thread](mailAccountId, ids = directIds(@[threadId]))` →
   the new dimension. Assert:
   - `gr.list.len == 1`
   - `Thread.fromJson(gr.list[0])` → `Ok`
   - `seededId in thread.emailIds`
   - `string(thread.id) == string(threadId)`

What this proves:

- `urn:ietf:params:jmap:mail` capability URI is auto-injected for the
  generic `addGet[Thread]` (no entity-specific overload exists for
  Thread, so this is the first test exercising the
  `registerJmapEntity(Thread)` path)
- `Thread.fromJson` accepts Stalwart's actual wire shape — the
  `emailIds` array is non-empty and parseable as `seq[Id]`
- Stalwart populates `Email.threadId` consistently with the
  `Thread.emailIds` membership

Anticipated wire-format divergence: Stalwart may return an empty
`emailIds` for a freshly-created Email if its threading pipeline is
asynchronous. If so, the `seededId in thread.emailIds` assertion will
fail; the fix is at the **test** layer (insert a re-fetch loop with a
small delay, capped) NOT at the parser. `parseThread` enforces a
non-empty invariant per `src/jmap_client/mail/thread.nim:32-36`, and
that invariant is correct per RFC 8621 §3 — every Thread MUST have
at least one Email.

### Step 9: `tvacation_get_set_live.nim` — VacationResponse get + set against the singleton

Scope: the only RFC 8621 entity without a variable id. Validates the
`urn:ietf:params:jmap:vacationresponse` capability URI auto-injection,
the singleton-id wire encoding (`"singleton"` hardcoded by the builder
per `mail_methods.nim:78`), and the typed
`VacationResponseUpdateSet` patch encoding.

Body — three sequential `client.send` calls plus a cleanup leg:

1. `addVacationResponseGet(initRequestBuilder(), vacAccountId)` —
   assert `gr.list.len == 1` (singleton invariant), parse via
   `VacationResponse.fromJson`. The library's response shape carries
   the `oldState` for the eventual idempotent reset.
2. `addVacationResponseSet(b, vacAccountId, update = updateSet)` where
   `updateSet = initVacationResponseUpdateSet(@[ setIsEnabled(true),
   setSubject(Opt.some("phase-b step-9 OOO")),
   setTextBody(Opt.some("Out until <date>.")) ]).expect(...)`. Assert
   `setResp.updateResults["singleton"].isOk`.
3. `addVacationResponseGet` again — parse the response, assert
   `vr.isEnabled == true`, `vr.subject == Opt.some("phase-b step-9 OOO")`,
   `vr.textBody == Opt.some("Out until <date>.")`.
4. **Cleanup leg** (still within the same block): one more
   `addVacationResponseSet` flipping `isEnabled` back to false, so
   re-runs against the same Stalwart instance see the same baseline.
   No assertion — best-effort idempotency hygiene.

Resolve the account id via `session.primaryAccounts.withValue(
"urn:ietf:params:jmap:vacationresponse", v):` — same idiom as
Phase A Step 4 / 5 / 6 / 7.

What this proves:

- `urn:ietf:params:jmap:vacationresponse` URI is in
  `session.primaryAccounts` and the builder auto-injects it via
  `mail_methods.nim:37`
- The hardcoded singleton id `"singleton"` round-trips through
  Stalwart's wire layer
- `VacationResponseUpdate` case-object → `(string, JsonNode)` patch
  pair (per `serde_vacation.nim:113`) renders as RFC 8620 §5.3
  `update[id][path]` shape that Stalwart accepts
- `VacationResponse.fromJson` accepts Stalwart's wire shape including
  any string fields (`subject`, `textBody`, `htmlBody`) and any UTC
  date fields

Anticipated wire-format divergences:

- Stalwart may return `null` vs absent for the optional date and body
  fields — `Opt[T]` plus the lenient `fromJson` for `UTCDate` should
  handle both, but the test should not assert specific
  `Opt.none`/`Opt.some` shape on fields the test did not set.
- The `htmlBody` field is RFC-optional and Stalwart may not emit it
  at all when unset.

The library exposes no creation or destroy path for VacationResponse
(no `parseVacationResponseCreate`, no `setSingleton`-triggering
overload). The singleton invariant is type-enforced at the source
level — Phase B does not attempt to test `setSingleton` projection
through a server round-trip. If a future RFC or Stalwart
extension allows creating a second VacationResponse, that test
arrives at that point.

### Step 10: `tmailbox_set_crud_live.nim` — Mailbox/set create + update + destroy with onDestroyRemoveEmails + setMailboxHasChild

Scope: first full CRUD round-trip; first server-projected entity-
specific SetError variant. Validates `parseMailboxCreate`, the
`MailboxUpdateSet` typed patch path, the entity-specific
`addMailboxSet` overload (the only standard /set with a non-standard
extra parameter), and the `setMailboxHasChild` SetError.

Body — six sequential `client.send` calls; both the happy path and
the structural sad path live in the same file (Phase A Step 7
precedent for combined-paths-in-one-test):

1. `addGet[Mailbox]` → resolve Inbox id (parent for the hierarchy).
2. `addMailboxSet(create = ...)` with one `parseMailboxCreate(name =
   "phase-b parent", parentId = Opt.some(inboxId))` entry. Assert
   `setResp.createResults[parentCid].isOk` and capture the server-
   assigned id `parentId = setResp.createResults[parentCid].get().id`.
3. `addMailboxSet(create = ...)` with one `parseMailboxCreate(name =
   "phase-b child", parentId = Opt.some(parentId))`. Assert
   `setResp.createResults[childCid].isOk`; capture `childId`.
4. **Sad path** — `addMailboxSet(destroy = directIds(@[parentId]))`
   without `onDestroyRemoveEmails`. Stalwart should reject with the
   `setMailboxHasChild` SetError per RFC 8621 §2.5. Assert:
   `setResp.destroyResults[parentId].isErr` and
   `setResp.destroyResults[parentId].error.errorType ==
   setMailboxHasChild` (variant from `errors.nim:275`, payload-less
   per the `seFieldsPlain(setMailboxHasChild)` arm at
   `errors.nim:388-389`).
5. **Update leg** — `addMailboxSet(update = parseNonEmptyMailboxUpdates(
   @[(childId, initMailboxUpdateSet(@[setName("phase-b renamed")]).get())]
   ).get())`. Assert `setResp.updateResults[childId].isOk`. (Validates
   the `MailboxUpdate` case-object → wire patch path —
   `mailbox.nim:283-360` plus serde.)
6. **Cleanup leg** — `addMailboxSet(destroy =
   directIds(@[childId, parentId]))`. Both should now succeed since
   the child went first (in destroy order — RFC 8620 §5.3 says
   destroy is processed left-to-right, so listing child before parent
   matters). Assert both `destroyResults[id].isOk`.

What this proves:

- `parseMailboxCreate` produces wire-compatible JSON Stalwart accepts
- The `parentId` field round-trips as a JSON string id (not a
  reference)
- The entity-specific `addMailboxSet` overload (`mail_builders.nim:112-136`)
  emits its arguments in the order Stalwart expects (creates and
  updates and destroys are processed in that order per RFC 8620 §5.3,
  not in argument order)
- The `setMailboxHasChild` SetError variant projects through the
  L3 error rail with `errorType == setMailboxHasChild` AND its raw
  string `"mailboxHasChild"` round-trips losslessly via `rawType`
- `MailboxUpdate.setName` (`mailbox.nim:312`) renders as the RFC §5.3
  patch shape `{"name": "..."}` Stalwart accepts (NOT the
  `{"/name": "..."}` JSON Pointer shape — RFC 8620 §5.3 specifies
  the path is the property name without the leading slash for a
  full-property replace)

`onDestroyRemoveEmails` itself is exercised at the **builder**
level (the Step 4 sad path passes `false` by relying on the default,
the Step 6 cleanup passes empty mailboxes — neither path actually
seeds emails inside the test mailbox, so the
`onDestroyRemoveEmails: bool` field's wire emission is exercised
without observing its semantic effect). Validating the semantic
effect (deleting emails on parent destroy) requires seeding emails
into the child mailbox first; that is **out of scope for Step 10**
and is the natural extension test if Phase B grows.

Anticipated wire-format divergences:

- Stalwart may emit `Mailbox.totalEmails` / `unreadEmails` as `0`
  (number) vs `null` for an empty mailbox. The test does NOT assert
  these fields, only the create/update/destroy result rails.
- The `setMailboxHasChild` arm's wire `type` field is exactly
  `"mailboxHasChild"` per RFC 8621 §10.6; Stalwart 0.15.5 should
  emit this verbatim. If Stalwart emits a different code (e.g.,
  `"hasChildren"`), the parser will project as `setUnknown` and
  the assertion fails — investigate the `rawType` to identify the
  divergence; the fix lives at the `errors.nim` SetErrorType enum
  if Stalwart's spelling is RFC-noncompliant or at the test if the
  test's expected value is wrong.

### Step 11: `temail_changes_live.nim` — Email/changes happy path + cannotCalculateChanges sad path

Scope: first state-delta test; introduces the `/changes` method
shape. Validates `addChanges[Email]` template resolution to
`ChangesResponse[Email]`, the delta arrays (`created`, `updated`,
`destroyed`), and the `metCannotCalculateChanges` MethodError
projection.

Body — six sequential `client.send` calls:

1. `addGet[Mailbox]` → Inbox id.
2. `addEmailGet(ids = directIds(@[]))` — fetch the empty list to
   capture the *baseline* `state`. (Asking Email/get with a literal
   empty ids array forces Stalwart to return `list: []` plus the
   current `state` — costs one round-trip but produces a clean
   baseline that does not depend on knowing any pre-existing email
   ids.) Capture `baselineState = getResp.state`.
3. `addEmailSet(create = ...)` with one `EmailBlueprint` (subject
   `"phase-b step-11 a"`).
4. `addEmailSet(create = ...)` with another `EmailBlueprint` (subject
   `"phase-b step-11 b"`).
5. **Happy path** — `addChanges[Email](b, mailAccountId,
   sinceState = baselineState)`. Assert:
   - `cr.oldState == baselineState`
   - `cr.created.len == 2` (both seeded ids present)
   - `cr.updated.len == 0`
   - `cr.destroyed.len == 0`
   - Both seeded ids appear in `cr.created`
6. **Sad path** — `addChanges[Email](b, mailAccountId,
   sinceState = JmapState("phase-b-bogus-state"))`. The plain
   `parseJmapState` accepts arbitrary non-empty strings (per
   `identifiers.nim`), so the request is well-formed; Stalwart
   should reject at the method level. Assert:
   - `resp.get(handle).isErr`
   - `methodErr.errorType == metCannotCalculateChanges`
   - `methodErr.rawType == "cannotCalculateChanges"`

What this proves:

- The `addChanges[T]` template (`builder.nim:193-205`) expands to
  `addChanges[Email, changesResponseType(Email)]` which resolves to
  `ChangesResponse[Email]` — the registration is wired correctly for
  Email
- `ChangesResponse[T]` deserialises with all six fields present
  (`accountId`, `oldState`, `newState`, `hasMoreChanges`, plus the
  three id arrays)
- The state strings round-trip: `baselineState` echoed as `oldState`
- The `metCannotCalculateChanges` MethodError variant projects from
  the wire `"cannotCalculateChanges"` string per `errors.nim:217`
  via the `rawType` lossless field

Anticipated wire-format divergences:

- Stalwart may treat any unknown state string as "snapshot lost" and
  return `cannotCalculateChanges`, OR it may treat unknown states as
  malformed input and return `invalidArguments`. Both are RFC-
  compliant; both project as MethodError variants. If Stalwart
  emits `invalidArguments`, change the assertion to accept either
  `metCannotCalculateChanges` OR `metInvalidArguments` and document
  Stalwart's choice; do not weaken the parser.
- `MaxChanges` (the optional integer cap) is NOT exercised in Step 11
  — the test has only two changes, well under any sane server limit.
  Promote to a future regression if Stalwart ever changes its default.

### Step 12: `temail_query_changes_live.nim` — Email/queryChanges with calculateTotal=true

Scope: composed change-over-query protocol. Validates
`addEmailQueryChanges` (entity-specific overload at
`mail_builders.nim:227-249`), `QueryChangesResponse[Email]`
deserialisation, and the `AddedItem` shape (`{id, index}` pair from
`framework.nim:81-94`).

Body — six sequential `client.send` calls:

1. `addGet[Mailbox]` → Inbox id.
2. Three `addEmailSet(create = ...)` requests (one per email — keeping
   creates separate avoids any "create-N-in-one-set" Stalwart
   quirks; each should emit a fresh queryState). Subjects are
   `"phase-b step-12 a-1"`, `"phase-b step-12 a-2"`,
   `"phase-b step-12 a-3"`. Capture each created id; note Phase A
   Step 6's seed pattern proved that `Email/set create` works
   reliably for arbitrary subjects.
3. `addEmailQuery(b, mailAccountId)` — no filter, no sort. Capture
   `queryState_1 = queryResp.queryState` and the ids.
4. One more `addEmailSet(create = ...)` with subject
   `"phase-b step-12 a-4"`. Capture id.
5. `addEmailQueryChanges(b, mailAccountId, sinceQueryState =
   queryState_1, calculateTotal = true)`. Assert:
   - `qcr.oldQueryState == queryState_1`
   - `qcr.newQueryState != queryState_1`
   - `qcr.total.isSome and qcr.total.get() == UnsignedInt(4)`
   - `qcr.removed.len == 0`
   - `qcr.added.len == 1`
   - `string(qcr.added[0].id) == string(idOfFourthEmail)`
   - The added item's `index` value is in range `[0u, 4u)` —
     the test does NOT assert a specific index because Stalwart's
     default sort order (no explicit sort given) is implementation-
     defined per RFC 8620 §5.5, and asserting position would couple
     the test to Stalwart's choice rather than the protocol.

What this proves:

- The entity-specific `addEmailQueryChanges` overload at
  `mail_builders.nim:227-249` emits the request shape Stalwart
  accepts (including the `collapseThreads: false` default)
- `QueryChangesResponse[T]` deserialises with all six standard
  fields (`accountId`, `oldQueryState`, `newQueryState`, `total`,
  `removed`, `added`)
- `AddedItem` (`framework.nim:81-94`) deserialises both the `id`
  string and the `index` UnsignedInt
- The `calculateTotal: true` parameter actually elicits a `total`
  field in the response (RFC 8620 §5.6 says it's only emitted when
  requested)
- Stalwart's queryState bookkeeping correctly encodes a state
  transition between `queryState_1` and `queryState_2` such that
  the delta is exactly the new email

Anticipated wire-format divergences:

- Stalwart may emit `total` as a JSON number even when
  `calculateTotal=false` was the default (some servers eagerly emit
  it). The test does not assert *absence* in the false case, only
  presence in the true case.
- The `index` field is server-determined per Stalwart's sort
  ordering when no sort is specified; the test asserts membership
  in the range only.
- An aggressively rate-limited Stalwart instance might collapse the
  three creates into a single state transition rather than three
  distinct ones, which would still give correct queryChanges
  semantics (`added` would still be size 1 for the post-query
  create); no test change needed.

A second sad-path leg (calling `addEmailQueryChanges` with a
different filter than the original query) is **deliberately omitted**
from Step 12. RFC 8620 §5.6 says the server MAY return
`cannotCalculateChanges` if filter/sort changes between calls, but
servers vary in strictness — Stalwart 0.15.5's behaviour here is
unverified. Adding the assertion couples the test to a specific
Stalwart version; promote it to a regression once Stalwart's
behaviour is empirically pinned.

## Predictable wire-format divergences (Phase B catalogue)

Catalogue of what live testing typically reveals at each new surface
Phase B introduces. The strict/lenient boundary in serde is the
right place to fix each one.

1. **Thread emailIds asynchrony.** Step 8: Stalwart's threading
   pipeline may not have populated `Thread.emailIds` by the time
   Thread/get is called. Re-fetch loop in the test, NOT a parser
   change.
2. **VacationResponse optional fields.** Step 9: optional
   string/date fields may be `null` vs absent vs empty string.
   `Opt[T]` plus lenient `fromJson` handles all three.
3. **Mailbox/set processing order.** Step 10: RFC §5.3 specifies
   create-then-update-then-destroy regardless of argument order;
   tests must NOT depend on argument ordering.
4. **SetError raw type spelling.** Step 10: any divergence between
   Stalwart's emitted `type` string and the RFC 8621 §10.6
   registry projects as `setUnknown` with a non-empty `rawType`.
   Fix lives in `errors.nim` if the spelling is RFC-noncompliant
   server-side; otherwise fix the test.
5. **Unknown state vs invalid state.** Step 11: server may return
   `cannotCalculateChanges` OR `invalidArguments` for a synthetic
   bogus state — both are RFC-compliant; the assertion must accept
   either.
6. **queryChanges calculateTotal echo.** Step 12: server may
   emit `total` even when `calculateTotal=false`; the test
   asserts presence only when `true` was requested, never absence
   when `false`.

## Success criteria

Phase B is complete when:

- [ ] All five new live test files exist under
  `tests/integration/live/` with the established idiom (license,
  docstring, single `block`, `loadLiveTestConfig().isOk` guard,
  `client.close()` before block exit, `doAssert` with narrative
  messages)
- [ ] All five new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six (lines 33–38 today)
- [ ] `just test-integration` exits 0 with eleven live tests passing
  (six from Phase A, five from Phase B)
- [ ] Every wire-format divergence Phase B surfaces has been
  root-caused at the `fromJson`/`toJson` layer or documented in this
  file's catalogue, NOT papered over in the test
- [ ] The eleven tests run in under 30 seconds total wall-clock on
  the devcontainer (Phase A's six ran in 6.2s; five additions plus
  six-to-thirty-second budget leaves comfortable headroom)
- [ ] No new Nimble dependencies, no new devcontainer packages — the
  2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro at
  `01-integration-testing-A.md:249-255`) holds throughout

## Out of scope for Phase B

Explicitly deferred to later phases:

- **EmailSubmission end-to-end** (alice → bob delivery, implicit
  chaining via `onSuccessUpdateEmail`, `DeliveryStatus` shape,
  `ParsedSmtpReply` round-trip with real RFC 3464 enhanced status
  codes) — Phase D
- **`SearchSnippet/get`** (mandatory filter, `ChainedHandles[A, B]`
  generic, `addEmailQueryWithSnippets` builder) and
  **`EmailQueryThreadChain`** (RFC 8621 §4.10 four-call workflow,
  arity-4 chain record) — Phase C
- **Multi-account ACL** (alice ↔ bob shared mailbox access,
  `Email/copy` between accounts, `forbidden` SetError variants on
  cross-account writes) — Phase E
- **Push notifications, blob upload/download, Layer 5 C ABI** — not
  yet implemented in the library; not part of the integration-
  testing campaign at all until they exist
- **Adversarial wire-format edge cases** (RFC 2047 encoded-word names
  in `EmailAddress.name`, fractional-second dates,
  empty-vs-null table entries, oversized request rejection at
  `maxSizeRequest`) — Phase F (optional symmetry; may be folded into
  individual phase tests as inline assertions instead)
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in `tests/stress/`
  if/when it becomes a goal

Phase C will introduce the chain machinery (`SearchSnippet/get`
plus `EmailQueryThreadChain`), validating the H1 type-lift work
(`ChainedHandles[A, B]` and the arity-4 record) against a real
server for the first time.
