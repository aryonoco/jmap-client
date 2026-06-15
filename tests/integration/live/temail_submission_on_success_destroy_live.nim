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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tEmailSubmissionOnSuccessDestroyLive:
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

    # --- Seed draft -----------------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope = buildEnvelope("alice@example.com", "bob@example.com").expect(
        "buildEnvelope[" & $target.kind & "]"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-35",
        "Submission with onSuccessDestroyEmail.", "draft35",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")

    # --- Build onSuccessDestroyEmail + blueprint + compound submit -------
    let subCid =
      parseCreationId("sub35").expect("parseCreationId sub35[" & $target.kind & "]")
    # Reference the in-request submission via its creation id (RFC 8621
    # §7.5 ¶3 — ``"#" + creationId`` resolves against the sibling create
    # in the same /set call). James 3.9 supports only ``#cid`` references
    # for ``onSuccessDestroyEmail`` because James does not store
    # EmailSubmissions; the ``creationRef`` form is RFC-canonical and
    # works on both servers.
    let onDestroy = parseNonEmptyOnSuccessDestroyEmail(@[creationRef(subCid)]).expect(
        "parseNonEmptyOnSuccessDestroyEmail"
      )
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    # The Ok value is a tuple carrying the uncopyable ``RequestBuilder`` (A7d),
    # so it is moved out of the Result rather than copied via ``.expect``.
    var subRes = addEmailSubmissionAndEmailSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(subTbl),
      onSuccessDestroyEmail = Opt.some(onDestroy),
    )
    doAssert subRes.isOk, "addEmailSubmissionAndEmailSet destroy[" & $target.kind & "]"
    let (b3, handles) = move(subRes.value)
    let resp3 = client.send(b3.freeze()).expect(
        "send EmailSubmission/set+Email/set destroy[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-submission-on-success-destroy-" & $target.kind
    )
      .expect("captureIfRequested")
    let pair = resp3.getBoth(handles).expect(
        "EmailSubmission/set+Email/set destroy dispatch[" & $target.kind & "]"
      )
    # Cat-B: Cyrus 3.12.2 rejects ``onSuccessDestroyEmail`` with
    # ``invalidArguments``. Stalwart and James implement the
    # compound submit-and-destroy. The success arm verifies the
    # round-trip; the error arm verifies the typed-error projection.
    # A server method error rides ``pair.primary`` as data
    # (``mokMethodError``); a rail ``JmapError`` from ``getBoth`` would
    # be a cross-builder ``jeMisuse`` programming bug, unwrapped fatally
    # by the ``.expect`` above.
    var submissionId: Id
    var compoundOk = false
    case pair.primary.kind
    of mokMethodError:
      let methodErr = pair.primary.error
      assertOn target,
        methodErr.kind in {metInvalidArguments, metUnknownMethod},
        "compound EmailSubmission/set + onSuccessDestroyEmail must surface " &
          "metInvalidArguments or metUnknownMethod when unimplemented (got " &
          methodErr.rawType & ")"
      continue
    of mokValue:
      let primaryResp = pair.primary.value
      primaryResp.createResults.withValue(subCid, outcome):
        if outcome.isOk:
          submissionId = outcome.unsafeValue.id
          compoundOk = true
      do:
        assertOn target, false, "EmailSubmission/set must report a create outcome"
      # §5.4: the implicit Email/set is emitted only on the submission's
      # success, so it is present (some) here on the primary mokValue arm.
      let implicitOutcome = pair.implicit.valueOr:
        assertOn target,
          false, "implicit Email/set destroy must be present on a successful submission"
        continue
      assertOn target,
        implicitOutcome.kind == mokValue,
        "implicit Email/set destroy must return a value, not a method error"
      let implicitResp = implicitOutcome.value
      implicitResp.destroyResults.withValue(draftId, outcome):
        assertOn target,
          outcome.isOk,
          "implicit Email/set destroy must succeed: " & outcome.error.rawType
      do:
        assertOn target,
          false, "implicit Email/set must report a destroy outcome for draftId"
    if not compoundOk:
      continue

    # --- Verification leg: divergent observation surface --------------
    case target.kind
    of ltkStalwart:
      # Discards the polled ``Opt[EmailSubmission[usFinal]]`` — the
      # caller only needs the SMTP-queue-drain barrier this helper
      # blocks on.
      discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
          "pollSubmissionDelivery[stalwart]"
        )
    of ltkJames, ltkCyrus:
      # James has no ``EmailSubmission/get``; Cyrus's ``deliveryStatus``
      # is hardcoded null. Both verify delivery via inbox arrival on
      # bob. ``onSuccessDestroyEmail`` is processed synchronously per
      # RFC 8621 §7.5 ¶3, so the draft destroy is already observable
      # via Email/get at this point.
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
          subject = "phase-f step-35",
          budgetMs = budget,
        )
        .expect("pollEmailDeliveryToInbox bob[" & $target.kind & "]")

    # --- Read-back: Email/get must surface the draft as notFound ---------
    let (b4, emailGetHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()), mailAccountId, ids = directIds(@[draftId])
    )
    let resp4 = client.send(b4.freeze()).expect(
        "send Email/get post-destroy[" & $target.kind & "]"
      )
    let getResp = resp4.get(emailGetHandle).expectValue(
        "Email/get post-destroy extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp.list.len == 0,
      "after onSuccessDestroyEmail, Email/get must return no entries (got " &
        $getResp.list.len & ")"
    assertOn target,
      draftId in getResp.notFound,
      "after onSuccessDestroyEmail, Email/get must surface draftId in notFound"
