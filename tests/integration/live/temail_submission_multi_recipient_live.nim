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
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailSubmissionMultiRecipientLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")
    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )
    let draftsId =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")

    # --- Seed multi-recipient draft -------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let draftId = seedMultiRecipientDraft(
        client,
        mailAccountId,
        draftsId,
        aliceAddr,
        @[bobAddr, aliceAddr],
        "phase-g step-40",
        "Phase G Step 40 — multi-recipient submission.",
        "draft40",
      )
      .expect("seedMultiRecipientDraft")

    # --- Build multi-rcpt envelope and submit ---------------------------
    let envelope = buildEnvelopeMulti(
        "alice@example.com", @["bob@example.com", "alice@example.com"]
      )
      .expect("buildEnvelopeMulti")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub40").expect("parseCreationId")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set")
    let subSetResp = resp3.get(subHandle).expect("EmailSubmission/set extract")
    var submissionId: Id
    subSetResp.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"

    # --- Poll until usFinal then re-fetch with capture ------------------
    discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
        "pollSubmissionDelivery"
      )
    let (b4, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp4 = client.send(b4).expect("send EmailSubmission/get")
    captureIfRequested(client, "email-submission-multi-recipient-delivery-stalwart")
      .expect("captureIfRequested")
    let getResp = resp4.get(getHandle).expect("EmailSubmission/get extract")
    doAssert getResp.list.len == 1,
      "EmailSubmission/get must return exactly one entry (got " & $getResp.list.len & ")"
    let any =
      AnyEmailSubmission.fromJson(getResp.list[0]).expect("AnyEmailSubmission.fromJson")
    let finalOpt = any.asFinal()
    doAssert finalOpt.isSome,
      "polled submission resolved to usFinal; entity must project as final"
    let sub = finalOpt.unsafeGet

    doAssert sub.deliveryStatus.isSome,
      "Stalwart must populate deliveryStatus once delivery is final"
    let dsMap = (Table[RFC5321Mailbox, DeliveryStatus])(sub.deliveryStatus.unsafeGet)
    doAssert dsMap.len == 2,
      "two-recipient envelope (bob, alice-self) must produce two deliveryStatus " &
        "entries (got " & $dsMap.len & ")"

    let bobMailbox =
      parseRFC5321Mailbox("bob@example.com").expect("parseRFC5321Mailbox bob")
    let aliceMailbox =
      parseRFC5321Mailbox("alice@example.com").expect("parseRFC5321Mailbox alice")
    doAssert bobMailbox in dsMap,
      "deliveryStatus must carry an entry keyed by bob@example.com"
    doAssert aliceMailbox in dsMap,
      "deliveryStatus must carry an entry keyed by alice@example.com"

    let bobEntry = dsMap[bobMailbox]
    doAssert bobEntry.smtpReply.replyCode == ReplyCode(250),
      "bob's local-queue SMTP reply must carry code 250 (got " &
        $bobEntry.smtpReply.replyCode & ")"
    let aliceEntry = dsMap[aliceMailbox]
    doAssert aliceEntry.smtpReply.replyCode == ReplyCode(250),
      "alice-self's local-queue SMTP reply must carry code 250 (got " &
        $aliceEntry.smtpReply.replyCode & ")"
    client.close()
