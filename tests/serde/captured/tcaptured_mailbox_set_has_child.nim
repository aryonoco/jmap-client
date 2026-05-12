# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/set`` destroy-
## with-surviving-child error (RFC 8621 §2.5,
## ``tests/testdata/captured/mailbox-set-has-child-stalwart.json``).
## The ``notDestroyed`` map carries one ``SetError`` whose
## ``errorType`` projects as ``setMailboxHasChild``.

{.push raises: [].}

import std/json
import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedMailboxSetHasChild:
  let j = loadCapturedFixture("mailbox-set-has-child-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Mailbox/set", "expected Mailbox/set, got " & inv.rawName

  let notDestroyedNode = inv.arguments{"notDestroyed"}
  doAssert not notDestroyedNode.isNil and notDestroyedNode.kind == JObject,
    "notDestroyed must be a JObject when destroy was rejected"
  doAssert notDestroyedNode.len == 1,
    "exactly one destroy outcome expected (got " & $notDestroyedNode.len & ")"
  for id, errNode in notDestroyedNode.pairs:
    let setErr = SetError.fromJson(errNode).expect("SetError.fromJson")
    doAssert setErr.errorType == setMailboxHasChild,
      "errorType must project as setMailboxHasChild (got " & $setErr.errorType &
        ", rawType=" & setErr.rawType & ")"
    doAssert setErr.rawType == "mailboxHasChild",
      "rawType must round-trip the wire literal"
