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

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tCrossAccountEmailGetRejectionLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()

    # --- alice setup ----------------------------------------------------
    var aliceClient = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient alice")
    discard aliceClient.fetchSession().expect("fetchSession alice")

    # --- bob accountId discovery ----------------------------------------
    # Only bob's accountId is needed; close his client immediately to
    # avoid coupling the rejection probe to bob's session lifetime.
    var bobClient = initBobClient(cfg).expect("initBobClient")
    let bobSession = bobClient.fetchSession().expect("fetchSession bob")
    let bobMailAccountId =
      resolveMailAccountId(bobSession).expect("resolveMailAccountId bob")
    bobClient.close()

    # --- alice probes bob's accountId -----------------------------------
    let (b, getHandle) =
      addEmailGet(initRequestBuilder(), bobMailAccountId, ids = directIds(@[]))
    let resp = aliceClient.send(b).expect("send Email/get cross-account")
    captureIfRequested(aliceClient, "email-get-cross-account-rejected-stalwart").expect(
      "captureIfRequested"
    )

    let getResult = resp.get(getHandle)
    doAssert getResult.isErr,
      "RFC 8620 §3.6.2 — alice probing bob's accountId without sharing must " &
        "surface a method-level error"
    let methodErr = getResult.error
    doAssert methodErr.errorType in {metForbidden, metAccountNotFound},
      "RFC 8620 §3.6.2 admits both metForbidden and metAccountNotFound for cross-account " &
        "rejection; got " & $methodErr.errorType & " (rawType=" & methodErr.rawType & ")"
    aliceClient.close()
