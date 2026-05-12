# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/changes`` bogus-
## ``sinceState`` method-level error (RFC 8620 §5.2 / §5.5,
## ``tests/testdata/captured/mailbox-changes-bogus-state-stalwart.json``).
## RFC 8620 §5.5 permits the server to project the failure as either
## ``cannotCalculateChanges`` or ``invalidArguments``; Stalwart 0.15.5
## currently picks ``invalidArguments``. The assertion uses set-
## membership so a future Stalwart upgrade onto either RFC-compliant
## variant continues to pass.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedMailboxChangesBogus:
  forEachCapturedServer("mailbox-changes-bogus-state", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "error",
      "method-level errors arrive under the literal rawName 'error'"
    let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
    doAssert me.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "errorType must project as one of cannotCalculateChanges / invalidArguments " &
        "(got " & $me.errorType & ", rawType=" & me.rawType & ")"
