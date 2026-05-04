# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/queryChanges (RFC 8620 §5.6) against
## Stalwart. Closes the last of five Phase B gaps.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed three Emails — capture each id.
##  3. ``Email/query`` → capture ``queryState_1`` and the three ids.
##  4. Seed a fourth Email — capture its id.
##  5. ``Email/queryChanges`` with ``sinceQueryState=queryState_1`` and
##     ``calculateTotal=true``. Assert the response advances state,
##     reports a total of 4, surfaces no removals, and adds exactly one
##     entry — the fourth seed — with an index ``< 4``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailQueryChangesLive:
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

    # --- Resolve inbox + seed three emails ------------------------------
    # The full live suite shares a Stalwart instance, so the inbox may
    # already hold messages seeded by earlier tests. The test asserts on
    # *deltas* — captured baseline ids, then the new added entry — not
    # on absolute counts.
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let id1 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-1", "seed1"
      )
      .expect("seedSimpleEmail 1")
    let id2 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-2", "seed2"
      )
      .expect("seedSimpleEmail 2")
    let id3 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-3", "seed3"
      )
      .expect("seedSimpleEmail 3")

    # --- Email/query: capture queryState_1 + baseline-cardinality -------
    let (b1, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
    let resp1 = client.send(b1).expect("send Email/query baseline")
    let queryResp = resp1.get(queryHandle).expect("Email/query baseline extract")
    let queryState1 = queryResp.queryState
    doAssert id1 in queryResp.ids, "seed 1 must appear in baseline query ids"
    doAssert id2 in queryResp.ids, "seed 2 must appear in baseline query ids"
    doAssert id3 in queryResp.ids, "seed 3 must appear in baseline query ids"
    let baselineCount = queryResp.ids.len

    # --- Seed a fourth email --------------------------------------------
    let id4 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-4", "seed4"
      )
      .expect("seedSimpleEmail 4")

    # --- Email/queryChanges since queryState_1 --------------------------
    let (b2, qcHandle) = addEmailQueryChanges(
      initRequestBuilder(),
      mailAccountId,
      sinceQueryState = queryState1,
      calculateTotal = true,
    )
    let resp2 = client.send(b2).expect("send Email/queryChanges with-total")
    captureIfRequested(client, "email-query-changes-with-total-stalwart").expect(
      "captureIfRequested"
    )
    let qcr = resp2.get(qcHandle).expect("Email/queryChanges extract")

    doAssert string(qcr.oldQueryState) == string(queryState1),
      "oldQueryState must echo the supplied baseline"
    doAssert string(qcr.newQueryState) != string(queryState1),
      "newQueryState must differ after a fresh seed"
    doAssert qcr.total.isSome and qcr.total.get() == UnsignedInt(baselineCount + 1),
      "calculateTotal must surface baselineCount+1 (got " & $qcr.total & ")"
    doAssert qcr.removed.len == 0, "no destroys issued — removed must be empty"
    doAssert qcr.added.len == 1,
      "exactly one new entry must be added (got " & $qcr.added.len & ")"
    doAssert string(qcr.added[0].id) == string(id4),
      "the added entry must be the fourth seeded id"
    doAssert qcr.added[0].index < UnsignedInt(baselineCount + 1),
      "added.index must fall within the new query's bounds"

    # --- Email/queryChanges without calculateTotal ----------------------
    # Issued purely so the captured-fixture loop records the "total
    # absent" response shape. The assertion is that ``total`` is
    # explicitly ``Opt.none`` — RFC 8620 §5.6: ``total`` is only present
    # when ``calculateTotal: true`` was sent.
    let (b3, qcNoTotalHandle) = addEmailQueryChanges(
      initRequestBuilder(), mailAccountId, sinceQueryState = queryState1
    )
    let resp3 = client.send(b3).expect("send Email/queryChanges no-total")
    captureIfRequested(client, "email-query-changes-no-total-stalwart").expect(
      "captureIfRequested"
    )
    let qcrNoTotal =
      resp3.get(qcNoTotalHandle).expect("Email/queryChanges no-total extract")
    doAssert qcrNoTotal.total.isNone,
      "total must be absent when calculateTotal is not requested"
    client.close()
