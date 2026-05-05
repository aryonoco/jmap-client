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
    # ``status`` mandated by RFC 7807 §3.1; the specific 4xx code is
    # server-discretionary. Stalwart, James, and Cyrus all use 400 for
    # this rejection — but the universal contract is the 4xx range.
    doAssert re.status.isSome,
      "RFC 7807 §3.1 mandates a status field on the problem-details shape"
    let statusCode = re.status.unsafeGet
    doAssert statusCode >= 400 and statusCode < 500,
      "request-layer limit rejection must surface as a 4xx HTTP status; got " &
        $statusCode
    doAssert re.limit.isSome and re.limit.unsafeGet == "maxCallsInRequest",
      "RFC 8620 §3.6.1: limit field must name the breached cap; got " & $re.limit
