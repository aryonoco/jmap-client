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
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
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
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    var vacAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:vacationresponse", v):
      vacAccountId = v
    do:
      assertOn target,
        false, "session must advertise a primary vacationresponse account"

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
    let resp1 =
      client.send(b1).expect("send VacationResponse/set[" & $target.kind & "]")
    let setResp1 =
      resp1.get(setHandle1).expect("VacationResponse/set extract[" & $target.kind & "]")
    var updateOk = false
    setResp1.updateResults.withValue(singletonId, outcome):
      assertOn target,
        outcome.isOk, "VacationResponse/set update must succeed for singleton"
      updateOk = true
    do:
      assertOn target,
        false, "VacationResponse/set must report an outcome for singleton"
    assertOn target, updateOk

    # --- Step 2: re-read and verify the three fields round-tripped ------
    let (b2, getHandle2) = addVacationResponseGet(initRequestBuilder(), vacAccountId)
    let resp2 =
      client.send(b2).expect("send VacationResponse/get post-set[" & $target.kind & "]")
    captureIfRequested(client, "vacation-get-singleton-" & $target.kind).expect(
      "captureIfRequested"
    )
    let getResp2 = resp2.get(getHandle2).expect(
        "VacationResponse/get post-set extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp2.list.len == 1,
      "VacationResponse/get must still return exactly one singleton entry"
    let vr = VacationResponse.fromJson(getResp2.list[0]).expect(
        "parse updated VacationResponse"
      )
    assertOn target, vr.isEnabled, "isEnabled must round-trip as true after set"
    assertOn target,
      vr.subject.isSome and vr.subject.get() == "phase-b step-9 OOO",
      "subject must round-trip as set"
    assertOn target,
      vr.textBody.isSome and vr.textBody.get() == "Out until next sprint.",
      "textBody must round-trip as set"

    # --- Cleanup: disable the auto-reply --------------------------------
    let cleanupSet = initVacationResponseUpdateSet(@[setIsEnabled(false)]).expect(
        "initVacationResponseUpdateSet cleanup"
      )
    let (b3, _) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = cleanupSet)
    discard
      client.send(b3).expect("send VacationResponse/set cleanup[" & $target.kind & "]")
    client.close()
