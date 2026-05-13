# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Core/echo (RFC 8620 §4) round-trip against
## every configured JMAP server. The server must echo arguments back
## unchanged and stamp the response envelope with a non-empty
## ``sessionState``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just jmap-up``. Body is guarded
## on ``loadLiveTestTargets().isOk`` (via ``forEachLiveTarget``) so the
## file joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/json

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tcoreEchoLive:
  forEachLiveTarget(target):
    let (client, recorder) = initRecordingClient(target)
    let args = %*{"hello": true, "n": 42, "msg": "phase-1 step-3"}
    let (b1, echoHandle) = initRequestBuilder(makeBuilderId()).addEcho(args)
    let resp = client.send(b1.freeze()).expect("send[" & $target.kind & "]")
    captureIfRequested(recorder.lastResponseBody, "core-echo-" & $target.kind).expect(
      "captureIfRequested[" & $target.kind & "]"
    )
    let echoExtract = proc(
        n: JsonNode
    ): Result[JsonNode, SerdeViolation] {.noSideEffect, raises: [].} =
      ok(n)
    let echoArgs = resp.get(echoHandle, echoExtract).expect(
        "Core/echo extract[" & $target.kind & "]"
      )
    assertOn target, echoArgs == args, "echo args must round-trip unchanged"
    assertOn target, ($resp.sessionState).len > 0, "response must carry sessionState"
