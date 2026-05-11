# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured compound ``Email/copy`` +
## implicit ``Email/set destroy`` rejection when ``fromAccountId ==
## accountId`` (RFC 8620 §5.4 + RFC 8621 §4.7,
## ``tests/testdata/captured/email-copy-destroy-original-rejected-stalwart.json``).
## The compound is rejected at the method level before any implicit
## destroy; the response carries a single ``"error"`` invocation.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailCopyDestroyOriginalRejected:
  let j = loadCapturedFixture("email-copy-destroy-original-rejected-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1,
    "compound copy+destroy rejection emits a single method-level error invocation " &
      "(got " & $resp.methodResponses.len & ")"
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive under the literal rawName 'error' (got " & inv.rawName &
      ")"
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType == metInvalidArguments,
    "errorType must project as metInvalidArguments (got " & $me.errorType & ", rawType=" &
      me.rawType & ")"
  doAssert me.rawType == "invalidArguments", "rawType must round-trip the wire literal"
