# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Identity/changes`` bogus-
## ``sinceState`` method-level error (RFC 8620 §5.2 / §5.5,
## ``tests/testdata/captured/identity-changes-bogus-state-stalwart.json``).
## Identity carries the ``urn:ietf:params:jmap:submission`` capability
## per ``mail/mail_entities.nim``; the response shape on bogus
## ``sinceState`` is the same RFC 8620 §5.5 method error projected as
## ``cannotCalculateChanges`` or ``invalidArguments``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedIdentityChangesBogus:
  let j = loadCapturedFixture("identity-changes-bogus-state-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "error",
    "method-level errors arrive under the literal rawName 'error'"
  let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
  doAssert me.errorType in {metCannotCalculateChanges, metInvalidArguments},
    "errorType must project as one of cannotCalculateChanges / invalidArguments " &
      "(got " & $me.errorType & ", rawType=" & me.rawType & ")"
