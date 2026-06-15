# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test pinning Stalwart's cross-account ``Email/get``
## rejection wire shape. Alice's session, with alice's credential,
## issues ``Email/get`` against bob's accountId. RFC 8620 §3.6.2 admits
## either ``accountNotFound`` or ``forbidden``; Stalwart 0.15.5
## empirically chooses ``forbidden`` — the account exists but alice
## has no read permission on it without sharing/ACL.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tCrossAccountEmailGetRejectionLive:
  forEachLiveTarget(target):
    # --- alice setup ----------------------------------------------------
    let (aliceClient, aliceRecorder) = initRecordingClient(target)
    discard
      aliceClient.fetchSession().expect("fetchSession alice[" & $target.kind & "]")

    # --- bob accountId discovery ----------------------------------------
    # Only bob's accountId is needed; the bob client itself is dropped
    # to ARC at end of testCase scope (no explicit close needed).
    let bobClient = initBobClient(target).expect("initBobClient[" & $target.kind & "]")
    let bobSession =
      bobClient.fetchSession().expect("fetchSession bob[" & $target.kind & "]")
    let bobMailAccountId = resolveMailAccountId(bobSession).expect(
        "resolveMailAccountId bob[" & $target.kind & "]"
      )

    # --- alice probes bob's accountId -----------------------------------
    let (b, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()), bobMailAccountId, ids = directIds(@[])
    )
    let resp = aliceClient.send(b.freeze()).expect(
        "send Email/get cross-account[" & $target.kind & "]"
      )
    captureIfRequested(
      aliceRecorder.lastResponseBody, "email-get-cross-account-rejected-" & $target.kind
    )
      .expect("captureIfRequested")

    let getResult = resp.get(getHandle)
    # A cross-account probe surfaces a server method error, which is now
    # DATA on the dispatch ok rail (``MethodOutcome.mokMethodError``): the
    # dispatch itself succeeded, the server merely answered the call with an
    # error object. Only a dispatch fault (``jeMisuse`` / ``jeProtocol``)
    # rides the rail, and that would be a programming or protocol bug here.
    assertOn target,
      getResult.isOk,
      "dispatch must succeed on the rail; a cross-account rejection is a " &
        "server method error carried as data, not a dispatch fault"
    let outcome = getResult.unsafeValue
    assertOn target,
      outcome.kind == mokMethodError,
      "RFC 8620 §3.6.2 — alice probing bob's accountId without sharing must " &
        "surface a method-level error"
    let methodErr = outcome.error
    assertOn target,
      methodErr.kind in {metForbidden, metAccountNotFound},
      "RFC 8620 §3.6.2 admits both metForbidden and metAccountNotFound for cross-account " &
        "rejection; got " & $methodErr.kind & " (rawType=" & methodErr.rawType & ")"
