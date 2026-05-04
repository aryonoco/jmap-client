# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase G capstone: full EmailSubmission CRUD lifecycle. HOLDFOR
## submission → poll pending → cancel via Update arm → destroy via
## Destroy arm. Three sequential ``EmailSubmission/set`` invocations
## exercise all three RFC 8621 §7.5 arms (create, update, destroy) in
## one test. Mirrors the visibly-harder capstone discipline of
## A Step 7 / B Step 12 / C Step 18 / D Step 24 / E Step 30 / F Step 36.
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

block tEmailSubmissionFullLifecycleLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")
    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )
    let draftsId =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")

    # --- Create — seed draft + submit with HOLDFOR=300 -------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-g step-42",
        "Phase G Step 42 — full CRUD lifecycle.", "draft42",
      )
      .expect("seedDraftEmail")
    let holdSeconds =
      parseHoldForSeconds(UnsignedInt(300)).expect("parseHoldForSeconds")
    let envelope = buildEnvelopeWithHoldFor(
        "alice@example.com", "bob@example.com", holdSeconds
      )
      .expect("buildEnvelopeWithHoldFor")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub42").expect("parseCreationId")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set HOLDFOR")
    let subSetResp = resp3.get(subHandle).expect("EmailSubmission/set extract")
    var submissionId: Id
    subSetResp.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"

    # --- Poll until usPending --------------------------------------------
    let pendingSubmission = pollSubmissionPending(
        client, submissionAccountId, submissionId
      )
      .expect("pollSubmissionPending")

    # --- Update — cancel via Update arm ----------------------------------
    let cancel = cancelUpdate(pendingSubmission)
    let updates = parseNonEmptyEmailSubmissionUpdates(@[(submissionId, cancel)]).expect(
        "parseNonEmptyEmailSubmissionUpdates"
      )
    let (b4, updateHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(updates)
    )
    let resp4 = client.send(b4).expect("send EmailSubmission/set update cancel")
    let updateResp =
      resp4.get(updateHandle).expect("EmailSubmission/set update extract")
    updateResp.updateResults.withValue(submissionId, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set update must succeed: " & outcome.error.rawType
    do:
      doAssert false,
        "EmailSubmission/set update must report an outcome for submissionId"

    # --- Destroy — destroy via Destroy arm -------------------------------
    let (b5, destroyHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, destroy = directIds(@[submissionId])
    )
    let resp5 = client.send(b5).expect("send EmailSubmission/set destroy")
    captureIfRequested(client, "email-submission-destroy-canceled-stalwart").expect(
      "captureIfRequested"
    )
    let destroyResp =
      resp5.get(destroyHandle).expect("EmailSubmission/set destroy extract")
    destroyResp.destroyResults.withValue(submissionId, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set destroy must succeed: " & outcome.error.rawType
    do:
      doAssert false,
        "EmailSubmission/set destroy must report an outcome for submissionId"

    # --- Re-fetch and confirm absence ------------------------------------
    let (b6, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp6 = client.send(b6).expect("send EmailSubmission/get post-destroy")
    let getResp =
      resp6.get(getHandle).expect("EmailSubmission/get post-destroy extract")
    doAssert getResp.list.len == 0,
      "destroyed submission must not surface in EmailSubmission/get list (got " &
        $getResp.list.len & " entries)"
    doAssert submissionId in getResp.notFound,
      "destroyed submissionId must surface in EmailSubmission/get notFound"
    client.close()
