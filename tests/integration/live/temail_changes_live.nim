# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/changes (RFC 8620 §5.2) against
## Stalwart. Two paths exercised in one test:
##
## 1. **Happy path** — capture a baseline ``state`` from an empty
##    Email/get, seed two new Emails via mlive helpers, then issue
##    Email/changes with ``sinceState=baseline``. Asserts both seeded
##    ids surface in ``created`` and that ``oldState`` matches the
##    baseline.
## 2. **Sad path** — issue Email/changes with a synthetic bogus
##    ``sinceState``. RFC 8620 §5.2 permits the server to respond with
##    either ``cannotCalculateChanges`` or ``invalidArguments``; the
##    test accepts both, asserting the projected ``MethodErrorType``
##    against that pair.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailChangesLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Capture baseline state via an empty Email/get -------------------
    let (b1, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[]),
      properties = Opt.some(@["id"]),
    )
    let resp1 =
      client.send(b1.freeze()).expect("send Email/get baseline[" & $target.kind & "]")
    let getResp =
      resp1.get(getHandle).expect("Email/get baseline extract[" & $target.kind & "]")
    let baselineState = getResp.state

    # --- Seed two emails via mlive --------------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let idA = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-11 a", "seedA"
      )
      .expect("seedSimpleEmail A[" & $target.kind & "]")
    let idB = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-11 b", "seedB"
      )
      .expect("seedSimpleEmail B[" & $target.kind & "]")

    # --- Happy path: Email/changes since baseline -----------------------
    let (b2, changesHandle) = addEmailChanges(
      initRequestBuilder(makeBuilderId()), mailAccountId, sinceState = baselineState
    )
    let resp2 =
      client.send(b2.freeze()).expect("send Email/changes happy[" & $target.kind & "]")
    let cr = resp2.get(changesHandle).expect(
        "Email/changes happy extract[" & $target.kind & "]"
      )
    assertOn target,
      string(cr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    assertOn target,
      cr.created.len == 2,
      "two seeds must surface as two created entries (got " & $cr.created.len & ")"
    assertOn target, cr.updated.len == 0, "no updates issued — updated must be empty"
    assertOn target,
      cr.destroyed.len == 0, "no destroys issued — destroyed must be empty"
    assertOn target, idA in cr.created, "seed A must appear in created"
    assertOn target, idB in cr.created, "seed B must appear in created"

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = JmapState("phase-b-bogus-state")
    let (b3, sadHandle) = addEmailChanges(
      initRequestBuilder(makeBuilderId()), mailAccountId, sinceState = bogusState
    )
    let resp3 =
      client.send(b3.freeze()).expect("send Email/changes bogus[" & $target.kind & "]")
    captureIfRequested(client, "email-changes-bogus-state-" & $target.kind).expect(
      "captureIfRequested"
    )
    let sadExtract = resp3.get(sadHandle)
    assertOn target,
      sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let getErr = sadExtract.error
    assertOn target,
      getErr.kind == gekMethod,
      "bogus sinceState must surface as gekMethod, not gekHandleMismatch"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"
    client.close()
