# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for VacationResponse/get + VacationResponse/set
## (RFC 8621 §7) against Stalwart. The VacationResponse is a singleton
## (id == "singleton"); the test mutates three fields via
## VacationResponse/set, then re-reads via VacationResponse/get to
## assert the round-trip, then resets ``isEnabled`` to false to leave
## the server clean.
##
## Stalwart returns the singleton in ``notFound`` (not ``list``) until
## the first ``VacationResponse/set`` materialises it — divergent from
## RFC 8621 §7, which mandates that the server provide a default
## VacationResponse on every account. The test does not assert on the
## pre-set state to remain robust against this divergence.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## The VacationResponse account is advertised under
## ``urn:ietf:params:jmap:vacationresponse``; resolution mirrors the
## ``urn:ietf:params:jmap:mail`` lookup pattern from the other live
## tests.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tvacationGetSetLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): Stalwart 0.15.5 and James 3.9 implement
    # VacationResponse/{get,set}. Cyrus 3.12.2 ships the implementation
    # but the test image disables it via ``imapd.conf:
    # jmap_vacation: no``; the unregistered-method dispatch path
    # (``imap/jmap_api.c:713-714``) returns ``metUnknownMethod`` for
    # both methods. Each VacationResponse extract uses
    # ``assertSuccessOrTypedError``.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    var vacAccountId: AccountId
    var vacAccountFound = false
    session.primaryAccounts.withValue("urn:ietf:params:jmap:vacationresponse", v):
      vacAccountId = v
      vacAccountFound = true
    do:
      discard
    if not vacAccountFound:
      client.close()
      continue

    let singletonId =
      parseIdFromServer("singleton").expect("parseId singleton[" & $target.kind & "]")

    # --- Step 1: enable + set subject + set textBody ---------------------
    let updateSet = initVacationResponseUpdateSet(
        @[
          setIsEnabled(true),
          setSubject(Opt.some("phase-b step-9 OOO")),
          setTextBody(Opt.some("Out until next sprint.")),
        ]
      )
      .expect("initVacationResponseUpdateSet[" & $target.kind & "]")
    let (b1, setHandle1) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = updateSet)
    # Cyrus 3.12.2 ships VacationResponse but the test image disables
    # it via ``imapd.conf: jmap_vacation: no``; the URN is absent
    # from the session's ``capabilities`` map. ``addVacationResponseSet``
    # injects the URN into the request's ``using`` set, so Cyrus
    # rejects the request at the request level with
    # ``urn:ietf:params:jmap:error:unknownCapability``. The library
    # projects this as ``Err(ClientError(cekRequest, ...))`` — the
    # typed-error rail IS the universal client-library contract here,
    # so the test asserts the projection AND captures the wire shape
    # before skipping the dependent round-trip assertions. Capture is
    # Cyrus-only because Stalwart/James reach the existing post-b2
    # site below; an unconditional capture here would silently change
    # Stalwart/James fixture content from get-response to set-response
    # on any fresh-fixture re-capture.
    let resp1Result = client.send(b1)
    case target.kind
    of ltkCyrus:
      captureIfRequested(client, "vacation-get-singleton-" & $target.kind).expect(
        "captureIfRequested cyrus pre-error"
      )
    of ltkStalwart, ltkJames:
      discard
    if resp1Result.isErr:
      case target.kind
      of ltkCyrus:
        let err = resp1Result.error
        assertOn target,
          err.kind == cekRequest,
          "Cyrus must surface unknownCapability as a request-level error (got " &
            $err.kind & ")"
      of ltkStalwart, ltkJames:
        assertOn target, false, "VacationResponse/set must succeed on " & $target.kind
      client.close()
      continue
    let resp1 = resp1Result.unsafeValue
    let setExtract = resp1.get(setHandle1)
    var updateOk = false
    assertSuccessOrTypedError(target, setExtract, {metUnknownMethod}):
      let setResp1 = success
      setResp1.updateResults.withValue(singletonId, outcome):
        if outcome.isOk:
          updateOk = true
      do:
        assertOn target,
          false, "VacationResponse/set must report an outcome for singleton"

    # --- Step 2: re-read and verify the three fields round-tripped ------
    if updateOk:
      let (b2, getHandle2) = addVacationResponseGet(initRequestBuilder(), vacAccountId)
      let resp2 = client.send(b2).expect(
          "send VacationResponse/get post-set[" & $target.kind & "]"
        )
      captureIfRequested(client, "vacation-get-singleton-" & $target.kind).expect(
        "captureIfRequested"
      )
      let getExtract2 = resp2.get(getHandle2)
      assertSuccessOrTypedError(target, getExtract2, {metUnknownMethod}):
        let getResp2 = success
        assertOn target,
          getResp2.list.len == 1,
          "VacationResponse/get must still return exactly one singleton entry"
        let vr = getResp2.list[0]
        assertOn target, vr.isEnabled, "isEnabled must round-trip as true after set"
        assertOn target,
          vr.subject.isSome and vr.subject.get() == "phase-b step-9 OOO",
          "subject must round-trip as set"
        assertOn target,
          vr.textBody.isSome and vr.textBody.get() == "Out until next sprint.",
          "textBody must round-trip as set"

      # --- Cleanup: disable the auto-reply ------------------------------
      let cleanupSet = initVacationResponseUpdateSet(@[setIsEnabled(false)]).expect(
          "initVacationResponseUpdateSet cleanup"
        )
      let (b3, _) =
        addVacationResponseSet(initRequestBuilder(), vacAccountId, update = cleanupSet)
      discard client.send(b3).expect(
          "send VacationResponse/set cleanup[" & $target.kind & "]"
        )
    client.close()
