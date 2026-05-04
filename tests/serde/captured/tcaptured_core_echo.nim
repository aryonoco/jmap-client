# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Core/echo`` fixture
## (``tests/testdata/captured/core-echo-stalwart.json``).
##
## Smoke for the replay harness: parse the response envelope, locate
## the single ``Core/echo`` invocation, assert the echoed args round-
## trip and the envelope carries a non-empty ``sessionState``.

{.push raises: [].}

import std/json

import jmap_client
import ./mloader

block tcapturedCoreEcho:
  forEachCapturedServer("core-echo", j):
    let respRes = envelope.Response.fromJson(j)
    doAssert respRes.isOk, "envelope.Response.fromJson must succeed"
    let resp = respRes.unsafeValue
    doAssert resp.methodResponses.len == 1,
      "expected one Core/echo invocation (got " & $resp.methodResponses.len & ")"
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Core/echo",
      "method name must be Core/echo (got " & inv.rawName & ")"
    doAssert string(inv.methodCallId) == "c0",
      "callId must be c0 (got " & string(inv.methodCallId) & ")"
    doAssert ($resp.sessionState).len > 0, "sessionState must be non-empty"
    doAssert inv.arguments.kind == JObject, "arguments must be a JObject"
    doAssert inv.arguments{"hello"}.getBool(false), "echo args carry hello=true"
    doAssert inv.arguments{"n"}.getInt() == 42, "echo args carry n=42"
    doAssert inv.arguments{"msg"}.getStr() == "phase-1 step-3",
      "echo args carry msg=phase-1 step-3"
