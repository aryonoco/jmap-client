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
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailSubmissionGetDeliveryStatusLive:
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

    let draftsId =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")

    # --- Resolve alice's Identity, create on miss -----------------------
    let (b1, identGetHandle) = addIdentityGet(initRequestBuilder(), submissionAccountId)
    let resp1 = client.send(b1).expect("send Identity/get")
    let identGetResp = resp1.get(identGetHandle).expect("Identity/get extract")
    var aliceIdentityId = Opt.none(Id)
    for node in identGetResp.list:
      let ident = Identity.fromJson(node).expect("parse Identity")
      if ident.email == "alice@example.com":
        aliceIdentityId = Opt.some(ident.id)
    if aliceIdentityId.isNone:
      let createIdent = parseIdentityCreate(email = "alice@example.com", name = "Alice")
        .expect("parseIdentityCreate")
      let identCid = parseCreationId("seedAliceF33").expect("parseCreationId")
      var identTbl = initTable[CreationId, IdentityCreate]()
      identTbl[identCid] = createIdent
      let (b2, identSetHandle) = addIdentitySet(
        initRequestBuilder(), submissionAccountId, create = Opt.some(identTbl)
      )
      let resp2 = client.send(b2).expect("send Identity/set seed")
      let identSetResp = resp2.get(identSetHandle).expect("Identity/set seed extract")
      identSetResp.createResults.withValue(identCid, outcome):
        doAssert outcome.isOk,
          "Identity/set seed must succeed: " & outcome.error.rawType
        aliceIdentityId = Opt.some(outcome.unsafeValue.id)
      do:
        doAssert false, "Identity/set seed must report an outcome"
    doAssert aliceIdentityId.isSome
    let identityId = aliceIdentityId.unsafeGet

    # --- Seed draft + submit --------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-33",
        "Test message body for delivery-status read.", "draft33",
      )
      .expect("seedDraftEmail")

    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub33").expect("parseCreationId")
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

    # --- Poll until usFinal, then fresh /get to read deliveryStatus -----
    discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
        "pollSubmissionDelivery"
      )
    let (b4, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp4 = client.send(b4).expect("send EmailSubmission/get")
    captureIfRequested(client, "email-submission-get-delivery-status-stalwart").expect(
      "captureIfRequested"
    )
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
    let bobMailbox =
      parseRFC5321Mailbox("bob@example.com").expect("parseRFC5321Mailbox bob")
    doAssert bobMailbox in dsMap,
      "deliveryStatus must carry an entry keyed by bob@example.com"
    let entry = dsMap[bobMailbox]
    doAssert entry.delivered.state == dsUnknown,
      "Stalwart's route.local queue does not generate a DSN; delivered " &
        "state must project as dsUnknown (got " & $entry.delivered.state &
        ", rawBacking=" & entry.delivered.rawBacking & ")"
    doAssert entry.smtpReply.replyCode == ReplyCode(250),
      "Stalwart's local-queue SMTP reply must carry code 250 (got " &
        $entry.smtpReply.replyCode & ")"
    doAssert entry.smtpReply.enhanced.isSome,
      "Stalwart's reply carries an RFC 3463 enhanced status code"
    client.close()
