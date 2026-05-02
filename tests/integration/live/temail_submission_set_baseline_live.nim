# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for EmailSubmission/set baseline create
## (RFC 8621 §7.5) against Stalwart. First wire test of the simple
## ``addEmailSubmissionSet`` builder — no compound onSuccessUpdate /
## onSuccessDestroy extras (Steps 34/35 cover those). The phantom-
## narrowed return value of ``pollSubmissionDelivery`` proves end-to-
## end delivery: Stalwart received the JMAP submit, dispatched the
## message via ``route.local`` to bob's mailbox, and the JMAP
## EmailSubmission entity reached ``undoStatus == final``.
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

block tEmailSubmissionSetBaselineLive:
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
      let identCid = parseCreationId("seedAliceF32").expect("parseCreationId")
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

    # --- Build envelope + seed a real draft -----------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-32",
        "Test message body.", "draft32",
      )
      .expect("seedDraftEmail")

    # --- EmailSubmission/set — single create, simple overload ----------
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub32").expect("parseCreationId sub32")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set")
    captureIfRequested(client, "email-submission-set-baseline-stalwart").expect(
      "captureIfRequested"
    )
    let subSetResp = resp3.get(subHandle).expect("EmailSubmission/set extract")
    var submissionId: Id
    var subOk = false
    subSetResp.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
      subOk = true
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"
    doAssert subOk

    # --- Poll until delivery resolves -----------------------------------
    let final = pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
        "pollSubmissionDelivery"
      )
    doAssert string(final.id) == string(submissionId),
      "polled submission id must match the created id"
    client.close()
