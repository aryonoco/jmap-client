# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured cross-account ``Email/get``
## rejection (RFC 8620 §3.6.2,
## ``tests/testdata/captured/email-get-cross-account-rejected-stalwart.json``).
## Stalwart 0.15.5 elects ``forbidden`` rather than ``accountNotFound``
## for this rail — the account exists but the caller has no read
## permission on it without sharing/ACL. ``MethodError.fromJson`` must
## project the ``forbidden`` rawType onto ``metForbidden`` and round-trip
## the rawType losslessly.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailGetCrossAccountRejected:
  let j = loadCapturedFixture("email-get-cross-account-rejected-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error", "expected 'error' invocation, got " & inv.rawName

  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType == metForbidden,
    "Stalwart 0.15.5 cross-account rejection must project as metForbidden " & "(got " &
      $me.errorType & ", rawType=" & me.rawType & ")"
  doAssert me.rawType == "forbidden", "rawType must round-trip the wire literal"
