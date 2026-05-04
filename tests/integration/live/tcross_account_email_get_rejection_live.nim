# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test pinning Stalwart's cross-account ``Email/get``
## rejection wire shape. Alice's session, with alice's bearer token,
## issues ``Email/get`` against bob's accountId. RFC 8620 §3.6.2 admits
## either ``accountNotFound`` or ``forbidden``; Stalwart 0.15.5
## empirically chooses ``forbidden`` — the account exists but alice
## has no read permission on it without sharing/ACL.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tCrossAccountEmailGetRejectionLive:
  forEachLiveTarget(target):
    # --- alice setup ----------------------------------------------------
    var aliceClient = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient alice[" & $target.kind & "]")
    discard
      aliceClient.fetchSession().expect("fetchSession alice[" & $target.kind & "]")

    # --- bob accountId discovery ----------------------------------------
    # Only bob's accountId is needed; close his client immediately to
    # avoid coupling the rejection probe to bob's session lifetime.
    var bobClient = initBobClient(target).expect("initBobClient[" & $target.kind & "]")
    let bobSession =
      bobClient.fetchSession().expect("fetchSession bob[" & $target.kind & "]")
    let bobMailAccountId = resolveMailAccountId(bobSession).expect(
        "resolveMailAccountId bob[" & $target.kind & "]"
      )
    bobClient.close()

    # --- alice probes bob's accountId -----------------------------------
    let (b, getHandle) =
      addEmailGet(initRequestBuilder(), bobMailAccountId, ids = directIds(@[]))
    let resp =
      aliceClient.send(b).expect("send Email/get cross-account[" & $target.kind & "]")
    captureIfRequested(aliceClient, "email-get-cross-account-rejected-" & $target.kind)
      .expect("captureIfRequested")

    let getResult = resp.get(getHandle)
    assertOn target,
      getResult.isErr,
      "RFC 8620 §3.6.2 — alice probing bob's accountId without sharing must " &
        "surface a method-level error"
    let methodErr = getResult.error
    assertOn target,
      methodErr.errorType in {metForbidden, metAccountNotFound},
      "RFC 8620 §3.6.2 admits both metForbidden and metAccountNotFound for cross-account " &
        "rejection; got " & $methodErr.errorType & " (rawType=" & methodErr.rawType & ")"
    aliceClient.close()
