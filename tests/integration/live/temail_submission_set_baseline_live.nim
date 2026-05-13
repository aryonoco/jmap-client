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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tEmailSubmissionSetBaselineLive:
  forEachLiveTarget(target):
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    let draftsId = resolveOrCreateDrafts(client, mailAccountId).expect(
        "resolveOrCreateDrafts[" & $target.kind & "]"
      )

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # --- Build envelope + seed a real draft -----------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope = buildEnvelope("alice@example.com", "bob@example.com").expect(
        "buildEnvelope[" & $target.kind & "]"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-32",
        "Test message body.", "draft32",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")

    # --- EmailSubmission/set — single create, simple overload ----------
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub32").expect("parseCreationId sub32[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, subHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(subTbl),
    )
    let resp3 =
      client.send(b3.freeze()).expect("send EmailSubmission/set[" & $target.kind & "]")
    captureIfRequested(
      recorder.lastResponseBody, "email-submission-set-baseline-" & $target.kind
    )
      .expect("captureIfRequested")
    let subSetResp =
      resp3.get(subHandle).expect("EmailSubmission/set extract[" & $target.kind & "]")
    var submissionId: Id
    var subOk = false
    subSetResp.createResults.withValue(subCid, outcome):
      assertOn target,
        outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
      subOk = true
    do:
      assertOn target, false, "EmailSubmission/set must report a create outcome"
    assertOn target, subOk

    # --- Verification leg: divergent observation surface --------------
    case target.kind
    of ltkStalwart:
      # Stalwart implements EmailSubmission/get; poll the typed
      # phantom-narrowed ``EmailSubmission[usFinal]`` to confirm the
      # JMAP-side submission record reached ``final`` and the SMTP
      # queue drained.
      let pollRes = pollSubmissionDelivery(client, submissionAccountId, submissionId)
        .expect("pollSubmissionDelivery[stalwart]")
      # Stalwart retains submission records; the polled
      # ``EmailSubmission[usFinal]`` is observable. (Eviction-on-final
      # is the Cyrus path, which never reaches this branch.)
      assertOn target, pollRes.isSome, "Stalwart must retain the submission record"
      let final = pollRes.unsafeGet
      assertOn target,
        $final.id == $submissionId, "polled submission id must match the created id"
    of ltkJames, ltkCyrus:
      # James 3.9 has no ``EmailSubmission/get``; Cyrus 3.12.2's
      # ``deliveryStatus`` is hardcoded null
      # (``imap/jmap_mail_submission.c:1200-1201``). Both verify
      # delivery via inbox arrival on bob — local-domain auto-routing
      # delivers the message synchronously to bob's inbox. Per-target
      # arm64-QEMU budget guidance: Stalwart 5000 ms (not used here),
      # James 5000 ms, Cyrus 10000 ms.
      var bobClient =
        initBobClient(target).expect("initBobClient[" & $target.kind & "]")
      let bobSession =
        bobClient.fetchSession().expect("fetchSession bob[" & $target.kind & "]")
      let bobMailAccountId = resolveMailAccountId(bobSession).expect(
          "resolveMailAccountId bob[" & $target.kind & "]"
        )
      let bobInbox = resolveInboxId(bobClient, bobMailAccountId).expect(
          "resolveInboxId bob[" & $target.kind & "]"
        )
      let budget = (if target.kind == ltkCyrus: 60000 else: 5000) * liveBudgetMul
      discard pollEmailDeliveryToInbox(
          bobClient,
          bobMailAccountId,
          bobInbox,
          subject = "phase-f step-32",
          budgetMs = budget,
        )
        .expect("pollEmailDeliveryToInbox bob[" & $target.kind & "]")
