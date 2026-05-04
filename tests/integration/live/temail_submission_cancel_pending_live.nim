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
  forEachLiveTarget(target):
    # James 3.9 compatibility: skipped on James.
    # Reason: James 3.9 implements only ``EmailSubmission/set create`` — the ``update`` / ``destroy`` arms (RFC 8621 §7.5) are not parsed; submissions cannot be cancelled because no submission record is stored.
    # When James adds support, remove this guard.
    if target.kind == ltkJames:
      continue
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

    # --- Seed draft + submit with HOLDFOR=300 ----------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-g step-41",
        "Phase G Step 41 — cancel pending submission.", "draft41",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")
    let holdSeconds = parseHoldForSeconds(UnsignedInt(300)).expect(
        "parseHoldForSeconds[" & $target.kind & "]"
      )
    let envelope = buildEnvelopeWithHoldFor(
        "alice@example.com", "bob@example.com", holdSeconds
      )
      .expect("buildEnvelopeWithHoldFor[" & $target.kind & "]")
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub41").expect("parseCreationId[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 =
      client.send(b3).expect("send EmailSubmission/set HOLDFOR[" & $target.kind & "]")
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

    # --- Poll until usPending --------------------------------------------
    let pendingSubmission = pollSubmissionPending(
        client, submissionAccountId, submissionId
      )
      .expect("pollSubmissionPending[" & $target.kind & "]")

    # --- Issue cancelUpdate via /set update ------------------------------
    let cancel = cancelUpdate(pendingSubmission)
    let updates = parseNonEmptyEmailSubmissionUpdates(@[(submissionId, cancel)]).expect(
        "parseNonEmptyEmailSubmissionUpdates"
      )
    let (b4, updateHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(updates)
    )
    let resp4 = client.send(b4).expect(
        "send EmailSubmission/set update cancel[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-submission-set-canceled-" & $target.kind).expect(
      "captureIfRequested"
    )
    let updateResp = resp4.get(updateHandle).expect(
        "EmailSubmission/set update extract[" & $target.kind & "]"
      )
    updateResp.updateResults.withValue(submissionId, outcome):
      assertOn target,
        outcome.isOk,
        "EmailSubmission/set update must succeed: " & outcome.error.rawType
    do:
      assertOn target,
        false, "EmailSubmission/set update must report an outcome for submissionId"

    # --- Re-fetch and confirm canceled projection ------------------------
    let (b5, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp5 = client.send(b5).expect(
        "send EmailSubmission/get post-cancel[" & $target.kind & "]"
      )
    let getResp = resp5.get(getHandle).expect(
        "EmailSubmission/get post-cancel extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp.list.len == 1,
      "EmailSubmission/get must return exactly one entry post-cancel (got " &
        $getResp.list.len & ")"
    let any = AnyEmailSubmission.fromJson(getResp.list[0]).expect(
        "AnyEmailSubmission.fromJson[" & $target.kind & "]"
      )
    assertOn target,
      any.asCanceled().isSome,
      "post-cancel submission must project as usCanceled (state=" & $any.state & ")"
    client.close()
