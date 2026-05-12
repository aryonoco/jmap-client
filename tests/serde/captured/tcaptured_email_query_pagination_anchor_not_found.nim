# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` rejection
## when the supplied anchor is not found in the result set (RFC 8620
## §5.5,
## ``tests/testdata/captured/email-query-pagination-anchor-not-found-stalwart.json``).
## The single invocation carries the wire name ``"error"``; arguments
## parse as ``MethodError`` with ``errorType == metAnchorNotFound``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailQueryPaginationAnchorNotFound:
  let j = loadCapturedFixture("email-query-pagination-anchor-not-found-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive under the literal rawName 'error' (got " & inv.rawName &
      ")"
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType == metAnchorNotFound,
    "errorType must project as metAnchorNotFound (got " & $me.errorType & ", rawType=" &
      me.rawType & ")"
  doAssert me.rawType == "anchorNotFound", "rawType must round-trip the wire literal"
