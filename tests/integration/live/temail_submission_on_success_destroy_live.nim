# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for the compound EmailSubmission/set with
## ``onSuccessDestroyEmail`` (RFC 8621 §7.5 ¶3) against Stalwart.
## Parallel arm to Step 34: instead of patching the draft, the
## server destroys it on a successful submission. The wire-shape
## difference from Step 34 is structural — ``onSuccessDestroyEmail``
## is an array of ``IdOrCreationRef``, not a map keyed by them.
## Read-back via ``Email/get`` confirms the draft is gone:
## ``getResp.list`` is empty and ``draftId`` lands in
## ``getResp.notFound``.
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

block tEmailSubmissionOnSuccessDestroyLive:
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

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # --- Seed draft -----------------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-35",
        "Submission with onSuccessDestroyEmail.", "draft35",
      )
      .expect("seedDraftEmail")

    # --- Build onSuccessDestroyEmail + blueprint + compound submit -------
    let onDestroy = parseNonEmptyOnSuccessDestroyEmail(@[directRef(draftId)]).expect(
        "parseNonEmptyOnSuccessDestroyEmail"
      )
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub35").expect("parseCreationId sub35")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, handles) = addEmailSubmissionAndEmailSet(
      initRequestBuilder(),
      submissionAccountId,
      create = Opt.some(subTbl),
      onSuccessDestroyEmail = Opt.some(onDestroy),
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set+Email/set destroy")
    captureIfRequested(client, "email-submission-on-success-destroy-stalwart").expect(
      "captureIfRequested"
    )
    let pair = resp3.getBoth(handles).expect("getBoth(EmailSubmissionHandles)")
    var submissionId: Id
    pair.primary.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"
    pair.implicit.destroyResults.withValue(draftId, outcome):
      doAssert outcome.isOk,
        "implicit Email/set destroy must succeed: " & outcome.error.rawType
    do:
      doAssert false, "implicit Email/set must report a destroy outcome for draftId"

    # --- Poll until usFinal -----------------------------------------------
    discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
        "pollSubmissionDelivery"
      )

    # --- Read-back: Email/get must surface the draft as notFound ---------
    let (b4, emailGetHandle) =
      addEmailGet(initRequestBuilder(), mailAccountId, ids = directIds(@[draftId]))
    let resp4 = client.send(b4).expect("send Email/get post-destroy")
    let getResp = resp4.get(emailGetHandle).expect("Email/get post-destroy extract")
    doAssert getResp.list.len == 0,
      "after onSuccessDestroyEmail, Email/get must return no entries (got " &
        $getResp.list.len & ")"
    doAssert draftId in getResp.notFound,
      "after onSuccessDestroyEmail, Email/get must surface draftId in notFound"
    client.close()
