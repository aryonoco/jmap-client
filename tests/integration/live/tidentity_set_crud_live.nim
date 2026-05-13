# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for full Identity/set CRUD against Stalwart.
## Phase A Step 5 covered create-only (``tidentity_get_live``); Phase F
## Step 31 closes the boundary by exercising create + update + get +
## destroy in one block. The update leg drives three IdentityUpdate
## arms — ``setName``, ``setReplyTo``, ``setTextSignature`` — packed
## into a single IdentityUpdateSet so the toJson cascade emits one
## merged PatchObject, then read-back via ``Identity/get`` validates
## that every arm landed on the wire round-trip.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/internal/mail/identity as jidentity
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tIdentitySetCrudLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): Stalwart 0.15.5 and James 3.9 implement the
    # full Identity/set surface. Cyrus 3.12.2 omits Identity/set
    # entirely (``imap/jmap_mail.c:122-123``: "Possibly to be
    # implemented") and returns ``metUnknownMethod``. Each Identity/
    # set extract uses ``assertSuccessOrTypedError``; dependent steps
    # skip when an upstream extract surfaces a typed error.
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    # --- Step 1: create -------------------------------------------------
    let createCid =
      parseCreationId("phaseFIdent").expect("parseCreationId[" & $target.kind & "]")
    let createIdent = parseIdentityCreate(
        email = "alice@example.com", name = "phase-f step-31 initial"
      )
      .expect("parseIdentityCreate[" & $target.kind & "]")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[createCid] = createIdent
    let (b1, createHandle) = addIdentitySet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(createTbl),
    )
    let resp1 =
      client.send(b1.freeze()).expect("send Identity/set create[" & $target.kind & "]")
    # Cyrus 3.12.2 returns metUnknownMethod for the entire Identity/set
    # surface (``imap/jmap_mail.c:122-123`` — "Possibly to be
    # implemented"). The test exits below before reaching the b2
    # update-response capture site, so capture b1 here for Cyrus only —
    # the unknownMethod wire shape feeds the captured-replay suite.
    # Stalwart and James capture b2's update-response at the existing
    # post-b2 site below.
    case target.kind
    of ltkCyrus:
      captureIfRequested(
        recorder.lastResponseBody, "identity-set-update-" & $target.kind
      )
        .expect("captureIfRequested cyrus pre-error")
    of ltkStalwart, ltkJames:
      discard
    let createExtract = resp1.get(createHandle)
    var identityId: Id
    var createOk = false
    assertSuccessOrTypedError(target, createExtract, {metUnknownMethod}):
      let setResp1 = success
      setResp1.createResults.withValue(createCid, outcome):
        if outcome.isOk:
          identityId = outcome.unsafeValue.id
          createOk = true
      do:
        assertOn target, false, "Identity/set must report a create result"

    if not createOk:
      continue

    # --- Step 2: update — three arms in one IdentityUpdateSet -----------
    let replyAddr = parseEmailAddress("alice+reply@example.com", Opt.none(string))
      .expect("parseEmailAddress reply-to[" & $target.kind & "]")
    let updateSet = initIdentityUpdateSet(
        @[
          jidentity.setName("phase-f step-31 renamed"),
          setReplyTo(Opt.some(@[replyAddr])),
          setTextSignature("phase-f sig"),
        ]
      )
      .expect("initIdentityUpdateSet[" & $target.kind & "]")
    let updates = parseNonEmptyIdentityUpdates(@[(identityId, updateSet)]).expect(
        "parseNonEmptyIdentityUpdates"
      )
    let (b2, updateHandle) = addIdentitySet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      update = Opt.some(updates),
    )
    let resp2 =
      client.send(b2.freeze()).expect("send Identity/set update[" & $target.kind & "]")
    captureIfRequested(recorder.lastResponseBody, "identity-set-update-" & $target.kind)
      .expect("captureIfRequested")
    let updateExtract = resp2.get(updateHandle)
    var updateOk = false
    assertSuccessOrTypedError(target, updateExtract, {metUnknownMethod}):
      let setResp2 = success
      setResp2.updateResults.withValue(identityId, outcome):
        if outcome.isOk:
          updateOk = true
      do:
        assertOn target, false, "Identity/set must report an update outcome"

    if updateOk:
      # --- Step 3: read-back via Identity/get ----------------------------
      let (b3, getHandle) = addIdentityGet(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        ids = directIds(@[identityId]),
      )
      let resp3 =
        client.send(b3.freeze()).expect("send Identity/get[" & $target.kind & "]")
      let getResp =
        resp3.get(getHandle).expect("Identity/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 1,
        "Identity/get must return exactly one entry for the updated id (got " &
          $getResp.list.len & ")"
      let updated = getResp.list[0]
      assertOn target,
        updated.name == "phase-f step-31 renamed",
        "name must reflect the setName update (got " & updated.name & ")"
      assertOn target,
        updated.replyTo.isSome, "replyTo must be present after setReplyTo"
      let replyList = updated.replyTo.unsafeGet
      assertOn target,
        replyList.len == 1,
        "replyTo must carry exactly one address (got " & $replyList.len & ")"
      assertOn target,
        replyList[0].email == "alice+reply@example.com",
        "replyTo[0].email must round-trip the supplied address"
      assertOn target,
        updated.textSignature == "phase-f sig",
        "textSignature must reflect the setTextSignature update"

    # --- Step 4: destroy ------------------------------------------------
    let (b4, destroyHandle) = addIdentitySet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      destroy = directIds(@[identityId]),
    )
    let resp4 =
      client.send(b4.freeze()).expect("send Identity/set destroy[" & $target.kind & "]")
    let destroyExtract = resp4.get(destroyHandle)
    assertSuccessOrTypedError(target, destroyExtract, {metUnknownMethod}):
      let setResp4 = success
      setResp4.destroyResults.withValue(identityId, outcome):
        assertOn target,
          outcome.isOk, "Identity/set destroy must succeed: " & outcome.error.rawType
      do:
        assertOn target, false, "Identity/set must report a destroy outcome"
