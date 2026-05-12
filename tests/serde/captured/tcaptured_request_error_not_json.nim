# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured request-level rejection
## Stalwart returns when sent a non-JSON body
## (``tests/testdata/captured/request-error-not-json-stalwart.json``).
##
## **Stalwart 0.15.5 deviation pin.**  RFC 8620 §3.6.1 mandates
## ``urn:ietf:params:jmap:error:notJSON`` for "the request did not
## parse as I-JSON".  Stalwart instead returns
## ``urn:ietf:params:jmap:error:notRequest`` for non-JSON input.  This
## fixture is the durable record of the deviation; the assertions
## below pin Stalwart's empirical choice byte-for-byte.  A future
## Stalwart upgrade that fixes the deviation will require recapture
## via ``JMAP_TEST_CAPTURE_FORCE=1``.

{.push raises: [].}

import jmap_client
import ./mloader
import ../../mtestblock

testCase tcapturedRequestErrorNotJson:
  let j = loadCapturedFixture("request-error-not-json-stalwart")
  let re = RequestError.fromJson(j).expect("RequestError.fromJson")
  doAssert re.rawType == "urn:ietf:params:jmap:error:notRequest",
    "Stalwart 0.15.5 returns notRequest for non-JSON input (RFC mandates notJSON); " &
      "got " & re.rawType
  doAssert re.errorType == retNotRequest,
    "errorType must match parseRequestErrorType(rawType); got " & $re.errorType
  doAssert re.errorType == parseRequestErrorType(re.rawType),
    "errorType / rawType must be derived consistently"
  doAssert re.status.isSome and re.status.unsafeGet == 400,
    "Stalwart pins the HTTP status field to 400"
  doAssert re.detail.isSome, "Stalwart populates the RFC 7807 detail field"
