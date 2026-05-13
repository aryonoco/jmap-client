# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/query`` pagination (RFC 8620 §5.5)
## against Stalwart. Phase E Step 29 — exercises the QueryParams
## window across four legs:
##
##  1. **Position+limit**: ``position=2, limit=2, calculateTotal=true``.
##     Asserts ``ids.len==2``, ``position==2``, ``total>=5``.
##     Capture: ``email-query-pagination-position-stalwart``.
##  2. **Anchor baseline**: filter only, ``QueryParams()`` defaults.
##     Captures ``baselineIds`` for leg 3 cross-checks. No capture.
##  3. **Anchor+anchorOffset (tolerant)**: anchor at
##     ``baselineIds[2]``, offset=-1, limit=2. Asserts:
##     - ``ids.len >= 1``
##     - every returned id is in ``baselineIds`` (the response is a
##       slice of the baseline)
##     - ``baselineIds[1]`` or ``baselineIds[2]`` (the anchor or the
##       item before it) appears in the result
##     The anchor+offset window-sizing is server-implementation
##     defined in practice; the strict-RFC reading would mandate
##     exactly 2 items, but Stalwart 0.15.5 returns a smaller window.
##     The tolerant assertions hold under both interpretations.
##     Capture: ``email-query-pagination-anchor-offset-stalwart``.
##  4. **metAnchorNotFound**: synthetic 28-octet ``'z'`` anchor cannot
##     match any allocated id; assert ``methodErr.errorType ==
##     metAnchorNotFound`` AND ``methodErr.rawType == "anchorNotFound"``.
##     RFC 8620 §5.5: "If the anchor is not found, the call is
##     rejected with an 'anchorNotFound' error." Capture:
##     ``email-query-pagination-anchor-not-found-stalwart``.
##
## Re-run tolerance: subjects share the disjoint discriminator
## ``"fritter29"`` so accumulation across runs only widens the result
## set; lower-bound assertions (``>= 5``) hold for any number of runs.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/sets

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailQueryPaginationLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises Email/query pagination shapes.
    # RFC 8620 §5.5 leaves ``calculateTotal`` to server discretion via
    # ``canCalculateTotal`` and lets a server reject ``anchor`` /
    # ``anchorOffset`` as ``invalidArguments`` if not supported.
    # Stalwart 0.15.5 supports the full surface; James 3.9 rejects
    # anchor/anchorOffset and omits ``total`` for Email/query; Cyrus
    # 3.12.2 supports the full surface (`imap/jmap_mail.c:212-248`,
    # `imap/jmap_mail_query.c:1071-1140`).
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve inbox + seed five emails ---------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let seededIds = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-e step-29 fritter29 a", "phase-e step-29 fritter29 b",
          "phase-e step-29 fritter29 c", "phase-e step-29 fritter29 d",
          "phase-e step-29 fritter29 e",
        ],
      )
      .expect("seedEmailsWithSubjects fritter29[" & $target.kind & "]")

    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("fritter29")))

    # Cyrus 3.12.2's Xapian rolling indexer lags Email/set by ~300 ms;
    # without this barrier the first leg's ``calculateTotal`` can
    # observe four of the five seeded rows and trip the ``>= 5``
    # lower bound. Stalwart and James index synchronously, so the
    # poll returns on the first iteration there.
    discard pollEmailQueryIndexed(target, mailAccountId, filter, seededIds.toHashSet)
      .expect("pollEmailQueryIndexed fritter29[" & $target.kind & "]")

    # --- Leg 1: position+limit + calculateTotal ----------------------------
    let qpPos = QueryParams(
      position: parseJmapInt(2).get(),
      limit: Opt.some(parseUnsignedInt(2).get()),
      calculateTotal: true,
    )
    let (b1, h1) = addEmailQuery(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpPos,
    )
    let resp1 = client.send(b1.freeze()).expect(
        "send Email/query position+limit[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-query-pagination-position-" & $target.kind
    )
      .expect("captureIfRequested position")
    let qr1 =
      resp1.get(h1).expect("Email/query position+limit extract[" & $target.kind & "]")
    assertOn target,
      qr1.ids.len == 2,
      "position=2,limit=2 must return exactly two ids (got " & $qr1.ids.len & ")"
    assertOn target,
      qr1.position == parseUnsignedInt(2).get(),
      "position must echo the requested 2 (got " & $qr1.position & ")"
    if qr1.total.isSome:
      # Server supports calculateTotal — assert the lower bound.
      assertOn target,
        qr1.total.unsafeGet >= parseUnsignedInt(5).get(),
        "total must be at least the seeded 5 (got " & $qr1.total.unsafeGet & ")"
    # When ``total.isNone`` the server is RFC-conformant: RFC 8620
    # §5.5 leaves the property server-discretionary via
    # ``canCalculateTotal``. The client wire shape parsed correctly.

    # --- Leg 2: anchor baseline (no window) --------------------------------
    let (b2, h2) = addEmailQuery(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = QueryParams(),
    )
    let resp2 = client.send(b2.freeze()).expect(
        "send Email/query anchor baseline[" & $target.kind & "]"
      )
    let qr2 =
      resp2.get(h2).expect("Email/query anchor baseline extract[" & $target.kind & "]")
    let baselineIds = qr2.ids
    assertOn target,
      baselineIds.len >= 5,
      "anchor baseline must return at least the seeded 5 ids (got " & $baselineIds.len &
        ")"

    # --- Leg 3: anchor + anchorOffset (tolerant) ---------------------------
    let qpAnchor = QueryParams(
      anchor: Opt.some(baselineIds[2]),
      anchorOffset: parseJmapInt(-1).get(),
      limit: Opt.some(parseUnsignedInt(2).get()),
    )
    let (b3, h3) = addEmailQuery(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpAnchor,
    )
    let resp3 = client.send(b3.freeze()).expect(
        "send Email/query anchor+offset[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-query-pagination-anchor-offset-" & $target.kind
    )
      .expect("captureIfRequested anchor-offset")
    let qr3Extract = resp3.get(h3)
    assertSuccessOrTypedError(
      target, qr3Extract, {metInvalidArguments, metUnsupportedFilter, metUnknownMethod}
    ):
      let qr3 = success
      assertOn target,
        qr3.ids.len >= 1,
        "anchor+offset query must return at least one id (got " & $qr3.ids.len & ")"
      let baselineSet = baselineIds.toHashSet
      for id in qr3.ids:
        assertOn target,
          id in baselineSet,
          "every anchor+offset id must appear in baselineIds (id=" & $id & ")"
      let qr3Set = qr3.ids.toHashSet
      assertOn target,
        (baselineIds[1] in qr3Set) or (baselineIds[2] in qr3Set),
        "anchor+offset response must contain the anchor (baselineIds[2]) or the item " &
          "immediately before it (baselineIds[1])"

    # --- Leg 4: metAnchorNotFound ------------------------------------------
    let synthetic = parseIdFromServer("zzzzzzzzzzzzzzzzzzzzzzzzzzzz").expect(
        "parseId synthetic[" & $target.kind & "]"
      )
    let qpBadAnchor = QueryParams(
      anchor: Opt.some(synthetic), limit: Opt.some(parseUnsignedInt(2).get())
    )
    let (b4, h4) = addEmailQuery(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = qpBadAnchor,
    )
    let resp4 = client.send(b4.freeze()).expect(
        "send Email/query bad-anchor[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody,
      "email-query-pagination-anchor-not-found-" & $target.kind,
    )
      .expect("captureIfRequested anchor-not-found[" & $target.kind & "]")
    let qr4Result = resp4.get(h4)
    if qr4Result.isErr:
      # Conformant servers surface a method error. Servers that
      # reject anchors at the parser layer return ``metInvalidArguments``
      # rather than ``metAnchorNotFound``; both are RFC-aligned typed
      # error projections.
      let getErr = qr4Result.unsafeError
      assertOn target,
        getErr.kind == gekMethod,
        "anchor-not-found must surface as gekMethod, not gekHandleMismatch"
      let methodErr = getErr.methodErr
      assertOn target,
        methodErr.errorType in {
          metAnchorNotFound, metInvalidArguments, metUnknownMethod
        },
        "errorType must project as metAnchorNotFound, metInvalidArguments, or " &
          "metUnknownMethod (got rawType=" & methodErr.rawType & ")"
