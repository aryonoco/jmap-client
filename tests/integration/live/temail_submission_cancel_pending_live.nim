# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``EmailSubmission/set update``: the cancel
## arm (RFC 8621 §7.5 ¶3 ``undoStatus → canceled``). Submits with
## RFC 4865 ``HOLDFOR=300`` so Stalwart holds the message in the
## FUTURERELEASE queue, observes ``usPending``, then issues the cancel
## update via the phantom-typed ``cancelUpdate(EmailSubmission[usPending])``
## smart constructor. Re-fetch confirms the canceled projection.
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

block tEmailSubmissionCancelPendingLive:
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

    # --- Seed draft + submit with HOLDFOR=300 ----------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-g step-41",
        "Phase G Step 41 — cancel pending submission.", "draft41",
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
    let subCid = parseCreationId("sub41").expect("parseCreationId")
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

    # --- Issue cancelUpdate via /set update ------------------------------
    let cancel = cancelUpdate(pendingSubmission)
    let updates = parseNonEmptyEmailSubmissionUpdates(@[(submissionId, cancel)]).expect(
        "parseNonEmptyEmailSubmissionUpdates"
      )
    let (b4, updateHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(updates)
    )
    let resp4 = client.send(b4).expect("send EmailSubmission/set update cancel")
    captureIfRequested(client, "email-submission-set-canceled-stalwart").expect(
      "captureIfRequested"
    )
    let updateResp =
      resp4.get(updateHandle).expect("EmailSubmission/set update extract")
    updateResp.updateResults.withValue(submissionId, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set update must succeed: " & outcome.error.rawType
    do:
      doAssert false,
        "EmailSubmission/set update must report an outcome for submissionId"

    # --- Re-fetch and confirm canceled projection ------------------------
    let (b5, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp5 = client.send(b5).expect("send EmailSubmission/get post-cancel")
    let getResp = resp5.get(getHandle).expect("EmailSubmission/get post-cancel extract")
    doAssert getResp.list.len == 1,
      "EmailSubmission/get must return exactly one entry post-cancel (got " &
        $getResp.list.len & ")"
    let any =
      AnyEmailSubmission.fromJson(getResp.list[0]).expect("AnyEmailSubmission.fromJson")
    doAssert any.asCanceled().isSome,
      "post-cancel submission must project as usCanceled (state=" & $any.state & ")"
    client.close()
