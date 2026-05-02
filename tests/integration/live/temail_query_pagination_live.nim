# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/query`` pagination (RFC 8620 §5.5)
## against Stalwart. Phase E Step 29 — exercises the QueryParams window
## across four legs:
##  1. position+limit: position=2, limit=2, calculateTotal=true. Asserts
##     ids.len==2, position==2, total>=5.
##  2. anchor baseline: filter only, no window. Captures baselineIds for
##     leg 3.
##  3. anchor+anchorOffset: anchor=baselineIds[2], anchorOffset=-1,
##     limit=2. Asserts the resulting ids are baselineIds[1..2].
##  4. metAnchorNotFound: anchor=synthetic-id, no match. Asserts
##     resp.get(handle).isErr with errorType==metAnchorNotFound and
##     rawType=="anchorNotFound".
##
## Captures: ``email-query-pagination-position-stalwart`` after leg 1 and
## ``email-query-pagination-anchor-not-found-stalwart`` after leg 4.
##
## Re-run tolerance: subjects share the disjoint discriminator
## ``"fritter29"`` so accumulation across runs only widens the result
## set; lower-bound assertions (``>= 5``) hold for any number of runs.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailQueryPaginationLive:
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
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # --- Resolve inbox + seed five emails ---------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    discard seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-e step-29 fritter29 a", "phase-e step-29 fritter29 b",
          "phase-e step-29 fritter29 c", "phase-e step-29 fritter29 d",
          "phase-e step-29 fritter29 e",
        ],
      )
      .expect("seedEmailsWithSubjects fritter29")

    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("fritter29")))

    # --- Leg 1: position+limit + calculateTotal ----------------------------
    let qpPos = QueryParams(
      position: JmapInt(2), limit: Opt.some(UnsignedInt(2)), calculateTotal: true
    )
    let (b1, h1) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpPos,
    )
    let resp1 = client.send(b1).expect("send Email/query position+limit")
    captureIfRequested(client, "email-query-pagination-position-stalwart").expect(
      "captureIfRequested position"
    )
    let qr1 = resp1.get(h1).expect("Email/query position+limit extract")
    doAssert qr1.ids.len == 2,
      "position=2,limit=2 must return exactly two ids (got " & $qr1.ids.len & ")"
    doAssert qr1.position == UnsignedInt(2),
      "position must echo the requested 2 (got " & $qr1.position & ")"
    doAssert qr1.total.isSome,
      "calculateTotal=true must surface total (got " & $qr1.total & ")"
    doAssert qr1.total.unsafeGet >= UnsignedInt(5),
      "total must be at least the seeded 5 (got " & $qr1.total.unsafeGet & ")"

    # --- Leg 2: anchor baseline (no window) --------------------------------
    let (b2, h2) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = QueryParams(),
    )
    let resp2 = client.send(b2).expect("send Email/query anchor baseline")
    let qr2 = resp2.get(h2).expect("Email/query anchor baseline extract")
    let baselineIds = qr2.ids
    doAssert baselineIds.len >= 5,
      "anchor baseline must return at least the seeded 5 ids (got " & $baselineIds.len &
        ")"

    # --- Leg 3: anchor + anchorOffset --------------------------------------
    let qpAnchor = QueryParams(
      anchor: Opt.some(baselineIds[2]),
      anchorOffset: JmapInt(-1),
      limit: Opt.some(UnsignedInt(2)),
    )
    let (b3, h3) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpAnchor,
    )
    let resp3 = client.send(b3).expect("send Email/query anchor+offset")
    let qr3 = resp3.get(h3).expect("Email/query anchor+offset extract")
    doAssert qr3.ids.len == 2,
      "anchor=baselineIds[2],offset=-1,limit=2 must return two ids (got " & $qr3.ids.len &
        ")"
    doAssert qr3.ids[0] == baselineIds[1],
      "first id must be baselineIds[1] (anchor at k=2 with offset -1 starts at k-1)"
    doAssert qr3.ids[1] == baselineIds[2],
      "second id must be baselineIds[2] (the anchor itself)"

    # --- Leg 4: metAnchorNotFound ------------------------------------------
    let synthetic = parseId("zzzzzzzzzzzzzzzzzzzzzzzzzzzz").expect("parseId synthetic")
    let qpBadAnchor =
      QueryParams(anchor: Opt.some(synthetic), limit: Opt.some(UnsignedInt(2)))
    let (b4, h4) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpBadAnchor,
    )
    let resp4 = client.send(b4).expect("send Email/query bad-anchor")
    captureIfRequested(client, "email-query-pagination-anchor-not-found-stalwart")
      .expect("captureIfRequested anchor-not-found")
    let qr4Result = resp4.get(h4)
    doAssert qr4Result.isErr,
      "Email/query with non-existent anchor must surface a method error per RFC 8620 §5.5"
    let methodErr = qr4Result.error
    doAssert methodErr.errorType == metAnchorNotFound,
      "errorType must project as metAnchorNotFound (got rawType=" & methodErr.rawType &
        ")"
    doAssert methodErr.rawType == "anchorNotFound",
      "rawType must round-trip the wire literal"
    client.close()
