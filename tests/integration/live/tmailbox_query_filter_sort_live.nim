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
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env
## vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

proc assertRoleFilter(client: var JmapClient, mailAccountId: AccountId, inboxId: Id) =
  ## Sub-test 1: filter by ``role: Opt.some(roleInbox)`` returns the
  ## inbox among its results.
  let roleFilter =
    filterCondition(MailboxFilterCondition(role: Opt.some(Opt.some(roleInbox))))
  let (b1, h1) =
    addMailboxQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(roleFilter))
  let resp1 = client.send(b1).expect("send Mailbox/query role filter")
  let qResp1 = resp1.get(h1).expect("Mailbox/query role filter extract")
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
  let (b2u, h2u) =
    addMailboxSet(initRequestBuilder(), mailAccountId, update = Opt.some(updates))
  let resp2u = client.send(b2u).expect("send Mailbox/set sortOrder update")
  discard resp2u.get(h2u).expect("Mailbox/set sortOrder update extract")

proc assertFilterSortOrder(
    client: var JmapClient,
    mailAccountId: AccountId,
    alphaId, bravoId, charlieId: Id,
    nameFilter: Filter[MailboxFilterCondition],
) =
  ## Sub-test 2: name filter + sortOrder ascending yields charlie →
  ## bravo → alpha.  Captures the wire response.
  let sortOrderProp =
    parsePropertyName("sortOrder").expect("parsePropertyName sortOrder")
  let sortAsc = @[parseComparator(sortOrderProp, isAscending = true)]
  let (b2, h2) = addMailboxQuery(
    initRequestBuilder(),
    mailAccountId,
    filter = Opt.some(nameFilter),
    sort = Opt.some(sortAsc),
  )
  let resp2 = client.send(b2).expect("send Mailbox/query filter+sort")
  captureIfRequested(client, "mailbox-query-filter-sort-stalwart").expect(
    "captureIfRequested filter+sort"
  )
  let qResp2 = resp2.get(h2).expect("Mailbox/query filter+sort extract")
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
  ## Stalwart-seeded principals always have at least the Inbox, so the
  ## result set is non-empty; assertion is structural — every returned
  ## id is non-empty.
  let roleAnyFilter =
    filterCondition(MailboxFilterCondition(hasAnyRole: Opt.some(true)))
  let nameProp = parsePropertyName("name").expect("parsePropertyName name")
  let nameSort = @[parseComparator(nameProp, isAscending = true)]
  let (b3, h3) = addMailboxQuery(
    initRequestBuilder(),
    mailAccountId,
    filter = Opt.some(roleAnyFilter),
    sort = Opt.some(nameSort),
    sortAsTree = true,
  )
  let resp3 = client.send(b3).expect("send Mailbox/query sortAsTree")
  let qResp3 = resp3.get(h3).expect("Mailbox/query sortAsTree extract")
  doAssert qResp3.ids.len >= 1,
    "Mailbox/query hasAnyRole=true must return at least the Inbox"
  for id in qResp3.ids:
    doAssert string(id).len > 0, "every returned id must be non-empty"

proc assertQueryChangesWithFilter(
    client: var JmapClient,
    mailAccountId: AccountId,
    nameFilter: Filter[MailboxFilterCondition],
) =
  ## Sub-test 4: capture baseline queryState, mutate, queryChanges
  ## with the same filter and ``calculateTotal: true``.
  let (b4, h4) =
    addMailboxQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(nameFilter))
  let resp4 = client.send(b4).expect("send Mailbox/query baseline for queryChanges")
  let qResp4 = resp4.get(h4).expect("Mailbox/query baseline extract")
  let baselineQueryState = qResp4.queryState

  let deltaId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 delta").expect(
      "resolveOrCreateMailbox delta"
    )
  discard deltaId

  let (b5, h5) = addMailboxQueryChanges(
    initRequestBuilder(),
    mailAccountId,
    sinceQueryState = baselineQueryState,
    filter = Opt.some(nameFilter),
    calculateTotal = true,
  )
  let resp5 = client.send(b5).expect("send Mailbox/queryChanges with filter")
  captureIfRequested(client, "mailbox-query-changes-with-filter-stalwart").expect(
    "captureIfRequested queryChanges"
  )
  let qcr = resp5.get(h5).expect("Mailbox/queryChanges extract")
  doAssert string(qcr.oldQueryState) == string(baselineQueryState),
    "oldQueryState must echo the supplied baseline"
  doAssert qcr.total.isSome,
    "calculateTotal=true must surface a total in queryChanges response"

block tmailboxQueryFilterSortLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    let inboxId = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    assertRoleFilter(client, mailAccountId, inboxId)

    let alphaId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 alpha")
      .expect("resolveOrCreateMailbox alpha")
    let bravoId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 bravo")
      .expect("resolveOrCreateMailbox bravo")
    let charlieId = resolveOrCreateMailbox(client, mailAccountId, "phase-i 49 charlie")
      .expect("resolveOrCreateMailbox charlie")
    setSortOrders(client, mailAccountId, alphaId, bravoId, charlieId)

    let nameFilter =
      filterCondition(MailboxFilterCondition(name: Opt.some("phase-i 49")))
    assertFilterSortOrder(
      client, mailAccountId, alphaId, bravoId, charlieId, nameFilter
    )
    assertSortAsTree(client, mailAccountId)
    assertQueryChangesWithFilter(client, mailAccountId, nameFilter)

    client.close()
