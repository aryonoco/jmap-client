# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response from
## bob's account after alice→bob delivery (RFC 8621 §4.2,
## ``tests/testdata/captured/bob-inbox-after-alice-delivery-stalwart.json``).
## First captured fixture authored against bob's accountId rather than
## alice's. Asserts the delivery post-condition the Phase F EmailSubmission
## tests left implicit: the entity that arrives in bob's inbox has alice's
## ``from`` and resides in a mailbox keyed by bob's account.

{.push raises: [].}

import std/sets

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedBobInboxAfterDelivery:
  forEachCapturedServer("bob-inbox-after-alice-delivery", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get", "expected Email/get, got " & inv.rawName

    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1,
      "exactly one delivered email expected (got " & $getResp.list.len & ")"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.subject.isSome and email.subject.unsafeGet.len > 0,
      "captured delivery must surface a non-empty subject"
    doAssert email.fromAddr.isSome and email.fromAddr.unsafeGet.len > 0,
      "captured delivery must include a non-empty from list"
    doAssert email.fromAddr.unsafeGet[0].email == "alice@example.com",
      "delivered from[0].email must be alice@example.com (got " &
        email.fromAddr.unsafeGet[0].email & ")"
    doAssert email.mailboxIds.isSome, "captured delivery must include mailboxIds"
    doAssert HashSet[Id](email.mailboxIds.unsafeGet).len >= 1,
      "delivered email must reside in at least one mailbox"
