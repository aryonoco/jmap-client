# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured request-level rejection
## Stalwart returns when the request body exceeds ``maxSizeRequest``
## (``tests/testdata/captured/request-error-limit-stalwart.json``).
##
## Stalwart 0.15.5 returns ``urn:ietf:params:jmap:error:limit`` here
## per RFC 8620 §3.6.1, AND populates the ``limit`` field with
## ``"maxSizeRequest"`` per RFC 8620 §3.6.1's "A 'limit' property
## MUST also be present" guidance.  This fixture additionally
## exercises the library's optional ``limit`` field projection.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedRequestErrorLimit:
  let j = loadCapturedFixture("request-error-limit-stalwart")
  let re = RequestError.fromJson(j).expect("RequestError.fromJson")
  doAssert re.rawType == "urn:ietf:params:jmap:error:limit",
    "Stalwart returns limit URI for over-size request; got " & re.rawType
  doAssert re.errorType == retLimit,
    "errorType must match parseRequestErrorType(rawType); got " & $re.errorType
  doAssert re.errorType == parseRequestErrorType(re.rawType),
    "errorType / rawType must be derived consistently"
  doAssert re.status.isSome and re.status.unsafeGet == 400,
    "Stalwart pins the HTTP status field to 400"
  doAssert re.detail.isSome, "Stalwart populates the RFC 7807 detail field"
  doAssert re.limit.isSome and re.limit.unsafeGet == "maxSizeRequest",
    "Stalwart names the breached limit per RFC 8620 §3.6.1; got " & $re.limit
