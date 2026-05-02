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
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/identity as jidentity
import ./mcapture
import ./mconfig
import ./mlive

block tIdentitySetCrudLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")

    # --- Step 1: create -------------------------------------------------
    let createCid = parseCreationId("phaseFIdent").expect("parseCreationId")
    let createIdent = parseIdentityCreate(
        email = "alice@example.com", name = "phase-f step-31 initial"
      )
      .expect("parseIdentityCreate")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[createCid] = createIdent
    let (b1, createHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(createTbl)
    )
    let resp1 = client.send(b1).expect("send Identity/set create")
    let setResp1 = resp1.get(createHandle).expect("Identity/set create extract")
    var identityId: Id
    var createOk = false
    setResp1.createResults.withValue(createCid, outcome):
      doAssert outcome.isOk,
        "Identity/set create must succeed: " & outcome.error.rawType
      identityId = outcome.unsafeValue.id
      createOk = true
    do:
      doAssert false, "Identity/set must report a create result"
    doAssert createOk

    # --- Step 2: update — three arms in one IdentityUpdateSet -----------
    let replyAddr = parseEmailAddress("alice+reply@example.com", Opt.none(string))
      .expect("parseEmailAddress reply-to")
    let updateSet = initIdentityUpdateSet(
        @[
          jidentity.setName("phase-f step-31 renamed"),
          setReplyTo(Opt.some(@[replyAddr])),
          setTextSignature("phase-f sig"),
        ]
      )
      .expect("initIdentityUpdateSet")
    let updates = parseNonEmptyIdentityUpdates(@[(identityId, updateSet)]).expect(
        "parseNonEmptyIdentityUpdates"
      )
    let (b2, updateHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(updates)
    )
    let resp2 = client.send(b2).expect("send Identity/set update")
    captureIfRequested(client, "identity-set-update-stalwart").expect(
      "captureIfRequested"
    )
    let setResp2 = resp2.get(updateHandle).expect("Identity/set update extract")
    var updateOk = false
    setResp2.updateResults.withValue(identityId, outcome):
      doAssert outcome.isOk,
        "Identity/set update must succeed: " & outcome.error.rawType
      updateOk = true
    do:
      doAssert false, "Identity/set must report an update outcome"
    doAssert updateOk

    # --- Step 3: read-back via Identity/get -----------------------------
    let (b3, getHandle) = addIdentityGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[identityId])
    )
    let resp3 = client.send(b3).expect("send Identity/get")
    let getResp = resp3.get(getHandle).expect("Identity/get extract")
    doAssert getResp.list.len == 1,
      "Identity/get must return exactly one entry for the updated id (got " &
        $getResp.list.len & ")"
    let updated = Identity.fromJson(getResp.list[0]).expect("parse Identity")
    doAssert updated.name == "phase-f step-31 renamed",
      "name must reflect the setName update (got " & updated.name & ")"
    doAssert updated.replyTo.isSome, "replyTo must be present after setReplyTo"
    let replyList = updated.replyTo.unsafeGet
    doAssert replyList.len == 1,
      "replyTo must carry exactly one address (got " & $replyList.len & ")"
    doAssert replyList[0].email == "alice+reply@example.com",
      "replyTo[0].email must round-trip the supplied address"
    doAssert updated.textSignature == "phase-f sig",
      "textSignature must reflect the setTextSignature update"

    # --- Step 4: destroy ------------------------------------------------
    let (b4, destroyHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, destroy = directIds(@[identityId])
    )
    let resp4 = client.send(b4).expect("send Identity/set destroy")
    let setResp4 = resp4.get(destroyHandle).expect("Identity/set destroy extract")
    var destroyOk = false
    setResp4.destroyResults.withValue(identityId, outcome):
      doAssert outcome.isOk,
        "Identity/set destroy must succeed: " & outcome.error.rawType
      destroyOk = true
    do:
      doAssert false, "Identity/set must report a destroy outcome"
    doAssert destroyOk
    client.close()
