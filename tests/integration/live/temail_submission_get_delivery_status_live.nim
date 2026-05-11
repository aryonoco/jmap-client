# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for EmailSubmission/get post-delivery —
## reads ``deliveryStatus`` (RFC 8621 §7 ¶8) and validates the parsed
## ``ParsedSmtpReply`` shape end-to-end. Phase F Step 33 reuses the
## seed-and-submit pipeline from Step 32 and then issues a fresh
## ``EmailSubmission/get`` once the poll resolves to ``usFinal``,
## projecting the ``DeliveryStatusMap`` onto the recipient
## ``RFC5321Mailbox`` key. Stalwart 0.15.5's ``route.local`` queue
## hands the message to the local mailbox without DSN tracking, so
## ``delivered.state`` projects as ``dsUnknown`` (a literal RFC 8621
## §7 ¶8 ``"unknown"``) — the SMTP reply still carries the queue's
## ``250 2.1.5 Queued`` ack with reply code ``250``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailSubmissionGetDeliveryStatusLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises EmailSubmission/get's
    # ``deliveryStatus`` parse path (RFC 8621 §7 ¶8). Stalwart 0.15.5
    # populates the field with a rich ``DeliveryStatus`` map; Cyrus
    # 3.12.2 hardcodes the field to ``null``
    # (``imap/jmap_mail_submission.c:1200-1201``) so the success arm
    # exercises the client's ``Opt.none`` projection; James 3.9 has no
    # EmailSubmission/get and the entire extract surfaces as
    # ``metUnknownMethod``.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    let draftsId = resolveOrCreateDrafts(client, mailAccountId).expect(
        "resolveOrCreateDrafts[" & $target.kind & "]"
      )

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # --- Seed draft + submit --------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope = buildEnvelope("alice@example.com", "bob@example.com").expect(
        "buildEnvelope[" & $target.kind & "]"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-33",
        "Test message body for delivery-status read.", "draft33",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")

    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub33").expect("parseCreationId[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set[" & $target.kind & "]")
    let subSetExtract = resp3.get(subHandle)
    var submissionId: Id
    var createOk = false
    assertSuccessOrTypedError(target, subSetExtract, {metUnknownMethod}):
      let subSetResp = success
      subSetResp.createResults.withValue(subCid, outcome):
        if outcome.isOk:
          submissionId = outcome.unsafeValue.id
          createOk = true
      do:
        assertOn target, false, "EmailSubmission/set must report a create outcome"

    if not createOk:
      client.close()
      continue

    # --- Poll until usFinal, then fresh /get to read deliveryStatus -----
    let pollRes = pollSubmissionDelivery(client, submissionAccountId, submissionId)
    if pollRes.isErr:
      # poll uses /get internally; on Cyrus the poll might still settle
      # (deliveryStatus is null but undoStatus advances), but on James
      # the entire surface fails. Skip dependent assertions.
      client.close()
      continue
    let (b4, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp4 = client.send(b4).expect("send EmailSubmission/get[" & $target.kind & "]")
    captureIfRequested(client, "email-submission-get-delivery-status-" & $target.kind)
      .expect("captureIfRequested")
    let getExtract = resp4.get(getHandle)
    assertSuccessOrTypedError(target, getExtract, {metUnknownMethod}):
      let getResp = success
      # RFC 8621 §7 ¶8 makes submission retention permissive
      # ("SHOULD retain at least until delivered"). Cyrus 3.12.2's
      # fire-and-forget submissions evict on ``final``; Stalwart
      # 0.15.5 retains. Both behaviours are RFC-conformant.
      # The wire-shape parse is the universal client-library
      # contract; the rich ``deliveryStatus`` assertions below only
      # run when the server retained the record.
      if getResp.list.len > 0:
        assertOn target,
          getResp.list.len == 1,
          "EmailSubmission/get must return at most one entry (got " & $getResp.list.len &
            ")"
        let any = getResp.list[0]
        let finalOpt = any.asFinal()
        assertOn target,
          finalOpt.isSome,
          "polled submission resolved to usFinal; entity must project as final"
        let sub = finalOpt.unsafeGet

        # When ``deliveryStatus`` is ``Opt.some``, Stalwart populates
        # the rich DeliveryStatus map. When ``Opt.none``, Cyrus 3.12.2
        # has hardcoded the field to ``null``
        # (``imap/jmap_mail_submission.c:1200-1201``); the client
        # parses the wire ``null`` as ``Opt.none(DeliveryStatusMap)``
        # and the ``isSome == false`` is itself the universal contract
        # assertion.
        for dsMapValue in sub.deliveryStatus:
          let dsMap = (Table[RFC5321Mailbox, DeliveryStatus])(dsMapValue)
          let bobMailbox = parseRFC5321Mailbox("bob@example.com").expect(
              "parseRFC5321Mailbox bob[" & $target.kind & "]"
            )
          assertOn target,
            bobMailbox in dsMap,
            "deliveryStatus must carry an entry keyed by bob@example.com"
          let entry = dsMap[bobMailbox]
          assertOn target,
            entry.delivered.state == dsUnknown,
            "route.local queue does not generate a DSN; delivered state " &
              "must project as dsUnknown (got " & $entry.delivered.state &
              ", rawBacking=" & entry.delivered.rawBacking & ")"
          assertOn target,
            entry.smtpReply.replyCode == ReplyCode(250),
            "local-queue SMTP reply must carry code 250 (got " &
              $entry.smtpReply.replyCode & ")"
          assertOn target,
            entry.smtpReply.enhanced.isSome,
            "reply carries an RFC 3463 enhanced status code"
    client.close()
