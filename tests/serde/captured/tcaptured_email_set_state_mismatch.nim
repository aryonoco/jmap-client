# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/set`` stale-
## ``ifInState`` method-level error (RFC 8620 §3.6.2 / RFC 8621 §4.6,
## ``tests/testdata/captured/email-set-state-mismatch-stalwart.json``).
## The invocation carries the wire name ``"error"``; arguments parse
## as ``MethodError`` with ``errorType == metStateMismatch``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailSetStateMismatch:
  let j = loadCapturedFixture("email-set-state-mismatch-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive under the literal rawName 'error' (got " & inv.rawName &
      ")"
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType == metStateMismatch,
    "errorType must project as metStateMismatch (got " & $me.errorType & ", rawType=" &
      me.rawType & ")"
  doAssert me.rawType == "stateMismatch", "rawType must round-trip the wire literal"
  doAssert me.description.isSome, "Stalwart includes a description on stateMismatch"
