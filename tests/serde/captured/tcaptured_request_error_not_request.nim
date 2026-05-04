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
    doAssert re.status.isSome and re.status.unsafeGet == 400,
      "Stalwart pins the HTTP status field to 400"
    doAssert re.detail.isSome, "Stalwart populates the RFC 7807 detail field"
