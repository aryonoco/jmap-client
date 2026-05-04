# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured request-level rejection
## Stalwart returns when ``using`` carries a capability URI the
## server does not advertise (``tests/testdata/captured/
## request-error-unknown-capability-stalwart.json``).
##
## **Stalwart 0.15.5 deviation pin.**  RFC 8620 §3.6.1 mandates
## ``urn:ietf:params:jmap:error:unknownCapability`` for this case.
## Stalwart collapses it onto ``urn:ietf:params:jmap:error:notRequest``
## along with other malformed-Request scenarios.  This fixture is the
## durable record; recapture via ``JMAP_TEST_CAPTURE_FORCE=1`` if a
## future Stalwart fixes the deviation.  The detail field still names
## the offending URI, so a library / human can extract it from the
## raw response.

{.push raises: [].}

import std/strutils

import jmap_client
import ./mloader

block tcapturedRequestErrorUnknownCapability:
  let j = loadCapturedFixture("request-error-unknown-capability-stalwart")
  let re = RequestError.fromJson(j).expect("RequestError.fromJson")
  doAssert re.rawType == "urn:ietf:params:jmap:error:notRequest",
    "Stalwart 0.15.5 returns notRequest for unknown capability URI " &
      "(RFC mandates unknownCapability); got " & re.rawType
  doAssert re.errorType == retNotRequest,
    "errorType must match parseRequestErrorType(rawType); got " & $re.errorType
  doAssert re.errorType == parseRequestErrorType(re.rawType),
    "errorType / rawType must be derived consistently"
  doAssert re.status.isSome and re.status.unsafeGet == 400,
    "Stalwart pins the HTTP status field to 400"
  doAssert re.detail.isSome, "Stalwart populates the RFC 7807 detail field"
  doAssert "urn:test:phase-j:bogus" in re.detail.unsafeGet,
    "Stalwart's detail message must echo the offending capability URI; got " &
      re.detail.unsafeGet
