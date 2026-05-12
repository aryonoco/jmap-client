# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for multi-recipient EmailSubmission delivery
## (RFC 8621 §7.4 ¶8). Phase F's six EmailSubmission fixtures all carry
## single-recipient ``deliveryStatus`` payloads; this step exercises a
## two-recipient envelope (``alice → [bob, alice-self]``) so the
## ``DeliveryStatusMap`` deserialises with two entries — one per
## RFC 8621 §7.4 ¶8 recipient.
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

block tEmailSubmissionMultiRecipientLive:
  forEachLiveTarget(target):
    # Cat-D (Phase L §0): asymmetric verification of the same client-
    # side outcome (the multi-recipient submission delivered) using
    # whichever observation surface the target makes available.
    # Stalwart 0.15.5 populates ``deliveryStatus`` with a per-
    # recipient map → polled via EmailSubmission/get. Cyrus 3.12.2
    # hardcodes ``deliveryStatus`` to ``null``
    # (`imap/jmap_mail_submission.c:1200-1201`); James 3.9 has no
    # EmailSubmission/get. Both verify delivery via per-recipient
    # inbox arrival.
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
    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )
    let draftsId = resolveOrCreateDrafts(client, mailAccountId).expect(
        "resolveOrCreateDrafts[" & $target.kind & "]"
      )

    # --- Seed multi-recipient draft -------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    const subjectKey = "phase-g-step-40-multirecipient"
    let draftId = seedMultiRecipientDraft(
        client,
        mailAccountId,
        draftsId,
        aliceAddr,
        @[bobAddr, aliceAddr],
        subjectKey,
        "Phase G Step 40 — multi-recipient submission.",
        "draft40",
      )
      .expect("seedMultiRecipientDraft[" & $target.kind & "]")

    # --- Build multi-rcpt envelope and submit ---------------------------
    let envelope = buildEnvelopeMulti(
        "alice@example.com", @["bob@example.com", "alice@example.com"]
      )
      .expect("buildEnvelopeMulti[" & $target.kind & "]")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub40").expect("parseCreationId[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(subTbl),
    )
    let resp3 =
      client.send(b3.freeze()).expect("send EmailSubmission/set[" & $target.kind & "]")
    let subSetResp =
      resp3.get(subHandle).expect("EmailSubmission/set extract[" & $target.kind & "]")
    var submissionId: Id
    subSetResp.createResults.withValue(subCid, outcome):
      assertOn target,
        outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      assertOn target, false, "EmailSubmission/set must report a create outcome"

    # --- Cat-D verification — per-target observation surface ------------
    case target.kind
    of ltkStalwart:
      # Stalwart populates ``deliveryStatus`` with a rich per-recipient
      # map; verification reads the map.
      # Discards the polled ``Opt[EmailSubmission[usFinal]]`` — the
      # caller only needs the SMTP-queue-drain barrier on Stalwart.
      discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
          "pollSubmissionDelivery"
        )
      let (b4, getHandle) = addEmailSubmissionGet(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        ids = directIds(@[submissionId]),
      )
      let resp4 = client.send(b4.freeze()).expect(
          "send EmailSubmission/get[" & $target.kind & "]"
        )
      captureIfRequested(
        client, "email-submission-multi-recipient-delivery-" & $target.kind
      )
        .expect("captureIfRequested[" & $target.kind & "]")
      let getResp =
        resp4.get(getHandle).expect("EmailSubmission/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 1,
        "EmailSubmission/get must return exactly one entry (got " & $getResp.list.len &
          ")"
      let any = getResp.list[0]
      let finalOpt = any.asFinal()
      assertOn target,
        finalOpt.isSome,
        "polled submission resolved to usFinal; entity must project as final"
      let sub = finalOpt.unsafeGet
      assertOn target,
        sub.deliveryStatus.isSome,
        "Stalwart must populate deliveryStatus once delivery is final"
      let dsMap = (Table[RFC5321Mailbox, DeliveryStatus])(sub.deliveryStatus.unsafeGet)
      assertOn target,
        dsMap.len == 2,
        "two-recipient envelope (bob, alice-self) must produce two deliveryStatus " &
          "entries (got " & $dsMap.len & ")"
      let bobMailbox = parseRFC5321Mailbox("bob@example.com").expect(
          "parseRFC5321Mailbox bob[" & $target.kind & "]"
        )
      let aliceMailbox = parseRFC5321Mailbox("alice@example.com").expect(
          "parseRFC5321Mailbox alice[" & $target.kind & "]"
        )
      assertOn target,
        bobMailbox in dsMap,
        "deliveryStatus must carry an entry keyed by bob@example.com"
      assertOn target,
        aliceMailbox in dsMap,
        "deliveryStatus must carry an entry keyed by alice@example.com"
      let bobEntry = dsMap[bobMailbox]
      assertOn target,
        bobEntry.smtpReply.replyCode == ReplyCode(250),
        "bob's local-queue SMTP reply must carry code 250 (got " &
          $bobEntry.smtpReply.replyCode & ")"
      let aliceEntry = dsMap[aliceMailbox]
      assertOn target,
        aliceEntry.smtpReply.replyCode == ReplyCode(250),
        "alice-self's local-queue SMTP reply must carry code 250 (got " &
          $aliceEntry.smtpReply.replyCode & ")"
    of ltkJames, ltkCyrus:
      # James and Cyrus expose no usable ``deliveryStatus``;
      # verify delivery via per-recipient inbox arrival on alice's
      # inbox (the alice-self leg). Bob's leg lands in bob's inbox
      # — observed indirectly by the SMTP queue draining (Stalwart
      # only) or by the JMAP-side ``undoStatus`` settling in
      # downstream tests. Per-target inbox-arrival budget for
      # arm64-QEMU: 30000ms on Cyrus under concurrent load.
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let budget = (if target.kind == ltkCyrus: 60000 else: 5000) * liveBudgetMul
      discard pollEmailDeliveryToInbox(
          client, mailAccountId, inbox, subjectKey, budgetMs = budget
        )
        .expect("pollEmailDeliveryToInbox alice-self[" & $target.kind & "]")
      captureIfRequested(
        client, "email-submission-multi-recipient-delivery-" & $target.kind
      )
        .expect("captureIfRequested[" & $target.kind & "]")
    client.close()
