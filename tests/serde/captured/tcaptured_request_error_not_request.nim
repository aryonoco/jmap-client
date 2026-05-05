# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured request-level rejection
## Stalwart returns when sent a top-level JSON array (a hard
## structural mismatch with the RFC 8620 §3.3 Request type)
## (``tests/testdata/captured/request-error-not-request-stalwart.json``).
##
## Stalwart 0.15.5 returns
## ``urn:ietf:params:jmap:error:notRequest`` here, RFC-conformant.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedRequestErrorNotRequest:
  forEachCapturedServer("request-error-not-request", j):
    let re = RequestError.fromJson(j).expect("RequestError.fromJson")
    doAssert re.rawType == "urn:ietf:params:jmap:error:notRequest",
      "Stalwart returns notRequest for top-level non-Request JSON; got " & re.rawType
    doAssert re.errorType == retNotRequest,
      "errorType must match parseRequestErrorType(rawType); got " & $re.errorType
    doAssert re.errorType == parseRequestErrorType(re.rawType),
      "errorType / rawType must be derived consistently"
    # ``status`` mandated by RFC 7807 §3.1; the specific 4xx code is
    # server-discretionary. ``detail`` is RFC 7807 §3.1 optional —
    # Stalwart and James populate it; Cyrus omits it for this
    # rejection. Both shapes are conformant.
    doAssert re.status.isSome,
      "RFC 7807 §3.1 mandates a status field on the problem-details shape"
    let statusCode = re.status.unsafeGet
    doAssert statusCode >= 400 and statusCode < 500,
      "notRequest must surface as a 4xx HTTP status; got " & $statusCode
    for d in re.detail:
      doAssert d.len > 0,
        "when detail is provided, it must be a non-empty human-readable string"
