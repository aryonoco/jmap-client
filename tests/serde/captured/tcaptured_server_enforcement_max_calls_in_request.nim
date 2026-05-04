# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured server-side enforcement
## of ``maxCallsInRequest`` (``tests/testdata/captured/
## server-enforcement-max-calls-in-request-stalwart.json``).
##
## Stalwart 0.15.5 returns the canonical
## ``urn:ietf:params:jmap:error:limit`` URI with
## ``limit: "maxCallsInRequest"`` populated — fully RFC-conformant.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedServerEnforcementMaxCallsInRequest:
  forEachCapturedServer("server-enforcement-max-calls-in-request", j):
    let re = RequestError.fromJson(j).expect("RequestError.fromJson")
    doAssert re.rawType == "urn:ietf:params:jmap:error:limit",
      "Stalwart returns canonical 'limit' URI; got " & re.rawType
    doAssert re.errorType == retLimit,
      "errorType must project to retLimit, got " & $re.errorType
    doAssert re.errorType == parseRequestErrorType(re.rawType),
      "errorType / rawType must be derived consistently"
    doAssert re.status.isSome and re.status.unsafeGet == 400,
      "Stalwart pins HTTP 400 on the request-layer limit rail"
    doAssert re.limit.isSome and re.limit.unsafeGet == "maxCallsInRequest",
      "Stalwart names the breached cap; got " & $re.limit
