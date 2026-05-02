# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test asserting alice→bob delivery genuinely deposits
## the message in bob's inbox. Phase F's six EmailSubmission tests pin
## the submitter-side wire shape (alice's ``EmailSubmission/get`` reaches
## ``undoStatus == final``) but do not assert the receiver-side post-
## condition. Two ``JmapClient`` instances coexist in this test (a
## campaign first); they are independent objects with separate keep-
## alive HTTP connections.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/json
import std/sets
import std/tables
import std/times

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailBobReceivesAliceDeliveryLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()

    # --- alice setup ----------------------------------------------------
    var aliceClient = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient alice")
    let aliceSession = aliceClient.fetchSession().expect("fetchSession alice")
    var aliceMailAccountId: AccountId
    aliceSession.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      aliceMailAccountId = v
    do:
      doAssert false, "alice's session must advertise a primary mail account"
    let aliceSubmissionAccountId = resolveSubmissionAccountId(aliceSession).expect(
        "resolveSubmissionAccountId alice"
      )
    let identityId = resolveOrCreateAliceIdentity(aliceClient, aliceSubmissionAccountId)
      .expect("resolveOrCreateAliceIdentity")
    let draftsId = resolveOrCreateDrafts(aliceClient, aliceMailAccountId).expect(
        "resolveOrCreateDrafts"
      )

    # --- alice seed-and-submit ------------------------------------------
    # Per-run unique subject prevents cross-talk with prior delivered
    # messages still resident in bob's inbox between runs.
    let subject = "phase-g step-38 marker " & $epochTime()
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")
    let draftId = seedDraftEmail(
        aliceClient, aliceMailAccountId, draftsId, aliceAddr, bobAddr, subject,
        "Phase G Step 38 — verifying receiver-side delivery.", "draft38",
      )
      .expect("seedDraftEmail")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub38").expect("parseCreationId")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), aliceSubmissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 = aliceClient.send(b3).expect("send EmailSubmission/set")
    let subSetResp = resp3.get(subHandle).expect("EmailSubmission/set extract")
    var submissionId: Id
    subSetResp.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"

    # --- alice poll-to-final --------------------------------------------
    discard pollSubmissionDelivery(aliceClient, aliceSubmissionAccountId, submissionId)
      .expect("pollSubmissionDelivery")

    # --- bob setup ------------------------------------------------------
    var bobClient = initBobClient(cfg).expect("initBobClient")
    let bobSession = bobClient.fetchSession().expect("fetchSession bob")
    var bobMailAccountId: AccountId
    bobSession.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      bobMailAccountId = v
    do:
      doAssert false, "bob's session must advertise a primary mail account"
    let bobInboxId =
      resolveInboxId(bobClient, bobMailAccountId).expect("resolveInboxId bob")

    # --- bob observe ----------------------------------------------------
    let bobEmailId = findEmailBySubjectInMailbox(
        bobClient, bobMailAccountId, bobInboxId, subject
      )
      .expect("findEmailBySubjectInMailbox")

    # --- bob full-fetch -------------------------------------------------
    let (b4, getHandle) = addEmailGet(
      initRequestBuilder(),
      bobMailAccountId,
      ids = directIds(@[bobEmailId]),
      properties = Opt.some(@["id", "subject", "from", "mailboxIds"]),
    )
    let resp4 = bobClient.send(b4).expect("send Email/get")
    captureIfRequested(bobClient, "bob-inbox-after-alice-delivery-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp4.get(getHandle).expect("Email/get extract")
    doAssert getResp.list.len == 1,
      "bob's Email/get must return exactly one entry for the delivered id (got " &
        $getResp.list.len & ")"
    let entity = getResp.list[0]

    let subjectNode = entity{"subject"}
    doAssert not subjectNode.isNil and subjectNode.kind == JString,
      "Email/get must include a string subject"
    doAssert subjectNode.getStr == subject,
      "delivered subject must match seeded subject (got " & subjectNode.getStr & ")"

    let fromNode = entity{"from"}
    doAssert not fromNode.isNil and fromNode.kind == JArray and fromNode.len > 0,
      "Email/get must include a non-empty from array"
    let fromAddrNode = fromNode[0]{"email"}
    doAssert not fromAddrNode.isNil and fromAddrNode.kind == JString,
      "from[0] must include a string email"
    doAssert fromAddrNode.getStr == "alice@example.com",
      "delivered from[0].email must be alice@example.com (got " & fromAddrNode.getStr &
        ")"

    let mbIdsNode = entity{"mailboxIds"}
    doAssert not mbIdsNode.isNil, "Email/get must include mailboxIds"
    let mbIdsTyped = MailboxIdSet.fromJson(mbIdsNode).expect("parse MailboxIdSet")
    let mbIds = HashSet[Id](mbIdsTyped)
    doAssert bobInboxId in mbIds,
      "delivered email must reside in bob's inbox mailbox (mailboxIds=" & $mbIds & ")"

    aliceClient.close()
    bobClient.close()
