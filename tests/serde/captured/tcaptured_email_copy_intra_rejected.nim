# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/copy`` rejection
## response when ``fromAccountId == accountId`` (RFC 8620 §5.4,
## ``tests/testdata/captured/email-copy-intra-rejected-stalwart.json``).
## The single invocation carries the wire name ``"error"``; arguments
## parse as ``MethodError`` with ``errorType == metInvalidArguments``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailCopyIntraRejected:
  let j = loadCapturedFixture("email-copy-intra-rejected-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive under the literal rawName 'error' (got " & inv.rawName &
      ")"
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType == metInvalidArguments,
    "errorType must project as metInvalidArguments (got " & $me.errorType & ", rawType=" &
      me.rawType & ")"
  doAssert me.rawType == "invalidArguments", "rawType must round-trip the wire literal"
  doAssert me.description.isSome,
    "Stalwart includes a description on the same-account rejection"
