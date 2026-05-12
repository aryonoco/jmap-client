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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tEmailSubmissionCancelPendingLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises the ``EmailSubmission/set update``
    # cancel arm (RFC 8621 §7.5 ¶3). Stalwart 0.15.5 and Cyrus 3.12.2
    # implement update/destroy fully; James 3.9 only parses the create
    # arm and stores no submission records, so update returns
    # ``invalidArguments`` or ``unknownMethod`` typed errors. Each
    # ``assertSuccessOrTypedError`` site exercises the typed-error
    # projection contract uniformly.
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
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(subTbl),
    )
    let resp3 = client.send(b3.freeze()).expect(
        "send EmailSubmission/set HOLDFOR[" & $target.kind & "]"
      )
    let subSetExtract = resp3.get(subHandle)
    var submissionId: Id
    var createOk = false
    assertSuccessOrTypedError(
      target, subSetExtract, {metInvalidArguments, metUnknownMethod}
    ):
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

    # --- Poll until usPending --------------------------------------------
    let pendingRes = pollSubmissionPending(client, submissionAccountId, submissionId)
    if pendingRes.isErr:
      client.close()
      continue
    let pendingSubmission = pendingRes.unsafeValue

    # --- Issue cancelUpdate via /set update ------------------------------
    let cancel = cancelUpdate(pendingSubmission)
    let updates = parseNonEmptyEmailSubmissionUpdates(@[(submissionId, cancel)]).expect(
        "parseNonEmptyEmailSubmissionUpdates"
      )
    let (b4, updateHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      update = Opt.some(updates),
    )
    let resp4 = client.send(b4.freeze()).expect(
        "send EmailSubmission/set update cancel[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-submission-set-canceled-" & $target.kind).expect(
      "captureIfRequested"
    )
    let updateExtract = resp4.get(updateHandle)
    var updateOk = false
    assertSuccessOrTypedError(
      target, updateExtract, {metInvalidArguments, metUnknownMethod}
    ):
      let updateResp = success
      updateResp.updateResults.withValue(submissionId, outcome):
        if outcome.isOk:
          updateOk = true
      do:
        assertOn target,
          false, "EmailSubmission/set update must report an outcome for submissionId"

    if not updateOk:
      client.close()
      continue

    # --- Re-fetch and confirm canceled projection ------------------------
    let (b5, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      ids = directIds(@[submissionId]),
    )
    let resp5 = client.send(b5.freeze()).expect(
        "send EmailSubmission/get post-cancel[" & $target.kind & "]"
      )
    let getExtract = resp5.get(getHandle)
    assertSuccessOrTypedError(target, getExtract, {metUnknownMethod}):
      let getResp = success
      # Some servers (Cyrus 3.12.2) remove the submission record on
      # cancel; others (Stalwart) retain it with ``undoStatus =
      # canceled``. Both behaviours are RFC-conformant — RFC 8621
      # §7.5 ¶3 doesn't mandate retention. The wire-shape parse is
      # the universal client-library contract.
      if getResp.list.len > 0:
        assertOn target,
          getResp.list.len == 1,
          "EmailSubmission/get must return at most one entry post-cancel (got " &
            $getResp.list.len & ")"
        let any = getResp.list[0]
        assertOn target,
          any.asCanceled().isSome,
          "retained post-cancel submission must project as usCanceled (state=" &
            $any.state & ")"
    client.close()
