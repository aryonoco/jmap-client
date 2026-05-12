# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured server-side enforcement
## of an over-cap ``ids`` array on ``Mailbox/get`` (``tests/testdata/
## captured/server-enforcement-max-objects-in-get-stalwart.json``).
##
## **Stalwart 0.15.5 empirical pin.**  The natural classification
## per RFC 8620 §3.6.1 would be a per-method ``invalidArguments``
## or RFC 8620 §3.6.1 request-layer ``limit`` with
## ``limit: "maxObjectsInGet"``.  Stalwart instead surfaces the
## error at the request layer with ``limit: "maxSizeRequest"``,
## indicating its enforcement classifier collapses adjacent caps
## onto the size-request rail.  The library's projection still
## works correctly — rawType losslessly preserved, errorType
## derived consistently.

{.push raises: [].}

import jmap_client
import ./mloader
import ../../mtestblock

testCase tcapturedServerEnforcementMaxObjectsInGet:
  forEachCapturedServer("server-enforcement-max-objects-in-get", j):
    let re = RequestError.fromJson(j).expect("RequestError.fromJson")
    doAssert re.rawType == "urn:ietf:params:jmap:error:limit",
      "Stalwart returns canonical 'limit' URI; got " & re.rawType
    doAssert re.errorType == retLimit,
      "errorType must project to retLimit, got " & $re.errorType
    doAssert re.errorType == parseRequestErrorType(re.rawType),
      "errorType / rawType must be derived consistently"
    # ``status`` mandated by RFC 7807 §3.1; the specific 4xx code is
    # server-discretionary. Stalwart and James use 400; Cyrus uses 413
    # for size-class limit rejections — both conformant.
    doAssert re.status.isSome,
      "RFC 7807 §3.1 mandates a status field on the problem-details shape"
    let statusCode = re.status.unsafeGet
    doAssert statusCode >= 400 and statusCode < 500,
      "request-layer limit rejection must surface as a 4xx HTTP status; got " &
        $statusCode
    doAssert re.limit.isSome, "RFC 8620 §3.6.1: limit field must name the breached cap"
