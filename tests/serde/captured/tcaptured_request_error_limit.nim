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
import ../../mtestblock

testCase tcapturedRequestErrorLimit:
  forEachCapturedServer("request-error-limit", j):
    let re = RequestError.fromJson(j).expect("RequestError.fromJson")
    doAssert re.rawType == "urn:ietf:params:jmap:error:limit",
      "Stalwart returns limit URI for over-size request; got " & re.rawType
    doAssert re.errorType == retLimit,
      "errorType must match parseRequestErrorType(rawType); got " & $re.errorType
    doAssert re.errorType == parseRequestErrorType(re.rawType),
      "errorType / rawType must be derived consistently"
    # RFC 7807 §3.1 mandates ``status`` reflects the HTTP status, but
    # the specific 4xx code is server-discretionary. Stalwart and James
    # use 400 (Bad Request); Cyrus uses 413 (Payload Too Large). Both
    # are RFC-conformant; the universal client-library contract is
    # ``status`` projects to ``Opt.some`` of a 4xx integer.
    doAssert re.status.isSome,
      "RFC 7807 §3.1 mandates a status field on the problem-details shape"
    let statusCode = re.status.unsafeGet
    doAssert statusCode >= 400 and statusCode < 500,
      "request-level limit rejection must surface as a 4xx HTTP status; got " &
        $statusCode
    # ``detail`` is RFC 7807 §3.1 optional. Stalwart, James, and Cyrus
    # all populate it for this rejection, but the universal contract
    # is non-empty when present.
    for d in re.detail:
      doAssert d.len > 0,
        "when detail is provided, it must be a non-empty human-readable string"
    doAssert re.limit.isSome and re.limit.unsafeGet == "maxSizeRequest",
      "RFC 8620 §3.6.1 mandates the breached limit name; got " & $re.limit
