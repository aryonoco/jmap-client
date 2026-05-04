# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``unsupportedSort`` method-
## level rejection (``tests/testdata/captured/
## method-error-unsupported-sort-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"unsupportedSort"`` rawType
## when an ``Email/query`` request asks to sort on a property the
## server does not support for the given filter context.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedMethodErrorUnsupportedSort:
  let j = loadCapturedFixture("method-error-unsupported-sort-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive on the literal 'error' rawName, got " & inv.rawName
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.rawType == "unsupportedSort",
    "Stalwart returns the canonical 'unsupportedSort' rawType, got " & me.rawType
  doAssert me.errorType == metUnsupportedSort,
    "errorType must project to metUnsupportedSort, got " & $me.errorType
  doAssert me.errorType == parseMethodErrorType(me.rawType),
    "errorType / rawType must be derived consistently"
