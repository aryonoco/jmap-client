# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``unsupportedFilter``
## method-level rejection (``tests/testdata/captured/
## method-error-unsupported-filter-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"unsupportedFilter"``
## rawType when a query carries a synthetic filter property the server
## does not recognise; description echoes the offending property name.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMethodErrorUnsupportedFilter:
  let j = loadCapturedFixture("method-error-unsupported-filter-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive on the literal 'error' rawName, got " & inv.rawName
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.rawType == "unsupportedFilter",
    "Stalwart returns the canonical 'unsupportedFilter' rawType, got " & me.rawType
  doAssert me.errorType == metUnsupportedFilter,
    "errorType must project to metUnsupportedFilter, got " & $me.errorType
  doAssert me.errorType == parseMethodErrorType(me.rawType),
    "errorType / rawType must be derived consistently"
  doAssert me.description.isSome,
    "Stalwart populates the description with the offending filter property"
  doAssert me.description.unsafeGet == "phaseJSyntheticProperty",
    "description must echo the offending filter property"
