# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Mailbox/queryChanges (RFC 8621 §2.4)
## against Stalwart. Phase H Step 44 — first wire test of
## ``addMailboxQueryChanges``. Mirrors the ``temail_query_changes_live``
## two-leg shape: a baseline ``Mailbox/query`` captures
## ``queryState_1`` and the baseline cardinality, a mutation
## (resolve-or-create child mailbox) advances the query state, then
## ``Mailbox/queryChanges`` is issued twice — once with
## ``calculateTotal: true``, once without — to exercise both the
## RFC 8620 §5.6 ``total`` projections.
##
## Two legs:
##  1. **With-total** — assert ``oldQueryState`` echoes the baseline,
##     ``total`` is present, and every ``AddedItem.id`` is non-empty
##     with ``index`` strictly less than ``total``. The Mailbox sort
##     is unstable under inserts (a new mailbox may shift existing
##     entries' positions in the tree-sorted output), so the
##     ``removed`` array can carry entries even when the only
##     mutation was a create — RFC 8620 §5.6 explicitly permits the
##     same id appearing in both ``removed`` and ``added`` to signal
##     a reposition. The test makes no cardinality assertion on
##     ``removed`` for that reason.
##  2. **No-total** — assert ``total.isNone`` (RFC 8620 §5.6:
##     ``total`` is only present when ``calculateTotal: true`` was
##     sent).
##
## Captures: ``mailbox-query-changes-with-total-stalwart`` after the
## with-total send and ``mailbox-query-changes-no-total-stalwart``
## after the no-total send. Listed in ``tests/testament_skip.txt`` so
## ``just test`` skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on
## ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tmailboxQueryChangesLive:
  forEachLiveTarget(target):
    # James 3.9 imposes the same restrictive contract on Mailbox/query
    # AND Mailbox/queryChanges: ``filter`` is mandatory (RFC 8620 §5.5
    # makes it optional, but James's ``MailboxQueryMethod.scala``
    # demands the property), no ``FilterOperator``, no ``sort``,
    # no ``position``/``anchor``/``anchorOffset``/``limit``,
    # no ``calculateTotal``, no ``sortAsTree``/``filterAsTree``. The
    # baseline ``Mailbox/query`` here uses the default ``QueryParams()``
    # — filter absent, calculateTotal=false — and James rejects with
    # ``invalidArguments`` "Missing '/filter' property" on entry.
    # Replay coverage for the Stalwart wire shape is preserved via the
    # captured ``-stalwart`` fixture.
    if target.kind == ltkJames:
      continue
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Baseline Mailbox/query: capture queryState_1 + cardinality -----
    # The full live suite shares a Stalwart instance. The test asserts on
    # *deltas* — the captured baseline queryState, then the new added
    # entry — not on absolute counts.
    let (b1, queryHandle) = addMailboxQuery(initRequestBuilder(), mailAccountId)
    let resp1 =
      client.send(b1).expect("send Mailbox/query baseline[" & $target.kind & "]")
    let queryResp = resp1.get(queryHandle).expect(
        "Mailbox/query baseline extract[" & $target.kind & "]"
      )
    let queryState1 = queryResp.queryState
    let baselineCount = queryResp.ids.len

    # --- Mutate: add a mailbox to advance the Mailbox query state -------
    let addedId = resolveOrCreateMailbox(client, mailAccountId, "phase-h step-44 added")
      .expect("resolveOrCreateMailbox added[" & $target.kind & "]")

    # --- With-total leg: Mailbox/queryChanges with calculateTotal ------
    let (b2, qcHandle) = addMailboxQueryChanges(
      initRequestBuilder(),
      mailAccountId,
      sinceQueryState = queryState1,
      calculateTotal = true,
    )
    let resp2 = client.send(b2).expect(
        "send Mailbox/queryChanges with-total[" & $target.kind & "]"
      )
    captureIfRequested(client, "mailbox-query-changes-with-total-" & $target.kind)
      .expect("captureIfRequested with-total")
    let qcr = resp2.get(qcHandle).expect(
        "Mailbox/queryChanges with-total extract[" & $target.kind & "]"
      )
    assertOn target,
      string(qcr.oldQueryState) == string(queryState1),
      "oldQueryState must echo the supplied baseline"
    assertOn target,
      qcr.total.isSome,
      "calculateTotal=true must surface a total (got " & $qcr.total & ")"
    let totalVal = qcr.total.get()
    for item in qcr.added:
      assertOn target, string(item.id).len > 0, "every added.id must be non-empty"
      assertOn target,
        item.index < totalVal,
        "added.index must fall within the new query's bounds (got " & $item.index &
          ", total " & $totalVal & ")"
    # ``addedId`` may or may not surface in qcr.added depending on
    # whether the mailbox already existed at queryState_1. Both cases
    # leave ``oldQueryState`` and ``total`` intact, which is the
    # deterministic surface under test.
    discard addedId
    discard baselineCount

    # --- No-total leg: Mailbox/queryChanges without calculateTotal ------
    # Issued purely so the captured-fixture loop records the "total
    # absent" response shape. The assertion is that ``total`` is
    # explicitly ``Opt.none`` — RFC 8620 §5.6: ``total`` is only present
    # when ``calculateTotal: true`` was sent.
    let (b3, qcNoTotalHandle) = addMailboxQueryChanges(
      initRequestBuilder(), mailAccountId, sinceQueryState = queryState1
    )
    let resp3 =
      client.send(b3).expect("send Mailbox/queryChanges no-total[" & $target.kind & "]")
    captureIfRequested(client, "mailbox-query-changes-no-total-" & $target.kind).expect(
      "captureIfRequested no-total"
    )
    let qcrNoTotal = resp3.get(qcNoTotalHandle).expect(
        "Mailbox/queryChanges no-total extract[" & $target.kind & "]"
      )
    assertOn target,
      qcrNoTotal.total.isNone,
      "total must be absent when calculateTotal is not requested"
    client.close()
