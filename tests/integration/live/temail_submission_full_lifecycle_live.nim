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

testCase tEmailSubmissionFullLifecycleLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): full CRUD lifecycle exercises every
    # EmailSubmission/set arm. Stalwart 0.15.5 and Cyrus 3.12.2 implement
    # all arms; James 3.9 only parses ``create`` and stores no
    # submission records (``update``/``destroy``/``get`` surface as
    # typed errors). Each ``assertSuccessOrTypedError`` site exercises
    # the typed-error projection contract uniformly.
    let (client, recorder) = initRecordingClient(target)
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

    # --- Create — seed draft + submit with HOLDFOR=300 -------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-g step-42",
        "Phase G Step 42 — full CRUD lifecycle.", "draft42",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")
    let holdSeconds = parseHoldForSeconds(parseUnsignedInt(300).get()).expect(
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
      parseCreationId("sub42").expect("parseCreationId[" & $target.kind & "]")
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
      continue

    # --- Poll until usPending --------------------------------------------
    let pendingRes = pollSubmissionPending(client, submissionAccountId, submissionId)
    if pendingRes.isErr:
      continue
    let pendingSubmission = pendingRes.unsafeValue

    # --- Update — cancel via Update arm ----------------------------------
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
      continue

    # --- Destroy — destroy via Destroy arm -------------------------------
    let (b5, destroyHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      destroy = directIds(@[submissionId]),
    )
    let resp5 = client.send(b5.freeze()).expect(
        "send EmailSubmission/set destroy[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-submission-destroy-canceled-" & $target.kind
    )
      .expect("captureIfRequested")
    let destroyExtract = resp5.get(destroyHandle)
    var destroyOk = false
    assertSuccessOrTypedError(
      target, destroyExtract, {metInvalidArguments, metUnknownMethod}
    ):
      let destroyResp = success
      destroyResp.destroyResults.withValue(submissionId, outcome):
        if outcome.isOk:
          destroyOk = true
      do:
        assertOn target,
          false, "EmailSubmission/set destroy must report an outcome for submissionId"

    if not destroyOk:
      continue

    # --- Re-fetch and confirm absence ------------------------------------
    let (b6, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      ids = directIds(@[submissionId]),
    )
    let resp6 = client.send(b6.freeze()).expect(
        "send EmailSubmission/get post-destroy[" & $target.kind & "]"
      )
    let getExtract = resp6.get(getHandle)
    assertSuccessOrTypedError(target, getExtract, {metUnknownMethod}):
      let getResp = success
      assertOn target,
        getResp.list.len == 0,
        "destroyed submission must not surface in EmailSubmission/get list (got " &
          $getResp.list.len & " entries)"
      assertOn target,
        submissionId in getResp.notFound,
        "destroyed submissionId must surface in EmailSubmission/get notFound"
