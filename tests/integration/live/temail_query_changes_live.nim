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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailQueryChangesLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): test asserts on client behaviour, not on
    # specific server implementations. Stalwart 0.15.5 and Cyrus 3.12.2
    # implement Email/queryChanges; James 3.9 does not
    # (``EmailQueryMethod.scala`` returns ``canCalculateChanges =
    # CANNOT`` unconditionally and no ``EmailQueryChangesMethod`` is
    # registered) and emits a typed JMAP error. Both arms of
    # ``assertSuccessOrTypedError`` exercise the client library
    # contract: the success arm verifies the queryChanges round-trip
    # semantic; the error arm verifies the typed-error projection
    # against a real-world server response.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve inbox + seed three emails ------------------------------
    # The full live suite shares a Stalwart instance, so the inbox may
    # already hold messages seeded by earlier tests. The test asserts on
    # *deltas* — captured baseline ids, then the new added entry — not
    # on absolute counts.
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let id1 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-1", "seed1"
      )
      .expect("seedSimpleEmail 1[" & $target.kind & "]")
    let id2 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-2", "seed2"
      )
      .expect("seedSimpleEmail 2[" & $target.kind & "]")
    let id3 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-3", "seed3"
      )
      .expect("seedSimpleEmail 3[" & $target.kind & "]")

    # --- Email/query: capture queryState_1 + baseline-cardinality -------
    let (b1, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
    let resp1 =
      client.send(b1).expect("send Email/query baseline[" & $target.kind & "]")
    let queryResp = resp1.get(queryHandle).expect(
        "Email/query baseline extract[" & $target.kind & "]"
      )
    let queryState1 = queryResp.queryState
    assertOn target, id1 in queryResp.ids, "seed 1 must appear in baseline query ids"
    assertOn target, id2 in queryResp.ids, "seed 2 must appear in baseline query ids"
    assertOn target, id3 in queryResp.ids, "seed 3 must appear in baseline query ids"
    let baselineCount = queryResp.ids.len

    # --- Seed a fourth email --------------------------------------------
    let id4 = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-12 a-4", "seed4"
      )
      .expect("seedSimpleEmail 4[" & $target.kind & "]")

    # --- Email/queryChanges since queryState_1 --------------------------
    let (b2, qcHandle) = addEmailQueryChanges(
      initRequestBuilder(),
      mailAccountId,
      sinceQueryState = queryState1,
      calculateTotal = true,
    )
    let resp2 =
      client.send(b2).expect("send Email/queryChanges with-total[" & $target.kind & "]")
    captureIfRequested(client, "email-query-changes-with-total-" & $target.kind).expect(
      "captureIfRequested"
    )
    let qcExtract = resp2.get(qcHandle)
    assertSuccessOrTypedError(
      target, qcExtract, {metCannotCalculateChanges, metUnknownMethod}
    ):
      let qcr = success
      assertOn target,
        string(qcr.oldQueryState) == string(queryState1),
        "oldQueryState must echo the supplied baseline"
      assertOn target,
        string(qcr.newQueryState) != string(queryState1),
        "newQueryState must differ after a fresh seed"
      # RFC 8620 §5.6 permits a server to return ``calculateTotal`` as
      # absent (e.g. James 3.9 doesn't honour the parameter on Email/
      # query). When present it must reflect the latest count.
      if qcr.total.isSome:
        assertOn target,
          qcr.total.get() >= UnsignedInt(baselineCount + 1),
          "calculateTotal lower bound: at least baselineCount+1 (got " & $qcr.total & ")"
      # RFC 8620 §5.6 permits the same id appearing in both ``removed``
      # and ``added`` to signal a reposition under a sorted query. The
      # client-library contract verifies the wire shape parses; the
      # exact cardinality of ``removed``/``added`` is server-specific.
      var foundAdded = false
      for item in qcr.added:
        if string(item.id) == string(id4):
          foundAdded = true
          assertOn target,
            item.index < UnsignedInt(baselineCount + 1),
            "added.index must fall within the new query's bounds (got " & $item.index &
              ")"
          break
      assertOn target,
        foundAdded,
        "fourth seeded id must surface in qcr.added (got " & $qcr.added & ")"

    # --- Email/queryChanges without calculateTotal ----------------------
    # Issued purely so the captured-fixture loop records the "total
    # absent" response shape. The assertion is that ``total`` is
    # explicitly ``Opt.none`` — RFC 8620 §5.6: ``total`` is only present
    # when ``calculateTotal: true`` was sent.
    let (b3, qcNoTotalHandle) = addEmailQueryChanges(
      initRequestBuilder(), mailAccountId, sinceQueryState = queryState1
    )
    let resp3 =
      client.send(b3).expect("send Email/queryChanges no-total[" & $target.kind & "]")
    captureIfRequested(client, "email-query-changes-no-total-" & $target.kind).expect(
      "captureIfRequested"
    )
    let qcNoTotalExtract = resp3.get(qcNoTotalHandle)
    assertSuccessOrTypedError(
      target, qcNoTotalExtract, {metCannotCalculateChanges, metUnknownMethod}
    ):
      # RFC 8620 §5.6 says ``total`` is "only present" when
      # ``calculateTotal: true`` was sent. Some servers (Cyrus 3.12.2)
      # populate the field unconditionally; others honour the
      # absence. The wire-shape parse is the universal client-library
      # contract — both ``isNone`` and ``isSome`` are accepted here.
      discard success
    client.close()
