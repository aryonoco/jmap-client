# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``unknownMethod`` method-
## level rejection (``tests/testdata/captured/
## method-error-unknown-method-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"unknownMethod"`` rawType
## with a description echoing the offending method name.  Verifies
## (a) the ``error`` invocation routes through ``MethodError.fromJson``
## via the typed ``rawName`` projection, and (b) ``rawType`` /
## ``errorType`` / ``description`` / ``methodCallId`` round-trip with
## byte-strict fidelity.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedMethodErrorUnknownMethod:
  let j = loadCapturedFixture("method-error-unknown-method-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive on the literal 'error' rawName, got " & inv.rawName
  doAssert $inv.methodCallId == "c0",
    "Stalwart echoes the call id from the request, got " & $inv.methodCallId
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.rawType == "unknownMethod",
    "Stalwart returns the canonical 'unknownMethod' rawType, got " & me.rawType
  doAssert me.errorType == metUnknownMethod,
    "errorType must project to metUnknownMethod, got " & $me.errorType
  doAssert me.errorType == parseMethodErrorType(me.rawType),
    "errorType / rawType must be derived consistently"
  doAssert me.description.isSome and me.description.unsafeGet == "Mailbox/snorgleflarp",
    "Stalwart echoes the offending method name in the description"
