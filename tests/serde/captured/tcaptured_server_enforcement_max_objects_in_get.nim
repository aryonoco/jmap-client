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

block tcapturedServerEnforcementMaxObjectsInGet:
  let j = loadCapturedFixture("server-enforcement-max-objects-in-get-stalwart")
  let re = RequestError.fromJson(j).expect("RequestError.fromJson")
  doAssert re.rawType == "urn:ietf:params:jmap:error:limit",
    "Stalwart returns canonical 'limit' URI; got " & re.rawType
  doAssert re.errorType == retLimit,
    "errorType must project to retLimit, got " & $re.errorType
  doAssert re.errorType == parseRequestErrorType(re.rawType),
    "errorType / rawType must be derived consistently"
  doAssert re.status.isSome and re.status.unsafeGet == 400,
    "Stalwart pins HTTP 400 on the request-layer limit rail"
  doAssert re.limit.isSome,
    "Stalwart populates the limit field on the request-layer rail"
