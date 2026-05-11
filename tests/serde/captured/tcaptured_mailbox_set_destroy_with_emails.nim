# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/set destroy``
## with ``onDestroyRemoveEmails: true`` response (RFC 8621 §2.5,
## ``tests/testdata/captured/mailbox-set-destroy-with-emails-stalwart.json``).
## A single invocation carries the typed
## ``SetResponse[MailboxCreatedItem]`` with one successful destroy.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMailboxSetDestroyWithEmails:
  forEachCapturedServer("mailbox-set-destroy-with-emails", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Mailbox/set", "expected Mailbox/set, got " & inv.rawName
    let setResp = SetResponse[MailboxCreatedItem].fromJson(inv.arguments).expect(
        "SetResponse[MailboxCreatedItem].fromJson"
      )
    doAssert setResp.destroyResults.len == 1,
      "exactly one destroy outcome expected (got " & $setResp.destroyResults.len & ")"
    for id, outcome in setResp.destroyResults.pairs:
      doAssert outcome.isOk,
        "destroy with onDestroyRemoveEmails must succeed (got rawType=" &
          outcome.error.rawType & ")"
      doAssert string(id).len > 0, "destroyed id must be non-empty"
    doAssert setResp.newState.isSome, "newState must be present in this fixture"
