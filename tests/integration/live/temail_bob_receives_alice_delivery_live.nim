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
  forEachLiveTarget(target):
    # --- alice setup ----------------------------------------------------
    var aliceClient = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient alice[" & $target.kind & "]")
    let aliceSession =
      aliceClient.fetchSession().expect("fetchSession alice[" & $target.kind & "]")
    let aliceMailAccountId = resolveMailAccountId(aliceSession).expect(
        "resolveMailAccountId alice[" & $target.kind & "]"
      )
    let aliceSubmissionAccountId = resolveSubmissionAccountId(aliceSession).expect(
        "resolveSubmissionAccountId alice"
      )
    let identityId = resolveOrCreateAliceIdentity(aliceClient, aliceSubmissionAccountId)
      .expect("resolveOrCreateAliceIdentity[" & $target.kind & "]")
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
    let envelope = buildEnvelope("alice@example.com", "bob@example.com").expect(
        "buildEnvelope[" & $target.kind & "]"
      )
    let draftId = seedDraftEmail(
        aliceClient, aliceMailAccountId, draftsId, aliceAddr, bobAddr, subject,
        "Phase G Step 38 — verifying receiver-side delivery.", "draft38",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub38").expect("parseCreationId[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), aliceSubmissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 =
      aliceClient.send(b3).expect("send EmailSubmission/set[" & $target.kind & "]")
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

    # --- alice poll-to-final --------------------------------------------
    # James 3.9 has no ``EmailSubmission/get``, so polling for
    # ``usFinal`` is Stalwart-only. James's local-domain auto-routing
    # delivers loopback within 50–500 ms; the bob-side
    # ``findEmailBySubjectInMailbox`` below absorbs the asynchrony for
    # both targets, so the alice-side poll is a Stalwart-only
    # observation that the SMTP queue drained before bob queries.
    case target.kind
    of ltkStalwart:
      discard pollSubmissionDelivery(
          aliceClient, aliceSubmissionAccountId, submissionId
        )
        .expect("pollSubmissionDelivery[stalwart]")
    of ltkJames:
      discard

    # --- bob setup ------------------------------------------------------
    var bobClient = initBobClient(target).expect("initBobClient[" & $target.kind & "]")
    let bobSession =
      bobClient.fetchSession().expect("fetchSession bob[" & $target.kind & "]")
    let bobMailAccountId = resolveMailAccountId(bobSession).expect(
        "resolveMailAccountId bob[" & $target.kind & "]"
      )
    let bobInboxId = resolveInboxId(bobClient, bobMailAccountId).expect(
        "resolveInboxId bob[" & $target.kind & "]"
      )

    # --- bob observe ----------------------------------------------------
    let bobEmailId = findEmailBySubjectInMailbox(
        bobClient, bobMailAccountId, bobInboxId, subject
      )
      .expect("findEmailBySubjectInMailbox[" & $target.kind & "]")

    # --- bob full-fetch -------------------------------------------------
    let (b4, getHandle) = addEmailGet(
      initRequestBuilder(),
      bobMailAccountId,
      ids = directIds(@[bobEmailId]),
      properties = Opt.some(@["id", "subject", "from", "mailboxIds"]),
    )
    let resp4 = bobClient.send(b4).expect("send Email/get[" & $target.kind & "]")
    captureIfRequested(bobClient, "bob-inbox-after-alice-delivery-" & $target.kind)
      .expect("captureIfRequested")
    let getResp = resp4.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
    assertOn target,
      getResp.list.len == 1,
      "bob's Email/get must return exactly one entry for the delivered id (got " &
        $getResp.list.len & ")"
    let email =
      Email.fromJson(getResp.list[0]).expect("Email.fromJson[" & $target.kind & "]")

    assertOn target, email.subject.isSome, "Email/get must include a subject"
    assertOn target,
      email.subject.unsafeGet == subject,
      "delivered subject must match seeded subject (got " & email.subject.unsafeGet & ")"

    assertOn target,
      email.fromAddr.isSome and email.fromAddr.unsafeGet.len > 0,
      "Email/get must include a non-empty from list"
    assertOn target,
      email.fromAddr.unsafeGet[0].email == "alice@example.com",
      "delivered from[0].email must be alice@example.com (got " &
        email.fromAddr.unsafeGet[0].email & ")"

    assertOn target, email.mailboxIds.isSome, "Email/get must include mailboxIds"
    let mbIds = HashSet[Id](email.mailboxIds.unsafeGet)
    assertOn target,
      bobInboxId in mbIds,
      "delivered email must reside in bob's inbox mailbox (mailboxIds=" & $mbIds & ")"

    aliceClient.close()
    bobClient.close()
