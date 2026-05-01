# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Core/echo (RFC 8620 §4) round-trip against
## Stalwart. The server must echo arguments back unchanged and stamp the
## response envelope with a non-empty ``sessionState``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Project test idiom: ``block <name>:`` plus ``doAssert`` (see
## ``tests/integration/live/tsession_discovery.nim``).

import std/json

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig

block tcoreEchoLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let args = %*{"hello": true, "n": 42, "msg": "phase-1 step-3"}
    let (b1, echoHandle) = initRequestBuilder().addEcho(args)
    let resp = client.send(b1).expect("send")
    captureIfRequested(client, "core-echo-stalwart").expect("captureIfRequested")
    let echoExtract = proc(
        n: JsonNode
    ): Result[JsonNode, SerdeViolation] {.noSideEffect, raises: [].} =
      ok(n)
    let echoArgs = resp.get(echoHandle, echoExtract).expect("Core/echo extract")
    doAssert echoArgs == args, "echo args must round-trip unchanged"
    doAssert ($resp.sessionState).len > 0, "response must carry sessionState"
    client.close()
