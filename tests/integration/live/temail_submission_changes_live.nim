# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``EmailSubmission/changes`` and
## ``EmailSubmission/queryChanges`` (RFC 8621 §7.2 / §7.4) against
## Stalwart. Capstone for Phase F: closes the read-side delta surface
## of the EmailSubmission entity by capturing baselines, submitting
## two new submissions, then issuing changes (happy + sad legs in one
## request) and queryChanges (with ``calculateTotal``).
##
## Three Requests, single send each:
##   1. **Baselines** -- one EmailSubmission/get + one
##      EmailSubmission/query (with calculateTotal). No fixture
##      capture; the values are local-only inputs to the deltas.
##   2. **Changes happy + sad** -- two EmailSubmission/changes
##      invocations sharing one builder: sinceState=baselineState
##      (happy) and sinceState=JmapState("phase-f-bogus-state")
##      (sad). Captured as ``email-submission-changes-stalwart``.
##   3. **QueryChanges** -- one EmailSubmission/queryChanges with
##      sinceQueryState=baselineQueryState. Captured as
##      ``email-submission-query-changes-stalwart``.
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

block tEmailSubmissionChangesLive:
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
    let (b0, identGetHandle) = addIdentityGet(initRequestBuilder(), submissionAccountId)
    let resp0 = client.send(b0).expect("send Identity/get")
    let identGetResp = resp0.get(identGetHandle).expect("Identity/get extract")
    var aliceIdentityId = Opt.none(Id)
    for node in identGetResp.list:
      let ident = Identity.fromJson(node).expect("parse Identity")
      if ident.email == "alice@example.com":
        aliceIdentityId = Opt.some(ident.id)
    if aliceIdentityId.isNone:
      let createIdent = parseIdentityCreate(email = "alice@example.com", name = "Alice")
        .expect("parseIdentityCreate")
      let identCid = parseCreationId("seedAliceF36").expect("parseCreationId")
      var identTbl = initTable[CreationId, IdentityCreate]()
      identTbl[identCid] = createIdent
      let (bIs, identSetHandle) = addIdentitySet(
        initRequestBuilder(), submissionAccountId, create = Opt.some(identTbl)
      )
      let respIs = client.send(bIs).expect("send Identity/set seed")
      let identSetResp = respIs.get(identSetHandle).expect("Identity/set seed extract")
      identSetResp.createResults.withValue(identCid, outcome):
        doAssert outcome.isOk,
          "Identity/set seed must succeed: " & outcome.error.rawType
        aliceIdentityId = Opt.some(outcome.unsafeValue.id)
      do:
        doAssert false, "Identity/set seed must report an outcome"
    doAssert aliceIdentityId.isSome
    let identityId = aliceIdentityId.unsafeGet

    # --- Request 1: baselines (no fixture capture) -----------------------
    let (b1, baseGetHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[])
    )
    let (b1b, baseQueryHandle) = addEmailSubmissionQuery(
      b1, submissionAccountId, queryParams = QueryParams(calculateTotal: true)
    )
    let resp1 = client.send(b1b).expect("send baseline EmailSubmission/get+query")
    let baseGetResp = resp1.get(baseGetHandle).expect("baseline get extract")
    let baseQueryResp = resp1.get(baseQueryHandle).expect("baseline query extract")
    let baselineState = baseGetResp.state
    let baselineQueryState = baseQueryResp.queryState
    doAssert baseQueryResp.total.isSome,
      "baseline query must surface total when calculateTotal=true"
    let baselineTotal = baseQueryResp.total.unsafeGet

    # --- Two seed-and-submit interludes ----------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")

    proc submitOne(subject, label, draftLabel: string): Id =
      let draftId = seedDraftEmail(
          client, mailAccountId, draftsId, aliceAddr, bobAddr, subject,
          "Phase F Step 36 capstone seed.", draftLabel,
        )
        .expect("seedDraftEmail " & label)
      let blueprint = parseEmailSubmissionBlueprint(
          identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
        )
        .expect("parseEmailSubmissionBlueprint " & label)
      let cid = parseCreationId(label).expect("parseCreationId " & label)
      var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
      subTbl[cid] = blueprint
      let (b, setHandle) = addEmailSubmissionSet(
        initRequestBuilder(), submissionAccountId, create = Opt.some(subTbl)
      )
      let resp = client.send(b).expect("send EmailSubmission/set " & label)
      let setResp = resp.get(setHandle).expect("EmailSubmission/set extract " & label)
      var submissionId = Id("")
      var subOk = false
      setResp.createResults.withValue(cid, outcome):
        doAssert outcome.isOk,
          "EmailSubmission/set " & label & " must succeed: " & outcome.error.rawType
        submissionId = outcome.unsafeValue.id
        subOk = true
      do:
        doAssert false, "EmailSubmission/set " & label & " must report an outcome"
      doAssert subOk
      discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
          "pollSubmissionDelivery " & label
        )
      submissionId

    let subId1 = submitOne("phase-f step-36 a", "subA", "draft36A")
    let subId2 = submitOne("phase-f step-36 b", "subB", "draft36B")

    # --- Request 2: EmailSubmission/changes — happy + sad combined ------
    let (b2, okHandle) = addEmailSubmissionChanges(
      initRequestBuilder(), submissionAccountId, sinceState = baselineState
    )
    let (b2b, badHandle) = addEmailSubmissionChanges(
      b2, submissionAccountId, sinceState = JmapState("phase-f-bogus-state")
    )
    let resp2 = client.send(b2b).expect("send EmailSubmission/changes happy+sad")
    captureIfRequested(client, "email-submission-changes-stalwart").expect(
      "captureIfRequested changes"
    )
    let cr = resp2.get(okHandle).expect("EmailSubmission/changes happy extract")
    doAssert string(cr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    doAssert cr.created.len == 2,
      "two seeds must surface as two created entries (got " & $cr.created.len & ")"
    doAssert subId1 in cr.created, "subId1 must appear in created"
    doAssert subId2 in cr.created, "subId2 must appear in created"
    doAssert cr.updated.len == 0, "no updates issued — updated must be empty"
    doAssert cr.destroyed.len == 0, "no destroys issued — destroyed must be empty"

    let badRes = resp2.get(badHandle)
    doAssert badRes.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = badRes.error
    doAssert methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"

    # --- Request 3: EmailSubmission/queryChanges -------------------------
    let (b3, qcHandle) = addEmailSubmissionQueryChanges(
      initRequestBuilder(),
      submissionAccountId,
      sinceQueryState = baselineQueryState,
      calculateTotal = true,
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/queryChanges")
    captureIfRequested(client, "email-submission-query-changes-stalwart").expect(
      "captureIfRequested queryChanges"
    )
    let qcr = resp3.get(qcHandle).expect("EmailSubmission/queryChanges extract")
    doAssert string(qcr.oldQueryState) == string(baselineQueryState),
      "oldQueryState must echo the supplied baseline"
    doAssert string(qcr.newQueryState) != string(baselineQueryState),
      "newQueryState must differ after two fresh submissions"
    doAssert qcr.total.isSome,
      "queryChanges must surface total when calculateTotal=true"
    doAssert int64(qcr.total.unsafeGet) == int64(baselineTotal) + 2,
      "total must advance by exactly two (got " & $qcr.total.unsafeGet & ", baseline=" &
        $baselineTotal & ")"
    doAssert qcr.added.len == 2,
      "exactly two AddedItems expected (got " & $qcr.added.len & ")"
    client.close()
