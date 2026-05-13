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
    assertOn target,
      getResult.isErr,
      "RFC 8620 §3.6.2 — alice probing bob's accountId without sharing must " &
        "surface a method-level error"
    # ``unsafeError`` bypasses ``withAssertOk`` — the ``$`` chain on the typed
    # ``GetResponse[Email]`` Ok value carries enough downstream side effects to
    # poison ``raiseResultDefect``'s inference. ``isErr`` is already asserted.
    # Under A6 the inner railway is ``GetError``; the ``gekMethod`` arm
    # wraps the original ``MethodError`` verbatim.
    let getErr = getResult.unsafeError
    assertOn target,
      getErr.kind == gekMethod,
      "cross-account rejection must surface as gekMethod, not gekHandleMismatch"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in {metForbidden, metAccountNotFound},
      "RFC 8620 §3.6.2 admits both metForbidden and metAccountNotFound for cross-account " &
        "rejection; got " & $methodErr.errorType & " (rawType=" & methodErr.rawType & ")"
