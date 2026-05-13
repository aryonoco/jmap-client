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
##      (happy) and sinceState=parseJmapState("phase-f-bogus-state").get()
##      (sad). Captured as ``email-submission-changes-stalwart``.
##   3. **QueryChanges** -- one EmailSubmission/queryChanges with
##      sinceQueryState=baselineQueryState. Captured as
##      ``email-submission-query-changes-stalwart``.
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

testCase tEmailSubmissionChangesLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises the EmailSubmission read-side delta
    # surface (``/get``, ``/query``, ``/changes``, ``/queryChanges``).
    # Stalwart 0.15.5 and Cyrus 3.12.2 implement all four; James 3.9
    # stores no submission records and the entire surface returns
    # typed errors. Each extract uses ``assertSuccessOrTypedError``;
    # dependent steps skip when an upstream extract surfaces a typed
    # error.
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

    # --- Request 1: baselines (no fixture capture) -----------------------
    let (b1, baseGetHandle) = addEmailSubmissionGet(
      initRequestBuilder(makeBuilderId()), submissionAccountId, ids = directIds(@[])
    )
    let (b1b, baseQueryHandle) = addEmailSubmissionQuery(
      b1, submissionAccountId, queryParams = QueryParams(calculateTotal: true)
    )
    let resp1 = client.send(b1b.freeze()).expect(
        "send baseline EmailSubmission/get+query[" & $target.kind & "]"
      )
    let baseGetExtract = resp1.get(baseGetHandle)
    let baseQueryExtract = resp1.get(baseQueryHandle)
    if baseGetExtract.isErr or baseQueryExtract.isErr:
      # Cat-B error arm — server lacks EmailSubmission/get or /query.
      # The typed-error projection has fired on the extract Result.
      # Under A6 the inner railway is ``GetError`` — extract via the
      # ``gekMethod`` arm; ``gekHandleMismatch`` is a programming bug
      # and should not be observable here.
      let baseGetErr =
        if baseGetExtract.isErr:
          let ge = baseGetExtract.unsafeError
          if ge.kind == gekMethod: ge.methodErr.errorType else: metUnknown
        else:
          metUnknown
      let baseQueryErr =
        if baseQueryExtract.isErr:
          let ge = baseQueryExtract.unsafeError
          if ge.kind == gekMethod: ge.methodErr.errorType else: metUnknown
        else:
          metUnknown
      assertOn target,
        baseGetErr in {metUnknownMethod, metUnknown} and
          baseQueryErr in {metUnknownMethod, metUnknown},
        "baseline EmailSubmission/get and /query must succeed or surface unknownMethod"
      continue
    let baseGetResp = baseGetExtract.unsafeValue
    let baseQueryResp = baseQueryExtract.unsafeValue
    let baselineState = baseGetResp.state
    let baselineQueryState = baseQueryResp.queryState
    assertOn target,
      baseQueryResp.total.isSome,
      "baseline query must surface total when calculateTotal=true"
    let baselineTotal = baseQueryResp.total.unsafeGet

    # --- Two seed-and-submit interludes ----------------------------------
    # Submissions use HOLDFOR=300 (RFC 4865) so the server retains them
    # in the ``pending`` state for 300 s instead of finalising
    # immediately. This makes ``EmailSubmission/changes`` enumerate
    # them on every server: Stalwart and Cyrus retain pending records
    # in their submission store, and Cyrus's fire-and-forget eviction
    # only fires after ``final``. The cleanup at the end of the test
    # cancels and destroys both submissions so they never deliver to
    # bob's inbox.
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let holdSeconds = parseHoldForSeconds(parseUnsignedInt(300).get()).expect(
        "parseHoldForSeconds[" & $target.kind & "]"
      )
    let envelope = buildEnvelopeWithHoldFor(
        "alice@example.com", "bob@example.com", holdSeconds
      )
      .expect("buildEnvelopeWithHoldFor[" & $target.kind & "]")

    proc submitOne(subject, label, draftLabel: string): Result[Id, GetError] =
      ## Closure: seed-and-submit one email per (subject, label) pair so
      ## the surrounding test body can drive a corpus of submissions
      ## without repeating the seed-to-final boilerplate. Returns the
      ## ``MethodError`` when ``EmailSubmission/set`` errors so callers
      ## can branch via ``assertSuccessOrTypedError``. Submissions are
      ## HOLDFOR-pended; cleanup cancels + destroys them.
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
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        create = Opt.some(subTbl),
      )
      let resp = client.send(b.freeze()).expect("send EmailSubmission/set " & label)
      let setExtract = resp.get(setHandle)
      if setExtract.isErr:
        return err(setExtract.unsafeError)
      let setResp = setExtract.unsafeValue
      var submissionId = parseIdFromServer("placeholder").get()
      var subOk = false
      setResp.createResults.withValue(cid, outcome):
        if outcome.isOk:
          submissionId = outcome.unsafeValue.id
          subOk = true
      do:
        discard
      if not subOk:
        return err(getErrorMethod(methodError("setError")))
      ok(submissionId)

    let sub1Res = submitOne("phase-f step-36 a", "subA", "draft36A")
    let sub2Res = submitOne("phase-f step-36 b", "subB", "draft36B")
    if sub1Res.isErr or sub2Res.isErr:
      # Cat-B error arm — the typed-error projection has fired.
      continue
    let subId1 = sub1Res.unsafeValue
    let subId2 = sub2Res.unsafeValue

    # --- Request 2: EmailSubmission/changes — happy + sad combined ------
    let (b2, okHandle) = addEmailSubmissionChanges(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      sinceState = baselineState,
    )
    let (b2b, badHandle) = addEmailSubmissionChanges(
      b2, submissionAccountId, sinceState = parseJmapState("phase-f-bogus-state").get()
    )
    let resp2 = client.send(b2b.freeze()).expect(
        "send EmailSubmission/changes happy+sad[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-submission-changes-" & $target.kind
    )
      .expect("captureIfRequested changes")
    let okExtract = resp2.get(okHandle)
    assertSuccessOrTypedError(
      target, okExtract, {metCannotCalculateChanges, metUnknownMethod}
    ):
      let cr = success
      assertOn target,
        $cr.oldState == $baselineState, "oldState must echo the supplied baseline"
      assertOn target,
        cr.created.len == 2,
        "two seeds must surface as two created entries (got " & $cr.created.len & ")"
      assertOn target, subId1 in cr.created, "subId1 must appear in created"
      assertOn target, subId2 in cr.created, "subId2 must appear in created"
      assertOn target,
        cr.updated.len == 0, "no updates issued — updated must be empty"
      assertOn target,
        cr.destroyed.len == 0, "no destroys issued — destroyed must be empty"

    let badRes = resp2.get(badHandle)
    assertOn target,
      badRes.isErr, "bogus sinceState must surface as a method-level error"
    let getErr = badRes.error
    doAssert getErr.kind == gekMethod, "expected gekMethod"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in
        {metCannotCalculateChanges, metInvalidArguments, metUnknownMethod},
      "method error must project as cannotCalculateChanges, invalidArguments, or " &
        "unknownMethod (got rawType=" & methodErr.rawType & ")"

    # --- Request 3: EmailSubmission/queryChanges -------------------------
    let (b3, qcHandle) = addEmailSubmissionQueryChanges(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      sinceQueryState = baselineQueryState,
      calculateTotal = true,
    )
    let resp3 = client.send(b3.freeze()).expect(
        "send EmailSubmission/queryChanges[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-submission-query-changes-" & $target.kind
    )
      .expect("captureIfRequested queryChanges")
    let qcExtract = resp3.get(qcHandle)
    assertSuccessOrTypedError(
      target, qcExtract, {metCannotCalculateChanges, metUnknownMethod}
    ):
      let qcr = success
      assertOn target,
        $qcr.oldQueryState == $baselineQueryState,
        "oldQueryState must echo the supplied baseline"
      assertOn target,
        $qcr.newQueryState != $baselineQueryState,
        "newQueryState must differ after two fresh submissions"
      assertOn target,
        qcr.total.isSome, "queryChanges must surface total when calculateTotal=true"
      assertOn target,
        qcr.total.unsafeGet.toInt64 == baselineTotal.toInt64 + 2,
        "total must advance by exactly two (got " & $qcr.total.unsafeGet & ", baseline=" &
          $baselineTotal & ")"
      assertOn target,
        qcr.added.len == 2,
        "exactly two AddedItems expected (got " & $qcr.added.len & ")"

    # --- Cleanup: destroy both pending submissions so they never
    # deliver to bob's inbox. Servers that retain pending records
    # honour the destroy; eviction-on-cancel servers (Cyrus) accept
    # it as a no-op.
    let (bDestroy, destroyHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      destroy = directIds(@[subId1, subId2]),
    )
    discard client.send(bDestroy.freeze())
    discard destroyHandle
