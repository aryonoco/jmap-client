# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 49 — first wire test of ``addMailboxQuery`` and
## ``addMailboxQueryChanges`` with filter + sort.  Phase H44 exercised
## the no-filter no-sort baseline; this step closes the
## ``MailboxFilterCondition`` (RFC 8621 §2.3) and ``Comparator``
## (sortOrder/name) gap, plus the ``sortAsTree`` extension.
##
## Workflow:
##
##  1. Filter by ``role: Opt.some(roleInbox)`` — asserts the Inbox
##     mailbox surfaces and the request shape Stalwart accepts.
##  2. Resolve / create three named mailboxes ``phase-i 49 alpha`` /
##     ``bravo`` / ``charlie``, then Mailbox/set update their
##     ``sortOrder`` to 30 / 20 / 10 so each run is idempotent
##     regardless of pre-existing state.  Filter by name ``"phase-i
##     49"`` (unique to this phase) and sort by ``sortOrder``
##     ascending — assert charlie → bravo → alpha.  Capture
##     ``mailbox-query-filter-sort-stalwart``.
##  3. ``sortAsTree`` extension under ``hasAnyRole: true`` — every
##     Stalwart-seeded principal carries an Inbox so the result set
##     is non-empty; assertion is structural only (every returned id
##     is non-empty), validating that the wire arg surfaces.
##  4. Capture baseline ``queryState`` from a name-filtered query,
##     resolve / create ``phase-i 49 delta``, issue Mailbox/queryChanges
##     with the same filter and ``calculateTotal: true``.  Assert
##     ``oldQueryState`` echoes the baseline and ``total.isSome``.
##     Capture ``mailbox-query-changes-with-filter-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env
## vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

proc assertRoleFilter(client: var JmapClient, mailAccountId: AccountId, inboxId: Id) =
  ## Sub-test 1: filter by ``role: Opt.some(roleInbox)`` returns the
  ## inbox among its results when the server accepts the role-filter
  ## shape; otherwise the typed error is acceptable.
  let roleFilter =
    filterCondition(MailboxFilterCondition(role: Opt.some(Opt.some(roleInbox))))
  let (b1, h1) = addMailboxQuery(
    initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(roleFilter)
  )
  let resp1 = client.send(b1.freeze()).expect("send Mailbox/query role filter")
  let qResp1Extract = resp1.get(h1)
  if qResp1Extract.isErr:
    let getErr = qResp1Extract.unsafeError
    doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in
      {metInvalidArguments, metUnsupportedFilter, metUnknownMethod},
      "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"
    return
  let qResp1 = qResp1Extract.unsafeValue
  var foundInbox = false
  for id in qResp1.ids:
    if id == inboxId:
      foundInbox = true
      break
  doAssert foundInbox,
    "Mailbox/query filter role=Inbox must surface the inbox id (got " & $qResp1.ids.len &
      " ids)"

proc setSortOrders(
    client: var JmapClient, mailAccountId: AccountId, alphaId, bravoId, charlieId: Id
) =
  ## Mailbox/set update enforces the desired sortOrder regardless of
  ## prior state, so re-runs are idempotent.
  let setAlpha = initMailboxUpdateSet(@[setSortOrder(UnsignedInt(30))]).expect(
      "initMailboxUpdateSet alpha"
    )
  let setBravo = initMailboxUpdateSet(@[setSortOrder(UnsignedInt(20))]).expect(
      "initMailboxUpdateSet bravo"
    )
  let setCharlie = initMailboxUpdateSet(@[setSortOrder(UnsignedInt(10))]).expect(
      "initMailboxUpdateSet charlie"
    )
  let updates = parseNonEmptyMailboxUpdates(
      @[(alphaId, setAlpha), (bravoId, setBravo), (charlieId, setCharlie)]
    )
    .expect("parseNonEmptyMailboxUpdates")
  let (b2u, h2u) = addMailboxSet(
    initRequestBuilder(makeBuilderId()), mailAccountId, update = Opt.some(updates)
  )
  let resp2u = client.send(b2u.freeze()).expect("send Mailbox/set sortOrder update")
  discard resp2u.get(h2u).expect("Mailbox/set sortOrder update extract")

proc assertFilterSortOrder(
    client: var JmapClient,
    mailAccountId: AccountId,
    alphaId, bravoId, charlieId: Id,
    nameFilter: Filter[MailboxFilterCondition],
    targetSuffix: string,
) =
  ## Sub-test 2: name filter + sortOrder ascending yields charlie →
  ## bravo → alpha when the server accepts the FilterOperator + sort
  ## shape; otherwise the typed error is acceptable.
  let sortOrderProp =
    parsePropertyName("sortOrder").expect("parsePropertyName sortOrder")
  let sortAsc = @[parseComparator(sortOrderProp, isAscending = true)]
  let (b2, h2) = addMailboxQuery(
    initRequestBuilder(makeBuilderId()),
    mailAccountId,
    filter = Opt.some(nameFilter),
    sort = Opt.some(sortAsc),
  )
  let resp2 = client.send(b2.freeze()).expect("send Mailbox/query filter+sort")
  captureIfRequested(client, "mailbox-query-filter-sort-" & targetSuffix).expect(
    "captureIfRequested filter+sort"
  )
  let qResp2Extract = resp2.get(h2)
  if qResp2Extract.isErr:
    let getErr = qResp2Extract.unsafeError
    doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in
      {metInvalidArguments, metUnsupportedSort, metUnsupportedFilter, metUnknownMethod},
      "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"
    return
  let qResp2 = qResp2Extract.unsafeValue
  var alphaPos = -1
  var bravoPos = -1
  var charliePos = -1
  for i, id in qResp2.ids:
    if id == alphaId:
      alphaPos = i
    elif id == bravoId:
      bravoPos = i
    elif id == charlieId:
      charliePos = i
  doAssert alphaPos >= 0 and bravoPos >= 0 and charliePos >= 0,
    "all three phase-i 49 mailboxes must surface in the filter result"
  doAssert charliePos < bravoPos and bravoPos < alphaPos,
    "sort by sortOrder ascending must yield charlie (10) → bravo (20) → " &
      "alpha (30); got positions charlie=" & $charliePos & " bravo=" & $bravoPos &
      " alpha=" & $alphaPos

proc assertSortAsTree(client: var JmapClient, mailAccountId: AccountId) =
  ## Sub-test 3: ``sortAsTree: true`` under ``hasAnyRole: true`` filter.
  ## Configured targets that seed an Inbox return a non-empty set;
  ## servers without ``sortAsTree`` support surface a typed error.
  let roleAnyFilter =
    filterCondition(MailboxFilterCondition(hasAnyRole: Opt.some(true)))
  let nameProp = parsePropertyName("name").expect("parsePropertyName name")
  let nameSort = @[parseComparator(nameProp, isAscending = true)]
  let (b3, h3) = addMailboxQuery(
    initRequestBuilder(makeBuilderId()),
    mailAccountId,
    filter = Opt.some(roleAnyFilter),
    sort = Opt.some(nameSort),
    sortAsTree = true,
  )
  let resp3 = client.send(b3.freeze()).expect("send Mailbox/query sortAsTree")
  let qResp3Extract = resp3.get(h3)
  if qResp3Extract.isErr:
    let getErr = qResp3Extract.unsafeError
    doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in
      {metInvalidArguments, metUnsupportedSort, metUnsupportedFilter, metUnknownMethod},
      "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"
    return
  let qResp3 = qResp3Extract.unsafeValue
  doAssert qResp3.ids.len >= 1,
    "Mailbox/query hasAnyRole=true must return at least the Inbox"
  for id in qResp3.ids:
    doAssert string(id).len > 0, "every returned id must be non-empty"

proc assertQueryChangesWithFilter(
    client: var JmapClient,
    mailAccountId: AccountId,
    nameFilter: Filter[MailboxFilterCondition],
    targetSuffix: string,
) =
  ## Sub-test 4: capture baseline queryState, mutate, queryChanges
  ## with the same filter and ``calculateTotal: true``. Servers that
  ## reject calculateTotal or the queryChanges shape surface a typed
  ## error.
  let (b4, h4) = addMailboxQuery(
    initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(nameFilter)
  )
  let resp4 =
    client.send(b4.freeze()).expect("send Mailbox/query baseline for queryChanges")
  let qResp4Extract = resp4.get(h4)
  if qResp4Extract.isErr:
    let getErr = qResp4Extract.unsafeError
    doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in
      {metInvalidArguments, metUnsupportedFilter, metUnknownMethod},
      "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"
    return
  let qResp4 = qResp4Extract.unsafeValue
  let baselineQueryState = qResp4.queryState

  let deltaId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 delta").expect(
      "resolveOrCreateMailbox delta"
    )
  discard deltaId

  let (b5, h5) = addMailboxQueryChanges(
    initRequestBuilder(makeBuilderId()),
    mailAccountId,
    sinceQueryState = baselineQueryState,
    filter = Opt.some(nameFilter),
    calculateTotal = true,
  )
  let resp5 = client.send(b5.freeze()).expect("send Mailbox/queryChanges with filter")
  captureIfRequested(client, "mailbox-query-changes-with-filter-" & targetSuffix).expect(
    "captureIfRequested queryChanges"
  )
  let qcrExtract = resp5.get(h5)
  if qcrExtract.isErr:
    let getErr = qcrExtract.unsafeError
    doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in {
      metInvalidArguments, metUnsupportedFilter, metCannotCalculateChanges,
      metUnknownMethod,
    }, "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"
    return
  let qcr = qcrExtract.unsafeValue
  doAssert string(qcr.oldQueryState) == string(baselineQueryState),
    "oldQueryState must echo the supplied baseline"
  doAssert qcr.total.isSome,
    "calculateTotal=true must surface a total in queryChanges response"

testCase tmailboxQueryFilterSortLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): Stalwart 0.15.5 and Cyrus 3.12.2 implement
    # the full Mailbox/query surface (FilterOperator, sort, position,
    # calculateTotal, sortAsTree, filterAsTree). James 3.9 imposes a
    # strict allow-list — only ``role`` filter, no sort/position/...,
    # no calculateTotal — and rejects the rest with typed errors.
    # Each sub-helper extracts the response and accepts either the
    # success arm or a typed-error projection.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    let inboxId = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    assertRoleFilter(client, mailAccountId, inboxId)

    let alphaId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 alpha")
      .expect("resolveOrCreateMailbox alpha[" & $target.kind & "]")
    let bravoId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 bravo")
      .expect("resolveOrCreateMailbox bravo[" & $target.kind & "]")
    let charlieId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 charlie")
      .expect("resolveOrCreateMailbox charlie[" & $target.kind & "]")
    setSortOrders(client, mailAccountId, alphaId, bravoId, charlieId)

    let nameFilter =
      filterCondition(MailboxFilterCondition(name: Opt.some("phase-i 49")))
    assertFilterSortOrder(
      client, mailAccountId, alphaId, bravoId, charlieId, nameFilter, $target.kind
    )
    assertSortAsTree(client, mailAccountId)
    assertQueryChangesWithFilter(client, mailAccountId, nameFilter, $target.kind)

    client.close()
